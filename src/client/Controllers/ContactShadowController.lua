--!strict
-- One registry/sampler. A missing verified footprint never becomes a guessed disc.
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Collection = game:GetService("CollectionService")
local C = require(RS.Shared.Config.PlaytestExact).Shadow
local Assets = require(RS.Shared.Config.PlaytestAssets)
local Geometry = require(RS.Shared.Config.CartGeometry)
local Measurements = require(RS.Shared.Config.PlaytestMeasurements)
local Controller = {}
local records, connections = {}, {}
local folder, stepConnection
local selected, roundRobin = {}, 0
local diagnostics = { casts = 0, maximumCastsPerFrame = 0, visible = 0, blockedFootprints = 0 }
local function destroy(record)
	if record.plane then
		record.plane:Destroy()
	end
	for _, connection in ipairs(record.connections) do
		connection:Disconnect()
	end
	records[record.model] = nil
end
local function register(model, cart)
	if not model:IsA("Model") or records[model] then
		return
	end
	local record = {
		model = model,
		cart = cart,
		connections = {},
		sampleAt = -math.huge,
		id = tostring(model:GetAttribute("ItemId") or model:GetAttribute("OwnerUserId") or model.Name),
	}
	records[model] = record
	-- Explicit model membership from the cart registry / brainrot discovery tag.
	local function part(x)
		if x:IsA("BasePart") then
			x.CastShadow = false
		end
	end
	for _, x in ipairs(model:GetDescendants()) do
		part(x)
	end
	table.insert(record.connections, model.DescendantAdded:Connect(part))
	table.insert(
		record.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				destroy(record)
			end
		end)
	)
