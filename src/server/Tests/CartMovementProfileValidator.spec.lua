--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartMovementProfileValidator =
		require(ReplicatedStorage.Shared.Validation.CartMovementProfileValidator)

	type Candidate = { [string]: any }

	local baseFields = {
		"HuntingSpeed",
		"MaxTravelSpeed",
		"ForwardAcceleration",
		"HighSpeedAccelerationMultiplier",
		"AccelerationCurveExponent",
		"CoastDeceleration",
		"HighSpeedCoastDecelerationMultiplier",
		"Braking",
		"HighSpeedBrakingMultiplier",
		"RecoveryBackupSpeed",
		"RecoveryBackupAcceleration",
		"RecoveryBackupDeceleration",
		"RecoveryInputDelay",
		"NearZeroSpeedThreshold",
		"LongitudinalInputDeadzone",
		"LongitudinalTransitionRetryInterval",
		"LongitudinalTransitionMaximumRetryInterval",
		"TurnRate",
		"StationarySteeringThreshold",
		"LowSpeedSteeringMultiplier",
		"HighSpeedSteeringMultiplier",
		"SteeringInterpolationExponent",
		"LateralGrip",
		"HighSpeedLateralGripMultiplier",
		"DriveForceLimit",
		"UprightResponsiveness",
		"UprightTorque",
		"MaxAngularSpeed",
		"GroundFriction",
		"GroundFrictionWeight",
	}

	local effectiveFields = { "CartId" }

	for _, field in baseFields do
		table.insert(effectiveFields, field)
	end

	local function createValidBase(): Candidate
		return {
			HuntingSpeed = 20,
			MaxTravelSpeed = 36,
			ForwardAcceleration = 16,
			HighSpeedAccelerationMultiplier = 0.25,
			AccelerationCurveExponent = 1.35,
			CoastDeceleration = 20,
			HighSpeedCoastDecelerationMultiplier = 0.75,
			Braking = 48,
			HighSpeedBrakingMultiplier = 1.15,
			RecoveryBackupSpeed = 3.5,
			RecoveryBackupAcceleration = 6,
			RecoveryBackupDeceleration = 12,
			RecoveryInputDelay = 0.45,
			NearZeroSpeedThreshold = 0.6,
			LongitudinalInputDeadzone = 0.05,
			LongitudinalTransitionRetryInterval = 0.1,
			LongitudinalTransitionMaximumRetryInterval = 1,
			TurnRate = 105,
			StationarySteeringThreshold = 0.5,
			LowSpeedSteeringMultiplier = 1.15,
			HighSpeedSteeringMultiplier = 0.32,
			SteeringInterpolationExponent = 1.35,
			LateralGrip = 10,
			HighSpeedLateralGripMultiplier = 1.25,
			DriveForceLimit = 180,
			UprightResponsiveness = 18,
			UprightTorque = 42000,
			MaxAngularSpeed = 130,
			GroundFriction = 0.08,
			GroundFrictionWeight = 100,
		}
	end

	local function createValidEffective(): Candidate
		local profile = createValidBase()

		profile.CartId = "CRT_TEST"
		profile.ControlReferenceSpeed = profile.MaxTravelSpeed

		return profile
	end

	local function hasError(result: any, text: string): boolean
		for _, errorMessage in result.Errors do
			if string.find(errorMessage, text, 1, true) ~= nil then
				return true
			end
		end

		return false
	end

	local function expectInvalidBase(candidate: Candidate, field: string?)
		local result = CartMovementProfileValidator.ValidateBase("CRT_TEST", candidate)

		expect(result.IsValid).to.equal(false)

		if field ~= nil then
			expect(hasError(result, string.format("Field=%s", field))).to.equal(true)
		end
	end

	describe("CartMovementProfileValidator", function()
		it("accepts valid base and effective hunting-cart profiles", function()
			expect(CartMovementProfileValidator.ValidateBase("CRT_TEST", createValidBase()).IsValid).to.equal(
				true
			)
			expect(
				CartMovementProfileValidator.ValidateEffective("CRT_TEST", createValidEffective()).IsValid
			).to.equal(true)
		end)

		it("rejects a non-table definition with a structured error", function()
			local result = CartMovementProfileValidator.ValidateBase("CRT_TEST", "invalid")

			expect(result.IsValid).to.equal(false)
			expect(hasError(result, "Field=<profile>")).to.equal(true)
			expect(hasError(result, "Value=invalid (string)")).to.equal(true)
		end)

		it("rejects every missing required base movement field", function()
			for _, field in baseFields do
				local candidate = createValidBase()

				candidate[field] = nil
				expectInvalidBase(candidate, field)
			end
		end)

		it("rejects every missing required effective profile field", function()
			for _, field in effectiveFields do
				local profile = createValidEffective()

				profile[field] = nil

				local result = CartMovementProfileValidator.ValidateEffective("CRT_TEST", profile)

				expect(result.IsValid).to.equal(false)
				expect(hasError(result, string.format("Field=%s", field))).to.equal(true)
			end
		end)

		it("rejects nonnumeric and non-finite values for every numeric base field", function()
			local invalidValues = {
				"fast",
				true,
				0 / 0,
				math.huge,
				-math.huge,
			}

			for _, field in baseFields do
				for _, invalidValue in invalidValues do
					local candidate = createValidBase()

					candidate[field] = invalidValue
					expectInvalidBase(candidate, field)
				end
			end
		end)

		it("rejects nonnumeric and non-finite values throughout the effective profile", function()
			for index = 2, #effectiveFields do
				local field = effectiveFields[index]

				for _, invalidValue in { "fast", true, 0 / 0, math.huge, -math.huge } do
					local profile = createValidEffective()

					profile[field] = invalidValue

					local result =
						CartMovementProfileValidator.ValidateEffective("CRT_TEST", profile)

					expect(result.IsValid).to.equal(false)
					expect(hasError(result, string.format("Field=%s", field))).to.equal(true)
				end
			end
		end)

		it("rejects values below required minimums", function()
			local cases = {
				{ Field = "HuntingSpeed", Value = 0 },
				{ Field = "MaxTravelSpeed", Value = 0 },
				{ Field = "ForwardAcceleration", Value = 0 },
				{ Field = "HighSpeedAccelerationMultiplier", Value = 0 },
				{ Field = "AccelerationCurveExponent", Value = 0 },
				{ Field = "CoastDeceleration", Value = 0 },
				{ Field = "HighSpeedCoastDecelerationMultiplier", Value = 0 },
				{ Field = "Braking", Value = 0 },
				{ Field = "HighSpeedBrakingMultiplier", Value = 0 },
				{ Field = "RecoveryBackupSpeed", Value = 0 },
				{ Field = "RecoveryBackupAcceleration", Value = 0 },
				{ Field = "RecoveryBackupDeceleration", Value = 0 },
				{ Field = "RecoveryInputDelay", Value = -0.01 },
				{ Field = "NearZeroSpeedThreshold", Value = -0.01 },
				{ Field = "LongitudinalInputDeadzone", Value = -0.01 },
				{ Field = "LongitudinalTransitionRetryInterval", Value = 0 },
				{ Field = "LongitudinalTransitionMaximumRetryInterval", Value = 0 },
				{ Field = "TurnRate", Value = 0 },
				{ Field = "StationarySteeringThreshold", Value = -0.01 },
				{ Field = "LowSpeedSteeringMultiplier", Value = 0 },
				{ Field = "HighSpeedSteeringMultiplier", Value = 0 },
				{ Field = "SteeringInterpolationExponent", Value = 0 },
				{ Field = "LateralGrip", Value = 0 },
				{ Field = "HighSpeedLateralGripMultiplier", Value = 0 },
				{ Field = "DriveForceLimit", Value = 0 },
				{ Field = "UprightResponsiveness", Value = 0 },
				{ Field = "UprightTorque", Value = 0 },
				{ Field = "MaxAngularSpeed", Value = 0 },
				{ Field = "GroundFriction", Value = -0.01 },
				{ Field = "GroundFrictionWeight", Value = -1 },
			}

			for _, case in cases do
				local candidate = createValidBase()

				candidate[case.Field] = case.Value
				expectInvalidBase(candidate, case.Field)
			end
		end)

		it("rejects finite values beyond centralized safety caps", function()
			for _, field in baseFields do
				local candidate = createValidBase()

				candidate[field] = 1000000000000
				expectInvalidBase(candidate, field)
			end
		end)

		it("rejects invalid hunting and recovery speed relationships", function()
			local huntingAboveTravel = createValidBase()
			huntingAboveTravel.HuntingSpeed = huntingAboveTravel.MaxTravelSpeed + 1
			expectInvalidBase(huntingAboveTravel, "HuntingSpeed")

			local traversalBackup = createValidBase()
			traversalBackup.RecoveryBackupSpeed = traversalBackup.HuntingSpeed
			expectInvalidBase(traversalBackup, "RecoveryBackupSpeed")

			local unreachableRecoveryThreshold = createValidBase()
			unreachableRecoveryThreshold.NearZeroSpeedThreshold =
				unreachableRecoveryThreshold.RecoveryBackupSpeed
			expectInvalidBase(unreachableRecoveryThreshold, "NearZeroSpeedThreshold")
		end)

		it("rejects multipliers that contradict speed-dependent control intent", function()
			local fasterHighSpeedAcceleration = createValidBase()
			fasterHighSpeedAcceleration.HighSpeedAccelerationMultiplier = 1.01
			expectInvalidBase(fasterHighSpeedAcceleration, "HighSpeedAccelerationMultiplier")

			local strongerHighSpeedCoast = createValidBase()
			strongerHighSpeedCoast.HighSpeedCoastDecelerationMultiplier = 1.01
			expectInvalidBase(strongerHighSpeedCoast, "HighSpeedCoastDecelerationMultiplier")

			local weakerHighSpeedBrake = createValidBase()
			weakerHighSpeedBrake.HighSpeedBrakingMultiplier = 0.99
			expectInvalidBase(weakerHighSpeedBrake, "HighSpeedBrakingMultiplier")

			local weakerHighSpeedStability = createValidBase()
			weakerHighSpeedStability.HighSpeedLateralGripMultiplier = 0.99
			expectInvalidBase(weakerHighSpeedStability, "HighSpeedLateralGripMultiplier")
		end)

		it("rejects invalid braking and recovery response relationships", function()
			local weakBrake = createValidBase()
			weakBrake.Braking = weakBrake.ForwardAcceleration - 1
			expectInvalidBase(weakBrake, "Braking")

			local weakerCoastBrake = createValidBase()
			weakerCoastBrake.Braking = weakerCoastBrake.CoastDeceleration - 1
			expectInvalidBase(weakerCoastBrake, "Braking")

			local slowRecoveryStop = createValidBase()
			slowRecoveryStop.RecoveryBackupDeceleration = slowRecoveryStop.RecoveryBackupAcceleration
				- 1
			expectInvalidBase(slowRecoveryStop, "RecoveryBackupDeceleration")
		end)

		it("rejects a maximum transition retry below the initial retry interval", function()
			local invalidRetryWindow = createValidBase()

			invalidRetryWindow.LongitudinalTransitionMaximumRetryInterval = invalidRetryWindow.LongitudinalTransitionRetryInterval
				- 0.01
			expectInvalidBase(invalidRetryWindow, "LongitudinalTransitionMaximumRetryInterval")
		end)

		it("rejects invalid steering and angular-control relationships", function()
			local increasedHighSpeedSteering = createValidBase()
			increasedHighSpeedSteering.HighSpeedSteeringMultiplier = increasedHighSpeedSteering.LowSpeedSteeringMultiplier
				+ 0.01
			expectInvalidBase(increasedHighSpeedSteering, "HighSpeedSteeringMultiplier")

			local ineffectiveAngularCap = createValidBase()
			ineffectiveAngularCap.MaxAngularSpeed = ineffectiveAngularCap.TurnRate - 1
			expectInvalidBase(ineffectiveAngularCap, "MaxAngularSpeed")

			local clippedSteeringRate = createValidBase()
			clippedSteeringRate.MaxAngularSpeed = clippedSteeringRate.TurnRate
			expectInvalidBase(clippedSteeringRate, "MaxAngularSpeed")

			local unreachableSteeringThreshold = createValidBase()
			unreachableSteeringThreshold.StationarySteeringThreshold = unreachableSteeringThreshold.RecoveryBackupSpeed
				+ 0.01
			expectInvalidBase(unreachableSteeringThreshold, "StationarySteeringThreshold")
		end)

		it("rejects a mismatched effective CartId", function()
			local profile = createValidEffective()

			profile.CartId = "CRT_OTHER"

			local result = CartMovementProfileValidator.ValidateEffective("CRT_TEST", profile)

			expect(result.IsValid).to.equal(false)
			expect(hasError(result, "Field=CartId")).to.equal(true)
		end)

		it("returns descriptive component, CartId, field, value, and constraint details", function()
			local candidate = createValidBase()

			candidate.ForwardAcceleration = "fast"

			local result = CartMovementProfileValidator.ValidateBase("CRT_TEST", candidate)
			local combined = table.concat(result.Errors, "\n")

			expect(string.find(combined, "[CartMovementProfileValidator.Base]", 1, true) ~= nil).to.equal(
				true
			)
			expect(string.find(combined, "CartId=CRT_TEST", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Field=ForwardAcceleration", 1, true) ~= nil).to.equal(
				true
			)
			expect(string.find(combined, "Value=fast (string)", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Expected=", 1, true) ~= nil).to.equal(true)
		end)
	end)
end
