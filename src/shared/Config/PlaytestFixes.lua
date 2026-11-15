--!strict
-- Playtest Fixes v1 (owner playtest, 12 Nov 2026). Presentation, placement and layout only: no HP,
-- damage, fire-rate, range, price, Training XP, odds, CPS, cargo, carry/steal or persistence numbers
-- live here. Every tunable number for the six parts lives in this table.
--
-- Gating: FeatureFlags.PlaytestFixesV1Enabled (default false) AND the part's sub-flag below. See
-- Config/PlaytestFixesFlags. Part A (MapStuds) is an Edit-mode authoring change to the stored V5 world;
-- tools/terrain/BuildWorld.edit.luau reads MapStuds here, and scripts/RevertMapStuds.server.lua undoes it.

local Rarity = {
	Common = 1.55,
	Uncommon = 1.65,
	Rare = 1.75,
	Epic = 1.90,
	Legendary = 2.05,
	Mythic = 2.20,
	Celestial = 2.30, -- not in the prompt's table; placed between Mythic and Secret (owner to confirm)
	Secret = 2.40,
}

return table.freeze({
	Version = "PTF1_20261113",

	-- Sub-flags (each still needs the master flag at runtime).
	Parts = table.freeze({
		MapStuds = true,
		StallPoses = true,
		WeaponFx = true,
		TrainPlace = true,
		SizeLadder = true,
		GemsStall = true,
	}),

	-- Part A ---------------------------------------------------------------------------------------
	MapStuds = table.freeze({
		Variant = "Environment_Saved_Studs_13719188279",
		VariantBaseMaterial = "Glacier",
		-- Materials that receive the variant.
		Materials = table.freeze({ "SmoothPlastic", "Plastic", "Glacier" }),
		MaxTransparency = 0.3,
		-- Parts smaller than this on two (or more) axes are trim and keep their look.
		MinReadableAxis = 0.6,
		-- Kits whose glow parts are never studded (they are Neon anyway; listed for safety).
		ExcludedKits = table.freeze({ "Lane_GlowTiles", "Volcano_LavaStrip" }),
		-- The old 0.8-transparent overlay Textures this replaces.
		LegacyTextureAsset = "rbxassetid://126387978066468",
		BackupAttributePrefix = "StudMigrationOriginal",
	}),

	-- Part B ---------------------------------------------------------------------------------------
	StallPoses = table.freeze({
		-- Displays in CodeAssets.WeaponDisplays are authored at 1.5x held size (measured 13 Nov).
		AuthoredMultiplier = 1.5,
		TargetMultiplier = 1.5, -- decisions doc: rack/wall displays at 1.5x held size
		MinMultiplier = 1.2, -- never squash below this; report instead
		OverrunTolerance = 0.05, -- shrink only when the weapon overruns the rail by more than 5%
		WallLeanDegrees = 12, -- all three wall slots lean back by this much
		AssertDot = 0.9, -- slot customer-facing check
		AssertLeanToleranceDegrees = 3,
		-- Gap between a slot line and its backing board (studs). The display's back is kept clear of it.
		BoardClearance = table.freeze({ Rack = 0.6, Wall = 1.0, Medal = 0 }),
		-- Usable rail lengths (studs), measured from the stall geometry: rack boards are 8.27 between
		-- posts; each wall slot owns a third of the 14.3-stud pegboard.
		-- Wall: two slots split the 14.3-stud pegboard (owner 13 Nov), 7.0 usable each.
		RailLength = table.freeze({ Rack = 8.2, Wall = 7.0 }),
		-- Owner 13 Nov: two weapons per rack board, a random few (not every weapon). Rows are heights
		-- above the stall pivot; each row's weapon fits within RowHeight (same 1.2x floor).
		RackRows = table.freeze({
			RackSlot_1 = 6.15, -- left board as seen from the front (x 54.7), top
			RackSlot_2 = 2.75, -- left board, bottom
			RackSlot_4 = 6.15, -- right board (x 29.3), top
			RackSlot_5 = 2.75, -- right board, bottom
		}),
		InactiveRackSlots = table.freeze({ "RackSlot_3", "RackSlot_6" }),
		RowHeight = 3.4,
		-- Owner 13 Nov: two weapons on the back wall. Offsets (studs) along the rail from the stall
		-- pivot, positive = customer's left. WallSlot_3 is unused while the flag is on.
		WallSlots = table.freeze({ WallSlot_1 = 3.575, WallSlot_2 = -3.575 }),
		InactiveWallSlots = table.freeze({ "WallSlot_3" }),
		-- Family pose rules in the slot frame. Axis names are the display model's own axes.
		--   along: model axis laid along the rail; its NEGATIVE end points to the customer's left
		--          (slot LookVector) when alongSign = 1 (muzzle/prod = model -Z for guns and crossbows).
		--   face:  model axis pointing at the customer (side profile / flat side).
		--   tilt:  degrees the weapon leans back around the rail axis.
		-- "largest"/"smallest" are measured from each display's bounding box. Crossbows use the stock
		-- (model Z) and side (model X) directly: on 8 of 10 crossbows the prod span is the largest axis.
		Families = table.freeze({
			Bow = table.freeze({ along = "largest", face = "smallest", tilt = 0, upSign = 1 }),
			Gun = table.freeze({ along = "largest", face = "smallest", tilt = 0 }),
			Crossbow = table.freeze({ along = "Z", face = "X", tilt = 10 }), -- 25 hung below the board
			Lance = table.freeze({ along = "largest", face = "X", tilt = 0 }),
		}),
		-- Family by weapon id where the display's Family attribute is not the display family.
		FamilyOverrides = table.freeze({
			WPN_SP_CRYSTALLANCE = "Lance",
			WPN_SP_PRISMREPEATER = "Gun", -- display says Crossbow; the decisions doc poses it as a blaster
		}),
		-- Per-id axis overrides (measured outliers; see docs/playtest_fixes/display_axes.md).
		AxisOverrides = table.freeze({
			WPN_B07 = table.freeze({ face = "X" }), -- moon ornaments make X wider than the draw depth
			WPN_G07 = table.freeze({ along = "Z", face = "X" }), -- eclipse ring is taller than the barrel
			WPN_SP_PRISMREPEATER = table.freeze({ face = "X" }), -- drum is wider than it is tall
		} :: { [string]: any }),
	}),

	-- Part C (CP-B) --------------------------------------------------------------------------------
	WeaponFx = table.freeze({
		DisplayCullRadius = 60,
		-- Prompt caps per effect. The per-tier ladder below stays inside them AND inside the per-shot
		-- budget (the caps alone would add up to 28 on High, over the 16-particle shot budget).
		Counts = table.freeze({
			MuzzleFlash = table.freeze({ High = 8, Low = 4 }),
			ImpactBurst = table.freeze({ High = 14, Low = 7 }),
			SleepPuff = table.freeze({ High = 6, Low = 3 }),
		}),
		MaxBurstParticlesPerShot = table.freeze({ High = 16, Low = 8 }),
		-- Held-weapon idle budgets (emitters, total Rate). T7 keeps its authored set.
		Budgets = table.freeze({
			Low = table.freeze({ maxEmitters = 2, maxRate = 10 }), -- T1-T4
			Mid = table.freeze({ maxEmitters = 3, maxRate = 20 }), -- T5-T6
			Top = table.freeze({ maxEmitters = 6, maxRate = 40 }), -- T8 and specials
		}),
		AuraMaxRate = 6,
		PoolSize = 4, -- rigs per pooled effect (no instance creation per shot after warm-up)
		-- Engine-built particle textures (no uploads). Gaps: a "Z" sprite (text is used) and a rift-crack
		-- decal (implosion texture is used) are owner uploads if wanted.
		Textures = table.freeze({
			Spark = "rbxasset://textures/particles/sparkles_main.dds",
			Smoke = "rbxasset://textures/particles/smoke_main.dds",
			Flash = "rbxasset://textures/particles/explosion01_core_main.dds",
			Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
			Implode = "rbxasset://textures/particles/explosion01_implosion_main.dds",
			Fire = "rbxasset://textures/particles/fire_sparks_main.dds",
		}),
		-- Tier colours follow the brainrot rarity ladder (Theme.Rarity); T5 crimson, T6 icy cyan,
		-- T7 black with a pale halo, T8 rainbow.
		TierColours = table.freeze({
			"#E3EAF3",
			"#72E65B",
			"#46A7FF",
			"#B86CFF",
			"#E3173E",
			"#6DEBFF",
			"#141018",
			"#FFFFFF",
		}),
		HaloColour = "#E8E4FF", -- T7 pale halo
		Rainbow = table.freeze({ "#FF3B3B", "#FFAE3D", "#FFE14A", "#5BE36B", "#46A7FF", "#B86CFF" }),
		-- Ladder: each tier includes the beats of the tiers before it (counts are High; Low halves).
		--   flash  muzzle flash particle    muzzle  muzzle sparks       ring   expanding muzzle ring
		--   shock  shockwave                trail   width/lifetime      sparkle trail sparkles
		--   core   Beam core (T5+)          ghosts  T8 afterimages      impact  hit sparks
		--   ground ground/eclipse ring       crack   T8 rift crack       puff/puffText sleep puff
		Tiers = table.freeze({
			table.freeze({
				flash = 1,
				muzzle = 3,
				impact = 4,
				puff = 1,
				puffText = "Z",
				trailWidth = 0.18,
				trailLife = 0.12,
			}),
			table.freeze({
				flash = 1,
				muzzle = 4,
				impact = 5,
				puff = 1,
				puffText = "Z",
				trailWidth = 0.22,
				trailLife = 0.14,
			}),
			table.freeze({
				flash = 1,
				muzzle = 4,
				ring = 1,
				impact = 6,
				puff = 3,
				puffText = "Zzz",
				trailWidth = 0.28,
				trailLife = 0.18,
				sparkle = true,
			}),
			table.freeze({
				flash = 1,
				muzzle = 4,
				ring = 1,
				impact = 6,
				puff = 3,
				puffText = "Zzz",
				trailWidth = 0.32,
				trailLife = 0.2,
				sparkle = true,
			}),
			table.freeze({
				flash = 1,
				muzzle = 4,
				ring = 1,
				shock = 1,
				impact = 6,
				ground = 1,
				puff = 2,
				puffText = "Zzz",
				trailWidth = 0.36,
				trailLife = 0.24,
				sparkle = true,
				core = true,
			}),
			table.freeze({
				flash = 1,
				muzzle = 4,
				ring = 1,
				shock = 1,
				impact = 6,
				ground = 1,
				puff = 2,
				puffText = "Zzz",
				trailWidth = 0.4,
				trailLife = 0.26,
				sparkle = true,
				core = true,
			}),
			table.freeze({
				flash = 1,
				muzzle = 3,
				ring = 1,
				shock = 1,
				impact = 6,
				ground = 1,
				puff = 2,
				puffText = "Zzz",
				trailWidth = 0.42,
				trailLife = 0.28,
				sparkle = true,
				core = true,
				dark = true,
			}),
			table.freeze({
				flash = 1,
				muzzle = 3,
				ring = 1,
				shock = 1,
				impact = 5,
				ground = 1,
				crack = 1,
				puff = 3,
				puffText = "Zzz",
				trailWidth = 0.46,
				trailLife = 0.3,
				sparkle = true,
				core = true,
				ghosts = 2,
				rainbow = true,
			}),
		}),
		-- Authored idle/signature effects added to a weapon's existing V4 parts (held art and stall
		-- displays). `part` is the first part with that name; kinds are built by WeaponFxLibrary.
		Authored = table.freeze({
			WPN_B06 = table.freeze({
				{ part = "FloatIce", kind = "FrostMist" },
				{ part = "CrownFlakeGlowHub", kind = "CyanSparkle" },
			}),
			WPN_C06 = table.freeze({
				{ part = "FloatIceCore", kind = "FrostMist" },
				{ part = "ProdMountGem", kind = "CyanSparkle" },
			}),
			WPN_G06 = table.freeze({
				{ part = "CoreCrystalCore", kind = "FrostMist" },
				{ part = "MuzzleOrb", kind = "CyanSparkle" },
			}),
			WPN_SP_RIFTBLASTER = table.freeze({
				{ part = "MuzzleGlow", kind = "RiftTear" },
				{ part = "RiftCore", kind = "VioletSparks" },
			}),
			WPN_SP_PRISMREPEATER = table.freeze({ { part = "DrumAxle", kind = "SpectrumSplit" } }),
			WPN_SP_CRYSTALLANCE = table.freeze({
				{ part = "LanceCollar", kind = "OrbitShards" },
				{ part = "LanceTip", kind = "FrostTrail" },
			}),
			WPN_SP_COLLECTORSBOW = table.freeze({ { part = "StringGlow", kind = "GoldSparkle" } }),
		}),
		-- T5-T6 idle aura (one slow emitter) for ladder weapons with no idle emitter of their own.
		AuraTiers = table.freeze({ [5] = true, [6] = true }),
		OrbitShards = table.freeze({ Count = 4, Radius = 1.1, SpinDegreesPerSecond = 90 }),
	}),

	-- Part D (CP-C) --------------------------------------------------------------------------------
	TrainPlace = table.freeze({
		ExtraActivationDistance = 6,
		CameraEaseSeconds = 0.35,
		MaxSecondsToSeat = 0.5,
		OthersTransparency = 0.5,
		MaxXpPops = 4,
		CollisionGroup = "TrainingCarts",
		DeckLift = 0.1, -- studs above the highest deck surface under the cart (rails sit above the deck)
		-- Camera 3/4 view after the pop: offset from the cart (cart space) and how long it holds.
		CameraOffset = Vector3.new(-14, 9, 16),
		CameraHoldSeconds = 1.1,
		Messages = table.freeze({
			TrainingOff = "Training is closed right now",
			AlreadyTraining = "You're already training",
			NotLiving = "Respawn first",
			TooFar = "Get closer to the Training stall",
			Dazed = "You're dazed - wait a moment",
			Busy = "Close your menu first",
			Carrying = "Drop your brainrot first",
			NoCart = "Your cart isn't ready yet",
			CartOccupied = "Someone is riding your cart",
			NoBay = "Training stall not found",
			DeckBlocked = "Someone is standing on the rollers",
		}),
	}),

	-- Part E (CP-C) --------------------------------------------------------------------------------
	SizeLadder = table.freeze({
		HeightByRarity = table.freeze(Rarity),
		SlotFootprint = table.freeze({ Width = 10.2, Depth = 13.9 }),
		SlotMargin = 0.92,
		FloorHeight = 6.706, -- today's canonical height; carried/cargo keep it, base displays never go below
		CatchPop = table.freeze({ From = 0.7, Peak = 1.12, Seconds = 0.3 }),
		FirstSightingRadius = 80,
		CameraNudgeSeconds = 0.2,
	}),

	-- Part F (CP-B concept, CP-D placement) ----------------------------------------------------------
	GemsStall = table.freeze({
		Purple = "#8A3DFF",
		Cyan = "#2EE9FF",
		PromptObjectText = "GEMS",
		PromptActionText = "Open",
		PromptDistance = 12,
		ModelName = "Kiosk_GemsStall",
		NewsModelName = "Kiosk_AnnouncementStall",
		-- Main street (owner, 12 Nov): between Sell (x -150) and Training (x -92) on the centre line,
		-- customer front (LookVector) facing the north row like Training. Measured footprints leave
		-- 12.0 studs to Sell and 13.0 to Training (spacing rule 12); Weapons-Carts has only 23 free studs.
		-- Placed by tools/playtest_fixes/PlaceGemsStall.edit.luau; hidden at runtime while the flag is off.
		Placement = table.freeze({ x = -121.4, z = -46, yawDegrees = 0 }),
		SparkleRate = 4,
		GlowPulseHz = 0.5,
		MaxParts = 120,
	}),
	-- Owner-editable NEWS board text (read-only SurfaceGui panel on the NEWS kiosk; no prompt, no window).
	NewsBoard = table.freeze({
		Headline = "Playtest update!",
		Line = "Bigger brainrots, flashier weapons and a new Gems stall.",
		Footer = "Codes → Settings",
		PixelsPerStud = 40,
		PanelSize = Vector2.new(9, 5), -- studs (width, height)
		PanelCentreHeight = 6.5, -- studs above the kiosk floor
	}),
})
