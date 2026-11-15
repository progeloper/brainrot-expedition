--!strict
-- Two native trails per selected live cart. One 10Hz scheduler; no wheel dependency.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Geometry = require(RS.Shared.Utility.CartGeometry)
local Factory = require(RS.Shared.Utility.Phase14TrailFactory)
local ResolvedQuality = require(RS.Shared.Utility.ResolvedPresentationQuality)
local Visibility = require(script.Parent.RegionVisibilityController)
local player = Players.LocalPlayer
local Controller = {}
local started = false
local connections = {}
local records = {}
local elapsed = 0
local function release(cart)
	local r = records[cart]
	if r then
		r.Handle:Destroy()
		records[cart] = nil
	end
end
-- Read the existing presenter's resolved tier, including Auto downshifts.
-- Raw Low wins immediately while that publisher processes a preference change.
function Controller.AllowsEffects(preference, reducedMotion)
	return reducedMotion ~= true
		and preference ~= "Low"
		and ResolvedQuality.GetTier(preference) ~= "Low"
end
local function allowedEffects()
	return Controller.AllowsEffects(
		player:GetAttribute("VFXQuality"),
		player:GetAttribute("ReducedMotion")
	)
end
local function cartFolder()
	local r = workspace:FindFirstChild("Runtime")
	return r and r:FindFirstChild("Carts")
end
local function step(dt, folder, position, effects, visible)
	for cart, r in records do
		if
			not folder
			or cart.Parent ~= folder
			or cart.PrimaryPart ~= r.Root
			or not r.Root.Parent
			or cart:GetAttribute("P14TrailId") ~= r.Id
			or cart:GetAttribute("OwnerUserId") ~= r.Owner
			or cart:GetAttribute("CartGeneration") ~= r.Generation
			or cart:GetAttribute("CartGeometryId") ~= r.GeometryId
			or cart:GetAttribute("CartGeometryRevision") ~= r.GeometryRevision
			or not Factory.HasCurrentBinding(cart)
			or cart:GetAttribute("ResetActive") == true
			or cart:GetAttribute("CartResetActive") == true
			or cart:GetAttribute("ResetStartedAt") ~= r.ResetStartedAt
			or cart:GetAttribute("ResetCompletedAt") ~= r.ResetCompletedAt
			or not position
			or (position - r.Root.Position).Magnitude > 100
			or not effects
		then
			release(cart)
		end
	end
	if not folder or not position or not effects then
		return
	end
	for _, cart in folder:GetChildren() do
		if not cart:IsA("Model") or not cart.PrimaryPart then
			continue
		end
		local root = cart.PrimaryPart
		local id = cart:GetAttribute("P14TrailId")
		local distance = (root.Position - position).Magnitude
		local r = records[cart]
		if
			not r
			and distance <= 80
			and Factory.Presets[id]
			and Factory.HasCurrentBinding(cart)
			and visible(cart)
			and cart:GetAttribute("ResetActive") ~= true
			and cart:GetAttribute("CartResetActive") ~= true
		then
			local profile = Geometry.Get(cart)
			if profile then
				local left, right = Factory.MountFrames(profile)
				local handle = left and right and Factory.Create(id, root, left, right)
				if handle then
					r = {
						Root = root,
						Id = id,
						Owner = cart:GetAttribute("OwnerUserId"),
						Generation = cart:GetAttribute("CartGeneration"),
						GeometryId = cart:GetAttribute("CartGeometryId"),
						GeometryRevision = cart:GetAttribute("CartGeometryRevision"),
						Handle = handle,
						Position = root.Position,
						ResetStartedAt = cart:GetAttribute("ResetStartedAt"),
						ResetCompletedAt = cart:GetAttribute("ResetCompletedAt"),
					}
					records[cart] = r
				end
			end
		end
		if r then
			local speed = Vector3.new(
				root.AssemblyLinearVelocity.X,
				0,
				root.AssemblyLinearVelocity.Z
			).Magnitude
			local moved = (root.Position - r.Position).Magnitude
			local continuous = moved <= math.max(24, speed * dt + 8)
				and cart:GetAttribute("OwnerUserId") == r.Owner
			if not continuous then
				r.Handle:Clear()
			end
			r.Handle:Update(speed, continuous and visible(cart))
			r.Position = root.Position
		end
	end
end
function Controller.Step(dt)
	local ch = player.Character
	local origin = ch and ch:FindFirstChild("HumanoidRootPart")
	step(
		dt,
		cartFolder(),
		if origin then origin.Position else nil,
		allowedEffects(),
		Visibility.IsVisible
	)
end
-- Native Instance fixtures exercise the actual shared scheduler without a real
-- player or a second Heartbeat. Never callable while the live controller runs.
function Controller._StepForTesting(dt, folder, position, effects, visible)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture required")
	step(dt, folder, position, effects, visible)
end
function Controller.GetDiagnostics()
	local carts, trails = 0, 0
	for _, r in records do
		carts += 1
		trails += #r.Handle.Trails
	end
	return {
		started = started,
		connections = #connections,
		carts = carts,
		trails = trails,
		schedulerHz = 10,
	}
end
function Controller.Start()
	if started then
		return false
	end
	started = true
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then
				return
			end
			local interval = elapsed
			elapsed = 0
			debug.profilebegin("P14.CosmeticTrails")
			Controller.Step(interval)
			debug.profileend()
		end)
	)
	for _, name in { "ReducedMotion", "VFXQuality" } do
		table.insert(
			connections,
			player:GetAttributeChangedSignal(name):Connect(function()
				Controller.Step(0)
			end)
		)
	end
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			for cart in records do
				release(cart)
			end
		end)
	)
	return true
end
function Controller.Stop()
	started = false
	elapsed = 0
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for cart in records do
		release(cart)
	end
end
return Controller
