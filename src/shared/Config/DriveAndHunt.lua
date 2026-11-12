--!strict
-- Drive-and-Hunt (owner prompt v1.0, 12 Nov 2026). Input, presentation and cart
-- placement only: catching, HP, damage, prices, spawns, cargo, steal and chase
-- rules are untouched. The whole feature is behind FeatureFlags.DriveAndHuntV1Enabled;
-- each part below can also be switched off on its own.
local CartInputRegistry = require(script.Parent.CartInputRegistry)

return table.freeze({
	-- Sub-flags (only read while DriveAndHuntV1Enabled is true).
	GateLaunch = true,
	SwitchButton = true,
	AutoLock = true,
	ScoopFx = true,
	Hints = true,

	Gate = table.freeze({
		CheckHz = 10,
		-- Players further than this from the camp edge skip the footprint test.
		EdgeBand = 60,
		-- A crossing only counts this close to the edge (a teleport is not a walk-out).
		MaxCrossingDistance = 30,
		SeatExitQuietSeconds = 4,
		RepeatQuietSeconds = 3,
	}),

	Lanes = table.freeze({
		-- Candidate distances outside the camp edge, nearest first.
		Distances = table.freeze({ 12, 18, 24 }),
		Spacing = 40, -- studs between lanes along each camp edge
		EdgeInset = 24, -- keep lanes this far from the camp corners
		MaxSlopeDegrees = 20,
		ClearMargin = 2, -- studs added round the cart collider bounds
		-- Lanes considered at launch, nearest the crossing point first.
		LanesTried = 2,
	}),

	Call = table.freeze({
		Directions = 8,
		Distances = table.freeze({ 7, 10, 13 }),
		FallbackRadius = 30,
		CooldownSeconds = 5,
		MaxBoundsQueries = 27,
		NoRoomText = "No room for your cart here",
	}),

	HopOut = table.freeze({
		SeatedGraceSeconds = 0.3,
		SideDistance = 4, -- studs from the cart edge
		BodySize = Vector3.new(4, 5, 4),
	}),

	-- "You need to get out here" pulse (cheap heuristic, no pathfinding).
	Unreachable = table.freeze({
		CheckHz = 2,
		Radius = 60,
		HeightAboveCart = 6,
		RoofProbe = 30,
		PulseEverySeconds = 10,
	}),

	Fx = table.freeze({
		BeatSeconds = 0.25,
		PopScales = table.freeze({ 0.6, 1.08, 1 }),
		Particles = 12,
		ParticlesLow = 6,
		PopPartsMax = 40,
		BystanderRadius = 80,
		BystanderParticles = 6, -- other players' puffs, whatever the quality setting
		BystanderPuffInterval = 0.5, -- seconds between bystander puffs on one client
		-- Reusing the cart burst would spend the owner's burst capacity or add
		-- speed on top of Training, so the launch has no boost (see the CP-A report).
		BoostSeconds = 0,
	}),

	-- Auto-lock aiming (Part C). Read by Utility/HuntTargetSelector and AutoLockController.
	Lock = table.freeze({
		ScanHz = 10,
		MaxCandidates = 12,
		Weights = table.freeze({ distance = 1.0, facing = 1.2, alreadyHit = 1.5, rarity = 0.3 }),
		NotHitFactor = 0.6,
		RarityFloor = 0.6, -- a Common scores 0.6 on the rarity term, the top rarity 1.0
		MaxRarityRank = 8,
		StickyBonus = 1.6,
		HoldAfterShotSeconds = 1.2,
		LostSightGraceSeconds = 0.5,
		TapRadiusPixels = 60,
		TapMaxSeconds = 0.3,
		TapMaxDragPixels = 14,
		PointerConeDegrees = 12,
		MountedArcDegrees = 160,
		TurretDegreesPerSecond = 540,
		-- The server rejects a shot whose camera line and muzzle line diverge by more than
		-- 60 degrees (BrainrotSleepSystem MIN_FORWARD_AIM_DOT = 0.5); stay inside that.
		MinimumParallaxDot = 0.55,
		HitMemorySeconds = 12,
		SnapSeconds = 0.15,
		-- Aim line from the cart muzzle to the lock (stands in for a turret: carts have no
		-- launcher art), plus a brief flash at the muzzle on each mounted shot.
		AimLineWidth = 0.15,
		AimLineTransparency = 0.6,
		MuzzleFlashSeconds = 0.08,
		MuzzleFlashSize = 1.6,
	}),

	-- Scoop feedback (Part D).
	Scoop = table.freeze({
		-- Reach beyond the cart's edge: scoop distance = cart half-width + Reach from the
		-- centre line (was HuntFlow.ScoopRadius from the pivot). Vertical limit unchanged.
		Reach = 10, -- no cart reaches less than the old 13-stud pivot radius
		RingRadius = 45, -- sleeping brainrots this close to the driven cart get a ring
		MaxRings = 6,
		RingSegments = 16,
		RingSegmentsLow = 8,
		RingStuds = 4.5, -- ring radius on the ground
		RingScanHz = 4,
		RingPulseHz = 10,
		MagnetSeconds = 0.25,
		MagnetArcHeight = 3,
		MagnetEndScale = 0.4,
		PlusOneSeconds = 0.8,
		FullSeconds = 4, -- gold home arrow + beam after "Cargo full"
		-- Pickup sound: the existing S6 load cue (AudioController, on every own cargo load).
	}),

	-- First-time hints (Part E). Session-only: no onboarding storage exists and no
	-- profile field is added.
	HintToast = table.freeze({
		Seconds = 3,
		MaxQueued = 4,
		Text = table.freeze({
			Lock = "TAP TO SHOOT!",
			Sleep = "DRIVE OVER IT!",
			Scoop = "+1! Fill up, then drive home",
			HopOut = "HOP OUT to reach it",
			LoadAndGo = "LOAD & GO!",
		}),
	}),

	Request = table.freeze({
		MinimumIntervalSeconds = 0.2, -- server rate limit on the switch request
	}),

	-- No enter/exit key existed (entry is the E prompt, exit was jump). F is Burst
	-- and gamepad Y is Manage Team / Drop, so the switch uses free inputs.
	-- Registered in Config/CartInputRegistry (Switch) with the other cart controls.
	Input = table.freeze({
		Keyboard = CartInputRegistry.Switch.Keyboard,
		Gamepad = CartInputRegistry.Switch.Gamepad,
	}),

	Labels = table.freeze({
		Driving = "HOP OUT",
		OnFoot = "CART",
		Carrying = "LOAD & GO",
	}),
})
