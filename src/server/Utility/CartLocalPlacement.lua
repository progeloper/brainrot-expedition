--!strict
-- Bounded server placement proof for the existing cart and its seated core bodies.
-- WorldRoot overlap queries exclude Terrain; voxel occupancy is checked separately.
-- Casts do not detect initial overlaps, so they are never used as overlap proof.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config.CartLocalCorrection)
local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local Regions = require(ReplicatedStorage.Shared.Config.WorldProgression)
local TerrainProfiles = require(ReplicatedStorage.Shared.Utility.CartTerrainProfileResolver)
local CartGeometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)
local TerrainSampler = require(ReplicatedStorage.Shared.Utility.CartTerrainSampler)
local Placement = {}
local context: any = nil
local budget = { window = 0, world = 0, terrain = 0, worldTotal = 0, terrainTotal = 0, denied = 0, tags = {} }

local function take(kind: string, tag: string?): boolean
	local now = Workspace:GetServerTimeNow()
	if now < budget.window or now - budget.window >= 1 then
		budget.window, budget.world, budget.terrain = now, 0, 0
	end
	local limit = if kind == "world" then Config.MaximumWorldQueriesPerSecond else Config.MaximumTerrainQueriesPerSecond
	if budget[kind] >= limit then
		budget.denied += 1
		return false
	end
	budget[kind] += 1
	budget[kind .. "Total"] += 1
	local key = tag or "CartCorrection"
	local tagged = budget.tags[key] or { world = 0, terrain = 0 }
	budget.tags[key] = tagged
	tagged[kind] += 1
	return true
end

local function finiteFrame(frame: CFrame): boolean
	for _, n in { frame:GetComponents() } do
		if n ~= n or math.abs(n) == math.huge then
			return false
		end
	end
	return true
end

-- Oriented-box SAT refines the broad combined envelope around separated wheels,
-- seats and seated limbs without issuing a query for every broad false positive.
local function intersects(a: CFrame, as: Vector3, b: CFrame, bs: Vector3): boolean
	local aa = { a.RightVector, a.UpVector, a.LookVector }
	local ba = { b.RightVector, b.UpVector, b.LookVector }
	local ah, bh = { as.X / 2, as.Y / 2, as.Z / 2 }, { bs.X / 2, bs.Y / 2, bs.Z / 2 }
	local delta = b.Position - a.Position
	local axes = { aa[1], aa[2], aa[3], ba[1], ba[2], ba[3] }
	for _, av in aa do
		for _, bv in ba do
			table.insert(axes, av:Cross(bv))
		end
	end
	for _, axis in axes do
		if axis.Magnitude < 1e-5 then
			continue
		end
		local ar, br = 0, 0
		for i = 1, 3 do
			ar += ah[i] * math.abs(aa[i]:Dot(axis))
			br += bh[i] * math.abs(ba[i]:Dot(axis))
		end
		if math.abs(delta:Dot(axis)) > ar + br then
			return false
		end
	end
	return true
end

local function extend(minimum: Vector3, maximum: Vector3, frame: CFrame, size: Vector3): (Vector3, Vector3)
	for _, x in { -0.5, 0.5 } do
		for _, y in { -0.5, 0.5 } do
			for _, z in { -0.5, 0.5 } do
				local p = frame:PointToWorldSpace(size * Vector3.new(x, y, z))
				minimum = Vector3.new(math.min(minimum.X, p.X), math.min(minimum.Y, p.Y), math.min(minimum.Z, p.Z))
				maximum = Vector3.new(math.max(maximum.X, p.X), math.max(maximum.Y, p.Y), math.max(maximum.Z, p.Z))
			end
		end
	end
	return minimum, maximum
end

-- Reuse the same four explicit native plot surfaces as the live Shield
-- boundary. Ownership comes from PlayerBaseSystem, never a model's owner claim.
local BASE_DRIVING_SURFACES = table.freeze({ Foundation = true, CartDisplay = true, CartRamp = true, HouseRamp = true })
local function assignedBase(player: Player?): Model?
	if not player or not context or type(context.GetAssignedBase) ~= "function" then
		return nil
	end
	local base = context.GetAssignedBase(player)
	return if typeof(base) == "Instance" and base:IsA("Model") and base:IsDescendantOf(Workspace) then base else nil
