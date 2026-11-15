--!strict
-- Shouter kit: round mascot body on short legs, wing-arms, beak and a tall cone hat.
-- Shared by every region (palette-swapped). Boxes only, faces -Z, ground y = 0, height ~5.7.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local B = K.Box

local left = {
	B("Foot_L", -0.85, 0, -0.85, -0.25, 0.25, 0.3, "shoe", { relief = true }),
	B("Leg_L", -0.7, 0.25, -0.2, -0.4, 0.8, 0.2, "shoe"),
	B("Wing_L", -1.65, 1.4, -0.45, -1.3, 3.3, 0.55, "cloth2", { relief = true, group = "ArmL" }),
	B("WingTip_L", -1.75, 1.2, -0.3, -1.4, 1.6, 0.4, "trim", { group = "ArmL" }),
	B("Tuft_L", -1.25, 4.2, -0.2, -0.75, 4.75, 0.3, "cloth2", { relief = true }),
}

local boxes = {
	B("Body", -1.3, 0.8, -1.0, 1.3, 4.2, 1.0, "cloth", { relief = true }),
	B("Belly", -0.95, 1.0, -1.08, 0.95, 2.45, -1.0, "cloth3", { relief = true }),
	B("BellyBand", -0.95, 2.1, -1.12, 0.95, 2.25, -1.08, "trim"),
	B("FacePlate", -1.15, 2.5, -1.08, 1.15, 4.1, -1.0, "skin"),
	B("Beak", -0.22, 2.72, -1.4, 0.22, 3.05, -1.08, "skin2"),
	B("Mouth", -0.4, 2.55, -1.12, 0.4, 2.7, -1.08, "Protected", { color = "#3A0F12" }),
	-- Cone hat (thrown in the tantrum): stacked tiers + glowing tip.
	B("Hat1", -0.85, 4.2, -0.65, 0.85, 4.55, 0.65, "hat", { relief = true, group = "Hat" }),
	B("Hat2", -0.6, 4.55, -0.45, 0.6, 4.95, 0.45, "hat", { relief = true, group = "Hat" }),
	B("Hat3", -0.4, 4.95, -0.3, 0.4, 5.3, 0.3, "hat2", { relief = true, group = "Hat" }),
	B("HatTip", -0.2, 5.3, -0.15, 0.2, 5.7, 0.15, "glow", { group = "Hat" }),
	-- Regional prop (Forest = none extra; the hat is the gag), small glow badge.
	B("BadgeGlow", 0.45, 1.6, -1.1, 0.8, 1.95, -1.05, "glow", { group = "Prop" }),
}
for _, item in left do
	table.insert(boxes, item)
end
for _, item in K.Mirror(left) do
	table.insert(boxes, item)
end
for _, cx in { -0.52, 0.52 } do
	for _, item in K.Eye(cx, 3.55, -1.08, 0.86, 0.9, "Lime") do
		table.insert(boxes, item)
	end
end

-- Regional variants (CP-B). Each hides the Forest cone hat and adds its own details.
local CONE = { "Hat1", "Hat2", "Hat3", "HatTip" }
local function joined(...)
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end
local function mirrored(list)
	return joined(list, K.Mirror(list))
end

