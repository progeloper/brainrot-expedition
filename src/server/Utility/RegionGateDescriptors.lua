--!strict
-- Cache authored floor columns once. Region membership is independent of gate
-- trigger contact and of a client's streamed instances or camera visibility.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.WorldProgression)
local Descriptors = {}
Descriptors.__index = Descriptors

function Descriptors.new(map: Instance): any
	local self = setmetatable({map=map, columns = {}, gates = {}, safeExteriors = {}, errors = {}}, Descriptors)
	for _, definition in Config.Ordered do
		local region = map:FindFirstChild(definition.displayName)
		local columns = {}
		if region then
			for _, part in region:GetDescendants() do
				if part:IsA("BasePart") and part:GetAttribute("LayoutRole") == "Floor"
					and part:GetAttribute("GeneratedBy") == "CreateBasicMap_v1" then
					table.insert(columns, {part = part, frame = part.CFrame, half = part.Size / 2})
				end
			end
		end
		if #columns == 0 then self.errors[definition.regionId] = "RegionFloorMissing" end
		self.columns[definition.regionId] = columns
	end
	local folder = map:FindFirstChild("ProgressionGates")
	if folder then
		for _, definition in Config.Ordered do
			if definition.index <= 1 then continue end
			local gate = folder:FindFirstChild(definition.key)
			if gate then self:BindGate(definition.regionId, gate) end
		end
	end
	return self
end

function Descriptors:GetRegionAtPosition(position: Vector3): string?
	if typeof(position) ~= "Vector3" or position.X ~= position.X or position.Y ~= position.Y
		or position.Z ~= position.Z or math.abs(position.X) == math.huge
		or math.abs(position.Y) == math.huge or math.abs(position.Z) == math.huge then return nil end
	-- Lower progression index wins an exact shared edge; inward movement resolves
	-- to the destination column. Height does not turn a jump into a bypass.
	for _, definition in Config.Ordered do
		for _, column in self.columns[definition.regionId] do
			if not column.part:IsDescendantOf(self.map) then continue end
			local localPoint = column.frame:PointToObjectSpace(position)
			if math.abs(localPoint.X) <= column.half.X and math.abs(localPoint.Z) <= column.half.Z then
				return definition.regionId
			end
		end
	end
	return nil
end

function Descriptors:BindGate(regionId: string, gate: Instance): (boolean, string?)
	local definition = Config.ById[regionId]
	if not definition or definition.index <= 1 then return false, "UnknownRegion" end
	local function reject(code)
		self.gates[regionId], self.errors[regionId] = nil, code
		return false, code
	end
	if self.errors[regionId] == "RegionFloorMissing" then return reject("RegionFloorMissing") end
	if not gate:IsA("Model") or gate:GetAttribute("RegionId") ~= regionId
		or gate:GetAttribute("LogicalRegionKey") ~= definition.key then return reject("GateRegionMismatch") end
	local names = {"InteractionAnchor", "Approach", "Threshold", "SafeCharacterExterior", "SafeCartExterior", "DoorPresentation"}
	local parts = {}
	for _, name in names do
		local part = gate:FindFirstChild(name)
		if not part or not part:IsA("BasePart") or not part.Anchored then return reject("GateDescriptorMissing") end
		parts[name] = part
	end
	if parts.DoorPresentation.CanCollide or parts.Approach.CanCollide or parts.Threshold.CanCollide then
		return reject("GateCollisionInvalid")
	end
	local normal = gate:GetAttribute("InwardNormal")
	if typeof(normal) ~= "Vector3" or math.abs(normal.Magnitude - 1) > 1e-6 or math.abs(normal.Y) > 1e-6 then
		return reject("GateNormalInvalid")
	end
	local threshold = parts.Threshold.Position
	if self:GetRegionAtPosition(threshold + normal * 4) ~= regionId then return reject("GateInteriorMismatch") end
	local exterior = parts.SafeCharacterExterior.Position
	local exteriorRegion = self:GetRegionAtPosition(exterior)
	if not exteriorRegion or Config.ById[exteriorRegion].index >= definition.index then return reject("GateExteriorInvalid") end
	local cartRegion = self:GetRegionAtPosition(parts.SafeCartExterior.Position)
	if cartRegion ~= exteriorRegion then return reject("GateCartExteriorInvalid") end
	local partCount = 0
	for _, part in gate:GetDescendants() do if part:IsA("BasePart") then partCount += 1 end end
	if partCount > 24 then return reject("GatePartBudgetExceeded") end
	self.gates[regionId] = {regionId = regionId, key = definition.key, instance = gate,
		anchor = parts.InteractionAnchor, threshold = threshold, normal = normal,
		approach = parts.Approach, crossing = parts.Threshold,
		safeCharacter = parts.SafeCharacterExterior.CFrame, safeCart = parts.SafeCartExterior.CFrame,
		exteriorRegion = exteriorRegion, partCount = partCount}
	self.safeExteriors[regionId] = {safeCharacter=self.gates[regionId].safeCharacter,
		safeCart=self.gates[regionId].safeCart,exteriorRegion=exteriorRegion}
	self.errors[regionId] = nil
	return true, nil
end

function Descriptors:GetGate(regionId: string): any?
	local gate = self.gates[regionId]
	if not gate or not gate.instance:IsDescendantOf(self.map) or not gate.anchor:IsDescendantOf(gate.instance) then return nil end
	return gate
end

function Descriptors:GetSafeExterior(regionId: string): any?
	local safe=self.safeExteriors[regionId]
	if not safe or self:GetRegionAtPosition(safe.safeCharacter.Position)~=safe.exteriorRegion
		or self:GetRegionAtPosition(safe.safeCart.Position)~=safe.exteriorRegion then return nil end
	return safe
end

function Descriptors:IsInTransition(position: Vector3, regionId: string, footprintDepth: number?): boolean
	local gate = self:GetGate(regionId)
	if not gate then return false end
	local point = gate.crossing.CFrame:PointToObjectSpace(position)
	local half = gate.crossing.Size / 2
	return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z + (footprintDepth or 0)
end

function Descriptors:Invalidate(regionId: string)
	self.gates[regionId] = nil
	self.errors[regionId] = "RegionUnavailable"
end

return Descriptors
