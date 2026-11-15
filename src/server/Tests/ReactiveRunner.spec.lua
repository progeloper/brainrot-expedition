--!nocheck
return function()
	local Config = require(game.ReplicatedStorage.Shared.Config.BrainrotBehaviours).ReactiveRunner
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local ReactiveRunner = require(script.Parent.Parent.Systems.Behaviours.ReactiveRunner)

	local function threat(userId, position, character)
		return {
			UserId = userId,
			Position = position,
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
			ResolvedSpeed = overrides.ResolvedSpeed or 6,
			Candidates = overrides.Candidates or {},
			Sensing = if overrides.Sensing == nil then true else overrides.Sensing,
			CanSeeCandidate = overrides.CanSeeCandidate or function()
				return true
			end,
			ResolveEscapeGoal = overrides.ResolveEscapeGoal
				or function(position, _, preferred, distance)
					return position + preferred * distance
				end,
		}
	end

	describe("Phase 6D-1 Reactive Runner", function()
		it("keeps all tuning in one shared profile", function()
			expect(Config.AwarenessRadius).to.equal(24)
			expect(Config.DisengageRadius).to.equal(30)
			expect(Config.DisengageGraceSeconds).to.equal(0.75)
			expect(Config.SenseIntervalSeconds).to.equal(0.10)
			expect(Config.ReplanIntervalSeconds).to.equal(0.75)
			expect(Config.TurnBlendSeconds).to.equal(0.35)
			expect(Config.GoalReachedDistance).to.equal(2)
			expect(Config.MinimumEscapeDistance).to.equal(12)
			expect(Config.EscapeLookAheadSeconds).to.equal(1.25)
			expect(Config.BlockedRetrySeconds).to.equal(0.75)
		end)

		it("acquires inclusively at 24 studs but not at 24.01", function()
			local state = ReactiveRunner.CreateState(0)
			local result = ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(24.01, 0, 0)) } }),
				0,
				Config
			)
			expect(result.Kind).to.equal("UseRoaming")
			expect(state.lockedThreatUserId).to.equal(nil)

			result = ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(24, 0, 0)) } }),
				0.1,
				Config
			)
			expect(result.Kind).to.equal("Escape")
			expect(state.lockedThreatUserId).to.equal(1)
		end)

		it("skips an obstructed nearest candidate and uses deterministic ties", function()
			local blockedCharacter, visibleCharacter = {}, {}
			local selected = ReactiveRunner.SelectThreat(Vector3.zero, {
				threat(20, Vector3.new(5, 0, 0), blockedCharacter),
				threat(30, Vector3.new(8, 0, 0), visibleCharacter),
			}, function(candidate)
				return candidate.Character ~= blockedCharacter
			end, Config)
			expect(selected.UserId).to.equal(30)

			selected = ReactiveRunner.SelectThreat(Vector3.zero, {
				threat(9, Vector3.new(-8, 0, 0)),
				threat(4, Vector3.new(8, 0, 0)),
			}, function()
				return true
			end, Config)
			expect(selected.UserId).to.equal(4)
		end)

		it("retains one threat despite a closer player and at 27 studs", function()
			local characterA, characterB = {}, {}
			local state = ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), characterA) } }),
				0,
				Config
			)
			ReactiveRunner.Step(
				state,
				makeContext({
					Candidates = {
						threat(1, Vector3.new(27, 0, 0), characterA),
						threat(2, Vector3.new(2, 0, 0), characterB),
					},
				}),
				0.1,
				Config
			)
			expect(state.lockedThreatUserId).to.equal(1)
			expect(state.lostThreatSince).to.equal(nil)
		end)

		it("uses grace for range or occlusion and clears it when visibility returns", function()
			local character = {}
			local state = ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), character) } }),
				0,
				Config
			)
			local far =
				makeContext({ Candidates = { threat(1, Vector3.new(31, 0, 0), character) } })
			ReactiveRunner.Step(state, far, 1, Config)
			expect(state.lockedThreatUserId).to.equal(1)
			ReactiveRunner.Step(state, far, 1.74, Config)
			expect(state.lockedThreatUserId).to.equal(1)

			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(20, 0, 0), character) } }),
				1.75,
				Config
			)
			expect(state.lostThreatSince).to.equal(nil)

			local hidden = makeContext({
				Candidates = { threat(1, Vector3.new(20, 0, 0), character) },
				CanSeeCandidate = function()
					return false
				end,
			})
			ReactiveRunner.Step(state, hidden, 2, Config)
			local released = ReactiveRunner.Step(state, hidden, 2.75, Config)
			expect(released.ReleaseReason).to.equal("Occluded")
			expect(state.lockedThreatUserId).to.equal(nil)
		end)

		it("releases after continuous out-of-range grace and not earlier", function()
			local character = {}
			local state = ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), character) } }),
				0,
				Config
			)
			local far =
				makeContext({ Candidates = { threat(1, Vector3.new(31, 0, 0), character) } })
			ReactiveRunner.Step(state, far, 1, Config)
			expect(ReactiveRunner.Step(state, far, 1.749, Config).ReleaseReason).to.equal(nil)
			local result = ReactiveRunner.Step(state, far, 1.75, Config)
			expect(result.Kind).to.equal("UseRoaming")
			expect(result.ReleaseReason).to.equal("OutOfRange")
		end)

		it("uses one continuous grace timer when the lost condition changes", function()
			local character = {}
			local state = ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), character) } }),
				0,
				Config
			)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(31, 0, 0), character) } }),
				1,
				Config
			)
			local hidden = makeContext({
				Candidates = { threat(1, Vector3.new(20, 0, 0), character) },
				CanSeeCandidate = function()
					return false
				end,
			})
			local result = ReactiveRunner.Step(state, hidden, 1.75, Config)
			expect(result.ReleaseReason).to.equal("Occluded")
			expect(state.lockedThreatUserId).to.equal(nil)
		end)

		it("does not follow a replacement character", function()
			local original, replacement = {}, {}
			local state = ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), original) } }),
				0,
				Config
			)
			local result = ReactiveRunner.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(10, 0, 0), replacement) } }),
				0.1,
				Config
			)
			expect(result.ReleaseReason).to.equal("InvalidThreat")
			expect(state.lockedThreatUserId).to.equal(nil)
		end)

		it("always returns a finite overlap fallback direction", function()
			for _, fallback in { Vector3.zero, Vector3.new(0, 2, 0), Vector3.new(0, 0, -3) } do
				local direction = ReactiveRunner.ComputeEscapeDirection(
					Vector3.new(5, 0, 5),
					Vector3.new(5, 10, 5),
					fallback
				)
				expect(direction.X == direction.X and direction.Z == direction.Z).to.equal(true)
				expect(math.abs(direction.Magnitude - 1) < 0.0001).to.equal(true)
			end
		end)

		it("uses bounded deterministic route alternatives and hold retries", function()
			local attempts = {}
			local goal = ReactiveRunner.ResolveEscapeGoal(
				Vector3.zero,
				Vector3.xAxis,
				12,
				function(candidate)
					table.insert(attempts, candidate)
					return #attempts == 3
				end
			)
			expect(goal ~= nil).to.equal(true)
			expect(#attempts).to.equal(3)

			attempts = {}
			expect(
				ReactiveRunner.ResolveEscapeGoal(
					Vector3.zero,
					Vector3.xAxis,
					12,
					function(candidate)
						table.insert(attempts, candidate)
						return false
					end
				)
			).to.equal(nil)
			expect(#attempts).to.equal(10)

			local state = ReactiveRunner.CreateState(0)
			local context = makeContext({
				Candidates = { threat(1, Vector3.new(10, 0, 0)) },
				ResolveEscapeGoal = function()
					return nil
				end,
			})
			local result = ReactiveRunner.Step(state, context, 0, Config)
			expect(result.Kind).to.equal("Hold")
			expect(result.RouteBlocked).to.equal(true)
			result = ReactiveRunner.Step(state, context, 0.5, Config)
			expect(result.Kind).to.equal("Hold")
			expect(result.RouteBlocked).to.equal(nil)
		end)

		it("does not replan every update or increase resolved speed", function()
			local character, replans, observedDistance = {}, 0, nil
			local state = ReactiveRunner.CreateState(0)
			local context = makeContext({
				ResolvedSpeed = 6,
				Candidates = { threat(1, Vector3.new(10, 0, 0), character) },
				ResolveEscapeGoal = function(position, _, preferred, distance)
					replans += 1
					observedDistance = distance
					return position + preferred * distance
				end,
			})
			local first = ReactiveRunner.Step(state, context, 0, Config)
			local goal = first.Goal
			for index = 1, 7 do
				context.Sensing = false
				local result = ReactiveRunner.Step(state, context, index * 0.1, Config)
				expect(result.Goal).to.equal(goal)
			end
			expect(replans).to.equal(1)
			expect(observedDistance).to.equal(12)
		end)

		it("keeps same-species state independent and stops immediately for lifecycle", function()
			local stateA, stateB = ReactiveRunner.CreateState(0), ReactiveRunner.CreateState(0)
			ReactiveRunner.Step(
				stateA,
				makeContext({ Candidates = { threat(1, Vector3.new(5, 0, 0)) } }),
				0,
				Config
			)
			ReactiveRunner.Step(
				stateB,
				makeContext({ Candidates = { threat(2, Vector3.new(-5, 0, 0)) } }),
				0,
				Config
			)
			expect(stateA.lockedThreatUserId).to.equal(1)
			expect(stateB.lockedThreatUserId).to.equal(2)

			local stopped = ReactiveRunner.Step(
				stateA,
				makeContext({ LifecycleEligible = false, Sensing = false }),
				0.01,
				Config
			)
			expect(stopped.Kind).to.equal("Stop")
			expect(stateA.lockedThreatUserId).to.equal(nil)
			expect(stateB.lockedThreatUserId).to.equal(2)
		end)

		it("keeps dispatch explicit and the BRT_007 role independent", function()
			for index = 11, 18 do
				expect(Catalog.Get(string.format("BRT_%03d", index)).behaviourId).to.equal(
					"ReactiveRunner"
				)
			end
			expect(Catalog.Get("BRT_007").behaviourId).to.equal("Wanderer")
			expect(Catalog.Get("BRT_007").expeditionRole).to.equal("Sprinter")
		end)
	end)
end
