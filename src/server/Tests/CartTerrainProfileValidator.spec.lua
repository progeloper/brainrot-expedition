--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartTerrainProfileValidator =
		require(ReplicatedStorage.Shared.Validation.CartTerrainProfileValidator)

	type Candidate = { [string]: any }

	local numericFields = {
		"ProbeOriginHeight",
		"GroundDetectionDistance",
		"MaximumSupportGap",
		"MaximumSupportPenetration",
		"LateralProbeFraction",
		"ForwardProbeFraction",
		"FullGroundedHitCount",
		"GroundedReacquireDelay",
		"AirborneDelay",
		"NormalResponseSpeed",
		"MaximumNormalChangeDegreesPerSecond",
		"AirborneWorldUpResponseSpeed",
		"NormalOutlierAngleDegrees",
		"SlopeEffectStartDegrees",
		"FullSlopeEffectDegrees",
		"MaximumClimbAngleDegrees",
		"MaximumGroundAngleDegrees",
		"MaximumUphillAccelerationReduction",
		"MaximumDownhillAcceleration",
		"MaximumDownhillCoastReduction",
		"PartialSupportStabilityMultiplier",
		"AirborneStabilityMultiplier",
		"DrivenSampleRate",
		"ServerMovingSampleRate",
		"ServerSettledSampleRate",
		"ServerSettledSpeedThreshold",
	}

	local function createValidBase(): Candidate
		return {
			Enabled = true,
			ProbeOriginHeight = 2,
			GroundDetectionDistance = 6,
			MaximumSupportGap = 1.25,
			MaximumSupportPenetration = 0.35,
			LateralProbeFraction = 0.42,
			ForwardProbeFraction = 0.3,
			FullGroundedHitCount = 2,
			GroundedReacquireDelay = 0.08,
			AirborneDelay = 0.18,
			NormalResponseSpeed = 10,
			MaximumNormalChangeDegreesPerSecond = 120,
			AirborneWorldUpResponseSpeed = 2.5,
			NormalOutlierAngleDegrees = 35,
			SlopeEffectStartDegrees = 3,
			FullSlopeEffectDegrees = 35,
			MaximumClimbAngleDegrees = 45,
			MaximumGroundAngleDegrees = 65,
			MaximumUphillAccelerationReduction = 0.25,
			MaximumDownhillAcceleration = 3,
			MaximumDownhillCoastReduction = 0.2,
			PartialSupportStabilityMultiplier = 0.7,
			AirborneStabilityMultiplier = 0.35,
			DrivenSampleRate = 15,
			ServerMovingSampleRate = 10,
			ServerSettledSampleRate = 4,
			ServerSettledSpeedThreshold = 1,
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
		local result = CartTerrainProfileValidator.ValidateBase("CRT_TEST", candidate)

		expect(result.IsValid).to.equal(false)

		if field ~= nil then
			expect(hasError(result, string.format("Field=%s", field))).to.equal(true)
		end
	end

	describe("CartTerrainProfileValidator", function()
		it("accepts the complete base and effective Development profiles", function()
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", createValidBase()).IsValid).to.equal(
				true
			)
			expect(
				CartTerrainProfileValidator.ValidateEffective("CRT_TEST", createValidEffective()).IsValid
			).to.equal(true)
		end)

		it("accepts an explicitly disabled but otherwise complete profile", function()
			local candidate = createValidBase()

			candidate.Enabled = false

			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", candidate).IsValid).to.equal(
				true
			)
		end)

		it("rejects a non-table profile and non-boolean Enabled values", function()
			local nonTable = CartTerrainProfileValidator.ValidateBase("CRT_TEST", "terrain")

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
				for _, invalidValue in { "terrain", true, 0 / 0, math.huge, -math.huge } do
					local candidate = createValidBase()

					candidate[field] = invalidValue
					expectInvalidBase(candidate, field)
				end
			end
		end)

		it("rejects values beyond centralized safety ranges rather than clamping", function()
			for _, field in numericFields do
				local below = createValidBase()
				local above = createValidBase()

				below[field] = -1000000000000
				above[field] = 1000000000000

				expectInvalidBase(below, field)
				expectInvalidBase(above, field)
			end
		end)

		it("requires an integer support-hit count from one through three", function()
			for _, invalidValue in { 0, 1.5, 4 } do
				local candidate = createValidBase()

				candidate.FullGroundedHitCount = invalidValue
				expectInvalidBase(candidate, "FullGroundedHitCount")
			end
		end)

		it("requires ordered slope thresholds", function()
			local startConflict = createValidBase()

			startConflict.SlopeEffectStartDegrees = startConflict.FullSlopeEffectDegrees
			expectInvalidBase(startConflict, "SlopeEffectStartDegrees")

			local equalFullAndClimb = createValidBase()

			equalFullAndClimb.FullSlopeEffectDegrees = equalFullAndClimb.MaximumClimbAngleDegrees
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", equalFullAndClimb).IsValid).to.equal(
				true
			)

			local climbConflict = createValidBase()

			climbConflict.MaximumClimbAngleDegrees = climbConflict.MaximumGroundAngleDegrees
			expectInvalidBase(climbConflict, "MaximumClimbAngleDegrees")
		end)

		it("requires the support gap to fit inside the sensing distance", function()
			local conflict = createValidBase()

			conflict.GroundDetectionDistance = 4
			conflict.MaximumSupportGap = 4.1
			expectInvalidBase(conflict, "MaximumSupportGap")

			conflict.MaximumSupportGap = conflict.GroundDetectionDistance
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", conflict).IsValid).to.equal(
				true
			)
		end)

		it("keeps penetration tolerance within the support gap", function()
			local conflict = createValidBase()

			conflict.MaximumSupportPenetration = conflict.MaximumSupportGap + 0.1
			expectInvalidBase(conflict, "MaximumSupportPenetration")

			conflict.MaximumSupportPenetration = conflict.MaximumSupportGap
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", conflict).IsValid).to.equal(
				true
			)
		end)

		it("orders settled, moving, and driven sample rates", function()
			local settledConflict = createValidBase()

			settledConflict.ServerSettledSampleRate = settledConflict.ServerMovingSampleRate + 1
			expectInvalidBase(settledConflict, "ServerSettledSampleRate")

			local movingConflict = createValidBase()

			movingConflict.ServerMovingSampleRate = movingConflict.DrivenSampleRate + 1
			expectInvalidBase(movingConflict, "ServerMovingSampleRate")

			local equalRates = createValidBase()

			equalRates.ServerSettledSampleRate = equalRates.ServerMovingSampleRate
			equalRates.DrivenSampleRate = equalRates.ServerMovingSampleRate
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", equalRates).IsValid).to.equal(
				true
			)
		end)

		it("keeps airborne assistance at or below partial-support assistance", function()
			local conflict = createValidBase()

			conflict.AirborneStabilityMultiplier = conflict.PartialSupportStabilityMultiplier + 0.1
			expectInvalidBase(conflict, "AirborneStabilityMultiplier")

			conflict.AirborneStabilityMultiplier = conflict.PartialSupportStabilityMultiplier
			expect(CartTerrainProfileValidator.ValidateBase("CRT_TEST", conflict).IsValid).to.equal(
				true
			)
		end)

		it("rejects a mismatched effective CartId", function()
			local candidate = createValidEffective()

			candidate.CartId = "CRT_OTHER"

			local result = CartTerrainProfileValidator.ValidateEffective("CRT_TEST", candidate)

			expect(result.IsValid).to.equal(false)
			expect(hasError(result, "Field=CartId")).to.equal(true)
		end)

		it("returns component, CartId, field, value, and expected constraint details", function()
			local candidate = createValidBase()

			candidate.NormalResponseSpeed = "smooth"

			local result = CartTerrainProfileValidator.ValidateBase("CRT_TEST", candidate)
			local combined = table.concat(result.Errors, "\n")

			expect(string.find(combined, "[CartTerrainProfileValidator.Base]", 1, true) ~= nil).to.equal(
				true
			)
			expect(string.find(combined, "CartId=CRT_TEST", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Field=NormalResponseSpeed", 1, true) ~= nil).to.equal(
				true
			)
			expect(string.find(combined, "Value=smooth (string)", 1, true) ~= nil).to.equal(true)
			expect(string.find(combined, "Expected=", 1, true) ~= nil).to.equal(true)
		end)
	end)
end
