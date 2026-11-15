--!strict
-- Storm response for an entity already inside a region it may not enter (flag-gated).
-- Access is decided by RegionBoundaryGuard; this module only chooses the response:
--   1. tell the client to push itself out (StormPush) along the nearest edge normal;
--   2. if it is still inside PUSH_GRACE_SECONDS later, move it to a safe point
--      FALLBACK_OFFSET studs outside the nearest usable edge.
-- Never damages, never changes carry state, never drops cargo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geometry = require(ReplicatedStorage.Shared.Utility.StormGeometry)

local Response = {}
Response.__index = Response

Response.PUSH_GRACE_SECONDS = 0.6
Response.FALLBACK_OFFSET = 8

export type Adapters = {
	Boundaries: { [string]: { points: { Vector2 } } },
	KeyForRegion: (regionId: string) -> string?,
	Now: (() -> number)?,
	-- Client hint: outward unit normal (Y = 0) and nearest exit point.
	Push: (entity: any, regionKey: string, normal: Vector3, exit: Vector3) -> (),
	-- Is this XZ point a valid landing for the entity (not locked for it, ground present)?
	-- Returns the grounded position or nil.
	ResolveLanding: (entity: any, point: Vector2) -> Vector3?,
	-- Authoritative move (character root or whole cart assembly). Returns success.
	Move: (entity: any, landing: Vector3) -> boolean,
	-- Legacy fallback when no landing qualifies (existing gate safe exterior).
	LegacyCorrect: (entity: any, regionId: string) -> boolean,
	Record: (name: string, data: { [string]: any }, entity: any) -> (),
}

function Response.new(adapters: Adapters): any
	return setmetatable({ a = adapters, now = adapters.Now or os.clock, active = {} }, Response)
end

-- Called every guard tick while the entity is inside a locked region.
function Response:Handle(entity: any, regionId: string): string
	local key = self.a.KeyForRegion(regionId)
	local boundary = key and self.a.Boundaries[key]
	if not key or not boundary then
		-- No Storm polygon: keep the legacy correction.
		self.a.LegacyCorrect(entity, regionId)
		return "Legacy"
	end
	local now = self.now()
	local state = self.active[entity.id]
	if state and state.regionId ~= regionId then
		state = nil
	end
	local position: Vector3 = entity.position
	if not state then
		local hit = Geometry.NearestEdge(boundary.points, position.X, position.Z)
		local normal = Vector3.new(hit.normal.X, 0, hit.normal.Y)
		self.a.Push(entity, key, normal, Vector3.new(hit.point.X, position.Y, hit.point.Y))
		self.active[entity.id] = { regionId = regionId, key = key, pushedAt = now, entity = entity }
		return "Pushed"
	end
	if now - state.pushedAt < Response.PUSH_GRACE_SECONDS then
		return "Waiting"
	end
	-- Still inside after the grace period: authoritative fallback.
	self.active[entity.id] = nil
	for _, candidate in
		Geometry.ExitCandidates(boundary.points, position.X, position.Z, Response.FALLBACK_OFFSET)
	do
		local landing = self.a.ResolveLanding(entity, candidate.point)
		if landing and self.a.Move(entity, landing) then
			self.a.Record("StormPushed", { regionKey = key, fallbackUsed = true }, entity)
			return "Moved"
		end
	end
	local corrected = self.a.LegacyCorrect(entity, regionId)
	self.a.Record(
		"StormPushed",
		{ regionKey = key, fallbackUsed = true, legacyExterior = corrected },
		entity
	)
	return if corrected then "LegacyMoved" else "Failed"
end

-- Called when the entity is no longer inside any locked region.
function Response:Clear(entityId: any)
	local state = self.active[entityId]
	if state then
		self.active[entityId] = nil
		-- The client push alone was enough.
		self.a.Record("StormPushed", { regionKey = state.key, fallbackUsed = false }, state.entity)
	end
end

function Response:Destroy()
	table.clear(self.active)
end

return Response
