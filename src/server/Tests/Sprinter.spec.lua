--!nocheck
return function()
	local Config = require(game.ReplicatedStorage.Shared.Config.BrainrotBehaviours).Sprinter
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Sprinter = require(script.Parent.Parent.Systems.Behaviours.Sprinter)

	local function close(actual, expected, tolerance)
		expect(math.abs(actual - expected) <= (tolerance or 0.0001)).to.equal(true)
	end

	local function threat(userId, distance, character)
		return {
			UserId = userId,
			Position = Vector3.new(distance, 0, 0),
			Character = character or { Generation = userId },
		}
	end

	local function makeContext(overrides)
		overrides = overrides or {}
		return {
			LifecycleEligible = if overrides.LifecycleEligible == nil
				then true
				else overrides.LifecycleEligible,
			Position = overrides.Position or Vector3.zero,
			Forward = overrides.Forward or -Vector3.zAxis,
			ResolvedSpeed = overrides.ResolvedSpeed or 10,
			Candidates = overrides.Candidates or {},
			Sensing = if overrides.Sensing == nil then true else overrides.Sensing,
			CanSeeCandidate = overrides.CanSeeCandidate or function()
				return true
			end,
			ResolveEscapeGoal = overrides.ResolveEscapeGoal
				or function(position, _, preferred, distance, minimumDistance)
					if distance < minimumDistance then
						return nil
					end
					return position + preferred * distance
				end,
		}
	end

	local function startCycle(baseSpeed, character)
		local state = Sprinter.CreateState(0)
		local context = makeContext({
			ResolvedSpeed = baseSpeed or 10,
			Candidates = { threat(1, 10, character) },
		})
		local result = Sprinter.Step(state, context, 0, Config)
		expect(result.BurstStarted).to.equal(true)
		return state, context
	end

	describe("Phase 6D-2 Sprinter", function()
		it("keeps all initial tuning in one shared profile", function()
			local expected = {
				AwarenessRadius = 30,
				DisengageRadius = 36,
				DisengageGraceSeconds = 0.75,
				SenseIntervalSeconds = 0.10,
				BurstDurationSeconds = 1.20,
				AccelerationSeconds = 0.25,
				BurstSpeedMultiplier = 1.80,
				RecoveryDurationSeconds = 2.00,
				RecoveryDecelerationSeconds = 0.20,
				RecoverySpeedMultiplier = 0.45,
				RecoveryMaxSpeedStudsPerSecond = 8,
				CooldownDurationSeconds = 3.00,
				ReturnToNormalSeconds = 0.20,
				NormalEscapeReplanSeconds = 0.75,
				MinimumBurstClearanceStuds = 8,
				BlockedRetrySeconds = 0.75,
			}
			for key, value in expected do
				expect(Config[key]).to.equal(value)
			end
		end)

		it("samples the exact configured speed curve", function()
			local state = startCycle(10)
			local samples = {
				{ 0.000, "Burst", 10 },
				{ 0.125, "Burst", 14 },
				{ 0.250, "Burst", 18 },
				{ 1.000, "Burst", 18 },
				{ 1.200, "Recovery", 18 },
				{ 1.300, "Recovery", 11.25 },
				{ 1.400, "Recovery", 4.5 },
				{ 3.000, "Recovery", 4.5 },
				{ 3.200, "Cooldown", 4.5 },
				{ 3.300, "Cooldown", 7.25 },
				{ 3.400, "Cooldown", 10 },
				{ 6.199, "Cooldown", 10 },
				{ 6.200, "Ready", 10 },
			}
			for _, row in samples do
				local phase, speed = Sprinter.SampleMotion(state, row[1], Config)
				expect(phase).to.equal(row[2])
				close(speed, row[3])
			end
		end)

		it("caps high-baseline recovery and integrates phase boundaries", function()
			local state = startCycle(40)
			local phase, speed = Sprinter.SampleMotion(state, 1.4, Config)
			expect(phase).to.equal("Recovery")
			close(speed, 8)
			local average = Sprinter.AverageSpeed(state, 1.15, 1.45, Config)
			close(average, 40, 0.0002)
		end)

		it("requires an inclusive visible 30-stud threat and a safe initial route", function()
			local state = Sprinter.CreateState(0)
			local result =
				Sprinter.Step(state, makeContext({ Candidates = { threat(1, 30.01) } }), 0, Config)
			expect(result.Kind).to.equal("Roam")
			expect(state.Phase).to.equal("Ready")

			result =
				Sprinter.Step(state, makeContext({ Candidates = { threat(1, 30) } }), 0.1, Config)
			expect(result.BurstStarted).to.equal(true)
			expect(state.Phase).to.equal("Burst")

			state = Sprinter.CreateState(0)
			result = Sprinter.Step(
				state,
				makeContext({
					Candidates = { threat(1, 10) },
					ResolveEscapeGoal = function()
						return nil
					end,
				}),
				0,
				Config
			)
			expect(result.Kind).to.equal("Hold")
			expect(state.Phase).to.equal("Ready")
			expect(state.nextBlockedRetryAt).to.equal(0.75)
		end)

		it("retains a stable threat and uses hysteresis with one grace timer", function()
			local a, b = {}, {}
			local state, context = startCycle(10, a)
			context.Candidates = { threat(1, 34, a), threat(2, 2, b) }
			Sprinter.Step(state, context, 0.1, Config)
			expect(state.lockedThreatUserId).to.equal(1)

			context.Candidates = { threat(1, 36.01, a), threat(2, 2, b) }
			Sprinter.Step(state, context, 0.2, Config)
			Sprinter.Step(state, context, 0.949, Config)
			expect(state.lockedThreatUserId).to.equal(1)
			local result = Sprinter.Step(state, context, 0.95, Config)
			expect(result.ReleaseReason).to.equal("OutOfRange")
			expect(state.lockedThreatUserId).to.equal(nil)
			-- A committed burst never switches to B in the same update.
			expect(result.AcquiredUserId).to.equal(nil)
			expect(result.Phase).to.equal("Burst")
		end)

		it("clears a replaced character and an occlusion grace restored in time", function()
			local original, replacement = {}, {}
			local state, context = startCycle(10, original)
			context.Candidates = { threat(1, 10, replacement) }
			local result = Sprinter.Step(state, context, 0.1, Config)
			expect(result.ReleaseReason).to.equal("InvalidThreat")

			state, context = startCycle(10, original)
			context.CanSeeCandidate = function()
				return false
			end
			Sprinter.Step(state, context, 0.2, Config)
			expect(state.lostThreatSince).to.equal(0.2)
			context.CanSeeCandidate = function()
				return true
			end
			Sprinter.Step(state, context, 0.8, Config)
			expect(state.lostThreatSince).to.equal(nil)
			expect(state.lockedThreatUserId).to.equal(1)
		end)

		it("does not switch or restart while burst and recovery are committed", function()
			local a, b = {}, {}
			local state, context = startCycle(10, a)
			context.Candidates = { threat(1, 10, a), threat(2, 1, b) }
			local recovery = Sprinter.Step(state, context, 1.2, Config)
			expect(recovery.Phase).to.equal("Recovery")
			expect(recovery.RecoveryStarted).to.equal(true)
			expect(state.lockedThreatUserId).to.equal(1)
			local stillRecovery = Sprinter.Step(state, context, 3.0, Config)
			expect(stillRecovery.Phase).to.equal("Recovery")
			expect(stillRecovery.BurstStarted).to.equal(nil)
		end)

		it(
			"preserves cooldown through threat loss and rejects retained range as acquisition",
			function()
				local a = {}
				local state, context = startCycle(10, a)
				context.Candidates = {}
				Sprinter.Step(state, context, 1.2, Config)
				Sprinter.Step(state, context, 3.2, Config)
				local originalDeadline = state.nextBurstAt

				context.Candidates = { threat(1, 10, a) }
				local early = Sprinter.Step(state, context, 5, Config)
				expect(early.BurstStarted).to.equal(nil)
				expect(state.nextBurstAt).to.equal(originalDeadline)

				context.Candidates = { threat(1, 34, a) }
				local ready = Sprinter.Step(state, context, 6.2, Config)
				expect(ready.Phase).to.equal("Ready")
				expect(ready.BurstStarted).to.equal(nil)
				context.Candidates = { threat(1, 30, a) }
				local nextBurst = Sprinter.Step(state, context, 6.3, Config)
				expect(nextBurst.BurstStarted).to.equal(true)
			end
		)

		it("never compounds repeated peak speeds", function()
			local state, context = startCycle(10)
			local _, firstPeak = Sprinter.SampleMotion(state, 0.25, Config)
			Sprinter.Step(state, context, 6.2, Config)
			local _, secondPeak = Sprinter.SampleMotion(state, 6.45, Config)
			expect(firstPeak).to.equal(18)
			expect(secondPeak).to.equal(18)
		end)

		it("anchors deadlines to elapsed time and skips historical phase events", function()
			local state, context = startCycle(10)
			local late = Sprinter.Step(state, context, 5.5, Config)
			expect(late.Phase).to.equal("Cooldown")
			expect(late.RecoveryStarted).to.equal(nil)
			expect(late.CooldownStarted).to.equal(nil)
			expect(state.nextBurstAt).to.equal(6.2)
		end)

		it("enters one full recovery and cooldown when an obstacle aborts burst", function()
			local state = startCycle(10)
			local _, speed = Sprinter.SampleMotion(state, 0.5, Config)
			expect(Sprinter.EnterRecovery(state, 0.5, speed, "Blocked", Config)).to.equal(true)
			expect(Sprinter.EnterRecovery(state, 0.6, speed, "Blocked", Config)).to.equal(false)
			expect(state.recoveryEndsAt).to.equal(2.5)
			expect(state.nextBurstAt).to.equal(5.5)
			local phase = Sprinter.SampleMotion(state, 2.5, Config)
			expect(phase).to.equal("Cooldown")
		end)

		it("interrupts every active phase idempotently without clearing cooldown", function()
			for _, time in { 0.125, 0.8, 1.4, 3.5 } do
				local state = startCycle(10)
				local deadline = state.nextBurstAt
				state.escapeGoal = Vector3.xAxis * 10
				Sprinter.Interrupt(state, time, "Sleeping")
				expect(state.escapeGoal).to.equal(nil)
				expect(state.lockedThreatUserId).to.equal(nil)
				expect(state.nextBurstAt).to.equal(deadline)
				expect(state.Phase).to.equal("Cooldown")
				Sprinter.Interrupt(state, time + 0.1, "Cargo")
				expect(state.nextBurstAt).to.equal(deadline)
				local phase, speed = Sprinter.SampleMotion(state, time + 0.1, Config)
				expect(phase).to.equal("Cooldown")
				expect(speed).to.equal(10)
			end
		end)

		it("restores a preserved cooldown without an old burst or threat", function()
			local state = Sprinter.CreateState(2, 6.2)
			expect(state.Phase).to.equal("Cooldown")
			expect(state.nextBurstAt).to.equal(6.2)
			expect(state.lockedThreatUserId).to.equal(nil)
			local context = makeContext({ Candidates = { threat(1, 10) } })
			local result = Sprinter.Step(state, context, 2, Config)
			expect(result.BurstStarted).to.equal(nil)
			expect(result.RequestedSpeed).to.equal(10)
		end)

		it("keeps same-species individual state independent", function()
			local stateA = startCycle(10, {})
			local stateB = startCycle(6, {})
			expect(stateA ~= stateB).to.equal(true)
			expect(stateA.cycleBaseSpeed).to.equal(10)
			expect(stateB.cycleBaseSpeed).to.equal(6)
			Sprinter.Interrupt(stateA, 0.2, "Carried")
			expect(stateB.Phase).to.equal("Burst")
		end)

		it("stops synchronously when lifecycle ownership changes", function()
			local state, context = startCycle(10)
			context.LifecycleEligible = false
			context.Sensing = false
			local result = Sprinter.Step(state, context, 0.25, Config)
			expect(result.Kind).to.equal("Stop")
			expect(state.lockedThreatUserId).to.equal(nil)
			expect(state.escapeGoal).to.equal(nil)
			expect(state.Phase).to.equal("Cooldown")
		end)

		it("dispatches only explicit Rare assignments and never the equipped role", function()
			for index = 19, 25 do
				expect(Catalog.Get(string.format("BRT_%03d", index)).behaviourId).to.equal(
					"Sprinter"
				)
			end
			expect(Catalog.Get("BRT_007").tier).to.equal("Common")
			expect(Catalog.Get("BRT_007").expeditionRole).to.equal("Sprinter")
			expect(Catalog.Get("BRT_007").behaviourId).to.equal("Wanderer")
			expect(Catalog.Get("BRT_011").behaviourId).to.equal("ReactiveRunner")
		end)
	end)
end
