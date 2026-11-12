--!nocheck

return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local Store = require(script.Parent.Parent.Data.PlayerProfileStore)
	local Config = require(script.Parent.Parent.Config.PlayerDataConfig)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	-- A loaded profile with bank history is marked retention-eligible by
	-- RetentionRules.Migrate, which bumps the retention revision once.
	local function migratedFullProfile()
		local expected = Fixtures.WithPhase12ExpectedFields(Fixtures.FullProfile())
		expected.Retention.Eligible = true
		expected.Retention.Revision = 1
		return expected
	end

	local function clone(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, nested in value do
			copy[key] = clone(nested)
		end
		return copy
	end

	local function fakeDataStore()
		local dataStore = {
			Records = {},
			Reevaluate = false,
			CommitThenFail = false,
			UserIds = { 1234 },
			Metadata = { Existing = "preserved" },
			TransformEvents = {},
		}
		function dataStore:UpdateAsync(key, transform)
			local keyInfo = {}
			function keyInfo.GetUserIds()
				return clone(dataStore.UserIds)
			end
			function keyInfo.GetMetadata()
				return clone(dataStore.Metadata)
			end
			local function evaluate()
				local current = clone(self.Records[key])
				local before = clone(current)
				local proposed, userIds, metadata = transform(current, keyInfo)
				table.insert(self.TransformEvents, {
					before = before,
					after = clone(current),
					proposed = clone(proposed),
				})
				return proposed, userIds, metadata
			end
			local proposed, userIds, metadata = evaluate()
			if self.Reevaluate then
				local hook = self.BeforeReevaluation
				self.BeforeReevaluation = nil
				if hook then
					hook(self, key)
				end
				proposed, userIds, metadata = evaluate()
			end
			if proposed ~= nil then
				self.Records[key] = clone(proposed)
				self.UserIds = clone(userIds or {})
				self.Metadata = clone(metadata or {})
			end
			if self.CommitThenFail then
				self.CommitThenFail = false
				error("injected response loss")
			end
			return clone(self.Records[key])
		end
		return dataStore
	end

	local function envelope(data)
		return {
			Transport = {
				Version = Config.TransportVersion,
				LeaseExpiresAt = 0,
				LastRevision = 9,
			},
			Data = data,
			SyntheticEnvelopeExtension = { preserve = true },
		}
	end

	local function storeFor(dataStore, now)
		return Store.new({
			DataStore = dataStore,
			Available = true,
			UnixNow = now or function()
				return 1000
			end,
		})
	end

	describe("Phase 7A-1 conditional profile store", function()
		it("acquires once, rejects a foreign owner, and preserves fractional data", function()
			local now = 1000
			local dataStore = fakeDataStore()
			dataStore.Reevaluate = true
			local store = Store.new({
				DataStore = dataStore,
				Available = true,
				UnixNow = function()
					return now
				end,
			})
			local acquired = store:Acquire("player_1", "owner-a", 180)
			expect(acquired.ok).to.equal(true)
			expect(acquired.isNew).to.equal(true)
			expect(store:Acquire("player_1", "owner-b", 180).code).to.equal("SESSION_LOCKED")

			local snapshot = Schema.CreateDefault()
			snapshot.Economy.Balance = 12.75
			expect(store:Save("player_1", "owner-a", "save-a", 1, snapshot, 180).ok).to.equal(true)
			expect(dataStore.Records.player_1.Data.Economy.Balance).to.equal(12.75)
			expect(dataStore.UserIds[1]).to.equal(1234)
			expect(dataStore.Metadata.Existing).to.equal("preserved")
		end)

		it(
			"does not let a stale owner save after handoff or after the new owner releases",
			function()
				local now = 1000
				local dataStore = fakeDataStore()
				local store = Store.new({
					DataStore = dataStore,
					Available = true,
					UnixNow = function()
						return now
					end,
				})
				local initial = store:Acquire("player_2", "owner-a", 180)
				expect(store:Release("player_2", "owner-a", "release-a", 0, initial.data).ok).to.equal(
					true
				)
				local second = store:Acquire("player_2", "owner-b", 180)
				expect(second.ok).to.equal(true)
				local staleData = Schema.CreateDefault()
				staleData.Economy.Balance = 999
				expect(store:Save("player_2", "owner-a", "stale-1", 1, staleData, 180).code).to.equal(
					"OWNER_MISMATCH"
				)
				expect(store:Release("player_2", "owner-b", "release-b", 0, second.data).ok).to.equal(
					true
				)
				expect(store:Save("player_2", "owner-a", "stale-2", 1, staleData, 180).code).to.equal(
					"OWNER_MISMATCH"
				)
				expect(dataStore.Records.player_2.Data.Economy.Balance).to.equal(0)
			end
		)

		it("recognizes the same committed operation after its response is lost", function()
			local dataStore = fakeDataStore()
			local store = Store.new({
				DataStore = dataStore,
				Available = true,
				UnixNow = function()
					return 1000
				end,
			})
			local acquired = store:Acquire("player_3", "owner", 180)
			local snapshot = acquired.data
			snapshot.Economy.Balance = 8.5
			dataStore.CommitThenFail = true
			expect(store:Save("player_3", "owner", "stable-op", 1, snapshot, 180).code).to.equal(
				"SAVE_UNCERTAIN"
			)
			expect(store:Save("player_3", "owner", "stable-op", 1, snapshot, 180).ok).to.equal(true)
			expect(dataStore.Records.player_3.Data.Economy.Balance).to.equal(8.5)
			expect(dataStore.Records.player_3.Transport.LastRevision).to.equal(1)
		end)

		it("refuses corrupt or newer data without replacing it with a default", function()
			local dataStore = fakeDataStore()
			dataStore.Records.player_4 = {
				Transport = {
					Version = Config.TransportVersion,
					OwnerToken = nil,
					LeaseExpiresAt = 0,
					LastRevision = 9,
				},
				Data = { SchemaVersion = 999, Economy = { Balance = 44 } },
			}
			local store = Store.new({
				DataStore = dataStore,
				Available = true,
				UnixNow = function()
					return 1000
				end,
			})
			local acquired = store:Acquire("player_4", "owner", 180)
			expect(acquired.ok).to.equal(false)
			expect(acquired.code).to.equal("UNSUPPORTED_NEWER_SCHEMA")
			expect(dataStore.Records.player_4.Data.Economy.Balance).to.equal(44)
			expect(dataStore.Records.player_4.Transport.OwnerToken).to.equal(nil)
		end)
	end)

	describe("Phase 7F actual UpdateAsync adapter and serializer", function()
		it("confirms the same committed release after its acknowledgement is lost", function()
			local dataStore = fakeDataStore()
			local store = storeFor(dataStore)
			local acquired = store:Acquire("synthetic_release_loss", "synthetic-a", 180)
			expect(acquired.ok).to.equal(true)
			local snapshot = assert(Schema.CreateSaveSnapshot(Fixtures.FullProfile()))
			dataStore.Reevaluate = true
			dataStore.CommitThenFail = true
			local uncertain = store:Release(
				"synthetic_release_loss",
				"synthetic-a",
				"stable-release",
				1,
				snapshot
			)
			expect(uncertain.code).to.equal("RELEASE_UNCERTAIN")
			expect(uncertain.uncertain).to.equal(true)
			local committed = clone(dataStore.Records.synthetic_release_loss)
			expect(committed.Transport.OwnerToken).to.equal(nil)
			Fixtures.AssertDeepEqual(committed.Data, Fixtures.FullProfile())
			local confirmed = store:Release(
				"synthetic_release_loss",
				"synthetic-a",
				"stable-release",
				1,
				snapshot
			)
			expect(confirmed.code).to.equal("RELEASED")
			Fixtures.AssertDeepEqual(dataStore.Records.synthetic_release_loss, committed)
		end)

		it(
			"blocks an uncertain old release retry after a fresh owner acquires and releases",
			function()
				local dataStore = fakeDataStore()
				local storeA, storeB = storeFor(dataStore), storeFor(dataStore)
				expect(storeA:Acquire("synthetic_release_handoff", "synthetic-a", 180).ok).to.equal(
					true
				)
				local snapshotA = assert(Schema.CreateSaveSnapshot(Fixtures.FullProfile()))
				dataStore.CommitThenFail = true
				expect(
					storeA:Release(
						"synthetic_release_handoff",
						"synthetic-a",
						"a-release",
						1,
						snapshotA
					).code
				).to.equal("RELEASE_UNCERTAIN")
				-- The release really committed, so B may acquire. A's lost response
				-- must not authorize its same-operation retry to clear B's new lock.
				local b = storeB:Acquire("synthetic_release_handoff", "synthetic-b", 180)
				expect(b.ok).to.equal(true)
				Fixtures.AssertDeepEqual(b.data, migratedFullProfile())
				local ownedByB = clone(dataStore.Records.synthetic_release_handoff)
				expect(
					storeA:Release(
						"synthetic_release_handoff",
						"synthetic-a",
						"a-release",
						1,
						snapshotA
					).code
				).to.equal("OWNER_MISMATCH")
				Fixtures.AssertDeepEqual(dataStore.Records.synthetic_release_handoff, ownedByB)
				b.data.Economy.Balance += 0.25
				b.data.Progression.Upgrades.CARGO_1 = nil
				local snapshotB = assert(Schema.CreateSaveSnapshot(b.data))
				expect(
					storeB:Release(
						"synthetic_release_handoff",
						"synthetic-b",
						"b-release",
						2,
						snapshotB
					).ok
				).to.equal(true)
				local releasedByB = clone(dataStore.Records.synthetic_release_handoff)
				expect(
					storeA:Release(
						"synthetic_release_handoff",
						"synthetic-a",
						"a-release",
						1,
						snapshotA
					).code
				).to.equal("OWNER_MISMATCH")
				Fixtures.AssertDeepEqual(dataStore.Records.synthetic_release_handoff, releasedByB)
				local fresh =
					storeFor(dataStore):Acquire("synthetic_release_handoff", "synthetic-c", 180)
				expect(fresh.ok).to.equal(true)
				Fixtures.AssertDeepEqual(fresh.data, snapshotB)
			end
		)

		for _, version in { 0, 1, Config.SchemaVersion } do
			it(
				"restores complete synthetic schema "
					.. version
					.. " through independent store sessions",
				function()
					local dataStore = fakeDataStore()
					dataStore.Records.synthetic_full = envelope(Fixtures.FullProfile(version))
					dataStore.Reevaluate = true
					local firstStore = storeFor(dataStore)
					local first = firstStore:Acquire("synthetic_full", "synthetic-first", 180)
					expect(first.ok).to.equal(true)
					expect(first.isNew).to.equal(false)
					Fixtures.AssertDeepEqual(first.data, migratedFullProfile())
					local snapshot = assert(Schema.CreateSaveSnapshot(first.data))
					expect(
						firstStore:Save(
							"synthetic_full",
							"synthetic-first",
							"full-save",
							10,
							snapshot,
							180
						).ok
					).to.equal(true)
					expect(
						firstStore:Release(
							"synthetic_full",
							"synthetic-first",
							"full-release",
							10,
							snapshot
						).ok
					).to.equal(true)
					-- Destroy the old session's logical data after the write. The backend
					-- and serializer must each have their own nested source tables.
					first.data.Collection.BrainrotInstances["synthetic-player-1:a"] = nil
					snapshot.Base.Slots["4"].accumulatedCash = 0
					snapshot.Progression.Upgrades.CARGO_1 = nil
					local secondStore = storeFor(dataStore)
					local second = secondStore:Acquire("synthetic_full", "synthetic-second", 180)
					expect(second.ok).to.equal(true)
					expect(second.lastRevision).to.equal(10)
					Fixtures.AssertDeepEqual(second.data, migratedFullProfile())
					local secondSnapshot = assert(Schema.CreateSaveSnapshot(second.data))
					expect(
						secondStore:Release(
							"synthetic_full",
							"synthetic-second",
							"second-release",
							10,
							secondSnapshot
						).ok
					).to.equal(true)
					local third =
						storeFor(dataStore):Acquire("synthetic_full", "synthetic-third", 180)
					expect(third.ok).to.equal(true)
					Fixtures.AssertDeepEqual(third.data, migratedFullProfile())
					expect(dataStore.Records.synthetic_full.SyntheticEnvelopeExtension.preserve).to.equal(
						true
					)
					expect(dataStore.UserIds[1]).to.equal(1234)
					expect(dataStore.Metadata.Existing).to.equal("preserved")
				end
			)
		end

		it(
			"reevaluates pure acquire, save, renew and release transforms without mutating input",
			function()
				local dataStore = fakeDataStore()
				dataStore.Records.synthetic_pure = envelope(Fixtures.FullProfile(1))
				dataStore.Reevaluate = true
				local store = storeFor(dataStore)
				local acquired = store:Acquire("synthetic_pure", "synthetic-owner", 180)
				expect(acquired.ok).to.equal(true)
				local snapshot = assert(Schema.CreateSaveSnapshot(acquired.data))
				snapshot.Base.Slots["4"].accumulatedCash = 19.875
				expect(
					store:Save("synthetic_pure", "synthetic-owner", "pure-save", 10, snapshot, 180).ok
				).to.equal(true)
				expect(store:Renew("synthetic_pure", "synthetic-owner", "pure-renew", 180).ok).to.equal(
					true
				)
				expect(
					store:Release("synthetic_pure", "synthetic-owner", "pure-release", 10, snapshot).ok
				).to.equal(true)
				expect(#dataStore.TransformEvents).to.equal(8)
				for index = 1, #dataStore.TransformEvents, 2 do
					local first = dataStore.TransformEvents[index]
					local second = dataStore.TransformEvents[index + 1]
					Fixtures.AssertDeepEqual(first.before, first.after, "transform-first-input")
					Fixtures.AssertDeepEqual(second.before, second.after, "transform-retry-input")
					Fixtures.AssertDeepEqual(
						first.proposed,
						second.proposed,
						"reevaluated-proposal"
					)
				end
				Fixtures.AssertDeepEqual(dataStore.Records.synthetic_pure.Data, snapshot)
			end
		)

		it(
			"refuses stale Save, Renew and Release after owner B releases an expired owner A lease",
			function()
				local now = 1000
				local dataStore = fakeDataStore()
				local storeA = storeFor(dataStore, function()
					return now
				end)
				local storeB = storeFor(dataStore, function()
					return now
				end)
				local a = storeA:Acquire("synthetic_handoff", "synthetic-a", 180)
				expect(a.ok).to.equal(true)
				now = 1181
				local b = storeB:Acquire("synthetic_handoff", "synthetic-b", 180)
				expect(b.ok).to.equal(true)
				b.data = Fixtures.FullProfile()
				local current = assert(Schema.CreateSaveSnapshot(b.data))
				expect(
					storeB:Release("synthetic_handoff", "synthetic-b", "b-release", 2, current).ok
				).to.equal(true)
				local released = clone(dataStore.Records.synthetic_handoff)
				local stale = assert(Schema.CreateSaveSnapshot(a.data))
				stale.Economy.Balance = 99999
				expect(
					storeA:Save("synthetic_handoff", "synthetic-a", "stale-save", 50, stale, 180).code
				).to.equal("OWNER_MISMATCH")
				expect(storeA:Renew("synthetic_handoff", "synthetic-a", "stale-renew", 180).code).to.equal(
					"OWNER_MISMATCH"
				)
				expect(
					storeA:Release("synthetic_handoff", "synthetic-a", "stale-release", 50, stale).code
				).to.equal("OWNER_MISMATCH")
				Fixtures.AssertDeepEqual(dataStore.Records.synthetic_handoff, released)
				expect(dataStore.Records.synthetic_handoff.Transport.OwnerToken).to.equal(nil)
			end
		)

		it(
			"rechecks ownership when a save transform is reevaluated after B acquires and releases",
			function()
				local now = 1000
				local dataStore = fakeDataStore()
				local storeA = storeFor(dataStore, function()
					return now
				end)
				local storeB = storeFor(dataStore, function()
					return now
				end)
				local a = storeA:Acquire("synthetic_race", "synthetic-a", 180)
				expect(a.ok).to.equal(true)
				local bReleased
				dataStore.Reevaluate = true
				dataStore.BeforeReevaluation = function()
					now = 1181
					local b = storeB:Acquire("synthetic_race", "synthetic-b", 180)
					expect(b.ok).to.equal(true)
					local current = assert(Schema.CreateSaveSnapshot(Fixtures.FullProfile()))
					expect(
						storeB:Release(
							"synthetic_race",
							"synthetic-b",
							"race-b-release",
							1,
							current
						).ok
					).to.equal(true)
					bReleased = clone(dataStore.Records.synthetic_race)
				end
				local stale = assert(Schema.CreateSaveSnapshot(a.data))
				stale.Economy.Balance = 99999
				local result =
					storeA:Save("synthetic_race", "synthetic-a", "race-a-save", 99, stale, 180)
				expect(result.code).to.equal("OWNER_MISMATCH")
				Fixtures.AssertDeepEqual(dataStore.Records.synthetic_race, bReleased)
			end
		)

		it(
			"leaves malformed, newer and duplicate-reference records source-equivalent on refused acquisition",
			function()
				local cases = {
					{
						"negative-wallet",
						"INVALID_BALANCE",
						function(data)
							data.Economy.Balance = -1
						end,
					},
					{
						"nonfinite-wallet",
						"INVALID_BALANCE",
						function(data)
							data.Economy.Balance = math.huge
						end,
					},
					{
						"nan-slot",
						"INVALID_SLOT_BALANCE",
						function(data)
							data.Base.Slots["4"].accumulatedCash = 0 / 0
						end,
					},
					{
						"newer",
						"UNSUPPORTED_NEWER_SCHEMA",
						function(data)
							data.SchemaVersion = Config.SchemaVersion + 1
						end,
					},
					{
						"duplicate",
						"DUPLICATE_SLOT_REFERENCE",
						function(data)
							data.Base.Slots["5"].brainrotId = data.Base.Slots["1"].brainrotId
						end,
					},
					{
						"missing-owner",
						"MISSING_OWNED_BRAINROT",
						function(data)
							data.Base.Slots["1"].brainrotId = "synthetic-absent"
						end,
					},
					{
						"slot-alias",
						"INVALID_SLOT_ID",
						function(data)
							data.Base.Slots["01"] = data.Base.Slots["1"]
							data.Base.Slots["1"] = nil
						end,
					},
					{
						"malformed-upgrades",
						"UPGRADES_NOT_TABLE",
						function(data)
							data.Progression.Upgrades = "corrupt"
						end,
					},
				}
				for _, case in cases do
					local dataStore = fakeDataStore()
					local source = Fixtures.FullProfile()
					case[3](source)
					dataStore.Records.synthetic_invalid = envelope(source)
					dataStore.Reevaluate = true
					local before = clone(dataStore.Records.synthetic_invalid)
					local acquired =
						storeFor(dataStore):Acquire("synthetic_invalid", "synthetic-owner", 180)
					assert(acquired.ok == false, case[1] .. " must not become writable")
					expect(acquired.code).to.equal(case[2])
					Fixtures.AssertDeepEqual(dataStore.Records.synthetic_invalid, before, case[1])
					expect(dataStore.Records.synthetic_invalid.Transport.OwnerToken).to.equal(nil)
				end
			end
		)
	end)
	it("reports confirmed currency conversion and new legacy grants without persisting an extra transaction log",function()
		local data=Schema.CreateDefault()
		data.CurrencyVersion=nil data.WorldProgression=nil data.Economy.Balance=20000
		data.Collection.BrainrotInstances["banked-011"]={speciesId="BRT_011",metadata={}}
		data.Base.Slots["1"]={brainrotId="banked-011",accumulatedCash=125.5}
		data.Base.Slots["2"]={accumulatedCash=125.5}
		local ds=fakeDataStore() ds.Records.player_migration=envelope(data)
		ds.Records.player_migration.Transport.Version=Config.LegacyTransportVersion
		local store=storeFor(ds) local acquired=store:Acquire("player_migration","owner-a",180)
		expect(acquired.ok).to.equal(true) expect(acquired.migrated).to.equal(true)
		expect(acquired.data.Economy.Balance).to.equal(30000000)
		expect(acquired.data.Base.Slots["1"].accumulatedCash).to.equal(188250)
		expect(acquired.data.Base.Slots["2"].accumulatedCash).to.equal(188250)
		expect(acquired.migrationSummary.currencyFrom).to.equal(1)
		expect(acquired.migrationSummary.currencyTo).to.equal(2)
		expect(acquired.migrationSummary.monetaryFieldCount).to.equal(13)
		expect(acquired.migrationSummary.legacyRegions).to.equal("Beach")
		expect(ds.Records.player_migration.migrationSummary).to.equal(nil)
		expect(store:Release("player_migration","owner-a","release-a",9,acquired.data).ok).to.equal(true)
		local returning=store:Acquire("player_migration","owner-b",180)
		expect(returning.ok).to.equal(true) expect(returning.data.Economy.Balance).to.equal(30000000)
		expect(returning.migrationSummary.monetaryFieldCount).to.equal(0)
		expect(returning.migrationSummary.legacyRegions).to.equal("")
		expect(returning.migrated).to.equal(false)
	end)

	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
