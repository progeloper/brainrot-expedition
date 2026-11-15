--!strict
-- Core Loop V2, Part L numbers (look). CP-A skeleton: the sections used so far are filled, the rest
-- are declared with the Part L values and filled as each checkpoint builds them. Colours come from
-- Theme.CoreLoop / Theme.Rarity / Theme.Mutation (L1); sizes are px at the 844x390 baseline.
-- Source comments name the mockup board each value was read from
-- (docs/coreloop/2026-11/reference/mockups/*.dc.html, version 1794638921-2618).
-- Review gate (L6): a group renders only its plain fallback (shape + colour + text + sound) until it is
-- listed in Approved (mirrors docs/coreloop/2026-11/FX_APPROVALS.md).
return table.freeze({
	Approved = table.freeze({
		Group1_Hud = false,
		Group2_StarKit = true, -- owner approved 15 Nov 2026 (FX_APPROVALS.md)
		Group3_Arrivals = true, -- owner approved 15 Nov 2026 (FX_APPROVALS.md)
		Group4_Mutations = true, -- owner approved 15 Nov 2026 (FX_APPROVALS.md)
		Group5_Behaviour = false,
		Group6_Atmosphere = false,
	}),

	-- L3.2 / L3.3 pillars (the 3D build follows Part L; boards 1 and 3 give colour and proportion only).
	L3_2_Pillar = table.freeze({
		Star = table.freeze({
			Height = 40,
			Width = 2.5,
			Transparency = 0.35,
			PulseSeconds = 1.2,
			DrawDistance = 200,
			DrawDistanceLow = 150,
		}),
		Super = table.freeze({
			Height = 70,
			Width = 3.5,
			Transparency = 0.35,
			ScrollTilesPerSecond = 0.6,
			DrawDistance = 300,
			DrawDistanceLow = 200,
		}),
		DropFromHeight = 120,
		DropSeconds = 0.5,
		BaseRingRadius = table.freeze({ Star = 4, Super = 6 }),
		GuardedRingRadius = 7,
		GuardedRingDegPerSecond = 30,
		OtherPlayersExtraTransparency = 0.5,
	}),
	L3_3_SkyBeam = table.freeze({
		Height = 300,
		Width = 6,
		OuterWidth = 9,
		OuterTransparency = 0.4,
		CrownStars = 3,
		CrownSize = 3,
		CrownDegPerSecond = 40,
		BaseRingRadius = 10,
		LightBrightness = 3,
		LightRange = 24,
	}),

	-- L4.3 RUSH chip — RushStates.dc.html + Main.dc.html.
	L4_3_Rush = table.freeze({
		-- Main.dc.html: chip 220x44 pill, top 8 px, centred; lightning 22 px; Luckiest Guy 20 px.
		ChipSize = Vector2.new(220, 44),
		ChipTop = 8,
		IconPx = 22,
		LabelPx = 20,
		-- RushStates.dc.html: MEGA warning label 17 px; active chip 220x52 / MEGA 240x52 with a 170 / 190 x 6
		-- px draining strip; MEGA subline "RARE MUTATIONS ×2!" Fredoka 14 px in #ffd447.
		MegaLabelPx = 17,
		ActiveSize = Vector2.new(220, 52),
		MegaActiveSize = Vector2.new(240, 52),
		ActiveLabelPx = 20,
		MegaActiveLabelPx = 18,
		StripSize = Vector2.new(170, 6),
		MegaStripSize = Vector2.new(190, 6),
		SublinePx = 14,
		-- RushStates.dc.html: countdown 120 px ring (#ff3d9e conic), 100 px ink disc #1d2133cc, digit 72 px
		-- #ffe14a, 6 px stroke. Prompt L4.3 says 96 px; proportion is the mockup's call (L7.5).
		CountdownRing = 120,
		CountdownDisc = 100,
		CountdownDigitPx = 72,
		CountdownStroke = 6,
		CountdownTickScale = 1.4,
		CountdownTickSeconds = 0.2,
		BobPx = 3,
		BobSeconds = 1.6,
		Copy = table.freeze({
			Warning = "RUSH IN %d:%02d",
			MegaWarning = "MEGA RUSH IN %d:%02d",
			Active = "RUSH! %d:%02d",
			MegaActive = "MEGA RUSH! %d:%02d",
			MegaSubline = "RARE MUTATIONS ×2!",
		}),
	}),

	-- L5 sound cues -> fallback AudioCatalog ids until the CL_* sounds are made and uploaded ("" = silent).
	L5_Cues = table.freeze({
		CL_POP = "S6_1",
		CL_STAR_DROP = "J2",
		CL_METEOR = "BOOM_L",
		CL_RIFT = "BOOM_X",
		CL_DIVE = "S4",
		CL_LEAVING_TICK = "U1_1",
		CL_SHIMMER = "",
		CL_REVEAL_ROLL = "",
		CL_ALERT = "J7",
		CL_COMBO_END = "J15",
		CL_RUSH_TICK = "U1_2",
		CL_RUSH_START = "J8",
		CL_RUSH_END = "J9",
		CL_RAIN_STRIKE = "ST3",
		CL_METER_FULL = "J6",
		CL_SNEAK = "J11",
		CL_NOT_YOURS = "U1_3",
		CL_TAUNT = "",
		-- D2 ladder / jingles (existing ids)
		S1 = "S1_1", -- hit ladder S1_1..S1_8
		S3 = "S3_1",
		J2 = "J2",
		J3 = "J3",
		J4 = "J4",
		J5a = "J5a", -- J5a..J5e by mutation
		BOOM_L = "BOOM_L",
		BOOM_X = "BOOM_X",
	}),

	-- L2 uploaded asset ids. Empty = the documented fallback is live (assets/coreloop_fx/UPLOAD_CHECKLIST.md).
	L2_Assets = table.freeze({
		CL_StudChunk = "",
		CL_Dust = "",
		CL_Crack = "",
		CL_Ring = "",
		CL_BeamStud = "",
		CL_BeamSparkle = "",
		CL_Spiral = "",
		CL_Bolt = "",
		CL_Confetti = "",
		CL_Star4 = "",
		CL_Zzz = "",
		CL_Sweat = "",
		CL_DizzyStar = "",
		CL_IconRush = "",
	}),

	-- L3 world FX numbers (Part L text; boards 1/3 give colour + proportion only).
	L3_1_Pop = table.freeze({
		Stagger = 0.10,
		Seconds = 0.35,
		ScaleFrom = 0.2,
		ScaleOver = 1.15,
		Chunks = 10,
		ChunksLow = 5,
		Dust = 6,
		DustLow = 3,
		FlashRingTo = 5,
		FlashRingSeconds = 0.3,
		LightBrightness = 2,
		LightRange = 10,
	}),
	L3_4_Meteor = table.freeze({
		StreakSeconds = 1.2,
		FromHeight = 400,
		AngleDeg = 35,
		ImpactRing = 12,
		ImpactSeconds = 0.4,
		Chunks = 24,
		ChunksLow = 8,
		Dust = 10,
		DustLow = 4,
		ShakeRadius = 80,
		SmokeSeconds = 4.75,
	}),
	L3_5_Rift = table.freeze({ TearSeconds = 1.5, TearHeight = 60, TearSize = 30, SlamSeconds = 0.2, Confetti = 40, ConfettiLow = 12 }),
	L3_6_Dive = table.freeze({ Seconds = 1.2, Squash = 0.75, Hop = 3, HopSeconds = 0.25, SinkSeconds = 0.5, Dust = 8, DustLow = 3 }),
	L3_7_Ko = table.freeze({
		HitFlash = 0.06,
		HitSparks = 4,
		HitSparksLow = 2,
		KoFlash = 0.08,
		KoDust = 6,
		KoDustLow = 2,
		StarFlash = 0.12,
		SuperFlash = 0.15,
		StarRingTo = 9,
		StarSparks = 16,
		SuperSparks = 24,
		StarSparksLow = 6,
	}),
	L3_8_Shimmer = table.freeze({ Rate = 3, RateLow = 1.5, Outline = 0.75, OutlinePulse = 0.45, PulseSeconds = 1.6 }),
	L3_9_Reveal = table.freeze({
		Freeze = 0.3,
		Burst = 30,
		BurstLow = 10,
		RingTo = 14,
		RaysSeconds = 1.6,
		ShoutPx = 48,
		GemStickerDelay = 0.2,
		UpgradeDelay = 0.3,
		UpgradeGrowSeconds = 0.5,
	}),
	-- L3.12 Mutation Rain strike (K4): cloud gathers, bolt strikes, recolour, lingering sparkles.
	L3_12_Rain = table.freeze({
		CloudHeight = 40,
		CloudSize = 14,
		GatherSeconds = 0.5,
		BoltBeams = 3,
		BoltBeamsLow = 1,
		BoltWidth = 2.5,
		BoltFlickers = 3,
		BoltSeconds = 0.1,
		FlashRingTo = 10,
		BurstScale = 0.7,
		SparkleRate = 6,
		SparkleSeconds = 2.4,
		VisibleStuds = 150,
		CountUpSeconds = 0.6,
	}),
	L4_2_Combo = table.freeze({
		OffsetFromReticle = Vector2.new(90, -60),
		Px = 44,
		Px6 = 56,
		Ring = 78,
		Disc = 66,
		PopSeconds = 0.18,
		EndSeconds = 1.0,
		Colours = table.freeze({ "#FFFFFF", "#FFFFFF", "#FFE14A", "#FF8A2A", "#FF3D9E", "rainbow" }),
	}),
	L4_1_Meter = table.freeze({
		Badge = 34,
		Bar = Vector2.new(260, 26),
		GapUnderCash = 8,
		LabelPx = 14,
		FloatySeconds = 0.6,
		FillSeconds = 0.25,
		PulseAt = 80,
		PulseScale = 1.04,
		PulseSeconds = 0.8,
		FullSeconds = 1.5,
		HideBelowPercent = 4,
	}),
})
