--!strict
-- TerrainRedesign (V5) outer island edge: the ocean beyond the rim and the out-of-bounds sea mist.
-- XZ rectangles use { min = Vector2(x, z), max = Vector2(x, z) } (Vector2.Y = world Z).
return table.freeze({
	-- Inner faces of the 22 perimeter CliffRun colliders (EV2_Run_01..04). They stay solid; the mist
	-- only answers a player who gets past them (over the rim, a launch, a physics glitch).
	Playable = table.freeze({ min = Vector2.new(-739, -646), max = Vector2.new(701, 522) }),
	-- Tolerance past the playable face before an entity counts as out of bounds (collider overlap).
	OutsideMargin = 4,
	-- Below this height anywhere on the map the entity fell through the world: moved back at once.
	FloorY = -40,
	-- Fallback landing probes, this many studs inward from the nearest playable edge.
	LandingInsets = table.freeze({ 40, 80, 140 }),
	-- Rim outer coast (author_v5_west RIM_EDGES / author_v5_east EAST_RIM_EDGES outer lines).
	Coast = table.freeze({ min = Vector2.new(-776, -680), max = Vector2.new(740, 592) }),
	Ocean = table.freeze({
		Reach = 640, -- open water beyond the coast on every side (reaches the fog line)
		ShelfWidth = 48, -- shallow sand shelf at the foot of the rim
		ShelfFloorY = -7, -- 3 studs under the surface: a lighter shallow band along the rim foot
		DeepFloorY = -26,
		BedBottomY = -34,
		SurfaceY = -4, -- below the -0.48 lane ground, so nothing on the island floods
		-- Sand islets offshore (x, z, radius): low caps break up the open water. Out of bounds.
		-- Sand bars offshore (x, z, ball radius): flat caps IsletCap above the surface break up the
		-- open water. Each stays at least 200 studs off the coast. Out of bounds.
		Islets = table.freeze({
			table.freeze({ -1020, -420, 96 }),
			table.freeze({ -1120, 140, 120 }),
			table.freeze({ -1000, 470, 84 }),
			table.freeze({ -420, -940, 110 }),
			table.freeze({ 160, -900, 88 }),
			table.freeze({ 560, -1040, 124 }),
			table.freeze({ 1000, -360, 96 }),
			table.freeze({ 1120, 120, 116 }),
			table.freeze({ 980, 520, 88 }),
			table.freeze({ 420, 860, 110 }),
			table.freeze({ -120, 960, 96 }),
			table.freeze({ -640, 880, 120 }),
		}),
		IsletCap = 5, -- studs above the surface
	}),
	Mist = table.freeze({
		Body = "#DFF9FF", -- V4 Mist
		Rim = "#7FE8FF", -- Arctic snow / V4 Ocean bright
		Offset = 6, -- curtain stands just off the coast, over the water
		BaseY = -4,
		Height = 140,
		SegmentLength = 96,
		-- Play, 9 Nov: at 0.55 / 0.92 with emission the white curtain vanished over the bright sea and
		-- sky; an almost opaque base with normal blending reads as a sea-haze sheet off the coast.
		TransparencyBase = 0.1,
		TransparencyTop = 0.7,
		LightEmission = 0,
		Vignette = { TintColor = "#E6FBFF", Saturation = -0.05 },
		-- Warn only up high near the edge (on the rim); a player walking the valley floor along a
		-- solid collider is not about to leave the island.
		WarnAboveY = 40,
		WarnDistance = 25,
		Banner = "Turn back!",
	}),
})
