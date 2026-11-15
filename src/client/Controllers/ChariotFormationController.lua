--!nocheck
-- Sole front-team owner. Complete cosmetic copies never join the physical cart.
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Collection = game:GetService("CollectionService")
local Templates = require(RS.Shared.Utility.CreatureTemplateProvider)
local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
local G = require(RS.Shared.Utility.WorldPresentationGeometry)
local C = require(RS.Shared.Config.PlaytestExact)
local Visibility = require(script.Parent.RegionVisibilityController)
local Ground = require(script.Parent.ContactShadowController)
local SeatState = require(RS.Shared.Utility.HumanoidSeatState)
local Controller = {}
local carts = {}
local connections = {}
local folder
local frameConnection
local templateVersion = -1
local generations = {}
local metrics = { updates = 0, queries = 0, terrain = 0, parts = 0, registrations = 0 }
function Controller.IsLocallyOccupied(h, cart)
	return h ~= nil
		and SeatState.IsSeated(h)
		and h.SeatPart ~= nil
		and h.SeatPart:IsDescendantOf(cart)
end
local function release(s)
	for key, v in pairs(s.visuals) do
		generations[key] = (generations[key] or 0) + 1
		Ground.RemoveFront(v.model)
		if v.anchor then
			v.anchor:Destroy()
		end
		v.model:Destroy()
	end
	table.clear(s.visuals)
	for _, p in s.traces do
		p:Destroy()
	end
	table.clear(s.traces)
end
local function remove(cart)
	local s = carts[cart]
	if not s then
		return
	end
	release(s)
	for _, c in s.connections do
		c:Disconnect()
	end
	carts[cart] = nil
end
local function descriptor(cart)
	local encoded = cart:GetAttribute("ChariotTeamPublic")
	if type(encoded) ~= "string" or #encoded > 6000 then
		return nil
	end
	local ok, d = pcall(Http.JSONDecode, Http, encoded)
	if
		not ok
		or type(d) ~= "table"
		or type(d.entries) ~= "table"
		or #d.entries > 6
		or d.generation ~= cart:GetAttribute("CartGeneration")
		or d.ownerUserId ~= cart:GetAttribute("OwnerUserId")
	then
		return nil
	end
	return d
end
local function clone(e, key, revision)
	local source = Templates.Get(e.speciesId, "Full")
	if not source then
		return nil
	end
	local m = source:Clone()
	m.Name = "Front_" .. tostring(e.slot)
	-- Voxel V4 templates carry only presentation attributes (roles/protection/studs).
	local voxel = source:GetAttribute("VoxelCreatureVersion") == 4
	for _, v in { m, table.unpack(m:GetDescendants()) } do
		for _, tag in Collection:GetTags(v) do
			Collection:RemoveTag(v, tag)
		end
		for a in v:GetAttributes() do
			if not voxel then
				v:SetAttribute(a, nil)
			end
		end
		if
			v:IsA("LuaSourceContainer")
			or v:IsA("ProximityPrompt")
			or v:IsA("ClickDetector")
			or v:IsA("BodyMover")
			or v:IsA("ParticleEmitter")
			or v:IsA("Sound")
			or v:IsA("Light")
		then
			v:Destroy()
		end
	end
	require(RS.Shared.Utility.WorldStudPolicy).ApplyModel(m, "Creature")
	m:SetAttribute("BrainrotId", e.speciesId)
	assert(Scale.ApplyCanonicalScale(m, "FrontTeam"), "Front normalization failed")
	m:SetAttribute("BrainrotId", nil)
	local root = assert(
		m.PrimaryPart
			or m:FindFirstChild("HiddenRoot")
			or m:FindFirstChildWhichIsA("BasePart", true),
		"Front template has no root"
	)
	m.PrimaryPart = root
	-- Preserve existing animated joints; connect only disconnected rigid assemblies.
	local connected = { [root] = true }
	for _, v in m:GetDescendants() do
		if v:IsA("JointInstance") or v:IsA("WeldConstraint") then
			if v.Part0 and v.Part1 then
				connected[v.Part1] = true
			end
		end
	end
	for _, v in m:GetDescendants() do
		if v:IsA("BasePart") then
			v.Anchored = v == root
			v.CanCollide = false
			v.CanTouch = false
			v.CanQuery = false
			v.Massless = true
			v.CastShadow = false
			if v ~= root and not connected[v] then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "CosmeticRigidJoint"
				weld.Part0 = root
				weld.Part1 = v
				weld.Parent = root
			end
		end
	end
	generations[key] = (generations[key] or 0) + 1
	m:SetAttribute("CosmeticIndividualId", e.individualId)
	m:SetAttribute("CosmeticSpeciesId", e.speciesId)
	m:SetAttribute("CosmeticMutationId", e.mutationId or "None")
	m:SetAttribute("Phase12PresentationState", "Equipped")
	m:SetAttribute("PresentationRole", "FrontTeam")
	m:SetAttribute("PreserveAuthoredBodyColours", true)
	m:SetAttribute("PresentationTargetId", key)
	m:SetAttribute("PresentationRevision", revision)
	m:SetAttribute("BindGeneration", generations[key])
	m.Parent = folder
	Collection:AddTag(m, "FrontTeamCosmetic")
	return m
