--!strict

local CollisionGroups = {
	Default = "Default",
	Carts = "Carts",
	Players = "Players",
	Brainrots = "Brainrots",
	CargoVisuals = "CargoVisuals",
	FormationVisuals = "FormationVisuals",
	Projectiles = "Projectiles",
	-- Playtest Fixes 2 Part D: invisible base wall colliders (authored in the place; collide with all).
	BaseWalls = "BaseWalls",
}

return table.freeze(CollisionGroups)
