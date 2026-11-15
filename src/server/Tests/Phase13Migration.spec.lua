--!nocheck
-- Synthetic records only; no live profile/storage access.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)
	local Values = require(RS.Shared.Utility.Phase12Rules)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local function historical()
		local data = Fixtures.FullProfile()
		data.Phase13 = nil
		data.Commerce = nil
		for i = 13, 48 do
			data.Base.Slots[tostring(i)] = nil
		end
		data.WorldReadyPlaytimeSeconds = 321.25
		data.ChariotTeam.PurchasedExtraSlots = 4
		return data
	end
	describe("Phase13 supported migration", function()
		it("preserves denomination-2 money and legacy identities while adding independent entitlements once", function()
			local source = historical()
			local before = Fixtures.Clone(source)
			local migrated, reason, changed = Schema.Migrate(source)
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			Fixtures.AssertDeepEqual(source, before)
			expect(migrated.CurrencyVersion).to.equal(2)
			expect(migrated.Economy.Balance).to.equal(1000.5)
			for i = 1, 12 do
				expect(migrated.Base.Slots[tostring(i)].accumulatedCash).to.equal(
					before.Base.Slots[tostring(i)].accumulatedCash
				)
			end
			expect(migrated.Base.Slots["1"].brainrotId).to.equal("synthetic-player-1:a")
			expect(migrated.Collection.BrainrotInstances["synthetic-player-1:c"].speciesId).to.equal("BRT_999")
			expect(migrated.Phase13.SpeedLevel).to.equal(1)
			expect(migrated.Phase13.CargoLevel).to.equal(1)
			expect(migrated.Phase13.SelectedWeaponId).to.equal("HRP_001")
			expect(migrated.Phase13.SelectedCartId).to.equal("CRT_001")
			expect(migrated.ChariotTeam.PurchasedExtraSlots).to.equal(4)
			expect(migrated.WorldReadyPlaytimeSeconds).to.equal(321.25)
			expect(migrated.Settings.Input.AimAssist).to.equal(true)
			expect(migrated.Progression.Upgrades.SYNTHETIC_UNKNOWN_UPGRADE).to.equal(true)
			expect(migrated.WorldProgression.BankedSpecies.BRT_007.source).to.equal("legacy_bank_record")
			expect(migrated.Commerce.Entitlements.INCOME_2X).to.equal(false)
			for i = 13, 48 do
				expect(migrated.Base.Slots[tostring(i)].brainrotId).to.equal(nil)
				expect(migrated.Base.Slots[tostring(i)].accumulatedCash).to.equal(0)
			end
			local snapshot = assert(Schema.CreateSaveSnapshot(migrated))
			local restored, againReason, againChanged = Schema.Migrate(snapshot)
			expect(againReason).to.equal(nil)
			expect(againChanged).to.equal(false)
			Fixtures.AssertDeepEqual(restored, migrated)
		end)
		it("keeps genuinely old currency x1500 once before Phase13, never x1M on saved money", function()
			local source = historical()
			source.CurrencyVersion = 1
			source.Economy.Balance = 12.25
			source.Base.Slots["1"].accumulatedCash = 7.5
			local migrated = assert(Schema.Migrate(source))
			expect(migrated.Economy.Balance).to.equal(18375)
			expect(migrated.Base.Slots["1"].accumulatedCash).to.equal(11250)
			local again, reason, changed = Schema.Migrate(assert(Schema.CreateSaveSnapshot(migrated)))
			expect(reason).to.equal(nil)
			expect(changed).to.equal(false)
			expect(again.Economy.Balance).to.equal(18375)
			expect(again.Base.Slots["1"].accumulatedCash).to.equal(11250)
		end)
		it("starts at12 with48 durable logical slots and preserves unavailable legacy value without spending it", function()
			local data = Schema.CreateDefault()
			local count = 0
			for _ in data.Base.Slots do
				count += 1
			end
			expect(count).to.equal(48)
			expect(Rules.GetCapacity(data)).to.equal(12)
			data.Base.Slots["13"].accumulatedCash = 0.5
			local ok, why = Schema.ValidateLoaded(data)
			expect(ok).to.equal(true)
			expect(why).to.equal(nil)
			local restored = assert(Schema.Migrate(assert(Schema.CreateSaveSnapshot(data))))
			expect(restored.Base.Slots["13"].accumulatedCash).to.equal(0.5)
			expect(Rules.Cash(restored)).to.equal(0)
			restored.Base.Slots["13"].accumulatedCash = -0.5
			expect(Schema.ValidateLoaded(restored)).to.equal(false)
		end)
		it("fails on future schema/extension corruption without replacing source data", function()
			for _, patch in
				{
					function(d)
						d.SchemaVersion = 999
					end,
					function(d)
						d.Phase13.Version = 999
					end,
					function(d)
						d.Phase13.SpeedLevel = 6
					end,
					function(d)
						d.Phase13.CargoLevel = 4
					end,
					function(d)
						d.Phase13.SelectedCartId = "CRT_013"
					end,
				}
			do
				local data = Schema.CreateDefault()
				patch(data)
				local before = Fixtures.Clone(data)
				local migrated = Schema.Migrate(data)
				expect(migrated).to.equal(nil)
				Fixtures.AssertDeepEqual(data, before)
			end
		end)
		it("upgrades historical transport1/2 to3 and fences the actual old writer before any data overwrite", function()
			local Store = require(script.Parent.Parent.Data.PlayerProfileStore)
			local OldWriter = require(script.Parent.Support.Phase13LegacyWriter)
			for _, version in { 1, 2 } do
				local raw = {
					Transport = { Version = version, OwnerToken = nil, LeaseExpiresAt = 0, LastRevision = 0 },
					Data = historical(),
				}
				local backend = {}
				function backend:UpdateAsync(_, transform)
					raw = transform(raw, nil)
					return raw
				end
				local current = Store.new({
					DataStore = backend,
					Available = true,
					UnixNow = function()
						return 1000
					end,
				})
				local acquired = current:Acquire("synthetic", "same-owner", 180)
				expect(acquired.ok).to.equal(true)
				expect(raw.Transport.Version).to.equal(3)
				raw.Data.Phase13.OwnedCartIds.CRT_013 = true
				raw.Data.Commerce.ProcessedReceipts.synthetic =
					{ ProductId = 1, Amount = 1, GrantedAt = 1000, ConfigVersion = "test" }
				raw.Data.Commerce.ReceiptCount = 1
				local preserved = Fixtures.Clone(raw)
				-- Deliberately use a valid12-slot old-style snapshot and the SAME token:
				-- the transport fence, rather than lease mismatch, must prevent rollback.
				local oldSnapshot = historical()
				local old = OldWriter.new({
					DataStore = backend,
					Available = true,
					UnixNow = function()
						return 1001
					end,
				})
				expect(old:Save("synthetic", "same-owner", "old-op", 99, oldSnapshot, 180).code).to.equal(
					"UNSUPPORTED_ENVELOPE"
				)
				expect(old:Acquire("synthetic", "same-owner", 180).code).to.equal("UNSUPPORTED_ENVELOPE")
				expect(current:Save("synthetic", "same-owner", "stale-new-writer", 99, oldSnapshot, 180).code).to.equal(
					"UNSUPPORTED_WRITE_PHASE13"
				)
				expect(current:Release("synthetic", "same-owner", "stale-close", 99, oldSnapshot).code).to.equal(
					"UNSUPPORTED_WRITE_PHASE13"
				)
				Fixtures.AssertDeepEqual(raw, preserved)
			end
		end)
		it("uses original species units and canonical mutation values", function()
			local first = Catalog.Get("BRT_001")
			expect(first.cashPerSecond).to.equal(1800000)
			expect(first.sellValue).to.equal(54000000)
			for _, pair in
				{
					{ "None", 1 },
					{ "Shiny", 1.5 },
					{ "Golden", 2.5 },
					{ "Glitched", 4 },
					{ "Radioactive", 7 },
					{
						"Astral",
						15,
					},
				}
			do
				local value = assert(Values.EffectiveValues("BRT_001", pair[1]))
				expect(value.cashPerSecond).to.equal(1800000 * pair[2])
				expect(value.sellValue).to.equal(54000000 * pair[2])
			end
			local live, teased = 0, 0
			for _, def in Catalog.GetAll() do
				if def.launchStatus == "Live" then
					live += 1
				elseif def.launchStatus == "Teased" then
					teased += 1
				end
			end
			expect(live).to.equal(32)
			expect(teased).to.equal(3)
		end)
	end)
end
