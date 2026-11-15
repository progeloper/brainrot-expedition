--!nocheck
-- Focused CP0/CP1 tests. Pure cases are separate from injected-backend writer
-- integration; neither substitutes for the connected first-bank/rejoin smoke.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Config = require(RS.Shared.Config.RetentionConfig)
	local Rules = require(RS.Shared.Utility.RetentionRules)
	local Progress = require(script.Parent.Parent.Data.Phase12Progress)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Money = require(RS.Shared.Utility.CurrencyDenomination)
	local function firstBank(data, id, species, at, mutation)
		local receipt = Progress.RecordFirstBank(data, {
			ItemId = id,
			BrainrotId = species or "BRT_001",
			Metadata = { MutationId = mutation or "None", AcquisitionKind = "Hunt" },
		}, nil, at or 86410)
		if receipt then
			data.Collection.BrainrotInstances[id] = {
				speciesId = receipt.speciesId,
				mutationId = receipt.mutationId,
				firstBankCompleted = true,
				firstBankedAt = receipt.firstBankedAt,
			}
		end
		return receipt
	end
	describe("Phase14 CP0 actual installed configuration and pure first-bank delta", function()
		it("ships exactly three fixed quest definitions and no new quest framework", function()
			expect(Rules.ValidateConfig()).to.equal(true)
			expect(Config.RewardConfigVersion).to.equal("P15_RETENTION_V3")
			expect(Config.DailyQuestStage).to.equal(3)
			local count = 0
			for _ in Config.QuestDefinitions do
				count += 1
			end
			expect(count).to.equal(3)
			expect(Config.PaidFlagEnabled).to.equal(false)
			expect(Config.PaidBannerEnabled).to.equal(false)
		end)
		for _, row in
			{
				{ "Forest", "Forest", "REGION_FOREST", 250000000 },
				{ "Beach", "Beach", "REGION_BEACH", 2500000000 },
				{ "Swamp", "Swamp", "REGION_SWAMP", 10000000000 },
				{ "Jungle", "Jungle", "REGION_JUNGLE", 50000000000 },
				{ "Arctic", "Arctic", "REGION_ARCTIC", 100000000000 },
				{ "Volcano", "Volcano", "REGION_VOLCANO", 250000000000 },
				{ "GlitchZone", "Glitch", "REGION_GLITCH", 500000000000 },
			}
		do
			it("resolves permanent " .. row[3] .. " and configured 3U/2U/1U/7U/8U Cash", function()
				local data = Schema.CreateDefault()
				data.WorldProgression.PersonalUnlocks[row[1]] = { source = "purchase" }
				expect(Rules.ResolveBand(data)).to.equal(row[2])
				expect(Config.RegionIdToBand[row[3]]).to.equal(row[2])
				local frozen = { unitCash = Config.UnitCashByRegionBand[row[2]] }
				expect(frozen.unitCash).to.equal(row[4])
				for _, units in { 1, 2, 3, 7, 8 } do
					expect(Rules.RewardAmount(frozen, units)).to.equal(row[4] * units)
				end
			end)
		end
		it("fails closed for missing negative nonfinite or uncalibrated actual config inputs", function()
			for _, bad in { -1, 0, math.huge, 0 / 0, 50000000 } do
				local config = Fixtures.Clone(Config)
				config.UnitCashByRegionBand.Forest = bad
				expect(Rules.ValidateConfig(config)).to.equal(false)
			end
			local config = Fixtures.Clone(Config)
			config.RegionIdToBand.REGION_ARCTIC = nil
			expect(Rules.ValidateConfig(config)).to.equal(false)
			-- A missing supply-cycle table previously threw before a diagnostic.
			-- These structural vectors call the actual validator, not a copy.
			local before = Fixtures.Clone(Config)
			local function rejects(value)
				local called, valid, reason = pcall(Rules.ValidateConfig, value)
				expect(called).to.equal(true)
				expect(valid).to.equal(false)
				expect(type(reason) == "string" and #reason > 0).to.equal(true)
			end
			for _, value in { false, 42, "invalid" } do
				rejects(value)
			end
			for _, field in {
				"RegionBandOrder",
				"UnitCashByRegionBand",
				"RegionIdToBand",
				"QuestDefinitions",
				"SupplyRewardUnitsByCycleClaim",
			} do
				local missing = Fixtures.Clone(Config)
				missing[field] = nil
				rejects(missing)
				for _, value in { false, 42, "invalid" } do
					local malformed = Fixtures.Clone(Config)
					malformed[field] = value
					rejects(malformed)
				end
			end
			for _, value in { false, 42, "invalid" } do
				local malformed = Fixtures.Clone(Config)
				malformed.QuestDefinitions.bring_them_home = value
				rejects(malformed)
			end
			expect(Rules.ValidateConfig()).to.equal(true)
			Fixtures.AssertDeepEqual(Config, before)
		end)
		it("does not freeze a new account's day during defaults migration or reads", function()
			local data = Schema.CreateDefault()
			expect(data.Retention.Eligible).to.equal(false)
			expect(Rules.ResolveBand(data)).to.equal("Forest")
			expect(data.Retention.Day).to.equal(nil)
		end)
		it("pays zero for A, A then 5U for B and preserves a fractional wallet", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 12.375
			firstBank(data, "cp1:a", "BRT_001")
			expect(data.Retention.Day.bring_them_home.count).to.equal(1)
			expect(data.Economy.Balance).to.equal(12.375)
			firstBank(data, "cp1:b", "BRT_001")
			expect(data.Retention.Day.bring_them_home.count).to.equal(2)
			expect(data.Economy.Balance).to.equal(12.375)
			local receipt = firstBank(data, "cp1:c", "BRT_011")
			expect(data.Retention.Day.bring_them_home.paid).to.equal(true)
			expect(data.Economy.Balance).to.equal(1250000012.375)
			expect(receipt.retention.amountCash).to.equal(750000000)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("canonical replay before after rejoin and midnight cannot count or pay again", function()
			local data = Schema.CreateDefault()
			for i = 1, 3 do
				firstBank(data, "cp1:" .. i)
			end
			local before = Fixtures.Clone(data)
			expect(firstBank(data, "cp1:3", "BRT_001", 86410)).to.equal(nil)
			data = assert(Schema.CreateSaveSnapshot(data))
			expect(firstBank(data, "cp1:3", "BRT_001", 172810)).to.equal(nil)
			Fixtures.AssertDeepEqual(data, before)
		end)
		it("keeps a frozen day's band through a later unlock then uses next day's permanent band", function()
			local data = Schema.CreateDefault()
			firstBank(data, "day:a")
			data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
			firstBank(data, "day:b")
			firstBank(data, "day:c")
			expect(data.Economy.Balance).to.equal(750000000)
			firstBank(data, "day:d", "BRT_001", 172810)
			expect(data.Retention.Day.unitCash).to.equal(2500000000)
			expect(data.Retention.Day.bring_them_home.count).to.equal(1)
		end)
		it("retains original entitlement at wallet overflow and recovers it once without repricing", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = Money.MAX_AMOUNT
			for i = 1, 3 do
				firstBank(data, "overflow:" .. i)
			end
			expect(data.Retention.Day.bring_them_home.paid).to.equal(false)
			local _, pending = next(data.Retention.PendingRewards)
			expect(pending.amountCash).to.equal(750000000)
			data.WorldProgression.PersonalUnlocks.GlitchZone = { source = "purchase" }
			data.Economy.Balance = 0.25
			expect(Rules.RecoverPending(data)).to.equal(true)
			expect(data.Economy.Balance).to.equal(750000000.25)
			expect(Rules.RecoverPending(data)).to.equal(false)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("additive migration uses reliable history once without changing existing fields", function()
			local data = Schema.CreateDefault()
			data.Retention = nil
			data.Collection.Species.BRT_011 = 3
			local before = Fixtures.Clone(data)
			expect(Rules.Migrate(data)).to.equal(true)
			expect(data.Retention.Eligible).to.equal(true)
			local after = Fixtures.Clone(data)
			local _, _, changed = Rules.Migrate(data)
			expect(changed).to.equal(false)
			Fixtures.AssertDeepEqual(data, after)
			data.Retention = nil
			Fixtures.AssertDeepEqual(data, before)
		end)
		it("unknown permanent region refuses retention without inventing a lower-band grant", function()
			local data = Schema.CreateDefault()
			data.WorldProgression.PersonalUnlocks.Unknown = { source = "purchase" }
			expect(Rules.ResolveBand(data)).to.equal(nil)
			local receipt = firstBank(data, "unknown:a")
			expect(receipt.retention.code).to.equal("UNKNOWN_RETENTION_REGION:Unknown")
			expect(data.Economy.Balance).to.equal(0)
			expect(data.Retention.Day).to.equal(nil)
		end)
	end)
	local function writerCase(callback, backendOptions)
		local now, sequence = 86410, 0
		local backend = FakeBackend.new(backendOptions)
		backend.Now = function()
			return now
		end
		Profile:_ResetForTests()
		Profile:Init({
			Backend = backend,
			UnixNow = function()
				return now
			end,
			MonotonicNow = function()
				return now
			end,
			Wait = function(s)
				now += s
			end,
			Random = function()
				return 0
			end,
			GenerateOperationId = function(prefix)
				sequence += 1
				return prefix .. ":" .. sequence
			end,
			KickOnFailure = false,
		})
		local function player()
			local p = { Name = "P14Synthetic", UserId = 814001, Parent = Players, Attributes = {} }
			function p:SetAttribute(key, value)
				self.Attributes[key] = value
			end
			function p:Kick(message)
				self.Kicked = message
			end
			return p
		end
		local p = player()
		local ok, failure = xpcall(function()
			assert(Profile:LoadPlayerAsync(p).ok, "Retention writer fixture profile load failed")
			callback(p, backend, player, function()
				return now
			end)
		end, debug.traceback)
		Profile:_ResetForTests()
		assert(ok, failure)
	end
	describe("Phase14 supply milestone actual profile writer durability", function()
		it(
			"reacquires across claims 6→7 and 13→14 with a lost acknowledgement and exact once-only rewards",
			function()
				writerCase(function(p, backend, player)
					assert(
						Profile:CommitMutation(p, function(data)
							firstBank(data, "supply:onboard")
							return true
						end).ok,
						"supply onboarding rejected"
					)
					local function claim(n)
						local result = Profile:CommitMutation(p, function(data)
							return Rules.ClaimSupply(data, n * 86400 + 20)
						end)
						assert(result.ok, "supply fixture claim rejected:" .. tostring(result.code))
					end
					local function rejoin()
						assert(Profile:ClosePlayerAsync(p, "Phase14SupplyRejoin").ok, "supply fixture close failed")
						p.Parent = nil
						p = player()
						assert(Profile:LoadPlayerAsync(p).ok, "supply fixture reacquire failed")
					end
					for n = 1, 6 do
						claim(n)
					end
					assert(Profile:SaveNowAsync(p, "Phase14Claim6").ok, "claim6 covering save failed")
					rejoin()
					claim(7)
					backend.CommitThenFailSaveCount = 1
					assert(Profile:SaveNowAsync(p, "Phase14Claim7LostAck").ok, "claim7 reconciliation failed")
					rejoin()
					local data = Profile:GetReadableData(p)
					expect(data.Economy.Balance).to.equal(2000000000)
					expect(data.Retention.Supplies.lifetimeClaims).to.equal(7)
					expect(data.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
					local duplicate = Profile:CommitMutation(p, function(current)
						return Rules.ClaimSupply(current, 7 * 86400 + 30)
					end)
					expect(duplicate.committed == true).to.equal(false)
					expect(duplicate.code).to.equal("SUPPLY_ALREADY_CLAIMED")
					expect(data.Economy.Balance).to.equal(2000000000)
					for n = 8, 13 do
						claim(n)
					end
					assert(Profile:SaveNowAsync(p, "Phase14Claim13").ok, "claim13 covering save failed")
					rejoin()
					claim(14)
					backend.CommitThenFailSaveCount = 1
					assert(Profile:SaveNowAsync(p, "Phase14Claim14LostAck").ok, "claim14 reconciliation failed")
					rejoin()
					data = Profile:GetReadableData(p)
					expect(data.Economy.Balance).to.equal(4000000000)
					expect(data.Retention.Supplies.lifetimeClaims).to.equal(14)
					expect(data.Commerce.Entitlements.P14_BASE_EXPEDITION).to.equal(true)
					expect(data.Commerce.StarterPackClaimed).to.equal(false)
				end)
			end
		)
	end)
	describe("Phase14 CP1 actual profile writer with synthetic backend", function()
		it("rolls uncommitted qualifying progress and reward back together on rejection", function()
			writerCase(function(p)
				for i = 1, 2 do
					assert(
						Profile:CommitMutation(p, function(data)
							firstBank(data, "rollback:" .. i)
							return true
						end).ok,
						"Retention rollback fixture bank seed rejected"
					)
				end
				local result = Profile:CommitMutation(p, function(data)
					firstBank(data, "rollback:3")
					return false, { ok = false, code = "CONTROLLED_REJECTION" }
				end)
				expect(result.ok).to.equal(false)
				local data = Profile:GetReadableData(p)
				expect(data.Retention.Day.bring_them_home.count).to.equal(2)
				expect(data.Economy.Balance).to.equal(0)
				expect(data.Collection.BrainrotInstances["rollback:3"]).to.equal(nil)
			end)
		end)
		it("commits bank progress Cash and marker in one covering save then same-owner reacquires", function()
			writerCase(function(p, _backend, player)
				for i = 1, 3 do
					assert(
						Profile:CommitMutation(p, function(data)
							firstBank(data, "saved:" .. i)
							return true
						end).ok,
						"Retention durable bank fixture mutation rejected"
					)
				end
				local result = Profile:SaveNowAsync(p, "Phase14CP1")
				expect(result.ok).to.equal(true)
				expect(Profile:IsRevisionConfirmed(p, 3)).to.equal(true)
				expect(Profile:ClosePlayerAsync(p, "Phase14CP1Rejoin").ok).to.equal(true)
				p.Parent = nil
				local second = player()
				expect(Profile:LoadPlayerAsync(second).ok).to.equal(true)
				local data = Profile:GetReadableData(second)
				expect(data.Retention.Day.bring_them_home.count).to.equal(3)
				expect(data.Retention.Day.bring_them_home.paid).to.equal(true)
				expect(data.Economy.Balance).to.equal(750000000)
				expect(firstBank(data, "saved:3")).to.equal(nil)
				expect(data.Economy.Balance).to.equal(750000000)
			end)
		end)
		it("retries uncertain accepted save with the same canonical state and never pays twice", function()
			writerCase(function(p, backend)
				for i = 1, 3 do
					assert(
						Profile:CommitMutation(p, function(data)
							firstBank(data, "uncertain:" .. i)
							return true
						end).ok,
						"Retention uncertain-save bank fixture mutation rejected"
					)
				end
				backend.CommitThenFailSaveCount = 1
				expect(Profile:SaveNowAsync(p, "Phase14CP1Uncertain").ok).to.equal(true)
				local data = Profile:GetReadableData(p)
				expect(data.Economy.Balance).to.equal(750000000)
				expect(data.Retention.Day.bring_them_home.paidCash).to.equal(750000000)
				expect(firstBank(data, "uncertain:3")).to.equal(nil)
				expect(data.Economy.Balance).to.equal(750000000)
			end)
		end)
	end)
end
