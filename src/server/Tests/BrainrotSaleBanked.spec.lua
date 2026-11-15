--!nocheck
-- Bulk sale of banked brainrots at the Sell stall (BrainrotSaleSystem:ListBanked / SellBanked).
-- The storage and banked services are fakes with the real method shapes: this suite covers the
-- sale system's own validation, ordering, quote check and put-back, not the profile store.
return function()
	local Players = game:GetService("Players")
	local Catalog = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotCatalog)
	local Sale = require(script.Parent.Parent.Systems.BrainrotSaleSystem)

	local nextUserId = -53000
	local function fixture(callback)
		Sale:Stop()
		nextUserId -= 1
		local owned = {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local salePoint = own(Instance.new("Part"))
		salePoint.Anchored = true
		salePoint.Size = Vector3.new(10, 1, 10)
		salePoint.CFrame = CFrame.new(15400, 100, 15400)
		salePoint.Parent = workspace
		local character = own(Instance.new("Model"))
		character.Parent = workspace
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Position = salePoint.Position + Vector3.new(0, 3, 0)
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = character
		local player = { Name = "BankedSalePlayer", UserId = nextUserId, Parent = Players, Character = character }
		local base = own(Instance.new("Model"))

		-- five platforms; four start occupied
		local platforms, entries = {}, {}
		for index = 1, 5 do
			local platform = Instance.new("Part")
			platform.Name = "Slot_" .. index
			platform.Anchored = true
			platform.Parent = base
			platforms[index] = { Index = index, Platform = platform }
		end
		local function put(index, id, species, mutationId)
			entries[index] = {
				SlotIndex = index,
				ItemId = id,
				BrainrotId = species,
				Metadata = { MutationId = mutationId },
			}
		end
		put(1, "ind-a", "BRT_001")
		put(2, "ind-b", "BRT_007")
		put(3, "ind-c", "BRT_011", "Shiny")
		put(4, "ind-d", "BRT_001")

		local log = {}
		local storageReady, removeFails, removeThrows = true, {}, {}
		local storage = { Base = base }
		function storage:GetSnapshot()
			local list = {}
			for index = 1, 5 do
				if entries[index] then
					table.insert(list, table.clone(entries[index]))
				end
			end
			return list
		end
		local limbo = {} -- removed from a platform, still owned
		local storageSystem = {}
		function storageSystem:GetStorageForPlayer(subject)
			return if storageReady and subject == player then storage else nil
		end
		function storageSystem:GetRegisteredPlatforms(subject)
			return if subject == base then platforms else nil
		end
		function storageSystem:TryRemoveFromPlatform(subject, platform, expectedId)
			assert(subject == player, "unexpected storage authority")
			if removeThrows[expectedId] then
				error("injected removal error")
			end
			if removeFails[expectedId] then
				return nil, removeFails[expectedId]
			end
			for index, slot in platforms do
				if slot.Platform == platform then
					local entry = entries[index]
					if not entry or entry.ItemId ~= expectedId then
						return nil, if entry then "STALE_ID" else "EMPTY"
					end
					entries[index] = nil
					limbo[expectedId] = entry
					table.insert(log, "remove:" .. expectedId)
					return entry, nil
				end
			end
			return nil, "INVALID_PLATFORM"
		end
		function storageSystem:BindReturnedOwnedIndividual(subject, slotId, id)
			assert(subject == player, "unexpected storage authority")
			local entry = limbo[id]
			if not entry or entries[tonumber(slotId)] then
				return false, "SOURCE_CHANGED"
			end
			limbo[id] = nil
			entry.SlotIndex = tonumber(slotId)
			entries[entry.SlotIndex] = entry
			table.insert(log, "rebind:" .. id .. "@" .. slotId)
			return true, nil
		end

		local balance, awards, failAward, throwAward, pendingBank = 0, 0, {}, {}, {}
		local revision = 10
		local banked = {}
		function banked:IsBankPending(_subject, id)
			return pendingBank[id] == true
		end
		local favourites = {}
		function banked:IsFavourite(_subject, id)
			return favourites[id] == true
		end
		function banked:TryCommitSale(subject, record, amount, strict, catalog)
			assert(subject == player and strict == true and catalog ~= nil, "unexpected sale authority")
			if throwAward[record.ItemId] then
				error("injected award error")
			end
			if failAward[record.ItemId] then
				return { ok = false, committed = false, code = failAward[record.ItemId] }
			end
			assert(limbo[record.ItemId], "sale must follow the platform removal")
			limbo[record.ItemId] = nil
			awards += 1
			balance += amount
			revision += 1
			table.insert(log, "paid:" .. record.ItemId)
			return { ok = true, committed = true, code = "CREDITED", revision = revision }
		end
		function banked:ReturnOwnedToAvailableSlot(subject, _record)
			assert(subject == player, "unexpected return authority")
			for index = 1, 5 do
				if not entries[index] then
					return { ok = true, committed = true, code = "RETURNED_TO_BASE", slotId = tostring(index) }
				end
			end
			return { ok = false, committed = false, code = "BASE_FULL" }
		end
		local ready = true
		local wallet = {}
		function wallet:IsReady(subject)
			return ready and subject == player
		end
		local syncs = 0
		function wallet:SyncBalance()
			syncs += 1
		end
		local carry = {}
		function carry.GetCarriedState()
			return nil
		end
		local sequence = 0
		Sale:Init({
			Carry = carry,
			Currency = wallet,
			Catalog = Catalog,
			Banked = banked,
			Storage = storageSystem,
			ResolveSalePoint = function()
				return salePoint
			end,
			Now = function()
				return 100
			end,
			GenerateSessionId = function()
				sequence += 1
				return "batch-" .. sequence
			end,
		})
		local receipts = {}
		local subscription = Sale.SubscribeCommitted(function(_subject, receipt)
			table.insert(receipts, receipt)
		end)
		local function value(species, mutationMultiplier)
			return assert(Catalog.GetDefinition(species)).sellValue * (mutationMultiplier or 1)
		end
		local ok, problem = xpcall(function()
			callback({
				player = player,
				root = root,
				humanoid = humanoid,
				salePoint = salePoint,
				entries = entries,
				limbo = limbo,
				log = log,
				receipts = receipts,
				value = value,
				shinyValue = function()
					return Sale:ListBanked(player).rows[3].sellValue
				end,
				balance = function()
					return balance
				end,
				awards = function()
					return awards
				end,
				syncs = function()
					return syncs
				end,
				failRemove = function(id, code)
					removeFails[id] = code
				end,
				throwRemove = function(id)
					removeThrows[id] = true
				end,
				failAward = function(id, code)
					failAward[id] = code
				end,
				throwAward = function(id)
					throwAward[id] = true
				end,
				setPendingBank = function(id, on)
					pendingBank[id] = on
				end,
				setFavourite = function(id, on)
					favourites[id] = on
				end,
				setStorageReady = function(on)
					storageReady = on
				end,
				setReady = function(on)
					ready = on
				end,
			})
		end, debug.traceback)
		subscription.Disconnect()
		Sale:Stop()
		for index = #owned, 1, -1 do
			owned[index]:Destroy()
		end
		assert(ok, problem)
	end

	describe("Bulk sale of banked brainrots at the Sell stall", function()
		it("lists every platform brainrot with the authoritative value and mutation", function()
			fixture(function(f)
				local list = Sale:ListBanked(f.player)
				expect(list.ok).to.equal(true)
				expect(#list.rows).to.equal(4)
				expect(list.max).to.equal(48)
				local first = list.rows[1]
				expect(first.id).to.equal("ind-a")
				expect(first.speciesId).to.equal("BRT_001")
				expect(first.sellValue).to.equal(f.value("BRT_001"))
				expect(first.slot).to.equal(1)
				expect(first.team).to.equal(false)
				expect(list.rows[3].mutationId).to.equal("Shiny")
				expect(list.rows[3].sellValue > f.value("BRT_011")).to.equal(true)
				f.setStorageReady(false)
				expect(Sale:ListBanked(f.player).code).to.equal("NotReady")
			end)
		end)

		it("sells the picked brainrots once each, removal before payment, and reports the total", function()
			fixture(function(f)
				local total = f.value("BRT_001") + f.value("BRT_007")
				local result = Sale:SellBanked(f.player, { "ind-a", "ind-b" }, total)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("Sold")
				expect(result.sold).to.equal(2)
				expect(result.paid).to.equal(total)
				expect(f.balance()).to.equal(total)
				expect(table.concat(f.log, ",")).to.equal("remove:ind-a,paid:ind-a,remove:ind-b,paid:ind-b")
				expect(f.entries[1]).to.equal(nil)
				expect(f.entries[2]).to.equal(nil)
				expect(f.entries[3].ItemId).to.equal("ind-c")
				expect(f.syncs()).to.equal(1)
				expect(#f.receipts).to.equal(2)
				expect(f.receipts[1].kind).to.equal("BrainrotSold")
				expect(f.receipts[1].individualId).to.equal("ind-a")
				expect(f.receipts[2].eventId ~= f.receipts[1].eventId).to.equal(true)
				-- a repeat of the same request finds nothing to sell and pays nothing
				local again = Sale:SellBanked(f.player, { "ind-a", "ind-b" }, total)
				expect(again.ok).to.equal(false)
				expect(again.code).to.equal("NotOnPlatform")
				expect(f.balance()).to.equal(total)
			end)
		end)

		it("sells nothing when the shown total differs from the authoritative total", function()
			fixture(function(f)
				local result = Sale:SellBanked(f.player, { "ind-a", "ind-c" }, f.value("BRT_001") + f.value("BRT_011"))
				expect(result.code).to.equal("QuoteChanged") -- ind-c is mutated: its value is higher
				expect(f.awards()).to.equal(0)
				expect(#f.log).to.equal(0)
				local good = Sale:SellBanked(f.player, { "ind-a", "ind-c" }, f.value("BRT_001") + f.shinyValue())
				expect(good.ok).to.equal(true)
				expect(good.sold).to.equal(2)
			end)
		end)

		it("rejects malformed, duplicate, oversized and foreign id lists before touching anything", function()
			fixture(function(f)
				local v = f.value("BRT_001")
				local big = {}
				for index = 1, 49 do
					big[index] = "ind-" .. index
				end
				local bad = {
					{ nil, v },
					{ "ind-a", v },
					{ {}, 0 },
					{ { "ind-a", "ind-a" }, v * 2 },
					{ { "ind-a", 7 }, v },
					{ { "" }, 0 },
					{ { a = "ind-a" }, v },
					{ { [1] = "ind-a", [3] = "ind-b" }, v },
					{ { string.rep("x", 129) }, 0 },
					{ big, 0 },
					{ { "ind-a" }, 0 / 0 },
					{ { "ind-a" }, -1 },
					{ { "ind-a" }, math.huge },
					{ { "ind-a" }, "5" },
				}
				for _, case in bad do
					expect(Sale:SellBanked(f.player, case[1], case[2]).code).to.equal("InvalidRequest")
				end
				expect(Sale:SellBanked(f.player, { "ind-a", "someone-else" }, v).code).to.equal("NotOnPlatform")
				expect(#f.log).to.equal(0)
				expect(f.awards()).to.equal(0)
			end)
		end)

		it("requires a living, ready player inside the server sale range", function()
			fixture(function(f)
				local v = f.value("BRT_001")
				f.root.Position = f.salePoint.Position + Vector3.new(40, 3, 0)
				expect(Sale:SellBanked(f.player, { "ind-a" }, v).code).to.equal("TooFarAway")
				f.root.Position = f.salePoint.Position + Vector3.new(0, 3, 0)
				f.setReady(false)
				expect(Sale:SellBanked(f.player, { "ind-a" }, v).code).to.equal("InvalidSession")
				f.setReady(true)
				f.humanoid.Health = 0
				expect(Sale:SellBanked(f.player, { "ind-a" }, v).code).to.equal("InvalidSession")
				expect(#f.log).to.equal(0)
			end)
		end)

		it("refuses the whole batch while one pick is still saving its bank", function()
			fixture(function(f)
				f.setPendingBank("ind-b", true)
				local total = f.value("BRT_001") + f.value("BRT_007")
				expect(Sale:SellBanked(f.player, { "ind-a", "ind-b" }, total).code).to.equal("BankSavePending")
				expect(#f.log).to.equal(0)
				expect(Sale:ListBanked(f.player).rows[2].saving).to.equal(true)
			end)
		end)

		it("lists a favourite as one and refuses any batch that contains it", function()
			fixture(function(f)
				f.setFavourite("ind-b", true)
				local list = Sale:ListBanked(f.player)
				expect(list.rows[2].favourite).to.equal(true)
				expect(list.rows[1].favourite).to.equal(false)
				local total = f.value("BRT_001") + f.value("BRT_007")
				expect(Sale:SellBanked(f.player, { "ind-a", "ind-b" }, total).code).to.equal("Favourite")
				expect(#f.log).to.equal(0)
				expect(f.awards()).to.equal(0)
				expect(f.entries[1].ItemId).to.equal("ind-a")
				f.setFavourite("ind-b", false)
				expect(Sale:SellBanked(f.player, { "ind-a", "ind-b" }, total).ok).to.equal(true)
			end)
		end)

		it("puts an unsold brainrot back on a platform when payment is refused, and stops", function()
			fixture(function(f)
				f.failAward("ind-b", "BALANCE_OVERFLOW")
				local total = f.value("BRT_001") + f.value("BRT_007") + f.value("BRT_001")
				local result = Sale:SellBanked(f.player, { "ind-a", "ind-b", "ind-d" }, total)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("PartlySold")
				expect(result.sold).to.equal(1)
				expect(result.requested).to.equal(3)
				expect(result.paid).to.equal(f.value("BRT_001"))
				expect(result.stoppedBy).to.equal("BALANCE_OVERFLOW")
				expect(f.balance()).to.equal(f.value("BRT_001"))
				-- ind-b is on a platform again (the first free one) and nothing is left in limbo
				expect(f.entries[1].ItemId).to.equal("ind-b")
				expect(next(f.limbo)).to.equal(nil)
				expect(f.entries[4].ItemId).to.equal("ind-d")
			end)
		end)

		it("fails cleanly when the first removal is refused", function()
			fixture(function(f)
				f.failRemove("ind-a", "BUSY")
				local result = Sale:SellBanked(f.player, { "ind-a" }, f.value("BRT_001"))
				expect(result.ok).to.equal(false)
				expect(result.code).to.equal("BUSY")
				expect(f.awards()).to.equal(0)
				expect(f.entries[1].ItemId).to.equal("ind-a")
				expect(f.syncs()).to.equal(0)
			end)
		end)

		it("recovers the in-flight brainrot and releases the lock after an unexpected error", function()
			fixture(function(f)
				f.throwAward("ind-a")
				local v = f.value("BRT_001")
				local result = Sale:SellBanked(f.player, { "ind-a" }, v)
				expect(result.ok).to.equal(false)
				expect(f.entries[1].ItemId).to.equal("ind-a")
				expect(next(f.limbo)).to.equal(nil)
				f.throwRemove("ind-d")
				expect(Sale:SellBanked(f.player, { "ind-d" }, v).ok).to.equal(false)
				-- the lock is free again: an ordinary sale still works
				expect(Sale:SellBanked(f.player, { "ind-b" }, f.value("BRT_007")).ok).to.equal(true)
			end)
		end)
	end)
end
