--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
	local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
	local CartReset = require(ReplicatedStorage.Shared.Config.CartReset)
	local CartResetRequestProtocol =
		require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)
	local CartAnalyticsEventValidator =
		require(ReplicatedStorage.Shared.Validation.CartAnalyticsEventValidator)
	local CartAnalyticsRuntime = require(script.Parent.Parent.Utility.CartAnalyticsRuntime)

	local function createRuntime(): CartAnalyticsRuntime.Runtime
		return CartAnalyticsRuntime.new(CartReset.RequestAttemptInterval)
	end

	local function register(runtime: CartAnalyticsRuntime.Runtime, key: any, now: number?): string
		local events = runtime:RegisterCart({
			Key = key,
			OwnerUserId = 101,
			CartId = "CRT_001",
			SpawnId = "CSP_001",
			SpawnedAt = now or 10,
		}, now or 10)

		expect(#events).to.equal(1)
		expect(events[1].Name).to.equal(AnalyticsEvents.CartSpawned)
		expect(events[1].Fields.CartId).to.equal("CRT_001")

		return events[1].RuntimeCartId :: string
	end

	describe("CartAnalyticsRuntime", function()
		it("constructs schema-valid payload fields for the complete normal catalogue", function()
			local runtime = createRuntime()
			local requests: { CartAnalyticsRuntime.EventRequest } = {}

			local function append(nextRequests: { CartAnalyticsRuntime.EventRequest })
				for _, request in nextRequests do
					table.insert(requests, request)
				end
			end

			append(runtime:RegisterCart({
				Key = "cart-a",
				OwnerUserId = 101,
				CartId = "CRT_001",
				SpawnId = "CSP_001",
				SpawnedAt = 10,
			}, 10))
			append(runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, "Unknown"))
			append(runtime:MovementStarted("cart-a", 202, "Forward", 14))
			append(runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = true,
				Reason = CartResetRequestProtocol.ReasonCodes.Approved,
				RequestedAt = 15,
				CompletedAt = 16,
				ResetStartedAt = 15.1,
				ResetCompletedAt = 15.9,
			}))
			append(runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = false,
				Reason = CartResetRequestProtocol.ReasonCodes.CooldownActive,
				RequestedAt = 16,
				CompletedAt = 16,
			}))
			append(runtime:RecordCorrection({
				CartKey = "cart-a",
				Revision = 1,
				Category = "NetworkOwnershipRestored",
				Severity = "Corrective",
				Reason = "NetworkOwnerMismatch",
				ServerTimestamp = 17,
			}))
			append(runtime:DriverChanged("cart-a", 202, nil, "SeatExited", 18, nil))
			append(runtime:DespawnCart("cart-a", "ExplicitDespawn", "Unknown", 20))

			expect(#requests).to.equal(11)
			local seenNames: { [string]: boolean } = {}

			for _, request in requests do
				local payload = table.clone(request.Fields)

				payload.EventVersion = CartAnalytics.EventVersion
				payload.BuildId = "test-build"
				payload.Environment = "Development"
				payload.ServerTimestamp = request.ServerTimestamp
				payload.PlayerUserId = request.PlayerUserId

				if request.RuntimeCartId ~= nil then
					payload.RuntimeCartId = request.RuntimeCartId
				end

				local validation = CartAnalyticsEventValidator.Validate(request.Name, payload)

				expect(validation.IsValid).to.equal(true)
				seenNames[request.Name] = true
			end

			local uniqueNameCount = 0

			for _ in seenNames do
				uniqueNameCount += 1
			end

			expect(uniqueNameCount).to.equal(10)
		end)

		it("registers one successful cart lifecycle and deduplicates the callback", function()
			local runtime = createRuntime()
			local runtimeCartId = register(runtime, "cart-a")
			local duplicate = runtime:RegisterCart({
				Key = "cart-a",
				OwnerUserId = 101,
				CartId = "CRT_001",
				SpawnId = "CSP_001",
				SpawnedAt = 10,
			}, 11)

			expect(runtimeCartId).to.equal("cart-1")
			expect(#duplicate).to.equal(0)
			expect(runtime:GetRecordCount()).to.equal(1)
			expect(#runtime:GetRegisteredKeys()).to.equal(1)

			runtime:DiscardCart("cart-a")
			expect(runtime:GetRecordCount()).to.equal(0)
		end)

		it("assigns a new runtime cart identity after replacement", function()
			local runtime = createRuntime()
			local firstId = register(runtime, "cart-a")

			runtime:DespawnCart("cart-a", "Replacement", "CartReplaced", 20)
			local secondId = register(runtime, "cart-b", 21)

			expect(firstId).never.to.equal(secondId)
			expect(secondId).to.equal("cart-2")
		end)

		it("opens one driver session and ignores duplicate authority callbacks", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")

			local entered = runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, "Unknown")
			local duplicate = runtime:DriverChanged("cart-a", 202, 202, "Unknown", 13, "Gamepad")

			expect(#entered).to.equal(1)
			expect(entered[1].Name).to.equal(AnalyticsEvents.CartDriverEntered)
			expect(entered[1].Fields.DriverSessionId).to.equal("cart-1-driver-1")
			expect(entered[1].Fields.Platform).to.equal("Unknown")
			expect(#duplicate).to.equal(0)
		end)

		it("orders direct driver replacement as exit then enter", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, "KeyboardMouse")

			local events = runtime:DriverChanged(
				"cart-a",
				202,
				303,
				"DriverSeat occupant changed",
				18,
				"Touch"
			)

			expect(#events).to.equal(2)
			expect(events[1].Name).to.equal(AnalyticsEvents.CartDriverExited)
			expect(events[1].PlayerUserId).to.equal(202)
			expect(events[1].Fields.ExitReason).to.equal("DriverReplaced")
			expect(events[2].Name).to.equal(AnalyticsEvents.CartDriverEntered)
			expect(events[2].PlayerUserId).to.equal(303)
			expect(events[2].Fields.DriverSessionId).to.equal("cart-1-driver-2")
		end)

		it("emits meaningful movement once per driver session", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, "Gamepad")

			local first = runtime:MovementStarted("cart-a", 202, "Forward", 14)
			local repeated = runtime:MovementStarted("cart-a", 202, "Reverse", 15)

			expect(#first).to.equal(1)
			expect(first[1].Name).to.equal(AnalyticsEvents.CartMovementStarted)
			expect(first[1].Fields.Direction).to.equal("Forward")
			expect(first[1].Fields.TimeSinceDriverEntered).to.equal(2)
			expect(#repeated).to.equal(0)

			runtime:DriverChanged("cart-a", 202, nil, "SeatExited", 16, nil)
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 17, "Gamepad")
			local newSession = runtime:MovementStarted("cart-a", 202, "Reverse", 19)

			expect(#newSession).to.equal(1)
			expect(newSession[1].Fields.DriverSessionId).to.equal("cart-1-driver-2")
		end)

		it("rejects movement without a matching active driver", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")

			expect(#runtime:MovementStarted("cart-a", 202, "Forward", 12)).to.equal(0)
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 13, nil)
			expect(#runtime:MovementStarted("cart-a", 303, "Forward", 14)).to.equal(0)
		end)

		it("emits requested-approved-completed in order with server durations", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, "KeyboardMouse")

			local events = runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = true,
				Reason = CartResetRequestProtocol.ReasonCodes.Approved,
				RequestedAt = 20,
				CompletedAt = 22,
				ResetStartedAt = 20.5,
				ResetCompletedAt = 21.75,
			})

			expect(#events).to.equal(3)
			expect(events[1].Name).to.equal(AnalyticsEvents.CartResetRequested)
			expect(events[2].Name).to.equal(AnalyticsEvents.CartResetApproved)
			expect(events[3].Name).to.equal(AnalyticsEvents.CartResetCompleted)
			expect(events[3].Fields.ResetDuration).to.equal(1.25)
			expect(events[3].Fields.DriverRetained).to.equal(true)
			expect(runtime:GetSnapshot("cart-a").CompletedResetCount).to.equal(1)
		end)

		it("emits requested-rejected and bounds hostile rate-limit telemetry", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			local first = runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = false,
				Reason = CartResetRequestProtocol.ReasonCodes.RateLimited,
				RequestedAt = 20,
				CompletedAt = 20,
			})
			local suppressed = runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = false,
				Reason = CartResetRequestProtocol.ReasonCodes.RateLimited,
				RequestedAt = 20.1,
				CompletedAt = 20.1,
			})

			expect(#first).to.equal(2)
			expect(first[1].Name).to.equal(AnalyticsEvents.CartResetRequested)
			expect(first[2].Name).to.equal(AnalyticsEvents.CartResetRejected)
			expect(first[2].Fields.Reason).to.equal("RateLimited")
			expect(#suppressed).to.equal(0)

			runtime:RemovePlayer(202)
			local rejoined = runtime:RecordResetOutcome({
				PlayerUserId = 202,
				CartKey = "cart-a",
				Approved = false,
				Reason = CartResetRequestProtocol.ReasonCodes.RateLimited,
				RequestedAt = 20.2,
				CompletedAt = 20.2,
			})

			expect(#rejoined).to.equal(2)
		end)

		it("emits only actual unique corrections and tracks the lifecycle count", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, nil)
			local corrected = runtime:RecordCorrection({
				CartKey = "cart-a",
				Revision = 1,
				Category = "VelocityCleared",
				Severity = "Corrective",
				Reason = "CorrectiveHorizontalSpeed",
				ServerTimestamp = 30,
			})
			local duplicate = runtime:RecordCorrection({
				CartKey = "cart-a",
				Revision = 1,
				Category = "VelocityCleared",
				Severity = "Corrective",
				Reason = "CorrectiveHorizontalSpeed",
				ServerTimestamp = 31,
			})

			expect(#corrected).to.equal(1)
			expect(corrected[1].Name).to.equal(AnalyticsEvents.CartMovementCorrected)
			expect(corrected[1].PlayerUserId).to.equal(202)
			expect(corrected[1].Fields.CorrectionCount).to.equal(1)
			expect(#duplicate).to.equal(0)
		end)

		it("closes an active driver before despawn and removes all state", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			runtime:DriverChanged("cart-a", nil, 202, "Unknown", 12, nil)
			runtime:MovementStarted("cart-a", 202, "Forward", 14)

			local events = runtime:DespawnCart("cart-a", "ModelDestroyed", "CartDestroyed", 20)
			local duplicate = runtime:DespawnCart("cart-a", "ModelDestroyed", "CartDestroyed", 21)

			expect(#events).to.equal(2)
			expect(events[1].Name).to.equal(AnalyticsEvents.CartDriverExited)
			expect(events[2].Name).to.equal(AnalyticsEvents.CartDespawned)
			expect(events[2].Fields.HadMeaningfulMovement).to.equal(true)
			expect(events[2].Fields.ActiveDriverPresent).to.equal(true)
			expect(#duplicate).to.equal(0)
			expect(runtime:GetRecordCount()).to.equal(0)
		end)

		it("stops with bounded cleanup events and releases every record", function()
			local runtime = createRuntime()
			register(runtime, "cart-a")
			register(runtime, "cart-b", 11)

			local events = runtime:Stop(20)

			expect(#events).to.equal(2)
			expect(events[1].Name).to.equal(AnalyticsEvents.CartDespawned)
			expect(events[2].Name).to.equal(AnalyticsEvents.CartDespawned)
			expect(runtime:GetRecordCount()).to.equal(0)
		end)
	end)
end
