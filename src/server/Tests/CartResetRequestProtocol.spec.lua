--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartResetRequestProtocol =
		require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)

	describe("CartResetRequestProtocol", function()
		it("creates frozen approved and rejected results", function()
			local approved = CartResetRequestProtocol.CreateResult(
				true,
				CartResetRequestProtocol.ReasonCodes.Approved,
				0,
				100,
				true
			)
			local rejected = CartResetRequestProtocol.CreateResult(
				false,
				CartResetRequestProtocol.ReasonCodes.CooldownActive,
				18.4,
				101,
				true
			)

			expect(CartResetRequestProtocol.IsResult(approved)).to.equal(true)
			expect(CartResetRequestProtocol.IsResult(rejected)).to.equal(true)
			expect(table.isfrozen(approved)).to.equal(true)
			expect(table.isfrozen(rejected)).to.equal(true)
			expect(rejected.RetryAfterSeconds).to.equal(18.4)
		end)

		it("exposes only stable recognised reason codes", function()
			local reasonCount = 0

			for _, reason in CartResetRequestProtocol.ReasonCodes do
				reasonCount += 1
				expect(CartResetRequestProtocol.IsReasonCode(reason)).to.equal(true)
			end

			expect(reasonCount).to.equal(10)
			expect(CartResetRequestProtocol.ReasonCodes.Approved).to.equal("Approved")
			expect(CartResetRequestProtocol.ReasonCodes.RateLimited).to.equal("RateLimited")
			expect(CartResetRequestProtocol.ReasonCodes.NoActiveCart).to.equal("NoActiveCart")
			expect(CartResetRequestProtocol.ReasonCodes.CartUnavailable).to.equal("CartUnavailable")
			expect(CartResetRequestProtocol.ReasonCodes.NotDriver).to.equal("NotDriver")
			expect(CartResetRequestProtocol.ReasonCodes.ResetAlreadyActive).to.equal(
				"ResetAlreadyActive"
			)
			expect(CartResetRequestProtocol.ReasonCodes.CooldownActive).to.equal("CooldownActive")
			expect(CartResetRequestProtocol.ReasonCodes.InvalidRequest).to.equal("InvalidRequest")
			expect(CartResetRequestProtocol.ReasonCodes.ResetUnavailable).to.equal(
				"ResetUnavailable"
			)
			expect(CartResetRequestProtocol.ReasonCodes.InternalFailure).to.equal("InternalFailure")
			expect(CartResetRequestProtocol.IsReasonCode("TetherActive")).to.equal(false)
			expect(CartResetRequestProtocol.IsReasonCode(nil)).to.equal(false)
			expect(table.isfrozen(CartResetRequestProtocol.ReasonCodes)).to.equal(true)
		end)

		it("rejects approval mismatches and unsafe numeric fields", function()
			expect(function()
				CartResetRequestProtocol.CreateResult(
					true,
					CartResetRequestProtocol.ReasonCodes.NotDriver,
					0,
					0,
					true
				)
			end).to.throw()
			expect(function()
				CartResetRequestProtocol.CreateResult(
					false,
					CartResetRequestProtocol.ReasonCodes.RateLimited,
					0 / 0,
					0,
					true
				)
			end).to.throw()
			expect(function()
				CartResetRequestProtocol.CreateResult(
					false,
					CartResetRequestProtocol.ReasonCodes.RateLimited,
					0,
					math.huge,
					true
				)
			end).to.throw()
		end)

		it("rejects malformed response tables", function()
			expect(CartResetRequestProtocol.IsResult(nil)).to.equal(false)
			expect(CartResetRequestProtocol.IsResult({})).to.equal(false)
			expect(CartResetRequestProtocol.IsResult({
				Approved = false,
				Reason = "CooldownActive",
				RetryAfterSeconds = math.huge,
				ServerTimestamp = 1,
				SafeToResume = true,
			})).to.equal(false)
			expect(CartResetRequestProtocol.IsResult({
				Approved = true,
				Reason = "NotDriver",
				RetryAfterSeconds = 0,
				ServerTimestamp = 1,
				SafeToResume = true,
			})).to.equal(false)
		end)
	end)
end
