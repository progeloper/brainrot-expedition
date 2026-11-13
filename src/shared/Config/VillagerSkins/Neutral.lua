--!strict
-- Plain review skin for the one villager body: a face, a cap on the Hat bone and a stick in
-- the right hand, so every body animation (hat throw, tag, reach) can be judged on its own.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Neutral",
	name = "Neutral review skin",
	approved = false,
	palette = table.freeze({
		skin = "#F2B79A",
		skin2 = "#E08A6A",
		hair = "#5A2E12",
		cloth = "#9AA3B5",
		top = "#9AA3B5",
		bottom = "#5C6478",
		shoe = "#2B2F3D",
		hat = "#F2C230",
		prop = "#C9894A",
		prop2 = "#8A5528",
		glow = "#8DFF3A",
	}),
	boxes = table.freeze(S.Join(S.Eyes(4.45, -0.9, 0.5, 0.76, 0.84, "Amber"), {
		B(
			"Head",
			"face",
			"Mouth",
			-0.4,
			3.82,
			-0.94,
			0.4,
			3.98,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B("Head", "face", "Nose", -0.15, 4.02, -1.1, 0.15, 4.26, -0.9, "skin2"),
		B("Head", "headwear", "Hair", -1.1, 4.8, -0.6, 1.1, 5.1, 0.95, "hair", { relief = true }),
		B("Head", "headwear", "HairBack", -1.1, 4.0, 0.9, 1.1, 5.1, 1.0, "hair", { relief = true }),
		B(
			"Hat",
			"headwear",
			"CapCrown",
			-0.9,
			5.05,
			-0.8,
			0.9,
			5.5,
			0.85,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "CapBrim", -0.9, 5.05, -1.4, 0.9, 5.15, -0.8, "hat"),
		B("Prop", "props", "Stick", 1.2, 1.4, -0.72, 1.4, 3.6, -0.52, "prop", { relief = true }),
		B("Prop", "props", "StickTip", 1.15, 3.6, -0.77, 1.45, 3.9, -0.47, "glow"),
	})),
})
