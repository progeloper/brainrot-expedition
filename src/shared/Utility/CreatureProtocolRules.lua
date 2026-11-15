--!strict
local Rules = {}
function Rules.IsFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Rules.ValidId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 160
end
function Rules.ValidTemplate(species: any, lod: any): boolean
	return type(species) == "string"
		and species:match("^BRT_%d%d%d$") ~= nil
		and (lod == "Full" or lod == "Detailed" or lod == "Reduced" or lod == "Far")
end
function Rules.TemplateKey(species: string, lod: string): string
	return species .. ":" .. lod
end
-- Epoch changes invalidate the complete previous region subscription. Sequence
-- orders packets; entity revision orders representations of one stable identity.
function Rules.AcceptPacket(state: any, packet: any): boolean
	if
		type(packet) ~= "table"
		or not Rules.IsFinite(packet.epoch)
		or not Rules.IsFinite(packet.sequence)
		or packet.epoch < state.epoch
		or packet.sequence <= state.sequence
	then
		return false
	end
	if packet.epoch > state.epoch and packet.kind ~= "Context" then
		return false
	end
	state.epoch, state.sequence = packet.epoch, packet.sequence
	return true
end
-- Presentation generation belongs to the stable identity's authoritative
-- publication order, not to a route/escape clock that may be absent on cargo.
-- The original route/reset generation remains a separate sourceGeneration field.
function Rules.StampRepresentation(row: any, revision: number)
	row.revision, row.generation = revision, revision
	return row
end
function Rules.ShouldHideBase(distance: number, wasHidden: boolean?): boolean
	return distance > (if wasHidden then 160 else 180)
end
function Rules.AcceptEntity(previous: any, incoming: any): boolean
	if
		type(incoming) ~= "table"
		or not Rules.ValidId(incoming.id)
		or not Rules.IsFinite(incoming.revision)
		or not Rules.IsFinite(incoming.generation)
	then
		return false
	end
	return previous == nil
		or incoming.generation > previous.generation
		or incoming.generation == previous.generation and incoming.revision >= previous.revision
end
function Rules.RepresentationPriority(state: any, pending: any): number
	if state == "Deposited" then
		return if pending == true then 60 else 50
	end
	if state == "Cart" then
		return 40
	end
	if state == "Carried" then
		return 30
	end
	return 20
end
function Rules.Interpolate(previous: CFrame, target: CFrame, elapsed: number, window: number): CFrame
	return previous:Lerp(target, math.clamp(elapsed / math.max(window, 0.001), 0, 1))
end
return table.freeze(Rules)
