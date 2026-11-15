--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
	local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
	local CartPerformanceSnapshot =
		require(ReplicatedStorage.Shared.Utility.CartPerformanceSnapshot)

	local function request(recordedAt: number, metricValue: number?): any
		return {
			ScenarioId = ScenarioIds.MovingLoad,
			LoadCount = 12,
			Stage = CartPerformanceSnapshot.Stages.SteadyState,
			RecordedAt = recordedAt,
			Metrics = {
				CartRecords = metricValue or 12,
			},
		}
	end

	describe("CartPerformanceSnapshot", function()
		it("creates a frozen finite numeric-only snapshot", function()
			local source = request(10)
			local snapshot = CartPerformanceSnapshot.Create(source)

			source.Metrics.CartRecords = 99

			expect(snapshot.ScenarioId).to.equal(ScenarioIds.MovingLoad)
			expect(snapshot.LoadCount).to.equal(12)
			expect(snapshot.Metrics.CartRecords).to.equal(12)
			expect(table.isfrozen(snapshot)).to.equal(true)
			expect(table.isfrozen(snapshot.Metrics)).to.equal(true)
		end)

		it("rejects unsupported identity, stage, time, and load values", function()
			for _, mutation in
				{
					{ Field = "ScenarioId", Value = "PERF_SCENARIO_UNKNOWN" },
					{ Field = "LoadCount", Value = 2 },
					{ Field = "LoadCount", Value = 12.5 },
					{ Field = "Stage", Value = "Rendering" },
					{ Field = "RecordedAt", Value = -1 },
					{ Field = "RecordedAt", Value = 0 / 0 },
					{ Field = "RecordedAt", Value = math.huge },
				}
			do
				local invalid = request(10)

				invalid[mutation.Field] = mutation.Value
				expect(function()
					CartPerformanceSnapshot.Create(invalid)
				end).to.throw()
			end
		end)

		it("rejects Instances, nested data, non-finite metrics, and oversized payloads", function()
			local folder = Instance.new("Folder")

			for _, invalidMetric in { folder, { Nested = true }, 0 / 0, math.huge, -math.huge } do
				local invalid = request(10)

				invalid.Metrics.Invalid = invalidMetric
				expect(function()
					CartPerformanceSnapshot.Create(invalid)
				end).to.throw()
			end

			folder:Destroy()

			local tooManyMetrics = request(10)

			for index = 1, CartPerformanceTest.Development.MaximumMetricsPerSnapshot do
				tooManyMetrics.Metrics[string.format("Metric%d", index)] = index
			end

			expect(function()
				CartPerformanceSnapshot.Create(tooManyMetrics)
			end).to.throw()
		end)

		it("retains only the newest bounded snapshots in chronological order", function()
			local buffer = CartPerformanceSnapshot.CreateBuffer(3)

			for recordedAt = 1, 5 do
				CartPerformanceSnapshot.Add(buffer, request(recordedAt, recordedAt))
			end

			local snapshots = CartPerformanceSnapshot.Read(buffer)

			expect(CartPerformanceSnapshot.GetCount(buffer)).to.equal(3)
			expect(#snapshots).to.equal(3)
			expect(snapshots[1].RecordedAt).to.equal(3)
			expect(snapshots[2].RecordedAt).to.equal(4)
			expect(snapshots[3].RecordedAt).to.equal(5)
			expect(table.isfrozen(snapshots)).to.equal(true)
		end)

		it("clears all bounded state without retaining snapshot references", function()
			local buffer = CartPerformanceSnapshot.CreateBuffer(2)

			CartPerformanceSnapshot.Add(buffer, request(1))
			CartPerformanceSnapshot.Add(buffer, request(2))
			CartPerformanceSnapshot.Clear(buffer)

			expect(CartPerformanceSnapshot.GetCount(buffer)).to.equal(0)
			expect(#CartPerformanceSnapshot.Read(buffer)).to.equal(0)
			expect(next(buffer.Values)).to.equal(nil)
		end)
	end)
end
