--!strict

local ScenarioIds = require(script.Parent.Parent.Constants.CartGreyboxScenarioIds)
local SectionIds = require(script.Parent.Parent.Constants.CartGreyboxSectionIds)

export type EvidenceKind = "Automated" | "Manual" | "Hybrid"

export type ScenarioDefinition = {
	Id: string,
	Label: string,
	SectionId: string,
	AllowedSectionIds: { string },
	Evidence: EvidenceKind,
}

local function scenario(
	id: string,
	label: string,
	sectionId: string,
	evidence: EvidenceKind,
	allowedSectionIds: { string }?
): ScenarioDefinition
	local resolvedAllowedSectionIds = table.clone(allowedSectionIds or { sectionId })

	table.freeze(resolvedAllowedSectionIds)

	return table.freeze({
		Id = id,
		Label = label,
		SectionId = sectionId,
		AllowedSectionIds = resolvedAllowedSectionIds,
		Evidence = evidence,
	})
end

local Scenarios: { ScenarioDefinition } = {
	scenario(ScenarioIds.SpawnReadiness, "Spawn and readiness", SectionIds.CartLifecycle, "Hybrid"),
	scenario(
		ScenarioIds.DriverAuthority,
		"Driver entry and authority",
		SectionIds.CartLifecycle,
		"Hybrid"
	),
	scenario(
		ScenarioIds.FlatAcceleration,
		"Flat acceleration",
		SectionIds.FlatAcceleration,
		"Hybrid"
	),
	scenario(ScenarioIds.Coasting, "Coasting", SectionIds.FlatAcceleration, "Hybrid"),
	scenario(ScenarioIds.BrakingStopping, "Braking and stopping", SectionIds.FlatBraking, "Hybrid"),
	scenario(ScenarioIds.ReverseEngagement, "Reverse engagement", SectionIds.Reverse, "Hybrid"),
	scenario(ScenarioIds.Steering, "Steering", SectionIds.SteeringModerateSpeed, "Hybrid", {
		SectionIds.SteeringLowSpeed,
		SectionIds.SteeringModerateSpeed,
		SectionIds.SteeringRapidChange,
	}),
	scenario(ScenarioIds.Stability, "Two-wheel stability", SectionIds.TiltRecovery, "Hybrid"),
	scenario(ScenarioIds.Terrain, "Terrain interaction", SectionIds.GentleUphill, "Hybrid", {
		SectionIds.GentleUphill,
		SectionIds.GentleDownhill,
		SectionIds.SideSlope,
		SectionIds.HillCrest,
		SectionIds.SmallBumps,
	}),
	scenario(ScenarioIds.Collision, "Collision response", SectionIds.ControlledCollision, "Hybrid"),
	scenario(
		ScenarioIds.CameraBase,
		"Camera base behaviour",
		SectionIds.FlatAcceleration,
		"Hybrid"
	),
	scenario(
		ScenarioIds.CameraObstruction,
		"Camera obstruction",
		SectionIds.CameraWall,
		"Hybrid",
		{
			SectionIds.CameraWall,
			SectionIds.CameraCorner,
			SectionIds.NarrowPath,
		}
	),
	scenario(ScenarioIds.PCInput, "PC input", SectionIds.FlatAcceleration, "Hybrid"),
	scenario(ScenarioIds.TouchInput, "Touch input", SectionIds.FlatAcceleration, "Hybrid"),
	scenario(ScenarioIds.GamepadInput, "Gamepad input", SectionIds.FlatAcceleration, "Hybrid"),
	scenario(ScenarioIds.ResetSuccess, "Reset success", SectionIds.CartReset, "Hybrid", {
		SectionIds.CartReset,
		SectionIds.ControlledStuck,
	}),
	scenario(
		ScenarioIds.ResetSecurity,
		"Reset rejection and security",
		SectionIds.CartReset,
		"Hybrid"
	),
	scenario(
		ScenarioIds.MovementValidation,
		"Movement sanity validation",
		SectionIds.ControlledCollision,
		"Hybrid"
	),
	scenario(
		ScenarioIds.AnalyticsSequence,
		"Analytics sequence",
		SectionIds.CartLifecycle,
		"Hybrid"
	),
	scenario(ScenarioIds.CartReplacement, "Cart replacement", SectionIds.CartLifecycle, "Hybrid"),
	scenario(ScenarioIds.CartDestruction, "Cart destruction", SectionIds.CartLifecycle, "Hybrid"),
	scenario(
		ScenarioIds.CharacterLifecycle,
		"Character lifecycle",
		SectionIds.CartLifecycle,
		"Hybrid"
	),
	scenario(
		ScenarioIds.FocusInputContext,
		"Focus and input context",
		SectionIds.FlatAcceleration,
		"Manual"
	),
	scenario(
		ScenarioIds.MultiplayerIsolation,
		"Multiplayer isolation",
		SectionIds.MultiplayerOpenArea,
		"Hybrid"
	),
	scenario(
		ScenarioIds.LifecycleEndurance,
		"Repeated lifecycle endurance",
		SectionIds.CartLifecycle,
		"Hybrid"
	),
}

table.freeze(Scenarios)

local ById: { [string]: ScenarioDefinition } = {}

for _, definition in Scenarios do
	ById[definition.Id] = definition
end

table.freeze(ById)

local function resolveSectionId(scenarioId: string, requestedSectionId: string?): (string?, string?)
	local definition = ById[scenarioId]

	if definition == nil then
		return nil, string.format("unknown greybox scenario %s", scenarioId)
	end

	local selectedSectionId = requestedSectionId or definition.SectionId

	for _, allowedSectionId in definition.AllowedSectionIds do
		if allowedSectionId == selectedSectionId then
			return selectedSectionId, nil
		end
	end

	return nil,
		string.format(
			"section %s is not allowed for greybox scenario %s",
			selectedSectionId,
			scenarioId
		)
end

local CartGreyboxScenarios = {
	All = Scenarios,
	ById = ById,
	ResolveSectionId = resolveSectionId,
}

return table.freeze(CartGreyboxScenarios)
