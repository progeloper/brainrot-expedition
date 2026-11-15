--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
	local CartAnalyticsEventValidator =
		require(ReplicatedStorage.Shared.Validation.CartAnalyticsEventValidator)
	local CartResetRequestProtocol =
		require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)

	type Payload = { [any]: any }

	local function commonPayload(): Payload
		return {
			EventVersion = 1,
			BuildId = "test-build",
			Environment = "Development",
			ServerTimestamp = 100,
			PlayerUserId = 42,
		}
	end

	local function withCommon(fields: Payload): Payload
		local payload = commonPayload()

		for field, value in fields do
			payload[field] = value
		end

		return payload
	end

	local VALID_PAYLOADS: { [string]: Payload } = {
		[AnalyticsEvents.CartSpawned] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			SpawnId = "CSP_001",
		}),
		[AnalyticsEvents.CartDriverEntered] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			TimeSinceCartSpawn = 0.25,
			Platform = "Unknown",
		}),
		[AnalyticsEvents.CartMovementStarted] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			TimeSinceDriverEntered = 0.4,
			Platform = "KeyboardMouse",
			Direction = "Forward",
		}),
		[AnalyticsEvents.CartDriverExited] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			DriverSessionDuration = 12,
			MeaningfulMovementBegan = true,
			ExitReason = "Unknown",
			Platform = "Gamepad",
		}),
		[AnalyticsEvents.CartResetRequested] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			Platform = "Touch",
		}),
		[AnalyticsEvents.CartResetApproved] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			TimeSinceDriverEntered = 3,
			Platform = "Unknown",
		}),
		[AnalyticsEvents.CartResetRejected] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			Reason = CartResetRequestProtocol.ReasonCodes.CooldownActive,
			Platform = "Unknown",
		}),
		[AnalyticsEvents.CartResetCompleted] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			ResetDuration = 0.2,
			Platform = "Unknown",
			DriverRetained = true,
		}),
		[AnalyticsEvents.CartDespawned] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			SpawnId = "CSP_001",
			CartLifetime = 60,
			HadDriver = true,
			HadMeaningfulMovement = true,
			DespawnReason = "Unknown",
			ActiveDriverPresent = false,
			CompletedResetCount = 1,
			MovementCorrectionCount = 0,
		}),
		[AnalyticsEvents.CartMovementCorrected] = withCommon({
			RuntimeCartId = "cart-1",
			CartId = "CRT_001",
			DriverSessionId = "cart-1-driver-1",
			Category = "VelocityCleared",
			Severity = "Corrective",
			Reason = "ExtremeHorizontalSpeed",
			CorrectionCount = 1,
		}),
	}

	local EVENT_SPECIFIC_REQUIRED_FIELDS: { [string]: { string } } = {
		[AnalyticsEvents.CartSpawned] = { "RuntimeCartId", "CartId", "SpawnId" },
		[AnalyticsEvents.CartDriverEntered] = {
			"RuntimeCartId",
			"CartId",
			"DriverSessionId",
			"TimeSinceCartSpawn",
			"Platform",
		},
		[AnalyticsEvents.CartMovementStarted] = {
			"RuntimeCartId",
			"CartId",
			"DriverSessionId",
			"TimeSinceDriverEntered",
			"Platform",
			"Direction",
		},
		[AnalyticsEvents.CartDriverExited] = {
			"RuntimeCartId",
			"CartId",
			"DriverSessionId",
			"DriverSessionDuration",
			"MeaningfulMovementBegan",
			"ExitReason",
			"Platform",
		},
		[AnalyticsEvents.CartResetRequested] = { "Platform" },
		[AnalyticsEvents.CartResetApproved] = {
			"RuntimeCartId",
			"CartId",
			"DriverSessionId",
			"TimeSinceDriverEntered",
			"Platform",
		},
		[AnalyticsEvents.CartResetRejected] = { "Reason", "Platform" },
		[AnalyticsEvents.CartResetCompleted] = {
			"RuntimeCartId",
			"CartId",
			"DriverSessionId",
			"ResetDuration",
			"Platform",
			"DriverRetained",
		},
		[AnalyticsEvents.CartDespawned] = {
			"RuntimeCartId",
			"CartId",
			"SpawnId",
			"CartLifetime",
			"HadDriver",
			"HadMeaningfulMovement",
			"DespawnReason",
			"ActiveDriverPresent",
			"CompletedResetCount",
			"MovementCorrectionCount",
		},
		[AnalyticsEvents.CartMovementCorrected] = {
			"RuntimeCartId",
			"CartId",
			"Category",
			"Severity",
			"Reason",
			"CorrectionCount",
		},
	}

	local COMMON_REQUIRED_FIELDS = {
		"EventVersion",
		"BuildId",
		"Environment",
		"ServerTimestamp",
		"PlayerUserId",
	}

	local function expectValid(eventName: string, payload: Payload)
		local result = CartAnalyticsEventValidator.Validate(eventName, payload)

		expect(result.IsValid).to.equal(true)
		expect(#result.Errors).to.equal(0)
	end

	local function expectInvalid(eventName: any, payload: any)
		expect(CartAnalyticsEventValidator.Validate(eventName, payload).IsValid).to.equal(false)
	end

	describe("CartAnalyticsEventValidator", function()
		it("accepts every required version-one event payload", function()
			for eventName, payload in VALID_PAYLOADS do
				expectValid(eventName, payload)
				expect(CartAnalyticsEventValidator.IsEventName(eventName)).to.equal(true)
				expect(CartAnalyticsEventValidator.GetEventVersion(eventName)).to.equal(1)
			end
		end)

		it("rejects unknown event names and non-table payloads", function()
			expectInvalid("cart_future_event", commonPayload())
			expectInvalid(AnalyticsEvents.CartSpawned, nil)

			local folder = Instance.new("Folder")

			expectInvalid(AnalyticsEvents.CartSpawned, folder)
			folder:Destroy()

			expect(CartAnalyticsEventValidator.IsEventName("cart_future_event")).to.equal(false)
			expect(CartAnalyticsEventValidator.GetEventVersion("cart_future_event")).to.equal(nil)
		end)

		it("rejects every missing common and event-specific required field", function()
			for eventName, payload in VALID_PAYLOADS do
				for _, field in COMMON_REQUIRED_FIELDS do
					local missing = table.clone(payload)

					missing[field] = nil
					expectInvalid(eventName, missing)
				end

				for _, field in EVENT_SPECIFIC_REQUIRED_FIELDS[eventName] do
					local missing = table.clone(payload)

					missing[field] = nil
					expectInvalid(eventName, missing)
				end
			end
		end)

		it("accepts only the documented optional unresolved-context fields", function()
			for _, eventName in
				{
					AnalyticsEvents.CartResetRequested,
					AnalyticsEvents.CartResetRejected,
				}
			do
				local payload = table.clone(VALID_PAYLOADS[eventName])

				payload.RuntimeCartId = nil
				payload.CartId = nil
				payload.DriverSessionId = nil
				expectValid(eventName, payload)
			end

			local correction = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartMovementCorrected])

			correction.DriverSessionId = nil
			expectValid(AnalyticsEvents.CartMovementCorrected, correction)
		end)

		it("rejects unknown fields and disallowed Roblox/runtime values", function()
			local unknownField = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartSpawned])

			unknownField.FullCFrame = CFrame.new()
			expectInvalid(AnalyticsEvents.CartSpawned, unknownField)

			local invalidValues = {
				{},
				function() end,
				coroutine.create(function() end),
				Vector3.zero,
				CFrame.new(),
			}

			for _, invalidValue in invalidValues do
				local payload = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartSpawned])

				payload.BuildId = invalidValue
				expectInvalid(AnalyticsEvents.CartSpawned, payload)
			end

			local folder = Instance.new("Folder")
			local instancePayload = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartSpawned])

			instancePayload.BuildId = folder
			expectInvalid(AnalyticsEvents.CartSpawned, instancePayload)
			folder:Destroy()
		end)

		it("requires finite timestamps, identifiers, and version one", function()
			for _, mutation in
				{
					{ Field = "EventVersion", Value = 2 },
					{ Field = "EventVersion", Value = 1.5 },
					{ Field = "EventVersion", Value = 0 / 0 },
					{ Field = "ServerTimestamp", Value = -1 },
					{ Field = "ServerTimestamp", Value = math.huge },
					{ Field = "PlayerUserId", Value = 1.5 },
					{ Field = "PlayerUserId", Value = -math.huge },
					{ Field = "BuildId", Value = "" },
				}
			do
				local payload = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartSpawned])

				payload[mutation.Field] = mutation.Value
				expectInvalid(AnalyticsEvents.CartSpawned, payload)
			end
		end)

		it("rejects negative and non-finite durations", function()
			for _, mutation in
				{
					{
						Event = AnalyticsEvents.CartDriverEntered,
						Field = "TimeSinceCartSpawn",
						Value = -1,
					},
					{
						Event = AnalyticsEvents.CartMovementStarted,
						Field = "TimeSinceDriverEntered",
						Value = 0 / 0,
					},
					{
						Event = AnalyticsEvents.CartDriverExited,
						Field = "DriverSessionDuration",
						Value = math.huge,
					},
					{
						Event = AnalyticsEvents.CartResetCompleted,
						Field = "ResetDuration",
						Value = -math.huge,
					},
					{
						Event = AnalyticsEvents.CartDespawned,
						Field = "CartLifetime",
						Value = -0.1,
					},
				}
			do
				local payload = table.clone(VALID_PAYLOADS[mutation.Event])

				payload[mutation.Field] = mutation.Value
				expectInvalid(mutation.Event, payload)
			end
		end)

		it("validates platform, direction, lifecycle, reset, and correction enums", function()
			for _, mutation in
				{
					{
						Event = AnalyticsEvents.CartDriverEntered,
						Field = "Platform",
						Value = "Console",
					},
					{
						Event = AnalyticsEvents.CartMovementStarted,
						Field = "Direction",
						Value = "Sideways",
					},
					{
						Event = AnalyticsEvents.CartDriverExited,
						Field = "ExitReason",
						Value = "PlayerChoseToLeave",
					},
					{
						Event = AnalyticsEvents.CartResetRejected,
						Field = "Reason",
						Value = CartResetRequestProtocol.ReasonCodes.Approved,
					},
					{
						Event = AnalyticsEvents.CartDespawned,
						Field = "DespawnReason",
						Value = "DeletedByAnalytics",
					},
					{
						Event = AnalyticsEvents.CartMovementCorrected,
						Field = "Category",
						Value = "Cheating",
					},
					{
						Event = AnalyticsEvents.CartMovementCorrected,
						Field = "Severity",
						Value = "Observation",
					},
				}
			do
				local payload = table.clone(VALID_PAYLOADS[mutation.Event])

				payload[mutation.Field] = mutation.Value
				expectInvalid(mutation.Event, payload)
			end
		end)

		it("requires booleans and non-negative integer counters", function()
			local invalidBoolean = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartDriverExited])

			invalidBoolean.MeaningfulMovementBegan = 1
			expectInvalid(AnalyticsEvents.CartDriverExited, invalidBoolean)

			for _, invalidCount in { -1, 0.5, math.huge } do
				local invalidCounter = table.clone(VALID_PAYLOADS[AnalyticsEvents.CartDespawned])

				invalidCounter.CompletedResetCount = invalidCount
				expectInvalid(AnalyticsEvents.CartDespawned, invalidCounter)
			end
		end)
	end)
end
