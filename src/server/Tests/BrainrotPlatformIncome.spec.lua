--!nocheck
-- Phase13 expected future earnings are ×1M; explicit old saved ledgers stay unchanged.

return function()
	local Players = game:GetService("Players")
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
	local ProfileSchema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Presentation = require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation)

	local function createStorage(baseId, ownerUserId, savedData, initialOccupants)
		local base = Instance.new("Model")
		base.Name = "Spec_PlatformIncome_" .. baseId
		base:SetAttribute("BaseId", baseId)
		base:SetAttribute("OwnerUserId", ownerUserId)
		base:SetAttribute("BaseOwnershipRevision", 1)
		local slots = {}
		for index = 1, 12 do
			local platform = Instance.new("Part")
			platform.Name = string.format("Slot_%02d", index)
			platform:SetAttribute("SlotIndex", index)
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name = "BrainrotPlacement"
			marker.Parent = platform
			slots[index] = { Index = index, Platform = platform, Marker = marker }
		end
		local presentationToken = assert(Presentation.Begin(base, 12, {OwnerUserId=ownerUserId,AssignmentRevision=1,ProfileReady=true}))
		for index, slot in slots do Presentation.BindSlot(slot.Platform, base, index, presentationToken) end
		Presentation.Publish(base, presentationToken, 12)
		-- Restoration is not a new deposit. Reconstruct the synthetic saved owner
		-- references before binding, then exercise the production restore boundary.
		if savedData and initialOccupants then
			if not savedData.Base then
				local legacy = savedData
				savedData = ProfileSchema.CreateDefault()
				for key, entry in legacy.PlatformIncome or {} do
					savedData.Base.Slots[key].accumulatedCash = entry.UnclaimedCashExact
				end
			end
			for _, entry in initialOccupants do
				savedData.Collection.BrainrotInstances[entry.ItemId] =
					{ speciesId = entry.BrainrotId, metadata = {} }
				savedData.Base.Slots[tostring(entry.PlatformId)].brainrotId = entry.ItemId
			end
		end
		local storage = BaseStorage.new(base, ownerUserId, slots, savedData)
		for _, entry in initialOccupants or {} do
			local record = {
				ItemId = entry.ItemId,
				BrainrotId = entry.BrainrotId,
				Metadata = {},
			}
			if savedData then
				assert(storage:BindRestoredRecord(entry.PlatformId, record, Instance.new("Model")))
			else
				local token = assert(storage:TryReserveSlot(entry.ItemId, entry.PlatformId))
				assert(storage:CommitReservation(token, record, Instance.new("Model")))
			end
		end
		return storage, base
	end

	local function run(options, callback)
		options = options or {}
		local now = options.InitialTime or 0
		local clockReads = 0
		local player = { Name = "IncomeOwner", UserId = options.UserId or 701, Parent = Players }
		local outsider = { Name = "Outsider", UserId = 702, Parent = Players }
		local storage, base = createStorage(
			options.BaseId or "Base_Income",
			player.UserId,
			options.SavedData,
			options.InitialOccupants
		)
		local observer
		local storageApi = { WorldRecords = { awake = true }, CargoRecords = { cargo = true } }
		function storageApi:GetStorageForPlayer(subject)
			return if subject == player then storage else nil
		end
		function storageApi:ObserveStorage(value)
			observer = value
			return function()
				observer = nil
			end
		end
		local baseApi = {}
		function baseApi:GetBase(subject)
			return if subject == player then base else nil
		end
		function baseApi:GetAssignment(subject)
			return if subject == player then {Player=player,Base=base,Generation=1} else nil
		end
		function baseApi:IsOwner(subject, candidate)
			return subject == player and candidate == base and subject.Parent == Players
		end
		function baseApi:SubscribeSessionClosing(_callbackValue)
			return {
				Disconnect = function() end,
			}
		end
		local accounts = {
			[player] = { Balance = 0, Credits = 0, Ready = true },
			[outsider] = { Balance = 0, Credits = 0, Ready = true },
		}
		local wallet = { Reject = false, BeforeAward = nil }
		function wallet:IsReady(subject)
			local account = accounts[subject]
			return account ~= nil and account.Ready and not account.Released
		end
		function wallet:AddCash(subject, amount, reason)
			local account = accounts[subject]
			if not self:IsReady(subject) or self.Reject then
				return { committed = false, code = "TEST_REJECTED" }
			end
			if self.BeforeAward then
				self.BeforeAward()
			end
			account.Balance += amount
			account.Credits += 1
			account.LastReason = reason
			return { committed = true, code = "CREDITED" }
		end
		function wallet:SyncBalance()
			return true
		end
		function wallet:BeginClosing(subject)
			local account = accounts[subject]
			if account then
				account.Closing = true
			end
			return true
		end
		function wallet:ReleaseAccount(subject)
			local account = accounts[subject]
			if account then
				account.Released = true
			end
		end
		local scheduler = { Connections = 0, Callback = nil }
		function scheduler:Connect(callbackValue)
			self.Connections += 1
			self.Callback = callbackValue
			local connected = true
			return {
				Disconnect = function()
					if connected then
						connected = false
						scheduler.Connections -= 1
						scheduler.Callback = nil
					end
				end,
			}
		end

		assert(Income:Init({
			Now = function()
				clockReads += 1
				return now
			end,
			Storage = storageApi,
			Base = baseApi,
			Wallet = wallet,
			Profile = options.Profile or false,
			ResolvePlatformRate = if options.Rates
				then function(brainrotId)
					return options.Rates[brainrotId]
				end
				else nil,
			Heartbeat = scheduler,
		}))
		assert(Income:Start())
		observer.OnBound(player, storage)

		local fixture = {
			Player = player,
			Outsider = outsider,
			Storage = storage,
			BaseId = base:GetAttribute("BaseId"),
			Accounts = accounts,
			Wallet = wallet,
			Scheduler = scheduler,
			SetTime = function(value)
				now = value
			end,
			ClockReads = function()
				return clockReads
			end,
			Deposit = function(platformId, itemId, brainrotId)
				observer.OnChanging(player, storage)
				local token = assert(storage:TryReserveSlot(itemId, platformId))
				assert(storage:CommitReservation(token, {
					ItemId = itemId,
					BrainrotId = brainrotId,
					Metadata = {},
				}, Instance.new("Model")))
				observer.OnCommitted(player, storage, storage:GetRevision(), storage:GetSnapshot())
			end,
			Remove = function(platformId, expectedItemId)
				observer.OnChanging(player, storage)
				local record, display, reason =
					storage:RemovePlatformRecord(platformId, expectedItemId)
				if record then
					observer.OnCommitted(
						player,
						storage,
						storage:GetRevision(),
						storage:GetSnapshot()
					)
					if display then
						display:Destroy()
					end
				end
				return record, reason
			end,
		}
		local ok, failure = xpcall(function()
			callback(fixture)
		end, debug.traceback)
		Income:Stop()
		storage:Destroy()
		base:Destroy()
		assert(ok, failure)
	end

	describe("Phase 6C-1 species-based per-platform income", function()
		it("restores saved cash without offline catch-up and starts a fresh live clock", function()
			local saved = ProfileSchema.CreateDefault()
			saved.Base.Slots["1"].accumulatedCash = 10
			run({
				InitialTime = 1000,
				SavedData = saved,
				Rates = { BRT_007 = 2 },
				InitialOccupants = {
					{ PlatformId = 1, ItemId = "saved-a", BrainrotId = "BRT_007" },
				},
			}, function(f)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(10)
				f.SetTime(1010)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(30)
			end)
		end)

		it("retains platform cash across occupant rate changes", function()
			run({ Rates = { BRT_007 = 2, BRT_011 = 1.8 } }, function(f)
				assert(f.Storage:SetUnclaimedCashExact(1, 10))
				f.Deposit(1, "continuity-a", "BRT_007")
				f.SetTime(5)
				local removed = f.Remove(1, "continuity-a")
				expect(removed.ItemId).to.equal("continuity-a")
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20)
				f.SetTime(105)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20)
				f.Deposit(1, "continuity-b", "BRT_011")
				f.SetTime(115)
				expect(Income:Step()).to.equal(true)
				expect(math.abs(f.Storage:GetUnclaimedCashExact(1) - 38) < 1e-6).to.equal(true)
			end)

			it("freezes live accrual at the coordinated profile close cutoff", function()
				local saved = ProfileSchema.CreateDefault()
				local owner = { Writable = true, Revision = 0 }
				function owner:GetReadableData()
					return saved
				end
				function owner:IsWritable()
					return self.Writable
				end
				function owner:MarkDirty()
					if not self.Writable then
						return nil, "PROFILE_NOT_WRITABLE"
					end
					self.Revision += 1
					return self.Revision
				end
				run({
					InitialTime = 0,
					SavedData = saved,
					Profile = owner,
					Rates = { BRT_007 = 2 },
					InitialOccupants = {
						{ PlatformId = 1, ItemId = "closing-a", BrainrotId = "BRT_007" },
					},
				}, function(f)
					f.SetTime(5)
					owner.Writable = false
					local changed, reason = Income:PrepareForSave(f.Player, 5)
					expect(reason).to.equal(nil)
					expect(changed).to.equal(true)
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(10)
					f.SetTime(50)
					expect(Income:Step()).to.equal(true)
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(10)
				end)
			end)

			it(
				"samples the income owner's clock when snapshot coordination omits a cutoff",
				function()
					local saved = ProfileSchema.CreateDefault()
					local owner = { Writable = true, Revision = 0 }
					function owner:GetReadableData()
						return saved
					end
					function owner:IsWritable()
						return self.Writable
					end
					function owner:MarkDirty()
						self.Revision += 1
						return self.Revision
					end
					run({
						InitialTime = 100,
						SavedData = saved,
						Profile = owner,
						Rates = { BRT_007 = 2 },
						InitialOccupants = {
							{ PlatformId = 1, ItemId = "snapshot-clock-a", BrainrotId = "BRT_007" },
						},
					}, function(f)
						f.SetTime(105)
						local changed, reason = Income:PrepareForSave(f.Player)
						expect(reason).to.equal(nil)
						expect(changed).to.equal(false)
						expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(10)
					end)
				end
			)
		end)
		it(
			"accrues a twelve-plaque refresh once without changing exact earnings or claims",
			function()
				local occupants = {}
				for index = 1, 12 do
					table.insert(
						occupants,
						{ PlatformId = index, ItemId = "batch-" .. index, BrainrotId = "BRT_001" }
					)
				end
				run({ InitialOccupants = occupants }, function(f)
					local requests = {}
					for index = 1, 12 do
						table.insert(requests, { BaseId = f.BaseId, PlatformId = index })
					end
					local accrualCalls = 0
					local original = f.Storage.AddUnclaimedCashExact
					f.Storage.AddUnclaimedCashExact = function(storage, ...)
						accrualCalls += 1
						return original(storage, ...)
					end
					f.SetTime(10)
					local before = f.ClockReads()
					local snapshots = Income:SyncPlatformSnapshots(requests)
					expect(f.ClockReads() - before).to.equal(1)
					expect(accrualCalls).to.equal(12)
					for index = 1, 12 do
						expect(snapshots[index].SnapshotServerTime).to.equal(10)
						expect(f.Storage:GetUnclaimedCashExact(index)).to.equal(18000000)
					end
					Income:SyncPlatformSnapshots(requests)
					expect(accrualCalls).to.equal(12) -- same time does not pay twice
					f.SetTime(11)
					local result = Income:TryClaimPlatform(f.Player, f.BaseId, 1)
					expect(math.abs(result.paid - 19800000) < 1e-6).to.equal(true)
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(0)
					expect(f.Storage:GetPlatformRecord(1).ItemId).to.equal("batch-1")
				end)
			end
		)

		it("does no accrual for an empty batch and rejects invalid platform snapshots", function()
			run({}, function(f)
				local before = f.ClockReads()
				expect(next(Income:SyncPlatformSnapshots({}))).to.equal(nil)
				expect(f.ClockReads()).to.equal(before)
				expect(Income:SyncPlatformSnapshot("missing", 1)).to.equal(nil)
				expect(Income:SyncPlatformSnapshot(f.BaseId, 99)).to.equal(nil)
			end)
		end)
		it("uses catalogue rates for the sixty-second control and fractional species", function()
			run({}, function(f)
				f.Deposit(1, "control-brainrot", "BRT_007")
				f.SetTime(60)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(120000000)
			end)

			run({}, function(f)
				f.Deposit(1, "fractional-brainrot", "BRT_001")
				f.SetTime(1)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(1800000)
				f.SetTime(10)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(18000000)
			end)
		end)

		it("settles and retains cash before replacement", function()
			run({}, function(f)
				f.Deposit(1, "old-brainrot", "BRT_007")
				f.SetTime(10)
				local removed = f.Remove(1, "old-brainrot")
				expect(removed.BrainrotId).to.equal("BRT_007")
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20000000)

				f.Deposit(1, "new-brainrot", "BRT_012")
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20000000)
				f.SetTime(20)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(65000000)
				expect(f.Storage:GetPlatformRecord(1).ItemId).to.equal("new-brainrot")
			end)
		end)

		it("keeps different species and platform claims independent", function()
			run({}, function(f)
				f.Deposit(1, "common-brainrot", "BRT_007")
				f.Deposit(2, "rare-brainrot", "BRT_019")
				f.SetTime(10)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20000000)
				expect(math.abs(f.Storage:GetUnclaimedCashExact(2) - 108000000) < 1e-6).to.equal(true)

				local claimed = Income:TryClaimPlatform(f.Player, f.BaseId, 1)
				expect(claimed.paid).to.equal(20000000)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(0)
				expect(math.abs(f.Storage:GetUnclaimedCashExact(2) - 108000000) < 1e-6).to.equal(true)
				expect(f.Storage:GetPlatformRecord(1).ItemId).to.equal("common-brainrot")

				f.SetTime(20)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(20000000)
				expect(math.abs(f.Storage:GetUnclaimedCashExact(2) - 216000000) < 1e-6).to.equal(true)
			end)
		end)

		it("preserves existing cash and earns nothing for an unknown species", function()
			run({
				SavedData = {
					PlatformIncome = { ["5"] = { UnclaimedCashExact = 12.5 } },
				},
				InitialOccupants = {
					{ PlatformId = 5, ItemId = "unknown-brainrot", BrainrotId = "BRT_999" },
				},
			}, function(f)
				f.SetTime(30)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(5)).to.equal(12.5)
				expect(Income:GetPlatformIncomeSnapshot(f.BaseId, 5).RatePerSecond).to.equal(0)
				local claimed = Income:TryClaimPlatform(f.Player, f.BaseId, 5)
				expect(claimed.paid).to.equal(12.5)
				expect(claimed.remainingExact).to.equal(0)
			end)
		end)

		it("retains cash on removal and adds replacement income", function()
			run({ Rates = { BRT_007 = 10, ["BRT-011"] = 20 } }, function(f)
				f.Deposit(1, "individual-a", "BRT_007")
				f.SetTime(8)
				local removed = f.Remove(1, "individual-a")
				expect(removed.ItemId).to.equal("individual-a")
				expect(f.Storage:GetPlatformRecord(1)).to.equal(nil)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(80)
				expect(f.Accounts[f.Player].Balance).to.equal(0)

				f.SetTime(13)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(80)

				f.Deposit(1, "individual-b", "BRT-011")
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(80)
				f.SetTime(16)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(140)

				local claimed = Income:TryClaimPlatform(f.Player, f.BaseId, 1)
				expect(claimed.paid).to.equal(140)
				expect(claimed.remainingExact).to.equal(0)
				expect(f.Accounts[f.Player].Balance).to.equal(140)
				expect(f.Accounts[f.Player].Credits).to.equal(1)
				expect(f.Storage:GetPlatformRecord(1).ItemId).to.equal("individual-b")
				expect(Income:GetPlatformIncomeSnapshot(f.BaseId, 1).Occupied).to.equal(true)
			end)
		end)

		it("collects retained cash once after removing the occupant", function()
			run({ Rates = { BRT_007 = 10 } }, function(f)
				f.Deposit(2, "individual-a", "BRT_007")
				f.SetTime(8)
				assert(f.Remove(2, "individual-a"))
				expect(f.Storage:GetUnclaimedCashExact(2)).to.equal(80)

				local outsider = Income:TryClaimPlatform(f.Outsider, f.BaseId, 2)
				expect(outsider.code).to.equal("NotOwner")
				expect(f.Storage:GetUnclaimedCashExact(2)).to.equal(80)

				local claimed = Income:TryClaimPlatform(f.Player, f.BaseId, 2)
				expect(claimed.code).to.equal("Collected")
				expect(claimed.paid).to.equal(80)
				expect(f.Accounts[f.Player].Balance).to.equal(80)
				expect(f.Storage:GetUnclaimedCashExact(2)).to.equal(0)
				expect(Income:GetPlatformIncomeSnapshot(f.BaseId, 2).Occupied).to.equal(false)
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 2).code).to.equal(
					"NothingToCollect"
				)
				expect(f.Accounts[f.Player].Credits).to.equal(1)
			end)
		end)

		it("accrues exact cash only for deposited occupants and never auto-awards", function()
			run({}, function(f)
				f.Deposit(1, "individual-1", "BRT_007")
				f.SetTime(2.5)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(5000000)
				expect(f.Storage:GetUnclaimedCashExact(2)).to.equal(0)
				expect(f.Accounts[f.Player].Balance).to.equal(0)
				expect(f.Accounts[f.Player].Credits).to.equal(0)
				local snapshot = Income:GetPlatformIncomeSnapshot(f.BaseId, 1)
				expect(snapshot.IndividualId).to.equal("individual-1")
				expect(snapshot.CatalogueId).to.equal("BRT_007")
				expect(snapshot.RatePerSecond).to.equal(2000000)
				expect(Income:GetIncomeRate(f.Player)).to.equal(2000000)
			end)
		end)

		it("preserves fractions, rejects non-owners and awards exactly once", function()
			run({}, function(f)
				f.Deposit(4, "individual-4", "BRT_007")
				f.SetTime(2.75)
				expect(Income:TryClaimPlatform(f.Outsider, f.BaseId, 4).code).to.equal("NotOwner")
				expect(f.Storage:GetUnclaimedCashExact(4)).to.equal(0)
				local claimed = Income:TryClaimPlatform(f.Player, f.BaseId, 4)
				expect(claimed.paid).to.equal(5500000)
				expect(claimed.remainingExact).to.equal(0)
				expect(f.Accounts[f.Player].Balance).to.equal(5500000)
				expect(f.Storage:GetUnclaimedCashExact(4)).to.equal(0)
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 4).code).to.equal(
					"NothingToCollect"
				)
				expect(f.Accounts[f.Player].Credits).to.equal(1)
			end)
		end)

		it("keeps the full exact balance when the award rejects", function()
			run({}, function(f)
				f.Deposit(3, "individual-3", "BRT_007")
				f.SetTime(3.25)
				Income:Step()
				f.Wallet.Reject = true
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 3).code).to.equal("AwardFailed")
				expect(f.Storage:GetUnclaimedCashExact(3)).to.equal(6500000)
				expect(f.Accounts[f.Player].Balance).to.equal(0)
			end)
		end)

		it("serializes slot balances and resumes without offline income", function()
			local saved
			run({}, function(f)
				f.Deposit(6, "persistent-6", "BRT_007")
				f.SetTime(2.5)
				Income:Step()
				saved = f.Storage:GetPersistentData()
			end)
			run({
				InitialTime = 1000,
				SavedData = saved,
				InitialOccupants = {
					{ PlatformId = 6, ItemId = "persistent-6", BrainrotId = "BRT_007" },
				},
			}, function(f)
				expect(f.Storage:GetUnclaimedCashExact(6)).to.equal(5000000)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(6)).to.equal(5000000)
				f.SetTime(1001)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(6)).to.equal(7000000)
			end)
		end)

		it("reconciles absent and invalid saved balances to zero", function()
			run({ SavedData = {} }, function(f)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(0)
			end)
			run({
				SavedData = { PlatformIncome = { ["1"] = { UnclaimedCashExact = 0 / 0 } } },
			}, function(f)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(0)
			end)
		end)

		it("restores and releases the authoritative ledger through the profile owner", function()
			local profile = {
				Saved = {
					PlatformIncome = { ["10"] = { UnclaimedCashExact = 4.5 } },
				},
			}
			function profile:Start()
				self.Active = true
			end
			function profile:Load()
				return self.Active
			end
			function profile:Get()
				return self.Saved
			end
			function profile:MarkDirty(_, data)
				self.Saved = data
				return true
			end
			function profile:Autosave()
				return false
			end
			function profile:Release()
				self.Released = true
				return true
			end
			function profile:Stop()
				self.Active = false
			end

			run({ Profile = profile }, function(f)
				expect(f.Storage:GetUnclaimedCashExact(10)).to.equal(4.5)
				f.Deposit(10, "persistent-profile-10", "BRT_007")
				f.SetTime(1)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(10)).to.equal(2000004.5)
			end)
			expect(profile.Released).to.equal(true)
			expect(profile.Saved.PlatformIncome["10"].UnclaimedCashExact).to.equal(2000004.5)

			profile.Released = false
			run({ Profile = profile, InitialTime = 1000 }, function(f)
				expect(f.Storage:GetUnclaimedCashExact(10)).to.equal(2000004.5)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(10)).to.equal(2000004.5)
			end)
		end)

		it("guards a platform against two simultaneous claims", function()
			run({}, function(f)
				f.Deposit(8, "individual-8", "BRT_007")
				f.SetTime(3)
				Income:Step()
				local entered, released, finished = false, false, false
				local first, workerError
				local function awaitCondition(predicate, message)
					local deadline = os.clock() + 2
					while not predicate() and os.clock() < deadline do task.wait() end
					assert(predicate(), message)
				end
				f.Wallet.BeforeAward = function()
					entered = true
					awaitCondition(function() return released end, "Claim release latch timed out")
				end
				local worker = task.spawn(function()
					local ok, result = pcall(Income.TryClaimPlatform, Income, f.Player, f.BaseId, 8)
					if ok then first = result else workerError = tostring(result) end
					finished = true
				end)
				local ok, why = xpcall(function()
					awaitCondition(function() return entered or finished end, "First claim never reached wallet latch or returned")
					assert(entered, "First claim exited before wallet latch: " .. tostring(workerError or (first and first.code)))
					expect(Income:TryClaimPlatform(f.Player, f.BaseId, 8).code).to.equal("Busy")
					expect(select(2, f.Storage:TryBeginPlatformMutation(8))).to.equal("BUSY")
					released = true
					awaitCondition(function() return finished end, "First claim did not finish after release")
					assert(workerError == nil, workerError)
					expect(first.paid).to.equal(6000000)
					expect(f.Accounts[f.Player].Credits).to.equal(1)
					local token = assert(f.Storage:TryBeginPlatformMutation(8))
					expect(f.Storage:EndPlatformMutation(8, token)).to.equal(true)
				end, debug.traceback)
				released, f.Wallet.BeforeAward = true, nil
				if coroutine.status(worker) ~= "dead" then task.cancel(worker) end
				assert(ok, why)
			end)
		end)

		it("starts one scheduler and validates claim preconditions", function()
			run({}, function(f)
				expect(f.Scheduler.Connections).to.equal(1)
				expect(Income:Start()).to.equal(false)
				expect(f.Scheduler.Connections).to.equal(1)
				f.Accounts[f.Player].Ready = false
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).code).to.equal(
					"ProfileNotReady"
				)
				f.Accounts[f.Player].Ready = true
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 13).code).to.equal(
					"InvalidPlatform"
				)
			end)
		end)
	end)
end
