--!nocheck
-- Actual runtime diagnostic handler + native presentation groups; no Start or profile session.
return function()
 local RS=game:GetService("ReplicatedStorage")
 local Players=game:GetService("Players")
 local Presentation=require(RS.Shared.Utility.BaseSlotPresentation)
 local Runtime=require(script.Parent.Parent.Services.Phase13RuntimeService)
 local Profiles=require(script.Parent.Parent.Services.PlayerDataService)
 local Bases=require(script.Parent.Parent.Systems.PlayerBaseSystem)
 local function fixture(callback)
  local base=Instance.new("Model")
  local player={UserId=-2,Parent=Players}
  base:SetAttribute("OwnerUserId",player.UserId);base:SetAttribute("BaseOwnershipRevision",7)
  local slots={}
  for _,index in {1,48}do
   local part=Instance.new("Part");part.Name="Slot_"..index;part.Parent=base
   local marker=Instance.new("Attachment");marker.Name="BrainrotPlacement";marker.Parent=part
   local gui=Instance.new("SurfaceGui");gui.Enabled=true;gui.Parent=part
   Presentation.CaptureGroup(part);slots[index]=part
  end
  local assignment={Player=player,Base=base,Generation=7}
  local status,current,readable="Ready",true,{}
  local original={GetAssignment=Bases.GetAssignment,IsCurrentAssignment=Bases.IsCurrentAssignment,GetBase=Bases.GetBase,GetStatus=Profiles.GetStatus,GetReadableData=Profiles.GetReadableData}
  Bases.GetAssignment=function(_,subject)return if subject==player then assignment else nil end
  Bases.IsCurrentAssignment=function(_,handle)return current and handle==assignment end
  Bases.GetBase=function(_,subject)return if subject==player then base else nil end
  Profiles.GetStatus=function(_,subject)return if subject==player then status else "Closed"end
  Profiles.GetReadableData=function(_,subject)return if subject==player then readable else nil end
  local function publish(capacity)
   local token=assert(Presentation.Begin(base,capacity,{OwnerUserId=player.UserId,AssignmentRevision=7,ProfileReady=true}))
   for index,part in slots do Presentation.BindSlot(part,base,index,token)end
   Presentation.Publish(base,token,capacity)
  end
  publish(48)
  local ok,why=xpcall(function()callback({Base=base,Player=player,Slots=slots,Publish=publish,Status=function(v)status=v end,Current=function(v)current=v end,Readable=function(v)readable=v end})end,debug.traceback)
  Bases.GetAssignment,Bases.IsCurrentAssignment,Bases.GetBase=original.GetAssignment,original.IsCurrentAssignment,original.GetBase
  Profiles.GetStatus,Profiles.GetReadableData=original.GetStatus,original.GetReadableData
  base:Destroy();assert(ok,why)
 end
 describe("B05 ready owner profile failure and recovery",function()
  for _,kind in {"SessionLost","LoadRejected","CloseUnconfirmed"}do
   it("hides complete committed slot groups for current "..kind,function()
    fixture(function(f)
     f.Status("Failed")
     expect(Runtime:OnProfileDiagnostic(f.Player,{kind=kind})).to.equal(true)
     expect(f.Base:GetAttribute("BaseCommittedCapacity")).to.equal(0)
     for _,part in f.Slots do
      expect(Presentation.IsActive(part)).to.equal(false)
      expect(part.Transparency).to.equal(1)
      expect(part.CanCollide or part.CanTouch or part.CanQuery).to.equal(false)
      expect(part:FindFirstChildWhichIsA("SurfaceGui").Enabled).to.equal(false)
      expect(part:FindFirstChild("BrainrotPlacement")~=nil).to.equal(true)
     end
    end)
   end)
  end
  it("ignores unrelated, recovered-session and stale-assignment diagnostics",function()
   fixture(function(f)
    local token=f.Base:GetAttribute("BasePresentationState")
    expect(Runtime:OnProfileDiagnostic(f.Player,{kind="SessionLost"})).to.equal(false)
    f.Status("Failed")
    expect(Runtime:OnProfileDiagnostic(f.Player,{kind="SaveRetry"})).to.equal(false)
    f.Current(false)
    expect(Runtime:OnProfileDiagnostic(f.Player,{kind="SessionLost"})).to.equal(false)
    expect(f.Base:GetAttribute("BasePresentationState")).to.equal(token)
   end)
  end)
  it("does not expose readable recovery data through the reconciliation queue",function()
   fixture(function(f)
    f.Status("Recovering")
    expect(Runtime:Reconcile(f.Player,nil)).to.equal(false)
    expect(Presentation.IsActive(f.Slots[1])).to.equal(false)
    expect(Presentation.IsActive(f.Slots[48])).to.equal(false)
   end)
  end)
  it("restores only recovered committed capacity and ignores an old failure afterward",function()
   fixture(function(f)
    f.Status("Failed");assert(Runtime:OnProfileDiagnostic(f.Player,{kind="SessionLost"}))
    f.Status("Ready");f.Publish(12)
    expect(Presentation.IsActive(f.Slots[1])).to.equal(true)
    expect(Presentation.IsActive(f.Slots[48])).to.equal(false)
    expect(Runtime:OnProfileDiagnostic(f.Player,{kind="SessionLost"})).to.equal(false)
    expect(Presentation.IsActive(f.Slots[1])).to.equal(true)
   end)
  end)
 end)
	-- B02/B06 service integration: existing FakeBackend + actual profile, critical
	-- coordinator, geometry, storage, income and runtime. Assignment/context adapters
	-- isolate one synthetic player/base; this is not actual-client/network evidence.
	local RunService = game:GetService("RunService")
	local SS = game:GetService("ServerStorage")
	local SSS = game:GetService("ServerScriptService")
	local Workspace = game:GetService("Workspace")
	local LogService = game:GetService("LogService")
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Geometry = require(script.Parent.Parent.Utility.Phase13BaseGeometry)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local Coordinator = require(script.Parent.Parent.Services.Phase13Service)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local StorageSystem = require(script.Parent.Parent.Systems.BaseStorageSystem)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local TeamService = require(script.Parent.Parent.Services.ChariotTeamService)
	local ProfileConfig = require(script.Parent.Parent.Config.PlayerDataConfig)
	local function waitFor(predicate, label)
		local deadline = os.clock() + 4
		repeat
			if predicate() then
				return
			end
			task.wait()
		until os.clock() >= deadline
		error("Bounded base-service fixture timeout: " .. label)
	end
	local function assertGroups(base, capacity)
		expect(base:GetAttribute("BaseCommittedCapacity")).to.equal(capacity)
		for index = 1, 48 do
			local slot = base:FindFirstChild(string.format("Slot_%02d", index))
			local active = index <= capacity
			expect(Presentation.IsActive(slot)).to.equal(active)
			local all = { slot }
			for _, item in slot:GetDescendants() do
				table.insert(all, item)
			end
			for _, item in all do
				if item:IsA("BasePart") then
					for _, property in { "Transparency", "CanCollide", "CanTouch", "CanQuery" } do
						local expected = if active
							then Presentation.GetAuthoredProperty(item, property)
							elseif property == "Transparency" then 1
							else false
						expect(item[property]).to.equal(expected)
					end
				elseif item:IsA("LayerCollector") or item:IsA("ProximityPrompt") then
					expect(item.Enabled).to.equal(active and Presentation.GetAuthoredProperty(item, "Enabled"))
				end
			end
			expect(slot.BrainrotPlacement.Parent).to.equal(slot)
		end
		expect(base.Foundation.CanCollide).to.equal(true)
	end
	local function serviceFixture(options, callback)
		assert(
			RunService:IsStudio()
				and (
					not RunService:IsRunning()
					or (game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true and SSS.Server.Bootstrap.Disabled)
				),
			"Isolated disabled-bootstrap UNIT only"
		)
		assert(SS:GetAttribute("Phase8TestProfileNamespace") == nil, "No real profile namespace")
		options = options or {}
		TeamService:Destroy()
		Coordinator:_ResetForTests()
		Income:Stop()
		StorageSystem:Destroy()
		Profiles:_ResetForTests()
		local f = {
			Clock = { Unix = 86410, Mono = 1000, Persistence = 86410 },
			Gates = {},
			Restores = {},
			Warnings = {},
			Owned = {},
		}
		local clock = f.Clock
		local id = 816602
		f.Key = ProfileConfig.KeyPrefix .. tostring(id)
		local initial = Schema.CreateDefault()
		initial.Commerce.Entitlements.AUTO_COLLECT = options.AutoCollect == true
		initial.Phase13.ExpansionLevel = options.Level or 0
		local target = 12 + 6 * (initial.Phase13.ExpansionLevel + 1)
		local reward = Rules.FindReward(string.format("EXP_%03d", target))
		initial.Economy.Balance = if options.Funded == false then 0.375 else (reward and reward.price or 0) + 0.375
		initial.Collection.BrainrotInstances["base-service:owned"] = {
			speciesId = "BRT_001",
			mutationId = "None",
			firstBankCompleted = true,
			metadata = {
				FirstBankCompleted = true,
			},
		}
		initial.Base.Slots["1"] = { brainrotId = "base-service:owned", accumulatedCash = 123.375 }
		if options.Legacy then
			initial.Collection.BrainrotInstances["base-service:legacy-locked"] = {
				speciesId = "BRT_002",
				mutationId = "None",
				firstBankCompleted = true,
				metadata = {
					FirstBankCompleted = true,
				},
			}
			initial.Base.Slots["48"] = { brainrotId = "base-service:legacy-locked", accumulatedCash = 321.125 }
		end
		if options.CashOnly then
			initial.Base.Slots["47"] = { accumulatedCash = 19.625 }
		end
		if options.StaleTeam then
			initial.ChariotTeam.Assignments["1"] = "base-service:legacy-locked"
		end
		-- Funding and inconsistent legacy data are explicit isolated initial records,
		-- never mutations to any normal profile or Ready attributes.
		local backend = FakeBackend.new({
			Now = function()
				return clock.Persistence
			end,
			Records = {
				[f.Key] = { Data = initial, OwnerToken = nil, LeaseExpiresAt = 0, LastRevision = 0 },
			},
		})
		f.Backend = backend
		local sequence = 0
		Profiles:Init({
			Backend = backend,
			UnixNow = function()
				return clock.Persistence
			end,
			MonotonicNow = function()
				return clock.Mono
			end,
			Wait = function(seconds)
				clock.Mono += math.max(seconds, 0.001)
				clock.Persistence += math.max(seconds, 0.001)
			end,
			Random = function()
				return 0
			end,
			GenerateOperationId = function(prefix)
				sequence += 1
				return prefix .. ":base-service:" .. sequence
			end,
			KickOnFailure = false,
		})
		local character = Instance.new("Model")
		character.Name = "BaseServiceSyntheticCharacter"
		table.insert(f.Owned, character)
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		local removing = Instance.new("BindableEvent")
		table.insert(f.Owned, removing)
		local function player()
			local p = {
				Name = "BaseServiceSynthetic",
				UserId = id,
				Parent = Players,
				Character = character,
				CharacterRemoving = removing.Event,
				Attributes = {},
			}
			function p:SetAttribute(k, v)
				self.Attributes[k] = v
			end
			function p:GetAttribute(k)
				return self.Attributes[k]
			end
			function p:FindFirstChildOfClass()
				return nil
			end
			function p:Kick(message)
				self.Kicked = message
			end
			return p
		end
		f.Player = player()
		local base = Instance.new("Model")
		base.Name = "Phase14OwnedBaseServiceFixture"
		base:SetAttribute("BaseId", "BaseServiceFixture")
		base:SetAttribute("OwnerUserId", id)
		base:SetAttribute("BaseOwnershipRevision", 1)
		base.Parent = Workspace
		table.insert(f.Owned, base)
		f.Base = base
		local foundation = Instance.new("Part")
		foundation.Name = "Foundation"
		foundation.Anchored = true
		foundation.Size = Vector3.new(46.66, 1, 79.4625)
		foundation.CFrame = CFrame.new(10000, 0, 10000)
		foundation.Parent = base
		for index = 1, 12 do
			local slot = Instance.new("Part")
			slot.Name = string.format("Slot_%02d", index)
			slot.Size = Vector3.new(10.16, 0.75, 13.92)
			slot.Anchored = true
			slot.CFrame = foundation.CFrame
				* CFrame.new(if index <= 6 then -12.77 else 12.77, 1, -28 + ((index - 1) % 6) * 12.18)
			slot.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name = "BrainrotPlacement"
			marker.Parent = slot
		end
		Geometry.Build(base)
		for index = 1, 48 do
			local slot = base:FindFirstChild(string.format("Slot_%02d", index))
			local decor = Instance.new("Part")
			decor.Name = "AuthoredTranslucentDecor"
			decor.Anchored = true
			decor.Transparency = 0.5
			decor.CanCollide = false
			decor.CanTouch = false
			decor.CanQuery = false
			decor.Parent = slot
			local gui = Instance.new("SurfaceGui")
			gui.Enabled = true
			gui.Parent = decor
			local prompt = Instance.new("ProximityPrompt")
			prompt.Enabled = true
			prompt.Parent = decor
			Presentation.CaptureGroup(slot)
		end
		f.Assignment = { Player = f.Player, Base = base, Generation = 1 }
		local original = {}
		for _, name in
			{
				"GetRegisteredBases",
				"GetBase",
				"GetAssignment",
				"IsCurrentAssignment",
				"IsOwner",
				"SubscribeAssignments",
			}
		do
			original[name] = Bases[name]
		end
		local assigned
		Bases.GetRegisteredBases = function()
			return { base }
		end
		Bases.GetBase = function(_, subject)
			return if subject == f.Player then base else nil
		end
		Bases.GetAssignment = function(_, subject)
			return if subject == f.Player then f.Assignment else nil
		end
		Bases.IsCurrentAssignment = function(_, handle)
			return handle == f.Assignment and handle.Player == f.Player
		end
		Bases.IsOwner = function(_, subject, which)
			return subject == f.Player and which == base
		end
		Bases.SubscribeAssignments = function(_, bound)
			assigned = bound
			return {
				Disconnect = function()
					assigned = nil
				end,
			}
		end
		table.insert(f.Restores, function()
			for name, value in original do
				Bases[name] = value
			end
		end)
		local logConnection = LogService.MessageOut:Connect(function(message)
			if
				(message:find("base-service:legacy-locked", 1, true) and message:find("unavailable slot 48", 1, true))
				or message:find("Retained unavailable saved slot userId=816602", 1, true)
			then
				table.insert(f.Warnings, message)
			end
		end)
		table.insert(f.Restores, function()
			logConnection:Disconnect()
		end)
		local function startSession()
			assert(Profiles:LoadPlayerAsync(f.Player).ok, "synthetic real profile load")
			Currency:_ResetForTests(Profiles, {
				Now = function()
					return clock.Unix
				end,
			})
			Banked:_ResetForTests({ Profile = Profiles, Currency = Currency })
			Banked:Start()
			assert(
				Geometry.Apply(
					base,
					Rules.GetCapacity(Profiles:GetReadableData(f.Player)),
					"BDS_001",
					false,
					{ OwnerUserId = id, AssignmentRevision = 1, ProfileReady = true }
				)
			)
			assert(Income:Start({
				Profile = Profiles,
				Storage = StorageSystem,
				Base = Bases,
				Wallet = Currency,
				Now = function()
					return clock.Unix
				end,
				Analytics = false,
				ConnectScheduler = false,
			}))
			StorageSystem:Start({
				Profile = Profiles,
				BankNow = function()
					return clock.Unix
				end,
			})
			assert(assigned, "captured isolated assignment adapter")
			assigned(f.Player, base, f.Assignment)
			assert(StorageSystem:GetStorageForPlayer(f.Player), "actual storage bound")
			assert(Profiles:SaveNowAsync(f.Player, "BaseServiceFixtureBaseline").ok, "baseline covering save")
			assert(Coordinator:Start({
				Profile = Profiles,
				Income = Income,
				Currency = Currency,
				Now = function()
					return clock.Unix
				end,
				ValidateContext = function(subject)
					return subject == f.Player and f.ContextAllowed ~= false, "FIXTURE_CONTEXT_REJECTED"
				end,
				ReconcileOwned = function(subject, receipt)
					return Runtime:Reconcile(subject, receipt)
				end,
			}))
			assert(Runtime:Reconcile(f.Player, nil), "actual committed runtime reconcile")
		end
		function f:Data()
			return assert(Profiles:GetReadableData(self.Player))
		end
		function f:Request(capacity)
			local quote = Coordinator:QuoteRebirth(self.Player, string.format("EXP_%03d", capacity), "Cash")
			return {
				rewardId = quote.rewardId or string.format("EXP_%03d", capacity),
				route = "Cash",
				previewRevision = quote.previewRevision,
				inventorySignature = quote.inventorySignature,
				sequence = quote.nextSequence,
				operationId = "base-service:expand:" .. capacity,
			},
				quote
		end
		function f:Hold(operationId)
			local gate = { Released = false, Entered = false, Exited = false }
			table.insert(self.Gates, gate)
			local old = backend.Save
			backend.Save = function(selfBackend, key, token, saveId, revision, snapshot, lease)
				if not gate.Entered and snapshot.Phase13.Operations[operationId] then
					gate.Entered = true
					gate.Thread = coroutine.running()
					waitFor(function()
						return gate.Released
					end, "owned pre-save gate")
				end
				local response = old(selfBackend, key, token, saveId, revision, snapshot, lease)
				gate.Exited = true
				return response
			end
			return gate
		end
		function f:Confirmed(operationId)
			waitFor(function()
				Coordinator:Step()
				return Coordinator:GetOperation(self.Player, operationId).state == "Confirmed"
					and Profiles:IsWritable(self.Player)
			end, "actual covering-save confirmation")
			return Coordinator:GetOperation(self.Player, operationId)
		end
		function f:Rejoin()
			Coordinator:_ResetForTests()
			Income:Stop()
			StorageSystem:Destroy()
			assert(Profiles:ClosePlayerAsync(self.Player, "SyntheticBaseServiceRejoin").ok, "synthetic close")
			self.Player.Parent = nil
			self.Player = player()
			self.Assignment = { Player = self.Player, Base = base, Generation = 1 }
			startSession()
		end
		local ok, why = xpcall(function()
			startSession()
			callback(f)
		end, debug.traceback)
		for _, gate in f.Gates do
			gate.Released = true
		end
		for _, gate in f.Gates do
			if gate.Entered and not gate.Exited then
				local drained = pcall(waitFor, function()
					return gate.Exited
				end, "owned gate cleanup")
				if not drained and gate.Thread and coroutine.status(gate.Thread) ~= "dead" then
					pcall(task.cancel, gate.Thread)
				end
			end
		end
		TeamService:Destroy()
		Coordinator:_ResetForTests()
		Income:Stop()
		StorageSystem:Destroy()
		local closed = Profiles:ClosePlayerAsync(f.Player, "BaseServiceFixtureCleanup")
		local closeConfirmed = closed.ok == true and f.Backend:GetRecord(f.Key).OwnerToken == nil
		Banked:_ResetForTests()
		Currency:_ResetForTests()
		Profiles:_ResetForTests()
		for index = #f.Restores, 1, -1 do
			f.Restores[index]()
		end
		for index = #f.Owned, 1, -1 do
			f.Owned[index]:Destroy()
		end
		assert(closeConfirmed, "synthetic backend lease was not released during cleanup")
		assert(ok, why)
	end
	describe("B02 actual profile-coordinator capacity publication", function()
		for level = 0, 5 do
			local beforeCapacity = 12 + 6 * level
			local afterCapacity = beforeCapacity + 6
			it(
				"commits "
					.. beforeCapacity
					.. " to "
					.. afterCapacity
					.. " only after its covering save and reacquires exact groups",
				function()
					serviceFixture({ Level = level }, function(f)
						assertGroups(f.Base, beforeCapacity)
						local request, quote = f:Request(afterCapacity)
						expect(quote.ok).to.equal(true)
						local owned = Fixtures.Clone(f:Data().Collection)
						local retention = Fixtures.Clone(f:Data().Retention)
						local commerce = Fixtures.Clone(f:Data().Commerce)
						local canonical = Fixtures.Clone(f.Backend:GetRecord(f.Key).Data)
						local gate = f:Hold(request.operationId)
						local result = Coordinator:Rebirth(f.Player, request)
						expect(result.state).to.equal("Saving")
						waitFor(function()
							return gate.Entered
						end, "covering save entered")
						expect(Rules.GetCapacity(f:Data())).to.equal(afterCapacity)
						expect(Runtime:Reconcile(f.Player, nil)).to.equal(false)
						Fixtures.AssertDeepEqual(f.Backend:GetRecord(f.Key).Data, canonical)
						assertGroups(f.Base, beforeCapacity)
						gate.Released = true
						f:Confirmed(request.operationId)
						assertGroups(f.Base, afterCapacity)
						expect(f:Data().Economy.Balance).to.equal(0)
						expect(Rules.Cash(f:Data())).to.equal(0)
						Fixtures.AssertDeepEqual(f:Data().Collection, owned)
						Fixtures.AssertDeepEqual(f:Data().Retention, retention)
						Fixtures.AssertDeepEqual(f:Data().Commerce, commerce)
						expect(f:Data().Base.Slots["1"].brainrotId).to.equal("base-service:owned")
						expect(f.Backend:GetRecord(f.Key).Data.Phase13.ExpansionLevel).to.equal(level + 1)
						f:Rejoin()
						assertGroups(f.Base, afterCapacity)
						expect(Rules.GetCapacity(f:Data())).to.equal(afterCapacity)
						expect(f:Data().Economy.Balance).to.equal(0)
						Fixtures.AssertDeepEqual(f:Data().Collection, owned)
					end)
				end
			)
		end
		it("quote-only cancellation and stale/context/insufficient rejects preserve profile and every group", function()
			serviceFixture({ Funded = false }, function(f)
				local before = Fixtures.Clone(f:Data())
				local canonical = Fixtures.Clone(f.Backend:GetRecord(f.Key).Data)
				local request, quote = f:Request(18)
				expect(quote.code).to.equal("INSUFFICIENT_CASH")
				-- Cancel is absence of a write: the real UI Cancel path makes no server call.
				Fixtures.AssertDeepEqual(f:Data(), before)
				assertGroups(f.Base, 12)
				request.sequence = before.Phase13.OperationSequence + 1
				request.previewRevision = before.Phase13.EligibilityRevision - 1
				expect(Coordinator:Rebirth(f.Player, request).code).to.equal("STALE_PREVIEW")
				request.previewRevision = before.Phase13.EligibilityRevision
				expect(Coordinator:Rebirth(f.Player, request).code).to.equal("INSUFFICIENT_CASH")
				f.ContextAllowed = false
				expect(Coordinator:Rebirth(f.Player, request).code).to.equal("FIXTURE_CONTEXT_REJECTED")
				Fixtures.AssertDeepEqual(f:Data(), before)
				Fixtures.AssertDeepEqual(f.Backend:GetRecord(f.Key).Data, canonical)
				assertGroups(f.Base, 12)
			end)
		end)
		it(
			"an actual pre-commit save fault retains prior durable capacity and visible groups until retry confirms",
			function()
				serviceFixture({}, function(f)
					local request = f:Request(18)
					local canonical = Fixtures.Clone(f.Backend:GetRecord(f.Key).Data)
					local oldSave = f.Backend.Save
					local failed = false
					local gate = { Released = false, Entered = false, Exited = false }
					table.insert(f.Gates, gate)
					f.Backend.Save = function(backend, key, token, saveId, revision, snapshot, lease)
						if not failed and snapshot.Phase13.Operations[request.operationId] then
							failed = true
							gate.Entered, gate.Thread = true, coroutine.running()
							f.Backend.FailBeforeSaveCount = 1
							local response = oldSave(backend, key, token, saveId, revision, snapshot, lease)
							Fixtures.AssertDeepEqual(backend:GetRecord(key).Data, canonical)
							assertGroups(f.Base, 12)
							waitFor(function()
								return gate.Released
							end, "release failed-save result")
							gate.Exited = true
							return response
						end
						return oldSave(backend, key, token, saveId, revision, snapshot, lease)
					end
					local result = Coordinator:Rebirth(f.Player, request)
					expect(result.state).to.equal("Saving")
					waitFor(function()
						return failed
					end, "injected backend failure")
					Fixtures.AssertDeepEqual(f.Backend:GetRecord(f.Key).Data, canonical)
					assertGroups(f.Base, 12)
					expect(Runtime:Reconcile(f.Player, nil)).to.equal(false)
					gate.Released = true
					f:Confirmed(request.operationId)
					expect(failed).to.equal(true)
					assertGroups(f.Base, 18)
					expect(f:Data().Economy.Balance).to.equal(0)
				end)
			end
		)
	end)
	describe("B03/B06 real storage and income fail-closed boundaries", function()
		it(
			"retains and diagnoses locked legacy identity/earnings while an unlocked producer still accrues and pays",
			function()
				serviceFixture({ Funded = false, Legacy = true }, function(f)
					local before = Fixtures.Clone(f:Data())
					local storage = assert(StorageSystem:GetStorageForPlayer(f.Player))
					expect(storage:GetPlatformRecord(48)).to.equal(nil)
					expect(storage:GetPlatformRecord(1) ~= nil).to.equal(true)
					waitFor(function()return #f.Warnings>0 end,"actual unavailable record warning")
					expect(#f.Warnings > 0).to.equal(true)
					assertGroups(f.Base, 12)
					for _, index in { 0, 13, 48, 49, -1 } do
						local result = Income:TryClaimPlatform(f.Player, "BaseServiceFixture", index)
						expect(result.ok).to.equal(false)
						expect(result.code).to.equal("InvalidPlatform")
					end
					local visitor = { UserId = 816603, Parent = Players }
					function visitor:GetAttribute(key)
						return if key == "PlayerDataWritable" then true else nil
					end
					-- Currency readiness remains authoritative; a visitor cannot acquire this context.
					expect(Income:TryClaimPlatform(visitor, "BaseServiceFixture", 1).ok).to.equal(false)
					local descriptor, _, reason = StorageSystem:ResolvePlatform(f.Player, f.Base.Slot_48)
					expect(descriptor).to.equal(nil)
					expect(reason).to.equal("LOCKED_SLOT")
					local incoming = { ItemId = "base-service:forged-target", BrainrotId = "BRT_001", Metadata = {} }
					local prepared, prepareReason =
						StorageSystem:PrepareStoreAtPlatform(f.Player, f.Base.Slot_48, incoming)
					expect(prepared).to.equal(nil)
					expect(prepareReason).to.equal("LOCKED_SLOT")
					local removed, removeReason =
						StorageSystem:TryRemoveFromPlatform(f.Player, f.Base.Slot_48, "base-service:legacy-locked")
					expect(removed).to.equal(nil)
					expect(removeReason).to.equal("LOCKED_SLOT")
					local visitorTarget, _, visitorReason = StorageSystem:ResolvePlatform(visitor, f.Base.Slot_01)
					expect(visitorTarget).to.equal(nil)
					expect(visitorReason).to.equal("NOT_OWNER")
					Fixtures.AssertDeepEqual(f:Data(), before)
					f.Clock.Unix += 1
					assert(Income:AccruePlatformsTo(f.Clock.Unix))
					local expectedPayout = storage:GetUnclaimedCashExact(1)
					local payout = Income:TryClaimPlatform(f.Player, "BaseServiceFixture", 1)
					expect(payout.ok).to.equal(true)
					expect(payout.paid).to.equal(expectedPayout)
					expect(f:Data().Economy.Balance > before.Economy.Balance).to.equal(true)
					Fixtures.AssertDeepEqual(f:Data().Collection.BrainrotInstances, before.Collection.BrainrotInstances)
					Fixtures.AssertDeepEqual(f:Data().Base.Slots["48"], before.Base.Slots["48"])
					expect(Presentation.IsActive(f.Base.Slot_48)).to.equal(false)
					expect(storage:GetPlatformRecord(48)).to.equal(nil)
				end)
			end
		)
	end)

	describe("B06 current writer and quarantined legacy money", function()
		it("rejects locked identity/ledger edits and new locked writes through the actual profile writer", function()
			serviceFixture({ Funded = false, Legacy = true, CashOnly = true, StaleTeam = true }, function(f)
				local before = Fixtures.Clone(f:Data())
				for _, mutator in
					{
						function(data)
							data.Base.Slots["48"].brainrotId = nil
						end,
						function(data)
							data.Base.Slots["48"].accumulatedCash = 0
						end,
						function(data)
							data.Collection.BrainrotInstances["base-service:legacy-locked"].speciesId = "BRT_003"
						end,
						function(data)
							data.Base.Slots["13"].accumulatedCash = 12.5
						end,
						function(data)
							data.Collection.BrainrotInstances["forged:locked"] = { speciesId = "BRT_001" }
							data.Base.Slots["13"].brainrotId = "forged:locked"
						end,
						function(data)
							data.Economy.Balance += 321.125
							data.Base.Slots["48"].accumulatedCash = 0
						end,
					}
				do
					local result = Profiles:CommitMutation(f.Player, function(data)
						mutator(data)
						return true, { code = "SYNTHETIC_FORGED_LOCKED_WRITE" }
					end)
					expect(result.ok).to.equal(false)
					expect(result.reason).to.equal("UNAVAILABLE_SLOT_MUTATION")
					Fixtures.AssertDeepEqual(f:Data(), before)
				end
				TeamService:Reconcile(f.Player, true)
				local snapshot = TeamService:Snapshot(f.Player)
				expect(#snapshot.rows).to.equal(1)
				expect(snapshot.rows[1].individualId).to.equal("base-service:owned")
				expect(snapshot.entries["1"]).to.equal(nil)
				expect(snapshot.stats.count).to.equal(0)
				expect(f.Base.Slot_48:FindFirstChild("ChariotEquippedPlaque")).to.equal(nil)
				Fixtures.AssertDeepEqual(f:Data().Collection, before.Collection)
				waitFor(function()return #f.Warnings>=2 end,"actual owned and cash-only unavailable warnings")
					expect(#f.Warnings >= 2).to.equal(true)
				f:Rejoin()
				Fixtures.AssertDeepEqual(f:Data().Base.Slots["48"], before.Base.Slots["48"])
				Fixtures.AssertDeepEqual(f:Data().Base.Slots["47"], before.Base.Slots["47"])
			end)
		end)
		it("AutoCollect uses only active ledgers while preserving exact locked cash and owned records", function()
			serviceFixture({ Funded = false, Legacy = true, AutoCollect = true }, function(f)
				local before = Fixtures.Clone(f:Data())
				local collected = {}
				local connection = Income:SubscribeCommitted(function(_, receipt)
					if receipt.kind == "PlatformIncomeCollected" then table.insert(collected, receipt) end
				end)
				table.insert(f.Restores, function() connection:Disconnect() end)
				f.Clock.Unix += 1
				assert(Income:Step())
				expect(#collected).to.equal(1)
				expect(collected[1].platformId).to.equal(1)
				expect(collected[1].amount).to.equal(1800123.375)
				expect(f:Data().Economy.Balance > before.Economy.Balance).to.equal(true)
				Fixtures.AssertDeepEqual(f:Data().Base.Slots["48"], before.Base.Slots["48"])
				Fixtures.AssertDeepEqual(f:Data().Collection.BrainrotInstances, before.Collection.BrainrotInstances)
				f:Rejoin()
				Fixtures.AssertDeepEqual(f:Data().Base.Slots["48"], before.Base.Slots["48"])
			end)
		end)
		for _, level in { 0, 5 } do
			local capacity = 18 + level * 6
			it(
				"Cash expansion to " .. capacity .. " excludes old locked money and Collection cannot sacrifice it",
				function()
					serviceFixture({ Level = level, Legacy = true }, function(f)
						local before = Fixtures.Clone(f:Data())
						local request, quote = f:Request(capacity)
						expect(quote.ok).to.equal(true)
						expect(quote.totalCash).to.equal(
							before.Economy.Balance + before.Base.Slots["1"].accumulatedCash
						)
						local collection = Coordinator:QuoteRebirth(f.Player, "BDS_002", "Collection")
						expect(collection.code).to.equal("UNAVAILABLE_SAVED_SLOT")
						Fixtures.AssertDeepEqual(f:Data(), before)
						assert(Coordinator:Rebirth(f.Player, request).ok, "actual Cash rebirth accepted")
						local result = f:Confirmed(request.operationId)
						expect(result.result.sacrificedCash).to.equal(quote.totalCash)
						expect(f:Data().Economy.Balance).to.equal(0)
						Fixtures.AssertDeepEqual(f:Data().Base.Slots["48"], before.Base.Slots["48"])
						Fixtures.AssertDeepEqual(
							f:Data().Collection.BrainrotInstances,
							before.Collection.BrainrotInstances
						)
						assertGroups(f.Base, capacity)
						if capacity == 48 then
							expect(StorageSystem:GetStorageForPlayer(f.Player):GetPlatformRecord(48) ~= nil).to.equal(
								true
							)
							expect(Income:TryClaimPlatform(f.Player, "BaseServiceFixture", 48).ok).to.equal(true)
							expect(f:Data().Base.Slots["48"].accumulatedCash).to.equal(0)
						else
							expect(Income:TryClaimPlatform(f.Player, "BaseServiceFixture", 48).ok).to.equal(false)
						end
						f:Rejoin()
						expect(Rules.GetCapacity(f:Data())).to.equal(capacity)
						expect(f:Data().Base.Slots["48"].brainrotId).to.equal("base-service:legacy-locked")
					end)
				end
			)
		end
	end)
end
