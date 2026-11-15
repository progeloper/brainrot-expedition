--!nocheck
return function()
	local Config = require(game.ReplicatedStorage.Shared.Config.BrainrotBehaviours).Zigzag
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Zigzag = require(script.Parent.Parent.Systems.Behaviours.Zigzag)

	local function close(actual, expected, tolerance)
		expect(math.abs(actual - expected) <= (tolerance or 0.0001)).to.equal(true)
	end

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
			Authorized = if overrides.Authorized == nil then true else overrides.Authorized,
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
			ResolveSafeCourse = overrides.ResolveSafeCourse or function(_, _, preferred)
				return preferred
			end,
			IsCourseSafe = overrides.IsCourseSafe or function()
				return true
			end,
		}
	end

	local function engage(character, speed)
		local state = Zigzag.CreateState(0)
		local context = makeContext({
			ResolvedSpeed = speed or 10,
			Candidates = { threat(1, Vector3.new(10, 0, 0), character) },
		})
		local result = Zigzag.Step(state, context, 0, 0, Config)
		expect(result.Engaged).to.equal(true)
		expect(state.Mode).to.equal("Reorienting")
		context.Sensing = false
		Zigzag.Step(state, context, Config.CourseReorientSeconds, 1 / 60, Config)
		expect(state.Mode).to.equal("Pattern")
		return state, context
	end

	local function integratePlan(plan, cycles, externalDt)
		local position = Vector3.zero
		local elapsed = 0
		local endAt = plan.CycleDurationSeconds * cycles
		while elapsed < endAt - 1e-7 do
			local frameEnd = math.min(endAt, elapsed + externalDt)
			local cursor = elapsed
			while cursor < frameEnd - 1e-7 do
				local stepEnd = math.min(frameEnd, cursor + 1 / 60)
				local phaseTime = cursor % plan.CycleDurationSeconds
				for _, boundary in
					{
						plan.SweepDurationSeconds,
						plan.SweepDurationSeconds + plan.StraightDurationSeconds,
						2 * plan.SweepDurationSeconds + plan.StraightDurationSeconds,
						plan.CycleDurationSeconds,
					}
				do
					local absolute = cursor - phaseTime + boundary
					if absolute > cursor + 1e-7 then
						stepEnd = math.min(stepEnd, absolute)
						break
					end
				end
				local sampleAt = (cursor + stepEnd) * 0.5
				local _, yaw = Zigzag.SamplePattern(sampleAt, plan)
				local direction = Zigzag.DirectionForYaw(-Vector3.zAxis, Vector3.xAxis, yaw)
				position += direction * plan.BaseSpeed * (stepEnd - cursor)
				cursor = stepEnd
			end
			elapsed = frameEnd
		end
		return position
	end

	describe("Phase 6D-3 Zigzag", function()
		it("keeps the complete initial tuning in one shared profile", function()
			local expected = {
				AwarenessRadius = 38,
				DisengageRadius = 46,
				DisengageGraceSeconds = 0.75,
				SenseIntervalSeconds = 0.10,
				SweepDurationSeconds = 0.80,
				StraightDurationSeconds = 0.60,
				SweepTurnSeconds = 0.15,
				MaxSweepAngleDegrees = 30,
				MaxLateralOffsetStuds = 6,
				InitialSide = 1,
				CourseRefreshThresholdDegrees = 15,
				MaxCourseChangeDegrees = 30,
				CourseReorientSeconds = 0.30,
				BlockedRetrySeconds = 0.75,
			}
			for key, value in expected do
				expect(Config[key]).to.equal(value)
			end
		end)

		it("samples the exact deterministic sweep and straight sequence", function()
			local plan = Zigzag.BuildCyclePlan(10, 1, Config)
			expect(plan).never.to.equal(nil)
			close(plan.EffectiveAngleRadians, math.rad(30))
			close(plan.CycleDurationSeconds, 2.8)
			local samples = {
				{ 0.000, "SweepA", 0, false },
				{ 0.075, "SweepA", 15, false },
				{ 0.150, "SweepA", 30, false },
				{ 0.400, "SweepA", 30, false },
				{ 0.650, "SweepA", 30, false },
				{ 0.725, "SweepA", 15, false },
				{ 0.800, "StraightA", 0, true },
				{ 1.200, "StraightA", 0, true },
				{ 1.400, "SweepB", 0, false },
				{ 1.475, "SweepB", -15, false },
				{ 1.550, "SweepB", -30, false },
				{ 2.050, "SweepB", -30, false },
				{ 2.125, "SweepB", -15, false },
				{ 2.200, "StraightB", 0, true },
				{ 2.600, "StraightB", 0, true },
				{ 2.800, "SweepA", 0, false },
			}
			for _, row in samples do
				local phase, yaw, straight = Zigzag.SamplePattern(row[1], plan)
				expect(phase).to.equal(row[2])
				close(math.deg(yaw), row[3], 0.001)
				expect(straight).to.equal(row[4])
			end
		end)

		it("mirrors yaw for the opposite initial side without changing timing", function()
			local positive = Zigzag.BuildCyclePlan(10, 1, Config)
			local negative = Zigzag.BuildCyclePlan(10, -1, Config)
			for _, time in { 0, 0.075, 0.4, 0.8, 1.475, 2.2, 2.8 } do
				local phaseA, yawA, straightA = Zigzag.SamplePattern(time, positive)
				local phaseB, yawB, straightB = Zigzag.SamplePattern(time, negative)
				expect(phaseA).to.equal(phaseB)
				close(yawA, -yawB)
				expect(straightA).to.equal(straightB)
			end
		end)

		it("builds a finite horizontal basis even at zero separation", function()
			local forward, right = Zigzag.ComputeCourse(Vector3.zero, Vector3.zero, Vector3.zero)
			expect(forward.X == forward.X).to.equal(true)
			expect(right.X == right.X).to.equal(true)
			close(forward.Y, 0)
			close(right.Y, 0)
			close(forward.Magnitude, 1)
			close(right.Magnitude, 1)
			close(forward:Dot(right), 0)

			forward, right =
				Zigzag.ComputeCourse(Vector3.zero, Vector3.new(0, 0, 10), Vector3.xAxis)
			expect(forward).to.equal(-Vector3.zAxis)
			expect(right).to.equal(Vector3.xAxis)
		end)

		it(
			"preserves unit speed and zero deliberate lateral steering in straight windows",
			function()
				local plan = Zigzag.BuildCyclePlan(10, 1, Config)
				for index = 0, 280 do
					local time = index / 100
					local _, yaw, straight = Zigzag.SamplePattern(time, plan)
					local direction = Zigzag.DirectionForYaw(-Vector3.zAxis, Vector3.xAxis, yaw)
					close(direction.Magnitude, 1)
					expect(direction.Z < 0).to.equal(true)
					if straight then
						close(direction.X, 0)
					end
				end
			end
		)

		it("cancels opposite lateral sweeps and is stable at 15, 30, and 60 Hz", function()
			local plan = Zigzag.BuildCyclePlan(10, 1, Config)
			local positions = {
				integratePlan(plan, 4, 1 / 15),
				integratePlan(plan, 4, 1 / 30),
				integratePlan(plan, 4, 1 / 60),
			}
			for _, position in positions do
				close(position.X, 0, 0.01)
				expect(position.Z < 0).to.equal(true)
			end
			close((positions[1] - positions[2]).Magnitude, 0, 0.01)
			close((positions[2] - positions[3]).Magnitude, 0, 0.01)
		end)

		it("reduces the angle at high speed instead of exceeding the lateral bound", function()
			local plan = Zigzag.BuildCyclePlan(100, 1, Config)
			expect(plan.EffectiveAngleRadians < math.rad(30)).to.equal(true)
			local conservativeWidth = plan.BaseSpeed
				* plan.SweepDurationSeconds
				* math.sin(plan.EffectiveAngleRadians)
			close(conservativeWidth, Config.MaxLateralOffsetStuds)
		end)

		it("requires explicit authorization and inclusive visible 38-stud awareness", function()
			local state = Zigzag.CreateState(0)
			local unauthorized = Zigzag.Step(
				state,
				makeContext({
					Authorized = false,
					Candidates = { threat(1, Vector3.new(10, 0, 0)) },
				}),
				0,
				0,
				Config
			)
			expect(unauthorized.Kind).to.equal("Stop")

			state = Zigzag.CreateState(0)
			local outside = Zigzag.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(38.01, 0, 0)) } }),
				0,
				0,
				Config
			)
			expect(outside.Kind).to.equal("Roam")
			expect(state.lockedThreatUserId).to.equal(nil)
			local boundary = Zigzag.Step(
				state,
				makeContext({ Candidates = { threat(1, Vector3.new(38, 0, 0)) } }),
				0.1,
				0.1,
				Config
			)
			expect(boundary.Engaged).to.equal(true)
		end)

		it("selects a visible candidate behind an obstructed nearer one", function()
			local blocked, visible = {}, {}
			local state = Zigzag.CreateState(0)
			Zigzag.Step(
				state,
				makeContext({
					Candidates = {
						threat(10, Vector3.new(5, 0, 0), blocked),
						threat(20, Vector3.new(8, 0, 0), visible),
					},
					CanSeeCandidate = function(candidate)
						return candidate.Character ~= blocked
					end,
				}),
				0,
				0,
				Config
			)
			expect(state.lockedThreatUserId).to.equal(20)
		end)

		it("retains one threat and one course while other players and the target move", function()
			local a, b = {}, {}
			local state, context = engage(a)
			local originalCourse = state.courseForward
			context.Sensing = true
			context.Candidates = {
				threat(1, Vector3.new(15, 0, 10), a),
				threat(2, Vector3.new(1, 0, 0), b),
			}
			local duringSweep = Zigzag.Step(state, context, 0.7, 1 / 60, Config)
			expect(state.lockedThreatUserId).to.equal(1)
			expect(state.courseForward).to.equal(originalCourse)
			expect(duringSweep.CourseChanged).never.to.equal(true)
			local straight = Zigzag.Step(state, context, 1.3, 1 / 60, Config)
			expect(straight.StraightWindow).to.equal(true)
			expect(state.courseForward).to.equal(originalCourse)
		end)

		it("refreshes only after a complete cycle and caps course change", function()
			local a = {}
			local state, context = engage(a)
			local original = state.courseForward
			context.Sensing = true
			context.Candidates = { threat(1, Vector3.new(0, 0, 10), a) }
			local before = Zigzag.Step(state, context, 3.099, 1 / 60, Config)
			expect(before.CourseChanged).never.to.equal(true)
			expect(state.courseForward).to.equal(original)
			local boundary = Zigzag.Step(state, context, 3.1, 1 / 60, Config)
			expect(boundary.CourseChanged).to.equal(true)
			expect(boundary.CourseChangeReason).to.equal("CycleBoundary")
			local angle = math.deg(math.acos(math.clamp(original:Dot(state.courseForward), -1, 1)))
			expect(angle <= Config.MaxCourseChangeDegrees + 0.001).to.equal(true)
		end)

		it("uses retention grace and releases without same-update reacquisition", function()
			local a, b = {}, {}
			local state, context = engage(a)
			context.Sensing = true
			context.Candidates = {
				threat(1, Vector3.new(46.01, 0, 0), a),
				threat(2, Vector3.new(2, 0, 0), b),
			}
			Zigzag.Step(state, context, 1, 1 / 60, Config)
			expect(state.lockedThreatUserId).to.equal(1)
			Zigzag.Step(state, context, 1.749, 1 / 60, Config)
			expect(state.lockedThreatUserId).to.equal(1)
			local released = Zigzag.Step(state, context, 1.75, 1 / 60, Config)
			expect(released.ReleaseReason).to.equal("OutOfRange")
			expect(released.AcquiredUserId).to.equal(nil)
			expect(state.lockedThreatUserId).to.equal(nil)
		end)

		it("uses bounded blocked retries without flipping sides every update", function()
			local blocked = true
			local state = Zigzag.CreateState(0)
			local context = makeContext({
				Candidates = { threat(1, Vector3.new(10, 0, 0)) },
				ResolveSafeCourse = function(_, _, preferred)
					return if blocked then nil else preferred
				end,
			})
			local result = Zigzag.Step(state, context, 0, 0, Config)
			expect(result.RouteBlocked).to.equal(true)
			expect(state.Mode).to.equal("Blocked")
			expect(state.nextBlockedRetryAt).to.equal(0.75)
			result = Zigzag.Step(state, context, 0.5, 1 / 60, Config)
			expect(result.Kind).to.equal("Hold")
			expect(state.nextBlockedRetryAt).to.equal(0.75)
			blocked = false
			result = Zigzag.Step(state, context, 0.75, 1 / 60, Config)
			expect(result.CourseChanged).to.equal(true)
			expect(result.CourseChangeReason).to.equal("Obstacle")
		end)

		it("keeps state independent and interrupts every movement mode idempotently", function()
			local stateA = engage({})
			local stateB = engage({})
			stateA.lockedThreatUserId = 11
			stateB.lockedThreatUserId = 22
			expect(stateA).never.to.equal(stateB)
			expect(stateA.lockedThreatUserId).to.equal(11)
			expect(stateB.lockedThreatUserId).to.equal(22)

			for _, mode in { "Reorienting", "Pattern", "Blocked" } do
				local state = Zigzag.CreateState(0)
				state.Mode = mode
				state.lockedThreatUserId = 1
				state.courseForward = Vector3.xAxis
				Zigzag.Interrupt(state, 1, "Sleeping")
				expect(state.Mode).to.equal("Inactive")
				expect(state.lockedThreatUserId).to.equal(nil)
				expect(state.courseForward).to.equal(nil)
				Zigzag.Interrupt(state, 2, "Cargo")
				expect(state.Mode).to.equal("Inactive")
			end
		end)

		it("stops on lifecycle loss and restarts with clean state after a real wake", function()
			local state = engage({})
			local stopped =
				Zigzag.Step(state, makeContext({ LifecycleEligible = false }), 0.5, 1 / 60, Config)
			expect(stopped.Kind).to.equal("Stop")
			expect(state.Mode).to.equal("Inactive")
			expect(state.lockedThreatUserId).to.equal(nil)
			local resumed = Zigzag.Step(
				state,
				makeContext({ Candidates = { threat(5, Vector3.new(5, 0, 0)) } }),
				2,
				1 / 60,
				Config
			)
			expect(resumed.Engaged).to.equal(true)
			expect(state.lockedThreatUserId).to.equal(5)
		end)

		it("discards historical travel after a stalled movement update", function()
			local state, context = engage({})
			local result = Zigzag.Step(state, context, 1, 0.2, Config)
			expect(result.CourseChanged).to.equal(true)
			expect(result.CourseChangeReason).to.equal("Stall")
			expect(state.Mode).to.equal("Reorienting")
			expect(state.reorientStartedAt).to.equal(1)
		end)

		it("does not infer Zigzag from Epic rarity or equipped-team roles", function()
			for index = 26, 30 do
				local definition = Catalog.Get(string.format("BRT_%03d", index))
				expect(definition.tier).to.equal("Epic")
				local expected = if index == 28
					then "Camouflage"
					elseif index == 29 then "DecoySplit"
					else "Wanderer"
				expect(definition.behaviourId).to.equal(expected)
			end
			expect(Catalog.Get("BRT_007").expeditionRole).to.equal("Sprinter")
			expect(Catalog.Get("BRT_007").behaviourId).to.equal("Wanderer")
			expect(Catalog.Get("BRT_011").behaviourId).to.equal("ReactiveRunner")
			expect(Catalog.Get("BRT_019").behaviourId).to.equal("Sprinter")
		end)
	end)
end
