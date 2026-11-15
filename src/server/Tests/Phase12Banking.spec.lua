--!nocheck
-- Native storage/profile integration fixtures, not connected-player evidence.
return function()
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Storage = require(script.Parent.Parent.Classes.BaseStorage)
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Rules = require(game.ReplicatedStorage.Shared.Utility.Phase12Rules)

	local function fixture(callback)
		local player = { UserId = 120012, Name = "Phase12BankFixture", Parent = game:GetService("Players") }
		local data = Schema.CreateDefault()
		local generation = 1
		local writable = true
		local owner = {}
		function owner:IsWritable(subject)
			return writable and subject == player
		end
		function owner:GetReadableData(subject)
			return if self:IsWritable(subject) then data else nil
		end
		function owner:GetWritableData(subject)
			return self:GetReadableData(subject)
		end
		function owner:GetSessionHandle(subject)
			return if self:IsWritable(subject) then { Generation = generation, UserId = subject.UserId } else nil
		end
		function owner:CommitMutation(subject, mutator)
			if not self:IsWritable(subject) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutator(data)
			if committed then
				result.ok, result.committed = true, true
			end
			return result
		end
		function owner:RequestSave(_subject, _reason)
			return { ok = true, state = "FixtureSaveRequested" }
		end
		local upgrades = {}
		function upgrades:GetMeasurementOffers()
			return {
				{ offerId = "UPG_Z", price = 100, ready = true, prerequisitesSatisfied = true, owned = false },
				{ offerId = "UPG_A", price = 100, ready = true, prerequisitesSatisfied = true, owned = false },
				{ offerId = "UPG_LOCKED", price = 1, ready = true, prerequisitesSatisfied = false, owned = false },
				{ offerId = "UPG_OWNED", price = 1, ready = true, prerequisitesSatisfied = true, owned = true },
			}
		end
		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "Phase12BankFixture")
		local slots = {}
		for index = 1, 12 do
			local platform = Instance.new("Part")
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Parent = platform
			slots[index] = { Index = index, Platform = platform, Marker = marker }
		end
		local storage = Storage.new(base, player.UserId, slots, data)
		local function deposit(id, species, mutation, slot)
			local item = { ItemId = id, BrainrotId = species, Metadata = { MutationId = mutation or "None" } }
			local token = assert(storage:TryReserveSlot(id, slot))
			assert(storage:CommitReservation(token, item, Instance.new("Model"), Banked:GetBankContext(player)))
			local receipt = storage:TakeBankReceipt(id)
			Banked:OnBankCommitted(player, receipt)
			return item, receipt
		end
		Currency:_ResetForTests(owner)
		Banked:_ResetForTests({ Profile = owner, Currency = Currency, Upgrades = upgrades })
		local ok, reason = xpcall(function()
			callback({
				player = player,
				data = data,
				storage = storage,
				deposit = deposit,
				setWritable = function(value)
					writable = value
				end,
				newSession = function()
					generation += 1
				end,
			})
		end, debug.traceback)
		Banked:_ResetForTests()
		Currency:_ResetForTests()
		storage:Destroy()
		base:Destroy()
		assert(ok, reason)
	end

	describe("Phase 12 banking and values", function()
		it("stores Common, Uncommon and duplicates with only the configured retention payout", function()
			fixture(function(f)
				f.deposit("common-a", "BRT_007", "None", 1)
				f.deposit("common-b", "BRT_007", "None", 2)
				f.deposit("uncommon", "BRT_011", "Golden", 3)
				expect(f.storage:GetOccupiedCount()).to.equal(3)
				-- First banks themselves have no sale payout; three deliveries and two
				-- distinct species legitimately cross the existing 3U+2U milestones.
				expect(f.data.Retention.Day.bring_them_home.count).to.equal(3)
				expect(f.data.Retention.Day.bring_them_home.paid).to.equal(true)
				expect(f.data.Retention.Day.bring_them_home.paidCash).to.equal(750000000)
				expect(f.data.Retention.Day.field_research.count).to.equal(2)
				expect(f.data.Retention.Day.field_research.paid).to.equal(true)
				expect(f.data.Retention.Day.field_research.paidCash).to.equal(500000000)
				expect(f.data.Economy.Balance).to.equal(1250000000)
				expect(f.data.Retention.Day.camp_payday.paid).to.equal(false)
				expect(f.data.Retention.Supplies.lifetimeClaims).to.equal(0)
				expect(f.data.Collection.Species.BRT_007 ~= nil).to.equal(true)
				expect(f.data.Collection.SpeciesMutations.BRT_007.Normal ~= nil).to.equal(true)
				expect(f.data.Collection.SpeciesMutations.BRT_011.Golden ~= nil).to.equal(true)
				expect(
					f.data.Collection.BrainrotInstances["common-a"] ~= f.data.Collection.BrainrotInstances["common-b"]
				).to.equal(true)
			end)
		end)

		it("full storage and invalid reservations retain the original exact source and no bank receipt", function()
			fixture(function(f)
				for index = 1, 12 do
					f.deposit("full-" .. index, "BRT_007", "None", index)
				end
				local beforeCash = f.data.Economy.Balance
				expect(beforeCash).to.equal(750000000)
				expect(f.data.Retention.Day.bring_them_home.count).to.equal(3)
				expect(f.data.Retention.Day.bring_them_home.paidCash).to.equal(750000000)
				expect(f.data.Retention.Day.field_research.count).to.equal(1)
				expect(f.data.Retention.Day.field_research.paid).to.equal(false)
				local source = {
					ItemId = "retained",
					BrainrotId = "BRT_011",
					Metadata = { MutationId = "Astral" },
					World = { ReservationId = "same-reservation", RemainingHp = 0, EscapeAttemptsUsed = 1 },
				}
				expect(f.storage:TryReserveSlot(source.ItemId)).to.equal(nil)
				local display = Instance.new("Model")
				expect(f.storage:CommitReservation({}, source, display)).to.equal(false)
				display:Destroy()
				expect(source.World.ReservationId).to.equal("same-reservation")
				expect(source.Metadata.DurableOwnerUserId).to.equal(nil)
				expect(f.data.Collection.BrainrotInstances.retained).to.equal(nil)
				expect(f.storage:TakeBankReceipt(source.ItemId)).to.equal(nil)
				expect(f.data.Collection.Species.BRT_011).to.equal(nil)
				expect(f.data.Economy.Balance).to.equal(beforeCash)
				expect(f.data.Retention.Day.bring_them_home.count).to.equal(3)
				expect(f.data.Retention.Day.field_research.count).to.equal(1)
			end)
		end)

		it("rejects an unknown runtime mutation before creating owned data or discovery", function()
			fixture(function(f)
				local item =
					{ ItemId = "invalid-mutation", BrainrotId = "BRT_007", Metadata = { MutationId = "Unknown" } }
				local token = assert(f.storage:TryReserveSlot(item.ItemId, 1))
				local display = Instance.new("Model")
				local committed, reason = f.storage:CommitReservation(token, item, display)
				expect(committed).to.equal(false)
				expect(reason).to.equal("INVALID_MUTATION")
				expect(f.data.Collection.BrainrotInstances[item.ItemId]).to.equal(nil)
				expect(f.data.Collection.Species.BRT_007).to.equal(nil)
				expect(item.Metadata.MutationId).to.equal("Unknown")
				f.storage:CancelReservation(token)
				display:Destroy()
			end)
		end)

		it("uses base times mutation once after lift, rebank and native serialization", function()
			fixture(function(f)
				local item, receipt = f.deposit("golden", "BRT_007", "Golden", 1)
				local effective = Rules.EffectiveValues("BRT_007", "Golden")
				expect(receipt.cashPerSecond).to.equal(effective.cashPerSecond)
				local rate = Income.CalculateStorageRate(f.storage:GetSnapshot())
				expect(rate / 10).to.equal(effective.cashPerSecond)
				local removed = assert(f.storage:RemovePlatformRecord(1, item.ItemId))
				local token = assert(f.storage:TryReserveSlot(item.ItemId, 2))
				assert(f.storage:CommitReservation(token, removed, Instance.new("Model")))
				expect(f.storage:TakeBankReceipt(item.ItemId)).to.equal(nil)
				expect(Income.CalculateStorageRate(f.storage:GetSnapshot()) / 10).to.equal(effective.cashPerSecond)
				local restored = assert(Schema.Migrate(assert(Schema.CreateSaveSnapshot(f.data))))
				expect(restored.Collection.BrainrotInstances.golden.mutationId).to.equal("Golden")
				expect(restored.Collection.BrainrotInstances.golden.firstBankCompleted).to.equal(true)
				expect(restored.Collection.BrainrotInstances.golden.World).to.equal(nil)
			end)
		end)

		it("rejects fresh sale, stale mutation and stale price; pays an exact owned sale once", function()
			fixture(function(f)
				local fresh = { ItemId = "fresh", BrainrotId = "BRT_007", Metadata = { MutationId = "Golden" } }
				expect(Banked:TryCommitSale(f.player, fresh, 123).code).to.equal("BANK_FIRST")
				local item = f.deposit("sale", "BRT_007", "Shiny", 1)
				local value = Rules.EffectiveValues("BRT_007", "Shiny").sellValue
				local removed = assert(f.storage:RemovePlatformRecord(1, item.ItemId))
				expect(Banked:TryCommitSale(f.player, removed, value + 1, true).code).to.equal("QUOTE_CHANGED")
				removed.Metadata.MutationId = "Golden"
				expect(Banked:TryCommitSale(f.player, removed, value, true).code).to.equal("MUTATION_CHANGED")
				removed.Metadata.MutationId = "Shiny"
				f.data.Economy.Balance = 0.25
				assert(Banked:TryCommitSale(f.player, removed, value, true).ok, "Expected current exact owned sale")
				expect(f.data.Economy.Balance).to.equal(value + 0.25)
				expect(f.data.Collection.BrainrotInstances.sale).to.equal(nil)
				expect(f.data.Collection.SpeciesMutations.BRT_007.Shiny ~= nil).to.equal(true)
				expect(Banked:TryCommitSale(f.player, removed, value, true).ok).to.equal(false)
				expect(f.data.Economy.Balance).to.equal(value + 0.25)
			end)
		end)

		it("tracks exit-return expedition totals across transactions without rebank inflation", function()
			fixture(function(f)
				Banked:ObserveCampState(f.player, true)
				expect(Banked:GetBankContext(f.player)).to.equal(nil)
				Banked:ObserveCampState(f.player, false)
				expect(Banked:GetBankContext(f.player)).to.equal(nil)
				Banked:ObserveCampState(f.player, true)
				local first = f.deposit("haul-a", "BRT_007", "Golden", 1)
				local _, second = f.deposit("haul-b", "BRT_011", "None", 2)
				expect(second.expedition.haulCount).to.equal(2)
				expect(f.data.Progression.ExpeditionBest.haulCount).to.equal(2)
				local removed = assert(f.storage:RemovePlatformRecord(1, first.ItemId))
				assert(
					f.storage:CommitReservation(
						assert(f.storage:TryReserveSlot(first.ItemId, 3)),
						removed,
						Instance.new("Model"),
						Banked:GetBankContext(f.player)
					)
				)
				expect(f.storage:TakeBankReceipt(first.ItemId)).to.equal(nil)
				expect(Banked:GetBankContext(f.player).haulCount).to.equal(2)
				Banked:ObserveCampState(f.player, false)
				Banked:ObserveCampState(f.player, true)
				local _, weaker = f.deposit("next-haul", "BRT_007", "None", 1)
				expect(weaker.expedition.haulCount).to.equal(1)
				expect(weaker.recordImprovements.haulCount).to.equal(nil)
				expect(f.data.Progression.ExpeditionBest.haulCount).to.equal(2)
			end)
		end)

		it("selects cheapest eligible upgrade with ID tie-break and wallet-only shortfall", function()
			fixture(function(f)
				f.data.Economy.Balance = 12.5
				f.data.Base.Slots["1"].accumulatedCash = 99999
				local snapshot = Banked:GetProgressSnapshot(f.player)
				expect(snapshot.trackedUpgrade.offerId).to.equal("UPG_A")
				expect(snapshot.trackedUpgrade.shortfall).to.equal(87.5)
				f.setWritable(false)
				expect(Banked:GetProgressSnapshot(f.player)).to.equal(nil)
			end)
		end)
	end)

	describe("Phase 12 profile migration safety", function()
		it("maps only mutation Celestial to Astral, keeps rarity and unrelated data, then is idempotent", function()
			local data = Schema.CreateDefault()
			data.Collection.BrainrotInstances.a = {
				speciesId = "BRT_007",
				rarity = "Celestial",
				metadata = { MutationId = "Celestial", Note = "preserved" },
			}
			data.Collection.BrainrotInstances.b = { speciesId = "BRT_011" }
			data.Collection.Mutations = { Celestial = 123 }
			data.Collection.SpeciesMutations = { BRT_007 = { Celestial = 456 } }
			data.Economy.Balance = 42.25
			local migrated, reason, changed = Schema.Migrate(data)
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			expect(data.Collection.BrainrotInstances.a.metadata.MutationId).to.equal("Celestial")
			expect(migrated.Collection.BrainrotInstances.a.mutationId).to.equal("Astral")
			expect(migrated.Collection.BrainrotInstances.a.rarity).to.equal("Celestial")
			expect(migrated.Collection.BrainrotInstances.a.metadata.Note).to.equal("preserved")
			expect(migrated.Collection.BrainrotInstances.b.mutationId).to.equal("None")
			expect(migrated.Collection.Mutations.Astral).to.equal(123)
			expect(migrated.Collection.SpeciesMutations.BRT_007.Astral).to.equal(456)
			expect(migrated.Economy.Balance).to.equal(42.25)
			local _, _, changedAgain = Schema.Migrate(migrated)
			expect(changedAgain).to.equal(false)
		end)

		it("rejects malformed mutation/progress and unsupported newer saves without zero replacement", function()
			for _, invalid in { "Unknown", false, {}, 123 } do
				local data = Schema.CreateDefault()
				data.Collection.BrainrotInstances.a = { speciesId = "BRT_007", mutationId = invalid }
				local migrated, reason = Schema.Migrate(data)
				expect(migrated).to.equal(nil)
				expect(reason).to.equal("INVALID_OWNED_MUTATION")
			end
			local conflict = Schema.CreateDefault()
			conflict.Collection.BrainrotInstances.a =
				{ speciesId = "BRT_007", mutationId = "Golden", metadata = { MutationId = "Shiny" } }
			expect(select(2, Schema.Migrate(conflict))).to.equal("OWNED_MUTATION_CONFLICT")
			local newer = Schema.CreateDefault()
			newer.SchemaVersion = 999
			newer.Economy.Balance = 777
			expect(select(2, Schema.Migrate(newer))).to.equal("UNSUPPORTED_NEWER_SCHEMA")
			expect(newer.Economy.Balance).to.equal(777)
		end)
	end)
end
