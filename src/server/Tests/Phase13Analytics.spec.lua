return function()
	local Adapter = require(script.Parent.Parent.Services.Phase13AnalyticsService)
	describe("Failure-isolated bounded analytics", function()
		it("rejects unregistered names, result values and arbitrary categories", function()
			Adapter:_ResetForTests()
			local p = {}
			expect(Adapter:Record(p, "UnboundedArbitraryName", 1, {})).to.equal(false)
			expect(Adapter:Record(p, "PurchaseOutcome", 1, { result = "user typed text" })).to.equal(false)
			expect(Adapter:Record(p, "PurchaseOutcome", 1, { category = "profile JSON" })).to.equal(false)
			expect(Adapter:Record(p, "PurchaseOutcome", 0 / 0, {})).to.equal(false)
		end)
		it("bounds burst and queued events without changing the caller", function()
			Adapter:_ResetForTests()
			local p = {}
			local accepted = 0
			for _ = 1, 200 do
				if Adapter:Record(p, "HuntOutcome", 1, { category = "Hunt", result = "Success" }) then
					accepted += 1
				end
			end
			expect(accepted).to.equal(120)
			for _ = 1, 200 do
				Adapter:Step(0)
			end
			expect(#Adapter:GetRecorder()).to.equal(120)
		end)
		it("does not infer skipped hunt steps or merge Hunt and Theft", function()
			Adapter:_ResetForTests()
			local p = {}
			expect(Adapter:Funnel(p, "HuntBranch", 3)).to.equal(false)
			expect(Adapter:Funnel(p, "TheftBranch", 1)).to.equal(true)
			expect(Adapter:Funnel(p, "HuntBranch", 2)).to.equal(false)
			expect(Adapter:Funnel(p, "EarlyJourney", 1)).to.equal(true)
			expect(Adapter:Funnel(p, "EarlyJourney", 2)).to.equal(true)
			expect(Adapter:Funnel(p, "EarlyJourney", 2)).to.equal(false)
		end)
		it("records each durable swap or opt-out once after Saving and ignores confirmation replay", function()
			for _, definition in
				{
					{ kind = "PlatformSwap", name = "SwapOutcome", category = "Swap" },
					{ kind = "ProtectionOptOut", name = "ProtectionOptOut", category = "Theft" },
				}
			do
				Adapter:_ResetForTests()
				local p = {}
				local response = { state = "Saving", operationId = "fixture-confirmed", result = { saleCash = 25 } }
				expect(Adapter:Receipt(p, definition.kind, response)).to.equal(false)
				response.state = "Confirmed"
				expect(Adapter:Receipt(p, definition.kind, response)).to.equal(true)
				for _ = 1, 3 do
					expect(Adapter:Receipt(p, definition.kind, response)).to.equal(false)
				end
				Adapter:Step(0)
				local events = Adapter:GetRecorder()
				expect(#events).to.equal(1)
				expect(events[1].name).to.equal(definition.name)
				expect(events[1].value).to.equal(1)
				expect(events[1].fields.CustomField02).to.equal(definition.category)
				expect(events[1].fields.CustomField03).to.equal("Success")
			end
			Adapter:_ResetForTests()
		end)
		it("contains a throwing sink and only records critical operations once", function()
			Adapter:_ResetForTests(function()
				error("synthetic telemetry outage")
			end)
			local p = {}
			local response =
				{ state = "Confirmed", operationId = "fixture", result = { category = "Cart", price = 100 } }
			expect(Adapter:Receipt(p, "CataloguePurchase", response)).to.equal(true)
			expect(Adapter:Receipt(p, "CataloguePurchase", response)).to.equal(false)
			expect(function()
				Adapter:Step(0)
			end).never.to.throw()
			Adapter:_ResetForTests()
		end)
	end)
end
