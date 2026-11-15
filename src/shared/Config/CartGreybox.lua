--!strict

local Ids = require(script.Parent.Parent.Constants.Ids)
local PerformanceIds = require(script.Parent.Parent.Constants.CartGreyboxPerformanceIds)
local SectionIds = require(script.Parent.Parent.Constants.CartGreyboxSectionIds)

export type SectionKind =
	"Flat"
	| "RampUp"
	| "RampDown"
	| "SideSlope"
	| "Crest"
	| "Bumps"
	| "Narrow"
	| "CameraWall"
	| "CameraCorner"
	| "Collision"
	| "Tilt"
	| "Stuck"
	| "Multiplayer"
	| "Performance"

export type SectionDefinition = {
	Id: string,
	Label: string,
	Kind: SectionKind,
	GridColumn: number,
	GridRow: number,
	Footprint: Vector2,
	StartOffset: Vector3,
	SpawnOffsets: { Vector3 }?,
}

local function section(
	id: string,
	label: string,
	kind: SectionKind,
	column: number,
	row: number,
	footprint: Vector2?,
	spawnOffsets: { Vector3 }?,
	startOffset: Vector3?
): SectionDefinition
	return table.freeze({
		Id = id,
		Label = label,
		Kind = kind,
		GridColumn = column,
		GridRow = row,
		Footprint = footprint or Vector2.new(80, 64),
		StartOffset = startOffset or Vector3.new(0, 0, 22),
		SpawnOffsets = spawnOffsets,
	})
end

local MULTIPLAYER_SPAWN_OFFSETS = table.freeze({
	Vector3.new(-30, 0, 22),
	Vector3.new(0, 0, 22),
	Vector3.new(30, 0, 22),
})

local PERFORMANCE_SPAWN_OFFSETS: { Vector3 } = {}

for laneIndex = 1, 12 do
	local laneX = (laneIndex - 6.5) * 28

	table.insert(PERFORMANCE_SPAWN_OFFSETS, Vector3.new(laneX, 0, 90))
end

table.freeze(PERFORMANCE_SPAWN_OFFSETS)

local Sections: { SectionDefinition } = {
	section(SectionIds.FlatAcceleration, "Flat acceleration", "Flat", 0, 0),
	section(SectionIds.FlatBraking, "Flat braking", "Flat", 1, 0),
	section(SectionIds.Reverse, "Reverse", "Flat", 2, 0),
	section(SectionIds.SteeringLowSpeed, "Low-speed steering", "Flat", 3, 0),
	section(SectionIds.SteeringModerateSpeed, "Moderate-speed steering", "Flat", 4, 0),
	section(SectionIds.SteeringRapidChange, "Rapid steering changes", "Flat", 0, 1),
	section(SectionIds.GentleUphill, "Gentle uphill", "RampUp", 1, 1),
	section(SectionIds.GentleDownhill, "Gentle downhill", "RampDown", 2, 1),
	section(SectionIds.SideSlope, "Side slope", "SideSlope", 3, 1),
	section(SectionIds.HillCrest, "Hill crest", "Crest", 4, 1),
	section(SectionIds.SmallBumps, "Small bumps", "Bumps", 0, 2),
	section(SectionIds.NarrowPath, "Narrow path", "Narrow", 1, 2),
	section(SectionIds.CameraWall, "Camera wall", "CameraWall", 2, 2),
	section(SectionIds.CameraCorner, "Camera corner", "CameraCorner", 3, 2),
	section(SectionIds.ControlledCollision, "Controlled collision", "Collision", 4, 2),
	section(SectionIds.TiltRecovery, "Moderate tilt and recovery", "Tilt", 0, 3),
	section(SectionIds.ControlledStuck, "Controlled stuck location", "Stuck", 1, 3),
	section(SectionIds.CartReset, "Cart reset", "Flat", 2, 3),
	section(SectionIds.CartLifecycle, "Cart replacement and destruction", "Flat", 3, 3),
	section(
		SectionIds.MultiplayerOpenArea,
		"Open multiplayer movement area",
		"Multiplayer",
		4,
		3,
		Vector2.new(120, 80),
		MULTIPLAYER_SPAWN_OFFSETS
	),
	section(
		PerformanceIds.TwelveCartLoadZone,
		"Twelve-cart performance lanes",
		"Performance",
		7,
		1,
		Vector2.new(360, 220),
		PERFORMANCE_SPAWN_OFFSETS,
		PERFORMANCE_SPAWN_OFFSETS[1]
	),
}

table.freeze(Sections)

local CartGreybox = {
	-- Development fixture metadata. None of these values affect Production gameplay.
	CanonicalSpawnId = Ids.CartSpawns.Development,
	CartId = Ids.Carts.ScrapChariot,
	RuntimeDevelopmentFolderName = "Development",
	RouteFolderName = "Phase1SGreybox",
	OwnedAttribute = "Phase1SGreyboxOwned",
	SectionIdAttribute = "GreyboxSectionId",
	SpawnIdPrefix = "GBOX_SPAWN_",
	SpawnPriorityBase = 1000,
	RouteOffset = Vector3.new(-220, 12, -150),
	GridSpacing = Vector2.new(110, 90),
	FloorThickness = 1,
	Sections = Sections,
}

return table.freeze(CartGreybox)
