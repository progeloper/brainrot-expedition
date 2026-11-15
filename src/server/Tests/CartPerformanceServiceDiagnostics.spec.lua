--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)

	local CartPerformanceLoadService =
		require(script.Parent.Parent.Services.CartPerformanceLoadService)
	local CartAnalyticsService = require(script.Parent.Parent.Services.CartAnalyticsService)
	local CartAssemblyValidationService =
		require(script.Parent.Parent.Services.CartAssemblyValidationService)
	local CartLongitudinalStateService =
		require(script.Parent.Parent.Services.CartLongitudinalStateService)
	local CartMovementValidationService =
		require(script.Parent.Parent.Services.CartMovementValidationService)
	local CartOccupantService = require(script.Parent.Parent.Services.CartOccupantService)
	local CartResetRequestService = require(script.Parent.Parent.Services.CartResetRequestService)
	local CartResetService = require(script.Parent.Parent.Services.CartResetService)
	local CartStabilityService = require(script.Parent.Parent.Services.CartStabilityService)
	local CartTerrainService = require(script.Parent.Parent.Services.CartTerrainService)

	local function expectFinite(value: number)
		expect(type(value)).to.equal("number")
		expect(value == value).to.equal(true)
		expect(math.abs(value) < math.huge).to.equal(true)
	end

	describe("Phase 1T service diagnostics", function()
		it(
			"exposes low-overhead numeric ownership counts without starting extra schedulers",
			function()
				local assembly = CartAssemblyValidationService:GetDiagnostics()
				local occupants = CartOccupantService:GetDiagnostics()
				local terrain = CartTerrainService:GetDiagnostics()
				local stability = CartStabilityService:GetDiagnostics()
				local longitudinal = CartLongitudinalStateService:GetDiagnostics()
				local validator = CartMovementValidationService:GetDiagnostics()
				local analytics = CartAnalyticsService:GetDiagnostics()
				local resets = CartResetService:GetDiagnostics()
				local security = CartResetRequestService:GetDiagnostics()

				for _, value in
					{
						assembly.RecordCount,
						assembly.RecordConnectionCount,
						assembly.RetainedConnectionObjectCount,
						assembly.ObservedInstanceCount,
						assembly.RetainedObservedInstanceCount,
						occupants.RecordCount,
						occupants.CartConnectionCount,
						terrain.RecordCount,
						terrain.TotalSampleCount,
						stability.RecordCount,
						stability.ManagedTorqueCount,
						stability.RetainedConnectionObjectCount,
						longitudinal.RecordCount,
						validator.RecordCount,
						validator.ProcessedRecordCount,
						analytics.RecordCount,
						resets.CartRecordCount,
						security.SecurityRecordCount,
					}
				do
					expectFinite(value)
					expect(value >= 0).to.equal(true)
				end

				expect(terrain.SchedulerCount <= 1).to.equal(true)
				expect(stability.SchedulerCount <= 1).to.equal(true)
				expect(validator.SchedulerCount <= 1).to.equal(true)
			end
		)

		it("keeps the server-only load service idle and rejects uncontrolled requests", function()
			local harnessStarted = CartPerformanceLoadService:Start()

			expect(harnessStarted).to.equal(true)

			local invalidScenarioAccepted =
				CartPerformanceLoadService:BeginRun("PERF_SCENARIO_UNCONTROLLED", 1)
			local invalidCountAccepted =
				CartPerformanceLoadService:BeginRun("PERF_SCENARIO_STATIONARY_LOAD", 2)
			local diagnostics = CartPerformanceLoadService:GetDiagnostics()

			expect(invalidScenarioAccepted).to.equal(false)
			expect(invalidCountAccepted).to.equal(false)
			expect(diagnostics.Active).to.equal(false)
			expect(diagnostics.RuntimeActiveCount).to.equal(0)
			expect(diagnostics.MeasurementSchedulerCount).to.equal(0)
			expect(diagnostics.MotionSchedulerCount).to.equal(0)
		end)

		it("does not add a replicated performance command or gameplay remote", function()
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")

			if remotes == nil then
				expect(remotes).to.equal(nil)
				return
			end

			for _, child in remotes:GetChildren() do
				expect(string.find(string.lower(child.Name), "performance", 1, true)).to.equal(nil)
			end
		end)

		it(
			"exposes only server-side Development cleanup for harness reset-security state",
			function()
				local before = CartResetRequestService:GetDiagnostics()
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				assert(remotes ~= nil, "expected the production remotes folder in the fixture")
				local originalRemote = remotes:FindFirstChild(RemoteNames.CartResetRequest)
				local startedByFixture = not before.Started
				local reservedByFixture = false
				local fixtureUserId = -999999999
				local ok, failure = xpcall(function()
					if startedByFixture then
						CartResetRequestService:Start()
					end
					local reserved, reservationError =
						CartResetRequestService:ReserveDevelopmentRequestState(fixtureUserId)
					reservedByFixture = reserved
						and CartResetRequestService:GetDiagnostics().DevelopmentReservationCount
							== before.DevelopmentReservationCount + 1
					expect(reserved).to.equal(true)
					expect(reservationError).to.equal(nil)
					expect(reservedByFixture).to.equal(true)
					local cleared, clearError =
						CartResetRequestService:ClearDevelopmentRequestState(fixtureUserId)
					if cleared then
						reservedByFixture = false
					end
					expect(cleared).to.equal(true)
					expect(clearError).to.equal(nil)
				end, debug.traceback)

				-- Undo only this fixture's reservation and service start, even on failure.
				if reservedByFixture then
					CartResetRequestService:ClearDevelopmentRequestState(fixtureUserId)
				end
				if startedByFixture then
					local createdRemote = if originalRemote == nil
						then remotes:FindFirstChild(RemoteNames.CartResetRequest)
						else nil
					CartResetRequestService:Stop()
					if createdRemote ~= nil then
						createdRemote:Destroy()
					end
				end
				local after = CartResetRequestService:GetDiagnostics()
				expect(after.Started).to.equal(before.Started)
				expect(after.SecurityRecordCount).to.equal(before.SecurityRecordCount)
				expect(after.DevelopmentReservationCount).to.equal(
					before.DevelopmentReservationCount
				)
				expect(after.SharedConnectionCount).to.equal(before.SharedConnectionCount)
				expect(after.RemoteCount).to.equal(before.RemoteCount)
				expect(remotes:FindFirstChild(RemoteNames.CartResetRequest)).to.equal(
					originalRemote
				)
				assert(ok, failure)
			end
		)
	end)
end