end

local function baseDrivingSurface(base: Model?, part: Instance): boolean
	return base ~= nil
		and part:IsA("BasePart")
		and part.Parent == base
		and BASE_DRIVING_SURFACES[part.Name] == true
		and part.Anchored
		and part.CanCollide
end

local function baseContains(base: Model?, position: Vector3): boolean
	if not base then
		return false
	end
	for name in BASE_DRIVING_SURFACES do
		local part = base:FindFirstChild(name)
		if not part or not baseDrivingSurface(base, part) then
			continue
		end
		local point = (part :: BasePart).CFrame:PointToObjectSpace(position)
		local size = (part :: BasePart).Size / 2
		if math.abs(point.X) <= size.X and math.abs(point.Z) <= size.Z then
			return true
		end
	end
	return false
end

local function validateAssignedSpawnIdentity(cart: Model, frame: CFrame, assignment: any?): Model?
	if type(assignment) ~= "table" or type(assignment.CurrentBase) ~= "function" then
		return nil
	end
	local base, marker, player = assignment.Base, assignment.Marker, assignment.Player
	if
		typeof(base) ~= "Instance"
		or not base:IsA("Model")
		or not base:IsDescendantOf(Workspace)
		or typeof(marker) ~= "Instance"
		or not marker:IsA("BasePart")
		or marker.Parent ~= base
		or marker.Name ~= "CartSpawn"
		or not marker.Anchored
		or marker.CanCollide
		or marker.CanQuery
		or marker.CanTouch
		or not player
		or assignment.CurrentBase() ~= base
		or marker:GetAttribute("Enabled") ~= true
		or marker:GetAttribute("SpawnId") ~= cart:GetAttribute("SpawnId")
		or cart:GetAttribute("OwnerUserId") ~= player.UserId
		or frame ~= marker.CFrame * CartGeometry.SpawnOffset(cart)
	then
		return nil
	end
	return base
end

local function coreParts(character: Model): { BasePart }
	local parts = {}
	-- Direct children only: accessories, Tools, held catches and layered cosmetics
	-- cannot enlarge either the driver's height or the occupied collision envelope.
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(parts, part)
		end
	end
	return parts
end

function Placement.DriverBodyHeight(driver: Player): number?
	local character = driver.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return nil
	end
	local minimum, maximum = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in coreParts(character) do
		minimum, maximum = extend(minimum, maximum, root.CFrame:ToObjectSpace(part.CFrame), part.Size)
	end
	local height = maximum.Y - minimum.Y
	return if height == height and height > 0 and height < math.huge then height else nil
end

function Placement.Measure(cart: Model): any?
	local pivot = cart:GetPivot()
	if not finiteFrame(pivot) then
		return nil
	end
	local minimum, maximum = Vector3.one * math.huge, -Vector3.one * math.huge
	local shapes, ignored = {}, { cart }
	for _, part in cart:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.CanCollide
			and part.CollisionGroup ~= "CargoVisuals"
			and part.CollisionGroup ~= "FormationVisuals"
		then
			local frame = pivot:ToObjectSpace(part.CFrame)
			table.insert(shapes, { frame = frame, size = part.Size, part = part })
			minimum, maximum = extend(minimum, maximum, frame, part.Size)
		end
	end
	if #shapes == 0 then
		return nil
	end
	local supportMinimum, supportMaximum = minimum, maximum
	local geometry = CartGeometry.Get(cart)
	-- Actual seat occupants, not nearby/owned characters. Keep their proposed core
	-- bodies in the envelope while excluding their current positions as obstacles.
	for _, seat in cart:GetDescendants() do
		if not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
			continue
		end
		local humanoid = seat.Occupant
		local character = humanoid and humanoid.Parent
		if not character or not character:IsA("Model") or not Players:GetPlayerFromCharacter(character) then
			continue
		end
		table.insert(ignored, character)
		for _, part in coreParts(character) do
			local frame = pivot:ToObjectSpace(part.CFrame)
			table.insert(shapes, { frame = frame, size = part.Size, part = part })
			minimum, maximum = extend(minimum, maximum, frame, part.Size)
		end
	end
	local profileOk, profile = pcall(TerrainProfiles.ResolveForCart, cart)
	local ownerId = cart:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	return {
		assignedBase = assignedBase(owner),
		maximumSlope = if profileOk then profile.MaximumClimbAngleDegrees else 45,
		shapes = shapes,
		ignored = ignored,
		minimum = minimum,
		maximum = maximum,
		supportMinimum = supportMinimum,
		supportMaximum = supportMaximum,
		contactSamples = if geometry then geometry.Ground.ContactSamples else nil,
		pivot = pivot,
	}
