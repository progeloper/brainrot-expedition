--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartMovementProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)
	local CartPerformanceMotionSimulator =
		require(script.Parent.Parent.Utility.CartPerformanceMotionSimulator)

	local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
	local EPSILON = 1e-6

	type FakeConnection = {
		Disconnect: (self: FakeConnection) -> (),
	}

	local function makeCart(index: number): (Model, BasePart)
		local cart = Instance.new("Model")
		local root = Instance.new("Part")

		cart.Name = string.format("PerformanceCart%d", index)
		root.Name = "Root"
		root.Parent = cart

		return cart, root
	end

	describe("CartPerformanceMotionSimulator", function()
		it("defines the deterministic 27-second forward/coast/brake/reverse cycle", function()
			expect(CartPerformanceMotionSimulator.CycleDuration).to.equal(27)
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(0)).to.equal("Forward")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(4.499)).to.equal("Forward")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(4.5)).to.equal("Coast")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(4.75)).to.equal("Brake")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(6)).to.equal("Stopped")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(9)).to.equal("Reverse")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(17)).to.equal("Coast")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(17.15)).to.equal("Brake")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(18.5)).to.equal("Stopped")
			expect(CartPerformanceMotionSimulator.GetPhaseAtTime(27)).to.equal("Forward")
		end)

		it("keeps a complete simulated cycle inside the Phase 1D speed limits", function()
			local deltaTime = 1 / 60
			local forwardSpeed = 0
			local yawRate = 0
			local seen: { [string]: boolean } = {}

			for stepIndex = 0, 27 * 60 - 1 do
				local plan = CartPerformanceMotionSimulator.ComputePlan(
					stepIndex * deltaTime,
					forwardSpeed,
					yawRate,
					deltaTime,
					profile
				)

				expect(plan.IsValid).to.equal(true)
				expect(plan.TargetForwardSpeed <= math.min(6, profile.HuntingSpeed * 0.3) + EPSILON).to.equal(
					true
				)
				expect(plan.TargetForwardSpeed <= profile.MaxTravelSpeed).to.equal(true)
				expect(plan.TargetForwardSpeed >= -profile.RecoveryBackupSpeed).to.equal(true)
				expect(plan.PlannedForwardSpeed <= profile.MaxTravelSpeed + EPSILON).to.equal(true)
				expect(plan.PlannedForwardSpeed >= -profile.RecoveryBackupSpeed - EPSILON).to.equal(
					true
				)
				expect(
					math.abs(plan.DeltaForwardSpeed)
						<= plan.Response * plan.EffectiveDeltaTime + EPSILON
				).to.equal(true)

				seen[plan.Phase] = true
				forwardSpeed = plan.PlannedForwardSpeed
				yawRate = plan.PlannedYawRate
			end

			expect(seen.Forward).to.equal(true)
			expect(seen.Coast).to.equal(true)
			expect(seen.Brake).to.equal(true)
			expect(seen.Stopped).to.equal(true)
			expect(seen.Reverse).to.equal(true)
			expect(math.abs(forwardSpeed) <= EPSILON).to.equal(true)
		end)

		it("keeps signed lane displacement bounded over a five-minute run", function()
			local deltaTime = 1 / 60
			local forwardSpeed = 0
			local yawRate = 0
			local signedDisplacement = 0
			local maximumAbsoluteDisplacement = 0

			for stepIndex = 0, 300 * 60 - 1 do
				local plan = CartPerformanceMotionSimulator.ComputePlan(
					stepIndex * deltaTime,
					forwardSpeed,
					yawRate,
					deltaTime,
					profile
				)
				local nextForwardSpeed = plan.PlannedForwardSpeed

				signedDisplacement += (forwardSpeed + nextForwardSpeed) * 0.5 * deltaTime
				maximumAbsoluteDisplacement =
					math.max(maximumAbsoluteDisplacement, math.abs(signedDisplacement))
				forwardSpeed = nextForwardSpeed
				yawRate = plan.PlannedYawRate
			end

			-- This is a Development route-fit assertion, not a gameplay travel or
			-- launch-performance budget. It keeps the simulator well inside the
			-- 192-stud lane barrier throughout a formal five-minute capture.
			expect(maximumAbsoluteDisplacement < 64).to.equal(true)
			expect(math.abs(signedDisplacement) < 32).to.equal(true)
		end)

		it("caps stalled-frame impulses and uses only a tiny bounded yaw target", function()
			local plan = CartPerformanceMotionSimulator.ComputePlan(2, 0, 0, 10, profile)
			local maximumYawTarget = math.rad(math.min(profile.TurnRate, profile.MaxAngularSpeed))
				* 0.04

			expect(plan.EffectiveDeltaTime).to.equal(0.25)
			expect(
				math.abs(plan.DeltaForwardSpeed)
					<= plan.Response * plan.EffectiveDeltaTime + EPSILON
			).to.equal(true)
			expect(math.abs(plan.TargetYawRate) <= maximumYawTarget + EPSILON).to.equal(true)
			expect(math.abs(plan.PlannedYawRate) <= maximumYawTarget + EPSILON).to.equal(true)
		end)

		it("returns a finite no-op plan for non-finite physical readings", function()
			local plan =
				CartPerformanceMotionSimulator.ComputePlan(0, 0 / 0, math.huge, 1 / 60, profile)

			expect(plan.IsValid).to.equal(false)
			expect(plan.DeltaForwardSpeed).to.equal(0)
			expect(plan.DeltaYawRate).to.equal(0)
			expect(plan.PlannedForwardSpeed).to.equal(0)
			expect(plan.PlannedYawRate).to.equal(0)
		end)

		it("runs twelve carts from one scheduler and clears owned state idempotently", function()
			local callback: ((number) -> ())? = nil
			local connectCount = 0
			local disconnectCount = 0
			local linearImpulseCount = 0
			local angularImpulseCount = 0
			local carts: { Model } = {}
			local records: { CartPerformanceMotionSimulator.RuntimeCartRecord } = {}

			local simulator = CartPerformanceMotionSimulator.new({
				IsAllowed = function()
					return true
				end,
				ConnectHeartbeat = function(nextCallback: (number) -> ()): FakeConnection
					connectCount += 1
					callback = nextCallback

					return {
						Disconnect = function(_self: FakeConnection)
							disconnectCount += 1
						end,
					}
				end,
				IsRecordLive = function(_cart: Model, _root: BasePart)
					return true
				end,
				ReadPhysicalState = function(
					_root: BasePart
				): (Vector3, Vector3, Vector3, number, boolean)
					return Vector3.new(0, 0, -1), Vector3.zero, Vector3.zero, 10, false
				end,
				ApplyLinearImpulse = function(_root: BasePart, impulse: Vector3)
					expect(impulse.Magnitude > 0).to.equal(true)
					linearImpulseCount += 1
				end,
				ApplyAngularImpulse = function(_root: BasePart, impulse: Vector3)
					expect(impulse.Magnitude > 0).to.equal(true)
					angularImpulseCount += 1
				end,
			})

			for index = 1, 12 do
				local cart = makeCart(index)

				table.insert(carts, cart)
				table.insert(records, {
					Model = cart,
					MovementProfile = profile,
				})
			end

			expect(simulator:Start(records)).to.equal(true)
			expect(simulator:Start(records)).to.equal(false)
			expect(connectCount).to.equal(1)
			expect(callback == nil).to.equal(false)

			local heartbeat = callback

			assert(heartbeat ~= nil, "test heartbeat was not connected")
			heartbeat(1 / 60)

			local activeDiagnostics = simulator:GetDiagnostics()

			expect(activeDiagnostics.Started).to.equal(true)
			expect(activeDiagnostics.RecordCount).to.equal(12)
			expect(activeDiagnostics.SchedulerCount).to.equal(1)
			expect(activeDiagnostics.StepCount).to.equal(1)
			expect(activeDiagnostics.AppliedRecordCount).to.equal(12)
			expect(activeDiagnostics.LinearImpulseCount).to.equal(12)
			expect(activeDiagnostics.AngularImpulseCount).to.equal(12)
			expect(linearImpulseCount).to.equal(12)
			expect(angularImpulseCount).to.equal(12)

			for _, cart in carts do
				expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Active)).to.equal(
					true
				)
				expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Phase)).to.equal(
					"Forward"
				)
			end

			expect(simulator:Stop()).to.equal(true)
			expect(simulator:Stop()).to.equal(false)
			expect(disconnectCount).to.equal(1)

			local stoppedDiagnostics = simulator:GetDiagnostics()

			expect(stoppedDiagnostics.Started).to.equal(false)
			expect(stoppedDiagnostics.RecordCount).to.equal(0)
			expect(stoppedDiagnostics.SchedulerCount).to.equal(0)
			expect(stoppedDiagnostics.AppliedRecordCount).to.equal(12)

			for _, cart in carts do
				expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Active)).to.equal(
					nil
				)
				expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Phase)).to.equal(
					nil
				)
				cart:Destroy()
			end
		end)

		it("uses an injected monotonic clock instead of an arbitrary heartbeat delta", function()
			local callback: ((number) -> ())? = nil
			local clockTime = 100
			local observedLinearImpulse = Vector3.zero
			local cart = makeCart(1)
			local simulator = CartPerformanceMotionSimulator.new({
				IsAllowed = function()
					return true
				end,
				Clock = function()
					return clockTime
				end,
				ConnectHeartbeat = function(nextCallback: (number) -> ())
					callback = nextCallback

					return {
						Disconnect = function() end,
					}
				end,
				IsRecordLive = function()
					return true
				end,
				ReadPhysicalState = function()
					return Vector3.new(0, 0, -1), Vector3.zero, Vector3.zero, 2, false
				end,
				ApplyLinearImpulse = function(_root: BasePart, impulse: Vector3)
					observedLinearImpulse = impulse
				end,
				ApplyAngularImpulse = function() end,
			})

			simulator:Start({ {
				Model = cart,
				MovementProfile = profile,
			} })
			clockTime = 100.5

			local heartbeat = callback

			assert(heartbeat ~= nil, "test heartbeat was not connected")
			heartbeat(999)

			local diagnostics = simulator:GetDiagnostics()
			local maximumDeltaSpeed = profile.ForwardAcceleration * 0.25

			expect(math.abs(diagnostics.ElapsedSeconds - 0.5) <= EPSILON).to.equal(true)
			expect(observedLinearImpulse.Magnitude <= 2 * maximumDeltaSpeed + EPSILON).to.equal(
				true
			)

			simulator:Stop()
			cart:Destroy()
		end)

		it("rejects non-Development use before allocating a scheduler", function()
			local connectCount = 0
			local cart = makeCart(1)
			local simulator = CartPerformanceMotionSimulator.new({
				IsAllowed = function()
					return false
				end,
				ConnectHeartbeat = function(_callback: (number) -> ())
					connectCount += 1
					return { Disconnect = function() end }
				end,
			})
			local succeeded = pcall(function()
				simulator:Start({ {
					Model = cart,
					MovementProfile = profile,
				} })
			end)

			expect(succeeded).to.equal(false)
			expect(connectCount).to.equal(0)
			expect(simulator:GetDiagnostics().SchedulerCount).to.equal(0)
			expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Active)).to.equal(
				nil
			)

			cart:Destroy()
		end)

		it("contains callback failure and prevents a repeated error loop", function()
			local callback: ((number) -> ())? = nil
			local disconnectCount = 0
			local warningCount = 0
			local cart = makeCart(1)
			local simulator = CartPerformanceMotionSimulator.new({
				IsAllowed = function()
					return true
				end,
				ConnectHeartbeat = function(nextCallback: (number) -> ())
					callback = nextCallback

					return {
						Disconnect = function()
							disconnectCount += 1
						end,
					}
				end,
				IsRecordLive = function()
					return true
				end,
				ReadPhysicalState = function()
					error("controlled read failure")
				end,
				Warn = function(_message: string)
					warningCount += 1
				end,
			})

			simulator:Start({ {
				Model = cart,
				MovementProfile = profile,
			} })

			local heartbeat = callback

			assert(heartbeat ~= nil, "test heartbeat was not connected")
			heartbeat(1 / 60)

			local diagnostics = simulator:GetDiagnostics()

			expect(diagnostics.Started).to.equal(false)
			expect(diagnostics.SchedulerCount).to.equal(0)
			expect(diagnostics.RecordCount).to.equal(0)
			expect(diagnostics.ErrorCount).to.equal(1)
			expect(disconnectCount).to.equal(1)
			expect(warningCount).to.equal(1)
			expect(cart:GetAttribute(CartPerformanceMotionSimulator.Attributes.Active)).to.equal(
				nil
			)

			cart:Destroy()
		end)
	end)
end
