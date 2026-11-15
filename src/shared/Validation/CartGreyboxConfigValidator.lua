--!strict

local CartGreyboxSectionIds = require(script.Parent.Parent.Constants.CartGreyboxSectionIds)
local CartGreyboxPerformanceIds = require(script.Parent.Parent.Constants.CartGreyboxPerformanceIds)

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

local CartGreyboxConfigValidator = {}

local VALID_KINDS: { [string]: boolean } = table.freeze({
	Flat = true,
	RampUp = true,
	RampDown = true,
	SideSlope = true,
	Crest = true,
	Bumps = true,
	Narrow = true,
	CameraWall = true,
	CameraCorner = true,
	Collision = true,
	Tilt = true,
	Stuck = true,
	Multiplayer = true,
	Performance = true,
})

local MULTI_LANE_COUNTS: { [string]: number } = table.freeze({
	[CartGreyboxSectionIds.MultiplayerOpenArea] = 3,
	[CartGreyboxPerformanceIds.TwelveCartLoadZone] = 12,
})

local REQUIRED_TOP_LEVEL_FIELDS: { [string]: boolean } = table.freeze({
	CanonicalSpawnId = true,
	CartId = true,
	RuntimeDevelopmentFolderName = true,
	RouteFolderName = true,
	OwnedAttribute = true,
	SectionIdAttribute = true,
	SpawnIdPrefix = true,
	SpawnPriorityBase = true,
	RouteOffset = true,
	GridSpacing = true,
	FloorThickness = true,
	Sections = true,
})

local REQUIRED_SECTION_FIELDS: { [string]: boolean } = table.freeze({
	Id = true,
	Label = true,
	Kind = true,
	GridColumn = true,
	GridRow = true,
	Footprint = true,
	StartOffset = true,
})

local ALLOWED_SECTION_FIELDS: { [string]: boolean } = table.freeze({
	Id = true,
	Label = true,
	Kind = true,
	GridColumn = true,
	GridRow = true,
	Footprint = true,
	StartOffset = true,
	SpawnOffsets = true,
})

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function vector2IsFinite(value: Vector2): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y)
end

