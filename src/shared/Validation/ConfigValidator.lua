--!strict

local ConfigValidator = {}

function ConfigValidator.AssertUniqueIds(categoryName: string, entries: { [string]: string })
	local seen: { [string]: string } = {}

	for key, id in entries do
		assert(
			type(id) == "string" and id ~= "",
			string.format("%s.%s has an invalid ID", categoryName, key)
		)

		local previousKey = seen[id]

		assert(
			previousKey == nil,
			string.format(
				"%s contains duplicate ID %s for %s and %s",
				categoryName,
				id,
				previousKey or "?",
				key
			)
		)

		seen[id] = key
	end
end

local function finitePositive(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function ConfigValidator.AssertBrainrotPopulation(configName: string, config: { [string]: any })
	for _, key in
		{
			"TargetWildPopulation",
			"ReplenishDelaySeconds",
			"RetryDelaySeconds",
			"MaxSpawnReservationsPerPass",
		}
	do
		assert(
			finitePositive(config[key]),
			string.format("%s.%s must be finite and positive", configName, key)
		)
	end
	assert(
		config.TargetWildPopulation % 1 == 0,
		configName .. ".TargetWildPopulation must be an integer"
	)
	assert(
		config.MaxSpawnReservationsPerPass % 1 == 0,
		configName .. ".MaxSpawnReservationsPerPass must be an integer"
	)
	assert(
		type(config.NaturalReplenishmentEnabled) == "boolean",
		configName .. ".NaturalReplenishmentEnabled must be a boolean"
	)
	assert(
		type(config.ProfileAdmissionCaps) == "table",
		configName .. ".ProfileAdmissionCaps must be a table"
	)
	local requiredProfiles = {
		"Wanderer",
		"ReactiveRunner",
		"Sprinter",
		"Zigzag",
		"Camouflage",
		"DecoySplit",
		"LegendaryPursuit",
		"MythicEvent",
	}
	local requiredSet = {}
	for _, profile in requiredProfiles do
		requiredSet[profile] = true
		local cap = config.ProfileAdmissionCaps[profile]
		assert(
			finitePositive(cap) and cap % 1 == 0,
			string.format(
				"%s.ProfileAdmissionCaps.%s must be a positive integer",
				configName,
				profile
			)
		)
	end
	for profile in config.ProfileAdmissionCaps do
		assert(
			requiredSet[profile] == true,
			string.format(
				"%s.ProfileAdmissionCaps has unknown profile %s",
				configName,
				tostring(profile)
			)
		)
	end
end

function ConfigValidator.AssertBrainrotTerritory(configName: string, config: { [string]: any })
	assert(
		finitePositive(config.MaxPlacementAttemptsPerSpawn)
			and config.MaxPlacementAttemptsPerSpawn % 1 == 0,
		configName .. ".MaxPlacementAttemptsPerSpawn must be a positive integer"
	)
	assert(
		finitePositive(config.BoundaryPaddingStuds),
		configName .. ".BoundaryPaddingStuds must be finite and positive"
	)
	assert(
		type(config.MinWalkableNormalY) == "number"
			and config.MinWalkableNormalY == config.MinWalkableNormalY
			and config.MinWalkableNormalY > 0
			and config.MinWalkableNormalY <= 1,
		configName .. ".MinWalkableNormalY must be in (0, 1]"
	)
end

function ConfigValidator.AssertSprinterProfile(profileName: string, profile: { [string]: any })
	for _, key in
		{
			"AwarenessRadius",
			"DisengageRadius",
			"DisengageGraceSeconds",
			"SenseIntervalSeconds",
			"BurstDurationSeconds",
			"AccelerationSeconds",
			"BurstSpeedMultiplier",
			"RecoveryDurationSeconds",
			"RecoveryDecelerationSeconds",
			"RecoverySpeedMultiplier",
			"RecoveryMaxSpeedStudsPerSecond",
			"CooldownDurationSeconds",
			"ReturnToNormalSeconds",
			"NormalEscapeReplanSeconds",
			"MinimumBurstClearanceStuds",
			"BlockedRetrySeconds",
		}
	do
		assert(
			finitePositive(profile[key]),
			string.format("%s.%s must be finite and positive", profileName, key)
		)
	end
	assert(
		profile.AccelerationSeconds <= profile.BurstDurationSeconds,
		profileName .. ".AccelerationSeconds must fit inside BurstDurationSeconds"
	)
	assert(
		profile.RecoveryDecelerationSeconds <= profile.RecoveryDurationSeconds,
		profileName .. ".RecoveryDecelerationSeconds must fit inside RecoveryDurationSeconds"
	)
	assert(
		profile.RecoverySpeedMultiplier > 0 and profile.RecoverySpeedMultiplier < 1,
		profileName .. ".RecoverySpeedMultiplier must be between zero and one"
	)
	assert(profile.BurstSpeedMultiplier > 1, profileName .. ".BurstSpeedMultiplier must exceed one")
	assert(
		profile.DisengageRadius >= profile.AwarenessRadius,
		profileName .. ".DisengageRadius must not be smaller than AwarenessRadius"
	)
end

function ConfigValidator.AssertZigzagProfile(profileName: string, profile: { [string]: any })
	for _, key in
		{
			"AwarenessRadius",
			"DisengageRadius",
			"DisengageGraceSeconds",
			"SenseIntervalSeconds",
			"SweepDurationSeconds",
			"StraightDurationSeconds",
			"SweepTurnSeconds",
			"MaxSweepAngleDegrees",
			"MaxLateralOffsetStuds",
			"CourseRefreshThresholdDegrees",
			"MaxCourseChangeDegrees",
			"CourseReorientSeconds",
			"BlockedRetrySeconds",
		}
	do
		assert(
			finitePositive(profile[key]),
			string.format("%s.%s must be finite and positive", profileName, key)
		)
	end
	assert(
		2 * profile.SweepTurnSeconds < profile.SweepDurationSeconds,
		profileName .. ".SweepTurnSeconds must leave a positive sweep hold interval"
	)
	assert(
		profile.MaxSweepAngleDegrees > 0 and profile.MaxSweepAngleDegrees < 90,
		profileName .. ".MaxSweepAngleDegrees must be strictly between zero and 90"
	)
	assert(
		profile.InitialSide == 1 or profile.InitialSide == -1,
		profileName .. ".InitialSide must equal 1 or -1"
	)
	assert(
		profile.DisengageRadius >= profile.AwarenessRadius,
		profileName .. ".DisengageRadius must not be smaller than AwarenessRadius"
	)
	assert(
		profile.CourseRefreshThresholdDegrees <= 180 and profile.MaxCourseChangeDegrees <= 180,
		profileName .. " course angles must not exceed 180 degrees"
	)
end

function ConfigValidator.AssertCamouflageProfile(profileName: string, profile: { [string]: any })
	for _, key in
		{
			"AwarenessRadius",
			"DisengageRadius",
			"DisengageGraceSeconds",
			"SenseIntervalSeconds",
			"RevealPeriodSeconds",
			"FullRevealSeconds",
			"ConcealFadeSeconds",
			"RevealFadeSeconds",
			"RevealCueSeconds",
		}
	do
		assert(
			finitePositive(profile[key]),
			string.format("%s.%s must be finite and positive", profileName, key)
		)
	end
	assert(
		type(profile.ConcealAmount) == "number"
			and profile.ConcealAmount == profile.ConcealAmount
			and profile.ConcealAmount > 0
			and profile.ConcealAmount < 1,
		profileName .. ".ConcealAmount must be strictly between zero and one"
	)
	assert(
		type(profile.RevealCueOutlineTransparency) == "number"
			and profile.RevealCueOutlineTransparency == profile.RevealCueOutlineTransparency
			and profile.RevealCueOutlineTransparency >= 0
			and profile.RevealCueOutlineTransparency <= 1,
		profileName .. ".RevealCueOutlineTransparency must be between zero and one"
	)
	assert(
		profile.FullRevealSeconds + profile.ConcealFadeSeconds + profile.RevealFadeSeconds
			< profile.RevealPeriodSeconds,
		profileName .. " reveal and fade intervals must leave a positive hidden interval"
	)
	assert(
		profile.RevealCueSeconds <= profile.FullRevealSeconds,
		profileName .. ".RevealCueSeconds must fit inside FullRevealSeconds"
	)
	assert(
		profile.DisengageRadius >= profile.AwarenessRadius,
		profileName .. ".DisengageRadius must not be smaller than AwarenessRadius"
	)
end

function ConfigValidator.AssertDecoySplitProfile(profileName: string, profile: { [string]: any })
	for _, key in
		{
			"AwarenessRadius",
			"DisengageRadius",
			"DisengageGraceSeconds",
			"SenseIntervalSeconds",
			"MaxDecoysPerEncounter",
			"MaxActiveEncounters",
			"ActiveDurationSeconds",
			"CooldownSeconds",
			"FailedStartRetrySeconds",
			"DecoyUpdateIntervalSeconds",
			"MinimumSpacingStuds",
			"MaximumSpacingStuds",
			"SeparationPaddingStuds",
			"CuePulsePeriodSeconds",
			"CuePulseDurationSeconds",
			"TrailLifetimeSeconds",
			"TrailMaxLengthStuds",
			"TrailWidthStuds",
		}
	do
		assert(
			finitePositive(profile[key]),
			string.format("%s.%s must be finite and positive", profileName, key)
		)
	end
	for _, key in { "MaxDecoysPerEncounter", "MaxActiveEncounters" } do
		assert(profile[key] % 1 == 0, string.format("%s.%s must be an integer", profileName, key))
	end
	assert(
		profile.DisengageRadius >= profile.AwarenessRadius,
		profileName .. ".DisengageRadius must not be smaller than AwarenessRadius"
	)
	assert(
		profile.MaximumSpacingStuds >= profile.MinimumSpacingStuds,
		profileName .. ".MaximumSpacingStuds must not be smaller than MinimumSpacingStuds"
	)
	assert(
		profile.CuePulseDurationSeconds <= profile.CuePulsePeriodSeconds,
		profileName .. ".CuePulseDurationSeconds must fit inside CuePulsePeriodSeconds"
	)
	assert(
		profile.MaxDecoysPerEncounter == 2 and profile.MaxActiveEncounters == 2,
		profileName .. " must preserve the approved two-by-two effect cap"
	)
end

function ConfigValidator.AssertLegendaryPursuitProfile(
	profileName: string,
	profile: { [string]: any },
	sprinterProfile: { [string]: any },
	zigzagProfile: { [string]: any }
)
	for _, key in
		{
			"AwarenessRadius",
			"DisengageRadius",
			"DisengageGraceSeconds",
			"SenseIntervalSeconds",
			"OpeningDurationSeconds",
			"ZigzagCycleCount",
			"RepeatCooldownSeconds",
			"BlockedRetrySeconds",
			"MaxActiveEncounters",
			"MaxUpdateGapSeconds",
		}
	do
		assert(
			finitePositive(profile[key]),
			string.format("%s.%s must be finite and positive", profileName, key)
		)
	end
	for _, key in { "ZigzagCycleCount", "MaxActiveEncounters" } do
		assert(profile[key] % 1 == 0, string.format("%s.%s must be an integer", profileName, key))
	end
	assert(
		profile.DisengageRadius >= profile.AwarenessRadius,
		profileName .. ".DisengageRadius must not be smaller than AwarenessRadius"
	)
	assert(
		profile.MaxActiveEncounters == 1,
		profileName .. " must preserve the approved one-active-encounter budget"
	)
	ConfigValidator.AssertSprinterProfile(profileName .. ".SprinterDependency", sprinterProfile)
	ConfigValidator.AssertZigzagProfile(profileName .. ".ZigzagDependency", zigzagProfile)
end

return ConfigValidator
