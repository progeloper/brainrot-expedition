--!nocheck

return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Config = require(script.Parent.Parent.Config.PlayerDataConfig)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	-- Independent expected current fields for these existing banked/owned
	-- historical cohorts. Do not derive expectations from the migration under test.
	local function expectedHistorical(source)
		assert(next(source.Collection.BrainrotInstances) ~= nil, "Expected historical banked ownership proof")
		local expected = Fixtures.WithPhase12ExpectedFields(source)
		expected.Retention.Eligible, expected.Retention.Revision = true, 1
		return expected
	end

	describe("Concurrent Phase 10 playtime schema compatibility", function()
		it("backfills missing playtime once while preserving banked records, team purchases and cash", function()
			local historical = Fixtures.FullProfile()
			historical.WorldReadyPlaytimeSeconds = nil
			historical.ChariotTeam.PurchasedExtraSlots = 1
			historical.ChariotTeam.Assignments["1"] = "synthetic-player-1:a"
			local before = Fixtures.Clone(historical)
			local migrated, reason, changed = Schema.Migrate(historical)
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			expect(migrated.WorldReadyPlaytimeSeconds).to.equal(0)
			Fixtures.AssertDeepEqual(historical, before)
			local expected = Fixtures.Clone(before)
			expected.WorldReadyPlaytimeSeconds = 0
			expected = expectedHistorical(expected)
			Fixtures.AssertDeepEqual(migrated, expected)
			local saved, saveReason = Schema.CreateSaveSnapshot(migrated)
			expect(saveReason).to.equal(nil)
			local restored, restoreReason, changedAgain = Schema.Migrate(saved)
			expect(restoreReason).to.equal(nil)
			expect(changedAgain).to.equal(false)
			Fixtures.AssertDeepEqual(restored, expected)
		end)
		it("rejects malformed playtime without resetting existing profile fields", function()
			for _, invalid in { -1, math.huge, -math.huge, 0 / 0, "900", false, {}, Config.MaxBalance + 1 } do
				local source = Fixtures.FullProfile()
				source.WorldReadyPlaytimeSeconds = invalid
				local before = Fixtures.Clone(source)
				local migrated, reason = Schema.Migrate(source)
				expect(migrated).to.equal(nil)
				expect(reason).to.equal("INVALID_WORLD_READY_PLAYTIME")
				local snapshot, saveReason = Schema.CreateSaveSnapshot(source)
				expect(snapshot).to.equal(nil)
				expect(saveReason).to.equal("INVALID_WORLD_READY_PLAYTIME")
				Fixtures.AssertDeepEqual(source, before)
			end
		end)
	end)

	describe("Phase 7A-1 player profile schema", function()
		it("retains empty-slot cash while backfilling trusted banking proof", function()
			local profile = Schema.CreateDefault()
			profile.Economy.Balance = 12.25
			profile.Collection.BrainrotInstances.a = { speciesId = "BRT_007" }
			profile.Base.Slots["1"] = { brainrotId = "a", accumulatedCash = 100.5 }
			profile.Base.Slots["2"].accumulatedCash = 100
			local loaded, reason, changed = Schema.Migrate(profile)
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			expect(loaded.Base.Slots["2"].accumulatedCash).to.equal(100)
			expect(loaded.Base.Slots["1"].accumulatedCash).to.equal(100.5)
			expect(loaded.Economy.Balance).to.equal(12.25)
			expect(profile.Base.Slots["2"].accumulatedCash).to.equal(100)
			local _, _, changedAgain = Schema.Migrate(loaded)
			expect(changedAgain).to.equal(false)
		end)
		it("creates independent nested defaults", function()
			local first = Schema.CreateDefault()
			local second = Schema.CreateDefault()
			first.Economy.Balance = 25
			first.Base.Slots["1"].accumulatedCash = 18.5
			expect(second.Economy.Balance).to.equal(0)
			expect(second.Base.Slots["1"].accumulatedCash).to.equal(0)
			expect(#second.Base.Slots).to.equal(0)
			local count = 0
			for _ in second.Base.Slots do
				count += 1
			end
			expect(count).to.equal(48)
		end)

		it("preserves fractional balances and unrelated fields in snapshots", function()
			local profile = Schema.CreateDefault()
			profile.Economy.Balance = 123.8
			profile.Settings = { Music = false }
			local snapshot, reason = Schema.CreateSaveSnapshot(profile)
			expect(reason).to.equal(nil)
			expect(math.abs(snapshot.Economy.Balance - 123.8) < 1e-9).to.equal(true)
			expect(snapshot.Settings.Music).to.equal(false)
			profile.Settings.Music = true
			expect(snapshot.Settings.Music).to.equal(false)
		end)

		it("migrates the explicit version-zero account shape once", function()
			local migrated, reason, changed = Schema.Migrate({
				SchemaVersion = 0,
				Balance = 14.25,
				Collection = { BRT_007 = true },
			})
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			expect(migrated.Economy.Balance).to.equal(21375)
			expect(migrated.Collection.BRT_007).to.equal(true)
			expect(migrated.Balance).to.equal(nil)
			local reconciled, secondReason, secondChanged = Schema.Migrate(migrated)
			expect(secondReason).to.equal(nil)
			expect(secondChanged).to.equal(false)
			expect(reconciled.Economy.Balance).to.equal(21375)
		end)

		it("migrates wallet-only version one without resetting money or unrelated data", function()
			local migrated, reason, changed = Schema.Migrate({
				SchemaVersion = 1,
				Economy = { Balance = 81.375 },
				Settings = { Music = false },
			})
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			expect(migrated.Economy.Balance).to.equal(122062.5)
			expect(migrated.Settings.Music).to.equal(false)
			expect(migrated.Collection.BrainrotInstances).never.to.equal(nil)
			expect(migrated.Base.Slots["12"].accumulatedCash).to.equal(0)
		end)

		it(
			"validates ownership, duplicate references, unknown species and empty-slot cash",
			function()
				local valid = Schema.CreateDefault()
				valid.Collection.BrainrotInstances.unknown = { speciesId = "BRT_999" }
				valid.Base.Slots["1"] = { brainrotId = "unknown", accumulatedCash = 4.25 }
				valid.Base.Slots["2"].accumulatedCash = 8.5
				expect(Schema.ValidateLoaded(valid)).to.equal(true)

				local duplicate = Schema.CreateSaveSnapshot(valid)
				duplicate.Base.Slots["3"].brainrotId = "unknown"
				local ok, duplicateReason = Schema.ValidateLoaded(duplicate)
				expect(ok).to.equal(false)
				expect(duplicateReason).to.equal("DUPLICATE_SLOT_REFERENCE")

				local missing = Schema.CreateSaveSnapshot(valid)
				missing.Base.Slots["1"].brainrotId = "absent"
				local missingOk, missingReason = Schema.ValidateLoaded(missing)
				expect(missingOk).to.equal(false)
				expect(missingReason).to.equal("MISSING_OWNED_BRAINROT")

				local invalidCash = Schema.CreateSaveSnapshot(valid)
				invalidCash.Base.Slots["2"].accumulatedCash = -1
				expect(Schema.ValidateLoaded(invalidCash)).to.equal(false)
			end
		)

		it("rejects conflicting legacy values, invalid balances and newer schemas", function()
			local conflict, conflictReason = Schema.Migrate({
				SchemaVersion = 0,
				Balance = 5,
				Economy = { Balance = 9 },
			})
			expect(conflict).to.equal(nil)
			expect(conflictReason).to.equal("CONFLICTING_LEGACY_BALANCE")

			for _, balance in { -1, math.huge, 0 / 0, "10" } do
				local profile = Schema.CreateDefault()
				profile.Economy.Balance = balance
				expect(Schema.ValidateLoaded(profile)).to.equal(false)
			end

			local newer, newerReason = Schema.Migrate({
				SchemaVersion = 999,
				Economy = { Balance = 50 },
			})
			expect(newer).to.equal(nil)
			expect(newerReason).to.equal("UNSUPPORTED_NEWER_SCHEMA")
		end)

		it("rejects non-serializable and cyclic profile content", function()
			local profile = Schema.CreateDefault()
			profile.Bad = workspace
			expect(Schema.CreateSaveSnapshot(profile)).to.equal(nil)
			profile.Bad = nil
			profile.Cycle = profile
			expect(Schema.CreateSaveSnapshot(profile)).to.equal(nil)
		end)
	end)

	describe("Phase 7F complete synthetic schema compatibility", function()
		it(
			"fails closed when synthetic version zero has a present malformed Economy container",
			function()
				for _, invalid in { "corrupt", false, 12 } do
					local source = Fixtures.FullProfile(0)
					source.Economy = invalid
					local before = Fixtures.Clone(source)
					local migrated, reason = Schema.Migrate(source)
					expect(migrated).to.equal(nil)
					expect(reason).to.equal("ECONOMY_NOT_TABLE")
					Fixtures.AssertDeepEqual(source, before)
				end
				local absent = Fixtures.FullProfile(0)
				absent.Economy = nil
				local migrated = assert(Schema.Migrate(absent))
				expect(migrated.Economy.Balance).to.equal(1000.5)
			end
		)

		for _, version in { 0, 1, Config.SchemaVersion } do
			it("round-trips every source field for synthetic schema " .. version, function()
				local source = Fixtures.FullProfile(version)
				local untouchedSource = Fixtures.Clone(source)
				local migrated, reason, changed = Schema.Migrate(source)
				expect(reason).to.equal(nil)
				expect(changed).to.equal(true) -- Historical banked records receive the Phase 12 extension once.
				Fixtures.AssertDeepEqual(source, untouchedSource)
				Fixtures.AssertDeepEqual(migrated, expectedHistorical(Fixtures.FullProfile()))
				local snapshot, snapshotReason = Schema.CreateSaveSnapshot(migrated)
				expect(snapshotReason).to.equal(nil)
				-- Independent simulated durable table: neither subsequent gameplay edits
				-- nor another simulated player's state may mutate this snapshot.
				local durable = Fixtures.Clone(snapshot)
				migrated.Economy.Balance = 0
				migrated.Collection.BrainrotInstances["synthetic-player-1:a"].metadata.variant =
					"changed"
				migrated.Base.Slots["4"].accumulatedCash = 0
				migrated.Progression.Upgrades.CARGO_1 = nil
				migrated.Settings.Input.AimAssist = false
				local other = Fixtures.FullProfile(nil, 2)
				other.Base.Slots["2"].accumulatedCash = 777
				Fixtures.AssertDeepEqual(snapshot, expectedHistorical(Fixtures.FullProfile()))
				for _ = 1, 3 do
					local fresh, reloadReason, remigrated = Schema.Migrate(durable)
					expect(reloadReason).to.equal(nil)
					expect(remigrated).to.equal(false)
					Fixtures.AssertDeepEqual(fresh, expectedHistorical(Fixtures.FullProfile()))
					expect(fresh == durable).to.equal(false)
					expect(fresh.Base.Slots == durable.Base.Slots).to.equal(false)
					durable = assert(Schema.CreateSaveSnapshot(fresh))
				end
			end)
		end

		it("fills sparse historical slots without resetting existing cash or ownership", function()
			for _, version in { 0, 1 } do
				local sparse = Fixtures.FullProfile(version)
				for index = 5, 11 do
					sparse.Base.Slots[tostring(index)] = nil
				end
				local migrated = assert(Schema.Migrate(sparse))
				Fixtures.AssertDeepEqual(migrated, expectedHistorical(Fixtures.FullProfile()))
				expect(sparse.Base.Slots["5"]).to.equal(nil)
			end
		end)

		it("rejects each invalid wallet and slot balance without changing its source", function()
			for _, invalid in
				{ -1, math.huge, -math.huge, 0 / 0, "12.75", true, Config.MaxBalance + 1 }
			do
				for _, field in { "wallet", "slot" } do
					local source = Fixtures.FullProfile()
					if field == "wallet" then
						source.Economy.Balance = invalid
					else
						source.Base.Slots["4"].accumulatedCash = invalid
					end
					local before = Fixtures.Clone(source)
					local migrated, reason = Schema.Migrate(source)
					expect(migrated).to.equal(nil)
					expect(reason).to.equal(
						if field == "wallet" then "INVALID_BALANCE" else "INVALID_SLOT_BALANCE"
					)
					expect(Schema.CreateSaveSnapshot(source)).to.equal(nil)
					Fixtures.AssertDeepEqual(source, before)
				end
			end
		end)

		it(
			"rejects runtime instances, callbacks and coroutine state in the actual serializer",
			function()
				for _, runtimeValue in
					{ workspace, function() end, coroutine.create(function() end) }
				do
					local source = Fixtures.FullProfile()
					source.Settings.RuntimeValue = runtimeValue
					local snapshot, reason = Schema.CreateSaveSnapshot(source)
					expect(snapshot).to.equal(nil)
					expect(reason).to.equal("UNSERIALIZABLE_VALUE")
				end
			end
		)

		it(
			"fails closed on noncanonical slot aliases instead of making saved occupants unreachable",
			function()
				for _, alias in { "01", "1.0", "1e0", " 1" } do
					local source = Fixtures.FullProfile()
					source.Base.Slots[alias] = source.Base.Slots["1"]
					source.Base.Slots["1"] = nil
					local before = Fixtures.Clone(source)
					local migrated, reason = Schema.Migrate(source)
					expect(migrated).to.equal(nil)
					expect(reason).to.equal("INVALID_SLOT_ID")
					expect(Schema.CreateSaveSnapshot(source)).to.equal(nil)
					Fixtures.AssertDeepEqual(source, before)
				end
			end
		)

		it(
			"rejects malformed present upgrade containers without resetting existing source fields",
			function()
				for _, invalid in { "corrupt", false, 12 } do
					for _, field in { "Progression", "Upgrades" } do
						local source = Fixtures.FullProfile()
						if field == "Progression" then
							source.Progression = invalid
						else
							source.Progression.Upgrades = invalid
						end
						local before = Fixtures.Clone(source)
						local migrated, reason = Schema.Migrate(source)
						expect(migrated).to.equal(nil)
						expect(reason).to.equal(
							if field == "Progression"
								then "PROGRESSION_NOT_TABLE"
								else "UPGRADES_NOT_TABLE"
						)
						expect(Schema.CreateSaveSnapshot(source)).to.equal(nil)
						Fixtures.AssertDeepEqual(source, before)
					end
				end
				for _, version in { 0, 1, Config.SchemaVersion } do
					local absent = Fixtures.FullProfile(version)
					absent.Progression = nil
					expect(Schema.Migrate(absent) ~= nil).to.equal(true)
					absent.Progression = {}
					expect(Schema.Migrate(absent) ~= nil).to.equal(true)
				end
			end
		)
	end)
	describe("B06 unavailable legacy schema compatibility", function()
		local function legacy()
			local d = Schema.CreateDefault()
			d.Collection.BrainrotInstances.legacy = { speciesId = "BRT_002", metadata = { tag = "preserve" } }
			d.Base.Slots["48"] = { brainrotId = "legacy", accumulatedCash = 321.125 }
			d.Base.Slots["47"] = { accumulatedCash = 19.625 }
			return d
		end
		it("preserves valid locked identity and cash-only records across migration and snapshot", function()
			local original = legacy()
			local before = Fixtures.Clone(original)
			local migrated, reason = Schema.Migrate(original)
			expect(reason).to.equal(nil)
			expect(migrated ~= nil).to.equal(true)
			Fixtures.AssertDeepEqual(original, before)
			Fixtures.AssertDeepEqual(migrated.Base.Slots["48"], before.Base.Slots["48"])
			Fixtures.AssertDeepEqual(migrated.Base.Slots["47"], before.Base.Slots["47"])
			local saved = assert(Schema.CreateSaveSnapshot(migrated))
			local again = assert(Schema.Migrate(saved))
			Fixtures.AssertDeepEqual(again.Base.Slots, migrated.Base.Slots)
			Fixtures.AssertDeepEqual(again.Collection.BrainrotInstances, migrated.Collection.BrainrotInstances)
		end)
		it("still rejects malformed money and missing or duplicate locked references", function()
			for _, invalid in { -1, math.huge, 0 / 0, "321" } do
				local d = legacy()
				d.Base.Slots["48"].accumulatedCash = invalid
				expect(Schema.Migrate(d)).to.equal(nil)
			end
			local d = legacy()
			d.Base.Slots["48"].brainrotId = "missing"
			local _, reason = Schema.Migrate(d)
			expect(reason).to.equal("MISSING_OWNED_BRAINROT")
			d = legacy()
			d.Base.Slots["13"].brainrotId = "legacy"
			local _, duplicate = Schema.Migrate(d)
			expect(duplicate).to.equal("DUPLICATE_SLOT_REFERENCE")
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
