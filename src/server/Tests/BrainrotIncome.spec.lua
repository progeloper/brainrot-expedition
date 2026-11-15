--!nocheck
-- Phase13 expected earning amounts use original CPS ×1M; timestamps/synthetic wallet failures are unchanged.
return function()
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local Players = game:GetService("Players")
	local function item(id, species)
		return { ItemId = id, BrainrotId = species }
	end
	local function run(callback)
		local time = 0
		local observer
		local subscriptions = 0
		local homes, stores = {}, {}
		local accounts, closing = {}, nil
		local wallet = {}
		function wallet:IsReady(p)
			local a = accounts[p]
			return a and a.Ready and not a.Released and (p.Parent == Players or a.Closing)
		end
		function wallet:AddCash(p, amount)
			local a = accounts[p]
			if not self:IsReady(p) or a.Reject then
				return { committed = false, code = "TEST_REJECTED" }
			end
			if a.BeforeCredit then
				a.BeforeCredit()
			end
			a.Balance += amount
			a.Credits += 1
			return { committed = true, code = "CREDITED" }
		end
		function wallet:SyncBalance(p)
			local a = accounts[p]
			if not a then
				return false, "FIXTURE_ACCOUNT_ABSENT"
			end
			if a.MirrorFails then
				return false, "fixture mirror failure"
			end
			a.Mirror = a.Balance
			return true
		end
		function wallet:BeginClosing(p)
			local a = accounts[p]
			if not a then
				return false
			end
			a.Closing = true
			return true
		end
		function wallet:ReleaseAccount(p)
			local a = accounts[p]
			if not a then
				return false
			end
			a.Released = true
		end
		local baseApi = {}
		function baseApi:SubscribeSessionClosing(onClosing)
			closing = onClosing
			return {
				Disconnect = function()
					closing = nil
				end,
			}
		end
		function baseApi:GetBase(p)
			return homes[p]
		end
		function baseApi:IsOwner(p, base)
			return homes[p] == base and p.Parent == Players
		end
		local storageApi = {}
		function storageApi:GetStorageForPlayer(p)
			return stores[p]
		end
		function storageApi:ObserveStorage(value)
			observer = value
			subscriptions += 1
			return function()
				observer = nil
				subscriptions -= 1
			end
		end
		local function owner(id, contents)
			local p = { Name = "IncomeOwner" .. id, UserId = id, Parent = Players }
			accounts[p] = { Balance = 0, Credits = 0, Ready = true, Released = false }
			local base = {}
			local s = {
				Base = base,
				BaseId = "Base_" .. id,
				OwnerUserId = id,
				Active = true,
				Revision = 0,
				Contents = contents or {},
				PlatformIncome = {},
			}
			for index = 1, 12 do
				s.PlatformIncome[index] = 0
			end
			function s:IsActive()
				return self.Active
			end
			function s:GetRevision()
				return self.Revision
			end
			function s:GetSnapshot()
				return self.Contents
			end
			function s:GetPlatformIds()
				return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
			end
			function s:IsValidPlatformId(index)
				return self.Active and type(index) == "number" and index >= 1 and index <= 12
			end
			function s:GetPlatformRecord(index)
				local entry = self.Contents[index]
				return if entry
					then {
						SlotIndex = index,
						ItemId = entry.ItemId,
						BrainrotId = entry.BrainrotId,
						Metadata = entry.Metadata or {},
					}
					else nil
			end
			function s:GetUnclaimedCashExact(index)
				return self.PlatformIncome[index]
			end
			function s:AddUnclaimedCashExact(index, amount)
				self.PlatformIncome[index] += amount
				return true
			end
			function s:SetUnclaimedCashExact(index, amount)
				self.PlatformIncome[index] = amount
				return true
			end
			homes[p], stores[p] = base, s
			return p, s
		end
		local a, storage = owner(1)
		local b, other = owner(2)
		local ok, failure = xpcall(function()
			Income:Start({
				NowMs = function()
					return time
				end,
				Storage = storageApi,
				Base = baseApi,
				Wallet = wallet,
			})
			Income:BindStorage(a, storage)
			Income:BindStorage(b, other)
			callback({
				a = a,
				b = b,
				storage = storage,
				other = other,
				owner = owner,
				stores = stores,
				homes = homes,
				observer = observer,
				accounts = accounts,
				wallet = wallet,
				state = Income:TrackPlayer(a),
				close = function(player)
					closing(player)
				end,
				time = function(value)
					time = value
				end,
				subscriptions = function()
					return subscriptions
				end,
				commit = function(p, s, contents, at)
					time = at
					s.Contents = contents
					s.Revision += 1
					observer.OnCommitted(p, s, s.Revision, contents)
				end,
			})
		end, debug.traceback)
		-- Reset only injected fixture failures before disposing this isolated test session.
		for p, account in accounts do
			account.Ready = true
			account.Reject = false
			account.BeforeCredit = nil
			local snapshot = Income:GetStateSnapshot(p)
			if snapshot then
				time = math.max(time, snapshot.LastAccruedMs or 0)
				p.Parent = Players
				local state = Income:TrackPlayer(p)
				if state then
					state.AccrualFault = false
					state.CreditUncertain = false
					state.FinalAccrualError = nil
				end
			end
		end
		Income:Destroy()
		assert(ok, failure)
	end
	describe("Phase 5D committed income rates", function()
		it("calculates exact integer-tenths rates and ignores item-provided multipliers", function()
			expect(Income.CalculateStorageRate({})).to.equal(0)
			expect(Income.CalculateStorageRate({ item("a", "BRT_007") })).to.equal(20000000)
			expect(Income.CalculateStorageRate({ item("a", "BRT-007"), item("b", "BRT-007") })).to.equal(
				40000000
			)
			local a = item("a", "BRT-001")
			a.cashPerSecond = 999
			a.Metadata = { Multiplier = 100 }
			expect(Income.CalculateStorageRate({ a, item("b", "BRT-004"), item("c", "BRT-019") })).to.equal(
				149000000
			)
		end)
		it(
			"counts duplicate individual IDs only once and reports unknown or missing identity",
			function()
				local snapshot = {
					item("a", "BRT-007"),
					item("a", "BRT-007"),
					item("b", "unknown"),
					item("", "BRT-035"),
				}
				local rate, diagnostics = Income.CalculateStorageRate(snapshot)
				expect(rate).to.equal(20000000)
				expect(#diagnostics).to.equal(3)
				expect(#snapshot).to.equal(4)
			end
		)
		it(
			"applies consecutive revisions in the same millisecond and ignores old/duplicate events",
			function()
				run(function(f)
					f.commit(f.a, f.storage, { item("a", "BRT-007") }, 750)
					f.commit(f.a, f.storage, { item("a", "BRT-007"), item("b", "BRT-004") }, 750)
					expect(Income:GetIncomeRate(f.a)).to.equal(4300000)
					f.observer.OnCommitted(f.a, f.storage, 1, {})
					f.observer.OnCommitted(f.a, f.storage, 2, {})
					expect(Income:GetStateSnapshot(f.a).ChangedAtMs).to.equal(750)
					expect(Income:GetIncomeRate(f.b)).to.equal(0)
				end)
			end
		)
		it(
			"tracks only committed snapshots and preserves rate through character/cart changes",
			function()
				run(function(f)
					local cargoOnly = item("cargo", "BRT-035")
					expect(cargoOnly.BrainrotId).to.equal("BRT-035")
					f.commit(f.a, f.storage, { item("a", "BRT-007"), item("b", "BRT-007") }, 100)
					f.a.Character = {}
					f.a.Character = nil
					cargoOnly = nil
					expect(Income:GetIncomeRate(f.a)).to.equal(4000000)
					f.storage.Reservation = item("pending", "BRT-035")
					expect(Income:GetIncomeRate(f.a)).to.equal(4000000)
				end)
			end
		)
		it(
			"detaches before storage invalidation and rejects stale callbacks after rebinding",
			function()
				run(function(f)
					f.commit(f.a, f.storage, { item("a", "BRT-007") }, 100)
					f.time(200)
					f.observer.OnReleasing(f.a, f.storage)
					f.storage.Active = false
					f.stores[f.a] = nil
					f.homes[f.a] = nil
					expect(Income:GetIncomeRate(f.a)).to.equal(0)
					local replacement, nextStorage = f.owner(1, { item("new", "BRT-004") })
					f.a.Parent = nil
					Income:UntrackPlayer(f.a)
					Income:BindStorage(replacement, nextStorage)
					f.observer.OnCommitted(f.a, f.storage, 2, { item("bad", "BRT-035") })
					expect(Income:GetIncomeRate(replacement)).to.equal(2300000)
				end)
			end
		)
		it("does not duplicate listeners or reset an identical binding", function()
			run(function(f)
				f.commit(f.a, f.storage, { item("a", "BRT-007") }, 100)
				f.time(900)
				Income:Start()
				Income:BindStorage(f.a, f.storage)
				Income:TrackPlayer(f.a)
				expect(f.subscriptions()).to.equal(1)
				expect(Income:GetStateSnapshot(f.a).ChangedAtMs).to.equal(100)
			end)
		end)
	end)

	local function balance(f, expected, units)
		expect(f.accounts[f.a].Balance).to.equal(expected)
		expect(f.state.PendingUnits).to.equal(units)
	end
	local function seed(f, entries)
		f.commit(f.a, f.storage, entries, 0)
	end
	local function step(f, at)
		f.time(at)
		Income:Step()
		for player in f.accounts do
			local storage = f.stores[player]
			if storage then
				Income:BindStorage(player, storage)
			end
			local state = Income:TrackPlayer(player)
			if state and not state.Closing then
				Income:AccrueTo(state, at)
				Income:FlushCash(player, state)
			end
		end
	end
	describe("Phase 5D exact elapsed income awards", function()
		it("pays nothing for empty storage or cargo-only items", function()
			run(function(f)
				f.a.Cargo = { item("cargo", "BRT-035") }
				step(f, 10000)
				balance(f, 0, 0)
			end)
		end)
		it(
			"pays 30,000 for one development species and 60,000 for two distinct individuals over ten seconds",
			function()
				run(function(f)
					seed(f, { item("a", "BRT_007") })
					step(f, 10000)
					balance(f, 20000000, 0)
					f.commit(f.b, f.other, { item("b", "BRT-007"), item("c", "BRT-007") }, 10000)
					step(f, 20000)
					expect(f.accounts[f.b].Balance).to.equal(40000000)
				end)
			end
		)
		it("conserves scaled 3,450/s over ten separate awards with exact fractional carry", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				for second = 1, 10 do
					step(f, second * 1000)
					expect(f.accounts[f.a].Balance * 10000 + f.state.PendingUnits).to.equal(
						23000000000 * second
					)
				end
				balance(f, 23000000, 0)
			end)
		end)
		it("awards 223,500 for the mixed scaled catalogue rate", function()
			run(function(f)
				seed(f, { item("a", "BRT-001"), item("b", "BRT-004"), item("c", "BRT-019") })
				step(f, 10000)
				balance(f, 149000000, 0)
			end)
		end)
		it("pays actual delayed elapsed time rather than one artificial second", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				step(f, 3500)
				balance(f, 8050000, 0)
			end)
		end)
		it("does not backdate a 750ms first deposit", function()
			run(function(f)
				f.commit(f.a, f.storage, { item("a", "BRT-004") }, 750)
				step(f, 1000)
				balance(f, 575000, 0)
			end)
		end)
		it("integrates both sides of a mid-interval rate increase", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				f.commit(f.a, f.storage, { item("a", "BRT-007"), item("b", "BRT-004") }, 750)
				step(f, 1000)
				balance(f, 2575000, 0)
				step(f, 2000)
				balance(f, 6875000, 0)
			end)
		end)
		it("retains 1,380 after a 400ms release without earning beyond release", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				f.time(400)
				f.observer.OnReleasing(f.a, f.storage)
				f.storage.Active = false
				f.stores[f.a] = nil
				step(f, 1000)
				balance(f, 920000, 0)
			end)
		end)
		it("settles a storage change and accounts for an unbound interval at zero", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				f.time(1000)
				f.observer.OnReleasing(f.a, f.storage)
				f.storage.Active = false
				f.stores[f.a] = nil
				f.time(5000)
				f.storage.Active = true
				f.storage.Contents = { item("a", "BRT-007"), item("b", "BRT-004") }
				f.storage.Revision += 1
				f.stores[f.a] = f.storage
				f.observer.OnBound(f.a, f.storage)
				step(f, 6000)
				balance(f, 6300000, 0)
			end)
		end)
		it(
			"retains earnings on precommit credit rejection and retries exactly once successfully",
			function()
				run(function(f)
					seed(f, { item("a", "BRT-004") })
					f.accounts[f.a].Reject = true
					step(f, 1000)
					balance(f, 0, 23000000000)
					f.accounts[f.a].Reject = false
					step(f, 2000)
					balance(f, 4600000, 0)
				end)
			end
		)
		it("does not recredit a failed cash mirror or repeated timestamp", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				f.accounts[f.a].MirrorFails = true
				step(f, 1000)
				balance(f, 2300000, 0)
				f.accounts[f.a].MirrorFails = false
				step(f, 1000)
				balance(f, 2300000, 0)
				expect(f.accounts[f.a].Mirror).to.equal(2300000)
				expect(f.accounts[f.a].Credits).to.equal(1)
			end)
		end)
		it(
			"keeps remainder through reset and pays pending whole units even at zero current rate",
			function()
				run(function(f)
					seed(f, { item("a", "BRT-004") })
					step(f, 1000)
					balance(f, 2300000, 0)
					f.a.Character = {}
					f.a.Character = nil
					f.accounts[f.a].Ready = false
					step(f, 2000)
					balance(f, 2300000, 23000000000)
					f.observer.OnReleasing(f.a, f.storage)
					f.stores[f.a] = nil
					f.accounts[f.a].Ready = true
					step(f, 3000)
					balance(f, 4600000, 0)
				end)
			end
		)
		it("does not auto-award when an initially unavailable wallet becomes ready", function()
			run(function(f)
				local p, s = f.owner(3, { item("new", "BRT-007") })
				f.accounts[p].Ready = false
				Income:BindStorage(p, s)
				step(f, 10000)
				expect(f.accounts[p].Balance).to.equal(0)
				f.accounts[p].Ready = true
				step(f, 11000)
				expect(f.accounts[p].Balance).to.equal(0)
				step(f, 12000)
				expect(f.accounts[p].Balance).to.equal(0)
			end)
		end)
		it("protects a reentrant flush and subtracts from current pending units", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				f.accounts[f.a].BeforeCredit = function()
					expect(Income:FlushCash(f.a, f.state).code).to.equal("BUSY")
					Income:AccrueTo(f.state, 1100)
				end
				step(f, 1000)
				balance(f, 2000000, 2000000000)
				f.accounts[f.a].BeforeCredit = nil
				f.time(1100)
			end)
		end)
		it(
			"ignores duplicate commit notifications without resetting fractional accounting",
			function()
				run(function(f)
					seed(f, { item("a", "BRT-004") })
					step(f, 1000)
					f.time(1500)
					f.observer.OnCommitted(f.a, f.storage, 1, { item("wrong", "BRT-035") })
					step(f, 2000)
					balance(f, 4600000, 0)
				end)
			end
		)
		it("closes without automatically claiming platform income", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				f.time(1000)
				f.a.Parent = nil
				f.close(f.a)
				expect(f.accounts[f.a].Balance).to.equal(0)
				expect(f.accounts[f.a].Released).to.equal(true)
				expect(Income:GetStateSnapshot(f.a)).to.equal(nil)
				f.close(f.a)
				expect(f.accounts[f.a].Credits).to.equal(0)
			end)
		end)
		it("does not invoke the currency award path during finalisation", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				f.accounts[f.a].Reject = true
				f.time(1000)
				local first = Income:FinalizePlayerSession(f.a, 1000)
				expect(first.ok).to.equal(true)
				expect(f.accounts[f.a].Released).to.equal(true)
				step(f, 9000)
				expect(f.accounts[f.a].Balance).to.equal(0)
				f.accounts[f.a].Reject = false
				expect(Income:FinalizePlayerSession(f.a, 9000).ok).to.equal(true)
				expect(f.accounts[f.a].Balance).to.equal(0)
			end)
		end)
		it("does not transfer money, rates or fractions when the same BaseId is reused", function()
			run(function(f)
				seed(f, { item("a", "BRT-004") })
				step(f, 1000)
				balance(f, 2300000, 0)
				f.close(f.a)
				f.a.Parent = nil
				f.storage.Active = false
				local p, s = f.owner(1, {})
				s.Base = f.storage.Base
				s.BaseId = f.storage.BaseId
				f.homes[p] = s.Base
				f.time(2000)
				Income:BindStorage(p, s)
				f.observer.OnCommitted(f.a, f.storage, 2, { item("stale", "BRT-035") })
				step(f, 3000)
				expect(f.accounts[p].Balance).to.equal(0)
				expect(Income:GetStateSnapshot(p).PendingUnits).to.equal(0)
			end)
		end)
		it(
			"rebases a missed revision at a fresh boundary without paying an uncertain interval",
			function()
				run(function(f)
					seed(f, { item("a", "BRT-007") })
					step(f, 500)
					balance(f, 1000000, 0)
					f.storage.Contents = { item("b", "BRT-004") }
					f.storage.Revision += 2
					step(f, 1500)
					balance(f, 1000000, 0)
					step(f, 2500)
					balance(f, 3300000, 0)
				end)
			end
		)
		it("rejects a late change timestamp without applying a new rate backwards", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				step(f, 1000)
				balance(f, 2000000, 0)
				f.time(1500)
				f.storage.Contents = { item("b", "BRT-004") }
				f.storage.Revision += 1
				Income:ApplyCommittedSnapshot(f.a, f.storage, 2, f.storage.Contents, 750)
				step(f, 2500)
				balance(f, 4300000, 0)
			end)
		end)
		it("rejects invalid time/rate/overflow before changing numeric counters", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				step(f, 1000)
				for _, at in { -1, 999, math.huge, 0 / 0, 1000.5 } do
					expect(Income:AccrueTo(f.state, at)).to.equal(false)
				end
				expect(f.state.LastAccruedMs).to.equal(1000)
				f.state.RateTenths = math.huge
				expect(Income:AccrueTo(f.state, 2000)).to.equal(false)
				f.state.AccrualFault = false
				f.state.RateTenths = 9007199254740991
				expect(Income:AccrueTo(f.state, 2000)).to.equal(false)
				expect(f.state.LastAccruedMs).to.equal(1000)
				f.state.RateTenths = 20
				f.state.AccrualFault = false
			end)
		end)
		it("does not blindly retry an ambiguous throwing wallet", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				local credit = f.wallet.AddCash
				function f.wallet:AddCash(p, amount, reason)
					credit(self, p, amount, reason)
					error("injected ambiguous post-credit throw")
				end
				step(f, 1000)
				step(f, 2000)
				expect(f.accounts[f.a].Credits).to.equal(1)
				expect(f.state.CreditUncertain).to.equal(true)
				-- Test-only reconciliation before disposal; production never guesses/retries.
				f.wallet.AddCash = credit
				f.state.PendingUnits -= 30000000
				f.state.CreditUncertain = false
			end)
		end)
		it(
			"recovers a missing binding at a fresh boundary instead of leaving income stale forever",
			function()
				run(function(f)
					f.time(100)
					f.observer.OnReleasing(f.a, f.storage)
					f.stores[f.a] = nil
					f.storage.Active = false
					step(f, 1000)
					f.storage.Active = true
					f.storage.Revision += 1
					f.storage.Contents = { item("new", "BRT-007") }
					f.stores[f.a] = f.storage -- injected missed OnBound
					step(f, 2000)
					balance(f, 0, 0)
					step(f, 3000)
					balance(f, 2000000, 0)
				end)
			end
		)
		it("isolates one unavailable wallet while another owner earns normally", function()
			run(function(f)
				seed(f, { item("a", "BRT-007") })
				f.commit(f.b, f.other, { item("b", "BRT-004") }, 0)
				f.accounts[f.a].Ready = false
				step(f, 1000)
				balance(f, 0, 20000000000)
				expect(f.accounts[f.b].Balance).to.equal(2300000)
			end)
		end)
	end)
end
