--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartLongitudinalStateMachine =
		require(ReplicatedStorage.Shared.Utility.CartLongitudinalStateMachine)
	local CartMovementProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)

	local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)

	local function step(snapshot: any, throttle: number, speed: number, now: number)
		return CartLongitudinalStateMachine.Step(snapshot, throttle, speed, now, profile)
	end

	local function reachReverse(startTime: number): any
		local snapshot = CartLongitudinalStateMachine.Create(startTime)

		snapshot = step(snapshot, 1, 0, startTime + 0.1).Snapshot
		snapshot = step(snapshot, 1, profile.MaxTravelSpeed, startTime + 0.2).Snapshot
		snapshot = step(snapshot, -1, 10, startTime + 0.3).Snapshot
		snapshot = step(snapshot, -1, 0, startTime + 0.4).Snapshot

		return step(snapshot, -1, 0, startTime + 0.4 + profile.RecoveryInputDelay).Snapshot
	end

	describe("CartLongitudinalStateMachine", function()
		it("accepts only the seven Phase 1I state names", function()
			for _, stateName in
				{
					"Idle",
					"Accelerating",
					"Cruising",
					"Coasting",
					"Braking",
					"Stopped",
					"Reverse",
				}
			do
				expect(CartLongitudinalStateMachine.IsValidState(stateName)).to.equal(true)
			end

			expect(CartLongitudinalStateMachine.IsValidState("Forward")).to.equal(false)
			expect(CartLongitudinalStateMachine.IsValidState("RecoveryHold")).to.equal(false)
			expect(CartLongitudinalStateMachine.IsValidState("RecoveryBackup")).to.equal(false)
		end)

		it("detects a new reverse episode even when its release edge was not observed", function()
			expect(
				CartLongitudinalStateMachine.RequiresReverseEpisodeRestart(
					"Reverse",
					"Reverse",
					4,
					6
				)
			).to.equal(true)
			expect(
				CartLongitudinalStateMachine.RequiresReverseEpisodeRestart(
					"Reverse",
					"Reverse",
					4,
					4
				)
			).to.equal(false)
			expect(
				CartLongitudinalStateMachine.RequiresReverseEpisodeRestart("Reverse", "None", 4, 5)
			).to.equal(false)

			local snapshot = reachReverse(0)

			if
				CartLongitudinalStateMachine.RequiresReverseEpisodeRestart(
					"Reverse",
					"Reverse",
					4,
					6
				)
			then
				snapshot = step(snapshot, 0, -2, 1).Snapshot
			end

			snapshot = step(snapshot, -1, -2, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Coasting")
		end)

		it("implements the complete forward-to-reverse sequence", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, 1, 0, 0.1).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")

			snapshot = step(snapshot, 1, profile.MaxTravelSpeed, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Cruising")

			snapshot = step(snapshot, 0, 30, 2).Snapshot
			expect(snapshot.CurrentState).to.equal("Coasting")

			snapshot = step(snapshot, -1, 20, 3).Snapshot
			expect(snapshot.CurrentState).to.equal("Braking")
			expect((snapshot.CurrentTransition :: any).TargetState).to.equal("Reverse")

			snapshot = step(snapshot, -1, 0, 4).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
			expect((snapshot.CurrentTransition :: any).StartedAt).to.equal(4)

			snapshot = step(snapshot, -1, 0, 4 + profile.RecoveryInputDelay - 0.001).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, -1, 0, 4 + profile.RecoveryInputDelay).Snapshot
			expect(snapshot.CurrentState).to.equal("Reverse")
			expect(snapshot.CurrentTransition).to.equal(nil)
		end)

		it("requires braking and Stopped before forward motion after Reverse", function()
			local snapshot = reachReverse(0)

			expect(snapshot.CurrentState).to.equal("Reverse")

			snapshot = step(snapshot, 1, -2, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Braking")
			expect((snapshot.CurrentTransition :: any).TargetState).to.equal("Accelerating")

			snapshot = step(snapshot, 1, 0, 1.1).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, 1, 0, 1.2).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")
		end)

		it("never permits Reverse while forward motion remains", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)
			local throttleSpam = { 1, -1, 0, -1, 1, -1, 0, -1 }

			for index, throttle in throttleSpam do
				snapshot = step(snapshot, throttle, 10, index * 0.1).Snapshot
				expect(snapshot.CurrentState == "Reverse").to.equal(false)
			end
		end)

		it("cancels braking when forward intent resumes during forward travel", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, 1, 10, 0.1).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")

			snapshot = step(snapshot, -1, 10, 0.2).Snapshot
			expect(snapshot.CurrentState).to.equal("Braking")

			snapshot = step(snapshot, 1, 8, 0.3).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")
			expect(snapshot.CurrentTransition).to.equal(nil)
		end)

		it("returns from Cruising to Accelerating after a forward-speed loss", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, 1, profile.MaxTravelSpeed, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Cruising")

			snapshot = step(snapshot, 1, profile.HuntingSpeed, 2).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")
		end)

		it("predicts safe forward control but requires approval for reverse propulsion", function()
			local resolveAction = CartLongitudinalStateMachine.ResolveControlAction
			local threshold = profile.NearZeroSpeedThreshold

			expect(resolveAction("Idle", "Forward", 0, 0, threshold, false)).to.equal(
				"ForwardPropulsion"
			)
			expect(resolveAction("Stopped", "Reverse", 0, 0, threshold, false)).to.equal("Coast")
			expect(resolveAction("Accelerating", "Forward", 0, 0, threshold, false)).to.equal(
				"ForwardPropulsion"
			)
			expect(resolveAction("Cruising", "Reverse", 10, 10, threshold, false)).to.equal("Brake")
			expect(resolveAction("Coasting", "Reverse", -1, -1, threshold, false)).to.equal("Coast")
			expect(resolveAction("Reverse", "Reverse", -1, -1, threshold, false)).to.equal("Coast")
			expect(resolveAction("Reverse", "Reverse", -1, -1, threshold, true)).to.equal(
				"ReversePropulsion"
			)
			expect(resolveAction("Reverse", "Forward", -1, -1, threshold, false)).to.equal("Brake")
			expect(resolveAction("Braking", "None", 10, 10, threshold, false)).to.equal("Coast")
			expect(resolveAction("Teleporting", "Forward", 0, 0, threshold, false)).to.equal(
				"Coast"
			)
		end)

		it("cannot accumulate a reverse delay through rapid near-zero input changes", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, -1, profile.NearZeroSpeedThreshold + 0.001, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Braking")

			snapshot = step(snapshot, -1, 0, 2).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, 0, 0, 2.2).Snapshot
			expect(snapshot.CurrentState).to.equal("Idle")

			snapshot = step(snapshot, -1, 0, 2.3).Snapshot
			snapshot = step(snapshot, 0, 0, 2.4).Snapshot
			snapshot = step(snapshot, -1, 0, 2.5).Snapshot
			snapshot = step(snapshot, -1, 0, 2.5 + profile.RecoveryInputDelay - 0.001).Snapshot

			expect(snapshot.CurrentState).to.equal("Stopped")
		end)

		it("does not confuse collision velocity with reverse authority", function()
			local backwardCollision = step(CartLongitudinalStateMachine.Create(0), -1, -2, 1)
			local reverseSnapshot = reachReverse(0)
			local forwardRebound = step(reverseSnapshot, -1, 2, 2)

			expect(backwardCollision.Snapshot.CurrentState).to.equal("Coasting")
			expect(forwardRebound.Snapshot.CurrentState).to.equal("Braking")
			expect((forwardRebound.Snapshot.CurrentTransition :: any).TargetState).to.equal(
				"Reverse"
			)
		end)

		it("starts the reverse delay only after the explicit stop gate", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, 1, 0, 0.1).Snapshot
			snapshot = step(snapshot, -1, 12, 1).Snapshot
			snapshot = step(snapshot, -1, 8, 10).Snapshot
			expect(snapshot.CurrentState).to.equal("Braking")

			snapshot = step(snapshot, -1, 0, 20).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
			expect((snapshot.CurrentTransition :: any).StartedAt).to.equal(20)

			snapshot = step(snapshot, -1, 0, 20 + profile.RecoveryInputDelay - 0.001).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, -1, 0, 20 + profile.RecoveryInputDelay).Snapshot
			expect(snapshot.CurrentState).to.equal("Reverse")
		end)

		it("does not count time spent idling toward reverse engagement", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, -1, 0, 100).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
			expect((snapshot.CurrentTransition :: any).StartedAt).to.equal(100)

			snapshot = step(snapshot, -1, 0, 100 + profile.RecoveryInputDelay).Snapshot
			expect(snapshot.CurrentState).to.equal("Reverse")
		end)

		it("cancels and restarts a pending reverse transition", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, -1, 0, 1).Snapshot
			snapshot = step(snapshot, 0, 0, 1.2).Snapshot
			expect(snapshot.CurrentState).to.equal("Idle")
			expect(snapshot.CurrentTransition).to.equal(nil)

			snapshot = step(snapshot, -1, 0, 2).Snapshot
			expect((snapshot.CurrentTransition :: any).StartedAt).to.equal(2)

			snapshot = step(snapshot, -1, 0, 2 + profile.RecoveryInputDelay - 0.001).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
		end)

		it("treats release from Reverse as Coasting and requires a new stop gate", function()
			local snapshot = reachReverse(0)

			snapshot = step(snapshot, 0, -2, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Coasting")

			snapshot = step(snapshot, -1, -2, 1.1).Snapshot
			expect(snapshot.CurrentState).to.equal("Coasting")
			expect((snapshot.CurrentTransition :: any).TargetState).to.equal("Reverse")

			snapshot = step(snapshot, -1, 0, 1.2).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
			expect((snapshot.CurrentTransition :: any).StartedAt).to.equal(1.2)

			snapshot = step(snapshot, -1, 0, 1.2 + profile.RecoveryInputDelay - 0.001).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, -1, 0, 1.2 + profile.RecoveryInputDelay).Snapshot
			expect(snapshot.CurrentState).to.equal("Reverse")
		end)

		it("uses inclusive stop speed and exclusive input deadzone boundaries", function()
			expect(
				CartLongitudinalStateMachine.ResolveIntent(
					profile.LongitudinalInputDeadzone,
					profile.LongitudinalInputDeadzone
				)
			).to.equal("None")
			expect(
				CartLongitudinalStateMachine.ResolveIntent(
					profile.LongitudinalInputDeadzone + 0.001,
					profile.LongitudinalInputDeadzone
				)
			).to.equal("Forward")
			expect(
				CartLongitudinalStateMachine.ResolveIntent(
					-profile.LongitudinalInputDeadzone - 0.001,
					profile.LongitudinalInputDeadzone
				)
			).to.equal("Reverse")

			local stoppedAtThreshold = step(
				CartLongitudinalStateMachine.Create(0),
				-1,
				profile.NearZeroSpeedThreshold,
				1
			).Snapshot
			local movingAboveThreshold = step(
				CartLongitudinalStateMachine.Create(0),
				-1,
				profile.NearZeroSpeedThreshold + 0.001,
				1
			).Snapshot

			expect(stoppedAtThreshold.CurrentState).to.equal("Stopped")
			expect(movingAboveThreshold.CurrentState).to.equal("Braking")

			local stoppedAtNegativeThreshold = step(
				CartLongitudinalStateMachine.Create(0),
				-1,
				-profile.NearZeroSpeedThreshold,
				1
			).Snapshot
			local movingBelowNegativeThreshold = step(
				CartLongitudinalStateMachine.Create(0),
				-1,
				-profile.NearZeroSpeedThreshold - 0.001,
				1
			).Snapshot

			expect(stoppedAtNegativeThreshold.CurrentState).to.equal("Stopped")
			expect(movingBelowNegativeThreshold.CurrentState).to.equal("Coasting")
		end)

		it("settles naturally through Coasting, Stopped, and Idle", function()
			local snapshot = CartLongitudinalStateMachine.Create(0)

			snapshot = step(snapshot, 1, 0, 0.1).Snapshot
			snapshot = step(snapshot, 0, 8, 1).Snapshot
			expect(snapshot.CurrentState).to.equal("Coasting")

			snapshot = step(snapshot, 0, 0, 2).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")

			snapshot = step(snapshot, 0, 0, 2.1).Snapshot
			expect(snapshot.CurrentState).to.equal("Idle")
		end)

		it("classifies neutral external motion as Coasting instead of Idle", function()
			local result = step(CartLongitudinalStateMachine.Create(0), 0, 2, 1)

			expect(result.Snapshot.CurrentState).to.equal("Coasting")
		end)

		it("does not advance a pending transition with non-monotonic time", function()
			local snapshot = step(CartLongitudinalStateMachine.Create(0), -1, 0, 10).Snapshot

			snapshot = step(snapshot, -1, 0, 9).Snapshot
			expect(snapshot.CurrentState).to.equal("Stopped")
		end)

		it("preserves state metadata until a real transition occurs", function()
			local snapshot = CartLongitudinalStateMachine.Create(5)

			snapshot = step(snapshot, 1, 0, 6).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")
			expect(snapshot.PreviousState).to.equal("Idle")
			expect(snapshot.StateEnteredAt).to.equal(6)

			snapshot = step(snapshot, 1, 10, 9).Snapshot
			expect(snapshot.CurrentState).to.equal("Accelerating")
			expect(snapshot.PreviousState).to.equal("Idle")
			expect(snapshot.StateEnteredAt).to.equal(6)
		end)

		it("returns frozen snapshots without caching velocity", function()
			local snapshot = step(CartLongitudinalStateMachine.Create(0), -1, 0, 1).Snapshot

			expect(table.isfrozen(snapshot)).to.equal(true)
			expect(table.isfrozen(snapshot.CurrentTransition :: any)).to.equal(true)
			expect((snapshot :: any).ForwardSpeed).to.equal(nil)
			expect((snapshot :: any).Velocity).to.equal(nil)
		end)

		it("recovers malformed state or numeric input safely to Idle", function()
			local malformed = step({ CurrentState = "Teleporting" }, 1, 10, 1)
			local nonFinite = step(CartLongitudinalStateMachine.Create(0), 1, 0 / 0, 2)
			local infiniteThrottle = step(CartLongitudinalStateMachine.Create(0), math.huge, 0, 2)
			local infiniteTime = step(CartLongitudinalStateMachine.Create(0), 1, 0, -math.huge)

			expect(malformed.RecoveredFromInvalidState).to.equal(true)
			expect(malformed.StateChanged).to.equal(true)
			expect(malformed.Snapshot.CurrentState).to.equal("Idle")
			expect(nonFinite.RecoveredFromInvalidState).to.equal(true)
			expect(nonFinite.Snapshot.CurrentState).to.equal("Idle")
			expect(infiniteThrottle.RecoveredFromInvalidState).to.equal(true)
			expect(infiniteThrottle.Snapshot.CurrentState).to.equal("Idle")
			expect(infiniteTime.RecoveredFromInvalidState).to.equal(true)
			expect(infiniteTime.Snapshot.CurrentState).to.equal("Idle")
		end)

		it("is deterministic for equivalent snapshots and observations", function()
			local initial = CartLongitudinalStateMachine.Create(0)
			local first = step(initial, -1, 8, 1)
			local second = step(initial, -1, 8, 1)

			expect(first.Snapshot.CurrentState).to.equal(second.Snapshot.CurrentState)
			expect(first.Snapshot.PreviousState).to.equal(second.Snapshot.PreviousState)
			expect(first.Snapshot.StateEnteredAt).to.equal(second.Snapshot.StateEnteredAt)
			expect(first.RequestedState).to.equal(second.RequestedState)
		end)

		it("creates a fresh Idle lifecycle state", function()
			local reverseSnapshot = reachReverse(0)
			local resetSnapshot = CartLongitudinalStateMachine.Create(10)

			expect(reverseSnapshot.CurrentState).to.equal("Reverse")
			expect(resetSnapshot.CurrentState).to.equal("Idle")
			expect(resetSnapshot.PreviousState).to.equal("Idle")
			expect(resetSnapshot.CurrentTransition).to.equal(nil)
			expect(resetSnapshot.StateEnteredAt).to.equal(10)
		end)
	end)
end
