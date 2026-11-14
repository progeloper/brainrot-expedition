--!strict
-- Village-life points of interest per guard (rig + animation brief v5, C.6), generated in Studio
-- on 14 November 2026 and validated against the map: inside the guard's region and outside
-- Camp; at least 4 studs from every road triangle (read from the MapBlockout.Paths meshes),
-- 6 from gates and aperture closures, 8 from base patches and burrows; flat (normal Y > 0.88),
-- within 3 studs of the home's height, unobstructed, and reachable in a straight line from home.
-- Within idleRadius, raised to at most 12 studs where nothing nearer passed (listed in
-- docs/animation/2026-11/village_life.md). `face` turns a Lookout toward the region's centre.
-- Lumaca Lampione has none (his home sits in a road band): he keeps the plain idle wander.
local function P(x: number, z: number, activity: string, face: { number }?): any
	return table.freeze({ x = x, z = z, activity = activity, face = face })
end

return table.freeze({
	-- Forest
	VIL_FOREST_TITO = {
		P(-440.9, -151.7, "Lookout", { 0.84, -0.54 }),
		P(-441.9, -142.6, "Chop"),
		P(-441.9, -157.4, "Sweep"),
	},
	VIL_FOREST_PINA = {
		P(-327.7, -45.5, "Lookout", { 0.43, -0.9 }),
		P(-332.3, -34.5, "Knead"),
		P(-324.5, -37.7, "Sweep"),
	},
	VIL_FOREST_GUFO = { P(-453.5, 73.7, "Lookout", { 0.56, -0.83 }) },
	VIL_FOREST_FRANCO = {
		P(-112.4, -594.1, "Lookout", { -0.3, 0.95 }),
		P(-106.9, -607.4, "Sweep"),
		P(-117.4, -603.1, "Chop"),
	},
	VIL_FOREST_CASTAGNA = {
		P(107.7, -607.7, "Lookout", { -0.72, 0.7 }),
		P(114.2, -614.2, "Knead"),
	},
	VIL_FOREST_PEPE = {
		P(-150, -622.8, "Lookout", { -0.16, 0.99 }),
		P(-150, -629, "Chop"),
	},
	-- Beach
	VIL_BEACH_BRUNO = {
		P(-682.6, -153.1, "Lookout", { 0.76, -0.66 }),
		P(-682.6, -146.9, "Sweep"),
	},
	VIL_BEACH_SABBIA = {
		P(-580, 56.7, "Lookout", { 0.19, -0.98 }),
		P(-580, 66, "Sweep"),
	},
	VIL_BEACH_GRANCHIO = {
		P(-698.8, 117, "Lookout", { 0.41, -0.91 }),
		P(-701.5, 123.7, "Fiddle"),
	},
	VIL_BEACH_SARA = {
		P(-598.3, -555.9, "Lookout", { 0.35, 0.94 }),
		P(-603.1, -567.4, "Sweep"),
		P(-592.6, -563.1, "Skate"),
	},
	VIL_BEACH_CONCHIGLIA = {
		P(-421.3, -597, "Lookout", { -0.29, 0.96 }),
		P(-417.7, -605.5, "Fish"),
	},
	-- Swamp
	VIL_SWAMP_RANA = {
		P(-645.5, 254.5, "Lookout", { 0.73, 0.68 }),
		P(-655.7, 244.3, "Sweep"),
	},
	VIL_SWAMP_POZZO = {
		P(-323, 329.3, "Lookout", { -0.96, 0.28 }),
		P(-314.5, 325.7, "Fish"),
	},
	VIL_SWAMP_ROCCO = {
		P(-694.1, 503.6, "Lookout", { 0.84, -0.54 }),
		P(-707.4, 509.1, "Sweep"),
	},
	VIL_SWAMP_PALUDE = {
		P(-450.5, 272.5, "Lookout", { -0.54, 0.84 }),
		P(-433.5, 272.5, "Fish"),
	},
	-- Jungle
	VIL_JUNGLE_SCIMMIA = {
		P(-151.7, 445.9, "Lookout", { -0.42, -0.91 }),
		P(-142.6, 453.1, "Sweep"),
		P(-157.4, 453.1, "Chop"),
	},
	VIL_JUNGLE_TOTO = {
		P(85.5, 499.7, "Lookout", { -0.92, -0.4 }),
		P(96.5, 504.3, "Stir"),
	},
	-- Only one spot passed; he tinkers at his look-out.
	VIL_JUNGLE_PAZZO = {
		P(-423.7, 498.5, "Lookout", { 0.9, -0.44 }),
		P(-423.7, 498.5, "Fiddle"),
	},
	VIL_JUNGLE_SOFIA = {
		P(139.6, 370, "Lookout", { -1, 0.04 }),
		P(152, 370, "Chop"),
		P(144, 378, "Sweep"),
	},
	VIL_JUNGLE_TINA = {
		P(-101.8, 244.4, "Lookout", { -0.5, 0.87 }),
		P(-97.7, 234.5, "Knead"),
	},
	-- Arctic
	VIL_ARCTIC_PATTINO = {
		P(413.7, -615.9, "Lookout", { 0.36, 0.93 }),
		P(408.9, -627.4, "Skate"),
		P(404.6, -616.9, "Sweep"),
	},
	VIL_ARCTIC_PIA = {
		P(646.9, -616.9, "Lookout", { -0.78, 0.63 }),
		P(655.7, -625.7, "Sweep"),
	},
	VIL_ARCTIC_BRODO = {
		P(608.5, -501.5, "Lookout", { -0.96, 0.26 }),
		P(608.5, -518.5, "Stir"),
	},
	VIL_ARCTIC_OLGA = {
		P(421.3, -353, "Lookout", { 0.37, -0.93 }),
		P(417.7, -344.5, "Skate"),
	},
	VIL_ARCTIC_FOCA = {
		P(309.7, -411.5, "Lookout", { 0.93, -0.37 }),
		P(302.3, -408.5, "Fish"),
	},
	-- Volcano
	VIL_VOLCANO_LAVA = {
		P(355.9, -152.4, "Lookout", { 0.95, -0.31 }),
		P(342.6, -146.9, "Sweep"),
		P(346.9, -157.4, "Chop"),
	},
	VIL_VOLCANO_MAGMA = {
		P(548.7, -3, "Lookout", { -0.39, -0.92 }),
		P(552.3, 5.5, "Stir"),
	},
	VIL_VOLCANO_CAMPANA = {
		P(400.8, 118, "Lookout", { 0.22, -0.98 }),
		P(398.5, 123.7, "Fiddle"),
	},
	VIL_VOLCANO_MIMMO = {
		P(607.4, -396.9, "Lookout", { -0.53, 0.85 }),
		P(607.4, -403.1, "Chop"),
	},
	VIL_VOLCANO_BRACE = {
		P(648.7, 147, "Lookout", { -0.47, -0.88 }),
		P(652.3, 155.5, "Stir"),
	},
	-- Glitch Zone
	VIL_GLITCH_PINO = {
		P(304.1, 448.3, "Lookout", { 0.93, -0.37 }),
		P(292.6, 453.1, "Sweep"),
		P(303.1, 457.4, "Fiddle"),
	},
	VIL_GLITCH_404 = {
		P(505.5, 497.7, "Lookout", { -0.25, -0.97 }),
		P(494.5, 502.3, "Fiddle"),
	},
	VIL_GLITCH_BIPBOP = {
		P(647.8, 388, "Lookout", { -1, -0.03 }),
		P(654, 388, "Fiddle"),
	},
	VIL_GLITCH_PINA = {
		P(450, 384.4, "Lookout", { 0.99, 0.1 }),
		P(450, 372, "Sweep"),
	},
	VIL_GLITCH_500 = {
		P(607.6, 500.6, "Lookout", { -0.76, -0.65 }),
		P(615.2, 508.2, "Fiddle"),
	},
})
