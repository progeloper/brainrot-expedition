--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxScenarioIds)
	local CartGreyboxValidationResult =
		require(ReplicatedStorage.Shared.Utility.CartGreyboxValidationResult)

	local function validRequest(): any
		return {
			ScenarioId = ScenarioIds.FlatAcceleration,
			Status = "Passed",
			Observed = {
				TopSpeed = 20,
				CorrectionApplied = false,
			},
			Expected = {
				Profile = "CRT_001",
			},
			RecordedAt = 12.5,
		}
	end

	describe("CartGreyboxValidationResult", function()
		it("creates a frozen Instance-free structured result", function()
			local result = CartGreyboxValidationResult.Create(validRequest())

			expect(result.Passed).to.equal(true)
			expect(result.Status).to.equal("Passed")
			expect(result.Observed.TopSpeed).to.equal(20)
			expect(result.Expected.Profile).to.equal("CRT_001")
			expect(table.isfrozen(result)).to.equal(true)
			expect(table.isfrozen(result.Observed)).to.equal(true)
			expect(table.isfrozen(result.Expected)).to.equal(true)
		end)

		it("represents blocked and failed outcomes without marking them passed", function()
			for _, status in { "Failed", "Blocked", "NotApplicable", "ManualReviewRequired" } do
				local request = validRequest()

				request.Status = status
				request.Severity = if status == "Failed" then "S2" else nil

				local result = CartGreyboxValidationResult.Create(request)

				expect(result.Passed).to.equal(false)
				expect(result.Status).to.equal(status)
			end
		end)

		it("rejects unknown scenarios and unsupported status or severity", function()
			local unknown = validRequest()

			unknown.ScenarioId = "GBOX_SCENARIO_UNKNOWN"
			expect(function()
				CartGreyboxValidationResult.Create(unknown)
			end).to.throw()

			local invalidStatus = validRequest()

			invalidStatus.Status = "MostlyPassed"
			expect(function()
				CartGreyboxValidationResult.Create(invalidStatus)
			end).to.throw()

			local invalidSeverity = validRequest()

			invalidSeverity.Severity = "S4"
			expect(function()
				CartGreyboxValidationResult.Create(invalidSeverity)
			end).to.throw()
		end)

		it("rejects Instances, nested fields, and non-finite measurements", function()
			for _, invalidValue in
				{
					Instance.new("Folder"),
					{ Nested = true },
					0 / 0,
					math.huge,
				}
			do
				local request = validRequest()

				request.Observed.Invalid = invalidValue
				expect(function()
					CartGreyboxValidationResult.Create(request)
				end).to.throw()
			end
		end)
	end)
end
