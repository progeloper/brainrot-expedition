--!nocheck
return function()
	local Players = game:GetService("Players")
	local Catalog = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotCatalog)
	local Sale = require(script.Parent.Parent.Systems.BrainrotSaleSystem)

	local nextUserId = -51000
	local function fixture(callback)
		Sale:Stop()
		nextUserId -= 1
		local owned = {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local salePoint = own(Instance.new("Part"))
		salePoint.Name = "Phase5FSalePoint"
		salePoint.Anchored = true
		salePoint.Size = Vector3.new(10, 1, 10)
		salePoint.CFrame = CFrame.new(15000, 100, 15000)
		salePoint.Parent = workspace
		local character = own(Instance.new("Model"))
		character.Name = "Phase5FCharacter"
		character.Parent = workspace
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Position = salePoint.Position + Vector3.new(0, 3, 0)
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = character
		local player = {
			Name = "Phase5FSalePlayer",
			UserId = nextUserId,
			Parent = Players,
			Character = character,
		}
		local definition = assert(Catalog.GetDefinition("BRT_007"))
		local currentSellValue: any? = nil
		local record = {
			ItemId = "sale-individual-1",
			BrainrotId = "BRT_007",
			Metadata = { Tier = 1 },
			World = {},
		}
		local states = {
			[player] = {
				Record = record,
				CarrierUserId = player.UserId,
				Character = character,
				Root = root,
				Busy = false,
				Returning = false,
			},
		}
		local consumes = 0
		local carry = {}
		function carry.GetCarriedState(subject)
			return states[subject]
		end
		function carry.ConsumeCarriedBrainrot(subject, expectedId, reason, commit)
			assert(reason == "BrainrotSale", "unexpected consume reason")
			local state = states[subject]
			if not state or state.Record.ItemId ~= expectedId then
				return nil, "SOURCE_CHANGED"
			end
			state.Busy = true
			local committed, commitReason = commit(state.Record)
			if not committed then
				state.Busy = false
				return nil, commitReason
			end
			states[subject] = nil
			consumes += 1
			return state.Record, nil
		end
		local ready, balance, awards, failAward = true, 0, 0, false
		local nestedResult = nil
		local nestedSessionId = nil
		local wallet = {}
		function wallet:IsReady(subject)
			return ready and subject == player
		end
		function wallet:AddCash(subject, amount, reason)
			assert(subject == player and reason == "BrainrotSale", "unexpected award authority")
			if failAward then
				return { committed = false, code = "INJECTED_FAILURE" }
			end
			awards += 1
			if nestedSessionId then
				local id = nestedSessionId
				nestedSessionId = nil
				nestedResult = Sale:ConfirmSale(player, id)
			end
			balance += amount
			return { committed = true, code = "CREDITED", balance = balance }
		end
		function wallet:SyncBalance() end
		local catalogue = {}
		function catalogue.GetDefinition(id)
			local actual, reason = Catalog.GetDefinition(id)
			if not actual then
				return nil, reason
			end
			return {
				displayName = actual.displayName,
				tier = actual.tier,
				sellValue = if currentSellValue ~= nil and id == record.BrainrotId
					then currentSellValue
					else actual.sellValue,
			}
		end
		local bankedEligible = true
		local banked = {}
		function banked:ValidateSaleRecord() return bankedEligible, if bankedEligible then nil else "BANK_FIRST" end
		function banked:TryCommitSale(subject, _record, amount)
			if not bankedEligible then return { ok = false, committed = false, code = "BANK_FIRST" } end
			if amount == 0 then return { ok = true, committed = true, code = "Applied" } end
			return wallet:AddCash(subject, amount, "BrainrotSale")
		end
		local clock = 100
		local sequence = 0
		Sale:Init({
			Carry = carry,
			Currency = wallet,
			Catalog = catalogue,
			Banked = banked,
			ResolveSalePoint = function()
				return salePoint
			end,
			Now = function()
				return clock
			end,
			GenerateSessionId = function()
				sequence += 1
				return "sale-session-" .. sequence
			end,
		})
		local ok, problem = xpcall(function()
			callback({
				player = player,
				root = root,
				record = record,
				states = states,
				definition = definition,
				humanoid = humanoid,
				setClock = function(value)
					clock = value
				end,
				setBanked = function(value) bankedEligible = value end,
				setReady = function(value)
					ready = value
				end,
				setSellValue = function(value)
					currentSellValue = value
				end,
				setSpecies = function(value)
					record.BrainrotId = value
					currentSellValue = nil
				end,
				setOwner = function(value)
					states[player].CarrierUserId = value
				end,
				setFailAward = function(value)
					failAward = value
				end,
				setNestedSession = function(value)
					nestedSessionId = value
				end,
				getNestedResult = function()
					return nestedResult
				end,
				getBalance = function()
					return balance
				end,
				getAwards = function()
					return awards
				end,
				getConsumes = function()
					return consumes
				end,
			})
		end, debug.traceback)
		Sale:Stop()
		for index = #owned, 1, -1 do
			owned[index]:Destroy()
		end
		assert(ok, problem)
	end

	local function twoPlayerFixture(callback)
		Sale:Stop()
		local owned = {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local salePoint = own(Instance.new("Part"))
		salePoint.Anchored = true
		salePoint.Size = Vector3.new(10, 1, 10)
		salePoint.CFrame = CFrame.new(15100, 100, 15100)
		salePoint.Parent = workspace

		local players, states, balances, consumes = {}, {}, {}, {}
		for index, catalogueId in { "BRT_007", "BRT-008" } do
			local character = own(Instance.new("Model"))
			character.Name = "Phase5FCharacter" .. index
			character.Parent = workspace
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = true
			root.Position = salePoint.Position + Vector3.new(index, 3, 0)
			root.Parent = character
			local humanoid = Instance.new("Humanoid")
			humanoid.RequiresNeck = false
			humanoid.Parent = character
			local player = {
				Name = "Phase5FSalePlayer" .. index,
				UserId = -52000 - index,
				Parent = Players,
				Character = character,
			}
			players[index] = player
			balances[player], consumes[player] = 0, 0
			states[player] = {
				Record = {
					ItemId = "sale-individual-" .. index,
					BrainrotId = catalogueId,
					Metadata = {},
					World = {},
				},
				CarrierUserId = player.UserId,
				Character = character,
				Root = root,
				Busy = false,
				Returning = false,
			}
		end

		local carry = {}
		function carry.GetCarriedState(player)
			return states[player]
		end
		function carry.ConsumeCarriedBrainrot(player, expectedId, reason, commit)
			expect(reason).to.equal("BrainrotSale")
			local state = states[player]
			if not state or state.Record.ItemId ~= expectedId or state.Busy then
				return nil, "SOURCE_CHANGED"
			end
			state.Busy = true
			local committed, commitReason = commit(state.Record)
			if not committed then
				state.Busy = false
				return nil, commitReason
			end
			states[player] = nil
			consumes[player] += 1
			return state.Record, nil
		end

		local nestedPlayer, nestedSessionId, nestedResult = nil, nil, nil
		local wallet = {}
		function wallet:IsReady(player)
			return balances[player] ~= nil
		end
		function wallet:AddCash(player, amount, reason)
			expect(reason).to.equal("BrainrotSale")
			balances[player] += amount
			if nestedPlayer and nestedSessionId then
				local subject, sessionId = nestedPlayer, nestedSessionId
				nestedPlayer, nestedSessionId = nil, nil
				nestedResult = Sale:ConfirmSale(subject, sessionId)
			end
			return { committed = true, code = "CREDITED", balance = balances[player] }
		end
		function wallet:SyncBalance() end

		local sequence = 0
		Sale:Init({
			Carry = carry,
			Currency = wallet,
			Catalog = Catalog,
			Banked = {
				ValidateSaleRecord = function() return true, nil end,
				TryCommitSale = function(_, player, _record, amount) return wallet:AddCash(player, amount, "BrainrotSale") end,
			},
			ResolveSalePoint = function()
				return salePoint
			end,
			Now = function()
				return 100
			end,
			GenerateSessionId = function()
				sequence += 1
				return "multi-sale-session-" .. sequence
			end,
		})
		local ok, problem = xpcall(function()
			callback({
				players = players,
				states = states,
				balances = balances,
				consumes = consumes,
				confirmDuringAward = function(player, sessionId)
					nestedPlayer, nestedSessionId = player, sessionId
				end,
				getNestedResult = function()
					return nestedResult
				end,
			})
		end, debug.traceback)
		Sale:Stop()
		for index = #owned, 1, -1 do
			owned[index]:Destroy()
		end
		assert(ok, problem)
	end

	describe("Phase 6C-2 server-owned brainrot sale", function()
		it("resolves the existing BRT_007 catalogue identity, rank and explicit value", function()
			local definition = assert(Catalog.GetDefinition("BRT_007"))
			expect(definition.displayName).to.equal("Tung Tung Tung Sahur")
			expect(definition.tier).to.equal("Common")
			expect(definition.sellValue).to.equal(60000000)
		end)

		it("rejects empty hands and a carried record owned by another player", function()
			fixture(function(f)
				local state = f.states[f.player]
				f.states[f.player] = nil
				expect(select(2, Sale:CreatePreview(f.player))).to.equal("NothingCarried")
				f.states[f.player] = state
				f.setOwner(f.player.UserId - 1)
				expect(select(2, Sale:CreatePreview(f.player))).to.equal("NotOwner")
			end)
		end)

		it("rejects fresh quote and an existing quote after banked provenance disappears", function()
			fixture(function(f)
				f.setBanked(false)
				expect(select(2, Sale:CreatePreview(f.player))).to.equal("BankFirst")
				expect(f.getConsumes()).to.equal(0)
				expect(f.getBalance()).to.equal(0)
				f.setBanked(true)
				local preview = assert(Sale:CreatePreview(f.player))
				f.setBanked(false)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal("BankFirst")
				expect(f.getConsumes()).to.equal(0)
				expect(f.getBalance()).to.equal(0)
			end)
		end)

		it("creates only the sanitized authoritative preview while in range", function()
			fixture(function(f)
				local preview, reason = Sale:CreatePreview(f.player)
				assert(preview, reason)
				expect(preview.SaleSessionId).to.equal("sale-session-1")
				expect(preview.DisplayName).to.equal(f.definition.displayName)
				expect(preview.RuntimeBrainrotId).to.equal(f.record.ItemId)
				expect(preview.SpeciesId).to.equal("BRT_007")
				expect(preview.Rarity).to.equal(f.definition.tier)
				expect(preview.Rank).to.equal(f.definition.tier)
				expect(preview.SellValue).to.equal(60000000)
				expect(preview.ExpiresAtServerTime).to.equal(120)
				expect(preview.TrainAvailable).to.equal(false)
				expect(preview.MutationAvailable).to.equal(false)
			end)
		end)

		it("quotes every required control species from the authoritative catalogue", function()
			fixture(function(f)
				for _, expected in
					{
						{ "BRT_007", "Tung Tung Tung Sahur", "Common", 120 },
						{ "BRT_011", "Glorbo Fruttodrillo", "Uncommon", 240 },
						{ "BRT_019", "Trenostruzzo Turbo 3000", "Rare", 648 },
						{ "BRT_026", "Rhino Toasterino", "Epic", 2160 },
						{ "BRT_031", "Odin Din Din Dun", "Legendary", 8100 },
					}
				do
					f.setSpecies(expected[1])
					local preview = assert(Sale:CreatePreview(f.player))
					expect(preview.SpeciesId).to.equal(expected[1])
					expect(preview.DisplayName).to.equal(expected[2])
					expect(preview.Rarity).to.equal(expected[3])
					expect(preview.SellValue).to.equal(expected[4] * 500000)
				end
			end)
		end)

		it("rejects an unknown species without a BRT_007 fallback", function()
			fixture(function(f)
				f.setSpecies("BRT_999")
				expect(select(2, Sale:CreatePreview(f.player))).to.equal("InvalidCatalogue")
				expect(f.getBalance()).to.equal(0)
				expect(f.getConsumes()).to.equal(0)
			end)
		end)

		it("cancels only the matching pending quote without consuming or paying", function()
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				expect(Sale:CancelPendingSale(f.player, "wrong-session")).to.equal(false)
				expect(Sale:CancelPendingSale(f.player, preview.SaleSessionId)).to.equal(true)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
					"InvalidSession"
				)
				expect(f.states[f.player].Record).to.equal(f.record)
				expect(f.getBalance()).to.equal(0)
				expect(f.getConsumes()).to.equal(0)
			end)
		end)

		it("uses closest-point server range checks at preview and confirm", function()
			fixture(function(f)
				f.root.Position += Vector3.new(100, 0, 0)
				expect(select(2, Sale:CreatePreview(f.player))).to.equal("TooFarAway")
				f.root.Position -= Vector3.new(100, 0, 0)
				local preview = assert(Sale:CreatePreview(f.player))
				f.root.Position += Vector3.new(100, 0, 0)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
					"TooFarAway"
				)
				expect(f.getConsumes()).to.equal(0)
			end)
		end)

		it("expires previews and invalidates swapped individuals", function()
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				f.setClock(120)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
					"PreviewExpired"
				)
				local refreshed = assert(Sale:CreatePreview(f.player))
				f.states[f.player].Record = table.clone(f.record)
				f.states[f.player].Record.ItemId = "different-individual"
				expect(Sale:ConfirmSale(f.player, refreshed.SaleSessionId).code).to.equal(
					"NothingCarried"
				)
			end)
		end)

		it("requires a fresh preview when the authoritative catalogue price changes", function()
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				f.setSellValue(121)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
					"PreviewChanged"
				)
				expect(f.getBalance()).to.equal(0)
				expect(f.getConsumes()).to.equal(0)
			end)
		end)

		it("awards and consumes once while a re-entrant duplicate is busy", function()
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				f.setNestedSession(preview.SaleSessionId)
				local result = Sale:ConfirmSale(f.player, preview.SaleSessionId)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("Sold")
				expect(result.DisplayName).to.equal(f.definition.displayName)
				expect(result.Paid).to.equal(60000000)
				expect(f.getNestedResult().code).to.equal("Busy")
				expect(f.getBalance()).to.equal(60000000)
				expect(f.getAwards()).to.equal(1)
				expect(f.getConsumes()).to.equal(1)
				expect(f.states[f.player]).to.equal(nil)
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
					"InvalidSession"
				)
			end)
		end)

		it("preserves the carried individual on an explicit award failure", function()
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				f.setFailAward(true)
				local result = Sale:ConfirmSale(f.player, preview.SaleSessionId)
				expect(result.code).to.equal("AwardFailed")
				expect(f.states[f.player].Record).to.equal(f.record)
				expect(f.states[f.player].Busy).to.equal(false)
				expect(f.getBalance()).to.equal(0)
				expect(f.getConsumes()).to.equal(0)
			end)
		end)

		it(
			"rejects unavailable profiles, dead characters and forged confirmation payloads",
			function()
				fixture(function(f)
					f.setReady(false)
					expect(select(2, Sale:CreatePreview(f.player))).to.equal("InvalidSession")
					f.setReady(true)
					local preview = assert(Sale:CreatePreview(f.player))
					expect(Sale:ConfirmSale(f.player, "invented-session").code).to.equal(
						"InvalidSession"
					)
					expect(f.getBalance()).to.equal(0)
					expect(f.getConsumes()).to.equal(0)

					f.humanoid.Health = 0
					expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal(
						"InvalidSession"
					)
					expect(f.getBalance()).to.equal(0)
					expect(f.getConsumes()).to.equal(0)
				end)
			end
		)

		it(
			"ignores client-supplied sale fields and pays only the previewed server value",
			function()
				fixture(function(f)
					local preview = assert(Sale:CreatePreview(f.player))
					local result = Sale:ConfirmSale(
						f.player,
						preview.SaleSessionId,
						"Fake Name",
						"Secret",
						999999999
					)
					expect(result.code).to.equal("Sold")
					expect(result.DisplayName).to.equal(f.definition.displayName)
					expect(result.Paid).to.equal(60000000)
					expect(f.getBalance()).to.equal(60000000)
					expect(f.getAwards()).to.equal(1)
				end)
			end
		)

		it("consumes only the carried runtime individual among identical species", function()
			fixture(function(f)
				local other = {
					ItemId = "sale-individual-2",
					BrainrotId = "BRT_007",
					Metadata = {},
				}
				local preview = assert(Sale:CreatePreview(f.player))
				local result = Sale:ConfirmSale(f.player, preview.SaleSessionId)
				expect(result.code).to.equal("Sold")
				expect(f.record.ItemId).to.equal("sale-individual-1")
				expect(other.ItemId).to.equal("sale-individual-2")
				expect(other.BrainrotId).to.equal("BRT_007")
				expect(f.getConsumes()).to.equal(1)
			end)
		end)

		it("leaves an unrelated platform's accumulated cash untouched", function()
			local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
			local base = Instance.new("Model")
			base:SetAttribute("BaseId", "sale-platform-regression")
			local platform = Instance.new("Part")
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Parent = platform
			local storage = BaseStorage.new(base, -1, {
				{ Index = 1, Platform = platform, Marker = marker },
			}, {
				PlatformIncome = { ["1"] = { UnclaimedCashExact = 75 } },
			})
			fixture(function(f)
				local preview = assert(Sale:CreatePreview(f.player))
				expect(Sale:ConfirmSale(f.player, preview.SaleSessionId).code).to.equal("Sold")
				expect(storage:GetUnclaimedCashExact(1)).to.equal(75)
			end)
			storage:Destroy()
			base:Destroy()
		end)

		it(
			"refuses malformed sale values and consumes a valid zero-value item without credit",
			function()
				fixture(function(f)
					for _, invalid in { -1, math.huge, 0 / 0, "120" } do
						f.setSellValue(invalid)
						expect(select(2, Sale:CreatePreview(f.player))).to.equal("InvalidCatalogue")
					end
					f.setSellValue(0)
					local preview = assert(Sale:CreatePreview(f.player))
					local result = Sale:ConfirmSale(f.player, preview.SaleSessionId)
					expect(result.code).to.equal("Sold")
					expect(result.Paid).to.equal(0)
					expect(f.getBalance()).to.equal(0)
					expect(f.getAwards()).to.equal(0)
					expect(f.getConsumes()).to.equal(1)
				end)
			end
		)

		it("preserves fractional base sale values and applies the mutation exactly once", function()
			fixture(function(f)
				f.setSellValue(1.5)
				f.record.Metadata.MutationId = "Shiny"
				local preview = assert(Sale:CreatePreview(f.player))
				expect(preview.SellValue).to.equal(2.25)
				local result = Sale:ConfirmSale(f.player, preview.SaleSessionId)
				expect(result.Paid).to.equal(2.25)
				expect(f.getBalance()).to.equal(2.25)
				expect(f.getConsumes()).to.equal(1)
			end)
		end)

		it("isolates two players' ownership, sessions, locks, payouts and consumption", function()
			twoPlayerFixture(function(f)
				local a, b = f.players[1], f.players[2]
				f.states[a].CarrierUserId = b.UserId
				expect(select(2, Sale:CreatePreview(a))).to.equal("NotOwner")
				f.states[a].CarrierUserId = a.UserId

				local aPreview = assert(Sale:CreatePreview(a))
				expect(Sale:ConfirmSale(b, aPreview.SaleSessionId).code).to.equal("InvalidSession")
				expect(f.balances[a]).to.equal(0)
				expect(f.balances[b]).to.equal(0)
				local bPreview = assert(Sale:CreatePreview(b))
				f.confirmDuringAward(b, bPreview.SaleSessionId)
				local aResult = Sale:ConfirmSale(a, aPreview.SaleSessionId)
				expect(aResult.code).to.equal("Sold")
				expect(f.getNestedResult().code).to.equal("Sold")
				expect(f.balances[a]).to.equal(60000000)
				expect(f.balances[b]).to.equal(66000000)
				expect(f.consumes[a]).to.equal(1)
				expect(f.consumes[b]).to.equal(1)
				expect(f.states[a]).to.equal(nil)
				expect(f.states[b]).to.equal(nil)
			end)
		end)
	end)
end
