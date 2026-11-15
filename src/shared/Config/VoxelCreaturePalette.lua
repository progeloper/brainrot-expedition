--!strict
-- Voxel V4 style kit constants (owner prompt v3, 3 Nov 2026, sections 2.4, 4 and 6).
-- Presentation only: no ID, rarity, mutation key, odds, multiplier or economy data.
local function freezeAll(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freezeAll(v)
		end
	end
	return table.freeze(t)
end

return freezeAll({
	Version = 4,
	-- Roblox CFrame mapping: design +x (nose) -> model forward -Z (matches the
	-- established creature forward), design +z -> +X. A proper rotation; no mirroring.
	DesignForward = Vector3.new(0, 0, -1),
	TargetHeightMultiplier = 1.30, -- of PlaytestMeasurements.ReferenceBodyHeight (~6.706 studs)

	-- Saved stud texture already in the place (v979 creature binding). Found in
	-- MaterialService of Main_Mutation_Binding_v979.rbxl; reused, never re-uploaded.
	Studs = {
		MaterialVariant = "AF2_Creature_SmoothPlastic", -- base SmoothPlastic, StudsPerTile 0.55
		ColorMap = "rbxassetid://126387978066468", -- same image as Bingus_Saved_Studs_13719188279
		NormalMap = "rbxassetid://124160206245321",
		StudsPerTile = 0.55, -- v979 bound period; MaterialVariant tiling is world-space so it survives ScaleTo
	},

	Fit = {
		MaxDepthStuds = 14.0,
		MaxWidthStuds = 10.5,
		HeightToleranceStuds = 0.07,
		-- Giant species (data.sizeMultiplier > 1, owner 5 Nov 2026) scale the depth/width limits by
		-- their multiplier, up to this cap.
		GiantSizeMultiplierMax = 2.0,
		MinBoxes = 40,
		MaxBoxes = 160, -- BRT_027's approved build has 152 boxes (approved geometry kept 1:1)
		-- Legendary and above may carry more sculpted detail (owner, BRT_033, 6 Nov 2026: "too blocky, add
		-- more detail"); still well inside MaxTrianglesLegendaryPlus.
		MaxBoxesLegendaryPlus = 280,
		TrianglesPerBox = 12,
		MaxTrianglesCommonToEpic = 3500,
		MaxTrianglesLegendaryPlus = 7000,
		CastShadowMinVolume = 1.0, -- stud^3 at gameplay scale
	},

	Constants = {
		JointDark = "#1D2133",
		JointDark2 = "#2A2F45",
		Glass = "#141A2E",
		GlassMid = "#1B2A5C",
		GlassGlint = "#6FA8FF",
		Claw = "#262A3A",
		Mouth = "#6E0E2C",
		Tongue = "#FF4F7A",
		Teeth = "#FFFFFF",
		Headlight = "#BFF8FF",
		Pupil = "#1A0B06",
		EyeWhite = "#FFFFFF",
		Lash = "#000000",
		Blush = "#FF6FA3",
		Catchlight = "#FFFFFF",
	},

	Library = {
		HotPink = "#FF3D9E",
		Teal = "#14C79F",
		Cyan = "#2EE9FF",
		Sun = "#FFD447",
		Tangerine = "#FF8A2A",
		Lime = "#8DFF3A",
		Grape = "#8A4DFF",
		Sky = "#46A7FF",
		SharkBlue = "#3A9BFF",
		ShoeBlue = "#1E6BFF",
		Cherry = "#F0283C",
		Bubblegum = "#FF87C8",
		Leaf = "#3BD16F",
		BrightWhite = "#F7F5FC",
		PeachSkin = "#FFD0B0",
		PeachTuft = "#FFB08A",
		WarmWood = "#C9894A",
		WarmWoodDark = "#8A5528",
		Banana = "#FFE14A",
		WatermelonRed = "#FF4F6B",
		WatermelonGreen = "#2FBF5A",
		Steel = "#9AA6C8",
		SteelDark = "#5D6788",
	},

	IrisFamilies = {
		Amber = { dark = "#7A2A10", mid = "#FF6A1A", bright = "#FFCF45" },
		Ocean = { dark = "#0B2E6B", mid = "#1E8BFF", bright = "#7FE8FF" },
		Candy = { dark = "#6B0F45", mid = "#FF3DA8", bright = "#FFB3E0" },
		Lime = { dark = "#1F4A0B", mid = "#45D11E", bright = "#C8FF6A" },
		Violet = { dark = "#2E0F6B", mid = "#8A4DFF", bright = "#D8B8FF" },
		Ruby = { dark = "#5A0A14", mid = "#F0283C", bright = "#FF9AA5" },
	},

	-- Anime eye, relative to the head panel (L = front-back length, H = height).
	Eye = {
		WhiteCore = { L = 0.48, H = 0.67 },
		WhiteWide = { L = 0.58, HInset = 0.06 },
		MinWhiteStuds = { 1.0, 1.2 },
		Iris = { W = 0.68, H = 0.84, Bands = { bright = 0.27, mid = 0.33, dark = 0.40 } },
		Pupil = { W = 0.49, H = 0.47, TopInset = 0.30 },
		BigCatchlight = { W = 0.38, H = 0.28 },
		SmallCatchlight = { W = 0.19, H = 0.13 },
		Sparkle = { W = 0.08, H = 0.06 },
		Lash = { H = 0.10, Wing = 0.12 },
		Blush = { L = 0.29, H = 0.10 },
		Proud = { white = 0.04, iris = 0.03 },
	},

	Roles = {
		"upper",
		"lower",
		"stripe",
		"trim",
		"skin",
		"skin2",
		"feather",
		"feather2",
		"foot",
		"prop",
		"accent",
	},
	NeonRoles = { stripe = true, accent = true },

	Mutations = { "Shiny", "Golden", "Glitched", "Radioactive", "Astral" },
	-- Owner-approved role palettes (matches PALETTES in both reference builds).
	MutationPalettes = {
		Shiny = {
			upper = "#FF87B7",
			lower = "#FFF4CD",
			stripe = "#FFFFFF",
			trim = "#FFE3EE",
			skin = "#FFE0EC",
			skin2 = "#FFB6D3",
			feather = "#FF5FA0",
			feather2 = "#FFFFFF",
			foot = "#FF9CC6",
			prop = "#FFF4CD",
			accent = "#FF87B7",
		},
		Golden = {
			upper = "#D99510",
			lower = "#FFD447",
			stripe = "#FFF0A3",
			trim = "#FFE27A",
			skin = "#FFD447",
			skin2 = "#E5A520",
			feather = "#8C4A08",
			feather2 = "#FFF0A3",
			foot = "#D99510",
			prop = "#FFD447",
			accent = "#FFF0A3",
		},
		Glitched = {
			upper = "#FF49E1",
			lower = "#2B0F52",
			stripe = "#3EFFF0",
			trim = "#5A1F9A",
			skin = "#FF8AF0",
			skin2 = "#3EFFF0",
			feather = "#2B0F52",
			feather2 = "#FF49E1",
			foot = "#3EFFF0",
			prop = "#FF49E1",
			accent = "#3EFFF0",
		},
		Radioactive = {
			upper = "#DCFF2B",
			lower = "#182018",
			stripe = "#DCFF2B",
			trim = "#2A3A20",
			skin = "#C9FF5A",
			skin2 = "#9FE01A",
			feather = "#182018",
			feather2 = "#DCFF2B",
			foot = "#DCFF2B",
			prop = "#182018",
			accent = "#DCFF2B",
		},
		Astral = {
			upper = "#6D74FF",
			lower = "#2A1F6E",
			stripe = "#EDE0FF",
			trim = "#3B2F8F",
			skin = "#C4B6FF",
			skin2 = "#8F80FF",
			feather = "#140D38",
			feather2 = "#EDE0FF",
			foot = "#6D74FF",
			prop = "#6D74FF",
			accent = "#EDE0FF",
		},
	},
	MutationGlow = {
		Shiny = { "#FFF4CD" },
		Golden = { "#FFD447" },
		Glitched = { "#FF49E1" },
		Radioactive = { "#DCFF2B" },
		Astral = { "#EDE0FF", "#6D74FF" },
	},
	MutationTag = {
		Shiny = "#FF87B7",
		Golden = "#FFD447",
		Glitched = "#FF49E1",
		Radioactive = "#DCFF2B",
		Astral = "#B9A6FF",
	},

	-- Per-mutation finish and signature effect (section 6.2). Effect sizes are
	-- multiplied by the model's gameplay-scale bounds when applied.
	MutationEffects = {
		Shiny = {
			reflectance = 0.12,
			overlay = "ShinyTwinkle",
			emitter = {
				colors = { "#FFFFFF", "#FF87B7" },
				rate = 3,
				life = { 0.6, 1.0 },
				size = { 0.3, 0.6 },
				lightEmission = 1,
			},
		},
		Golden = {
			-- Foil would drop the saved stud MaterialVariant (SmoothPlastic base), so the
			-- SmoothPlastic + Reflectance option is kept: studs stay visible.
			reflectance = 0.28,
			overlay = "GoldVariance",
			emitter = {
				colors = { "#FFF0A3", "#FFFFFF" },
				rate = 4,
				life = { 0.5, 0.9 },
				size = { 0.3, 0.55 },
				lightEmission = 1,
			},
		},
		Glitched = {
			reflectance = 0,
			overlay = "GlitchTiles",
			tick = {
				minInterval = 2.5,
				maxInterval = 4.0,
				duration = 0.12,
				offsetStuds = 0.08,
				swap = { "#FF49E1", "#3EFFF0" },
			},
			emitter = {
				colors = { "#3EFFF0", "#FF49E1" },
				rate = 4,
				life = { 0.4, 0.8 },
				size = { 0.2, 0.4 },
				lightEmission = 1,
				square = true,
			},
		},
		Radioactive = {
			reflectance = 0,
			bodyEmissiveTint = 0.22,
			pulse = { period = 1.2, maxTransparency = 0.35 },
			emitter = {
				colors = { "#DCFF2B" },
				rate = 3,
				life = { 1.0, 1.6 },
				size = { 0.25, 0.5 },
				lightEmission = 1,
				riseStudsPerSecond = 1.5,
			},
		},
		Astral = {
			reflectance = 0,
			overlay = "StarSpeckle",
			halo = { color = "#EDE0FF", tiltDegrees = -12, radiusScale = 0.62, thickness = 0.12 },
			emitter = {
				colors = { "#EDE0FF", "#6D74FF" },
				rate = 2,
				life = { 0.8, 1.4 },
				size = { 0.15, 0.3 },
				lightEmission = 1,
			},
		},
	},
	-- Shared overlay images (section 6.2). Upload is owner-gated: until an asset ID
	-- is recorded here the overlay is skipped (studs, colour, glow and effect still apply).
	OverlayImages = {
		ShinyTwinkle = "",
		GoldVariance = "",
		GlitchTiles = "",
		StarSpeckle = "",
		Sparkle4 = "",
		PixelSquare = "",
		RingBubble = "",
		HaloRing = "",
		AuraRadial = "rbxassetid://131252330517526", -- existing installed Astral radiance (reused)
	},
	OverlayStudsPerTile = 0.5,
	-- Interim particle sprite: engine-bundled content, no upload, until Sparkle4 exists.
	InterimParticleTexture = "rbxasset://textures/particles/sparkles_main.dds",
	-- Passive species FX (owner, 6 Nov 2026): a few always-on emitters built into a species template
	-- (presentation only; base/cargo presentation already disables ParticleEmitters on inactive models).
	-- Engine-bundled sprites only, no uploads; kept small so they never stress the engine.
	PassiveFx = {
		Textures = {
			smoke = "rbxasset://textures/particles/smoke_main.dds",
			sparkle = "rbxasset://textures/particles/sparkles_main.dds",
		},
		MaxEmitters = 3,
		MaxRate = 8, -- particles per second per emitter
		MaxLifetime = 3, -- seconds
	},
	AuraHeightScale = 1.4,

	Quality = {
		FullMaxDistance = 120,
		ReducedMaxDistance = 250,
		MinimalMaxDistance = 400,
	},
	EffectTickHz = 10,

	RarityTiers = {
		Common = { primary = "#E3EAF3", glow = nil },
		Uncommon = { primary = "#72E65B", glow = "#72E65B" },
		Rare = { primary = "#46A7FF", glow = "#46A7FF" },
		Epic = { primary = "#B86CFF", glow = "#B86CFF" },
		Legendary = { primary = "#FFAE3D", glow = "#FFAE3D" },
		Mythic = { primary = "#FF4B67", glow = "#FF4B67", pulse = true },
		Celestial = { primary = "#6DEBFF", glow = "#6DEBFF" },
		Secret = { primary = "#1A1428", glow = "#DBD6E7" },
	},
	IncomeColor = "#52FF6A",
})
