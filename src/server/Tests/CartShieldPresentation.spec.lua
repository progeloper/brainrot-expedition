--!strict

return function()
	local Shared = game:GetService("ReplicatedStorage").Shared
	local Presentation = require(Shared.Utility.CartShieldPresentation)
	local BurstLayout = require(Shared.Utility.CartBurstHudLayout)
	local function state(capacity: number, remaining: number, expires: number, revision: number?): any
		return { capacity = capacity, remaining = remaining, protectedUntil = expires, revision = revision or 1, lifecycleId = "fixture-life", cartGeneration = 7 }
	end
	describe("Shield state and HUD presentation", function()
		it("hides the ordinary no-provider HUD and never treats spare charges as an active window", function()
			expect(Presentation.View(state(0, 0, 0), 10).visible).to.equal(false)
			local full = Presentation.View(state(3, 3, 0), 10)
			expect(full.visible).to.equal(true)
			expect(full.active).to.equal(false)
			expect(full.title).to.equal("Shield 3/3")
		end)
		it("keeps depleted 0/N and final-charge protection visible through its original deadline", function()
			local value = state(2, 0, 15)
			local active = Presentation.View(value, 14.9)
			expect(active.title).to.equal("Shield 0/2")
			expect(active.active).to.equal(true)
			expect(string.find(active.status, "0.1 s", 1, true) ~= nil).to.equal(true)
			local depleted = Presentation.View(value, 15)
			expect(depleted.visible).to.equal(true)
			expect(depleted.active).to.equal(false)
		end)
		it("an earned window remains visible with zero capacity, then hides at exact expiry", function()
			local value = state(0, 0, 20)
			expect(Presentation.View(value, 19.999).visible).to.equal(true)
			expect(Presentation.View(value, 20).visible).to.equal(false)
		end)
		it("rejects stale revisions and wrong cart generations without losing a newer window", function()
			local current = state(2, 0, 20, 4)
			expect(Presentation.Accept(current, state(2, 1, 15, 3), 7)).to.equal(false)
			expect(Presentation.Accept(current, state(2, 0, 20, 4), 8)).to.equal(false)
			expect(Presentation.Accept(current, state(2, 0, 20, 4), 7)).to.equal(true)
		end)
		it("older menu callbacks preserve newer remaining charges for the same lifecycle and cart", function()
			local current, old = state(3, 1, 20, 4), state(3, 3, 0, 2)
			expect(Presentation.PreserveNewerReserve(current, old, true)).to.equal(current)
			old.lifecycleId = "new-fixture-life"
			expect(Presentation.PreserveNewerReserve(current, old, true)).to.equal(old)
			expect(Presentation.PreserveNewerReserve(current, old, false)).to.equal(old)
		end)
		it("a stale expiry identity cannot clear a later window or rebuilt cart", function()
			local old, current = state(2, 1, 15), state(2, 0, 20, 2)
			expect(Presentation.SameWindow(old, current)).to.equal(false)
			current.protectedUntil = 15 current.revision = 3
			expect(Presentation.SameWindow(old, current)).to.equal(true)
			current.lifecycleId = "new-fixture-life"
			expect(Presentation.SameWindow(old, current)).to.equal(false)
			current.lifecycleId = old.lifecycleId current.cartGeneration = 8
			expect(Presentation.SameWindow(old, current)).to.equal(false)
		end)
		it("coherent disable clears old protection feedback while a stale callback cannot clear newer feedback", function()
			local identity = { cartGeneration = 7, lifecycleId = "fixture-life", revision = 4 }
			local old, disabled = state(0, 0, 0, 3), state(0, 0, 0, 5)
			expect(Presentation.ShouldClearFeedback(old, identity, old, 10)).to.equal(false)
			expect(Presentation.ShouldClearFeedback(disabled, identity, disabled, 10)).to.equal(true)
			expect(Presentation.ShouldClearFeedback(nil, identity, disabled, 10)).to.equal(true)
			local protected = state(0, 0, 15, 5)
			expect(Presentation.ShouldClearFeedback(protected, identity, protected, 10)).to.equal(false)
			disabled.lifecycleId = "older-lifecycle"
			expect(Presentation.ShouldClearFeedback(disabled, identity, disabled, 10)).to.equal(false)
		end)
		it("reads only coherent current-cart integer reserves", function()
			local cart = Instance.new("Model")
			cart:SetAttribute("CartGeneration", 7) cart:SetAttribute("ShieldCartGeneration", 7)
			cart:SetAttribute("ShieldCapacity", 3) cart:SetAttribute("ShieldRemaining", 1)
			cart:SetAttribute("ShieldProtectionExpiresAt", 15) cart:SetAttribute("ShieldRevision", 4)
			cart:SetAttribute("ShieldLifecycleId", "fixture-life")
			expect(Presentation.Read(cart).remaining).to.equal(1)
			cart:SetAttribute("ShieldCartGeneration", 6)
			expect(Presentation.Read(cart)).to.equal(nil)
			cart:SetAttribute("ShieldCartGeneration", 7) cart:SetAttribute("ShieldRemaining", 1.5)
			expect(Presentation.Read(cart)).to.equal(nil)
			cart:Destroy()
		end)
		it("fits common safe areas without covering the established Cargo Burst or Reset rectangles", function()
			for _, size in { Vector2.new(320, 568), Vector2.new(390, 760), Vector2.new(568, 250), Vector2.new(844, 310), Vector2.new(1024, 700) } do
				local layout = Presentation.Layout(size)
				local x, y, w, h = layout.Position.X.Offset, layout.Position.Y.Offset, layout.Size.X.Offset, layout.Size.Y.Offset
				expect(x >= 0 and y >= 56 and x + w <= size.X and y + h <= size.Y).to.equal(true)
				local burst = BurstLayout.Resolve(size)
				local bx, by = size.X + burst.Position.X.Offset - burst.Size.X.Offset, burst.Position.Y.Offset
				local overlap = x < bx + burst.Size.X.Offset and x + w > bx and y < by + burst.Size.Y.Offset and y + h > by
				expect(overlap).to.equal(false)
				expect(x + w <= size.X - 116 or y + h <= size.Y - 206 or y >= size.Y - 150).to.equal(true)
			end
		end)
	end)
end
