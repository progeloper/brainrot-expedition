--!strict
-- Personal access derives only from confirmed grants and the registered owner-driver.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.WorldProgression)
local Service = {}
Service.__index = Service

function Service.new(dependencies: any): any
	assert(dependencies.Progression and dependencies.Occupants and dependencies.Descriptors
		and dependencies.GetPlayerState and dependencies.Occupants.GetOwnerUserId
		and dependencies.Occupants.GetDriver and dependencies.Occupants.CanPlayerControlCart,
		"Region access requires authoritative owner-driver adapters")
	return setmetatable({progression = dependencies.Progression, occupants = dependencies.Occupants,
		descriptors = dependencies.Descriptors, state = dependencies.GetPlayerState, operational = {}}, Service)
end

function Service:SetOperational(regionId: string, operational: boolean): boolean
	local definition = Config.ById[regionId]
	if not definition then return false end
	if definition.index > 1 and operational and not self.descriptors:GetGate(regionId) then return false end
	self.operational[regionId] = operational
	return true
end

function Service:IsOperational(regionId: string): boolean
	local definition = Config.ById[regionId]
	return definition ~= nil and (definition.index <= 1 or (self.operational[regionId] == true
		and self.descriptors:GetGate(regionId) ~= nil))
end

function Service:GetCurrentAuthoritativeRegion(entity: any): string?
	local position
	if typeof(entity) == "Vector3" then position = entity
	elseif typeof(entity) == "Instance" then
		if entity:IsA("BasePart") then position = entity.Position
		elseif entity:IsA("Model") then position = entity:GetPivot().Position end
	end
	return if position then self.descriptors:GetRegionAtPosition(position) else nil
end

function Service:CanInteractWild(player: Player, target: any): (boolean, string?)
	local targetRegion = self:GetCurrentAuthoritativeRegion(target)
	local state = self.state(player)
	if not targetRegion or not state or not state.ready or not state.alive then return false, "CharacterUnavailable" end
	if not self:GetEffectiveAccess(player, targetRegion) then return false, "RegionAccessRequired" end
	if state.regionId ~= targetRegion then
		local position = if typeof(target) == "Vector3" then target else target:GetPivot().Position
		if state.transitionRegionId ~= targetRegion or not self.descriptors:IsInTransition(position, targetRegion) then
			return false, "DifferentHuntingRegion"
		end
	end
	return true, nil
end

function Service:CanBoard(player: Player): boolean
	local state = self.state(player)
	return state ~= nil and state.regionId ~= nil and self:GetEffectiveAccess(player, state.regionId)
end

function Service:GetPersonalAccess(player: Player, regionId: string): boolean
	return self.progression:GetPersonalAccess(player, regionId)
end

function Service:GetEffectiveAccess(player: Player, regionId: string): boolean
	if not self:IsOperational(regionId) then return false end
	local state = self.state(player)
	return state ~= nil and state.ready and state.alive and self:GetPersonalAccess(player, regionId)
end

function Service:GetCartEntryAccess(cart: Model, regionId: string): any
	if not Config.ById[regionId] then return {allowed=false,code="UnknownRegion"} end
	if not self:IsOperational(regionId) then return {allowed=false,code="RegionUnavailable"} end
	local ownerUserId = self.occupants:GetOwnerUserId(cart)
	local driver = self.occupants:GetDriver(cart)
	if not ownerUserId or not driver or driver.UserId ~= ownerUserId then
		return {allowed=false,code="OwnerDriverRequired"}
	end
	local state = self.state(driver)
	if not state or not state.ready or not state.alive then return {allowed=false,code="ProfileNotReady"} end
	if not self.occupants:CanPlayerControlCart(driver, cart) then
		return {allowed=false,code="OwnerDriverRequired"}
	end
	local allowed = self:GetPersonalAccess(driver, regionId)
	return {allowed=allowed,code=if allowed then "Allowed" else "RegionAccessRequired"}
end

function Service:Destroy()
	table.clear(self.operational)
end

return Service
