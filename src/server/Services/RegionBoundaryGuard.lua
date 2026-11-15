--!strict
-- One scheduler's work unit. All entity/assembly mutation remains in existing adapters.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.WorldProgression)
local Math = require(ReplicatedStorage.Shared.Utility.RegionGuardMath)
local Guard = {}
Guard.__index = Guard

function Guard.new(adapters: any): any
	assert(adapters.Access and adapters.Descriptors and adapters.GetEntities and adapters.Correct
		and adapters.SetDenied and adapters.StopInward and adapters.Notice, "Boundary guard requires authoritative adapters")
	return setmetatable({a=adapters,lastNotice={},denied={},deniedEntities={},now=adapters.Now or os.clock},Guard)
end

local function approachContains(gate, entity)
	local point=gate.approach.CFrame:PointToObjectSpace(entity.position)
	local half=gate.approach.Size/2
	-- Height does not authorize jumping over the entrance.
	return math.abs(point.X)<=half.X+(entity.lateralExtent or 0)
		and math.abs(point.Z)<=half.Z+(entity.extent or 0)
end

function Guard:Notify(entity: any, code: string, regionId: string)
	local now=self.now()
	for _,player in entity.members do
		if now-(self.lastNotice[player] or -math.huge)>=Config.UNAUTHORIZED_NOTICE_COOLDOWN_SECONDS then
			self.lastNotice[player]=now self.a.Notice(player,code,regionId)
		end
	end
end

function Guard:SetDenied(entity: any, gate: any?)
	local previous=self.deniedEntities[entity.id]
	local replaced=previous~=nil and previous.cart~=entity.cart
	if replaced then
		-- Release the old target before rebinding a reused logical identity.
		self.a.SetDenied(previous,nil)
		self.denied[entity.id]=nil self.deniedEntities[entity.id]=nil
	end
	local regionId=if gate then gate.regionId else nil
	if replaced or self.denied[entity.id]~=regionId then
		self.a.SetDenied(entity,if gate then gate.normal else nil)
		self.denied[entity.id]=regionId
	end
	-- Refresh snapshots without rewriting an unchanged, legitimate denial.
	self.deniedEntities[entity.id]=if gate then entity else nil
end

function Guard:Step()
	local seen={}
	for _,entity in self.a.GetEntities() do
		seen[entity.id]=true
		if not entity.ready or not entity.alive then self:SetDenied(entity,nil) continue end
		local current=self.a.Descriptors:GetRegionAtPosition(entity.position)
		local function hasEffectiveAccess(regionId)
			for _,player in entity.members do
				if not self.a.Access:GetEffectiveAccess(player,regionId) then return false end
			end
			return #entity.members>0
		end
		local blocked=false
		for _,definition in Config.Ordered do
			if definition.index<=1 then continue end
			local gate=self.a.Descriptors:GetGate(definition.regionId)
			if not gate then continue end
			local inward=(entity.position-gate.threshold):Dot(gate.normal)
			local atApproach=approachContains(gate,entity)
			local predicts=atApproach and inward<=0 and Math.WouldCross(entity.position,entity.velocity,
				gate.threshold,gate.normal,entity.extent or 0,Config.REGION_GUARD_INTERVAL_SECONDS,gate.crossing.Size.Z/2)
			-- Keep a stopped cart denied until steering changes or permission arrives.
			local retaining=self.denied[entity.id]==definition.regionId and atApproach
				and entity.forward:Dot(gate.normal)>0
			if predicts or retaining then
				local access=if entity.cart then self.a.Access:GetCartEntryAccess(entity.cart,definition.regionId)
					else {allowed=hasEffectiveAccess(definition.regionId),code="RegionAccessRequired"}
				if not access.allowed then
					blocked=true self:SetDenied(entity,gate)
					self.a.StopInward(entity,gate.normal)
					self:Notify(entity,access.code,definition.regionId)
					break
				end
			end
		end
		if not blocked then self:SetDenied(entity,nil) end
		local storming=false
		if current and Config.ById[current] and Config.ById[current].index>1 and not hasEffectiveAccess(current) then
			if self.a.Storm then
				-- TerrainRedesign: same access decision; push/fallback response instead of an instant snap.
				storming=true
				self.a.Storm:Handle(entity,current) self:Notify(entity,"RegionAccessRequired",current)
			else
				local gate=self.a.Descriptors:GetGate(current)
				if gate or (self.a.Descriptors.GetSafeExterior and self.a.Descriptors:GetSafeExterior(current)) then
					self.a.Correct(entity,current) self:Notify(entity,"RegionAccessRequired",current)
				end
			end
		end
		if self.a.Storm and not storming then self.a.Storm:Clear(entity.id) end
	end
	for id,entity in self.deniedEntities do
		if not seen[id] then self:SetDenied(entity,nil) end
	end
	if self.a.Storm then
		for id in self.a.Storm.active do
			if not seen[id] then self.a.Storm.active[id]=nil end
		end
	end
end

function Guard:RemovePlayer(player: Player)
	self.lastNotice[player]=nil
end

function Guard:Destroy()
	if self.a.Storm then self.a.Storm:Destroy() end
	for _,entity in self.deniedEntities do self:SetDenied(entity,nil) end
	table.clear(self.lastNotice) table.clear(self.denied) table.clear(self.deniedEntities)
end
return Guard