end

local function parameters(measure: any): (RaycastParams, OverlapParams)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = measure.ignored
	ray.IgnoreWater, ray.RespectCanCollide, ray.CollisionGroup = true, true, "Carts"
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = measure.ignored
	overlap.RespectCanCollide, overlap.CollisionGroup = true, "Carts"
	overlap.MaxParts = 0 -- bounded local query; no truncated result may prove clearance
	return ray, overlap
end

local function drivable(result: RaycastResult?, maximumSlope: number?, base: Model?): boolean
	if not result or result.Normal.Y < math.cos(math.rad(maximumSlope or 45)) then
		return false
	end
	local part = result.Instance
	if part == Workspace.Terrain then
		return result.Material ~= Enum.Material.Water
	end
	if baseDrivingSurface(base, part) then
		return true
	end
	return part:IsA("BasePart")
		and part.CanCollide
		and part.Anchored
		and (
			part:GetAttribute("LayoutRole") == "Floor"
			or part:GetAttribute("LayoutRole") == "Ramp"
			or part:GetAttribute("CartDrivableGround") == true
		)
end

-- Brainrot placements reuse the authored driving surfaces rather than treating
-- every anchored roof, rock or decorative top as ground. A departing catch may
-- legitimately start on a registered Camp plot even after its owner disconnects.
function Placement.IsBrainrotSupport(result: RaycastResult?, allowCampBase: boolean?): boolean
	if not result or result.Normal.Y < BrainrotTerritory.MinWalkableNormalY then
		return false
	end
	if drivable(result, math.deg(math.acos(BrainrotTerritory.MinWalkableNormalY)), nil) then
		return true
	end
	if allowCampBase then
		local bases = require(script.Parent.Parent.Systems.PlayerBaseSystem):GetRegisteredBases()
		for _, base in bases do
			if base:IsDescendantOf(Workspace) and baseDrivingSurface(base, result.Instance) then
				return true
			end
		end
	end
	return false
end

-- Candidate retries share the additional placement pool. Static area/readiness
-- probes deliberately do not call this helper or cache a transient budget denial.
function Placement.ProbeBrainrotGround(
	origin: Vector3,
	direction: Vector3,
	params: RaycastParams
): (RaycastResult?, string?)
	if not take("terrain", "OrdinarySpawn") then
		return nil, "QueryBudget"
	end
	return Workspace:Raycast(origin, direction, params), nil
end

function Placement.IsBrainrotVolumeClear(frame: CFrame, size: Vector3, params: OverlapParams): (boolean, string?)
	if not take("world", "OrdinarySpawn") then
		return false, "QueryBudget"
	end
	return #Workspace:GetPartBoundsInBox(frame, size, params) == 0, "INSUFFICIENT_CLEARANCE"
end

function Placement.IsBrainrotGateClear(frame: CFrame, size: Vector3): boolean
	if not context or not context.Descriptors then
		return true
	end
	for _, definition in Regions.Ordered do
		local gate = context.Descriptors:GetGate(definition.regionId)
		if
			gate
			and intersects(frame, size + Vector3.one * Config.SafetySkin * 2, gate.crossing.CFrame, gate.crossing.Size)
		then
			return false
		end
	end
	return true
end