end
local function footprint(record)
	local model = record.model
	if record.front then
		local b = require(game:GetService("ReplicatedStorage").Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(model, Measurements.Species[model:GetAttribute("CosmeticSpeciesId")])
		return b and b.normalizedSize, b and b.groundPoint
	end
	if record.cart then
		local id = model:GetAttribute("CartId")
		local profile = Geometry[id]
		local measured = Measurements.Carts[id]
		if not profile or not measured or measured.verifiedFootprint ~= true then
			return nil
		end
		local lo, hi =
			model:GetAttribute("CargoPresentationBoundsMin"), model:GetAttribute("CargoPresentationBoundsMax")
		if typeof(lo) == "Vector3" and typeof(hi) == "Vector3" then
			local baseLo = profile.VisualBounds.Frame.Position - profile.VisualBounds.Size / 2
			local baseHi = profile.VisualBounds.Frame.Position + profile.VisualBounds.Size / 2
			lo = lo:Min(baseLo)
			hi = hi:Max(baseHi)
			return hi - lo, Vector3.new((lo.X + hi.X) / 2, profile.Ground.BottomY, (lo.Z + hi.Z) / 2)
		end
		return profile.VisualBounds.Size, Vector3.new(0, profile.Ground.BottomY, 0)
	end
	local state = model:GetAttribute("BrainrotDisplayState")
	if state == "Carried" or state == "Cart" then
		return nil
	end
	local metadata = require(game:GetService("ReplicatedStorage").Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(model, Measurements.Species[model:GetAttribute("BrainrotId")])
	if not metadata or metadata.verified ~= true then
		return nil
	end
	return metadata.normalizedSize, metadata.groundPoint
end
local function ensurePlane(record)
	if record.plane then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Contact_" .. record.id
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
	p.Parent = folder
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SoftContact"
	surface.Adornee = p
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(C.TextureSize, C.TextureSize)
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.Parent = p
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = Assets.ContactShadow
	image.ImageTransparency = 1
	image.Parent = surface
	record.plane, record.surface, record.image = p, surface, image
end
function Controller.Start()
	if stepConnection then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "ExactContactShadows"
	folder.Parent = workspace
	local carts = workspace:WaitForChild("Runtime"):WaitForChild("Carts")
	for _, x in ipairs(carts:GetChildren()) do
		register(x, true)
	end
	table.insert(
		connections,
		carts.ChildAdded:Connect(function(x)
			register(x, true)
		end)
	)
	for _, x in ipairs(Collection:GetTagged("BrainrotDisplay")) do
		if x:GetAttribute("CreatureProxy") ~= true then
			register(x, false)
		end
	end
	table.insert(
		connections,
		Collection:GetInstanceAddedSignal("BrainrotDisplay"):Connect(function(x)
			if x:GetAttribute("CreatureProxy") ~= true then
				register(x, false)
			end
		end)
	)
	local elapsed = 0
	stepConnection = Run.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		elapsed += dt
		if elapsed >= 1 / C.Hz then
			elapsed = 0
			local candidates = {}
			diagnostics.blockedFootprints = 0
			for _, record in pairs(records) do
				local root = record.model.PrimaryPart
				local size, ground = footprint(record)
				if record.surface then
					record.surface.Enabled = false
				end
				if root and size and ground then
					local distance = (root.Position - camera.CFrame.Position).Magnitude
					if distance <= C.Range then
						record.size, record.ground = size, ground
						record.distance = distance
						record.priority = if record.cart
								and record.model:GetAttribute("ActiveDriverUserId") == Players.LocalPlayer.UserId
							then 0
							elseif
								record.front
								and record.front:GetAttribute("ActiveDriverUserId") == Players.LocalPlayer.UserId
							then 1
							else 2
						table.insert(candidates, record)
					end
				else
					diagnostics.blockedFootprints += 1
				end
			end
			table.sort(candidates, function(a, b)
				return if a.priority ~= b.priority
					then a.priority < b.priority
					elseif a.distance ~= b.distance then a.distance < b.distance
					else a.id < b.id
			end)
			selected = {}
			for i = 1, math.min(C.Cap, #candidates) do
				selected[i] = candidates[i]
				ensurePlane(selected[i])
			end
		end

		-- Foot refinement is selected by cart distance, independently of the
		-- twelve visible-shadow slots. Both uses consume this one ray budget.
		local nearCarts, seen = {}, {}
		for _, r in records do
			local cart = r.front
			if
				cart
				and cart.PrimaryPart
				and not seen[cart]
				and (cart.PrimaryPart.Position - camera.CFrame.Position).Magnitude <= C.Range
			then
				seen[cart] = true
				table.insert(nearCarts, cart)
			end
		end
		table.sort(nearCarts, function(a, b)
			local da = (a.PrimaryPart.Position - camera.CFrame.Position).Magnitude
			local db = (b.PrimaryPart.Position - camera.CFrame.Position).Magnitude
			return if da ~= db
				then da < db
				else tostring(a:GetAttribute("OwnerUserId")) < tostring(b:GetAttribute("OwnerUserId"))
		end)
		local nearest = {}
		for i = 1, math.min(C.FrontRefinementCartCap, #nearCarts) do
			nearest[nearCarts[i]] = true
		end
		local samplePool, admitted = {}, {}
		for _, r in selected do
			if not r.front or nearest[r.front] then
				table.insert(samplePool, r)
				admitted[r] = true
			end
		end
		local extra = {}
		for _, r in records do
			if r.front and nearest[r.front] and not admitted[r] then
				table.insert(extra, r)
			end
		end
		table.sort(extra, function(a, b)
			return a.id < b.id
		end)
		for _, r in extra do
			table.insert(samplePool, r)
		end
		local casts = 0
		for _ = 1, #samplePool do
			roundRobin = roundRobin % math.max(#samplePool, 1) + 1
			local record = samplePool[roundRobin]
			if now - record.sampleAt >= 1 / C.Hz and record.model.PrimaryPart then
				local point = if record.front and record.front.PrimaryPart
					then record.front.PrimaryPart.CFrame:PointToWorldSpace(record.localGround)
					else record.model:GetPivot():PointToWorldSpace(record.ground)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { workspace.MapBlockout, workspace.Terrain }
				params.RespectCanCollide = true
				local hit = workspace:Raycast(point + Vector3.yAxis * C.RayUp, -Vector3.yAxis * C.RayDown, params)
				record.hit = if hit and hit.Normal:Dot(Vector3.yAxis) >= C.NormalMinimum then hit else nil
				record.sampleAt = now
				casts += 1
				diagnostics.casts += 1
				if casts >= C.CastsPerFrame then
					break
				end
			end
		end
		diagnostics.maximumCastsPerFrame = math.max(diagnostics.maximumCastsPerFrame, casts)
		diagnostics.visible = 0
		for _, record in ipairs(selected) do
			local root = record.model.PrimaryPart
			local hit = record.hit
			local visible = root and hit and now - record.sampleAt <= C.MaxSampleAge
			if visible then
				local point = record.model:GetPivot():PointToWorldSpace(record.ground)
				local normal = hit.Normal
				local h = math.max(0, (point - hit.Position):Dot(normal))
				visible = h < C.FadeHeight
				if visible then
					local forward = root.CFrame.LookVector
					forward -= normal * forward:Dot(normal)
					if forward.Magnitude < C.ProjectionMinimum then
						forward = -Vector3.zAxis
						forward -= normal * forward:Dot(normal)
					end
					if forward.Magnitude < C.ProjectionMinimum then
						forward = Vector3.xAxis
						forward -= normal * forward:Dot(normal)
					end
					forward = forward.Unit
					record.plane.Size = Vector3.new(
						record.size.X * C.FootprintMultiplier,
						C.Offset,
						record.size.Z * C.FootprintMultiplier
					)
					record.plane.CFrame = CFrame.fromMatrix(
						point - normal * ((point - hit.Position):Dot(normal)) + normal * (C.Offset - C.Offset / 2),
						forward:Cross(normal),
						normal,
						-forward
					)
					record.image.ImageTransparency = 1 - math.clamp(1 - h / C.FadeHeight, 0, 1)
					diagnostics.visible += 1
				end
			end
			record.surface.Enabled = visible == true
		end
	end)
end
function Controller.RegisterFront(model, cart, localGround)
	register(model, false)
	local r = records[model]
	r.front = cart
	r.id = tostring(model:GetAttribute("PresentationTargetId") or model:GetAttribute("CosmeticIndividualId") or r.id)
	r.localGround = localGround
end
function Controller.RemoveFront(model)
	local r = records[model]
	if r then
		destroy(r)
	end
end
function Controller.FrontSupport(model, fallback, cart)
	local grounded, normal = require(script.Parent.CartMovementController).GetPresentationSupport(cart)
	if grounded == false then
		return fallback
	end
	local r = records[model]
	if not r or not r.hit or os.clock() - r.sampleAt > C.MaxSampleAge then
		if normal then
			local forward = fallback.LookVector - normal * fallback.LookVector:Dot(normal)
			if forward.Magnitude >= C.ProjectionMinimum then
				return CFrame.lookAt(fallback.Position, fallback.Position + forward.Unit, normal)
			end
		end
		return fallback
	end
	local root = cart.PrimaryPart
	if not root then
		return fallback
	end
	if grounded == nil and math.abs(root.AssemblyLinearVelocity.Y) > C.FadeHeight then
		return fallback
	end
	normal = r.hit.Normal
	local point = fallback.Position
	local projection = point - normal * (point - r.hit.Position):Dot(normal)
	local forward = fallback.LookVector - normal * fallback.LookVector:Dot(normal)
	if forward.Magnitude < C.ProjectionMinimum then
		return fallback
	end
	return CFrame.lookAt(projection, projection + forward.Unit, normal)
end

function Controller.GetDiagnostics()
	return table.clone(diagnostics)
end
function Controller.Stop()
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	local old = {}
	for _, record in pairs(records) do
		table.insert(old, record)
	end
	for _, record in ipairs(old) do
		destroy(record)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end
return Controller
