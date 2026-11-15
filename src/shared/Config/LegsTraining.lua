--!strict
-- Playtest Fixes 2, Part G (owner-approved 14 Nov 2026: treadmill look, no speed cap). Legs training:
-- standing on the treadmill beside the Training stall's cart rollers earns Legs XP; Legs levels set
-- WalkSpeed (server); Legs 5 / 10 / 15 unlock free trails; three more trails sell for Gems.
-- Behind FeatureFlags.LegsTrainingV1Enabled (Config/LegsTrainingFlags). Every Legs number lives here.
--
-- XP: +1 per tick (1 s) on the treadmill, ×2 with the existing 2× Training pass: the same tick rate
-- as the Wooden rollers. The curve is Training.lua's shape (level 1 = 60 XP, ×1.35 per level).
-- Speed: WalkSpeed 16 at Legs 0 -> 26 at Legs 15, linear. Guards chase at 0.8–1.05 × the chased
-- cart's top speed (≥ 34.6 studs/s), so Legs 15 never out-runs a guard: no cap (owner, 14 Nov 2026).
-- The Legs level is kept on Rebirth (Rebirth never touches these Phase13 fields).

export type Trail = {
	id: string,
	name: string,
	colors: { Color3 },
	unlockLevel: number?, -- free at this Legs level
	gemItemId: string?, -- sold in the Gem Shop under this item id
	priceGems: number?,
	order: number,
}

local MAX_LEVEL = 15
local LEVEL1_XP = 60
local GROWTH = 1.35
local BASE_SPEED = 16
local MAX_SPEED = 26

local Legs = {
	Version = 1, -- Phase13.LegsVersion written by MigrateLegs
	MaxLevel = MAX_LEVEL,
	Level1Xp = LEVEL1_XP,
	Growth = GROWTH,
	BaseWalkSpeed = BASE_SPEED,
	MaxWalkSpeed = MAX_SPEED,
	TickSeconds = 1,
	BaseXpPerTick = 1,
	PassMultiplier = 2,
	PassId = "TRAINING_2X",
	PollHz = 5, -- server presence poll (≤ 5 Hz)
	-- The belt's standing volume: the belt part's footprint, this tall above its top.
	BeltStandHeight = 6,
	ModelName = "LegsTreadmill",
	EquipCooldownSeconds = 0.5,
	TrailLifetime = 0.45,
	TrailLowLifetimeScale = 0.5, -- Low quality halves Lifetime (client-side, per viewer)
	Trails = {
		{
			id = "TRAIL_GREEN",
			name = "Sprint Green",
			colors = { Color3.fromHex("#9BFF5B"), Color3.fromHex("#1FBF4A") },
			unlockLevel = 5,
			order = 1,
		},
		{
			id = "TRAIL_PURPLE",
			name = "Dash Purple",
			colors = { Color3.fromHex("#E19BFF"), Color3.fromHex("#7A2BFF") },
			unlockLevel = 10,
			order = 2,
		},
		{
			id = "TRAIL_GOLD",
			name = "Gold Rush",
			colors = { Color3.fromHex("#FFF07A"), Color3.fromHex("#FFB000") },
			unlockLevel = 15,
			order = 3,
		},
		{
			id = "TRAIL_RAINBOW",
			name = "Rainbow",
			colors = {
				Color3.fromHex("#FF3B3B"),
				Color3.fromHex("#FFE14A"),
				Color3.fromHex("#5BE36B"),
				Color3.fromHex("#46A7FF"),
				Color3.fromHex("#B86CFF"),
			},
			gemItemId = "TRAIL_RAINBOW",
			priceGems = 150,
			order = 4,
		},
		{
			id = "TRAIL_GLITCH",
			name = "Glitch",
			colors = { Color3.fromHex("#00FFE0"), Color3.fromHex("#FF00C8") },
			gemItemId = "TRAIL_GLITCH",
			priceGems = 300,
			order = 5,
		},
		{
			id = "TRAIL_FIRE",
			name = "Fire",
			colors = { Color3.fromHex("#FFE14A"), Color3.fromHex("#FF3B0F") },
			gemItemId = "TRAIL_FIRE",
			priceGems = 600,
			order = 6,
		},
	} :: { Trail },
}

local byId: { [string]: Trail } = {}
for _, trail in Legs.Trails do
	byId[trail.id] = trail
end
Legs.TrailsById = byId

-- XP needed to go from `level` to `level + 1` (0..14).
function Legs.XpToNext(level: number): number
	if level < 0 or level >= MAX_LEVEL then
		return math.huge
	end
	return math.floor(LEVEL1_XP * GROWTH ^ level + 0.5)
end

function Legs.TotalXp(level: number): number
	local total = 0
	for l = 0, math.min(level, MAX_LEVEL) - 1 do
		total += Legs.XpToNext(l)
	end
	return total
end

-- Server WalkSpeed for a Legs level (16 -> 26).
function Legs.WalkSpeed(level: number): number
	local l = math.clamp(math.floor(level), 0, MAX_LEVEL)
	return BASE_SPEED + (MAX_SPEED - BASE_SPEED) * l / MAX_LEVEL
end

function Legs.XpPerTick(hasPass: boolean): number
	return Legs.BaseXpPerTick * (if hasPass then Legs.PassMultiplier else 1)
end

-- Free trails owned at a Legs level.
function Legs.FreeTrailsAt(level: number): { string }
	local out = {}
	for _, trail in Legs.Trails do
		if trail.unlockLevel and level >= trail.unlockLevel then
			table.insert(out, trail.id)
		end
	end
	return out
end

return table.freeze(Legs)