function Placement.IsSupported(cart: Model, measure: any?): boolean
	measure = measure or Placement.Measure(cart)
	if not measure then
		return false
	end
	local geometry = CartGeometry.Get(cart)
	if geometry and cart.PrimaryPart and cart.PrimaryPart.CFrame.UpVector.Y > 0.25 then
		local ray = parameters(measure)
		local supported=0
		if geometry.Ground.CylinderSamples then
			for _,sample in geometry.Ground.CylinderSamples do
				if not take("terrain") then return false end
				local hub=cart.PrimaryPart.CFrame:PointToWorldSpace(sample.Hub)
				local axis=cart.PrimaryPart.CFrame:VectorToWorldSpace(sample.Axis)
				local probe=hub+axis*sample.AxialOffset
				local reach=sample.Radius+sample.HalfThickness+Config.SupportContactGap*2
				local result=Workspace:Raycast(probe+Vector3.yAxis*Config.SupportContactGap,-Vector3.yAxis*reach,ray)
				local gap=if result then TerrainSampler.CylinderPlaneGap(hub,axis,sample.Radius,sample.HalfThickness,result.Position,result.Normal)else nil
				if gap and drivable(result,measure.maximumSlope,measure.assignedBase)and math.abs(gap)<=Config.SupportContactGap then supported+=1 end
			end
		else
			for _, contact in geometry.Ground.ContactSamples do
				if not take("terrain") then return false end
				local point=cart.PrimaryPart.CFrame:PointToWorldSpace(contact)
				local result=Workspace:Raycast(point+Vector3.yAxis*Config.SupportContactGap,-Vector3.yAxis*(Config.SupportContactGap*2),ray)
				if drivable(result,measure.maximumSlope,measure.assignedBase) and result and math.abs(result.Position.Y-point.Y)<=Config.SupportContactGap then supported+=1 end
			end
		end
		return supported>=2
	end
	if not take("terrain") then return false end
	local minimum, maximum = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, shape in measure.shapes do
		if shape.part:IsDescendantOf(cart) then
			minimum, maximum = extend(minimum, maximum, measure.pivot * shape.frame, shape.size)
		end
	end
	local ray = parameters(measure)
	local origin = Vector3.new(measure.pivot.Position.X, minimum.Y + Config.SupportContactGap, measure.pivot.Position.Z)
	local result = Workspace:Raycast(origin, -Vector3.yAxis * (Config.SupportContactGap * 2), ray)
	-- Includes an overturned body resting on drivable ground. Neither wheel
	-- alignment nor the old sampler's upright lower-root-face test is required.
	return drivable(result, measure.maximumSlope, measure.assignedBase)
		and result ~= nil
		and math.abs(result.Position.Y - minimum.Y) <= Config.SupportContactGap
end

local function permitted(_cart: Model, driver: Player?, frame: CFrame, measure: any, initialBase: Model?): boolean
	if not context or not context.Descriptors or not context.Access then
		return false
	end
	local descriptors, access = context.Descriptors, context.Access
	local base = if driver then assignedBase(driver) else initialBase
	local function allows(position: Vector3): boolean
		-- Camp has its own authored boundary authority and is intentionally not
		-- a hunting-region access grant in the progression descriptor registry.
		if baseContains(base, position) then
			return true
		end
		if context.CampContains and context.CampContains(position) then
			return true
		end
		local region = descriptors:GetRegionAtPosition(position)
		return region ~= nil and (driver == nil or access:GetEffectiveAccess(driver, region))
	end
	if not allows(frame.Position) then
		return false
	end
	for _, x in { measure.supportMinimum.X, measure.supportMaximum.X } do
		for _, z in { measure.supportMinimum.Z, measure.supportMaximum.Z } do
			if not allows(frame:PointToWorldSpace(Vector3.new(x, 0, z))) then
				return false
			end
		end
	end
	for _, definition in Regions.Ordered do
		local gate = descriptors:GetGate(definition.regionId)
		if not gate or (driver and access:GetEffectiveAccess(driver, definition.regionId)) then
			continue
		end
		-- Descriptor threshold is semantic and deliberately noncolliding/nonqueryable.
		for _, shape in measure.shapes do
			if
				intersects(
					frame * shape.frame,
					shape.size + Vector3.one * Config.SafetySkin * 2,
					gate.crossing.CFrame,
					gate.crossing.Size
				)
			then
				return false
			end
		end
	end
	return true
end

