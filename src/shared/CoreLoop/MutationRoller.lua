--!strict
-- K1/K3/K4 mutation rolls. Pure: callers pass a Random. One mutation per individual; catalogue
-- shares and multipliers are read, never changed. Chance = Base x source x event x paid storm,
-- clamped to Mutation.Cap.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)
local MutationCatalog = require(script.Parent.Parent.Config.MutationCatalog)

export type RushKind = "Idle" | "Warning" | "Rush" | "Mega"
export type Source = "Snack" | "Loner" | "WildStar" | "VillageStar"

local Roller = {}

local RARE_TILT = { Radioactive = true, Astral = true }

-- Shares inside a mutated roll (sum 1). MEGA doubles Radioactive + Astral, then renormalises.
function Roller.Shares(mega: boolean): { { id: string, share: number } }
	local rows = {}
	local total = 0
	for _, entry in MutationCatalog.Order do
		if entry.share > 0 then
			local share = entry.share
			if mega and RARE_TILT[entry.id] then
				share *= CoreLoop.Mutation.MegaRareShareMult
			end
			table.insert(rows, { id = entry.id, share = share })
			total += share
		end
	end
	for _, row in rows do
		row.share /= total
	end
	return rows
end

-- Source multiplier for a roll, before the paid storm and the cap.
function Roller.SourceMultiplier(source: Source, rush: RushKind): number
	local isRush, isMega = rush == "Rush", rush == "Mega"
	if source == "WildStar" or source == "VillageStar" then
		local key = (if isMega then "Mega" elseif isRush then "Rush" else "")
			.. (if source == "WildStar" then "Wild" else "Village")
		return (CoreLoop.Star.MutationMult :: any)[key]
	end
	local m = CoreLoop.Mutation
	return if isMega then m.MegaSnackMult elseif isRush then m.RushSnackMult else m.SnackMult
end

-- Absolute chance. stormMult is the paid Mutation Storm multiplier (1 when inactive); base defaults to
-- Phase12.MutationChance's 4%. The paid storm multiplies before the clamp.
function Roller.Chance(source: Source, rush: RushKind, stormMult: number?, base: number?): number
	local chance = (base or CoreLoop.Mutation.Base)
		* Roller.SourceMultiplier(source, rush)
		* (stormMult or 1)
	return math.clamp(chance, 0, CoreLoop.Mutation.Cap)
end

local function pick(rows: { { id: string, share: number } }, random: Random): string
	local roll = random:NextNumber()
	local acc = 0
	for _, row in rows do
		acc += row.share
		if roll < acc then
			return row.id
		end
	end
	return rows[#rows].id
end

-- "None" or a mutation id.
function Roller.Roll(chance: number, mega: boolean, random: Random): string
	if chance <= 0 or random:NextNumber() >= chance then
		return "None"
	end
	return pick(Roller.Shares(mega), random)
end

-- Weighted pick from a {Name = share} map (pity Shiny/Golden, Mutation Rain outcomes).
function Roller.FromShares(shares: { [string]: number }, random: Random): string
	local rows = {}
	local total = 0
	for id, share in shares do
		table.insert(rows, { id = id, share = share })
		total += share
	end
	table.sort(rows, function(a, b)
		return a.id < b.id
	end)
	for _, row in rows do
		row.share /= total
	end
	return pick(rows, random)
end

function Roller.RainOutcome(random: Random): string
	return Roller.FromShares(CoreLoop.Mutation.Rain.Shares :: any, random)
end

function Roller.Multiplier(mutationId: string?): number
	local entry = if mutationId then MutationCatalog.ById[mutationId] else nil
	return if entry then entry.multiplier else 1
end

return table.freeze(Roller)