local function vector3IsFinite(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function requireNonEmptyString(container: { [any]: any }, field: string, errors: { string })
	local value = container[field]

	if type(value) ~= "string" or value == "" then
		addError(errors, string.format("%s must be a non-empty string", field))
	end
end

local function rejectUnknownFields(
	container: { [any]: any },
	allowed: { [string]: boolean },
	path: string,
	errors: { string }
)
	for field in container do
		if type(field) ~= "string" or not allowed[field] then
			addError(
				errors,
				string.format("%s contains unsupported field %s", path, tostring(field))
			)
		end
	end
end

local function validateSection(
	sectionValue: unknown,
	index: number,
	seenIds: { [string]: boolean },
	seenGridCells: { [string]: boolean },
	expectedIds: { [string]: boolean },
	errors: { string }
)
	local path = string.format("Sections[%d]", index)

	if type(sectionValue) ~= "table" then
		addError(errors, string.format("%s must be a table", path))
		return
	end

	local section = sectionValue :: { [any]: any }

	rejectUnknownFields(section, ALLOWED_SECTION_FIELDS, path, errors)

	for field in REQUIRED_SECTION_FIELDS do
		if section[field] == nil then
			addError(errors, string.format("%s.%s is required", path, field))
		end
	end
	requireNonEmptyString(section, "Id", errors)
	requireNonEmptyString(section, "Label", errors)

	local id = section.Id

	if type(id) == "string" and id ~= "" then
		if not expectedIds[id] then
			addError(errors, string.format("%s.Id is not a central greybox section ID", path))
		elseif seenIds[id] then
			addError(errors, string.format("%s.Id duplicates %s", path, id))
		else
			seenIds[id] = true
		end
	end

	if type(section.Kind) ~= "string" or not VALID_KINDS[section.Kind] then
		addError(errors, string.format("%s.Kind is unsupported", path))
	elseif
		section.Id == CartGreyboxPerformanceIds.TwelveCartLoadZone
		and section.Kind ~= "Performance"
	then
		addError(errors, string.format("%s.Kind must be Performance", path))
	elseif
		section.Id == CartGreyboxSectionIds.MultiplayerOpenArea
		and section.Kind ~= "Multiplayer"
	then
		addError(errors, string.format("%s.Kind must be Multiplayer", path))
	end

	for _, field in { "GridColumn", "GridRow" } do
		local value = section[field]

		if not isFiniteNumber(value) or value < 0 or value % 1 ~= 0 then
			addError(errors, string.format("%s.%s must be a nonnegative integer", path, field))
		end
	end

	if
		isFiniteNumber(section.GridColumn)
		and section.GridColumn >= 0
		and section.GridColumn % 1 == 0
		and isFiniteNumber(section.GridRow)
		and section.GridRow >= 0
		and section.GridRow % 1 == 0
	then
		local gridCell = string.format("%d:%d", section.GridColumn, section.GridRow)

		if seenGridCells[gridCell] then
			addError(errors, string.format("%s duplicates route grid cell %s", path, gridCell))
		else
			seenGridCells[gridCell] = true
		end
	end

	if typeof(section.Footprint) ~= "Vector2" then
		addError(errors, string.format("%s.Footprint must be a Vector2", path))
	else
		local footprint = section.Footprint :: Vector2

		if not vector2IsFinite(footprint) or footprint.X <= 0 or footprint.Y <= 0 then
			addError(
				errors,
				string.format("%s.Footprint must contain positive finite values", path)
			)
		end
	end

	if typeof(section.StartOffset) ~= "Vector3" then
		addError(errors, string.format("%s.StartOffset must be a Vector3", path))
	elseif not vector3IsFinite(section.StartOffset :: Vector3) then
		addError(errors, string.format("%s.StartOffset must be finite", path))
	end

	local spawnOffsets = section.SpawnOffsets

	local expectedLaneCount = if type(section.Id) == "string"
		then MULTI_LANE_COUNTS[section.Id]
		else nil

	if expectedLaneCount ~= nil then
		if type(spawnOffsets) ~= "table" or #spawnOffsets ~= expectedLaneCount then
			addError(
				errors,
				string.format("%s.SpawnOffsets must contain %d lanes", path, expectedLaneCount)
			)
		else
			local validatedOffsets: { Vector3 } = {}

			for laneIndex, spawnOffset in spawnOffsets do
				if typeof(spawnOffset) ~= "Vector3" or not vector3IsFinite(spawnOffset) then
					addError(
						errors,
						string.format("%s.SpawnOffsets[%d] must be finite", path, laneIndex)
					)
				else
					local offset = spawnOffset :: Vector3

					for _, previousOffset in validatedOffsets do
						if (offset - previousOffset).Magnitude <= 24 then
							addError(
								errors,
								string.format("%s.SpawnOffsets lanes must not overlap", path)
							)
						end
					end

					table.insert(validatedOffsets, offset)
				end
			end
		end
	elseif spawnOffsets ~= nil then
		addError(
			errors,
			string.format(
				"%s.SpawnOffsets is not supported for section %s",
				path,
				tostring(section.Id)
			)
		)
	end
end

function CartGreyboxConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "greybox configuration must be a table" },
		}
	end

	local values = config :: { [any]: any }

	rejectUnknownFields(values, REQUIRED_TOP_LEVEL_FIELDS, "CartGreybox", errors)

	for _, field in
		{
			"CanonicalSpawnId",
			"CartId",
			"RuntimeDevelopmentFolderName",
			"RouteFolderName",
			"OwnedAttribute",
			"SectionIdAttribute",
			"SpawnIdPrefix",
		}
	do
		requireNonEmptyString(values, field, errors)
	end

	if
		not isFiniteNumber(values.SpawnPriorityBase)
		or values.SpawnPriorityBase < 0
		or values.SpawnPriorityBase % 1 ~= 0
	then
		addError(errors, "SpawnPriorityBase must be a nonnegative integer")
	end

	if typeof(values.RouteOffset) ~= "Vector3" then
		addError(errors, "RouteOffset must be a Vector3")
	elseif not vector3IsFinite(values.RouteOffset :: Vector3) then
		addError(errors, "RouteOffset must be finite")
	end

	if typeof(values.GridSpacing) ~= "Vector2" then
		addError(errors, "GridSpacing must be a Vector2")
	else
		local spacing = values.GridSpacing :: Vector2

		if not vector2IsFinite(spacing) or spacing.X <= 0 or spacing.Y <= 0 then
			addError(errors, "GridSpacing must contain positive finite values")
		end
	end

	if not isFiniteNumber(values.FloorThickness) or values.FloorThickness <= 0 then
		addError(errors, "FloorThickness must be a positive finite number")
	end

	local expectedIds: { [string]: boolean } = {}

	for _, id in CartGreyboxSectionIds do
		expectedIds[id] = true
	end

	expectedIds[CartGreyboxPerformanceIds.TwelveCartLoadZone] = true

	local sectionsValue = values.Sections

	if type(sectionsValue) ~= "table" then
		addError(errors, "Sections must be a table")
	else
		local sections = sectionsValue :: { any }
		local seenIds: { [string]: boolean } = {}
		local seenGridCells: { [string]: boolean } = {}

		for index, sectionValue in sections do
			if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
				addError(errors, "Sections must be an array")
				continue
			end

			validateSection(sectionValue, index, seenIds, seenGridCells, expectedIds, errors)
		end

		for id in expectedIds do
			if not seenIds[id] then
				addError(errors, string.format("Sections is missing central section ID %s", id))
			end
		end
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartGreyboxConfigValidator)