local function terrainClear(frame: CFrame, measure: any): (boolean, string?)
	local skin = Vector3.one * Config.SafetySkin * 2
	-- Terrain is absent from part overlaps. Refine any occupied voxel that
	-- touches the proposed volume using terrain-only shape casts from a proven
	-- empty position above it. This permits a partially filled support voxel
	-- below the lifted wheels, while a true terrain ceiling/initial embedding
	-- remains blocked. The elevated start and entire path are in this voxel read.
	if not take("terrain", measure.tag) then
		return false, "QueryBudget"
	end
	local minimum, maximum = Vector3.one * math.huge, -Vector3.one * math.huge
	local rise = 0
	for _, shape in measure.shapes do
		minimum, maximum = extend(minimum, maximum, frame * shape.frame, shape.size + skin)
		rise = math.max(rise, shape.size.Magnitude + 8)
	end
	local region = Region3.new(minimum, maximum + Vector3.yAxis * rise):ExpandToGrid(4)
	local _, occupancy = Workspace.Terrain:ReadVoxels(region, 4)
	local low = region.CFrame.Position - region.Size / 2
	local solid = {}
	for x, ys in ipairs(occupancy) do
		for y, zs in ipairs(ys) do
			for z, amount in ipairs(zs) do
				if amount > 0 then
					table.insert(solid, CFrame.new(low + Vector3.new((x - 0.5) * 4, (y - 0.5) * 4, (z - 0.5) * 4)))
				end
			end
		end
	end
	if #solid > 0 then
		local terrain = RaycastParams.new()
		terrain.FilterType = Enum.RaycastFilterType.Include
		terrain.FilterDescendantsInstances = { Workspace.Terrain }
		terrain.CollisionGroup, terrain.RespectCanCollide, terrain.IgnoreWater = "Carts", true, true
		for _, shape in measure.shapes do
			local proposed, size = frame * shape.frame, shape.size + skin
			local start = proposed + Vector3.yAxis * rise
			local needsRefinement = false
			for _, voxel in solid do
				if intersects(start, size, voxel, Vector3.one * 4) then
					return false, "TerrainAbovePose"
				end
				if intersects(proposed, size, voxel, Vector3.one * 4) then
					needsRefinement = true
				end
			end
			if needsRefinement then
				if not take("terrain", measure.tag) then
					return false, "QueryBudget"
				end
				-- A box resting on its own support grazes that terrain at the very
				-- end of the cast. Accept contact within the skin margin, as the
				-- settling casts do; deeper embedding is still blocked.
				local hit = Workspace:Blockcast(start, size, -Vector3.yAxis * rise, terrain)
				if hit and hit.Distance < rise - Config.SafetySkin * 2 then
					return false, "TerrainOccupied"
				end
			end
		end
	end
	return true, nil
end
local function obstacleOverlap(frame: CFrame, measure: any, overlap: OverlapParams): (boolean, string?)
	if not take("world") then
		return false, "QueryBudget"
	end
	local skin = Vector3.one * Config.SafetySkin * 2
	local center = (measure.minimum + measure.maximum) / 2
	local parts =
		Workspace:GetPartBoundsInBox(frame * CFrame.new(center), measure.maximum - measure.minimum + skin, overlap)
	for _, part in parts do
		for _, shape in measure.shapes do
			if intersects(frame * shape.frame, shape.size + skin, part.CFrame, part.Size) then
				return false, "BlockedBy:" .. part:GetFullName()
			end
		end
	end
	return terrainClear(frame, measure)
end


