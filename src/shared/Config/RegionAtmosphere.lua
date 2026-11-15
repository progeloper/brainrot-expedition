--!strict
-- TerrainRedesign (V5) presentation config: per-region atmosphere, Storm curtain look and
-- client detail budgets. Presentation only; no access, economy or spawn data.
local function freezeAll(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freezeAll(v)
		end
	end
	return table.freeze(t)
end

-- Game audio on: the Storm rumble is the uploaded loop and AudioController plays the push/unlock.
-- Game audio off: the original Roblox built-in sounds, exactly as before.
local gameAudio = (require(script.Parent.FeatureFlags) :: any).GameAudioEnabled == true

return freezeAll({
	Version = 1,
	CrossfadeSeconds = 1.5,
	RegionPollHz = 4,
	-- Region profiles (keys match WorldProgression region keys). Ambient sound ids are empty until the
	-- owner supplies licensed audio; an empty id plays nothing (no Toolbox audio is used).
	Profiles = {
		Default = {
			TintColor = "#FFFFFF",
			Saturation = 0.08,
			Contrast = 0.04,
			AtmosphereColor = "#C7E9FF",
			Haze = 0.6,
			AmbientSound = "",
		},
		Camp = {
			TintColor = "#FFFBEA",
			Saturation = 0.12,
			Contrast = 0.05,
			AtmosphereColor = "#D9F7FF",
			Haze = 0.5,
			AmbientSound = "",
		},
		Forest = {
			TintColor = "#F2FFF6",
			Saturation = 0.16,
			Contrast = 0.06,
			AtmosphereColor = "#BFF8FF",
			Haze = 0.7,
			AmbientSound = "",
		},
		-- Wide open, long sightlines: the clearest air on the map.
		Beach = {
			TintColor = "#FFFBEA",
			Saturation = 0.18,
			Contrast = 0.05,
			AtmosphereColor = "#DFF9FF",
			Haze = 0.3,
			AmbientSound = "",
		},
		-- Mysterious, low visibility: heavier teal haze and denser air.
		Swamp = {
			TintColor = "#E9FFF6",
			Saturation = 0.1,
			Contrast = 0.1,
			AtmosphereColor = "#9FE8D6",
			Haze = 2.2,
			Density = 0.42,
			AmbientSound = "",
		},
		Jungle = {
			TintColor = "#FFF8E6",
			Saturation = 0.2,
			Contrast = 0.08,
			AtmosphereColor = "#D6FFC8",
			Haze = 1.1,
			AmbientSound = "",
		},
		-- Slippery fun, blue glow: cool, crisp air.
		Arctic = {
			TintColor = "#EEF8FF",
			Saturation = 0.14,
			Contrast = 0.06,
			AtmosphereColor = "#DFF9FF",
			Haze = 0.9,
			AmbientSound = "",
		},
		-- Danger and drama: warm, smoky haze.
		Volcano = {
			TintColor = "#FFF0E6",
			Saturation = 0.18,
			Contrast = 0.1,
			AtmosphereColor = "#FFB98A",
			Haze = 1.6,
			Density = 0.36,
			AmbientSound = "",
		},
		-- Chaotic, wrong: violet air.
		GlitchZone = {
			TintColor = "#F6EEFF",
			Saturation = 0.2,
			Contrast = 0.1,
			AtmosphereColor = "#D9C2FF",
			Haze = 1.2,
			AmbientSound = "",
		},
	},
	-- One client ambient emitter follows the player (Full tier only); these set its look per region.
	Particles = {
		Forest = {
			name = "Fireflies",
			colours = { "#C8FF6A", "#2EE9FF" },
			rate = 6,
			size = 0.35,
			speed = { 0.5, 1.5 },
		},
		Beach = {
			name = "BeachSparkles",
			colours = { "#FFFFFF", "#FFE14A" },
			rate = 8,
			size = 0.25,
			speed = { 0.2, 0.8 },
		},
		Swamp = {
			name = "SwampMist",
			colours = { "#DFF9FF", "#9FE8D6" },
			rate = 4,
			size = 6,
			speed = { 0.3, 0.8 },
			mist = true,
		},
		Jungle = {
			name = "JungleFireflies",
			colours = { "#FFD447", "#FFF0A3" },
			rate = 7,
			size = 0.35,
			speed = { 0.5, 1.5 },
		},
		Arctic = {
			name = "Snowfall",
			colours = { "#FFFFFF", "#BFF8FF" },
			rate = 14,
			size = 0.3,
			speed = { 0.2, 0.6 },
			fall = 2,
		},
		Volcano = {
			name = "Embers",
			colours = { "#FF8A2A", "#FFD447" },
			rate = 9,
			size = 0.25,
			speed = { 0.5, 1.2 },
			fall = -2,
		},
		GlitchZone = {
			name = "GlitchPixels",
			colours = { "#FF49E1", "#2EE9FF" },
			rate = 8,
			size = 0.4,
			speed = { 0.2, 0.6 },
		},
	},
	Storm = {
		Texture = "rbxassetid://123347547633652", -- StormSwirl, tools/terrain/generate_storm_swirl.py (uploaded 8 Nov 2026)
		Body = "#2B0F52", -- V4 GlitchZone lower (StormViolet)
		Height = 70,
		SegmentLength = 48,
		TextureLength = 24,
		TextureSpeed = 0.35,
		-- Owner brief asked for 0.6; a dark violet beam blends additively and vanished on bright
		-- terrain in Edit captures, so the body uses normal blending. The accent rim stays emissive.
		LightEmission = 0,
		TransparencyBase = 0.4,
		TransparencyTop = 0.82,
		RimHeight = 6,
		VisibleRadius = 420, -- only segments near the camera are enabled (Storm Beams budget <= 40)
		-- Two beams per segment (body + rim) plus the gate guide: 19 segments keep it <= 40 Beams
		-- (Play, 9 Nov: 40 segments enabled 52 Beams once region culling stopped hiding some).
		MaxVisibleSegments = 19,
		ApproachDistance = 25,
		PushSpeed = 55,
		PushLift = 25,
		PushHoldSeconds = 0.3,
		ShakeSeconds = 0.25,
		SparkCount = 12,
		CollapseSeconds = 1.2,
		Vignette = { TintColor = "#E7D9FF", Saturation = 0.1 },
		-- Region glow accents (the rim colour) and display colours; mirrors TerrainRegions/Gates.
		Accents = {
			Beach = "#FF3D9E",
			Swamp = "#8DFF3A",
			Jungle = "#FFD447",
			Arctic = "#46A7FF",
			Volcano = "#FF8A2A",
			GlitchZone = "#FF49E1",
		},
		-- Rumble is the uploaded Storm loop (BE_ST1.ogg). Whoosh/Fanfare are empty with game audio on
		-- because AudioController plays the Storm push (ST2) and unlock (J16 + ST3) itself.
		Sounds = {
			Rumble = if gameAudio then "rbxassetid://95796669912951" else "rbxasset://sounds/action_falling.mp3",
			Whoosh = if gameAudio then "" else "rbxasset://sounds/swoosh.wav",
			Fanfare = if gameAudio then "" else "rbxasset://sounds/victory.wav",
			Discovered = "rbxasset://sounds/electronicpingshort.wav",
		},
	},
	Toys = {
		BounceCooldownSeconds = 0.6,
		SlideMaxSpeed = 70,
		CarryNotice = "Can't bounce while carrying",
		CarrySlideNotice = "No slide boost while carrying",
	},
	Quality = {
		ProbeSeconds = 3,
		DropMedianFrameMs = 33,
		-- Full / Reduced / Minimal detail budgets (client-only detail parts and emitters).
		Tiers = {
			Full = { detailParts = 1, particles = true },
			Reduced = { detailParts = 0.5, particles = false },
			Minimal = { detailParts = 0, particles = false },
		},
	},
})
