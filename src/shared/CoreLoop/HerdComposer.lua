--!strict
-- A5 herd contents. Pure: callers pass a Random. Snacks roll the region pool normally; the Star takes
-- the best tier of N draws, then a uniform species within that tier (Glitch Legendary keeps 2999 : 1),
-- and its own mutation multiplier. Forced Stars (Lucky / pity / first session) re-roll the whole Star
-- until its TRUE grade reaches the minimum, with the A5/C3 fallbacks.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)
local PoolData = require(script.Parent.PoolData)
local MutationRoller = require(script.Parent.MutationRoller)
local StarGrade = require(script.Parent.StarGrade)

export type Kind = "Wild" | "Village"
export type RushKind = MutationRoller.RushKind
export type Member = { speciesId: string, mutationId: string, star: boolean }
export type Options = {
	stormMult: number?,
	minTrueGrade: ("Super" | "Jackpot")?, -- Lucky Star / Super pity -> "Super"; Jackpot pity -> "Jackpot"
	mutatedSnack: boolean?, -- mutation pity: one snack gets Shiny 70% / Golden 30%
	forceStar: { species: string, mutation: string }?, -- first-session fixed Star
	size: number?,
}
export type Herd = {
	kind: Kind,
	size: number,
	members: { Member }, -- members[1] is the Star
	star: Member,
	visibleGrade: StarGrade.Grade,
	trueGrade: StarGrade.Grade,
	rerolls: number,
	fallback: boolean,
}

local Composer = {}

local function weighted(map: { [number]: number }, random: Random): number
	local keys = {}
	for k in map do
		table.insert(keys, k)
	end
	table.sort(keys)
	local roll, acc = random:NextNumber(), 0
	for _, k in keys do
		acc += map[k]
		if roll < acc then
			return k
		end
	end
	return keys[#keys]
end

function Composer.DrawTier(regionId: string, random: Random): string?
	local roll, acc, last = random:NextNumber(), 0, nil
	for _, tier in PoolData.TierOrder do
		local p = PoolData.TierWeight(regionId, tier)
		if p > 0 then
			acc += p
			last = tier
			if roll < acc then
				return tier
			end
		end
	end
	return last
end

function Composer.BestTier(regionId: string, draws: number, random: Random): string?
	local best = nil
	for _ = 1, math.max(1, draws) do
		local tier = Composer.DrawTier(regionId, random)
		if tier and (best == nil or PoolData.Rank(tier) > PoolData.Rank(best)) then
			best = tier
		end
	end
	return best
end

function Composer.PickSpecies(regionId: string, tier: string, random: Random): string?
	local rows = PoolData.SpeciesRows(regionId, tier)
	if #rows == 0 then
		return nil
	end
	local roll, acc = random:NextNumber(), 0
	for _, row in rows do
		acc += row.share
		if roll < acc then
			return row.id
		end
	end
	return rows[#rows].id
end

local function drawKey(kind: Kind, rush: RushKind): string
	return (if rush == "Mega" then "Mega" elseif rush == "Rush" then "Rush" else "") .. kind
end

function Composer.StarDraws(kind: Kind, rush: RushKind): number
	return (CoreLoop.Star.Draws :: any)[drawKey(kind, rush)]
end

local function rollStar(
	regionId: string,
	kind: Kind,
	rush: RushKind,
	random: Random,
	storm: number?
): Member?
	local tier = Composer.BestTier(regionId, Composer.StarDraws(kind, rush), random)
	local species = tier and Composer.PickSpecies(regionId, tier, random)
	if not species then
		return nil
	end
	local source = if kind == "Wild" then "WildStar" else "VillageStar"
	local chance = MutationRoller.Chance(source, rush, storm)
	return {
		speciesId = species,
		mutationId = MutationRoller.Roll(chance, rush == "Mega", random),
		star = true,
	}
end

function Composer.RollSnack(
	regionId: string,
	rush: RushKind,
	random: Random,
	storm: number?
): Member?
	local tier = Composer.DrawTier(regionId, random)
	local species = tier and Composer.PickSpecies(regionId, tier, random)
	if not species then
		return nil
	end
	local chance = MutationRoller.Chance("Snack", rush, storm)
	return {
		speciesId = species,
		mutationId = MutationRoller.Roll(chance, rush == "Mega", random),
		star = false,
	}
end

-- C3 fallbacks: Super -> top tier + Golden; Jackpot -> top tier + Radioactive.
local function fallbackStar(regionId: string, minimum: string, random: Random): Member?
	local top = PoolData.TopTier(regionId)
	local species = top and Composer.PickSpecies(regionId, top, random)
	if not species then
		return nil
	end
	return {
		speciesId = species,
		mutationId = if minimum == "Jackpot" then "Radioactive" else "Golden",
		star = true,
	}
end

function Composer.ComposeStar(
	regionId: string,
	kind: Kind,
	rush: RushKind,
	random: Random,
	options: Options?
): (Member?, number, boolean)
	local opts = options or {} :: Options
	if opts.forceStar then
		return {
			speciesId = opts.forceStar.species,
			mutationId = opts.forceStar.mutation,
			star = true,
		},
			0,
			false
	end
	local minimum = opts.minTrueGrade
	if not minimum then
		return rollStar(regionId, kind, rush, random, opts.stormMult), 0, false
	end
	local cap = if minimum == "Jackpot"
		then CoreLoop.Star.JackpotRerollCap
		else CoreLoop.Star.LuckyRerollCap
	local needed = StarGrade.Rank(minimum)
	for attempt = 1, cap do
		local star = rollStar(regionId, kind, rush, random, opts.stormMult)
		if
			star
			and StarGrade.Rank(StarGrade.True(regionId, star.speciesId, star.mutationId))
				>= needed
		then
			return star, attempt, false
		end
	end
	return fallbackStar(regionId, minimum, random), cap, true
end

function Composer.Compose(
	regionId: string,
	kind: Kind,
	rush: RushKind,
	random: Random,
	options: Options?
): Herd?
	local opts = options or {} :: Options
	local size = opts.size
		or weighted(
			(if kind == "Wild" then CoreLoop.Herd.WildSizes else CoreLoop.Herd.VillageSizes) :: any,
			random
		)
	local star, rerolls, fallback = Composer.ComposeStar(regionId, kind, rush, random, opts)
	if not star then
		return nil
	end
	local members: { Member } = { star }
	for _ = 2, size do
		local snack = Composer.RollSnack(regionId, rush, random, opts.stormMult)
		if snack then
			table.insert(members, snack)
		end
	end
	if opts.mutatedSnack and #members >= 2 then
		members[2].mutationId =
			MutationRoller.FromShares(CoreLoop.Pity.MutationPityShares :: any, random)
	end
	return {
		kind = kind,
		size = #members,
		members = members,
		star = star,
		visibleGrade = StarGrade.Visible(regionId, star.speciesId),
		trueGrade = StarGrade.True(regionId, star.speciesId, star.mutationId),
		rerolls = rerolls,
		fallback = fallback,
	}
end

return table.freeze(Composer)
