--!nocheck
-- Account ownership/selection regression. Native mount fit is verified separately.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Cosmetics = require(RS.Shared.Utility.Phase14CosmeticRules)
	local Appearance = require(RS.Shared.Utility.Phase13AppearanceRules)
	local Commerce = require(RS.Shared.Utility.Phase13CommerceRules)
	local Phase13 = require(RS.Shared.Utility.Phase13Rules)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Transactions = require(script.Parent.Parent.Services.Phase13Service)
	local function fixture()
		local data = Schema.CreateDefault()
		data.Economy.Balance = 123.375
		return data
	end
	describe("Phase14 independent cosmetic ownership and selection contract", function()
		it("has exactly six flag/banner and three included trail records with fixed metadata", function()
			expect(#Cosmetics.Catalog).to.equal(9)
			expect(Cosmetics.Get("P14_FLAG_FOREST").priceCash).to.equal(500000000)
			expect(Cosmetics.Get("P14_BASE_FOREST").priceCash).to.equal(2500000000)
			expect(Cosmetics.Get("P14_FLAG_CAMP").lifetimeClaim).to.equal(7)
			expect(Cosmetics.Get("P14_BASE_EXPEDITION").lifetimeClaim).to.equal(14)
			for _, id in { "P14_FLAG_RIFT", "P14_BASE_RIFT" } do
				local row = Cosmetics.Get(id)
				-- P15: the Rift pair is sold for Gems (Economy.GemCosmetics); it has no
				-- Robux platform identity and no enabled paid path.
				expect(row.paidEnabled ~= true).to.equal(true)
				expect(row.platformId).to.equal(nil)
				expect(row.acquisition).to.equal("Gems")
				expect(row.priceCash).to.equal(nil)
				expect(row.priceGems).to.equal(if id == "P14_FLAG_RIFT" then 120 else 220)
			end
		end)
		it("defaults all three slots to None without mutating or migrating an existing profile", function()
			local data = fixture()
			local before = Fixtures.Clone(data)
			local snapshot = Cosmetics.Snapshot(data)
			for _, slot in Cosmetics.Slots do
				expect(snapshot.slots[slot].selected).to.equal("None")
				expect(#snapshot.slots[slot].rows).to.equal(3)
				expect(Appearance.CanSelect(data, slot, "None")).to.equal(true)
			end
			Fixtures.AssertDeepEqual(data, before)
		end)
		for _, row in
			{
				{ "P14_TRAIL_STARFORGE", "CRT_007" },
				{ "P14_TRAIL_COMET", "CRT_010" },
				{ "P14_TRAIL_OBSIDIAN", "CRT_013" },
			}
		do
			it("derives " .. row[1] .. " only from durable canonical " .. row[2] .. " ownership", function()
				local data = fixture()
				expect(Cosmetics.Owns(data, row[1])).to.equal(false)
				data.Phase13.OwnedCartIds[Cosmetics.Get(row[1]).requiredCartName] = true
				data.Phase13.OwnedCartIds["CH_" .. row[1]] = true
				expect(Cosmetics.Owns(data, row[1])).to.equal(false)
				data.Phase13.OwnedCartIds[row[2]] = true
				local before = Fixtures.Clone(data)
				expect(Cosmetics.Owns(data, row[1])).to.equal(true)
				local snapshot = Cosmetics.Snapshot(data)
				local found
				for _, item in snapshot.slots.Trail.rows do
					if item.id == row[1] then
						found = item
					end
				end
				expect(found.owned).to.equal(true)
				expect(found.acquisitionText).to.equal("Included with " .. Cosmetics.Get(row[1]).requiredCartName)
				expect(found.priceCash).to.equal(nil)
				expect(snapshot.slots.Trail.selected).to.equal("None")
				Fixtures.AssertDeepEqual(data, before)
			end)
		end
		it("allows validated renderers for legitimate owners without granting new ownership", function()
			local data = fixture()
			for _, row in Cosmetics.Catalog do
				if row.requiredCartId then
					data.Phase13.OwnedCartIds[row.requiredCartId] = true
				else
					data.Commerce.Entitlements[row.id] = true
				end
				local allowed, reason = Appearance.CanSelect(data, row.slot, row.id)
				expect(allowed).to.equal(true)
				expect(reason).to.equal(nil)
			end
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("rejects spoofed IDs cross-slot values and client-owned hints without mutation", function()
			local data = fixture()
			local before = Fixtures.Clone(data)
			for _, pair in
				{
					{ "Flag", "CH_SCRAP_CHARIOT" },
					{ "Flag", "P14_BASE_FOREST" },
					{ "Trail", "Starforge Chariot" },
					{ "Trail", "P14_TRAIL_COMET" },
					{ "Flag", { owned = true, id = "P14_FLAG_CAMP" } },
				}
			do
				expect(Appearance.CanSelect(data, pair[1], pair[2])).to.equal(false)
			end
			Fixtures.AssertDeepEqual(data, before)
		end)
		it("allows exactly the six account cosmetic keys without adding paid pass grants", function()
			local data = fixture()
			for _, row in Cosmetics.Catalog do
				if row.acquisition ~= "Included" then
					data.Commerce.Entitlements[row.id] = true
				end
			end
			expect(Schema.ValidateLoaded(data)).to.equal(true)
			expect(Commerce.GrantPass(data, "P14_FLAG_RIFT", 1000)).to.equal(false)
			data.Commerce.Entitlements.P14_TRAIL_STARFORGE = true
			expect(Schema.ValidateLoaded(data)).to.equal(false)
		end)
		it("preserves confirmed selections through asset unavailability and rejects corrupt new slot IDs", function()
			local data = fixture()
			data.Commerce.Entitlements.P14_FLAG_CAMP = true
			data.Commerce.Appearance.Flag = "P14_FLAG_CAMP"
			local snapshot = Cosmetics.Snapshot(data)
			expect(snapshot.slots.Flag.selected).to.equal("P14_FLAG_CAMP")
			expect(Cosmetics.Selected(data, "Flag")).to.equal("P14_FLAG_CAMP")
			expect(Schema.ValidateLoaded(data)).to.equal(true)
			data.Commerce.Appearance.Flag = "P14_BASE_FOREST"
			expect(Schema.ValidateLoaded(data)).to.equal(false)
		end)
		it("cannot invoke Starter Cash or legacy entitlement reconciliation during repeated previews", function()
			local data = fixture()
			data.Commerce.Entitlements.STARTER_PACK = true
			data.Commerce.Entitlements.VIP = true
			data.Commerce.StarterPackClaimed = true
			local before = Fixtures.Clone(data)
			for _ = 1, 20 do
				Cosmetics.Snapshot(data)
				Appearance.CanSelect(data, "Flag", "None")
			end
			Fixtures.AssertDeepEqual(data, before)
			expect(Appearance.CanSelect(data, "VIPTitle", "On")).to.equal(true)
			expect(Appearance.CanSelect(data, "CartFinish", "Trailblazer")).to.equal(true)
		end)
		for _, route in { "Cash", "Collection" } do
			it("preserves ownership and selection through the unchanged " .. route .. " rebirth", function()
				local data = fixture()
				data.Economy.Balance = 1000000000000
				for i = 1, 12 do
					local id = "owned:" .. i
					data.Collection.BrainrotInstances[id] = {
						speciesId = if i <= 4 then "BRT_019" else "BRT_001",
						mutationId = "None",
						firstBankCompleted = true,
					}
					data.Base.Slots[tostring(i)].brainrotId = id
				end
				data.Phase13.OwnedCartIds.CRT_007 = true
				data.Commerce.Entitlements.P14_FLAG_CAMP = true
				data.Commerce.Appearance.Flag = "P14_FLAG_CAMP"
				data.Commerce.Appearance.Trail = "P14_TRAIL_STARFORGE"
				local before = Fixtures.Clone(data.Commerce)
				local quote = Phase13.QuoteRebirth(data, "BDS_002", route)
				expect(quote.ok).to.equal(true)
				expect(Phase13.ApplyRebirth(data, {
					rewardId = "BDS_002",
					route = route,
					previewRevision = quote.previewRevision,
					inventorySignature = quote.inventorySignature,
				}, 1000)).to.equal(true)
				Fixtures.AssertDeepEqual(data.Commerce, before)
				expect(Cosmetics.Owns(data, "P14_TRAIL_STARFORGE")).to.equal(true)
			end)
		end
	end)
	describe("Phase14 CP4B existing critical selection writer fixture", function()
		it("commits None atomically behind covering save and deduplicates the existing operation", function()
			Transactions:_ResetForTests()
			local p = { UserId = 814004, Parent = Players, Attributes = {} }
			function p:SetAttribute(k, v)
				self.Attributes[k] = v
			end
			local f = {
				Data = fixture(),
				Revision = 0,
				Saved = 0,
				Session = {},
				Fence = nil,
				SaveListeners = {},
				Calls = 0,
			}
			f.Data.Commerce.Entitlements.P14_FLAG_CAMP = true
			f.Data.Commerce.Appearance.Flag = "P14_FLAG_CAMP"
			function f:GetReadableData()
				return self.Data
			end
			function f:GetCurrentRevision()
				return self.Revision
			end
			function f:GetSessionHandle()
				return self.Session
			end
			function f:IsCurrentSessionHandle(s)
				return self.Session == s
			end
			function f:IsRevisionConfirmed(_, r)
				return self.Saved >= r
			end
			function f:AcquireCritical(_, id)
				if self.Fence then
					return nil, "BUSY"
				end
				self.Fence = { Id = id }
				return self.Fence
			end
			function f:ReleaseCritical(_, h)
				if self.Fence ~= h then
					return false
				end
				self.Fence = nil
				return true
			end
			function f:HasCriticalOperation()
				return self.Fence ~= nil
			end
			function f:SubscribeReady()
				return { Disconnect = function() end }
			end
			function f:SubscribeSaveConfirmed(fn)
				table.insert(self.SaveListeners, fn)
				return { Disconnect = function() end }
			end
			function f:CommitCriticalMutation(_, h, mutator)
				assert(self.Fence == h, "Critical fixture handle changed")
				local committed, result = mutator(self.Data)
				if not committed then
					return { ok = false, code = result.code }
				end
				assert(Schema.ValidateLoaded(self.Data), "Attachment selection produced an invalid profile")
				self.Revision += 1
				self.Calls += 1
				return { ok = true, revision = self.Revision, result = result }
			end
			function f:RequestSave()
				return { ok = false, code = "CONTROLLED_UNCERTAIN" }
			end
			local income = {
				BeginCriticalCutover = function()
					return {}
				end,
				EndCriticalCutover = function()
					return true
				end,
			}
			Transactions:Start({
				Profile = f,
				Income = income,
				Currency = {
					SyncBalance = function()
						return true
					end,
				},
				Now = function()
					return 1000
				end,
			})
			local ok, why = xpcall(function()
				local mutations = 0
				local function select(data)
					mutations += 1
					local allowed, reason = Appearance.CanSelect(data, "Flag", "None")
					if not allowed then
						return false, { code = reason }
					end
					data.Commerce.Appearance.Flag = "None"
					return true, { category = "Cosmetic", key = "Flag", value = "None" }
				end
				expect(Transactions:CommitCritical(p, "p14:none", "Appearance", select).state).to.equal("Saving")
				expect(Transactions:CommitCritical(p, "p14:none", "Appearance", select).state).to.equal("Saving")
				expect(mutations).to.equal(1)
				expect(f.Data.Economy.Balance).to.equal(123.375)
				f.Saved = f.Revision
				for _, fn in f.SaveListeners do
					fn(p, f.Saved)
				end
				expect(Transactions:GetOperation(p, "p14:none").state).to.equal("Confirmed")
				expect(Transactions:CommitCritical(p, "p14:none", "Appearance", select).state).to.equal("Confirmed")
				expect(mutations).to.equal(1)
				local saved = assert(Schema.CreateSaveSnapshot(f.Data), "Attachment selection snapshot failed")
				expect(Cosmetics.Selected(saved, "Flag")).to.equal("None")
				expect(saved.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
			end, debug.traceback)
			Transactions:_ResetForTests()
			assert(ok, why)
		end)
	end)
end
