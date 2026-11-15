--!strict
-- First-session visual checkpoint (visual audit 2026-11, owner-approved 8 Nov 2026).
-- Presentation data only: no odds, economy, access, collision or spawn values live here.
-- Positions were measured in the DEV place (see docs/visual_audit/2026-11/REPORT.md).

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

return table.freeze({
	Version = "FirstSessionVisuals_v1",

	-- Wall facades: visible height above the floor surface. Collision is unchanged
	-- (shell cores never collide); only the presentation is shortened.
	Facade = table.freeze({
		-- Tuned against the C2 wall-dominance measurement (median <= 25 % per region).
		-- 24 studs is still >3x the character jump height; gates open to 18 studs.
		InteriorHeight = 24,
		PerimeterHeight = 36,
		-- Pieces whose centre lies within this distance of the outer floor bounds are perimeter.
		PerimeterBand = 48,
		CrestThickness = 2.5,
		CrestOverhang = 1.25,
		-- Region-themed crest colours keyed by region floor folder name.
		CrestColours = table.freeze({
			Camp = Color3.fromHex("84E52B"),
			Forest = Color3.fromHex("2F9E44"),
			Beach = Color3.fromHex("F2D27A"),
			Swamp = Color3.fromHex("5E8C4A"),
			Jungle = Color3.fromHex("18A88A"),
			Arctic = Color3.fromHex("CFF4FF"),
			Volcano = Color3.fromHex("E2562B"),
			["Glitch Zone"] = Color3.fromHex("A836FF"),
		}),
		NeutralCrest = Color3.fromHex("6C78D8"),
	}),

	-- One skyline marker per hunting region, rising out of its hero landmark.
	-- Base = hero landmark centre (x, z) and visible top (y) measured in Edit mode.
	Skyline = table.freeze({
		TopHeight = 150,
		ChipWidth = 128,
		ChipHeight = 30,
		ChipText = 18,
		ChipMaxDistance = 2200,
		Markers = table.freeze({
			{ Region = "Forest", Style = "CanopyTree", X = -199, Z = -550, BaseY = 44 },
			{ Region = "Beach", Style = "Lighthouse", X = -666, Z = -70, BaseY = 48 },
			{ Region = "Swamp", Style = "SwampLantern", X = -319, Z = 331, BaseY = 28 },
			{ Region = "Jungle", Style = "JungleGiant", X = 125, Z = 414, BaseY = 68 },
			{ Region = "Arctic", Style = "IceSpire", X = 262, Z = -450, BaseY = 38 },
			{ Region = "Volcano", Style = "VolcanoPlume", X = 497, Z = -134, BaseY = 74 },
			{ Region = "Glitch Zone", Style = "GlitchPylon", X = 557, Z = 374, BaseY = 70 },
		}),
	}),

	-- Prop clusters placed beside measured featureless route stretches (C1/B3).
	-- Kind "Forest" = tree + rock + shrub; "Camp" = rock + two shrubs (no tree in the plaza).
	-- Every spot is off the yellow path lanes (9-point ray test against the lane meshes),
	-- clear of geometry within 11 studs and at least 28 studs from other clusters.
	-- Six planned spots had no off-lane clearing within 60 studs and were dropped;
	-- the hub-to-Forest corridor is lane almost wall to wall, so it holds only one.
	Clusters = table.freeze({
		{ Kind = "Forest", Position = v(-176, -343) },
		{ Kind = "Forest", Position = v(-319, -201) },
		{ Kind = "Forest", Position = v(-303, -106) },
		{ Kind = "Forest", Position = v(-114, -336) },
		{ Kind = "Forest", Position = v(-26, -347) },
		{ Kind = "Forest", Position = v(67, -345) },
		{ Kind = "Forest", Position = v(44, -398) },
		{ Kind = "Forest", Position = v(-300, -226) },
		{ Kind = "Forest", Position = v(-295, -136) },
		{ Kind = "Forest", Position = v(-255, -357) },
		{ Kind = "Forest", Position = v(-352, -110) },
		{ Kind = "Camp", Position = v(-235, -190) },
		{ Kind = "Forest", Position = v(-476, -419) },
		{ Kind = "Forest", Position = v(-11, -321) },
		{ Kind = "Forest", Position = v(72, -380) },
		{ Kind = "Forest", Position = v(-333, -146) },
		{ Kind = "Camp", Position = v(-165, 174) },
		-- Just inside the Forest mouth, beside the lane every base route uses.
		{ Kind = "Forest", Position = v(-236, -335) },
	}),
	ClusterPrototypes = table.freeze({
		Tree = "REGION_FOREST_Tree_01",
		Rock = "REGION_FOREST_Rock_01",
		Shrub = "REGION_FOREST_Shrub_01",
		CampShrub = "REGION_CAMP_Shrub_01",
	}),

	-- Spawn guidance toward the single Forest mouth every base route uses.
	Guide = table.freeze({
		Beacon = Vector3.new(-221, 0, -318),
		BeaconHeight = 70,
		BeaconColour = Color3.fromHex("8CFF3A"),
		Label = "HUNT HERE",
		SubLabel = "Forest",
		ChevronSpacing = 14,
		ChevronLimit = 48,
		ChevronSize = 6,
		RepathSeconds = 6,
		RepathDistance = 40,
		EdgeArrowMargin = 56,
		-- Guidance shows until the first durable bank (existing retention counter).
		CompletionAttribute = "RetentionCollectionCount",
		HubRegionId = "REGION_CAMP",
	}),

	-- Catch reveal card shown on the local player's server-confirmed sleep.
	Reveal = table.freeze({
		Width = 340,
		Height = 128,
		Top = 64,
		HoldSeconds = 3.2,
		InSeconds = 0.22,
		OutSeconds = 0.35,
		NameText = 26,
		DetailText = 16,
		IncomeText = 20,
		-- 16 x 0.88 minimum UI scale = 14.1 px on an 844-wide phone.
		ChipText = 16,
		BurstCount = 36,
		ReducedBurstCount = 12,
		BurstSize = 1.4,
		BurstSpeed = 18,
		BurstLifetime = 1.1,
	}),

	-- Name-tag declutter: hide a lower-priority plate whose screen box overlaps an
	-- admitted plate by at least this fraction of the smaller box. Long centred names
	-- collide visibly from ~0.15 box overlap (measured in the Forest), so keep it low.
	Nametag = table.freeze({
		OverlapFraction = 0.08,
	}),
})
