--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartMovementSafety = require(ReplicatedStorage.Shared.Config.CartMovementSafety)
	local CartMovementValidation = require(ReplicatedStorage.Shared.Config.CartMovementValidation)
	local CartMovementValidationConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartMovementValidationConfigValidator)

	local DEVELOPMENT_NUMBER_FIELDS = {
		"SampleInterval",
		"ForwardSpeedMultiplier",
		"ForwardSpeedAdditive",
		"ReverseSpeedMultiplier",
		"ReverseSpeedAdditive",
		"LateralSpeedMultiplier",
		"LateralSpeedAdditive",
		"OverallSpeedMultiplier",
		"OverallSpeedAdditive",
		"CorrectiveHorizontalSpeedMultiplier",
		"CorrectiveHorizontalSpeedAdditive",
		"SevereHorizontalSpeedMultiplier",
		"SevereHorizontalSpeedAdditive",
		"DisplacementMultiplier",
		"DisplacementAdditive",
		"CorrectiveDisplacementMultiplier",
		"CorrectiveDisplacementAdditive",
		"SevereDisplacementMultiplier",
		"SevereDisplacementAdditive",
		"AccelerationMultiplier",
		"AccelerationAdditive",
		"UpwardSpeedObservation",
		"DownwardSpeedObservation",
		"VerticalDisplacementAdditive",
		"AngularSpeedMultiplier",
		"AngularSpeedAdditiveDegrees",
		"OwnershipTransitionGrace",
		"NoDriverAccelerationTolerance",
		"ObservationScoreIncrement",
		"CorrectiveScoreIncrement",
		"SevereScoreIncrement",
		"ValidSampleDecay",
		"CorrectiveScoreThreshold",
		"SevereScoreThreshold",
		"MaximumViolationScore",
		"CorrectionCooldown",
		"RepeatedWarningThreshold",
		"WarningWindow",
	}
	local SYSTEM_SAFETY_NUMBER_FIELDS = {
		"MaximumHorizontalSpeed",
		"MaximumUpwardSpeed",
		"MaximumDownwardSpeed",
		"MaximumAngularSpeedDegrees",
		"MaximumVerticalDisplacementAdditive",
	}

	local function cloneConfig(): any
		return {
			Enabled = CartMovementValidation.Enabled,
			Development = table.clone(CartMovementValidation.Development),
			SystemSafety = table.clone(CartMovementValidation.SystemSafety),
		}
	end

	local function expectInvalid(config: any)
		expect(CartMovementValidationConfigValidator.Validate(config).IsValid).to.equal(false)
	end

	describe("CartMovementValidationConfigValidator", function()
		it("accepts the complete Phase 1Q configuration", function()
			local result = CartMovementValidationConfigValidator.Validate(CartMovementValidation)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
		end)

		it("rejects missing configuration sections and non-boolean flags", function()
			expectInvalid(nil)
			expectInvalid({})
			expectInvalid({ Enabled = true, Development = {}, SystemSafety = false })

			local invalidEnabled = cloneConfig()

			invalidEnabled.Enabled = "true"
			expectInvalid(invalidEnabled)

			local invalidDiagnostics = cloneConfig()

			invalidDiagnostics.Development.DiagnosticsEnabled = 0
			expectInvalid(invalidDiagnostics)
		end)

		it("rejects every missing, NaN, infinite, or non-number numeric field", function()
			for _, sectionAndFields in
				{
					{ Section = "Development", Fields = DEVELOPMENT_NUMBER_FIELDS },
					{ Section = "SystemSafety", Fields = SYSTEM_SAFETY_NUMBER_FIELDS },
				}
			do
				for _, field in sectionAndFields.Fields do
					local missing = cloneConfig()
					local missingSection = missing[sectionAndFields.Section]

					missingSection[field] = nil
					expectInvalid(missing)

					for _, invalidValue in { "invalid", 0 / 0, math.huge, -math.huge } do
						local config = cloneConfig()
						local section = config[sectionAndFields.Section]

						section[field] = invalidValue
						expectInvalid(config)
					end
				end
			end
		end)

		it("rejects invalid intervals, multipliers, tolerances, and score ranges", function()
			for _, mutation in
				{
					{ Field = "SampleInterval", Value = 0 },
					{ Field = "ForwardSpeedMultiplier", Value = 0.99 },
					{ Field = "ReverseSpeedAdditive", Value = -1 },
					{ Field = "UpwardSpeedObservation", Value = 0 },
					{ Field = "OwnershipTransitionGrace", Value = -1 },
					{ Field = "CorrectionCooldown", Value = -1 },
					{ Field = "RepeatedWarningThreshold", Value = 1.5 },
					{ Field = "WarningWindow", Value = 0 },
				}
			do
				local config = cloneConfig()

				config.Development[mutation.Field] = mutation.Value
				expectInvalid(config)
			end
		end)

		it("requires monotonic observation, corrective, and severe envelopes", function()
			for _, fields in
				{
					{ "OverallSpeedMultiplier", "CorrectiveHorizontalSpeedMultiplier" },
					{ "CorrectiveHorizontalSpeedMultiplier", "SevereHorizontalSpeedMultiplier" },
					{ "OverallSpeedAdditive", "CorrectiveHorizontalSpeedAdditive" },
					{ "CorrectiveHorizontalSpeedAdditive", "SevereHorizontalSpeedAdditive" },
					{ "DisplacementMultiplier", "CorrectiveDisplacementMultiplier" },
					{ "CorrectiveDisplacementMultiplier", "SevereDisplacementMultiplier" },
					{ "DisplacementAdditive", "CorrectiveDisplacementAdditive" },
					{ "CorrectiveDisplacementAdditive", "SevereDisplacementAdditive" },
				}
			do
				local config = cloneConfig()

				config.Development[fields[1]] = config.Development[fields[2]] + 1
				expectInvalid(config)
			end
		end)

		it("requires bounded, ordered violation scoring", function()
			local reversedIncrements = cloneConfig()

			reversedIncrements.Development.ObservationScoreIncrement = 3
			reversedIncrements.Development.CorrectiveScoreIncrement = 2
			expectInvalid(reversedIncrements)

			local reversedThresholds = cloneConfig()

			reversedThresholds.Development.CorrectiveScoreThreshold = 9
			reversedThresholds.Development.SevereScoreThreshold = 8
			expectInvalid(reversedThresholds)

			local thresholdAboveMaximum = cloneConfig()

			thresholdAboveMaximum.Development.SevereScoreThreshold = 13
			expectInvalid(thresholdAboveMaximum)

			local fractionalScore = cloneConfig()

			fractionalScore.Development.ValidSampleDecay = 0.5
			expectInvalid(fractionalScore)
		end)

		it("keeps hard system ceilings above approved Phase 1D limits", function()
			local horizontalBelowMovementSafety = cloneConfig()

			horizontalBelowMovementSafety.SystemSafety.MaximumHorizontalSpeed = CartMovementSafety.MaximumTravelSpeed
				- 1
			expectInvalid(horizontalBelowMovementSafety)

			local angularBelowMovementSafety = cloneConfig()

			angularBelowMovementSafety.SystemSafety.MaximumAngularSpeedDegrees = CartMovementSafety.MaximumAngularSpeed
				- 1
			expectInvalid(angularBelowMovementSafety)

			local angularObservationAboveHardCeiling = cloneConfig()

			angularObservationAboveHardCeiling.SystemSafety.MaximumAngularSpeedDegrees = 1000
			expectInvalid(angularObservationAboveHardCeiling)
		end)

		it("keeps Development observations below their hard system ceilings", function()
			for _, relationship in
				{
					{ "UpwardSpeedObservation", "MaximumUpwardSpeed" },
					{ "DownwardSpeedObservation", "MaximumDownwardSpeed" },
					{
						"VerticalDisplacementAdditive",
						"MaximumVerticalDisplacementAdditive",
					},
				}
			do
				local config = cloneConfig()

				config.Development[relationship[1]] = config.SystemSafety[relationship[2]] + 1
				expectInvalid(config)
			end
		end)
	end)
end