function Placement.Prepare(cart: Model, driver: Player, heading: Vector3): (any?, string?)
	local measure = Placement.Measure(cart)
	local height = Placement.DriverBodyHeight(driver)
	if not measure or not height then
		return nil, "CoreBodyUnavailable"
	end
	measure.assignedBase = assignedBase(driver)
	local position = measure.pivot.Position
	local upright = CFrame.lookAt(position, position + heading, Vector3.yAxis)
	if not permitted(cart, driver, upright, measure) then
		return nil, "RegionOrGateBlocked"
	end
	local ray, overlap = parameters(measure)
	local groundHeight = -math.huge
	local supports = {}
	local mid = (measure.supportMinimum + measure.supportMaximum) / 2
	local footprint = { Vector3.new(mid.X, 0, mid.Z) }
	for _, x in { measure.supportMinimum.X, measure.supportMaximum.X } do
		for _, z in { measure.supportMinimum.Z, measure.supportMaximum.Z } do
			table.insert(footprint, Vector3.new(x, 0, z))
		end
	end
	for _, point in footprint do
		if not take("terrain") then
			return nil, "QueryBudget"
		end
		local origin = upright:PointToWorldSpace(point) + Vector3.yAxis * 8
		local result = Workspace:Raycast(origin, -Vector3.yAxis * Config.GroundProbeDistance, ray)
		if not drivable(result, measure.maximumSlope, measure.assignedBase) or not result then
			return nil, "InvalidDrivableSupport"
		end
		groundHeight = math.max(groundHeight, result.Position.Y)
		supports[result.Instance] = true
	end
	local lift = height / 3
	local target = upright + Vector3.yAxis * (groundHeight + lift - measure.supportMinimum.Y - position.Y)
	if not finiteFrame(target) then
		return nil, "InvalidPose"
	end
	local clear, reason = obstacleOverlap(target, measure, overlap)
	if not clear then
		return nil, reason
	end
	-- Sweep each actual collision/body box through the fall. Only the intended
	-- drivable support near the final contact may terminate a cast.
	for _, shape in measure.shapes do
		if not take("world") then
			return nil, "QueryBudget"
		end
		local hit = Workspace:Blockcast(
			target * shape.frame,
			shape.size + Vector3.one * Config.SafetySkin * 2,
			-Vector3.yAxis * lift,
			ray
		)
		if
			hit
			and (
				not supports[hit.Instance]
				or not drivable(hit, measure.maximumSlope, measure.assignedBase)
				or hit.Distance < lift - Config.SafetySkin * 2
			)
		then
			return nil, "SettlingPathBlocked:" .. hit.Instance:GetFullName()
		end
	end
	return {
		frame = target,
		measure = measure,
		driver = driver,
		cart = cart,
		original = position,
		ground = groundHeight,
		lift = lift,
		heading = heading,
		supports = supports,
		preparedAt = Workspace:GetServerTimeNow(),
	},
		nil
end

-- Initial assigned spawn has no occupant yet. It waits at its exact assigned
-- pad; neither transient obstacles nor rejected clearance choose another node.
function Placement.ValidateAssignedSpawn(cart: Model, frame: CFrame, assignment: any?): (boolean, string?)
	if not Config.Enabled then
		return true, nil
	end
	local measure = Placement.Measure(cart)
	if not measure or not finiteFrame(frame) then
		return false, "InvalidSpawnEnvelope"
	end
	local base = validateAssignedSpawnIdentity(cart, frame, assignment)
	-- Initial outside-region permission requires the exact still-assigned pad.
	-- A cart's owner attribute alone cannot authorize an arbitrary spawn pose.
	measure.assignedBase = base
	if assignment ~= nil and base == nil then
		return false, "StaleAssignedSpawn"
	end
	if not permitted(cart, nil, frame, measure, base) then
		return false, "RegionOrGateBlocked"
	end
	-- A prepared replacement must ignore only the exact currently assigned cart
	-- that it will replace, never another owner's parked vehicle.
	local existing=assignment and assignment.ExistingCart
	if existing and existing:IsA("Model") and existing~=cart and existing:GetAttribute("OwnerUserId")==assignment.Player.UserId then table.insert(measure.ignored,existing)end
	local ray, overlap = parameters(measure)
	local ground = -math.huge
	local supports = {}
	local contactSamples = measure.contactSamples
	if not contactSamples then
		contactSamples={}
		for _, x in {measure.supportMinimum.X,measure.supportMaximum.X} do
			for _, z in {measure.supportMinimum.Z,measure.supportMaximum.Z} do
				table.insert(contactSamples,Vector3.new(x,measure.supportMinimum.Y,z))
			end
		end
	end
	for _, contact in contactSamples do
		if not take("terrain") then return false,"QueryBudget" end
		local origin=frame:PointToWorldSpace(contact)+Vector3.yAxis*2
		local hit=Workspace:Raycast(origin,-Vector3.yAxis*Config.GroundProbeDistance,ray)
		if not hit or not drivable(hit,measure.maximumSlope,measure.assignedBase) then return false,"InvalidDrivableSupport" end
		ground=math.max(ground,hit.Position.Y);supports[hit.Instance]=true
	end
	local clear, reason = obstacleOverlap(frame, measure, overlap)
	if not clear then
		return false, reason
	end
	local fall = frame.Position.Y + measure.supportMinimum.Y - ground
	if fall < 0 then
		return false, "SupportPenetration"
	end
	for _, shape in measure.shapes do
		if not take("world") then
			return false, "QueryBudget"
		end
		local hit = Workspace:Blockcast(
			frame * shape.frame,
			shape.size + Vector3.one * Config.SafetySkin * 2,
			-Vector3.yAxis * fall,
			ray
		)
		if
			hit
			and (
				not supports[hit.Instance]
				or not drivable(hit, measure.maximumSlope, measure.assignedBase)
				or hit.Distance < fall - Config.SafetySkin * 2
			)
		then
			return false, "SpawnFallBlocked"
		end
	end
	return true, nil
