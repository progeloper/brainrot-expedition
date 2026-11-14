--!strict
-- Guards: the regional NPCs (called villagers in code). Owner, 14 Nov 2026: "all villagers
-- should be regular npcs, with the v4 style eyes (japanese anime eyes) and their uniforms";
-- "we'll call them guards going forward". Every guard is an ordinary person on the one guard
-- body (Config/VillagerBody, 24 uploaded animations) wearing their region's uniform
-- (Uniform_<Region>), with their own skin tone, hair and eye colour. No animal parts.
--
-- A guard skin carries its own full `palette`: the region's uniform colours plus the guard's
-- skin, skin2 (nose) and hair. Playback should build a guard with `skin.palette`.
local S = require(script.Parent.Support)
local B = S.Box

local Guard = {}

export type Look = {
	id: string,
	villagerId: string,
	name: string,
	uniform: any,
	skin: string,
	skin2: string,
	hair: string,
	style: string, -- "Short", "Long", "Bun" or "Beard"
	eyes: string, -- iris family (Config/VoxelCreaturePalette IrisFamilies)
	activities: { string }?,
}

-- The face: big V4 anime eyes, brows in the hair colour, a small nose, a smiling mouth, blush.
local function face(eyes: string): { any }
	return S.Join(S.Eyes(4.45, -0.9, 0.5, 0.76, 0.84, eyes), {
		B(
			"Head",
			"face",
			"Mouth",
			-0.34,
			3.84,
			-0.94,
			0.34,
			3.98,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.16,
			3.84,
			-0.95,
			0.16,
			3.89,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		B("Head", "face", "Nose", -0.13, 4.06, -1.04, 0.13, 4.26, -0.9, "skin2"),
		B("Head", "face", "Brow_L", -0.84, 4.9, -0.95, -0.18, 4.98, -0.9, "hair"),
		B("Head", "face", "Brow_R", 0.18, 4.9, -0.95, 0.84, 4.98, -0.9, "hair"),
		B(
			"Head",
			"face",
			"Blush_L",
			-1.0,
			3.96,
			-0.93,
			-0.7,
			4.04,
			-0.9,
			"Protected",
			{ color = "#FF8FA3" }
		),
		B(
			"Head",
			"face",
			"Blush_R",
			0.7,
			3.96,
			-0.93,
			1.0,
			4.04,
			-0.9,
			"Protected",
			{ color = "#FF8FA3" }
		),
	})
end

-- Hair on the Head bone, never above the head top (y 5.05): hats live on the Hat bone above.
local function hair(style: string, hooded: boolean): { any }
	local out = {
		B("Head", "headwear", "Fringe", -1.0, 5.0, -0.95, 1.0, 5.05, -0.9, "hair"),
	}
	if not hooded then
		table.insert(
			out,
			B(
				"Head",
				"headwear",
				"HairTop",
				-1.08,
				4.98,
				-0.92,
				1.08,
				5.05,
				0.98,
				"hair",
				{ relief = true }
			)
		)
		table.insert(
			out,
			B(
				"Head",
				"headwear",
				"HairBack",
				-1.1,
				4.15,
				0.9,
				1.1,
				5.05,
				1.02,
				"hair",
				{ relief = true }
			)
		)
		table.insert(
			out,
			B("Head", "headwear", "HairSide_L", -1.12, 4.4, -0.35, -1.05, 5.05, 1.0, "hair")
		)
		table.insert(
			out,
			B("Head", "headwear", "HairSide_R", 1.05, 4.4, -0.35, 1.12, 5.05, 1.0, "hair")
		)
		if style == "Long" then
			table.insert(
				out,
				B(
					"Head",
					"headwear",
					"HairLong",
					-1.0,
					3.55,
					0.92,
					1.0,
					4.15,
					1.06,
					"hair",
					{ relief = true }
				)
			)
			table.insert(
				out,
				B("Head", "headwear", "Lock_L", -1.12, 3.75, 0.2, -1.05, 4.4, 0.95, "hair")
			)
			table.insert(
				out,
				B("Head", "headwear", "Lock_R", 1.05, 3.75, 0.2, 1.12, 4.4, 0.95, "hair")
			)
		elseif style == "Bun" then
			table.insert(
				out,
				B(
					"Head",
					"headwear",
					"Bun",
					-0.32,
					4.45,
					1.0,
					0.32,
					4.95,
					1.4,
					"hair",
					{ relief = true }
				)
			)
		end
	end
	if style == "Beard" then
		table.insert(
			out,
			B(
				"Head",
				"face",
				"Beard",
				-0.86,
				3.6,
				-0.95,
				0.86,
				3.82,
				-0.9,
				"hair",
				{ relief = true }
			)
		)
		table.insert(
			out,
			B("Head", "face", "Moustache", -0.4, 3.98, -0.97, 0.4, 4.05, -0.93, "hair")
		)
		table.insert(
			out,
			B("Head", "face", "Sideburn_L", -1.1, 3.8, -0.6, -1.05, 4.4, -0.2, "hair")
		)
		table.insert(out, B("Head", "face", "Sideburn_R", 1.05, 3.8, -0.6, 1.1, 4.4, -0.2, "hair"))
	end
	return out
end

function Guard.Make(look: Look): any
	local uniform = look.uniform
	local palette: { [string]: string } = table.clone(uniform.palette)
	palette.skin, palette.skin2, palette.hair = look.skin, look.skin2, look.hair
	return table.freeze({
		id = look.id,
		villagerId = look.villagerId,
		name = look.name,
		region = uniform.region,
		approved = true, -- owner approved the human guard batch, 14 Nov 2026
		hooks = table.freeze({ uniform.outfit, "V4 anime eyes" }),
		activities = table.freeze(look.activities or {}),
		palette = table.freeze(palette),
		boxes = table.freeze(
			S.Join(face(look.eyes), hair(look.style, uniform.hooded == true), uniform.boxes)
		),
	})
end

return table.freeze(Guard)
