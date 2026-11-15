--!strict
-- Core Loop V2 (14 Nov 2026, v5). Gated by FeatureFlags.CoreLoopV2Enabled. See the Core Loop V2 prompt
-- (docs/coreloop/2026-11/REPORT.md records every change to these defaults with its measured reason).
-- Every gameplay number lives here once; every Part L (look) number lives in CoreLoopFx.
return table.freeze({
	-- Part sub-flags. Each is ANDed with the master flag (see CoreLoopFlags).
	Flags = table.freeze({
		Herds = true,
		Stars = true,
		LuckyMeter = true,
		Pity = true,
		Combo = true,
		Temperaments = true,
		SpawnFx = true,
		MutationReveal = true,
		MutationRain = true,
		GuardedVillagers = true,
		Rush = true,
		FirstSession = true,
		LegacyRemoval = true,
		FxReviewGate = true,
	}),

	-- §3 Hunter: outside Camp, alive, not training, moved > ActiveMoveStuds in the last ActiveWindowSeconds.
	-- Present player (K4): any input in the last PresentInputSeconds.
	Hunter = table.freeze({
		ActiveMoveStuds = 20,
		ActiveWindowSeconds = 30,
		PresentInputSeconds = 300,
	}),

	-- A1 server budget. AdmissionCapScale multiplies BrainrotPopulation.ProfileAdmissionCaps (rounded up).
	Population = table.freeze({
		TargetWild = 64,
		HardCap = 72, -- includes sleeping / Saved
		PerRegionCap = 24,
		PerHunterAwakeCap = 10,
		PerHunterRadius = 160,
		ReservationsPerPass = 6,
		AdmissionCapScale = 1.5,
		DirectorHz = 4,
	}),

	-- A3/A4/A5 herd ordering, placement and size.
	Herd = table.freeze({
		ReorderAwakeAtMost = 1, -- re-order when <= this many awake unclaimed members within PerHunterRadius
		ReorderFarStuds = 180, -- or the herd centre is farther than this
		OrderCooldown = 4.0,
		PendingStarCooldown = 1.0, -- Lucky / pity Star pending
		MovingSpeed = 8,
		AheadMin = 70,
		AheadMax = 110,
		AheadSpreadDeg = 40,
		StillMin = 55,
		StillMax = 85,
		StillSpreadDeg = 90,
		Attempts = 8,
		MinPlayerDistance = 45,
		MinPadDistance = 20,
		MaxSlopeDeg = 25,
		MemberRingMin = 5,
		MemberRingMax = 12,
		MemberSpacing = 6,
		MinValidMembers = 2,
		GuardZoneRadius = 110,
		VillageChance = 0.5,
		VillageMinHomeDistance = 30,
		WildSizes = table.freeze({ [3] = 0.30, [4] = 0.45, [5] = 0.25 }),
		VillageSizes = table.freeze({ [4] = 0.35, [5] = 0.40, [6] = 0.25 }),
	}),

	-- Part B. Draws = best-of-N tier draws; MutationMult multiplies the 4% base (clamped by Mutation.Cap).
	Star = table.freeze({
		Draws = table.freeze({
			Wild = 2,
			Village = 3,
			RushWild = 3,
			RushVillage = 4,
			MegaWild = 4,
			MegaVillage = 5,
		}),
		MutationMult = table.freeze({
			Wild = 2,
			Village = 3,
			RushWild = 3,
			RushVillage = 4,
			MegaWild = 4,
			MegaVillage = 5,
		}),
		SuperMultiple = 2.9,
		JackpotMultiple = 7.0,
		OwnerExclusiveSeconds = 20,
		LifeSeconds = 120,
		LeavingWarnSeconds = 20,
		SeenRadius = 150,
		SeenConeDeg = 75,
		MaxPillars = 6,
		MaxSkyBeams = 3,
		OtherPlayersTransparency = 0.5,
		LuckyRerollCap = 500,
		JackpotRerollCap = 5000,
	}),

	-- A6.
	Loners = table.freeze({
		PerHunter = 2,
		RushPerHunter = 3,
		Min = 90,
		Max = 160,
		SpreadDeg = 100,
		FarStuds = 230,
		FarSeconds = 8,
	}),

	-- A7 DespawnPolicy.
	Despawn = table.freeze({
		ProtectRadius = 150,
		RecentHitSeconds = 8,
		UnseenSeconds = 8,
		AmbientUnseenSeconds = 20,
		SavedRadius = 30,
		SavedExtraSleep = 45,
		SavedMaxStars = 1,
		SavedMaxSnacks = 2,
		DiveSeconds = 1.2,
		DiveWalkStuds = 15,
	}),

	-- C1 Lucky Meter gains (session-only).
	Meter = table.freeze({
		-- C-1 tuning (14 Nov 2026, allowed by C1 "tune only this table"): the prompt's gains filled the meter
		-- every 35 s (median) for a SimHunter at 16.3 KO/min, against a 3-4 min target. Gains are divided by ~3
		-- (prompt values: 3 / 8 / 12 / 0 / 4 / 8 / 12). Multipliers below are unchanged.
		Max = 100,
		Snack = 1,
		Star = 3,
		Super = 4,
		Jackpot = 0,
		SneakShot = 1,
		Sneaky = 3,
		CleanEscape = 4,
		ComboDoubleAt = 3,
		RushMult = 1.5,
		FirstSessionMult = 2,
		LuckyStarDelay = 1.0,
		PulseAt = 80,
	}),

	-- C3 hard pity, in hunting seconds.
	Pity = table.freeze({
		SuperSeconds = 300,
		JackpotSeconds = 900,
		MutationSeconds = 180,
		MutationPityShares = table.freeze({ Shiny = 0.7, Golden = 0.3 }),
	}),

	-- D1 (meter-only; no Cash or Gems).
	Combo = table.freeze({
		WindowSeconds = 4.0,
		Cap = 6,
		MagnetAt = 4,
		MagnetRadius = 22,
		MagnetInterval = 0.25,
		UpdateRateHz = 10,
	}),

	-- D2 maxima (seconds / shake trauma / FOV degrees).
	Juice = table.freeze({
		HitFreeze = 0.04,
		KoFreeze = 0.06,
		StarFreeze = 0.09,
		SuperFreeze = 0.12,
		JackpotCeremony = 0.6,
		RevealFreeze = 0.3,
		KoFlash = 0.08,
		StarShake = 0.25,
		SuperShake = 0.35,
		JackpotShake = 0.5,
		StarFov = -3,
		SuperFov = -4,
		JackpotFov = -6,
		TextSeconds = 1.2,
		RevealTextSeconds = 1.6,
		ComboPopSeconds = 0.18,
	}),

	-- Part E temperaments (speeds in studs/s, pass through the E6 clamps).
	Behaviour = table.freeze({
		CalmSpeed = 6,
		CalmTurnDegPerSec = 140,
		NoticeFactor = 1.2,
		NoticeTurnSeconds = 0.4,
		TelegraphSeconds = 0.4,
		CartLoudFactor = 1.25,
		CartLoudSpeed = 20,
		SlowFootFactor = 0.6,
		SlowFootSpeed = 10,
		BehindFactor = 0.5,
		FrontConeDeg = 120,
		WaryFactor = 1.5,
		WarySeconds = 10,
		StarAwarenessFactor = 0.8,
		MutatedAwarenessFactor = 1.15,
		SneakWindowSeconds = 3,
		StaggerFactor = 0.5,
		StaggerSeconds = 0.6,
		GroggySeconds = 1.0,
		ExhaustedSeconds = 4,
		MaxFleeSecondsPerEncounter = 10,
		EncounterResetSeconds = 20,
		FleeClampOfHunter = 0.85,
		MaxBoltStuds = 25,
		ShowoffBoltStuds = 30,
		MaxFromCentre = 60,
		OffscreenStopSeconds = 2,
		MaxDropStuds = 6,
		Herd = table.freeze({
			SeparationRadius = 5,
			SeparationWeight = 1.0,
			CohesionWeight = 0.35,
			Leash = 18,
			AlignmentWeight = 0.25,
			CentreDrift = 1.2,
			StarFromCentre = 8,
			NearHz = 10,
			FarHz = 2,
			ScatterRadius = 25,
			ScatterSeconds = 1.5,
			ScatterStuds = 15,
			ScatterPause = 2.5,
			ScatterRepeat = 6,
			DocileScatterSpeed = 9,
		}),
		Curious = table.freeze({
			ApproachChance = 0.6,
			ApproachStuds = 4,
			Flee = 12,
			BoltSeconds = 1.2,
			BoltStuds = 15,
			ArcDeg = 35,
			RestMin = 1.5,
			RestMax = 2.5,
			MaxBolts = 2,
		}),
		Sprinter = table.freeze({
			Flee = 10,
			Burst = 18,
			BurstSeconds = 1.2,
			Recovery = 4,
			RecoverySeconds = 2.0,
			Cooldown = 3.0,
			MaxBolts = 3,
		}),
		Zigzag = table.freeze({
			Flee = 14,
			SweepSeconds = 0.8,
			StraightSeconds = 0.6,
			SweepDeg = 30,
			Rest = 1.5,
			MaxBolts = 3,
		}),
		Camo = table.freeze({ Flee = 12, MaxBolts = 3 }),
		Showoff = table.freeze({
			Opening = 16,
			OpeningSeconds = 3,
			ZigzagCycles = 2,
			Burst = 20,
			BurstSeconds = 1.0,
			Rest = 1.5,
			MaxBolts = 4,
			TauntCooldown = 6,
			TauntRadius = 30,
		}),
		TierFallback = table.freeze({
			Common = "Docile",
			Uncommon = "Curious",
			Rare = "Sprinter",
			Epic = "Zigzag",
			Legendary = "LegendaryPursuit",
			Mythic = "LegendaryPursuit",
		}),
	}),

	-- Part G: who triggers villagers and how many chase. Speeds/rings/tags are unchanged.
	Guard = table.freeze({
		KeeperSearchRadius = 150,
		StrollSpeed = 6,
		WatchPointStuds = 12,
		NoticeRadius = 55,
		CalmRadius = 90,
		CalmSeconds = 20,
		SuperExtraRadius = 200,
		JackpotRadius = 250,
		MaxChasesPerPlayer = 1,
	}),

	-- Part H: replaces the reset cycle and the rare wave. Never changes Phase12CycleId.
	Rush = table.freeze({
		CycleSeconds = 300,
		RushSeconds = 60,
		MegaEvery = 3,
		MegaSeconds = 90,
		WarnSeconds = 60,
		CountdownSeconds = 10,
		ReorderAwakeAtMost = 2,
		OrderCooldown = 2.0,
		MegaOrderCooldown = 1.5,
		MegaLuckyStarMinSeconds = 30,
		AnnounceCooldown = 60,
		AnnounceQueue = 2,
		RainAnnounceCooldown = 20,
	}),

	-- Part K. One mutation per individual; catalogue shares and multipliers unchanged.
	Mutation = table.freeze({
		Base = 0.04,
		Cap = 0.30,
		SnackMult = 1,
		RushSnackMult = 1.5,
		MegaSnackMult = 2,
		MegaRareShareMult = 2, -- Radioactive + Astral shares x2 inside a MEGA roll, renormalised
		Rain = table.freeze({
			StrikesPerMega = 1,
			EveryNthMega = 1,
			Shares = table.freeze({ Shiny = 0.80, Golden = 0.18, Glitched = 0.02 }),
			BeamSeconds = 1.0,
		}),
		ShimmerParticles = 6,
		ShimmerParticlesLow = 3,
		ShimmerBobSeconds = 1.6,
	}),

	-- Part I.
	FirstSession = table.freeze({
		MaxSeconds = 1800,
		StarterLaneRadius = 80,
		StarterDocileSeconds = 60,
		NoVillagersUntilFirstBank = true,
		VillageSearchStuds = 300,
		MeterMult = 2,
		SuperPity = 150,
		JackpotPity = 600,
		MutationPity = 90,
		StarterStar = "BRT_019",
		StarterUncommon = table.freeze({ "BRT_011", "BRT_013" }),
		FirstLuckyStar = table.freeze({ species = "BRT_019", mutation = "Golden" }),
	}),

	-- Part F timing; the full look lives in CoreLoopFx (Part L).
	Fx = table.freeze({
		PopStagger = 0.10,
		PopSeconds = 0.35,
		PopParticles = 10,
		PopParticlesLow = 5,
		MaxPopsAtOnce = 3,
		MeteorSeconds = 1.2,
		MeteorShakeRadius = 80,
		RiftSeconds = 1.5,
	}),

	-- C4 lever (b): owner approved x4.33 on 14 Nov 2026 (sim factor for an 80 s nominal trip; revise after
	-- real trips are measured). Applied by CoreLoop/PriceCurve only while Core Loop V2 is on.
	Economy = table.freeze({ PriceCurveFactor = 4.33 }),
})
