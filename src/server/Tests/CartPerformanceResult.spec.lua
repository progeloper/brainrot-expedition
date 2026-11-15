--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
	local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
	local CartPerformanceResult = require(ReplicatedStorage.Shared.Utility.CartPerformanceResult)
	local CartPerformanceSnapshot =
		require(ReplicatedStorage.Shared.Utility.CartPerformanceSnapshot)

	local function snapshot(recordedAt: number, scenarioId: string?, loadCount: number?): any
		return CartPerformanceSnapshot.Create({
			ScenarioId = scenarioId or ScenarioIds.StationaryLoad,
			LoadCount = loadCount or 12,
			Stage = CartPerformanceSnapshot.Stages.SteadyState,
			RecordedAt = recordedAt,
			Metrics = {
				CartRecords = 12,
			},
		})
	end

	local function validRequest(): any
		return {
			ScenarioId = ScenarioIds.StationaryLoad,
			LoadCount = 12,
			Status = "Passed",
			StartedAt = 10,
			CompletedAt = 20,
			Summary = {
				PeakCartRecords = 12,
			},
			Snapshots = {
				snapshot(12),
				snapshot(18),
			},
		}
	end

	describe("CartPerformanceResult", function()
		it("creates a frozen bounded result and derives duration and pass state", function()
			local request = validRequest()
			local result = CartPerformanceResult.Create(request)

			request.Summary.PeakCartRecords = 99

			expect(result.Passed).to.equal(true)
			expect(result.Duration).to.equal(10)
			expect(result.SnapshotCount).to.equal(2)
			expect(result.Summary.PeakCartRecords).to.equal(12)
			expect(table.isfrozen(result)).to.equal(true)
			expect(table.isfrozen(result.Snapshots)).to.equal(true)
			expect(table.isfrozen(result.Summary)).to.equal(true)

			local function containsInstance(value: any): boolean
				if typeof(value) == "Instance" then
					return true
				elseif type(value) ~= "table" then
					return false
				end

				for key, child in value do
					if containsInstance(key) or containsInstance(child) then
						return true
					end
				end

				return false
			end

			expect(containsInstance(result)).to.equal(false)
		end)

		it("represents failed and setup-blocked scenarios without claiming a pass", function()
			local failed = validRequest()

			failed.Status = "Failed"
			failed.Severity = "S2"
			failed.FailureCode = "PERF_RECORD_GROWTH"

			local failedResult = CartPerformanceResult.Create(failed)

			expect(failedResult.Passed).to.equal(false)
			expect(failedResult.Severity).to.equal("S2")

			local blocked = validRequest()

			blocked.Status = "Blocked"
			blocked.Snapshots = {}
			blocked.FailureCode = "PERF_SETUP_CART"

			local blockedResult = CartPerformanceResult.Create(blocked)

			expect(blockedResult.Passed).to.equal(false)
			expect(blockedResult.SnapshotCount).to.equal(0)
		end)

		it("rejects invalid identity, status, severity, and timing", function()
			for _, mutation in
				{
					{ Field = "ScenarioId", Value = "PERF_SCENARIO_UNKNOWN" },
					{ Field = "LoadCount", Value = 2 },
					{ Field = "Status", Value = "MostlyPassed" },
					{ Field = "Severity", Value = "S4" },
					{ Field = "StartedAt", Value = -1 },
					{ Field = "StartedAt", Value = 0 / 0 },
					{ Field = "CompletedAt", Value = 9 },
					{ Field = "CompletedAt", Value = math.huge },
				}
			do
				local invalid = validRequest()

				invalid[mutation.Field] = mutation.Value
				expect(function()
					CartPerformanceResult.Create(invalid)
				end).to.throw()
			end

			local noEvidence = validRequest()

			noEvidence.Snapshots = {}
			expect(function()
				CartPerformanceResult.Create(noEvidence)
			end).to.throw()
		end)

		it("rejects mismatched, out-of-window, and nonchronological snapshots", function()
			for _, snapshots in
				{
					{ snapshot(12, ScenarioIds.MovingLoad) },
					{ snapshot(12, nil, 8) },
					{ snapshot(9) },
					{ snapshot(21) },
					{ snapshot(18), snapshot(12) },
				}
			do
				local invalid = validRequest()

				invalid.Snapshots = snapshots
				expect(function()
					CartPerformanceResult.Create(invalid)
				end).to.throw()
			end
		end)

		it("rejects contradictory failure metadata on a passed result", function()
			local severity = validRequest()

			severity.Severity = "S2"
			expect(function()
				CartPerformanceResult.Create(severity)
			end).to.throw()

			local failureCode = validRequest()

			failureCode.FailureCode = "PERF_CONTRADICTORY_PASS"
			expect(function()
				CartPerformanceResult.Create(failureCode)
			end).to.throw()
		end)

		it(
			"rejects Instances, nested data, non-finite summaries, and oversized histories",
			function()
				local folder = Instance.new("Folder")

				for _, invalidMetric in { folder, { Nested = true }, 0 / 0, math.huge } do
					local invalid = validRequest()

					invalid.Summary.Invalid = invalidMetric
					expect(function()
						CartPerformanceResult.Create(invalid)
					end).to.throw()
				end

				folder:Destroy()

				local oversized = validRequest()

				oversized.Snapshots = {}
				for index = 1, CartPerformanceTest.Development.SnapshotCapacity + 1 do
					oversized.Snapshots[index] = snapshot(10)
				end

				expect(function()
					CartPerformanceResult.Create(oversized)
				end).to.throw()
			end
		)
	end)
end
