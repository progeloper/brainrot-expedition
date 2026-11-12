--!strict
-- Camp Rework, Part E (owner-approved 12 Nov 2026): Training replaces the cart Speed upgrades.
-- Behind FeatureFlags.TrainingV1Enabled (see Config/CampReworkFlags). Every Training number lives here.
--
-- Speed: old Speed level n (CartPerformanceResolver: base × (1 + 0.10 n)) is Training level 5n; the
-- levels in between interpolate geometrically, so level 25 = old Speed 5 and nobody ever gets slower.
-- XP: +1 per second on the rollers × roller multiplier × 2 with the 2× Training pass. The XP to the
-- next level grows ×1.35 per level; level 1 takes ~60 s on Wooden rollers.
-- Rollers are permanent Cash purchases anchored to the removed Speed prices (Steel ≈ Speed 2 …
-- Rift ≈ Speed 5), so they sit on the existing price curve.

export type Roller = { id: string, name: string, multiplier: number, price: number, order: number }

local MAX_LEVEL = 25
local LEVEL1_XP = 60
local GROWTH = 1.35

local Training = {
	Version = 1, -- profile TrainingVersion written by the SpeedLevel -> TrainingLevel migration
	MaxLevel = MAX_LEVEL,
	Level1Xp = LEVEL1_XP,
	Growth = GROWTH,
	TickSeconds = 1,
	BaseXpPerTick = 1,
	PassMultiplier = 2,
	PassId = "TRAINING_2X",
	AfkKickSeconds = 600, -- 10 minutes without input frees the bay
	StationarySpeed = 1.5, -- studs/s: the cart must be (nearly) still on the rollers
	OldSpeedStep = 0.10, -- CartPerformanceResolver: +10% per old Speed level
	Rollers = {
		{ id = "Wooden", name = "Wooden rollers", multiplier = 1, price = 0, order = 1 },
		{ id = "Steel", name = "Steel rollers", multiplier = 3, price = 2_500_000_000, order = 2 }, -- ≈ Speed 2
		{ id = "Turbo", name = "Turbo rollers", multiplier = 10, price = 15_000_000_000, order = 3 }, -- ≈ Speed 3
		{ id = "Rocket", name = "Rocket rollers", multiplier = 40, price = 75_000_000_000, order = 4 }, -- ≈ Speed 4
		{ id = "Rift", name = "Rift rollers", multiplier = 150, price = 300_000_000_000, order = 5 }, -- ≈ Speed 5
	} :: { Roller },
	-- Client presentation only: how fast the stall rollers/wheels spin per roller tier (deg/s, ≤ 1700
	-- so a 10 Hz tween never wraps the wrong way).
	RollerSpinDegrees = { Wooden = 300, Steel = 480, Turbo = 720, Rocket = 1080, Rift = 1500 },
}

local byId: { [string]: Roller } = {}
for _, roller in Training.Rollers do
	byId[roller.id] = table.freeze(roller)
end
Training.RollersById = byId

-- XP needed to go from `level` to `level + 1` (level 0..24).
function Training.XpToNext(level: number): number
	if level < 0 or level >= MAX_LEVEL then
		return math.huge
	end
	return math.floor(LEVEL1_XP * GROWTH ^ level + 0.5)
end

-- Total XP from level 0 to `level`.
function Training.TotalXp(level: number): number
	local total = 0
	for l = 0, math.min(level, MAX_LEVEL) - 1 do
		total += Training.XpToNext(l)
	end
	return total
end

-- Old Speed multiplier (CartPerformanceResolver) for old level n.
function Training.OldSpeedMultiplier(n: number): number
	return 1 + Training.OldSpeedStep * n
end

-- Cart speed multiplier for a Training level: old Speed n at 5n, geometric in between.
function Training.SpeedMultiplier(level: number): number
	local l = math.clamp(math.floor(level), 0, MAX_LEVEL)
	local n0 = math.floor(l / 5)
	if n0 >= 5 then
		return Training.OldSpeedMultiplier(5)
	end
	local a = Training.OldSpeedMultiplier(n0)
	local b = Training.OldSpeedMultiplier(n0 + 1)
	return a * (b / a) ^ ((l - 5 * n0) / 5)
end

-- Migration target for an old SpeedLevel: never slower (level 5n has exactly old Speed n).
function Training.LevelForOldSpeed(speedLevel: number): number
	return math.clamp(5 * math.max(0, math.floor(speedLevel)), 0, MAX_LEVEL)
end

-- XP gained per tick for a roller and pass ownership.
function Training.XpPerTick(rollerId: string?, hasPass: boolean): number
	local roller = byId[rollerId or "Wooden"] or byId.Wooden
	return Training.BaseXpPerTick * roller.multiplier * (if hasPass then Training.PassMultiplier else 1)
end

return table.freeze(Training)
