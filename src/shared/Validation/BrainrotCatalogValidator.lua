--!strict

local Brainrots = require(script.Parent.Parent.Config.BrainrotCatalog)
local Rarities = require(script.Parent.Parent.Config.Rarities)
local Regions = require(script.Parent.Parent.Config.Regions)
local Effects = require(script.Parent.Parent.Config.ChariotEffectDefinitions)

export type ValidationSeverity = "Error" | "Warning"

export type ValidationIssue = {
	severity: ValidationSeverity,
	code: string,
	speciesId: string?,
	message: string,
}

export type ValidationReport = {
	errors: { ValidationIssue },
	warnings: { ValidationIssue },
}

local Validator = {}
local EXPECTED_COUNT = 35
local validLaunchStatuses = { Live = true, Teased = true }
local validRegionAssignmentStatuses = { Approved = true, Pending = true, Conflict = true }
local validExpeditionRoles = {
	Sprinter = true,
	Tracker = true,
	Wrangler = true,
	Hauler = true,
	Trickster = true,
	Lucky = true,
}
local validBehaviours = {
	Wanderer = true,
	ReactiveRunner = true,
	Sprinter = true,
	Trickster = true,
	Hauler = true,
	Zigzag = true,
	Camouflage = true,
	DecoySplit = true,
	LegendaryPursuit = true,
	MythicEvent = true,
	Pending = true,
}

local function issue(
	report: ValidationReport,
	severity: ValidationSeverity,
	code: string,
	speciesId: string?,
	message: string
)
	local item: ValidationIssue = {
		severity = severity,
		code = code,
		speciesId = speciesId,
		message = message,
	}
	table.insert(if severity == "Error" then report.errors else report.warnings, item)
end

