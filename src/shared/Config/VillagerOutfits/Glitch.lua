--!strict
-- Glitch Zone outfit set: "glitched remix" of the Forest and Beach outfits in the Glitch palette.
-- Reference card: docs/villagers/GlitchZone_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
-- reference colours). The region glow sits on ONE trim line; prop glows are allowed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local B = K.Box

local function tagged(slot: string, list: { any }): { any }
	for _, item in list do
		item.outfit = slot
	end
	return list
end
local function joined(...): { any }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end
local function mirrored(list: { any }): { any }
	return joined(list, K.Mirror(list))
end

local Forest = require(script.Parent.Forest)
local Beach = require(script.Parent.Beach)

-- Remix an existing outfit layer: extra hides, dropped adds, extra adds (pixel breaks etc.).
local function remix(
	base: any,
	name: string,
	extraHide: { string },
	drop: { string },
	extraAdd: { any },
	extraRoles: { string }
): any
	local dropped = {}
	for _, slot in drop do
		dropped[slot] = true
	end
	local add = {}
	for _, item in base.add do
		if not dropped[item.slot] then
			table.insert(add, item)
		end
	end
	local roles = table.clone(base.outfitRoles)
	for _, role in extraRoles do
		table.insert(roles, role)
	end
	return {
		name = name,
		hide = joined(base.hide, extraHide),
		add = joined(add, extraAdd),
		outfitRoles = roles,
	}
end

local GLITCH_VARIANT_GLOWS =
	{ "PixelBand", "PixelSpike1", "PixelSpike2", "Shard1", "Shard2", "Shard3" }

local sprinter = remix(
	Forest.outfits.Sprinter,
	"Glitched remix: Alpine loden work dress (men)",
	GLITCH_VARIANT_GLOWS,
	{},
	{
		B("PixelBreak1", -1.08, 3.2, -0.66, -0.86, 3.42, -0.62, "top2"),
		B("PixelBreak2", 0.3, 1.5, -0.37, 0.52, 1.72, -0.33, "top2"),
		B("PixelBreak3", 0.4, 5.55, -0.79, 0.62, 5.77, -0.75, "top2"),
	},
	{ "top2" }
)

local sprinterBeach = remix(
	Beach.outfits.Sprinter,
	"Glitched remix: southern Italian fisherman's work dress",
	GLITCH_VARIANT_GLOWS,
	{ "WhistleProp" },
	{
		B("PixelBreak1", -1.08, 3.0, -0.66, -0.86, 3.22, -0.62, "top2"),
		B("PixelBreak2", 0.3, 1.5, -0.37, 0.52, 1.72, -0.33, "top2"),
		B("PixelBreak3", 0.4, 5.45, -1.03, 0.62, 5.62, -0.99, "top2"),
	},
	{ "top2" }
)

-- Walking box (Plodder / Box): Alpine pieces refitted to the box; the error panel is a prop screen.
local plodder = {
	name = "Glitched remix: Alpine loden work dress (walking box)",
	hide = { "ErrorPanel" },
	add = joined(
		{ B("ErrorPanelScreen", -0.75, 1.3, -0.9, 0.75, 2.5, -0.85, "glow", { group = "Prop" }) },
		tagged("headwear", {
			B("FeltHatBrim", -1.25, 4.95, -1.1, 1.25, 5.05, 1.15, "hat", { group = "Hat" }),
			B(
				"FeltHatCrown",
				-0.8,
				5.05,
				-0.65,
				0.8,
				5.5,
				0.7,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("FeltHatBand", -0.82, 5.05, -0.67, 0.82, 5.15, 0.72, "glow", { group = "Hat" }),
		}),
		tagged(
			"top",
			joined(
				mirrored({
					B("JacketSide_L", -1.36, 1.0, -0.78, -1.3, 4.5, 0.84, "top", { relief = true }),
				}),
				{ B("JacketHem", -1.32, 0.6, -0.88, 1.32, 0.8, 0.92, "top") }
			)
		),
		tagged("bottom", mirrored({ B("Breeches_L", -0.9, 0.3, -0.3, -0.3, 0.62, 0.3, "bottom") })),
		tagged(
			"footwear",
			mirrored({ B("BootCuff_L", -0.98, 0.28, -0.84, -0.17, 0.4, 0.4, "shoe") })
		),
		tagged("accessory", {
			B("NeckerchiefBand", -1.32, 2.6, -0.88, 1.32, 2.8, 0.92, "acc"),
			B("NeckerchiefKnot", -0.15, 2.4, -0.92, 0.15, 2.6, -0.88, "acc"),
		}),
		{
			B("PixelBreak1", -1.4, 3.0, -0.2, -1.36, 3.25, 0.05, "top2"),
			B("PixelBreak2", 1.36, 1.8, 0.1, 1.4, 2.05, 0.35, "top2"),
			B("PixelBreak3", 0.4, 5.2, -0.69, 0.6, 5.4, -0.66, "top2"),
		}
	),
	outfitRoles = { "hat", "top", "top2", "bottom", "shoe", "acc" },
}

-- Speaker on legs (Shouter / Speaker): Beach crab fit; antenna tips become cyan pixels and the
-- speaker core glows as a prop, so the cap band is the one glow trim.
local shouter = remix(
	Beach.outfits.Shouter,
	"Glitched remix: southern Italian fisherman's work dress (speaker)",
	{
		"AntennaTip_L",
		"AntennaTip_R",
		"SpeakerCore",
	},
	{},
	joined(
		mirrored({
			B("AntennaPixel_L", -0.68, 5.1, -0.18, -0.42, 5.4, 0.08, "top2"),
		}),
		{
			B("SpeakerCoreProp", -0.3, 1.45, -1.28, 0.3, 2.0, -1.2, "glow", { group = "Prop" }),
			B("PixelBreak1", -1.36, 1.6, -1.07, -1.14, 1.82, -1.04, "top2"),
			B("PixelBreak2", 1.0, 2.1, -1.07, 1.22, 2.32, -1.04, "top2"),
		}
	),
	{ "top2" }
)

return table.freeze({
	set = "Glitch",
	regionId = "REGION_GLITCH",
	reference = "docs/villagers/GlitchZone_outfit_reference.md",
	palette = table.freeze({
		GlitchMagenta = "#FF49E1",
		GlitchCyan = "#3EFFF0",
		GlitchViolet = "#2B0F52",
		GlitchWhite = "#F7F5FC",
		GlitchDark = "#1D2133",
	}),
	glow = "#FF49E1",
	outfits = table.freeze({
		["Sprinter"] = sprinter,
		["Sprinter.Beach"] = sprinterBeach,
		["Plodder"] = plodder,
		["Shouter"] = shouter,
	}),
})
