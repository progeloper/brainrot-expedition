--!strict
-- Pure absolute-time samples shared by the coordinator and isolated tests.
local Rules = {}
function Rules.Rebirth(age: number, reduced: boolean?): any
	local t = math.clamp(age, 0, 7)
	local phase = if t < 1
		then "Frame"
		elseif t < 4.5 then "Intake"
		elseif t < 5.5 then "Contract"
		elseif t < 7 then "Reveal"
		else "Done"
	local intake = math.clamp((t - 1) / 3.5, 0, 1)
	return {
		phase = phase,
		canSkip = t >= 1,
		done = t >= 7,
		intake = intake,
		contraction = math.clamp((t - 4.5), 0, 1),
		reveal = math.clamp((t - 5.5) / 1.5, 0, 1),
		fade = if reduced then (if t < 1 then t elseif t < 5.5 then 1 else 1 - (t - 5.5) / 1.5) else 0,
	}
end
function Rules.Reset(age: number, reduced: boolean?): any
	local t = math.max(0, age)
	return {
		scale = if reduced then 1 else 1 + 0.12 * math.sin(math.clamp(t / 0.1, 0, 1) * math.pi / 2),
		transparency = math.clamp((t - 0.1) / 0.7, 0, 1),
		done = t >= 0.8,
	}
end
function Rules.CopyCount(total: number, tier: string): number
	local cap = ({ High = 12, Medium = 6, Low = 3 })[tier] or 3
	return math.min(math.max(0, math.floor(total)), cap)
end
-- Descriptor groups partition at most48 provided samples over the existing
-- intake interval. The renderer destroys the old group before building the next.
function Rules.CopyWindow(age: number, available: number, tier: string, cash: boolean?): any
	local cap = Rules.CopyCount(48, tier)
	local sampled = math.clamp(math.floor(available), 0, 48)
	if cash then
		sampled = cap
	end
	local groups = if sampled > 0 then math.ceil(sampled / cap) else 0
	if cash then
		groups = 1
	end
	local duration = if groups > 0 then 3.5 / groups else 3.5
	local group = if groups > 0 then math.clamp(math.floor(math.max(0, age - 1) / duration), 0, groups - 1) else 0
	local first = group * cap + 1
	local last = math.min(sampled, first + cap - 1)
	return {
		cap = cap,
		sampled = sampled,
		groups = groups,
		group = group,
		first = first,
		last = last,
		count = math.max(0, last - first + 1),
		progress = math.clamp((age - 1 - group * duration) / duration, 0, 1),
		duration = duration,
	}
end
function Rules.CopyProgress(progress: number, ordinal: number, count: number): number
	local delay = if count > 1 then math.clamp((ordinal - 1) / (count - 1), 0, 1) * 0.22 else 0
	return math.clamp((progress - delay) / (1 - delay), 0, 1)
end
-- A suspended preparation owns no GUI or control lock. Only the newest live
-- ticket may cross the asynchronous boundary into presentation construction.
function Rules.PreparationFence(isLive: (number) -> boolean): any
	local pending: any = nil
	local fence = {}
	function fence:Begin(generation: number, isCurrentContext: (() -> boolean)?): any
		local ticket = { generation = generation, isCurrentContext = isCurrentContext }
		pending = ticket
		return ticket
	end
	function fence:IsCurrent(ticket: any): boolean
		return ticket ~= nil
			and pending == ticket
			and isLive(ticket.generation)
			and (not ticket.isCurrentContext or ticket.isCurrentContext())
	end
	function fence:Commit(ticket: any): boolean
		if not self:IsCurrent(ticket) then
			return false
		end
		pending = nil
		return true
	end
	function fence:Cancel()
		pending = nil
	end
	return fence
end
-- One delayed subject repair shares the coordinator schedule. A departing
-- character is never selected again, even during CharacterRemoving's old-character gap.
function Rules.CameraRestoreFence(
	isLive: (number) -> boolean,
	isInWorld: (any) -> boolean,
	belongsTo: (any, any) -> boolean
): any
	local pending: any = nil
	local fence = {}
	function fence:Begin(ticket: any)
		pending = table.clone(ticket)
		pending.stepped = false
	end
	function fence:Cancel()
		pending = nil
	end
	function fence:Pending(): boolean
		return pending ~= nil
	end
	function fence:Step(context: any): (any, string)
		local ticket = pending
		if not ticket then
			return nil, "Idle"
		end
		if
			not isLive(ticket.generation)
			or context.camera ~= ticket.camera
			or (ticket.stepped and context.cameraType ~= ticket.cameraType)
		then
			pending = nil
			return nil, "Cancelled"
		end
		if context.now >= ticket.deadline then
			pending = nil
			return nil, "Expired"
		end
		-- Default camera may already have adopted the new Humanoid. A different
		-- subject belongs to another camera owner and must not be overwritten.
		local previousUsable = ticket.subject == nil or isInWorld(ticket.subject)
		local characterChanged = ticket.departing or context.character ~= ticket.character
		local previousWasCharacter = ticket.subject ~= nil and belongsTo(ticket.subject, ticket.character)
		local ownedNilGap = context.subject == nil
			and ((characterChanged and previousWasCharacter) or not previousUsable)
		if context.subject ~= ticket.subject and context.subject ~= context.humanoid and not ownedNilGap then
			pending = nil
			return nil, "Cancelled"
		end
		ticket.stepped = true
		if previousUsable and (not characterChanged or (ticket.subject ~= nil and not previousWasCharacter)) then
			pending = nil
			return ticket.subject, "Ready"
		end
		if
			context.character ~= nil
			and (not ticket.departing or context.character ~= ticket.character)
			and context.humanoid ~= nil
			and isInWorld(context.humanoid)
			and belongsTo(context.humanoid, context.character)
		then
			pending = nil
			return context.humanoid, "Ready"
		end
		return nil, "Waiting"
	end
	return fence
end
return table.freeze(Rules)
