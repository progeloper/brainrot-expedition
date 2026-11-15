--!nocheck
-- Phase13 physical fixture has48 anchors; profile starts with12 unlocked.
-- Real storage/cargo modules and real geometry; ownership boundaries are mocked.
-- Fault injection exists only inside these tests and is restored after each fixture.
return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PhysicsService = game:GetService("PhysicsService")
	local CollectionService = game:GetService("CollectionService")
	local BaseSystem = require(script.Parent.Parent.Systems.PlayerBaseSystem)
	local CartService = require(script.Parent.Parent.Services.CartService)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
	local Wallet = require(script.Parent.Parent.Systems.CurrencySystem)
	local ProfileSchema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Presentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
	local CreatureAssets = require(script.Parent.Parent.Utility.CreatureAssetService)
	if not PhysicsService:IsCollisionGroupRegistered("Carts") then
		PhysicsService:RegisterCollisionGroup("Carts")
	end

	local function run(callback, malformed)
		local restores = {}
		local function replace(object, key, value)
			local old = object[key]
			table.insert(restores, function()
				object[key] = old
			end)
			object[key] = value
		end
		local folder = Instance.new("Folder")
		folder.Name = "BaseStorageSpec"
		folder.Parent = workspace
		local createdFolders = {}
		local function child(parent, name)
			local c = parent:FindFirstChild(name)
			if not c then
				c = Instance.new("Folder")
				c.Name = name
				c.Parent = parent
				table.insert(createdFolders, c)
			end
			return c
		end
		-- Use the actual server source path. The enabled private protocol takes
		-- precedence over legacy replicated templates even in isolated Edit tests.
		local assets = CreatureAssets.GetBrainrotFolder()
		if assets == nil then assets = child(child(ReplicatedStorage, "StudioAssets"), "Brainrots") end
		assert(assets:FindFirstChild("SPEC_STORAGE_ITEM") == nil, "A prior owned storage fixture must be cleaned first")
		local template = Instance.new("Model")
		template.Name = "SPEC_STORAGE_ITEM"
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(4, 6, 3)
		body.CFrame = CFrame.new(0, 3, 0)
		body.PivotOffset = CFrame.new(3, 1, -2)
		body.Parent = template
		local captureAttachment = Instance.new("Attachment")
		captureAttachment.Name, captureAttachment.Parent = "CaptureAttachment", body
		template.PrimaryPart = body
		template.Parent = assets
		local bases, homes, carts, records, assignmentHandles = {}, {}, {}, {}, {}
		local function base(n)
			local b = Instance.new("Model")
			b.Name = "SpecBase" .. n
			b:SetAttribute("BaseId", b.Name)
			b.Parent = folder
			for i = 1, 48 do
				local p = Instance.new("Part")
				p.Name = string.format("Slot_%02d", i)
				p.Anchored = true
				p.Size = Vector3.new(10, 0.75, 10)
				p.CFrame = CFrame.new(n * 200 + i * 14, 4, 20) * CFrame.Angles(0, math.pi / 2, 0)
				p.Parent = b
				local m = Instance.new("Attachment")
				m.Name = "BrainrotPlacement"
				m.CFrame = CFrame.new(0, 0.375, 0)
				m.Parent = p
			end
			table.insert(bases, b)
			return b
		end
		local function owner(id, b)
			local p = { UserId = id, Name = "SpecPlayer" .. id, Parent = Players }
			homes[p] = b
			assignmentHandles[p] = {
				Player = p,
				Base = b,
				BaseId = b:GetAttribute("BaseId"),
				Generation = id,
			}
			local c = Instance.new("Model")
			c.Name = "SpecCart" .. id
			c:SetAttribute("CartId", "CRT_001")
			c.Parent = folder
			local slots = Instance.new("Folder")
			slots.Name = "CargoSlots"
			slots.Parent = c
			for i = 1, 3 do
				local part = Instance.new("Part")
				part.Name = "Slot" .. i
				part.Anchored = true
				part.CFrame = CFrame.new(id * 30 + i * 4, 3, 0)
				part.Parent = slots
				local m = Instance.new("Attachment")
				m.Name = "CargoAttachment"
				m.Parent = part
			end
			c.PrimaryPart = slots.Slot1
			carts[p] = c
			records[id] = { OwnerUserId = id, Model = c }
			return p, c
		end
		local a, ac = owner(1, base(1))
		local b, bc = owner(2, base(2))
		local walletOwner = {
			Revision = 0,
			Data = { [a] = ProfileSchema.CreateDefault(), [b] = ProfileSchema.CreateDefault() },
		}
		function walletOwner:IsWritable(player)
			return self.Data[player] ~= nil and player.Parent == Players
		end
		function walletOwner:GetReadableData(player)
			return self.Data[player], if self.Data[player] then nil else "PROFILE_NOT_READY"
		end
		function walletOwner:GetWritableData(player)
			return self:GetReadableData(player)
		end
		function walletOwner:MarkDirty(player)
			if not self:IsWritable(player) then
				return nil, "PROFILE_NOT_READY"
			end
			self.Revision += 1
			return self.Revision
		end
		function walletOwner:CommitMutation(player, mutator)
			if not self:IsWritable(player) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutator(self.Data[player])
			if not committed then
				return result
			end
			self.Revision += 1
			result.ok, result.committed, result.revision = true, true, self.Revision
			return result
		end
		function walletOwner:GetDiagnostics()
			return { currentRevision = self.Revision }
		end
		function walletOwner:BeginClosing()
			return true
		end
		Wallet:_ResetForTests(walletOwner)
		table.insert(restores, function()
			Wallet:_ResetForTests()
		end)
		if malformed then
			malformed(homes[a])
		end
		local assigned, releasing
		local subscriptions = 0
		replace(BaseSystem, "GetRegisteredBases", function()
			return bases
		end)
		replace(BaseSystem, "GetBase", function(_, p)
			return homes[p]
		end)
		replace(BaseSystem, "IsOwner", function(_, p, home)
			return homes[p] == home and p.Parent == Players
		end)
		replace(BaseSystem, "GetAssignment", function(_, p)
			return if homes[p] then assignmentHandles[p] else nil
		end)
		replace(BaseSystem, "IsCurrentAssignment", function(_, handle)
			return handle ~= nil
				and homes[handle.Player] == handle.Base
				and assignmentHandles[handle.Player] == handle
				and handle.Player.Parent == Players
		end)
		replace(BaseSystem, "SubscribeAssignments", function(_, add, remove)
			assigned = add
			releasing = remove
			subscriptions += 1
			return {
				Disconnect = function()
					subscriptions -= 1
				end,
			}
		end)
		replace(CartService, "GetCart", function(_, p)
			return carts[p]
		end)
		replace(CartService, "GetCartRecordByOwnerUserId", function(_, id)
			return records[id]
		end)
        -- This legacy transfer fixture has no ordinary-world ledger or backend.
        -- Its synthetic save is immediately confirmed; dedicated Phase13 tests
        -- exercise delayed/uncertain covering-save and population release.
        local world=require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
        local banked=require(script.Parent.Parent.Services.BankedBrainrotService)
        replace(world,"BeginPendingBank",function()return true end)
        replace(world,"ConfirmPendingBank",function()return true end)
        local bankReceipts={}
        local originalBankCommitted=banked.OnBankCommitted
        replace(banked,"OnBankCommitted",function(self,player,receipt)
            table.insert(bankReceipts,receipt)
            return originalBankCommitted(self,player,receipt)
        end)
        replace(banked,"RegisterPendingBank",function(_self,_player,_record,_revision,onSaved)
            onSaved() return {ok=true,state="Confirmed"}
        end)
		local ok, err = xpcall(function()
			Storage:Start({ Profile = walletOwner })
			assigned(a, homes[a])
			assigned(b, homes[b])
			callback({
				a = a,
				b = b,
				cart = ac,
				otherCart = bc,
				base = homes[a],
				otherBase = homes[b],
				template = template,
				body = body,
				storage = Storage:GetStorageForPlayer(a),
				bankReceipts = bankReceipts,
				replace = replace,
				cleanup = function(cleanupAction)
					table.insert(restores, cleanupAction)
				end,
				assigned = assigned,
				releasing = releasing,
				homes = homes,
				profiles = walletOwner.Data,
				owner = owner,
				subscriptions = function()
					return subscriptions
				end,
			})
		end, debug.traceback)
		Storage:Destroy()
		for i = #restores, 1, -1 do
			restores[i]()
		end
		-- Fixture disposal only; real cart removal is covered by lifecycle tests.
		for _, cart in carts do
			for _, record in Cargo:GetCargoSnapshot(cart) do
				local token = Cargo:DetachForTransfer(cart, record.ItemId)
				if token then
					Cargo:FinalizeTransfer(cart, token)
				end
			end
		end
		folder:Destroy()
		template:Destroy()
		for i = #createdFolders, 1, -1 do
			if #createdFolders[i]:GetChildren() == 0 then
				createdFolders[i]:Destroy()
			end
		end
		assert(ok, err)
	end
	local function add(f, metadata)
		local itemMetadata = metadata
			or {
				Tier = 1,
				Rarity = "Existing",
				Mutation = { Name = "Unchanged", Quality = 2 },
			}
		local entry = Cargo:AddCargo(f.cart, "SPEC_STORAGE_ITEM", itemMetadata)
		assert(entry, "Test cargo creation failed")
		return entry
	end
	local function visual(cart, id)
		local container = cart:FindFirstChild("CargoVisuals")
		if container then
			for _, v in container:GetChildren() do
				if v:GetAttribute("ItemId") == id then
					return v
				end
			end
		end
	end
	local function deposit(f, item)
		return Storage:TryDepositItem(f.a, f.cart, item.ItemId, f.storage)
	end

	describe("Phase 5C-1 cargo/base transfer", function()
		it("rejects registered locked slots, visitor requests and unconfirmed capacity through real ResolvePlatform", function()
			run(function(f)
				f.base:SetAttribute("OwnerUserId", f.a.UserId)
				f.base:SetAttribute("BaseOwnershipRevision", f.a.UserId)
				local context = {OwnerUserId=f.a.UserId,AssignmentRevision=f.a.UserId,ProfileReady=true}
				local function apply(capacity)
					local token = assert(Presentation.Begin(f.base, capacity, context))
					for _, part in f.base:GetChildren() do
						local index = tonumber(part.Name:match("^Slot_(%d+)$"))
						if index then Presentation.BindSlot(part, f.base, index, token) end
					end
					Presentation.Publish(f.base, token, capacity)
				end
				apply(12)
				expect(select(3, Storage:ResolvePlatform(f.a, f.base.Slot_48))).to.equal("LOCKED_SLOT")
				expect(select(3, Storage:ResolvePlatform(f.b, f.base.Slot_01))).to.equal("NOT_OWNER")
				f.profiles[f.a].Phase13.ExpansionLevel = 1 -- in-memory mutation, no presentation commit
				expect(f.storage:IsValidPlatformId(13)).to.equal(true)
				expect(select(3, Storage:ResolvePlatform(f.a, f.base.Slot_13))).to.equal("LOCKED_SLOT")
				expect(f.storage:GetOccupiedCount()).to.equal(0)
				expect(f.profiles[f.a].Economy.Balance).to.equal(0)
				expect(f.profiles[f.a].Base.Slots["48"].brainrotId).to.equal(nil)
				apply(18)
				expect(select(1, Storage:ResolvePlatform(f.a, f.base.Slot_13)).Index).to.equal(13)
				expect(select(3, Storage:ResolvePlatform(f.a, f.base.Slot_19))).to.equal("LOCKED_SLOT")
				Presentation.Invalidate(f.base, f.b.UserId, 99)
				f.base:SetAttribute("OwnerUserId", f.b.UserId)
				f.base:SetAttribute("BaseOwnershipRevision", 99)
				expect(select(3, Storage:ResolvePlatform(f.a, f.base.Slot_01))).to.equal("LOCKED_SLOT")
			end)
		end)

		it("restores a saved binding once without resetting cash or joining wild systems", function()
			run(function(f)
				-- Installed native art may already contain this accepted ID. Read it
				-- through the factory rather than adding a duplicate source model.
				if f.template.Parent:FindFirstChild("BRT_007") == nil then
					local restoredTemplate = f.template:Clone()
					restoredTemplate.Name = "BRT_007"
					restoredTemplate.Parent = f.template.Parent
					f.cleanup(function() restoredTemplate:Destroy() end)
				end
				local profile = f.profiles[f.a]
				profile.Collection.BrainrotInstances["restored-a"] = {
					speciesId = "BRT_007",
				}
				profile.Base.Slots["4"] = {
					brainrotId = "restored-a",
					accumulatedCash = 73.625,
				}

				f.releasing(f.a, f.base)
				f.assigned(f.a, f.base)
				local restored = assert(Storage:GetStorageForPlayer(f.a))
				expect(restored:GetOccupiedCount()).to.equal(1)
				expect(restored:GetPlatformRecord(4).ItemId).to.equal("restored-a")
				expect(restored:GetUnclaimedCashExact(4)).to.equal(73.625)
				expect(#f.base.StoredBrainrots:GetChildren()).to.equal(1)
				for _, descendant in f.base.StoredBrainrots:GetDescendants() do
					if descendant:IsA("BasePart") then
						expect(descendant.Anchored).to.equal(true)
						expect(descendant.CanQuery).to.equal(false)
					end
				end

				f.assigned(f.a, f.base)
				expect(Storage:GetStorageForPlayer(f.a)).to.equal(restored)
				expect(restored:GetOccupiedCount()).to.equal(1)
				expect(#f.base.StoredBrainrots:GetChildren()).to.equal(1)
			end)
		end)
		it("retains a missing-asset occupant and its cash without substituting a model", function()
			run(function(f)
				local profile = f.profiles[f.a]
				profile.Collection.BrainrotInstances["missing-asset"] = {
					speciesId = "BRT_999",
				}
				profile.Base.Slots["6"] = {
					brainrotId = "missing-asset",
					accumulatedCash = 44.5,
				}
				f.releasing(f.a, f.base)
				f.assigned(f.a, f.base)
				local restored = assert(Storage:GetStorageForPlayer(f.a))
				expect(restored:GetPlatformRecord(6).ItemId).to.equal("missing-asset")
				expect(restored:GetUnclaimedCashExact(6)).to.equal(44.5)
				expect(profile.Collection.BrainrotInstances["missing-asset"] ~= nil).to.equal(true)
				local container = f.base:FindFirstChild("StoredBrainrots")
				expect(container == nil or #container:GetChildren() == 0).to.equal(true)
			end)
		end)
		it("guards reject reentrant transfers without acquiring a second reservation", function()
			run(function(f)
				local a = add(f)
				local original = Cargo.CreateItemVisual
				local nestedResult
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					nestedResult = deposit(f, a)
					return original(self, id)
				end)
				expect(deposit(f, a).ok).to.equal(true)
				expect(nestedResult.code).to.equal("BUSY")
				expect(f.storage:GetOccupiedCount()).to.equal(1)
				expect(f.storage:GetAvailableSlotCount()).to.equal(11)
			end)
		end)
		it(
			"moves exactly one item/visual, retains identity/metadata, and grounds a rotated non-centred pivot",
			function()
				run(function(f)
					local a = add(f)
					local old = visual(f.cart, a.ItemId)
					local cartPivot = f.cart:GetPivot()
					local result = deposit(f, a)
					expect(result.code).to.equal("DEPOSITED")
					expect(result.slotIndex).to.equal(1)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					expect(f.cart:GetAttribute("CargoCount")).to.equal(0)
					expect(f.storage:GetOccupiedCount()).to.equal(1)
					expect(old.Parent).to.equal(nil)
					local data = f.storage:GetSnapshot()[1]
					expect(data.ItemId).to.equal(a.ItemId)
					expect(data.Metadata.Mutation.Quality).to.equal(2)
					expect(data.AttachmentIndex).to.equal(nil)
					local display = f.base.StoredBrainrots:GetChildren()[1]
					local bounds, size = display:GetBoundingBox()
					local marker = f.base.Slot_01.BrainrotPlacement
					expect(math.abs(bounds.Position.Y - size.Y / 2 - marker.WorldPosition.Y - 0.05) < 0.001).to.equal(
						true
					)
					expect(bounds.LookVector:Dot(marker.WorldCFrame.LookVector) > 0.999).to.equal(true)
					expect(
						display.Body.Anchored
							and not display.Body.CanCollide
							and not display.Body.CanTouch
							and not display.Body.CanQuery
					).to.equal(true)
					expect(f.cart:GetPivot()).to.equal(cartPivot)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(2)
				end)
			end
		)
		it("stores same-species individuals separately and rejects duplicate requests without revisions", function()
			run(function(f)
				local a = add(f)
				local b = add(f)
				expect(a.ItemId ~= b.ItemId).to.equal(true)
				deposit(f, a)
				deposit(f, b)
				local revision = Cargo:GetCargoRevision(f.cart)
				expect(deposit(f, a).code).to.equal("ALREADY_STORED")
				expect(f.storage:GetOccupiedCount()).to.equal(2)
				expect(#f.base.StoredBrainrots:GetChildren()).to.equal(2)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
			end)
		end)
		it("emits transaction identity only after covering-save confirmation and never on duplicate deposit", function()
			run(function(f)
				local template = f.template:Clone()
				template.Name, template.Parent = "BRT_007", f.template.Parent
				f.cleanup(function() template:Destroy() end)
				local pending
				local banked = require(script.Parent.Parent.Services.BankedBrainrotService)
				f.replace(banked, "RegisterPendingBank", function(_self, _player, _record, _revision, callback)
					pending = callback
					return { ok = true, state = "Pending" }
				end)
				local item = assert(Cargo:AddCargo(f.cart, "BRT_007", {MutationId="None"}))
				local result = deposit(f, item)
				expect(result.ok).to.equal(true)
				expect(#f.bankReceipts).to.equal(0)
				assert(pending)()
				local receipt = assert(f.bankReceipts[1])
				expect(receipt.operationId).to.equal("Bank:" .. item.ItemId)
				expect(receipt.commitRevision).to.equal(result.commitRevision)
				expect(receipt.ownerUserId).to.equal(f.a.UserId)
				expect(receipt.populationReleased).to.equal(true)
				expect(receipt.populationReleaseCode).to.equal("CONFIRMED")
				expect(deposit(f, item).code).to.equal("ALREADY_STORED")
				expect(#f.bankReceipts).to.equal(1)
			end)
		end)
		it("rejects another owner's cart/base and stale or absent item identities", function()
			run(function(f)
				local a = add(f)
				expect(Storage:TryDepositItem(f.b, f.cart, a.ItemId, f.storage).code).to.equal("INVALID_CONTEXT")
				expect(Storage:TryDepositItem(f.a, f.cart, a.ItemId, Storage:GetStorageForPlayer(f.b)).code).to.equal(
					"INVALID_CONTEXT"
				)
				expect(Storage:TryDepositItem(f.a, f.cart, "absent", f.storage).code).to.equal("NOT_IN_CARGO")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
				expect(f.storage:GetOccupiedCount()).to.equal(0)
			end)
		end)
		it("partial unload retains order, exact surviving visuals/attachments, and fills the real gap", function()
			run(function(f)
				local a = add(f)
				local b = add(f)
				local c = add(f)
				local bv = visual(f.cart, b.ItemId)
				local cv = visual(f.cart, c.ItemId)
				local cf = bv:GetPivot()
				deposit(f, a)
				local remaining = Cargo:GetCargoSnapshot(f.cart)
				expect(remaining[1].ItemId).to.equal(b.ItemId)
				expect(remaining[1].AttachmentIndex).to.equal(2)
				expect(remaining[2].ItemId).to.equal(c.ItemId)
				expect(remaining[2].AttachmentIndex).to.equal(3)
				local d = add(f)
				expect(d.AttachmentIndex).to.equal(1)
				expect(visual(f.cart, b.ItemId)).to.equal(bv)
				expect(bv:GetPivot()).to.equal(cf)
				expect(visual(f.cart, c.ItemId)).to.equal(cv)
				expect(Cargo:GetCargoCapacity(f.cart)).to.equal(3)
				expect(Cargo:CanAcceptCargo(f.cart)).to.equal(false)
				expect(Cargo:AddCargo(f.cart, "SPEC_STORAGE_ITEM")).to.equal(nil)
			end)
		end)
		it("full base leaves all cargo records, revisions and visual attachment positions unchanged", function()
			run(function(f)
				for _ = 1, 12 do
					expect(deposit(f, add(f)).ok).to.equal(true)
				end
				local a = add(f)
				local b = add(f)
				local v = visual(f.cart, a.ItemId)
				local cf = v:GetPivot()
				local revision = Cargo:GetCargoRevision(f.cart)
				expect(deposit(f, a).code).to.equal("NO_SPACE")
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
				expect(Cargo:GetCargoItem(f.cart, a.ItemId)).to.equal(a)
				expect(Cargo:GetCargoItem(f.cart, b.ItemId)).to.equal(b)
				expect(v:GetPivot()).to.equal(cf)
				expect(f.storage:GetOccupiedCount()).to.equal(12)
			end)
		end)
		it("missing asset and removed marker fail before detach and release reservations/guards", function()
			run(function(f)
				local a = add(f)
				local v = visual(f.cart, a.ItemId)
				local parent = f.template.Parent
				f.template.Parent = nil
				expect(deposit(f, a).code).to.equal("INVALID_ASSET")
				expect(f.storage:GetAvailableSlotCount()).to.equal(12)
				f.template.Parent = parent
				f.base.Slot_01.BrainrotPlacement:Destroy()
				expect(deposit(f, a).code).to.equal("INVALID_PLATFORM")
				expect(Cargo:GetCargoItem(f.cart, a.ItemId)).to.equal(a)
				expect(v.Parent ~= nil).to.equal(true)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
			end)
		end)
		it("malformed base registration disables deposits but retains assigned owner's cargo", function()
			run(function(f)
				local a = add(f)
				expect(f.storage).to.equal(nil)
				expect(deposit(f, a).code).to.equal("INVALID_PLATFORM")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
			end, function(base)
				base.Slot_12:SetAttribute("SlotIndex", 1)
			end)
		end)
		it("failure after detach restores exact membership/order/attachment/revision and clears guards", function()
			run(function(f)
				local a = add(f)
				local b = add(f)
				local c = add(f)
				local v = visual(f.cart, b.ItemId)
				local revision = Cargo:GetCargoRevision(f.cart)
				local original = f.storage.CommitReservation
				f.storage.CommitReservation = function()
					assert(
						Cargo:GetCargoItem(f.cart, b.ItemId) == nil and v.Parent ~= nil,
						"Must inject after detach, with source visual intact"
					)
					error("Injected before commit")
				end
				expect(deposit(f, b).ok).to.equal(false)
				f.storage.CommitReservation = original
				local entries = Cargo:GetCargoSnapshot(f.cart)
				expect(entries[1].ItemId).to.equal(a.ItemId)
				expect(entries[2].ItemId).to.equal(b.ItemId)
				expect(entries[3].ItemId).to.equal(c.ItemId)
				expect(entries[2].AttachmentIndex).to.equal(2)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
				expect(visual(f.cart, b.ItemId)).to.equal(v)
				expect(f.storage:GetAvailableSlotCount()).to.equal(12)
				expect(#f.base.StoredBrainrots:GetChildren()).to.equal(0)
				expect(deposit(f, b).ok).to.equal(true)
			end)
		end)
		it("parenting failure after detach rolls back without publishing count changes", function()
			run(function(f)
				local a = add(f)
				local original = Cargo.DetachForTransfer
				f.replace(Cargo, "DetachForTransfer", function(self, cart, id)
					local token, reason = original(self, cart, id)
					f.base.StoredBrainrots:Destroy()
					return token, reason
				end)
				expect(deposit(f, a).ok).to.equal(false)
				expect(Cargo:GetCargoItem(f.cart, a.ItemId)).to.equal(a)
				expect(f.cart:GetAttribute("CargoCount")).to.equal(1)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
				expect(f.storage:GetOccupiedCount()).to.equal(0)
				expect(f.storage:GetAvailableSlotCount()).to.equal(12)
			end)
		end)
		it("post-commit visual failure cannot restore cargo and does not block count/revision finalisation", function()
			run(function(f)
				local a = add(f)
				local original = Cargo.FinalizeTransfer
				-- Simulate a failing post-commit observer after real finalisation.
				local detached = Cargo.DetachForTransfer
				local oldVisual = visual(f.cart, a.ItemId)
				f.replace(Cargo, "DetachForTransfer", function(self, cart, id)
					local token, reason = detached(self, cart, id)
					-- Replace only in this fixture; no fault-injection API exists in production.
					f.replace(Cargo, "FinalizeTransfer", function(service, model, t)
						local ok = original(service, model, t)
						assert(ok, "Real cargo finalisation must complete first")
						error("Injected observer failure after finalisation")
					end)
					return token, reason
				end)
				local result = deposit(f, a)
				expect(result.ok).to.equal(true)
				expect(result.code).to.equal("DEPOSITED")
				expect(result.presentationError ~= nil).to.equal(true)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
				expect(f.cart:GetAttribute("CargoCount")).to.equal(0)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(2)
				expect(oldVisual.Parent).to.equal(nil)
				expect(f.storage:GetOccupiedCount()).to.equal(1)
				expect(Cargo:CanAcceptCargo(f.cart)).to.equal(true)
			end)
		end)
		it("transfer tokens restore/finalise once and block captures during detach", function()
			run(function(f)
				local a = add(f)
				local token = Cargo:DetachForTransfer(f.cart, a.ItemId)
				expect(Cargo:CanAcceptCargo(f.cart)).to.equal(false)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
				expect(Cargo:RestoreTransfer(f.cart, token)).to.equal(true)
				expect(Cargo:RestoreTransfer(f.cart, token)).to.equal(false)
				token = Cargo:DetachForTransfer(f.cart, a.ItemId)
				expect(Cargo:FinalizeTransfer(f.cart, token)).to.equal(true)
				expect(Cargo:FinalizeTransfer(f.cart, token)).to.equal(false)
				expect(Cargo:RestoreTransfer(f.cart, token)).to.equal(false)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(2)
			end)
		end)
		it("repeated startup/bind and character reset preserve contents; release/reuse invalidates old work", function()
			run(function(f)
				local a = add(f)
				deposit(f, a)
				local s = f.storage
				Storage:Start()
				f.assigned(f.a, f.base)
				f.a.Character = Instance.new("Model")
				expect(Storage:GetStorageForPlayer(f.a)).to.equal(s)
				expect(s:GetOccupiedCount()).to.equal(1)
				expect(f.subscriptions()).to.equal(1)
				f.cart:Destroy()
				expect(s:GetOccupiedCount()).to.equal(1)
				f.releasing(f.a, f.base)
				f.homes[f.a] = nil
				f.a.Parent = nil
				expect(s:IsActive()).to.equal(false)
				local c, cart = f.owner(3, f.base)
				f.profiles[c] = ProfileSchema.CreateDefault()
				f.assigned(c, f.base)
				local replacement = Storage:GetStorageForPlayer(c)
				expect(replacement ~= s).to.equal(true)
				expect(replacement:GetOccupiedCount()).to.equal(0)
				expect(Storage:TryDepositItem(c, cart, a.ItemId, s).code).to.equal("INVALID_CONTEXT")
				f.releasing(f.a, f.base)
				expect(Storage:GetStorageForPlayer(c)).to.equal(replacement)
				f.a.Character:Destroy()
			end)
		end)
		it("display clone strips scripts/tags and external joints without modifying template/cart", function()
			run(function(f)
				local scriptInstance = Instance.new("Script")
				scriptInstance.Parent = f.template
				CollectionService:AddTag(f.template, "Huntable")
				CollectionService:AddTag(f.body, "Roaming")
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = f.body
				weld.Part1 = f.cart.CargoSlots.Slot1
				weld.Parent = f.body
				local display = Cargo:CreateItemVisual("SPEC_STORAGE_ITEM")
				expect(#CollectionService:GetTags(display)).to.equal(0)
				expect(#CollectionService:GetTags(display.Body)).to.equal(0)
				expect(display:FindFirstChildWhichIsA("LuaSourceContainer", true)).to.equal(nil)
				expect(display:FindFirstChildWhichIsA("WeldConstraint", true)).to.equal(nil)
				expect(weld.Parent).to.equal(f.body)
				expect(scriptInstance.Parent).to.equal(f.template)
				display:Destroy()
			end)
		end)
		it("notifies income synchronously for each committed revision before visual cleanup", function()
			run(function(f)
				local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
				f.template.Name = "BRT_007"
				local time, events = 100, {}
				Income:Start({
					NowMs = function()
						return time
					end,
				})
				f.cleanup(function()
					Income:Destroy()
				end)
				Income:BindStorage(f.a, f.storage)
				local a = Cargo:AddCargo(f.cart, "BRT_007")
				local b = Cargo:AddCargo(f.cart, "BRT_007")
				local revision = Cargo:GetCargoRevision(f.cart)
				f.cleanup(Storage:ObserveStorage({
					OnCommitted = function(player, storage, rev, snapshot)
						expect(player).to.equal(f.a)
						expect(storage).to.equal(f.storage)
						expect(#snapshot).to.equal(rev)
						expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision + rev)
						expect(Cargo:GetCargoCount(f.cart)).to.equal(2 - rev)
						-- The exact transferred visual still exists at this logical boundary.
						expect(visual(f.cart, snapshot[rev].ItemId) ~= nil).to.equal(true)
						expect(function()
							snapshot[1].BrainrotId = "BRT-035"
						end).to.throw()
						table.insert(events, snapshot)
					end,
					OnReleasing = function(player, storage)
						if player == f.a then
							expect(storage:IsActive()).to.equal(true)
							expect(Storage:GetStorageForPlayer(player)).to.equal(storage)
						end
					end,
				}))
				local token = f.storage:TryReserveSlot("pending")
				f.storage:CancelReservation(token)
				expect(#events).to.equal(0)
				time = 750
				expect(deposit(f, a).code).to.equal("DEPOSITED")
				expect(Income:GetIncomeRate(f.a)).to.equal(2000000)
				expect(deposit(f, b).code).to.equal("DEPOSITED")
				expect(Income:GetIncomeRate(f.a)).to.equal(4000000)
				expect(#events).to.equal(2)
				expect(#events[1]).to.equal(1)
				expect(deposit(f, b).code).to.equal("ALREADY_STORED")
				expect(#events).to.equal(2)
				f.releasing(f.a, f.base)
				expect(Income:GetIncomeRate(f.a)).to.equal(0)
			end)
		end)
		it("accrues only deposited cargo and credits the wallet only after a manual claim", function()
			run(function(f)
				local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
				f.template.Name = "BRT_007"
				function f.a:SetAttribute(name, value)
					self[name] = value
				end
				local time = 0
				Income:Start({
					NowMs = function()
						return time
					end,
				})
				f.cleanup(function()
					Income:Destroy()
				end)
				Income:BindStorage(f.a, f.storage)
				local a, b, c =
					Cargo:AddCargo(f.cart, "BRT_007"),
					Cargo:AddCargo(f.cart, "BRT_007"),
					Cargo:AddCargo(f.cart, "BRT_007")
				local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
				-- Disposal of these exact three fixture identities must also cover
				-- pending recovery when a preceding assertion exits early.
				f.cleanup(function()
					for _, entry in { a, b, c } do
						Cargo:CancelPendingReturnForTesting(entry.ItemId)
						World.DestroyWorldForTesting(entry.ItemId)
					end
				end)
				time = 10000
				Income:Step()
				expect(Wallet:GetBalance(f.a)).to.equal(0)
				expect(Income:GetIncomeRate(f.a)).to.equal(0)
				local bVisual, cVisual = visual(f.cart, b.ItemId), visual(f.cart, c.ItemId)
				local deposited = deposit(f, a)
				expect(deposited.code).to.equal("DEPOSITED")
				expect(Income:GetIncomeRate(f.a)).to.equal(2000000)
				time = 20000
				Income:Step()
				expect(Wallet:GetBalance(f.a)).to.equal(0)
				local claimed = Income:TryClaimPlatform(f.a, f.base:GetAttribute("BaseId"), deposited.slotIndex)
				expect(claimed.paid).to.equal(20000000)
				expect(Wallet:GetBalance(f.a)).to.equal(20000000)
				expect(f.a.Cash).to.equal(20000000)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(2)
				expect(visual(f.cart, b.ItemId)).to.equal(bVisual)
				expect(visual(f.cart, c.ItemId)).to.equal(cVisual)
				expect(Cargo:GetCargoItem(f.cart, b.ItemId).AttachmentIndex).to.equal(2)
				-- This old income fixture removes a loaded cart: give restoration real
				-- ground and retire the resulting fixture models before its template.
				local ground = Instance.new("Part")
				ground.Name, ground.Anchored = "RemovalFixtureGround", true
				ground:SetAttribute("CartDrivableGround", true)
				ground.Size = Vector3.new(100, 1, 100)
				local pivot = f.cart:GetPivot()
				ground.Position, ground.Parent = Vector3.new(pivot.X, -0.5, pivot.Z), f.cart.Parent
				f.cart:Destroy()
				task.wait()
				Cargo:ProcessPendingReturns()
				local restored = 0
				for _, model in World.GetWorldModels() do
					local record = World.GetWorldRecord(model)
					if record.ItemId == b.ItemId or record.ItemId == c.ItemId then
						restored += 1
						World.DestroyWorldForTesting(record.ItemId) -- Exact diagnostic fixture individuals only.
					end
				end
				expect(restored).to.equal(2)
				for _, entry in { b, c } do
					expect(World.GetWorldModelById(entry.ItemId)).to.equal(nil)
					for _, pendingId in Cargo:GetRemovalDiagnostics().PendingIds do
						expect(pendingId == entry.ItemId).to.equal(false)
					end
				end
				f.a.Character = nil
				time = 21000
				Income:Step()
				expect(Wallet:GetBalance(f.a)).to.equal(20000000)
				expect(Income:TryClaimPlatform(f.a, f.base:GetAttribute("BaseId"), deposited.slotIndex).paid).to.equal(
					2000000
				)
				expect(Wallet:GetBalance(f.a)).to.equal(22000000)
				print(
					"[INCOME_INTEGRATION] cargo-only=0 deposited-rate=3000 after-10s=30000 after-cart-destroy=33000 survivors-retained=true"
				)
			end)
		end)
		it("observer exceptions cannot roll back a committed deposit or block other observers", function()
			run(function(f)
				local calls = 0
				f.cleanup(Storage:ObserveStorage({
					OnCommitted = function()
						error("injected observer failure")
					end,
				}))
				f.cleanup(Storage:ObserveStorage({
					OnCommitted = function()
						calls += 1
					end,
				}))
				local item = add(f)
				expect(deposit(f, item).code).to.equal("DEPOSITED")
				expect(calls).to.equal(1)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
				expect(f.storage:ContainsItem(item.ItemId)).to.equal(true)
			end)
		end)
	end)
end
