--!nocheck
-- Bulk sale of banked brainrots against the real profile-backed BaseStorage, BankedBrainrotService
-- and CurrencySystem (same owner fixture as BankedBrainrotPersistence.spec). Only the storage *system*
-- (base binding, displays, observers) is a thin adapter over the real BaseStorage class.
return function()
	local Players = game:GetService("Players")
	local ProfileSchema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local Catalog = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotCatalog)
	local Sale = require(script.Parent.Parent.Systems.BrainrotSaleSystem)

	local function fixture(runFixture)
		Sale:Stop()
		local player = { UserId = 74102, Name = "BankedSaleSpec", Parent = Players }
		local profile = ProfileSchema.CreateDefault()
		local owner = { Data = profile, Revision = 0, SaveRequests = {} }
		function owner:IsWritable(subject)
			return subject == player and subject.Parent == Players
		end
		function owner:GetReadableData(subject)
			return if self:IsWritable(subject) then self.Data else nil, "PROFILE_NOT_READY"
		end
		function owner:GetWritableData(subject)
			return self:GetReadableData(subject)
		end
		function owner:CommitMutation(subject, mutator)
			if not self:IsWritable(subject) then
				return { ok = false, committed = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutator(self.Data)
			if not committed then
				return result
			end
			self.Revision += 1
			result.ok, result.committed, result.revision = true, true, self.Revision
			return result
		end
		function owner:MarkDirty(subject)
			if not self:IsWritable(subject) then
				return nil, "PROFILE_NOT_READY"
			end
			self.Revision += 1
			return self.Revision
		end
		function owner:GetDiagnostics()
			return { currentRevision = self.Revision, lastConfirmedSavedRevision = 0 }
		end
		function owner:GetSessionHandle(subject)
			return if self:IsWritable(subject) then { Player = subject, UserId = subject.UserId, Generation = 1 } else nil
		end
		function owner:IsCurrentSessionHandle(handle)
			return handle ~= nil and handle.Player == player
		end
		function owner:RequestSave(_subject, reason)
			table.insert(self.SaveRequests, { reason = reason, revision = self.Revision })
			return { ok = true, code = "SCHEDULED" }
		end
		function owner:SubscribeSaveConfirmed()
			return { Disconnect = function() end }
		end
		function owner:SubscribeDiagnostics()
			return { Disconnect = function() end }
		end
		function owner:BeginClosing()
			return true
		end

		local owned = {}
		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "BankedSaleSpecBase")
		table.insert(owned, base)
		local slots = {}
		for index = 1, 12 do
			local platform = Instance.new("Part")
			platform.Name = "Slot_" .. index
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name = "BrainrotPlacement"
			marker.Parent = platform
			slots[index] = { Index = index, Platform = platform, Marker = marker }
		end
		local storage = BaseStorage.new(base, player.UserId, slots, profile)
		local function deposit(id, speciesId, slotIndex, mutationId)
			local item = {
				ItemId = id,
				BrainrotId = speciesId,
				Metadata = { DurableOwnerUserId = player.UserId, MutationId = mutationId },
			}
			local reservation = assert(storage:TryReserveSlot(id, slotIndex))
			assert(storage:CommitReservation(reservation, item, Instance.new("Model")))
			return item
		end

		-- the storage system's two calls, over the real BaseStorage and the real profile mutation
		local rebinds = {}
		local adapter = {}
		function adapter:GetStorageForPlayer(subject)
			return if subject == player then storage else nil
		end
		function adapter:GetRegisteredPlatforms(subject)
			return if subject == base then slots else nil
		end
		function adapter:TryRemoveFromPlatform(subject, platform, expectedId)
			for _, slot in slots do
				if slot.Platform == platform then
					local result = owner:CommitMutation(subject, function()
						local record, display, why = storage:RemovePlatformRecord(slot.Index, expectedId)
						if not record then
							return false, { ok = false, code = why }
						end
						if display then
							display:Destroy()
						end
						return true, { ok = true, record = record }
					end)
					return result.record, result.code
				end
			end
			return nil, "INVALID_PLATFORM"
		end
		function adapter:BindReturnedOwnedIndividual(_subject, slotId, id)
			table.insert(rebinds, id .. "@" .. slotId)
			return true, nil
		end

		local salePoint = Instance.new("Part")
		salePoint.Anchored = true
		salePoint.Size = Vector3.new(10, 1, 10)
		salePoint.CFrame = CFrame.new(15800, 100, 15800)
		salePoint.Parent = workspace
		table.insert(owned, salePoint)
		local character = Instance.new("Model")
		character.Parent = workspace
		table.insert(owned, character)
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Position = salePoint.Position + Vector3.new(0, 3, 0)
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = character
		player.Character = character

		Currency:_ResetForTests(owner)
		Banked:_ResetForTests({ Profile = owner, Currency = Currency })
		Banked:Start()
		local quoteCatalog = Catalog
		Sale:Init({
			Carry = {
				GetCarriedState = function()
					return nil
				end,
			},
			Currency = Currency,
			Catalog = {
				GetDefinition = function(id)
					return quoteCatalog.GetDefinition(id)
				end,
			},
			Banked = Banked,
			Storage = adapter,
			ResolveSalePoint = function()
				return salePoint
			end,
			Now = function()
				return 100
			end,
		})
		local ok, failure = xpcall(function()
			runFixture({
				Player = player,
				Profile = profile,
				Owner = owner,
				Storage = storage,
				Deposit = deposit,
				Rebinds = rebinds,
				Value = function(speciesId)
					return assert(Catalog.GetDefinition(speciesId)).sellValue
				end,
				SetQuoteCatalog = function(value)
					quoteCatalog = value
				end,
			})
		end, debug.traceback)
		Sale:Stop()
		Currency:_ResetForTests()
		Banked:_ResetForTests()
		storage:Destroy()
		for _, instance in owned do
			instance:Destroy()
		end
		assert(ok, failure)
	end

	describe("Bulk banked sale on the real profile, storage and wallet", function()
		it("removes ownership and the slot, credits the exact total, and keeps platform cash", function()
			fixture(function(f)
				f.Deposit("bulk-a", "BRT_007", 1)
				f.Deposit("bulk-b", "BRT_001", 2)
				f.Deposit("bulk-c", "BRT_011", 3)
				f.Profile.Economy.Balance = 1000.5
				f.Profile.Base.Slots["1"].accumulatedCash = 38
				f.Profile.Base.Slots["2"].accumulatedCash = 7.25
				local list = Sale:ListBanked(f.Player)
				expect(#list.rows).to.equal(3)
				local total = f.Value("BRT_007") + f.Value("BRT_001")
				local result = Sale:SellBanked(f.Player, { "bulk-a", "bulk-b" }, total)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("Sold")
				expect(result.paid).to.equal(total)
				expect(f.Profile.Economy.Balance).to.equal(1000.5 + total)
				expect(f.Profile.Collection.BrainrotInstances["bulk-a"]).to.equal(nil)
				expect(f.Profile.Collection.BrainrotInstances["bulk-b"]).to.equal(nil)
				expect(f.Profile.Collection.BrainrotInstances["bulk-c"] ~= nil).to.equal(true)
				expect(f.Profile.Base.Slots["1"].brainrotId).to.equal(nil)
				expect(f.Profile.Base.Slots["2"].brainrotId).to.equal(nil)
				expect(f.Profile.Base.Slots["3"].brainrotId).to.equal("bulk-c")
				-- platform cash belongs to the platform, not the brainrot
				expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(38)
				expect(f.Profile.Base.Slots["2"].accumulatedCash).to.equal(7.25)
				expect(f.Storage:GetOccupiedCount()).to.equal(1)
				expect(#f.Rebinds).to.equal(0)
				-- the sale asked for a save, and the saved snapshot agrees
				expect(#f.Owner.SaveRequests > 0).to.equal(true)
				local saved = assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
				expect(saved.Collection.BrainrotInstances["bulk-a"]).to.equal(nil)
				expect(saved.Economy.Balance).to.equal(1000.5 + total)
				-- the same request again pays nothing
				expect(Sale:SellBanked(f.Player, { "bulk-a", "bulk-b" }, total).code).to.equal("NotOnPlatform")
				expect(f.Profile.Economy.Balance).to.equal(1000.5 + total)
			end)
		end)

		it("pays a mutated brainrot its multiplied value and refuses the un-multiplied total", function()
			fixture(function(f)
				f.Deposit("bulk-shiny", "BRT_011", 1, "Shiny")
				local plain = f.Value("BRT_011")
				expect(Sale:SellBanked(f.Player, { "bulk-shiny" }, plain).code).to.equal("QuoteChanged")
				expect(f.Profile.Collection.BrainrotInstances["bulk-shiny"] ~= nil).to.equal(true)
				local quoted = Sale:ListBanked(f.Player).rows[1].sellValue
				expect(quoted).to.equal(plain * 1.5)
				local before = f.Profile.Economy.Balance
				expect(Sale:SellBanked(f.Player, { "bulk-shiny" }, quoted).ok).to.equal(true)
				expect(f.Profile.Economy.Balance).to.equal(before + quoted)
			end)
		end)

		it("a favourite is saved on the owned brainrot and cannot be sold by either path", function()
			fixture(function(f)
				local item = f.Deposit("fav-a", "BRT_007", 1)
				f.Deposit("fav-b", "BRT_001", 2)
				local before = f.Profile.Economy.Balance
				-- only the player's own banked brainrots, only a real boolean
				expect(Banked:SetFavourite(f.Player, "not-mine", true).code).to.equal("NOT_OWNED")
				expect(Banked:SetFavourite(f.Player, "fav-a", "yes").code).to.equal("INVALID_REQUEST")
				expect(Banked:SetFavourite(f.Player, 7, true).code).to.equal("INVALID_REQUEST")
				expect(Banked:IsFavourite(f.Player, "fav-a")).to.equal(false)

				local set = Banked:SetFavourite(f.Player, "fav-a", true)
				expect(set.ok).to.equal(true)
				expect(set.committed).to.equal(true)
				expect(f.Profile.Collection.BrainrotInstances["fav-a"].favourite).to.equal(true)
				expect(Banked:IsFavourite(f.Player, "fav-a")).to.equal(true)
				expect(Banked:GetFavourites(f.Player)["fav-a"]).to.equal(true)
				expect(Banked:GetFavourites(f.Player)["fav-b"]).to.equal(nil)
				local again = Banked:SetFavourite(f.Player, "fav-a", true)
				expect(again.ok).to.equal(true)
				expect(again.code).to.equal("UNCHANGED")
				-- it is part of the saved profile
				local saved = assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
				expect(saved.Collection.BrainrotInstances["fav-a"].favourite).to.equal(true)
				expect(saved.Collection.BrainrotInstances["fav-b"].favourite).to.equal(nil)

				-- bulk path: listed as a favourite, and the batch is refused whole
				local list = Sale:ListBanked(f.Player)
				expect(list.rows[1].favourite).to.equal(true)
				local total = f.Value("BRT_007") + f.Value("BRT_001")
				expect(Sale:SellBanked(f.Player, { "fav-a", "fav-b" }, total).code).to.equal("Favourite")
				expect(f.Profile.Economy.Balance).to.equal(before)
				expect(f.Profile.Base.Slots["1"].brainrotId).to.equal("fav-a")
				expect(f.Profile.Base.Slots["2"].brainrotId).to.equal("fav-b")

				-- carried path: off its platform, the same owned record still refuses the sale
				assert(f.Storage:RemovePlatformRecord(1, "fav-a"))
				local eligible, reason = Banked:ValidateSaleRecord(f.Player, item)
				expect(eligible).to.equal(false)
				expect(reason).to.equal("FAVOURITE")
				local refused = Banked:TryCommitSale(f.Player, item, f.Value("BRT_007"), true, Catalog)
				expect(refused.committed).to.equal(false)
				expect(refused.code).to.equal("FAVOURITE")
				expect(f.Profile.Economy.Balance).to.equal(before)
				expect(f.Profile.Collection.BrainrotInstances["fav-a"] ~= nil).to.equal(true)

				-- unstarred, it sells; the flag is gone from the save, not stored as false
				expect(Banked:SetFavourite(f.Player, "fav-a", false).committed).to.equal(true)
				expect(f.Profile.Collection.BrainrotInstances["fav-a"].favourite).to.equal(nil)
				expect(Banked:TryCommitSale(f.Player, item, f.Value("BRT_007"), true, Catalog).committed).to.equal(true)
				expect(f.Profile.Economy.Balance).to.equal(before + f.Value("BRT_007"))
			end)
		end)

		it("the profile schema accepts only an absent or true favourite", function()
			fixture(function(f)
				f.Deposit("fav-c", "BRT_001", 1)
				local record = f.Profile.Collection.BrainrotInstances["fav-c"]
				expect(ProfileSchema.ValidateLoaded(f.Profile)).to.equal(true)
				record.favourite = true
				expect(ProfileSchema.ValidateLoaded(f.Profile)).to.equal(true)
				for _, bad in { false, "true", 1, {} } do
					record.favourite = bad
					local valid, why = ProfileSchema.ValidateLoaded(f.Profile)
					expect(valid).to.equal(false)
					expect(why).to.equal("INVALID_INDIVIDUAL_FAVOURITE")
				end
				record.favourite = nil
				expect(ProfileSchema.ValidateLoaded(f.Profile)).to.equal(true)
			end)
		end)

		it("returns a refused brainrot to a platform, still owned, with nothing paid for it", function()
			fixture(function(f)
				f.Deposit("bulk-a", "BRT_007", 1)
				f.Deposit("bulk-b", "BRT_001", 2)
				local total = f.Value("BRT_007") + f.Value("BRT_001")
				-- the wallet cannot take the second credit
				local limit = require(script.Parent.Parent.Config.PlayerDataConfig).MaxBalance
				f.Profile.Economy.Balance = limit - f.Value("BRT_007") - 1
				local result = Sale:SellBanked(f.Player, { "bulk-a", "bulk-b" }, total)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("PartlySold")
				expect(result.sold).to.equal(1)
				expect(result.stoppedBy).to.equal("BALANCE_OVERFLOW")
				expect(f.Profile.Economy.Balance).to.equal(limit - 1)
				expect(f.Profile.Collection.BrainrotInstances["bulk-a"]).to.equal(nil)
				-- bulk-b: still owned and back in the first free slot
				expect(f.Profile.Collection.BrainrotInstances["bulk-b"] ~= nil).to.equal(true)
				expect(f.Profile.Base.Slots["1"].brainrotId).to.equal("bulk-b")
				expect(f.Rebinds[1]).to.equal("bulk-b@1")
			end)
		end)
	end)
end
