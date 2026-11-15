--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local LoadCounts = require(ReplicatedStorage.Shared.Constants.CartPerformanceLoadCounts)
	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
	local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
	local CartPerformanceConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartPerformanceConfigValidator)

	local function cloneConfig(): any
		local scenarios = {}
		local byScenarioId = {}

		for index, definition in CartPerformanceTest.Scenarios do
			local clonedDefinition = table.clone(definition)

			scenarios[index] = clonedDefinition
			byScenarioId[clonedDefinition.Id] = clonedDefinition
		end

		return {
			Enabled = CartPerformanceTest.Enabled,
			LoadCounts = table.clone(CartPerformanceTest.LoadCounts),
			Scenarios = scenarios,
			ByScenarioId = byScenarioId,
			Development = table.clone(CartPerformanceTest.Development),
		}
	end

	local function expectInvalid(config: any)
		expect(CartPerformanceConfigValidator.Validate(config).IsValid).to.equal(false)
	end

	describe("CartPerformance configuration", function()
		it("accepts the complete Development performance-test contract", function()
			local result = CartPerformanceConfigValidator.Validate(CartPerformanceTest)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
			expect(#CartPerformanceTest.LoadCounts).to.equal(4)
			expect(CartPerformanceTest.LoadCounts[1]).to.equal(1)
			expect(CartPerformanceTest.LoadCounts[4]).to.equal(12)
			expect(#CartPerformanceTest.Scenarios).to.equal(8)
			expect(CartPerformanceTest.Development.EnduranceCycleCount).to.equal(10)
			expect(CartPerformanceTest.Development.ActionObservationDuration).to.equal(2)
			expect(CartPerformanceTest.Development.MinimumSteadyStateCoverageRatio).to.equal(0.95)
		end)

		it("centralises and freezes all required counts and scenarios", function()
			expect(LoadCounts.Target).to.equal(12)
			expect(#ScenarioIds.All).to.equal(8)
			expect(table.isfrozen(LoadCounts)).to.equal(true)
			expect(table.isfrozen(LoadCounts.Ordered)).to.equal(true)
			expect(table.isfrozen(ScenarioIds)).to.equal(true)
			expect(table.isfrozen(ScenarioIds.All)).to.equal(true)
			expect(table.isfrozen(CartPerformanceTest)).to.equal(true)
			expect(table.isfrozen(CartPerformanceTest.Development)).to.equal(true)

			for _, definition in CartPerformanceTest.Scenarios do
				expect(table.isfrozen(definition)).to.equal(true)
			end
		end)

		it("rejects missing, unknown, and non-boolean root configuration", function()
			expectInvalid(nil)
			expectInvalid({})

			local missing = cloneConfig()

			missing.Scenarios = nil
			expectInvalid(missing)

			local unknown = cloneConfig()

			unknown.ProductionCartLimit = 12
			expectInvalid(unknown)

			local invalidEnabled = cloneConfig()

			invalidEnabled.Enabled = "true"
			expectInvalid(invalidEnabled)
		end)

		it("requires the exact ordered load-count progression", function()
			for _, mutation in
				{
					{ Index = 1, Value = 0 },
					{ Index = 2, Value = 8 },
					{ Index = 3, Value = 4 },
					{ Index = 4, Value = 11 },
					{ Index = 4, Value = 12.5 },
					{ Index = 4, Value = 0 / 0 },
					{ Index = 4, Value = math.huge },
				}
			do
				local config = cloneConfig()

				config.LoadCounts[mutation.Index] = mutation.Value
				expectInvalid(config)
			end

			local extra = cloneConfig()

			extra.LoadCounts[5] = 16
			expectInvalid(extra)
		end)

		it("requires each central scenario exactly once with a strict shape", function()
			local duplicate = cloneConfig()

			duplicate.Scenarios[2].Id = duplicate.Scenarios[1].Id
			duplicate.ByScenarioId = {}
			for _, definition in duplicate.Scenarios do
				duplicate.ByScenarioId[definition.Id] = definition
			end
			expectInvalid(duplicate)

			local unknown = cloneConfig()

			unknown.Scenarios[1].Id = "PERF_SCENARIO_UNAPPROVED"
			unknown.ByScenarioId = {
				PERF_SCENARIO_UNAPPROVED = unknown.Scenarios[1],
			}
			expectInvalid(unknown)

			local emptyLabel = cloneConfig()

			emptyLabel.Scenarios[1].Label = ""
			expectInvalid(emptyLabel)

			local unknownField = cloneConfig()

			unknownField.Scenarios[1].FrameBudget = 16.67
			expectInvalid(unknownField)
		end)

		it("rejects missing, non-finite, and invalid Development values", function()
			for _, field in
				{
					"WarmupDuration",
					"SteadyStateDuration",
					"SnapshotInterval",
					"CleanupObservationDuration",
					"ActionObservationDuration",
					"EnduranceCycleCount",
					"MinimumSteadyStateCoverageRatio",
					"SnapshotCapacity",
					"MaximumMetricsPerSnapshot",
					"MaximumSummaryMetrics",
				}
			do
				local missing = cloneConfig()

				missing.Development[field] = nil
				expectInvalid(missing)

				for _, invalidValue in { "invalid", 0 / 0, math.huge, -math.huge } do
					local config = cloneConfig()

					config.Development[field] = invalidValue
					expectInvalid(config)
				end
			end

			for _, mutation in
				{
					{ Field = "WarmupDuration", Value = -1 },
					{ Field = "SteadyStateDuration", Value = 0 },
					{ Field = "SnapshotInterval", Value = 0 },
					{ Field = "CleanupObservationDuration", Value = -1 },
					{ Field = "ActionObservationDuration", Value = 0 },
					{ Field = "EnduranceCycleCount", Value = 1.5 },
					{ Field = "MinimumSteadyStateCoverageRatio", Value = 0 },
					{ Field = "MinimumSteadyStateCoverageRatio", Value = 1.01 },
					{ Field = "SnapshotCapacity", Value = 0 },
					{ Field = "MaximumMetricsPerSnapshot", Value = 0 },
				}
			do
				local config = cloneConfig()

				config.Development[mutation.Field] = mutation.Value
				expectInvalid(config)
			end
		end)

		it("requires the bounded snapshot store to retain one measurement window", function()
			local intervalTooLong = cloneConfig()

			intervalTooLong.Development.SnapshotInterval = 301
			expectInvalid(intervalTooLong)

			local insufficientCapacity = cloneConfig()

			insufficientCapacity.Development.SnapshotCapacity = 299
			expectInvalid(insufficientCapacity)
		end)
	end)
end
