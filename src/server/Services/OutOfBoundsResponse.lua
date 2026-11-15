--!strict
-- TerrainRedesign (V5) out-of-bounds sea mist (flag-gated). Runs after the region guard each tick.
-- An entity past the island's playable edge is:
--   1. told to push itself back inward (StormPush remote, kind "Mist");
--   2. if still outside PUSH_GRACE_SECONDS later, moved to the nearest valid shore landing, else to
--      its last safe position, else to the hub.
-- An entity below FloorY (fell through the world) is moved at once. Never damages, never changes
-- carry state; region access is unchanged (landings in a region locked for the entity are refused).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EdgeMath = require(ReplicatedStorage.Shared.Utility.IslandEdgeMath)

local Response = {}
Response.__index = Response

Response.PUSH_GRACE_SECONDS = 0.6

export type Adapters = {
	Edge: any, -- Config.IslandEdge
	Now: (() -> number)?,
	-- Client hint: inward unit normal (Y = 0) and the nearest point on the playable edge.
	Push: (entity: any, normal: Vector3, exit: Vector3) -> (),
	-- Grounded landing at this XZ point valid for the entity (not locked for it, solid, dry), or nil.
	ResolveLanding: (entity: any, point: Vector2) -> Vector3?,
	-- Authoritative move of the entity to an exact position. Returns success.
	Move: (entity: any, landing: Vector3) -> boolean,
	-- Last-resort landing (the hub spawn), or nil.
	Hub: () -> Vector3?,
	-- Is the entity currently being handled by the Storm (inside a locked region)?
	Storming: (entity: any) -> boolean,
	Record: (data: { [string]: any }, entity: any) -> (),
}

function Response.new(adapters: Adapters): any
	return setmetatable(
		{ a = adapters, now = adapters.Now or os.clock, active = {}, safe = {} },
		Response
	)
end

function Response:Classify(position: Vector3): string
	local edge = self.a.Edge
	if position.Y < edge.FloorY then
		return "Fell"
	end
	if EdgeMath.IsOutside(edge.Playable, edge.OutsideMargin, position.X, position.Z) then
		return "Outside"
	end
	return "Inside"
end

function Response:Return(entity: any, reason: string): string
	local edge = self.a.Edge
	local position: Vector3 = entity.position
	if reason == "Outside" then
		for _, point in EdgeMath.Landings(edge.Playable, position.X, position.Z, edge.LandingInsets) do
			local landing = self.a.ResolveLanding(entity, point)
			if landing and self.a.Move(entity, landing) then
				self.a.Record(
					{ regionKey = "OutOfBounds", fallbackUsed = true, landing = "Shore" },
					entity
				)
				return "Shore"
			end
		end
	end
	local last = self.safe[entity.id]
	if last and self.a.Move(entity, last) then
		self.a.Record(
			{ regionKey = "OutOfBounds", fallbackUsed = true, landing = "LastSafe" },
			entity
		)
		return "LastSafe"
	end
	local hub = self.a.Hub()
	if hub and self.a.Move(entity, hub) then
		self.a.Record({ regionKey = "OutOfBounds", fallbackUsed = true, landing = "Hub" }, entity)
		return "Hub"
	end
	self.a.Record({ regionKey = "OutOfBounds", fallbackUsed = true, landing = "Failed" }, entity)
	return "Failed"
end

-- One entity per guard tick. Returns the action taken (for tests and diagnostics).
function Response:Handle(entity: any): string
	if not entity.ready or not entity.alive then
		self.active[entity.id] = nil
		return "Skipped"
	end
	local position: Vector3 = entity.position
	local where = self:Classify(position)
	if where == "Inside" then
		if not self.a.Storming(entity) then
			self.safe[entity.id] = position
		end
		local state = self.active[entity.id]
		if state then
			self.active[entity.id] = nil
			-- The client push alone was enough.
			self.a.Record({ regionKey = "OutOfBounds", fallbackUsed = false }, entity)
			return "Cleared"
		end
		return "Inside"
	end
	if where == "Fell" then
		self.active[entity.id] = nil
		return self:Return(entity, where)
	end
	local now = self.now()
	local state = self.active[entity.id]
	if not state then
		local _, point, normal = EdgeMath.Nearest(self.a.Edge.Playable, position.X, position.Z)
		self.a.Push(
			entity,
			Vector3.new(normal.X, 0, normal.Y),
			Vector3.new(point.X, position.Y, point.Y)
		)
		self.active[entity.id] = { pushedAt = now }
		return "Pushed"
	end
	if now - state.pushedAt < Response.PUSH_GRACE_SECONDS then
		return "Waiting"
	end
	self.active[entity.id] = nil
	return self:Return(entity, where)
end

function Response:Step(entities: { any })
	local seen = {}
	for _, entity in entities do
		seen[entity.id] = true
		self:Handle(entity)
	end
	for id in self.active do
		if not seen[id] then
			self.active[id] = nil
		end
	end
	for id in self.safe do
		if not seen[id] then
			self.safe[id] = nil
		end
	end
end

function Response:Destroy()
	table.clear(self.active)
	table.clear(self.safe)
end

return Response
