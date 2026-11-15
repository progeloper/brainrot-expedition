--!strict
-- Scoped broad surfaces; vehicle, creature, rarity and sky art retain their owners.
local A = require(script.Parent.AfternoonRepair)
return table.freeze({
	Version = A.Version,
	Grass = A.Colours.CampGrass,
	Path = A.Colours.CampPath,
	Wall = A.Colours.NeutralStructure,
	Trim = A.Colours.Metal,
	ShellLimit = 64,
	PanelInset = 0.12,
	GateColors = table.freeze({
		Jungle = Color3.fromRGB(74, 135, 66),
		Swamp = Color3.fromRGB(116, 145, 78),
		Arctic = Color3.fromRGB(153, 218, 237),
		Volcano = Color3.fromRGB(219, 100, 48),
		Beach = Color3.fromRGB(221, 191, 112),
		GlitchZone = Color3.fromRGB(160, 96, 220),
	}),
})