end
local function reconcile(s, d)
	local geometry = G.Cart(s.cart:GetAttribute("CartId"))
	if not geometry then
		return
	end
	local keep = {}
	local allReady = true
	for _, e in ipairs(d.entries) do
		local key = tostring(d.ownerUserId)
			.. ":"
			.. tostring(d.generation)
			.. ":"
			.. tostring(e.slot)
			.. ":"
			.. e.individualId
			.. ":FrontTeam"
		keep[key] = true
		local prior = s.visuals[key]
		local template = Templates.Get(e.speciesId, "Full")
		if prior and prior.template ~= template then
			generations[key] = (generations[key] or 0) + 1
			Ground.RemoveFront(prior.model)
			if prior.anchor then
				prior.anchor:Destroy()
			end
			prior.model:Destroy()
			s.visuals[key] = nil
		end
		if not s.visuals[key] then
			local m = clone(e, key, d.revision)
			if m then
				s.visuals[key] = { model = m, entry = e, key = key, template = template }
			else
				allReady = false
			end
		end
	end
	for key, v in s.visuals do
		if not keep[key] then
			generations[key] = (generations[key] or 0) + 1
			Ground.RemoveFront(v.model)
			if v.anchor then
				v.anchor:Destroy()
			end
			v.model:Destroy()
			s.visuals[key] = nil
		end
	end
	for key, p in s.traces do
		if not keep[key] then
			p:Destroy()
			s.traces[key] = nil
		end
	end
	local nose = geometry.VisualBounds.Frame.Z - geometry.VisualBounds.Size.Z / 2
	s.geometry = geometry
	s.nose = nose
	local poses, lo, hi = G.Layout(d.entries, 2, true, nose, geometry.Ground.BottomY)
	local route = require(RS.Shared.Config.PlaytestPresentationMetadata).Route
	local columns = 2
	if
		#poses > 0
		and 2
					* math.max(math.abs(lo.X), math.abs(hi.X), geometry.VisualBounds.Size.X / 2)
				+ 2 * C.Cargo.RequiredRouteSideClearanceStuds
			> route.MinimumStraightClearWidth
	then
		columns = 1
		poses, lo, hi = G.Layout(d.entries, 1, true, nose, geometry.Ground.BottomY)
	end
	for i, e in ipairs(d.entries) do
		for _, v in s.visuals do
			if v.entry.individualId == e.individualId and v.entry.slot == e.slot then
				v.pose = poses[i]
				if not v.anchor then
					v.anchor = Instance.new("Attachment")
					v.anchor.Name = "FrontVisualAnchor_" .. tostring(e.slot)
					v.anchor.Parent = s.cart.PrimaryPart
				end
				v.anchor.CFrame = poses[i].support
				v.model:SetAttribute("Formation", if columns == 2 then "A" else "B")
				Ground.RegisterFront(v.model, s.cart, poses[i].ground)
			end
		end
	end
	s.cart:SetAttribute("FrontPresentationBoundsMin", if #poses > 0 then lo else nil)
	s.cart:SetAttribute("FrontPresentationBoundsMax", if #poses > 0 then hi else nil)
	s.revision = d.revision
	s.ready = allReady
	s.descriptor = d
end
local function register(cart)
	if carts[cart] or not cart:IsA("Model") or not cart:GetAttribute("RuntimeCart") then
		return
	end
	local s =
		{ cart = cart, visuals = {}, traces = {}, connections = {}, revision = -1, dirty = true }
	carts[cart] = s
	table.insert(
		s.connections,
		cart:GetAttributeChangedSignal("ChariotTeamPublic"):Connect(function()
			s.dirty = true
		end)
	)
	table.insert(
		s.connections,
		cart.Destroying:Connect(function()
			remove(cart)
		end)
	)
end
function Controller.Start()
	if frameConnection then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "ChariotTeamPresentation"
	folder.Parent = workspace
	local runtime = workspace:WaitForChild("Runtime"):WaitForChild("Carts")
	for _, cart in runtime:GetChildren() do
		register(cart)
	end
	table.insert(connections, runtime.ChildAdded:Connect(register))
	frameConnection = Run.RenderStepped:Connect(function()
		metrics.updates += 1
		local changed = templateVersion ~= Templates.GetVersion()
		templateVersion = Templates.GetVersion()
		for cart, s in carts do
			if not cart.Parent then
				remove(cart)
				continue
			end
			local d = descriptor(cart)
			if not d then
				if next(s.visuals) then
					release(s)
				end
				continue
			end
			if not Visibility.IsVisible(cart) then
				if next(s.visuals) then
					release(s)
					s.ready = false
				end
				continue
			end
			if s.dirty or changed or not s.ready or s.revision ~= d.revision then
				reconcile(s, d)
				s.dirty = false
			end
			local root = cart.PrimaryPart
			if root then
				local envelopeLow = Vector3.one * math.huge
				local envelopeHigh = -envelopeLow
				local occupied = false
				for _, v in s.visuals do
					if v.pose then
						local support = root.CFrame * v.pose.support
						support = Ground.FrontSupport(v.model, support, cart)
						local target = G.GroundPivot(v.entry.speciesId, support)
						v.model:PivotTo(target)
						v.model:SetAttribute("ComputedVisualTarget", target)
						if
							v.entry.slot == s.descriptor.entries[1].slot
							or (
								s.descriptor.entries[2]
								and v.entry.slot == s.descriptor.entries[2].slot
							)
						then
							local hitch =
								require(RS.Shared.Config.PlaytestPresentationMetadata).FrontHitch
							local p = s.traces[v.key]
							if not p then
								p = Instance.new("Part")
								p.Name = "HarnessTrace"
								p.Anchored = true
								p.CanCollide = false
								p.CanTouch = false
								p.CanQuery = false
								p.Massless = true
								p.CastShadow = false
								p.Material = hitch.Material
								p.Color = hitch.Colour
								require(RS.Shared.Utility.WorldStudPolicy).Apply(p, nil, "Prop")
								p.Parent = folder
								s.traces[v.key] = p
							end
							local side = if v.pose.ground.X < 0 then -1 else 1
							local a = s.geometry.FormationAdapter
							local start = root.CFrame
								* Vector3.new(
									side * (a.x + a.width / 2 + hitch.EdgeOffset),
									a.supportY + v.pose.size.Y * hitch.BodyHeightFraction,
									s.nose
								)
							local finish = support
								* Vector3.new(
									0,
									v.pose.size.Y * hitch.BodyHeightFraction,
									v.pose.size.Z / 2
								)
							p.Size = Vector3.new(
								hitch.CrossSection,
								hitch.CrossSection,
								(finish - start).Magnitude
							)
							p.CFrame = CFrame.lookAt((start + finish) / 2, finish)
						end

						occupied = true
						for _, x in { -1, 1 } do
							for _, y in { 0, 1 } do
								for _, z in { -1, 1 } do
									local point = root.CFrame:PointToObjectSpace(
										support
											* Vector3.new(
												x * v.pose.size.X / 2,
												y * v.pose.size.Y + C.BodyGroundClearanceStuds,
												z * v.pose.size.Z / 2
											)
									)
									envelopeLow = envelopeLow:Min(point)
									envelopeHigh = envelopeHigh:Max(point)
								end
							end
						end
					end
				end
				if occupied then
					cart:SetAttribute("FrontPresentationBoundsMin", envelopeLow)
					cart:SetAttribute("FrontPresentationBoundsMax", envelopeHigh)
				end
			end
		end
	end)
end
function Controller.Destroy()
	if frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
	for cart in carts do
		remove(cart)
	end
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if folder then
		folder:Destroy()
		folder = nil
	end
end
function Controller.Diagnostics()
	local out = table.clone(metrics)
	out.models = 0
	out.parts = 0
	for _, s in carts do
		for _, v in s.visuals do
			out.models += 1
			for _, p in v.model:GetDescendants() do
				if p:IsA("BasePart") then
					out.parts += 1
				end
			end
		end
	end
	return out
end
return Controller