local function finitePositive(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge and value > 0
end

local function nonEmpty(value: any): boolean
	return type(value) == "string" and string.match(value, "%S") ~= nil
end

local function append(target: ValidationReport, source: ValidationReport)
	for _, item in source.errors do
		table.insert(target.errors, item)
	end
	for _, item in source.warnings do
		table.insert(target.warnings, item)
	end
end

function Validator.ValidateDefinitions(definitions: { any }): ValidationReport
	local report: ValidationReport = { errors = {}, warnings = {} }
	local seen: { [string]: string } = {}
	local present: { [string]: boolean } = {}

	if #definitions < EXPECTED_COUNT then
		issue(
			report,
			"Error",
			"UNEXPECTED_ROSTER_COUNT",
			nil,
			string.format("expected at least the %d legacy definitions, found %d", EXPECTED_COUNT, #definitions)
		)
	end

	for index, definition in definitions do
		if type(definition) ~= "table" then
			issue(
				report,
				"Error",
				"INVALID_ID",
				nil,
				string.format("definition %d is not a table", index)
			)
			continue
		end
		local rawId = definition.id
		local normalized = Brainrots.NormalizeId(rawId)
		local speciesId = normalized or if type(rawId) == "string" then rawId else nil
		if normalized == nil or rawId ~= normalized then
			issue(report, "Error", "INVALID_ID", speciesId, "id must use canonical BRT_ddd form")
		end
		if normalized then
			local previous = seen[normalized]
			if previous then
				issue(
					report,
					"Error",
					"DUPLICATE_ID",
					normalized,
					string.format("normalizes to the same ID as %s", previous)
				)
			else
				seen[normalized] = tostring(rawId)
				present[normalized] = true
			end
		end

		if definition.chariotEffect ~= nil then
			append(report, Effects.ValidateSpeciesEffectReport(definition.chariotEffect, speciesId))
		end

		if not nonEmpty(definition.displayName) then
			issue(report, "Error", "MISSING_DISPLAY_NAME", speciesId, "displayName is empty")
		end
		if not Rarities.IsValid(definition.tier) then
			issue(report, "Error", "INVALID_TIER", speciesId, "tier is not supported")
		end
		if not nonEmpty(definition.modelRef) then
			issue(report, "Error", "MISSING_MODEL_REF", speciesId, "modelRef is empty")
		end
		if not finitePositive(definition.cashPerSecond) then
			issue(
				report,
				"Error",
				"INVALID_CASH_PER_SECOND",
				speciesId,
				"cashPerSecond must be a finite number greater than zero"
			)
		end
		if not finitePositive(definition.sellValue) or definition.sellValue % 1 ~= 0 then
			issue(
				report,
				"Error",
				"INVALID_SELL_VALUE",
				speciesId,
				"sellValue must be a positive finite integer"
			)
		end
		if not validLaunchStatuses[definition.launchStatus] then
			issue(
				report,
				"Error",
				"INVALID_LAUNCH_STATUS",
				speciesId,
				"launchStatus is not supported"
			)
		end
		if not validBehaviours[definition.behaviourId] then
			issue(
				report,
				"Error",
				"INVALID_BEHAVIOUR_ID",
				speciesId,
				"behaviourId is not supported"
			)
		end
		if not validExpeditionRoles[definition.expeditionRole] then
			issue(
				report,
				"Error",
				"INVALID_EXPEDITION_ROLE",
				speciesId,
				"expeditionRole is not supported"
			)
		end
		if type(definition.spawnEnabled) ~= "boolean" then
			issue(
				report,
				"Error",
				"INVALID_SPAWN_ENABLED",
				speciesId,
				"spawnEnabled must be a boolean"
			)
		elseif definition.spawnEnabled and definition.behaviourId == "Pending" then
			issue(
				report,
				"Error",
				"ENABLED_WITH_PENDING_BEHAVIOUR",
				speciesId,
				"a Pending behaviour cannot be declared spawn-enabled"
			)
		end
		local status = definition.regionAssignmentStatus
		if not validRegionAssignmentStatuses[status] then
			issue(
				report,
				"Error",
				"INVALID_REGION_ASSIGNMENT_STATUS",
				speciesId,
				"regionAssignmentStatus must be Approved, Pending or Conflict"
			)
		end

		local homeRegionId = definition.homeRegionId
		local normalizedHome = Regions.NormalizeId(homeRegionId)
		if homeRegionId ~= nil and (normalizedHome == nil or homeRegionId ~= normalizedHome) then
			issue(report, "Error", "UNKNOWN_REGION", speciesId, "homeRegionId is not canonical")
		end

		local allowedRegionIds = definition.allowedRegionIds
		local allowedSet: { [string]: boolean } = {}
		if type(allowedRegionIds) ~= "table" then
			issue(
				report,
				"Error",
				"INVALID_ALLOWED_REGION_IDS",
				speciesId,
				"allowedRegionIds must be an array"
			)
		else
			for _, rawRegionId in allowedRegionIds do
				local regionId = Regions.NormalizeId(rawRegionId)
				if regionId == nil or rawRegionId ~= regionId then
					issue(
						report,
						"Error",
						"UNKNOWN_REGION",
						speciesId,
						"allowedRegionIds contains an unknown or non-canonical region"
					)
				elseif regionId == Regions.CampId then
					issue(
						report,
						"Error",
						"CAMP_NOT_SPAWNABLE",
						speciesId,
						"Camp cannot be an allowed natural-spawn region"
					)
				elseif allowedSet[regionId] then
					issue(
						report,
						"Error",
						"DUPLICATE_ALLOWED_REGION",
						speciesId,
						"allowedRegionIds contains " .. regionId .. " more than once"
					)
				else
					allowedSet[regionId] = true
				end
			end
		end

		if status == "Approved" then
			if normalizedHome == nil or next(allowedSet) == nil then
				issue(
					report,
					"Error",
					"INCOMPLETE_APPROVED_REGION_ASSIGNMENT",
					speciesId,
					"Approved assignments require a home and at least one allowed region"
				)
			elseif not allowedSet[normalizedHome] then
				issue(
					report,
					"Error",
					"HOME_NOT_ALLOWED",
					speciesId,
					"homeRegionId must appear in allowedRegionIds"
				)
			end
		elseif status == "Pending" then
			issue(
				report,
				"Warning",
				"REGION_ASSIGNMENT_PENDING",
				speciesId,
				"current-map home and allowed regions require approval"
			)
		elseif status == "Conflict" then
			issue(
				report,
				"Warning",
				"REGION_ASSIGNMENT_CONFLICT",
				speciesId,
				"approved sources conflict on the current-map assignment"
			)
		end
	end

	for index = 1, EXPECTED_COUNT do
		local id = string.format("BRT_%03d", index)
		if not present[id] then
			issue(report, "Error", "MISSING_ROSTER_ID", id, "required roster ID is absent")
		end
	end
	return report
end

function Validator.ValidateAssets(
	definitions: { any },
	brainrotAssetFolder: Instance?
): ValidationReport
	local report: ValidationReport = { errors = {}, warnings = {} }
	for _, definition in definitions do
		if type(definition) ~= "table" or not nonEmpty(definition.modelRef) then
			continue
		end
		local severity: ValidationSeverity = if definition.spawnEnabled == true
			then "Error"
			else "Warning"
		local model = if brainrotAssetFolder
			then brainrotAssetFolder:FindFirstChild(definition.modelRef)
			else nil
		if model == nil then
			issue(
				report,
				severity,
				"MISSING_MODEL",
				definition.id,
				string.format("modelRef %s was not found", definition.modelRef)
			)
		elseif not model:IsA("Model") then
			issue(
				report,
				severity,
				"MODEL_REF_NOT_MODEL",
				definition.id,
				string.format("modelRef %s resolves to %s", definition.modelRef, model.ClassName)
			)
		elseif model:FindFirstChildWhichIsA("BasePart", true) == nil then
			issue(
				report,
				severity,
				"MODEL_HAS_NO_BASEPART",
				definition.id,
				string.format("modelRef %s has no BasePart", definition.modelRef)
			)
		end
	end
	return report
end

function Validator.ValidateCatalog(brainrotAssetFolder: Instance?): ValidationReport
	local report: ValidationReport = { errors = {}, warnings = {} }
	local definitions = Brainrots.GetAll()
	append(report, Validator.ValidateDefinitions(definitions))
	append(report, Validator.ValidateAssets(definitions, brainrotAssetFolder))
	return report
end

function Validator.HasErrors(report: ValidationReport): boolean
	return #report.errors > 0
end

function Validator.FormatReport(report: ValidationReport): string
	local lines = {
		string.format(
			"Brainrot catalogue validation: %d error(s), %d warning(s)",
			#report.errors,
			#report.warnings
		),
	}
	local issues = {}
	for _, item in report.errors do
		table.insert(issues, item)
	end
	for _, item in report.warnings do
		table.insert(issues, item)
	end
	table.sort(issues, function(a, b)
		local left = string.format("%s|%s|%s|%s", a.severity, a.speciesId or "", a.code, a.message)
		local right = string.format("%s|%s|%s|%s", b.severity, b.speciesId or "", b.code, b.message)
		return left < right
	end)
	for _, item in issues do
		table.insert(
			lines,
			string.format(
				"[%s] %s%s: %s",
				item.severity,
				item.code,
				if item.speciesId then " (" .. item.speciesId .. ")" else "",
				item.message
			)
		)
	end
	return table.concat(lines, "\n")
end

return table.freeze(Validator)
