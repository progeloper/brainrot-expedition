--!strict
-- Cart "dopamine ladder" presentation styles (design/Brainrot_Cart_Flair_Standard.md).
-- Presentation only: no stats, prices, capacities or physics live here.
-- Read by the server CartFlairBuilder (bakes Visual.Flair into the templates at boot)
-- and by the client CartFlairController (quality-gated VFX and colour cycling).
local C = Color3.fromRGB

local Styles = {}

Styles.Tag = "CartFlair"
Styles.Version = 2

-- Tier = upgrade step. Every tier keeps everything below it and adds a layer:
-- 0 Starter: bold neon stripes, neon underglow strip, wheel rings, head/tail
--    lights, glowing exhaust tip with an idle puff.
-- 1 (500M): + underglow ground light, under-tubes, twin coloured smoke, light trails.
-- 2 (125B): + wings, crests, chevrons, body sparkles, boost flames, wheel sparks.
-- 3 (6T):   + aura column, colour-cycling neon, signature set piece, long trails.
Styles.Cycles = {
	Rainbow = { C(255, 61, 158), C(255, 138, 42), C(255, 225, 74), C(141, 255, 58), C(46, 233, 255), C(166, 77, 255) },
	Aurora = { C(109, 246, 255), C(22, 119, 255), C(166, 77, 255), C(70, 255, 200) },
	Magma = { C(255, 90, 31), C(255, 37, 188), C(166, 77, 255), C(255, 138, 42) },
}

Styles.Carts = {
	ScrapChariot = {
		Tier = 0, Class = "Balanced",
		Primary = C(141, 255, 58), Secondary = C(255, 177, 61), Ink = C(29, 33, 51),
		Head = C(255, 246, 176), Tail = C(255, 61, 61),
		Smoke = { C(214, 214, 224), C(130, 130, 145) },
		Exhausts = 1,
	},
	DuneRunner = {
		Tier = 1, Class = "Scout",
		Primary = C(141, 255, 58), Secondary = C(255, 225, 74), Ink = C(29, 33, 51),
		Head = C(191, 248, 255), Tail = C(255, 138, 42),
		Smoke = { C(255, 225, 120), C(255, 170, 70) },
		Trail = { C(141, 255, 58), C(255, 225, 74) },
		Exhausts = 2,
	},
	IronHauler = {
		Tier = 1, Class = "Reinforced",
		Primary = C(255, 45, 85), Secondary = C(255, 138, 42), Ink = C(29, 33, 51),
		Head = C(191, 248, 255), Tail = C(255, 45, 85),
		Smoke = { C(255, 120, 80), C(90, 70, 80) },
		Trail = { C(255, 45, 85), C(255, 138, 42) },
		Exhausts = 2,
	},
	NeonCruiser = {
		Tier = 2, Class = "Balanced",
		Primary = C(255, 61, 158), Secondary = C(46, 233, 255), Ink = C(29, 33, 51),
		Head = C(191, 248, 255), Tail = C(255, 61, 158),
		Smoke = { C(255, 61, 158), C(166, 77, 255) },
		Trail = { C(255, 61, 158), C(46, 233, 255) },
		Flame = { C(255, 255, 255), C(46, 233, 255) },
		Spark = C(46, 233, 255),
		Crest = "Star", Wing = "Fin", Exhausts = 2,
	},
	VoltDasher = {
		Tier = 2, Class = "Scout",
		Primary = C(255, 225, 74), Secondary = C(62, 255, 240), Ink = C(29, 33, 51),
		Head = C(191, 248, 255), Tail = C(255, 225, 74),
		Smoke = { C(62, 255, 240), C(70, 167, 255) },
		Trail = { C(255, 225, 74), C(62, 255, 240) },
		Flame = { C(255, 255, 255), C(62, 255, 240) },
		Spark = C(255, 240, 120),
		Crest = "Bolt", Wing = "Zig", Exhausts = 2,
	},
	BastionWagon = {
		Tier = 2, Class = "Reinforced",
		Primary = C(255, 212, 71), Secondary = C(166, 77, 255), Ink = C(58, 20, 92),
		Head = C(255, 246, 176), Tail = C(166, 77, 255),
		Smoke = { C(166, 77, 255), C(90, 31, 194) },
		Trail = { C(255, 212, 71), C(166, 77, 255) },
		Flame = { C(255, 246, 176), C(255, 170, 40) },
		Spark = C(255, 212, 71),
		Crest = "Crown", Wing = "Shield", Exhausts = 2,
	},
	StarforgeChariot = {
		Tier = 3, Class = "Balanced",
		Primary = C(255, 212, 71), Secondary = C(255, 255, 255), Ink = C(255, 246, 225),
		Head = C(255, 255, 255), Tail = C(255, 61, 158),
		Smoke = { C(255, 225, 120), C(255, 61, 158) },
		Trail = { C(255, 61, 158), C(255, 225, 74), C(46, 233, 255), C(166, 77, 255) },
		Flame = { C(255, 255, 255), C(255, 212, 71) },
		Spark = C(255, 225, 120),
		Aura = { C(255, 225, 74), C(255, 61, 158), C(46, 233, 255) },
		Cycle = "Rainbow", Crest = "Star", Wing = "Angel", Halo = true, Exhausts = 2,
	},
	CometSkimmer = {
		Tier = 3, Class = "Scout",
		Primary = C(109, 246, 255), Secondary = C(255, 255, 255), Ink = C(22, 60, 140),
		Head = C(255, 255, 255), Tail = C(22, 119, 255),
		Smoke = { C(240, 252, 255), C(150, 220, 255) },
		Trail = { C(255, 255, 255), C(109, 246, 255), C(22, 119, 255) },
		Flame = { C(255, 255, 255), C(109, 246, 255) },
		Spark = C(200, 250, 255),
		Aura = { C(255, 255, 255), C(109, 246, 255), C(166, 77, 255) },
		Cycle = "Aurora", Crest = "Comet", Wing = "Crystal", Exhausts = 2,
	},
	ObsidianFortress = {
		Tier = 3, Class = "Reinforced",
		Primary = C(255, 90, 31), Secondary = C(255, 37, 188), Ink = C(26, 15, 36),
		Head = C(255, 170, 90), Tail = C(255, 37, 188),
		Smoke = { C(60, 25, 70), C(20, 10, 25) },
		Trail = { C(255, 138, 42), C(255, 37, 188), C(166, 77, 255) },
		Flame = { C(255, 225, 74), C(255, 90, 31) },
		Spark = C(255, 138, 42),
		Aura = { C(255, 138, 42), C(255, 37, 188), C(166, 77, 255) },
		Cycle = "Magma", Crest = "Horns", Wing = "Bat", FireExhaust = true, Exhausts = 2,
	},
}

-- Client gating. Ranks: Low 1, Medium 2, High 3 (ResolvedPresentationQuality).
Styles.Runtime = {
	MaxDistance = 150, -- nothing animates beyond this
	OthersMediumDistance = 70, -- other players' carts run one quality step lower
	OthersHighDistance = 120, -- ... and two steps lower out to here
	CycleDistance = 90,
	MovingSpeed = 6, -- studs/s, with hysteresis
	FastFraction = 0.6, -- of the cart's MaxTravelSpeed
	BoostFraction = 0.9,
	RateScale = { Low = 0.5, Medium = 0.6, High = 1 },
}

for _, style in Styles.Carts do
	table.freeze(style)
end
table.freeze(Styles.Carts)
table.freeze(Styles.Cycles)
table.freeze(Styles.Runtime)
return table.freeze(Styles)