end

function Placement.Revalidate(plan: any): (boolean, string?)
	local cart, driver = plan.cart, plan.driver
	local current = cart:GetPivot().Position
	if
		cart.Parent == nil
		or driver.Character == nil
		or (Vector3.new(current.X, 0, current.Z) - Vector3.new(plan.original.X, 0, plan.original.Z)).Magnitude
			> 0.01
	then
		return false, "CartMovedBeforeCommit"
	end
	if plan.measure.assignedBase and assignedBase(driver) ~= plan.measure.assignedBase then
		return false, "StaleAssignedBase"
	end
	if not permitted(cart, driver, plan.frame, plan.measure) then
		return false, "RegionOrGateBlocked"
	end
	local ray, overlap = parameters(plan.measure)
	local clear, reason = obstacleOverlap(plan.frame, plan.measure, overlap)
	if not clear then
		return false, reason
	end
	-- Dynamic clearance includes the fall path, not only the lifted start box.
	-- One broad sweep proves a clear path cheaply; only a broad false positive
	-- requires the actual component envelopes to refine it.
	if not take("world") then
		return false, "QueryBudget"
	end
	local center = (plan.measure.minimum + plan.measure.maximum) / 2
	local broad = Workspace:Blockcast(
		plan.frame * CFrame.new(center),
		plan.measure.maximum - plan.measure.minimum + Vector3.one * Config.SafetySkin * 2,
		-Vector3.yAxis * plan.lift,
		ray
	)
	if
		broad
		and (
			not plan.supports[broad.Instance]
			or not drivable(broad, plan.measure.maximumSlope, plan.measure.assignedBase)
			or broad.Distance < plan.lift - Config.SafetySkin * 2
		)
	then
		for _, shape in plan.measure.shapes do
			if not take("world") then
				return false, "QueryBudget"
			end
			local hit = Workspace:Blockcast(
				plan.frame * shape.frame,
				shape.size + Vector3.one * Config.SafetySkin * 2,
				-Vector3.yAxis * plan.lift,
				ray
			)
			if
				hit
				and (
					not plan.supports[hit.Instance]
					or not drivable(hit, plan.measure.maximumSlope, plan.measure.assignedBase)
					or hit.Distance < plan.lift - Config.SafetySkin * 2
				)
			then
				return false, "SettlingPathChanged"
			end
		end
	end
	return true, nil
end

-- The ordinary-world and release helpers share this exact initial-terrain
-- proof and pool. It adds no duplicate part overlap and raises no query caps.
function Placement.IsTerrainClear(frame: CFrame, size: Vector3, tag: string?): (boolean, string?)
	if
		not finiteFrame(frame)
		or size.X <= 0
		or size.Y <= 0
		or size.Z <= 0
		or size.X ~= size.X
		or size.Y ~= size.Y
		or size.Z ~= size.Z
		or size.Magnitude >= 256
	then
		return false, "InvalidTerrainEnvelope"
	end
	return terrainClear(
		frame,
		{ shapes = { { frame = CFrame.identity, size = size } }, tag = tag or "BrainrotRelease" }
	)
end

-- Only the disposable native TestEZ-style runner may reset its fixture window.
-- Query caps and cumulative diagnostics remain unchanged for real sessions.
function Placement.ResetQueryBudgetForTesting(): boolean
	if not game:GetService("RunService"):IsStudio() or game:GetAttribute("BrainrotTestDiagnosticsDisabled") ~= true then
		return false
	end
	budget.window = Workspace:GetServerTimeNow()
	budget.world, budget.terrain = 0, 0
	budget.TestingResets = (budget.TestingResets or 0) + 1
	return true
end

function Placement.Configure(value: any): any
	local previous = context
	context = value
	return previous
end
function Placement.GetDiagnostics(): any
	return table.clone(budget)
end
Placement.Intersects = intersects
return Placement
