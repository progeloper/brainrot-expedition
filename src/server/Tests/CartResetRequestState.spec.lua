--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartResetRequestProtocol =
		require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)
	local CartResetRequestState = require(script.Parent.Parent.Utility.CartResetRequestState)

	local function createStore(): CartResetRequestState.Store
		return CartResetRequestState.new({
			RequestAttemptInterval = 5,
			SuccessfulResetCooldown = 30,
			SuspiciousRejectionThreshold = 3,
			SuspiciousRejectionWindow = 30,
		})
	end

	describe("CartResetRequestState", function()
		it("reports bounded runtime security-record ownership", function()
			local store = createStore()

			expect(store:GetRecordCount()).to.equal(0)
			store:RecordAttempt(1001, 0, 0)
			store:RecordAttempt(1002, 0, 0)
			expect(store:GetRecordCount()).to.equal(2)
			store:RemoveUser(1001)
			expect(store:GetRecordCount()).to.equal(1)
			store:Clear()
			expect(store:GetRecordCount()).to.equal(0)
		end)

		it("uses a sliding five-second attempt limit for every arrival", function()
			local store = createStore()
			local firstAllowed = store:RecordAttempt(10, 100, 0)
			local secondAllowed, secondReason, secondRetry = store:RecordAttempt(10, 101, 0)
			local thirdAllowed, thirdReason, thirdRetry = store:RecordAttempt(10, 105, 0)
			local fourthAllowed = store:RecordAttempt(10, 110, 0)

			expect(firstAllowed).to.equal(true)
			expect(secondAllowed).to.equal(false)
			expect(secondReason).to.equal(CartResetRequestProtocol.ReasonCodes.RateLimited)
			expect(secondRetry).to.equal(4)
			expect(thirdAllowed).to.equal(false)
			expect(thirdReason).to.equal(CartResetRequestProtocol.ReasonCodes.RateLimited)
			expect(thirdRetry).to.equal(1)
			expect(fourthAllowed).to.equal(true)
		end)

		it("counts malformed attempts without allowing authority-bearing payloads", function()
			local store = createStore()
			local malformedAllowed, malformedReason = store:RecordAttempt(20, 0, 1)
			local repeatedAllowed, repeatedReason = store:RecordAttempt(20, 1, 2)
			local validAllowed, validReason = store:RecordAttempt(20, 5, 0)
			local validAfterWindow = store:RecordAttempt(20, 10, 0)

			expect(malformedAllowed).to.equal(false)
			expect(malformedReason).to.equal(CartResetRequestProtocol.ReasonCodes.InvalidRequest)
			expect(repeatedAllowed).to.equal(false)
			expect(repeatedReason).to.equal(CartResetRequestProtocol.ReasonCodes.InvalidRequest)
			expect(validAllowed).to.equal(false)
			expect(validReason).to.equal(CartResetRequestProtocol.ReasonCodes.RateLimited)
			expect(validAfterWindow).to.equal(true)
		end)

		it("treats every explicit remote argument as an invalid payload", function()
			local store = createStore()
			local instance = Instance.new("Model")
			local nextUserId = 100

			local function expectInvalid(...: any)
				nextUserId += 1

				local allowed, reason = store:RecordAttempt(nextUserId, 0, select("#", ...))

				expect(allowed).to.equal(false)
				expect(reason).to.equal(CartResetRequestProtocol.ReasonCodes.InvalidRequest)
			end

			expectInvalid(nil)
			expectInvalid(CFrame.new())
			expectInvalid(Vector3.zero)
			expectInvalid(instance)
			expectInvalid({ Destination = CFrame.new() })
			expectInvalid("CRT_001", 123)

			instance:Destroy()
		end)

		it("isolates rate limits by UserId and removes them on cleanup", function()
			local store = createStore()

			expect(store:RecordAttempt(30, 0, 0)).to.equal(true)
			expect(store:RecordAttempt(30, 1, 0)).to.equal(false)
			expect(store:RecordAttempt(31, 1, 0)).to.equal(true)
			expect(store:RemoveUser(30)).to.equal(true)
			expect(store:RecordAttempt(30, 1, 0)).to.equal(true)
			expect(store:RemoveUser(999)).to.equal(false)
		end)

		it("serialises processing and commits cooldown only on success", function()
			local store = createStore()
			local firstLease = store:TryAcquire(40, 5)
			local duplicateLease, duplicateReason = store:TryAcquire(40, 5)

			expect(firstLease == nil).to.equal(false)
			expect(duplicateLease).to.equal(nil)
			expect(duplicateReason).to.equal(
				CartResetRequestProtocol.ReasonCodes.ResetAlreadyActive
			)
			expect(store:Finish(firstLease :: CartResetRequestState.Lease, 6, true)).to.equal(true)
			expect(store:GetCooldownRemaining(40, 6)).to.equal(30)

			local cooldownLease, cooldownReason, cooldownRetry = store:TryAcquire(40, 35.5)

			expect(cooldownLease).to.equal(nil)
			expect(cooldownReason).to.equal(CartResetRequestProtocol.ReasonCodes.CooldownActive)
			expect(cooldownRetry).to.equal(0.5)
			expect(store:TryAcquire(40, 36) == nil).to.equal(false)
		end)

		it("does not consume cooldown for a rejected or failed reset", function()
			local store = createStore()
			local failedLease = store:TryAcquire(50, 0)

			expect(store:Finish(failedLease :: CartResetRequestState.Lease, 1, false)).to.equal(
				true
			)
			expect(store:GetCooldownRemaining(50, 1)).to.equal(0)

			local retryLease = store:TryAcquire(50, 1)

			expect(retryLease == nil).to.equal(false)
		end)

		it("rejects stale completions after Player-removal state is replaced", function()
			local store = createStore()
			local oldLease = store:TryAcquire(60, 0)

			store:RemoveUser(60)

			local newLease = store:TryAcquire(60, 1)

			expect(store:Finish(oldLease :: CartResetRequestState.Lease, 2, true)).to.equal(false)
			expect(store:RemoveLeaseState(oldLease :: CartResetRequestState.Lease)).to.equal(false)
			expect((store:GetSnapshot(60) :: CartResetRequestState.Snapshot).Processing).to.equal(
				true
			)
			expect(store:Finish(newLease :: CartResetRequestState.Lease, 2, false)).to.equal(true)
			expect(store:RemoveLeaseState(newLease :: CartResetRequestState.Lease)).to.equal(true)
			expect(store:GetSnapshot(60)).to.equal(nil)
		end)

		it("bounds repeated-rejection diagnostics to one warning per window", function()
			local store = createStore()
			local reason = CartResetRequestProtocol.ReasonCodes.NotDriver

			store:RecordAttempt(70, 0, 0)

			local firstCount, firstLog = store:RecordRejection(70, reason, 0)
			local secondCount, secondLog = store:RecordRejection(70, reason, 1)
			local thirdCount, thirdLog = store:RecordRejection(70, reason, 2)
			local cappedCount, cappedLog = store:RecordRejection(70, reason, 3)
			local resetCount, resetLog = store:RecordRejection(70, reason, 30)

			expect(firstCount).to.equal(1)
			expect(firstLog).to.equal(false)
			expect(secondCount).to.equal(2)
			expect(secondLog).to.equal(false)
			expect(thirdCount).to.equal(3)
			expect(thirdLog).to.equal(true)
			expect(cappedCount).to.equal(3)
			expect(cappedLog).to.equal(false)
			expect(resetCount).to.equal(1)
			expect(resetLog).to.equal(false)
		end)

		it("does not recreate state when a stale rejection follows cleanup", function()
			local store = createStore()
			local reason = CartResetRequestProtocol.ReasonCodes.CartUnavailable

			store:RecordAttempt(75, 0, 0)
			local lease = store:TryAcquire(75, 0)

			store:RemoveUser(75)

			expect(store:Finish(lease :: CartResetRequestState.Lease, 1, false)).to.equal(false)

			local count, shouldLog = store:RecordRejection(75, reason, 1)

			expect(count).to.equal(0)
			expect(shouldLog).to.equal(false)
			expect(store:GetSnapshot(75)).to.equal(nil)
		end)

		it("returns immutable diagnostic snapshots and clears all state", function()
			local store = createStore()

			store:RecordAttempt(80, 10, 0)
			store:RecordRejection(80, CartResetRequestProtocol.ReasonCodes.NoActiveCart, 10)

			local snapshot = store:GetSnapshot(80)

			expect(snapshot == nil).to.equal(false)
			expect(table.isfrozen(snapshot :: CartResetRequestState.Snapshot)).to.equal(true)
			expect(table.isfrozen((snapshot :: CartResetRequestState.Snapshot).RejectionCounts)).to.equal(
				true
			)

			store:Clear()
			expect(store:GetSnapshot(80)).to.equal(nil)
		end)

		it("rejects unsafe limiter configuration", function()
			expect(function()
				CartResetRequestState.new({
					RequestAttemptInterval = 0,
					SuccessfulResetCooldown = 30,
					SuspiciousRejectionThreshold = 3,
					SuspiciousRejectionWindow = 30,
				})
			end).to.throw()
			expect(function()
				CartResetRequestState.new({
					RequestAttemptInterval = 5,
					SuccessfulResetCooldown = 0 / 0,
					SuspiciousRejectionThreshold = 3,
					SuspiciousRejectionWindow = 30,
				})
			end).to.throw()
		end)
	end)
end
