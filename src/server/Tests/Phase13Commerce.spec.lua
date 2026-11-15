return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.Phase13CommerceRules)
	local Money = require(RS.Shared.Utility.CurrencyDenomination)
	local Capacity = require(RS.Shared.Utility.Phase13CommerceCapacity)
	local function profile()
		local data = { Economy = { Balance = 123 }, Phase13 = { EligibilityRevision = 0 } }
		Rules.Migrate(data)
		return data
	end
	describe("Client-local displayed prices", function()
		it("uses the fetched personalized price rather than the server reference price", function()
			expect(
				Rules.DisplayPrice(
					{ enabled = true, platformId = 123, platformKind = "Product", price = 49 },
					{ ProductId = 123, PriceInRobux = 31 }
				)
			).to.equal(31)
			expect(
				Rules.DisplayPrice(
					{ enabled = true, platformId = 456, platformKind = "GamePass" },
					{ AssetId = 456, PriceInRobux = 79, IsForSale = true }
				)
			).to.equal(79)
		end)
		it("rejects mismatched identity, disabled or unavailable offers without guessing", function()
			local offer = { enabled = true, platformId = 123, platformKind = "Product" }
			expect(Rules.DisplayPrice(offer, { ProductId = 124, PriceInRobux = 31 })).to.equal(nil)
			expect(Rules.DisplayPrice(offer, { ProductId = 123, PriceInRobux = 31, IsForSale = false })).to.equal(nil)
			offer.enabled = false
			expect(Rules.DisplayPrice(offer, { ProductId = 123, PriceInRobux = 31 })).to.equal(nil)
		end)
		it("rejects missing, nonfinite, fractional and negative price values", function()
			local offer = { enabled = true, platformId = 123, platformKind = "Product" }
			expect(Rules.DisplayPrice(offer, { ProductId = 123 })).to.equal(nil)
			for _, price in { 0 / 0, math.huge, -1, 1.5 } do
				expect(Rules.DisplayPrice(offer, { ProductId = 123, PriceInRobux = price })).to.equal(nil)
			end
		end)
	end)
	describe("Permanent paid ledger and entitlements", function()
		it("measures the complete encoded envelope instead of estimating receipt string length", function()
			local data = profile()
			data.UnrelatedPadding = string.rep("x", Capacity.EntryLimitBytes)
			local result = Capacity.MeasureEnvelope({ Transport = { Version = 3 }, Data = data })
			expect(result.ok).to.equal(false)
			expect(result.code).to.equal("PROFILE_STORAGE_HEADROOM")
			expect(data.Commerce.ReceiptCount).to.equal(0)
			expect(data.Economy.Balance).to.equal(123)
		end)
		it("grants each fixed pack once and conserves balance on delivery replay", function()
			local data = profile()
			local total = 123
			for i, amount in { 500000000, 2000000000, 10000000000 } do
				local id = "fixture-" .. i
				expect(Rules.GrantReceipt(data, id, 100 + i, amount, 1000, "FIXTURE")).to.equal(true)
				total += amount
				expect(data.Economy.Balance).to.equal(total)
				expect(Rules.GrantReceipt(data, id, 100 + i, amount, 1001, "FIXTURE")).to.equal(false)
				expect(data.Economy.Balance).to.equal(total)
			end
			expect(data.Commerce.ReceiptCount).to.equal(3)
			expect(Rules.Validate(data)).to.equal(true)
		end)
		it("retains original reward when a receipt is delivered with another offer", function()
			local data = profile()
			Rules.GrantReceipt(data, "same", 1, 500000000, 1000, "V1")
			local prior = data.Economy.Balance
			expect(Rules.GrantReceipt(data, "same", 2, 10000000000, 1001, "V2")).to.equal(false)
			expect(data.Economy.Balance).to.equal(prior)
			expect(data.Commerce.ProcessedReceipts.same.Amount).to.equal(500000000)
		end)
		it("claims the starter cash once across migration and a cash sacrifice", function()
			local data = profile()
			expect(Rules.GrantPass(data, "STARTER_PACK", 1000)).to.equal(true)
			expect(data.Economy.Balance).to.equal(3000000123)
			data.Economy.Balance = 0
			Rules.Migrate(data)
			Rules.GrantPass(data, "STARTER_PACK", 1001)
			expect(data.Economy.Balance).to.equal(0)
			expect(Rules.HasEntitlement(data, "STARTER_PACK")).to.equal(true)
		end)
		it("does not multiply paid cash by the income pass or VIP", function()
			local data = profile()
			Rules.GrantPass(data, "INCOME_2X", 1000)
			Rules.GrantPass(data, "VIP", 1000)
			-- P15 income: (1 + 0.15 VIP) x 2 pass; the paid cash below stays unmultiplied.
			expect(math.abs(Rules.ProductionMultiplier(data) - 2.3) < 1e-9).to.equal(true)
			Rules.GrantReceipt(data, "pouch", 1, 500000000, 1000, "V1")
			expect(data.Economy.Balance).to.equal(500000123)
		end)
		it("rejects overflow before setting a starter claim or receipt", function()
			local data = profile()
			data.Economy.Balance = Money.MAX_AMOUNT
			expect(Rules.GrantPass(data, "STARTER_PACK", 1000)).to.equal(false)
			expect(data.Commerce.StarterPackClaimed).to.equal(false)
			expect(data.Commerce.Entitlements.STARTER_PACK).to.equal(false)
			expect(Rules.GrantReceipt(data, "overflow", 1, 500000000, 1000, "V1")).to.equal(false)
			expect(data.Commerce.ReceiptCount).to.equal(0)
		end)
		it("rejects future schemas and non-finite receipt time", function()
			local data = profile()
			data.Commerce.Version = 2
			expect(Rules.Migrate(data)).to.equal(false)
			data = profile()
			expect(Rules.GrantReceipt(data, "badtime", 1, 500000000, 0 / 0, "V1")).to.equal(false)
			expect(data.Commerce.ReceiptCount).to.equal(0)
		end)
	end)
end
