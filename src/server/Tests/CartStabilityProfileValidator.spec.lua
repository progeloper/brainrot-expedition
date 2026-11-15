--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartStabilityProfileValidator =
		require(ReplicatedStorage.Shared.Validation.CartStabilityProfileValidator)

	type Candidate = { [string]: any }

	local numericFields = {
		"OrientationErrorDeadZoneDegrees",
		"FreeRollAngleDegrees",
		"FreePitchAngleDegrees",
		"ModerateRollAngleDegrees",
		"ModeratePitchAngleDegrees",
		"StrongRollAngleDegrees",
		"StrongPitchAngleDegrees",
		"UprightStrength",
		"RollCorrectionStrength",
		"PitchCorrectionStrength",
		"RollDamping",
		"PitchDamping",
		"MaxCorrectiveTorque",
		"MaxCorrectiveAngularResponseDegreesPerSecond",
		"ResponseSpeed",
		"StationaryAssistanceMultiplier",
		"DrivingAssistanceMultiplier",
		"SevereTiltRecoveryMultiplier",
		"ExtremeYawDamping",
		"ExtremeYawThresholdDegreesPerSecond",
	}

	local function createValidBase(): Candidate
		return {
			Enabled = true,
			OrientationErrorDeadZoneDegrees = 1,
			FreeRollAngleDegrees = 6,
			FreePitchAngleDegrees = 4,
			ModerateRollAngleDegrees = 18,
			ModeratePitchAngleDegrees = 14,
			StrongRollAngleDegrees = 55,
			StrongPitchAngleDegrees = 45,
			UprightStrength = 1,
			RollCorrectionStrength = 1,
			PitchCorrectionStrength = 0.75,
			RollDamping = 0.42,
			PitchDamping = 0.5,
			MaxCorrectiveTorque = 42000,
			MaxCorrectiveAngularResponseDegreesPerSecond = 120,
			ResponseSpeed = 12,
			StationaryAssistanceMultiplier = 0.85,
			DrivingAssistanceMultiplier = 1,
			SevereTiltRecoveryMultiplier = 1.35,
			ExtremeYawDamping = 0,
			ExtremeYawThresholdDegreesPerSecond = 240,
		}
	end

	local function createValidEffective(): Candidate
		local candidate = createValidBase()

		candidate.CartId = "CRT_TEST"

		return candidate
	end

	local function hasError(result: any, expectedText: string): boolean
		for _, errorMessage in result.Errors do
			if string.find(errorMessage, expectedText, 1, true) ~= nil then
				return true
			end
		end

		return false
	end

	local function expectInvalidBase(candidate: Candidate, field: string?)
		local result = CartStabilityProfileValidator.ValidateBase("CRT_TEST", candidate)

		expect(result.IsValid).to.equal(false)

		if field ~= nil then
			expect(hasError(result, string.format("Field=%s", field))).to.equal(true)
		end
	end

	describe("CartStabilityProfileValidator", function()
		it("accepts the complete base and effective Development profiles", function()
			expect(
				CartStabilityProfileValidator.ValidateBase("CRT_TEST", createValidBase()).IsValid
			).to.equal(true)
			expect(
				CartStabilityProfileValidator.ValidateEffective("CRT_TEST", createValidEffective()).IsValid
			).to.equal(true)
		end)

		it("accepts an explicitly disabled but otherwise complete profile", function()
			local candidate = createValidBase()

			candidate.Enabled = false

			expect(CartStabilityProfileValidator.ValidateBase("CRT_TEST", candidate).IsValid).to.equal(
				true
			)
		end)

		it("rejects a non-table profile and a non-boolean Enabled value", function()
			local nonTable = CartStabilityProfileValidator.ValidateBase("CRT_TEST", "unstable")

			expect(nonTable.IsValid).to.equal(false)
			expect(hasError(nonTable, "Field=<profile>")).to.equal(true)

			local missing = createValidBase()

			missing.Enabled = nil
			expectInvalidBase(missing, "Enabled")

			for _, invalidValue in { 0, "true" } do
				local candidate = createValidBase()

				candidate.Enabled = invalidValue
				expectInvalidBase(candidate, "Enabled")
			end
		end)

		it("rejects every missing required numeric field", function()
			for _, field in numericFields do
				local candidate = createValidBase()

				candidate[field] = nil
				expectInvalidBase(candidate, field)
			end
		end)

		it("rejects nonnumeric and non-finite values for every numeric field", function()
			for _, field in numericFields do
				for _, invalidValue in { "strong", true, 0 / 0, math.huge, -math.huge } do
					local candidate = createValidBase()

					candidate[field] = invalidValue
					expectInvalidBase(candidate, field)
				end
			end
		end)

		it("rejects values outside centralized safety ranges rather than clamping", function()
			for _, field in numericFields do
				local below = createValidBase()
				local above = createValidBase()

				below[field] = -1000000000000
				above[field] = 1000000000000

				expectInvalidBase(below, field)
				expectInvalidBase(above, field)
			end
		end)

		it(
			"requires positive roll and pitch damping while allowing disabled yaw damping",
			function()
				for _, field in { "RollDamping", "PitchDamping" } do
					local candidate = createValidBase()

					candidate[field] = 0
					expectInvalidBase(candidate, field)
				end

				local yawDisabled = createValidBase()

				yawDisabled.ExtremeYawDamping = 0
				expect(CartStabilityProfileValidator.ValidateBase("CRT_TEST", yawDisabled).IsValid).to.equal(
					true
				)
			end
		)

		it("requires the error dead zone to fit inside both free-angle ranges", function()
			local rollConflict = createValidBase()

			rollConflict.OrientationErrorDeadZoneDegrees = rollConflict.FreeRollAngleDegrees + 0.1
			expectInvalidBase(rollConflict, "OrientationErrorDeadZoneDegrees")

			local pitchConflict = createValidBase()

			pitchConflict.OrientationErrorDeadZoneDegrees = pitchConflict.FreePitchAngleDegrees
				+ 0.1
			expectInvalidBase(pitchConflict, "OrientationErrorDeadZoneDegrees")
		end)

		it("requires strictly ordered roll thresholds", function()
			local freeConflict = createValidBase()

			freeConflict.FreeRollAngleDegrees = freeConflict.ModerateRollAngleDegrees
			expectInvalidBase(freeConflict, "FreeRollAngleDegrees")

			local moderateConflict = createValidBase()

			moderateConflict.ModerateRollAngleDegrees = moderateConflict.StrongRollAngleDegrees
			expectInvalidBase(moderateConflict, "ModerateRollAngleDegrees")
		end)

		it("requires strictly ordered pitch thresholds", function()
			local freeConflict = createValidBase()

			freeConflict.FreePitchAngleDegrees = freeConflict.ModeratePitchAngleDegrees
			expectInvalidBase(freeConflict, "FreePitchAngleDegrees")

			local moderateConflict = createValidBase()

			moderateConflict.ModeratePitchAngleDegrees = moderateConflict.StrongPitchAngleDegrees
			expectInvalidBase(moderateConflict, "ModeratePitchAngleDegrees")
		end)

		it("keeps optional extreme-yaw damping outside normal correction response", function()
			local candidate = createValidBase()

			candidate.ExtremeYawDamping = 1
			candidate.ExtremeYawThresholdDegreesPerSecond =
				candidate.MaxCorrectiveAngularResponseDegreesPerSecond

			expectInvalidBase(candidate, "ExtremeYawThresholdDegreesPerSecond")

			candidate.ExtremeYawDamping = 0

			expect(CartStabilityProfileValidator.ValidateBase("CRT_TEST", candidate).IsValid).to.equal(
				true
			)
		end)

		it("rejects a mismatched effective CartId", function()
			local candidate = createValidEffective()

			candidate.CartId = "CRT_OTHER"

			local result = CartStabilityProfileValidator.ValidateEffective("CRT_TEST", candidate)

			expect(result.IsValid).to.equal(false)
			expect(hasError(result, "Field=CartId")).to.equal(true)
		end)

		it("returns component, CartId, field, value, and expected constraint details", function()
			local candidate = createValidBase()

			candidate.RollDamping = "heavy"

			local result = CartStabilityProfileValidator.ValidateBase("CRT_TEST", candidate)
			local combined = table.concat(result.Errors, "\n")

			expect(string.find(combined, "[CartStabilityProfileValidator.Base]", 1, true) ~= nil).to.equal(
				true
			)
			expect(string.find(combined, "CartId=CRT_TEST", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Field=RollDamping", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Value=heavy (string)", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Expected=", 1, true) ~= nil).to.equal(true)
		end)
	end)
end