local variants = {
	-- Foca Fischietto: seal muzzle, captain's hat, whistle, tail flipper (CP-C).
	Seal = {
		hide = joined(CONE, { "Beak", "Tuft_L", "Tuft_R" }),
		add = {
			B("Muzzle", -0.42, 2.72, -1.28, 0.42, 3.08, -1.08, "skin2"),
			B("SealNose", -0.13, 2.98, -1.33, 0.13, 3.1, -1.28, "trim"),
			B("Whistle", -0.15, 2.55, -1.55, 0.15, 2.72, -1.12, "glow", { group = "Prop" }),
			B("TailFlipper", -0.8, 0.0, 0.9, 0.8, 0.25, 1.6, "cloth2"),
			B(
				"CaptainHat",
				-0.9,
				4.2,
				-0.8,
				0.9,
				4.6,
				0.8,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B(
				"CaptainTop",
				-0.7,
				4.6,
				-0.7,
				0.7,
				5.35,
				0.7,
				"hat2",
				{ relief = true, group = "Hat" }
			),
			B("HatBadge", -0.2, 4.3, -0.84, 0.2, 4.5, -0.8, "glow", { group = "Hat" }),
		},
	},
	-- Campana Cenere: ash hood with ember trim, a big hand bell (CP-C).
	Bell = {
		hide = joined(CONE, { "Tuft_L", "Tuft_R" }),
		add = {
			B("Hood", -1.2, 4.0, -0.95, 1.2, 4.9, 1.05, "hat", { relief = true, group = "Hat" }),
			B(
				"HoodPoint",
				-0.5,
				4.9,
				-0.4,
				0.5,
				5.45,
				0.5,
				"hat2",
				{ relief = true, group = "Hat" }
			),
			B("EmberBand", -1.22, 4.0, -0.97, 1.22, 4.1, 1.07, "glow", { group = "Hat" }),
			B("BellHandle", 1.75, 2.9, -0.1, 1.95, 3.6, 0.1, "prop2", { group = "Prop" }),
			B("Bell", 1.5, 2.2, -0.4, 2.2, 2.9, 0.3, "prop", { relief = true, group = "Prop" }),
			B("BellLip", 1.4, 2.1, -0.5, 2.3, 2.25, 0.4, "prop2", { group = "Prop" }),
			B("Clapper", 1.75, 1.95, -0.12, 1.95, 2.1, 0.08, "glow", { group = "Prop" }),
		},
	},
	-- Bip Bop: a speaker on legs with antennas (CP-C).
	Speaker = {
		hide = joined(CONE, {
			"Beak",
			"Tuft_L",
			"Tuft_R",
			"Wing_L",
			"Wing_R",
			"WingTip_L",
			"WingTip_R",
			"Belly",
			"BellyBand",
		}),
		add = joined(
			mirrored({
				B("Antenna_L", -0.6, 4.2, -0.1, -0.5, 5.1, 0.0, "trim"),
				B("AntennaTip_L", -0.68, 5.1, -0.18, -0.42, 5.4, 0.08, "glow", { group = "Hat" }),
				B("Knob_L", -1.42, 3.0, -0.3, -1.3, 3.4, 0.1, "prop"),
			}),
			{
				B("SpeakerCone", -0.85, 1.05, -1.2, 0.85, 2.4, -1.0, "trim", { relief = true }),
				B("SpeakerCore", -0.3, 1.45, -1.28, 0.3, 2.0, -1.2, "glow"),
			}
		),
	},

	-- Granchio Megafono: eye stalks, extra legs, a pincer and a megaphone.
	Crab = {
		hide = joined(CONE, { "Beak", "Tuft_L", "Tuft_R" }),
		add = joined(
			mirrored({
				B("Stalk_L", -0.72, 4.2, -0.25, -0.5, 4.9, -0.03, "skin2"),
				B("StalkBall_L", -0.88, 4.9, -0.4, -0.34, 5.42, 0.12, "skin", { group = "Hat" }),
				B("SideLeg_L", -1.75, 0.2, 0.1, -1.3, 0.9, 0.42, "shoe"),
			}),
			{
				B("Claw_L", -2.45, 2.9, -1.05, -1.6, 3.6, -0.2, "cloth2", { relief = true }),
				B("ClawPincer_L", -2.45, 3.6, -1.05, -2.0, 3.98, -0.4, "cloth2"),
				B("MegaphoneHandle", 1.75, 2.8, -1.55, 2.05, 3.3, -1.3, "trim", { group = "Prop" }),
				B(
					"Megaphone",
					1.5,
					3.3,
					-2.0,
					2.3,
					4.1,
					-1.2,
					"prop",
					{ relief = true, group = "Prop" }
				),
				B("MegaphoneBell", 1.35, 3.15, -2.4, 2.45, 4.25, -2.0, "prop2", { group = "Prop" }),
				B("MegaphoneRim", 1.33, 3.13, -2.46, 2.47, 4.27, -2.4, "glow", { group = "Prop" }),
			}
		),
	},
	-- Lumaca Lampione: eye stalks and a lantern shell glowing from inside.
	Snail = {
		hide = joined(CONE, { "Beak", "Tuft_L", "Tuft_R" }),
		add = joined(
			mirrored({
				B("Stalk_L", -0.6, 4.2, -0.42, -0.45, 5.1, -0.27, "skin"),
				B("StalkTip_L", -0.69, 5.1, -0.5, -0.36, 5.42, -0.18, "skin2", { group = "Hat" }),
			}),
			{
				B("Shell", -1.2, 1.6, 1.0, 1.2, 4.4, 2.6, "cloth2", { relief = true }),
				B("ShellSpiral", -1.25, 2.4, 1.35, 1.25, 3.6, 2.2, "trim", { relief = true }),
				B("LanternGlow", -1.28, 2.7, 1.55, 1.28, 3.3, 1.95, "glow"),
				B("LanternCap", -0.3, 4.4, 1.5, 0.3, 4.8, 2.0, "prop", { group = "Prop" }),
			}
		),
	},
	-- Pappagallo Pazzo: hooked beak, feather crest, long tail feathers.
	Parrot = {
		hide = joined(CONE, { "Beak" }),
		add = {
			B("BigBeak", -0.3, 2.72, -1.6, 0.3, 3.12, -1.08, "skin2", { relief = true }),
			B("BeakHook", -0.3, 2.5, -1.65, 0.3, 2.78, -1.42, "trim"),
			B("Crest1", -0.15, 4.2, -0.35, 0.15, 5.1, -0.05, "hat", { group = "Hat" }),
			B("Crest2", -0.15, 4.2, -0.05, 0.15, 5.6, 0.25, "hat2", { group = "Hat" }),
			B("Crest3", -0.15, 4.2, 0.25, 0.15, 4.75, 0.55, "glow", { group = "Hat" }),
			B("TailFeathers", -0.38, 0.4, 1.0, 0.38, 2.0, 1.55, "cloth2", { relief = true }),
			B("TailTip", -0.38, 0.2, 1.15, 0.38, 0.4, 1.55, "glow"),
		},
	},
}

return table.freeze({
	id = "Shouter",
	version = 2,
	boxes = table.freeze(boxes),
	variants = table.freeze(variants),
	tantrum = "Squawk",
})
