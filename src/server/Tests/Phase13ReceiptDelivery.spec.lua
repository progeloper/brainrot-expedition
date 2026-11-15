return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.Phase13CommerceRules)
	local Service = require(script.Parent.Parent.Services.Phase13CommerceService)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local function run(callback)
		local player = { UserId = 831313 }
		local f = {
			data = Schema.CreateDefault(),
			revision = 0,
			saved = 0,
			available = true,
			mutations = 0,
			telemetry = {},
		}
		Rules.Migrate(f.data)
		local profile = {}
		function profile:GetReadableData()
			return if f.available then f.data else nil
		end
		function profile:GetSaveEnvelope(_, snapshot, revision)
			return {
				Transport = { Version = 3, OwnerToken = "fixture", LastRevision = revision, LeaseExpiresAt = 1180 },
				Data = snapshot,
			}
		end
		function profile:IsWritable()
			return f.available
		end
		function profile:GetCurrentRevision()
			return f.revision
		end
		function profile:IsRevisionConfirmed(_, revision)
			return f.saved >= revision
		end
		local transactions = {}
		function transactions:IsBusy()
			return f.revision > f.saved
		end
		function transactions:SubscribeConfirmed(listener)
			f.confirmed = listener
			return {
				Disconnect = function()
					f.confirmed = nil
				end,
			}
		end
		function f.confirm()
			f.saved = f.revision
			if f.pending and f.confirmed then
				local response = f.pending
				f.pending = nil
				f.confirmed(player, response)
			end
		end
		function transactions:CommitCritical(_, operationId, kind, mutator)
			if f.revision > f.saved then
				return { ok = false, code = "BUSY" }
			end
			local ok, result = mutator(f.data, 1000)
			if ok then
				f.revision += 1
				f.mutations += 1
				f.pending = { state = "Confirmed", operationId = operationId, kind = kind, result = result }
			end
			return { ok = ok, state = if ok then "Saving" else "Rejected", result = result }
		end
		-- These synthetic IDs exist only in this injected fixture. No Marketplace API is called.
		local products = {
			{ id = "FIXTURE_POUCH", platformId = 1, verifiedUniverseId = 999, amount = 500000000 },
			{ id = "FIXTURE_CRATE", platformId = 2, verifiedUniverseId = 999, amount = 2000000000 },
			{ id = "FIXTURE_VAULT", platformId = 3, verifiedUniverseId = 999, amount = 10000000000 },
		}
		Service:_ConfigureForTests({
			Profile = profile,
			Marketplace = {
				GetProductInfoAsync = function(_, id)
					return { ProductId = id, PriceInRobux = 10, IsForSale = true }
				end,
				PromptProductPurchase = function() end,
			},
			Telemetry = {
				Record = function(_, _, name, value, fields)
					table.insert(f.telemetry, { kind = "Custom", name = name, value = value, fields = fields })
				end,
				Funnel = function(_, _, name, step, id)
					table.insert(f.telemetry, { kind = "Funnel", name = name, step = step, id = id })
				end,
			},
			Transactions = transactions,
			UniverseId = 999,
			ResolvePlayer = function(id)
				return if id == player.UserId then player else nil
			end,
			Catalogue = {
				UniverseId = 999,
				Version = "FIXTURE",
				ProductionDeliveryEnabled = true,
				PaidCapacityRecoveryReady = true,
				PriceCacheSeconds = 300,
				Passes = {},
				Products = products,
			},
		})
		local ok, why = xpcall(function()
			callback(f, player)
		end, debug.traceback)
		Service:_ResetFixture()
		assert(ok, why)
	end
	describe("Receipt dispatcher covering-save delivery", function()
		it("validates offer views and records them once per bounded section window", function()
			run(function(f, p)
				expect(Service:ObserveOffers(p, "INJECTED").ok).to.equal(false)
				expect(#f.telemetry).to.equal(0)
				expect(Service:ObserveOffers(p, "Cash").ok).to.equal(true)
				expect(#f.telemetry).to.equal(2)
				expect(f.telemetry[1].fields.result).to.equal("Untrusted")
				expect(f.telemetry[2].step).to.equal(1)
				Service:ObserveOffers(p, "Cash")
				expect(#f.telemetry).to.equal(2)
				f.available = false
				expect(Service:ObserveOffers(p, "Passes").ok).to.equal(false)
				expect(#f.telemetry).to.equal(2)
			end)
		end)
		it(
			"attributes only a newly confirmed matching offer while old receipts and wrong offers cannot complete the current funnel",
			function()
				run(function(f, p)
					Service:RefreshPrices()
					Service:ObserveOffers(p, "Cash")
					expect(Service:Prompt(p, "FIXTURE_POUCH").ok).to.equal(true)
					local function completions()
						local count = 0
						for _, event in f.telemetry do
							if event.kind == "Funnel" and event.name == "Commerce" and event.step == 3 then
								count += 1
							end
						end
						return count
					end
					Rules.GrantReceipt(f.data, "old-saved", 1, 500000000, 900, "FIXTURE")
					f.data.Commerce.ProcessedReceipts["old-saved"].CommitRevision = 0
					expect(Service:ProcessReceipt({ PlayerId = p.UserId, ProductId = 1, PurchaseId = "old-saved" })).to.equal(
						Enum.ProductPurchaseDecision.PurchaseGranted
					)
					expect(completions()).to.equal(0)
					local wrong = { PlayerId = p.UserId, ProductId = 2, PurchaseId = "new-wrong-offer" }
					expect(Service:ProcessReceipt(wrong)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					f.confirm()
					expect(completions()).to.equal(0)
					expect(Service:ProcessReceipt(wrong)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					local matching = { PlayerId = p.UserId, ProductId = 1, PurchaseId = "new-matching-offer" }
					expect(Service:ProcessReceipt(matching)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expect(completions()).to.equal(0)
					f.confirm()
					expect(completions()).to.equal(1)
					for _ = 1, 3 do
						expect(Service:ProcessReceipt(matching)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					end
					expect(completions()).to.equal(1)
					expect(f.mutations).to.equal(2)
					expect(f.data.Economy.Balance).to.equal(3000000000)
				end)
			end
		)
		it("postpones all three grants until their exact permanent receipt is durable", function()
			run(function(f, p)
				local expected = 0
				for id, amount in { 500000000, 2000000000, 10000000000 } do
					local receipt = { PlayerId = p.UserId, ProductId = id, PurchaseId = "fixture-paid-" .. id }
					expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expected += amount
					expect(f.data.Economy.Balance).to.equal(expected)
					expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expect(f.mutations).to.equal(id)
					f.saved = f.revision
					expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					expect(f.data.Economy.Balance).to.equal(expected)
				end
			end)
		end)
		it("defers unknown products, offline identities and unavailable profiles without mutation", function()
			run(function(f, p)
				expect(Service:ProcessReceipt({ PlayerId = p.UserId, ProductId = 99, PurchaseId = "unknown" })).to.equal(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(Service:ProcessReceipt({ PlayerId = 0, ProductId = 1, PurchaseId = "offline" })).to.equal(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				f.available = false
				expect(Service:ProcessReceipt({ PlayerId = p.UserId, ProductId = 1, PurchaseId = "unready" })).to.equal(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(f.mutations).to.equal(0)
				expect(f.data.Economy.Balance).to.equal(0)
			end)
		end)
		it("a saved ledger replay succeeds after transaction journal loss without another credit", function()
			run(function(f, p)
				local r = { PlayerId = p.UserId, ProductId = 1, PurchaseId = "rejoin" }
				Service:ProcessReceipt(r)
				f.saved = f.revision
				expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
				expect(f.mutations).to.equal(1)
				expect(f.data.Economy.Balance).to.equal(500000000)
			end)
		end)
	end)
end
