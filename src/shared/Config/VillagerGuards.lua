--!strict
-- Villager guards + Escape Ring tuning (presentation/NPC layer only).
-- Nothing here changes catching, odds, prices, cargo, carry or persistence.
-- The whole feature is gated by FeatureFlags.VillagerGuardsEnabled.

export type VillagerType = "Sprinter" | "Plodder" | "Shouter"

-- Real cart numbers read on 10 Nov 2026 (StarterPlayer.CharacterWalkSpeed = 16):
--   StarterSpeed = max(48, 16 * 2.5) = 48; class speed 0.9 / 1.0 / 1.1
--   => MaxTravelSpeed 43.2 (Reinforced, accel 72), 48 (Balanced, accel 80),
--      52.8 (Scout, accel 100) studs/s.
-- The brief's starting table (50..120) crosses in 1-3 s at these speeds, so it is
-- scaled so a straight run from rest (t = v / 2a + R / v) takes 4-10 s on every cart.
local RING_RADIUS_BY_RARITY: { [string]: number } = {
	Common = 200, -- 4.05 s (Scout) .. 4.93 s (Reinforced)
	Uncommon = 225, -- 4.52 .. 5.51
	Rare = 250, -- 4.99 .. 6.09
	Epic = 280, -- 5.57 .. 6.78
	Legendary = 320, -- 6.32 .. 7.71
	Mythic = 360, -- 7.08 .. 8.63
	Celestial = 360,
	Secret = 360,
}

local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Celestial = 7,
	Secret = 7,
}

local VillagerGuards = {
	TickHz = 10,
	NoticeRadius = 70,
	ShouterAlarmRadius = 60,
	WakeRadius = 150,
	MaxAwakeVillagers = 24,

	WindUpSeconds = 0.75,
	MaxChaseSeconds = 12,
	GiveUpCooldownSeconds = 8,
	TantrumSeconds = 1.5,

	-- Villager walk speed while "?" (studs/s). Slightly under player walk speed.
	SuspiciousWalkSpeed = 13,
	SuspiciousStandoff = 14, -- "?" villagers stop this far from the player; they never tag
	SuspiciousTimeoutSeconds = 90, -- "?" with no cart load calms down after this (a new hit refreshes it)
	ReturnWalkSpeed = 10,
	IdleWalkSpeed = 3,

	Types = table.freeze({
		Sprinter = table.freeze({
			burstFactor = 1.05,
			burstSeconds = 3,
			tiredFactor = 0.80,
			giveUpSeconds = 6,
			chases = true,
		}),
		Plodder = table.freeze({
			burstFactor = 0.80,
			burstSeconds = 0,
			tiredFactor = 0.80,
			giveUpSeconds = math.huge,
			chases = true,
		}),
		Shouter = table.freeze({
			burstFactor = 0,
			burstSeconds = 0,
			tiredFactor = 0,
			giveUpSeconds = 0,
			chases = false,
		}),
	}),

	Tag = table.freeze({
		Reach = 6, -- studs from the cart root
		-- Boarding grace: no tags for this long after the load, so a "?" villager standing
		-- beside the cart can't tag it while the player climbs in. They hover just out of reach.
		GraceSeconds = 2.5,
		SpeedMultiplier = 0.6,
		SlowSeconds = 1.5,
		KnockbackSpeed = 6, -- small horizontal nudge, never vertical
	}),
	CloseCallDistance = 5,

	Assist = table.freeze({
		TaggedChasesInRow = 2,
		SpeedMultiplier = 0.9,
		RingRadiusMultiplier = 1.15,
	}),

	-- Fallback cart top speed if a cart definition is missing (Balanced starter).
	FallbackCartTopSpeed = 48,

	RingRadiusByRarity = table.freeze(RING_RADIUS_BY_RARITY),
	RarityRank = table.freeze(RARITY_RANK),
	RingSegments = 48,
	NametagDistance = 40,
	IdleAnimationDistance = 120,
	MaxActiveEmittersNear = 6,
}

function VillagerGuards.radiusForRarity(rarity: string?): number
	return RING_RADIUS_BY_RARITY[rarity or "Common"] or RING_RADIUS_BY_RARITY.Common
end

-- Largest rarity in the cart wins.
function VillagerGuards.highestRarity(rarities: { string }): string
	local best, bestRank = "Common", 0
	for _, rarity in rarities do
		local rank = RARITY_RANK[rarity] or 0
		if rank > bestRank then
			best, bestRank = rarity, rank
		end
	end
	return best
end

return table.freeze(VillagerGuards)
