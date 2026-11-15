--!nocheck
return function()
	local Behaviours = require(game.ReplicatedStorage.Shared.Config.BrainrotBehaviours)
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local LegendaryPursuit = require(script.Parent.Parent.Systems.Behaviours.LegendaryPursuit)
	local Sprinter = require(script.Parent.Parent.Systems.Behaviours.Sprinter)
	local Zigzag = require(script.Parent.Parent.Systems.Behaviours.Zigzag)

	local Config = Behaviours.LegendaryPursuit
	local SprinterConfig = Behaviours.Sprinter
	local ZigzagConfig = Behaviours.Zigzag

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

	local function context(overrides)
		overrides = overrides or {}
		return {
			Authorized = if overrides.Authorized == nil then true else overrides.Authorized,
			LifecycleEligible = if overrides.LifecycleEligible == nil
				then true
				else overrides.LifecycleEligible,
			RuntimeId = overrides.RuntimeId or "legendary-a",
			Position = overrides.Position or Vector3.zero,
			Forward = overrides.Forward or -Vector3.zAxis,
			ResolvedSpeed = overrides.ResolvedSpeed or 10,
			Candidates = overrides.Candidates or {},
			Sensing = if overrides.Sensing == nil then true else overrides.Sensing,
			CanSeeCandidate = overrides.CanSeeCandidate or function()
				return true
			end,
			ResolveBurstCourse = overrides.ResolveBurstCourse or function(_, _, preferred)
				return preferred
			end,
			ResolveZigzagCourse = overrides.ResolveZigzagCourse or function(_, _, preferred)
				return preferred
			end,
		}
	end

	local function step(state, ctx, now, dt)
		return LegendaryPursuit.Step(
			state,
			ctx,
			now,
			dt or 0.1,
			Config,
			SprinterConfig,
			ZigzagConfig
		)
	end

	local function start(runtimeId, character)
		local state = LegendaryPursuit.CreateState(0)
		local ctx = context({
			RuntimeId = runtimeId or "legendary-a",
			Candidates = { threat(1, 20, character) },
		})
		local result = step(state, ctx, 0, 0)
		expect(result.Started).to.equal(true)
		ctx.Sensing = false
		return state, ctx
	end

	local function cleanup(state, now)
		LegendaryPursuit.Interrupt(state, now or 100, "TestCleanup", Config)
	end

	describe("Phase 6D-6 Legendary Pursuit", function()
		it("keeps the fixed tuning in one shared profile", function()
			local expected = {
				AwarenessRadius = 50,
				DisengageRadius = 70,
				DisengageGraceSeconds = 1.50,
				SenseIntervalSeconds = 0.10,
				OpeningDurationSeconds = 3.00,
				ZigzagCycleCount = 2,
				RepeatCooldownSeconds = 4.00,
				BlockedRetrySeconds = 0.75,
				MaxActiveEncounters = 1,
				MaxUpdateGapSeconds = 0.25,
			}
			for key, value in expected do
				expect(Config[key]).to.equal(value)
			end
		end)

		it("builds the exact fixed plan with two complete three-second openings", function()
			local plan = LegendaryPursuit.BuildPlan(Config, SprinterConfig, ZigzagConfig, 10)
			expect(plan).never.to.equal(nil)
			local samples = {
				{ 0.000, "Phase1Burst" },
				{ 1.200, "Opening1Enter" },
				{ 1.400, "Opening1" },
				{ 4.400, "Phase2Enter" },
				{ 4.700, "Phase2Zigzag" },
				{ 10.300, "Opening2Enter" },
				{ 10.500, "Opening2" },
				{ 13.500, "Cooldown" },
			}
			for _, row in samples do
				expect((LegendaryPursuit.SampleStage(plan, row[1]))).to.equal(row[2])
			end
			close(plan.Phase2Duration, 5.6)
			close(plan.Phase2EnterStartsAt - plan.Opening1StartsAt, 3)
			close(plan.SequenceEndsAt - plan.Opening2StartsAt, 3)
			close(plan.EarliestRestartAt, 17.5)
		end)

		it("reuses Sprinter speeds and Zigzag directions without compounding either", function()
			local plan = LegendaryPursuit.BuildPlan(Config, SprinterConfig, ZigzagConfig, 10)
			local motion = Sprinter.BuildMotionProfile(10, SprinterConfig)
			for _, elapsed in { 0, 0.125, 0.25, 1.0 } do
				local _, legendarySpeed = LegendaryPursuit.SampleSpeed(plan, elapsed)
				close(legendarySpeed, Sprinter.SampleBurstProfile(motion, elapsed))
			end
			local speeds = {
				{ 0.25, 18 },
				{ 1.40, 4.5 },
				{ 4.70, 10 },
				{ 10.50, 4.5 },
				{ 13.50, 10 },
			}
			for _, row in speeds do
				close(select(2, LegendaryPursuit.SampleSpeed(plan, row[1])), row[2])
			end
			local _, legendaryYaw = Zigzag.SamplePattern(0.15, plan.ZigzagPlan)
			local standalone = Zigzag.BuildCyclePlan(10, ZigzagConfig.InitialSide, ZigzagConfig)
			local _, standaloneYaw = Zigzag.SamplePattern(0.15, standalone)
			close(legendaryYaw, standaloneYaw)
		end)

		it("uses only explicit workbook-live and teased catalogue assignments", function()
			for _, id in { "BRT_031", "BRT_032", "BRT_033" } do
				expect(Catalog.Get(id).behaviourId).to.equal("LegendaryPursuit")
			end
			expect(Catalog.Get("BRT_031").launchStatus).to.equal("Live")
			expect(Catalog.Get("BRT_031").spawnEnabled).to.equal(true)
			expect(Catalog.Get("BRT_032").launchStatus).to.equal("Live")
			expect(Catalog.Get("BRT_032").spawnEnabled).to.equal(true)
			expect(Catalog.Get("BRT_033").launchStatus).to.equal("Teased")
			expect(Catalog.Get("BRT_033").spawnEnabled).to.equal(false)
			expect(Catalog.Get("BRT_034").behaviourId).to.equal("Wanderer")
			expect(Catalog.Get("BRT_035").behaviourId).to.equal("Wanderer")
		end)

		it("requires authorization, inclusive awareness, and a safe initial route", function()
			local state = LegendaryPursuit.CreateState(0)
			local result = step(
				state,
				context({
					Authorized = false,
					Candidates = { threat(1, 10) },
				}),
				0,
				0
			)
			expect(result.Kind).to.equal("Stop")

			state = LegendaryPursuit.CreateState(0)
			result = step(state, context({ Candidates = { threat(1, 50.01) } }), 0, 0)
			expect(result.Started).to.equal(nil)
			result = step(state, context({ Candidates = { threat(1, 50) } }), 0.1, 0.1)
			expect(result.Started).to.equal(true)
			cleanup(state)

			state = LegendaryPursuit.CreateState(0)
			result = step(
				state,
				context({
					Candidates = { threat(1, 10) },
					ResolveBurstCourse = function()
						return nil
					end,
				}),
				0,
				0
			)
			expect(result.Started).to.equal(nil)
			expect(state.nextBlockedRetryAt).to.equal(0.75)
			expect(LegendaryPursuit.GetDiagnostics().ActiveEncounters).to.equal(0)
		end)

		it("runs both pursuits and both openings once in the fixed order", function()
			local state, ctx = start()
			local samples = {
				{ 1.2, "Opening1Enter" },
				{ 1.4, "Opening1" },
				{ 4.4, "Phase2Enter" },
				{ 4.7, "Phase2Zigzag" },
				{ 10.3, "Opening2Enter" },
				{ 10.5, "Opening2" },
				{ 13.5, "Cooldown" },
			}
			for _, row in samples do
				local result = step(state, ctx, row[1], 0.1)
				expect(state.Stage).to.equal(row[2])
				expect(result.StageChanged).to.equal(true)
			end
			expect(state.active).to.equal(false)
			expect(state.nextAllowedAt).to.equal(17.5)
			expect(LegendaryPursuit.GetDiagnostics().ActiveEncounters).to.equal(0)
		end)

		it("holds one stable threat while another player becomes closer", function()
			local a, b = {}, {}
			local state, ctx = start("legendary-stable", a)
			ctx.Sensing = true
			ctx.Candidates = { threat(1, 60, a), threat(2, 1, b) }
			step(state, ctx, 0.1, 0.1)
			expect(state.lockedThreatUserId).to.equal(1)
			cleanup(state)
		end)

		it("releases pursuit after grace but lets an advertised opening finish", function()
			local character = {}
			local state, ctx = start("legendary-loss-pursuit", character)
			ctx.Sensing = true
			ctx.Candidates = { threat(1, 70.01, character) }
			step(state, ctx, 0.1, 0.1)
			local released = step(state, ctx, 1.6, 0.1)
			expect(released.EndedReason).to.equal("Disengaged")
			expect(state.active).to.equal(false)

			state, ctx = start("legendary-loss-opening", character)
			step(state, ctx, 1.2, 0.1)
			step(state, ctx, 1.4, 0.1)
			ctx.Sensing = true
			ctx.Candidates = {}
			local pending = step(state, ctx, 1.5, 0.1)
			expect(pending.EndedReason).to.equal(nil)
			expect(state.Stage).to.equal("Opening1")
			ctx.Sensing = false
			released = step(state, ctx, 4.4, 0.1)
			expect(released.EndedReason).to.equal("Disengaged")
			expect(state.active).to.equal(false)
		end)

		it("shortens blocked pursuits into full openings and holds blocked openings", function()
			local state, ctx = start("legendary-blocked")
			expect(LegendaryPursuit.OnMovementBlocked(state, 0.5, Config)).to.equal(true)
			expect(state.Stage).to.equal("Opening1Enter")
			step(state, ctx, 0.7, 0.1)
			expect(state.Stage).to.equal("Opening1")
			close(state.stageEndsAt - state.stageStartedAt, 3)
			expect(LegendaryPursuit.OnMovementBlocked(state, 1, Config)).to.equal(true)
			expect(step(state, ctx, 2, 0.1).Kind).to.equal("Hold")
			cleanup(state)

			state, ctx = start("legendary-phase2-blocked")
			step(state, ctx, 1.2, 0.1)
			step(state, ctx, 1.4, 0.1)
			step(state, ctx, 4.4, 0.1)
			step(state, ctx, 4.7, 0.1)
			expect(LegendaryPursuit.OnMovementBlocked(state, 5, Config)).to.equal(true)
			expect(state.Stage).to.equal("Opening2Enter")
			step(state, ctx, 5.2, 0.1)
			expect(state.Stage).to.equal("Opening2")
			close(state.stageEndsAt - state.stageStartedAt, 3)
			cleanup(state)
		end)

		it("reserves only one encounter and keeps individual state independent", function()
			local first, firstContext = start("legendary-first")
			local second = LegendaryPursuit.CreateState(0)
			local secondContext = context({
				RuntimeId = "legendary-second",
				Candidates = { threat(2, 10) },
			})
			local result = step(second, secondContext, 0, 0)
			expect(result.Started).to.equal(nil)
			expect(second.active).to.equal(false)
			expect(first.lockedThreatUserId).to.equal(1)
			cleanup(first)
			result = step(second, secondContext, 0.1, 0.1)
			expect(result.Started).to.equal(true)
			expect(second.lockedThreatUserId).to.equal(2)
			expect(firstContext.RuntimeId).never.to.equal(secondContext.RuntimeId)
			cleanup(second)
		end)

		it("interrupts every stage idempotently and preserves the established cooldown", function()
			local stageTimes = { 0.2, 1.3, 2, 4.5, 5, 10.4, 11 }
			for index, targetTime in stageTimes do
				local state, ctx = start("legendary-interrupt-" .. index)
				for _, boundary in { 1.2, 1.4, 4.4, 4.7, 10.3, 10.5 } do
					if boundary <= targetTime then
						step(state, ctx, boundary, 0.1)
					end
				end
				local deadline = state.nextAllowedAt
				expect(LegendaryPursuit.Interrupt(state, targetTime, "Sleeping", Config)).to.equal(
					true
				)
				expect(LegendaryPursuit.Interrupt(state, targetTime, "Sleeping", Config)).to.equal(
					false
				)
				expect(state.active).to.equal(false)
				expect(state.lockedThreatUserId).to.equal(nil)
				expect(state.nextAllowedAt).to.equal(deadline)
				expect(LegendaryPursuit.GetDiagnostics().ActiveEncounters).to.equal(0)
			end
		end)

		it("does not bypass cooldown after interruption and uses fresh eligibility", function()
			local state, ctx = start("legendary-cooldown")
			LegendaryPursuit.Interrupt(state, 1, "Sleeping", Config)
			ctx.Sensing = true
			local early = step(state, ctx, 10, 0.1)
			expect(early.Started).to.equal(nil)
			local ready = step(state, ctx, 17.5, 0.1)
			expect(ready.Started).to.equal(true)
			cleanup(state)
		end)

		it(
			"anchors ordinary stages but extends cooldown once after a legitimately late finish",
			function()
				local state, ctx = start("legendary-late-finish")
				for _, boundary in { 1.2, 1.4, 4.4, 4.7, 10.3, 10.5 } do
					step(state, ctx, boundary, 0.1)
				end
				local completed = step(state, ctx, 13.6, 0.1)
				expect(completed.EndedReason).to.equal("Completed")
				close(state.nextAllowedAt, 17.6)
				local deadline = state.nextAllowedAt
				LegendaryPursuit.Interrupt(state, 13.6, "Cleanup", Config)
				expect(state.nextAllowedAt).to.equal(deadline)
			end
		)

		it("ends safely on a long scheduler gap without replaying historical phases", function()
			local state, ctx = start("legendary-gap")
			local result = step(state, ctx, 1, Config.MaxUpdateGapSeconds + 0.01)
			expect(result.EndedReason).to.equal("UpdateGap")
			expect(state.active).to.equal(false)
			expect(state.Stage).to.equal("Cooldown")
			expect(LegendaryPursuit.GetDiagnostics().ActiveEncounters).to.equal(0)
		end)

		it("skips Phase 2 safely when no Zigzag course exists", function()
			local state, ctx = start("legendary-no-phase2")
			ctx.ResolveZigzagCourse = function()
				return nil
			end
			step(state, ctx, 1.2, 0.1)
			step(state, ctx, 1.4, 0.1)
			step(state, ctx, 4.4, 0.1)
			expect(state.Stage).to.equal("Opening2Enter")
			step(state, ctx, 4.6, 0.1)
			expect(state.Stage).to.equal("Opening2")
			close(state.stageEndsAt - state.stageStartedAt, 3)
			cleanup(state)
		end)
	end)
end
