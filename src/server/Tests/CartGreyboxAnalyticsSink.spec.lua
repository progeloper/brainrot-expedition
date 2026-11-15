--!strict

return function()
	local CartGreyboxAnalyticsSink = require(script.Parent.Parent.Utility.CartGreyboxAnalyticsSink)

	describe("CartGreyboxAnalyticsSink", function()
		it("captures immutable copies through its bounded Development provider", function()
			CartGreyboxAnalyticsSink.Clear()

			local payload = {
				EventVersion = 1,
				RuntimeCartId = "runtime-cart-1",
			}
			local provider = CartGreyboxAnalyticsSink.GetProvider()

			provider:Emit("cart_spawned", payload)
			payload.RuntimeCartId = "mutated"

			local events = CartGreyboxAnalyticsSink.GetEvents()

			expect(#events).to.equal(1)
			expect(events[1].Name).to.equal("cart_spawned")
			expect(events[1].Payload.RuntimeCartId).to.equal("runtime-cart-1")
			expect(table.isfrozen(events[1])).to.equal(true)
			expect(table.isfrozen(events[1].Payload)).to.equal(true)
		end)

		it("bounds retained events and clears deterministically", function()
			CartGreyboxAnalyticsSink.Clear()

			local provider = CartGreyboxAnalyticsSink.GetProvider()
			local totalBefore = CartGreyboxAnalyticsSink.GetTotalEmittedCount()

			for index = 1, 300 do
				provider:Emit("test_event", { Sequence = index })
			end

			local events = CartGreyboxAnalyticsSink.GetEvents()

			expect(#events).to.equal(256)
			expect(events[1].Payload.Sequence).to.equal(45)
			expect(events[256].Payload.Sequence).to.equal(300)
			expect(CartGreyboxAnalyticsSink.GetTotalEmittedCount() - totalBefore).to.equal(300)

			CartGreyboxAnalyticsSink.Clear()
			expect(CartGreyboxAnalyticsSink.GetEventCount()).to.equal(0)
			expect(CartGreyboxAnalyticsSink.GetTrackedRuntimeCartCount()).to.equal(0)
			expect(CartGreyboxAnalyticsSink.GetTotalEmittedCount() - totalBefore).to.equal(300)
		end)

		it("attributes bounded event counts to their server runtime cart identity", function()
			CartGreyboxAnalyticsSink.Clear()

			local provider = CartGreyboxAnalyticsSink.GetProvider()

			provider:Emit("cart_spawned", { RuntimeCartId = "load-cart-1" })
			provider:Emit("cart_movement_corrected", { RuntimeCartId = "load-cart-1" })
			provider:Emit("cart_spawned", { RuntimeCartId = "unrelated-cart" })
			provider:Emit("session_started", {})

			expect(CartGreyboxAnalyticsSink.GetRuntimeCartEventCount("load-cart-1", "cart_spawned")).to.equal(
				1
			)
			expect(
				CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
					"load-cart-1",
					"cart_movement_corrected"
				)
			).to.equal(1)
			expect(
				CartGreyboxAnalyticsSink.GetRuntimeCartEventCount("load-cart-1", "cart_despawned")
			).to.equal(0)
			expect(CartGreyboxAnalyticsSink.GetTrackedRuntimeCartCount()).to.equal(2)
		end)

		it("bounds runtime-cart attribution state independently of retained events", function()
			CartGreyboxAnalyticsSink.Clear()

			local provider = CartGreyboxAnalyticsSink.GetProvider()

			for index = 1, 513 do
				provider:Emit("cart_spawned", {
					RuntimeCartId = string.format("runtime-cart-%d", index),
				})
			end

			expect(CartGreyboxAnalyticsSink.GetTrackedRuntimeCartCount()).to.equal(512)
			expect(
				CartGreyboxAnalyticsSink.GetRuntimeCartEventCount("runtime-cart-1", "cart_spawned")
			).to.equal(0)
			expect(
				CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
					"runtime-cart-513",
					"cart_spawned"
				)
			).to.equal(1)
		end)
	end)
end
