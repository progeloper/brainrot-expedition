--!strict
-- Authored Development starting defaults from the 14 October 2026 request.
-- Current valid regional/economy/theft configuration retains precedence.
local Environment = require(script.Parent.Environment)
local function frozen(value)
	return table.freeze(value)
end
local escapes = {}
for _, row in
	{
		{ "Common", 0, 0, 0, 0 },
		-- Owner decision (10 Nov 2026): only Epic and above try to escape.
		{ "Uncommon", 0, 0, 0, 0 },
		{ "Rare", 0, 0, 0, 0 },
		{ "Epic", 4, 7, 1, 0.7 },
		{ "Legendary", 2, 4, 2, 0.7 },
		{ "Mythic", 2, 4, 2, 0.7 },
		{ "Celestial", 2, 4, 3, 0.8 },
		{ "Secret", 2, 4, 3, 0.8 },
	}
do
	escapes[row[1]] = frozen({ MinDelay = row[2], MaxDelay = row[3], MaxAttempts = row[4], WarningSeconds = row[5] })
end
escapes.Astral = escapes.Celestial
local fallback = {}
local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Celestial", "Secret" }
for _, row in
	{
		{ "REGION_BEACH", 70, 22, 6.7, 1.1, 0.18, 0.02, 0, 0 },
		{ "REGION_FOREST", 60, 28, 10, 1.75, 0.23, 0.02, 0, 0 },
		{ "REGION_SWAMP", 45, 32, 18, 4.3, 0.6, 0.1, 0, 0 },
		{ "REGION_JUNGLE", 30, 32, 28, 8.5, 1.3, 0.2, 0, 0 },
		{ "REGION_ARCTIC", 20, 28, 36, 13, 2.6, 0.38, 0.02, 0 },
		{ "REGION_VOLCANO", 12, 22, 38, 23, 4.3, 0.65, 0.05, 0 },
		{ "REGION_GLITCH", 8, 18, 36, 30, 6.8, 1.1, 0.1, 0 },
	}
do
	local weights = {}
	for i, id in order do
		weights[id] = row[i + 1]
	end
	fallback[row[1]] = frozen(weights)
end
return frozen({
	Enabled = Environment.MainGameplayEnabled or Environment.Name == "Development",
	BaseDamage = 1,
	HpByRarity = frozen({
		Common = 1,
		Uncommon = 1,
		Rare = 2,
		Epic = 3,
		Legendary = 4,
		Mythic = 6,
		Celestial = 8,
		Astral = 8,
		Secret = 10,
	}),
	RecaptureRestoresFullHp = true,
	RegenerateHp = false,
	MutationChance = 0.04,
	GroundSleepByRarity = frozen({
		Common = 12,
		Uncommon = 12,
		Rare = 10,
		Epic = 10,
		Legendary = 8,
		Mythic = 8,
		Celestial = 8,
		Astral = 8,
		Secret = 8,
	}),
	HpUi = frozen({
		WidthPixels = 64,
		HeightPixels = 6,
		BorderPixels = 1,
		RangeStuds = 100,
		MaximumLockRangeStuds = 125,
		TweenSeconds = 0.12,
		RefreshSeconds = 0.1,
		WakeWarningSeconds = 3,
	}),
	ResetPhaseEffect = frozen({ PopSeconds = 0.10, FadeSeconds = 0.70, CleanupSeconds = 1, MaximumSubstitutes = 42 }),
	RebirthPresentation = frozen({
		DurationSeconds = 7,
		SkipAfterSeconds = 1,
		Copies = frozen({
			High = 12,
			Medium = 6,
			Low = 3,
		}),
	}),
	EscapeByRarity = frozen(escapes),
	EscapeSampleSeconds = 0.05,
	EscapeRetrySeconds = 1,
	ResetPeriod = 300,
	ResetWarningSeconds = 60,
	ResetBuildSeconds = 30,
	ResetCriticalSeconds = 10,
	EmergenceSeconds = 0.6,
	SpawnConstructionInterval = 0.04,
	BurrowsPerRegion = 3,
	RegionFallbackWeights = frozen(fallback),
	MutationWeatherEnabled = false,
	LuckyMutationEnabled = false,
	BankBatchSeconds = 1.25,
	Presentation = frozen({
		MaxSkySequences = 1,
		MaxRifts = 3,
		MaxMeteors = 6,
		MaxBankCelebrations = 2,
		MaxDetailedGlows = 12,
		ParticleCaps = frozen({ High = 480, Medium = 240, Low = 120 }),
		BannerQueueCap = 8,
		BannerHoldSeconds = 3,
		BannerEntrySeconds = 0.15,
		BannerExitSeconds = 0.4,
		BannerGradientSeconds = 1.4,
		BannerWidth = 0.86,
		SpawnBurstSeconds = 0.2,
		EscapeTranslationMin = 0.05,
		EscapeTranslationMax = 0.15,
		EscapeRotationMin = 1,
		EscapeRotationMax = 3,
		EscapeHz = 8,
		EscapeCueSeconds = 2,
		JumpArcSeconds = 0.45,
		JumpArcRise = 1.5,
		FireworkHeight = 16,
		AudioDuckDb = 4,
		AudioDuckAttack = 0.15,
		AudioDuckRelease = 0.4,
	}),
})
