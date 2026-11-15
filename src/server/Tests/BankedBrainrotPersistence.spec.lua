--!nocheck

return function()
	local Players = game:GetService("Players")
	local ProfileSchema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)

	local function fixture(runFixture)
		local player = { UserId = 74002, Name = "BankedSpec", Parent = Players }
		local profile = ProfileSchema.CreateDefault()
		local owner = {
			Data = profile,
			Revision = 0,
			SavedRevision = 0,
			SaveRequests = {},
			SaveListeners = {},
			DiagnosticListeners = {},
			SessionCurrent = true,
		}
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
			return {
				currentRevision = self.Revision,
				lastConfirmedSavedRevision = self.SavedRevision,
			}
		end
		function owner:GetSessionHandle(subject)
			return if self:IsWritable(subject)
				then { Player = subject, UserId = subject.UserId, Generation = 1 }
				else nil
		end
		function owner:IsCurrentSessionHandle(handle)
			return self.SessionCurrent
				and handle ~= nil
				and handle.Player == player
				and handle.UserId == player.UserId
				and handle.Generation == 1
		end
		function owner:RequestSave(subject, reason)
			if not self:IsWritable(subject) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			table.insert(self.SaveRequests, { reason = reason, revision = self.Revision })
			return { ok = true, code = if #self.SaveRequests > 1 then "COALESCED" else "SCHEDULED" }
		end
		function owner:SubscribeSaveConfirmed(callback)
			local token = {}
			self.SaveListeners[token] = callback
			return {
				Disconnect = function()
					self.SaveListeners[token] = nil
				end,
			}
		end
		function owner:SubscribeDiagnostics(callback)
			local token = {}
			self.DiagnosticListeners[token] = callback
			return {
				Disconnect = function()
					self.DiagnosticListeners[token] = nil
				end,
			}
		end
		function owner:Confirm(revision)
			self.SavedRevision = math.max(self.SavedRevision, revision)
			for _, callback in self.SaveListeners do
				callback(player, self.SavedRevision, self.Revision)
			end
		end
		function owner:EmitDiagnostic(receipt)
			for _, callback in self.DiagnosticListeners do
				callback(player, receipt)
			end
		end
		function owner:BeginClosing()
			return true
		end

		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "BankedSpecBase")
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
		local function deposit(id, speciesId, slotIndex)
			local item = {
				ItemId = id,
				BrainrotId = speciesId,
				Metadata = { DurableOwnerUserId = player.UserId },
			}
			local reservation = assert(storage:TryReserveSlot(id, slotIndex))
			assert(storage:CommitReservation(reservation, item, Instance.new("Model")))
			return item
		end

		Currency:_ResetForTests(owner)
		Banked:_ResetForTests({ Profile = owner, Currency = Currency })
		Banked:Start()
		local ok, failure = xpcall(function()
			runFixture({
				Player = player,
				Profile = profile,
				Owner = owner,
				Storage = storage,
				Deposit = deposit,
			})
		end, debug.traceback)
		Currency:_ResetForTests()
		Banked:_ResetForTests()
		storage:Destroy()
		base:Destroy()
		assert(ok, failure)
	end

	describe("Phase 8 successful banking proof", function()
		it("records one Uncommon proof at deposit and keeps it through lifting and sale", function()
			fixture(function(f)
				local item=f.Deposit("uncommon-a","BRT_011",1)
				local proof=f.Profile.WorldProgression.BankedSpecies.BRT_011
				expect(proof.rarityAtFirstBank).to.equal("Uncommon")
				expect(proof.source).to.equal("deposit")
				f.Deposit("uncommon-b","BRT_011",2)
				local count=0 for _ in f.Profile.WorldProgression.BankedSpecies do count+=1 end
				expect(count).to.equal(1)
				assert(f.Storage:RemovePlatformRecord(1,item.ItemId))
				expect(Banked:TryCommitSale(f.Player,item,360000).ok).to.equal(true)
				expect(f.Profile.WorldProgression.BankedSpecies.BRT_011).to.equal(proof)
				local saved=assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
				expect(saved.WorldProgression.BankedSpecies.BRT_011.rarityAtFirstBank).to.equal("Uncommon")
			end)
		end)
		it("does not grant proof for a full-base attempt or invalid reservation", function()
			fixture(function(f)
				for index=1,12 do f.Deposit("full-"..index,"BRT_007",index) end
				expect(f.Storage:TryReserveSlot("not-banked")).to.equal(nil)
				local display=Instance.new("Model")
				expect(f.Storage:CommitReservation({}, {ItemId="not-banked",BrainrotId="BRT_011",Metadata={}},display)).to.equal(false)
				display:Destroy()
				expect(f.Profile.WorldProgression.BankedSpecies.BRT_011).to.equal(nil)
			end)
		end)
	end)

	describe("Phase 7A-2 banked individual and base persistence", function()
		it("keeps two same-species individuals distinct across remove and redeposit", function()
			fixture(function(f)
				local a = f.Deposit("durable-a", "BRT_007", 1)
				f.Deposit("durable-b", "BRT_007", 2)
				expect(f.Profile.Collection.BrainrotInstances["durable-a"].speciesId).to.equal(
					"BRT_007"
				)
				expect(f.Profile.Collection.BrainrotInstances["durable-b"].speciesId).to.equal(
					"BRT_007"
				)
				expect(f.Profile.Base.Slots["1"].brainrotId).to.equal("durable-a")
				expect(f.Profile.Base.Slots["2"].brainrotId).to.equal("durable-b")

				assert(f.Storage:SetUnclaimedCashExact(1, 27.75))
				local removed = assert(f.Storage:RemovePlatformRecord(1, a.ItemId))
				expect(removed.ItemId).to.equal("durable-a")
				expect(f.Profile.Collection.BrainrotInstances["durable-a"] ~= nil).to.equal(true)
				expect(f.Profile.Base.Slots["1"].brainrotId).to.equal(nil)
				expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(27.75)

				local reservation = assert(f.Storage:TryReserveSlot("durable-a", 3))
				assert(f.Storage:CommitReservation(reservation, removed, Instance.new("Model")))
				expect(f.Profile.Base.Slots["3"].brainrotId).to.equal("durable-a")
				local count = 0
				for _ in f.Profile.Collection.BrainrotInstances do
					count += 1
				end
				expect(count).to.equal(2)
			end)
		end)

		it("preserves an unavailable legacy slot and exact earnings during initial owned-location recovery", function()
			fixture(function(f)
				local owned = {speciesId="BRT_007",metadata={source="legacy"}}
				local slot = {brainrotId="legacy-locked",accumulatedCash=18.375}
				f.Profile.Collection.BrainrotInstances["legacy-locked"] = owned
				f.Profile.Base.Slots["48"] = slot
				local result = Banked:ReconcileInitialOwnedLocations(f.Player, f.Owner)
				expect(result.ok).to.equal(true)
				expect(result.returnedCount).to.equal(0)
				expect(result.destroyedCount).to.equal(0)
				expect(f.Profile.Base.Slots["48"]).to.equal(slot)
				expect(slot.brainrotId).to.equal("legacy-locked")
				expect(slot.accumulatedCash).to.equal(18.375)
				expect(f.Profile.Collection.BrainrotInstances["legacy-locked"]).to.equal(owned)
				for index=1,12 do expect(f.Profile.Base.Slots[tostring(index)].brainrotId).to.equal(nil) end
				expect(f.Profile.Economy.Balance).to.equal(0)
			end)
		end)
		it("round-trips all twelve occupants, slot cash and unassigned ownership", function()
			fixture(function(f)
				for index = 1, 12 do
					f.Deposit("roundtrip-" .. index, "BRT_007", index)
					f.Profile.Base.Slots[tostring(index)].accumulatedCash = index + 0.25
				end
				f.Profile.Collection.BrainrotInstances.unassigned = { speciesId = "BRT_999" }
				local snapshot = assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
				local restored = assert(ProfileSchema.Migrate(snapshot))
				for index = 1, 12 do
					expect(restored.Base.Slots[tostring(index)].brainrotId).to.equal(
						"roundtrip-" .. index
					)
					expect(restored.Base.Slots[tostring(index)].accumulatedCash).to.equal(
						index + 0.25
					)
				end
				expect(restored.Collection.BrainrotInstances.unassigned.speciesId).to.equal(
					"BRT_999"
				)
			end)
		end)

		it("collects profile slot cash and wallet together in one revision", function()
			fixture(function(f)
				f.Profile.Economy.Balance = 1000.5
				f.Profile.Base.Slots["1"].accumulatedCash = 120.25
				local result = Currency:TryCreditWithSource(
					f.Player,
					120.25,
					"PlatformIncomeClaim",
					function(data)
						if data.Base.Slots["1"].accumulatedCash ~= 120.25 then
							return false, "SOURCE_CHANGED"
						end
						data.Base.Slots["1"].accumulatedCash = 0
						return true
					end
				)
				expect(result.ok).to.equal(true)
				expect(f.Profile.Economy.Balance).to.equal(1120.75)
				expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(0)
				expect(f.Owner.Revision).to.equal(1)
			end)
		end)

		it(
			"sells only the exact unassigned individual without collecting retained slot cash",
			function()
				fixture(function(f)
					local a = f.Deposit("sale-a", "BRT_007", 1)
					f.Deposit("sale-b", "BRT_007", 2)
					f.Profile.Economy.Balance = 1120.75
					f.Profile.Base.Slots["1"].accumulatedCash = 38
					assert(f.Storage:RemovePlatformRecord(1, a.ItemId))
					local result = Banked:TryCommitSale(f.Player, a, 120)
					expect(result.ok).to.equal(true)
					expect(f.Profile.Economy.Balance).to.equal(1240.75)
					expect(f.Profile.Collection.BrainrotInstances["sale-a"]).to.equal(nil)
					expect(f.Profile.Collection.BrainrotInstances["sale-b"] ~= nil).to.equal(true)
					expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(38)
					expect(f.Profile.Base.Slots["2"].brainrotId).to.equal("sale-b")
					local second = Banked:TryCommitSale(f.Player, a, 120)
					expect(second.ok).to.equal(false)
					expect(second.code).to.equal("OWNERSHIP_INCONSISTENT")
					local snapshot = assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
					expect(snapshot.Collection.BrainrotInstances["sale-a"]).to.equal(nil)
					expect(snapshot.Economy.Balance).to.equal(1240.75)
				end)
			end
		)

		it("rejects a fresh sale and preserves valid legacy owned provenance with an empty platform", function()
			fixture(function(f)
				local fresh = { ItemId = "fresh-sale", BrainrotId = "BRT_007", Metadata = {} }
				local before = f.Profile.Economy.Balance
				expect(Banked:TryCommitSale(f.Player, fresh, 120).code).to.equal("BANK_FIRST")
				expect(Banked:TryCommitSale(f.Player, fresh, 0).code).to.equal("BANK_FIRST")
				expect(Banked:ClassifyRecord(f.Player, fresh)).to.equal("FreshUnbanked")
				expect(f.Profile.Economy.Balance).to.equal(before)
				f.Profile.Collection.BrainrotInstances["legacy-owned"] = { speciesId = "BRT_007", metadata = {} }
				local legacy = { ItemId = "legacy-owned", BrainrotId = "BRT_007", Metadata = {} }
				expect(Banked:ClassifyRecord(f.Player, legacy)).to.equal("Banked")
				expect(Banked:ValidateSaleRecord(f.Player, legacy)).to.equal(true)
				f.Profile.Collection.BrainrotInstances["malformed"] = { speciesId = "UNKNOWN" }
				expect(Banked:ClassifyRecord(f.Player, { ItemId = "malformed", BrainrotId = "BRT_007" })).to.equal("Uncertain")
			end)
		end)

		it("removes banked ownership even when the configured payout is zero", function()
			fixture(function(f)
				local zero = f.Deposit("zero-sale", "BRT_007", 1)
				assert(f.Storage:RemovePlatformRecord(1, zero.ItemId))
				local result = Banked:TryCommitSale(f.Player, zero, 0)
				expect(result.ok).to.equal(true)
				expect(f.Profile.Collection.BrainrotInstances["zero-sale"]).to.equal(nil)
				expect(f.Profile.Economy.Balance).to.equal(0)
			end)
		end)

		it(
			"returns an owned carried individual to the first free logical slot without moving cash",
			function()
				fixture(function(f)
					local item = f.Deposit("return-me", "BRT_007", 3)
					f.Profile.Base.Slots["1"].accumulatedCash = 8.75
					f.Profile.Base.Slots["3"].accumulatedCash = 27.5
					assert(f.Storage:RemovePlatformRecord(3, item.ItemId))
					local result = Banked:ReturnOwnedToAvailableSlot(f.Player, item)
					expect(result.ok).to.equal(true)
					expect(result.slotId).to.equal("1")
					expect(f.Profile.Base.Slots["1"].brainrotId).to.equal("return-me")
					expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(8.75)
					expect(f.Profile.Base.Slots["3"].accumulatedCash).to.equal(27.5)
					expect(f.Profile.Collection.BrainrotInstances["return-me"] ~= nil).to.equal(
						true
					)
				end)
			end
		)

		it("destroys ownership and every saved location coherently without payout", function()
			fixture(function(f)
				local item = f.Deposit("departing", "BRT_007", 2)
				f.Profile.Base.Slots["2"].accumulatedCash = 19.25
				local result = Banked:DestroyOwned(f.Player, item)
				expect(result.ok).to.equal(true)
				expect(f.Profile.Collection.BrainrotInstances.departing).to.equal(nil)
				expect(f.Profile.Base.Slots["2"].brainrotId).to.equal(nil)
				expect(f.Profile.Base.Slots["2"].accumulatedCash).to.equal(19.25)
				expect(f.Profile.Economy.Balance).to.equal(0)
			end)
		end)

		it(
			"returns banked carry and cargo in one logout revision while releasing fresh cargo locally",
			function()
				fixture(function(f)
					local carried = f.Deposit("logout-carried", "BRT_007", 3)
					local cargo = f.Deposit("logout-cargo", "BRT_007", 4)
					assert(f.Storage:RemovePlatformRecord(3, carried.ItemId))
					assert(f.Storage:RemovePlatformRecord(4, cargo.ItemId))
					f.Profile.Base.Slots["1"].accumulatedCash = 8.75
					local fresh = { ItemId = "fresh-cargo", BrainrotId = "BRT_007", Metadata = {} }
					local result = Banked:ApplyLogoutOutcomes(f.Player, carried, { cargo, fresh })
					expect(result.ok).to.equal(true)
					expect(result.revision).to.equal(1)
					expect(result.outcomes[carried.ItemId].action).to.equal("ReturnToAvailableSlot")
					expect(result.outcomes[cargo.ItemId].action).to.equal("ReturnToAvailableSlot")
					expect(result.outcomes[fresh.ItemId].action).to.equal(
						"PublishExistingWorldDrop"
					)
					expect(f.Profile.Base.Slots["1"].brainrotId).to.equal(carried.ItemId)
					expect(f.Profile.Base.Slots["1"].accumulatedCash).to.equal(8.75)
					expect(f.Profile.Collection.BrainrotInstances[cargo.ItemId] ~= nil).to.equal(true)
				end)
			end
		)

		it(
			"retains a banked carried individual unassigned on full-base logout",
			function()
				fixture(function(f)
					for index = 1, 12 do
						f.Deposit("occupied-" .. index, "BRT_007", index)
					end
					local carried = { ItemId = "full-base-carry", BrainrotId = "BRT_007" }
					f.Profile.Collection.BrainrotInstances[carried.ItemId] =
						{ speciesId = "BRT_007" }
					local result = Banked:ApplyLogoutOutcomes(f.Player, carried, {})
					expect(result.ok).to.equal(true)
					expect(result.outcomes[carried.ItemId].action).to.equal("PreserveOwnedUnassigned")
					expect(f.Profile.Collection.BrainrotInstances[carried.ItemId] ~= nil).to.equal(true)
					for index = 1, 12 do
						expect(f.Profile.Base.Slots[tostring(index)].brainrotId).to.equal(
							"occupied-" .. index
						)
					end
				end)
			end
		)

		it("publishes a relinquished individual only after a save covers its revision", function()
			fixture(function(f)
				local item = f.Deposit("release-me", "BRT_007", 4)
				local published = 0
				local pending = Banked:BeginConfirmedRelease(f.Player, item, function(operation)
					published += 1
					expect(operation.IndividualId).to.equal("release-me")
					return true
				end)
				expect(pending.ok).to.equal(true)
				expect(pending.code).to.equal("RELEASE_PENDING")
				expect(f.Profile.Collection.BrainrotInstances["release-me"]).to.equal(nil)
				expect(f.Profile.Base.Slots["4"].brainrotId).to.equal(nil)
				expect(published).to.equal(0)

				local duplicate = Banked:BeginConfirmedRelease(f.Player, item, function()
					published += 100
					return true
				end)
				expect(duplicate.code).to.equal("RELEASE_ALREADY_PENDING")
				expect(#f.Owner.SaveRequests).to.equal(1)

				f.Owner:Confirm(pending.revision - 1)
				expect(published).to.equal(0)
				-- A later coalesced snapshot may cover the release directly; no
				-- additional release-specific save cycle is required.
				f.Owner:Confirm(pending.revision + 2)
				expect(published).to.equal(1)
				f.Owner:Confirm(pending.revision + 3)
				expect(published).to.equal(1)
			end)
		end)

		it(
			"waits through a lost acknowledgement until verification confirms the durable revision",
			function()
				fixture(function(f)
					local item = f.Deposit("ambiguous-release", "BRT_007", 5)
					local published = 0
					local pending = Banked:BeginConfirmedRelease(f.Player, item, function()
						published += 1
						return true
					end)
					expect(pending.ok).to.equal(true)
					-- The backend may have committed while its response was lost. Without
					-- the profile owner's verified confirmation, publication remains private.
					f.Owner.SavedRevision = pending.revision
					Banked:ProcessConfirmedReleases()
					expect(published).to.equal(0)
					f.Owner:Confirm(pending.revision)
					expect(published).to.equal(1)
					Banked:ProcessConfirmedReleases()
					expect(published).to.equal(1)
				end)
			end
		)

		it("does not publish after the captured profile session loses ownership", function()
			fixture(function(f)
				local item = f.Deposit("stale-release", "BRT_007", 6)
				local published, unconfirmed = 0, 0
				local pending = Banked:BeginConfirmedRelease(f.Player, item, function()
					published += 1
					return true
				end, function()
					unconfirmed += 1
				end)
				f.Owner.SessionCurrent = false
				f.Owner:EmitDiagnostic({ kind = "SessionLost", code = "OWNERSHIP_LOST" })
				f.Owner:Confirm(pending.revision + 1)
				Banked:ProcessConfirmedReleases()
				expect(published).to.equal(0)
				expect(unconfirmed).to.equal(1)
				expect(Banked:IsReleasePending(f.Player, item.ItemId)).to.equal(false)
			end)
		end)

		it("retries confirmed publication without another ownership mutation or save", function()
			fixture(function(f)
				local item = f.Deposit("publication-retry", "BRT_007", 7)
				local attempts = 0
				local pending = Banked:BeginConfirmedRelease(f.Player, item, function()
					attempts += 1
					return attempts >= 2, "INJECTED_PUBLICATION_FAILURE"
				end)
				local revision = f.Owner.Revision
				f.Owner:Confirm(pending.revision)
				expect(attempts).to.equal(1)
				expect(Banked:IsReleasePending(f.Player, item.ItemId)).to.equal(true)
				Banked:ProcessConfirmedReleases()
				expect(attempts).to.equal(2)
				expect(Banked:IsReleasePending(f.Player, item.ItemId)).to.equal(false)
				expect(f.Owner.Revision).to.equal(revision)
				expect(#f.Owner.SaveRequests).to.equal(1)
			end)
		end)

		it(
			"finishes one already-confirmed relinquishment after its former player departs",
			function()
				fixture(function(f)
					local item = f.Deposit("confirmed-detached", "BRT_007", 8)
					local attempts, publications = 0, 0
					local pending = Banked:BeginConfirmedRelease(f.Player, item, function(operation)
						attempts += 1
						expect(operation.IndividualId).to.equal(item.ItemId)
						if attempts == 1 then
							return false, "STAGED_ROUTE_NOT_READY"
						end
						publications += 1
						return true
					end)
					f.Owner:Confirm(pending.revision)
					expect(publications).to.equal(0)
					local confirmed = assert(ProfileSchema.CreateSaveSnapshot(f.Profile))
					f.Player.Parent = nil
					f.Owner.SessionCurrent = false
					f.Owner:EmitDiagnostic({ kind = "SessionLost", code = "FORMER_PLAYER_DEPARTED" })
					Banked:ProcessConfirmedReleases()
					Banked:ProcessConfirmedReleases()
					expect(attempts).to.equal(2)
					expect(publications).to.equal(1)
					expect(Banked:IsReleasePending(f.Player, item.ItemId)).to.equal(false)
					expect(confirmed.Collection.BrainrotInstances[item.ItemId]).to.equal(nil)
					expect(f.Profile.Collection.BrainrotInstances[item.ItemId]).to.equal(nil)
					expect(f.Profile.Base.Slots["8"].brainrotId).to.equal(nil)
					expect(f.Owner.Revision).to.equal(pending.revision)
					expect(#f.Owner.SaveRequests).to.equal(1)
				end)
			end
		)
	end)
end
