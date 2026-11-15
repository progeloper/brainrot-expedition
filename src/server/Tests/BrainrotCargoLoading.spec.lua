--!nocheck
-- Isolated Studio geometry/transaction fixtures, not a live driving playtest.
-- Fake Player/current-cart registry only; real world, carry, cargo, raycasts and welds.
return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Physics = game:GetService("PhysicsService")
	local Collection = game:GetService("CollectionService")
	local Run = game:GetService("RunService")
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)
	local Services, Systems = script.Parent.Parent.Services, script.Parent.Parent.Systems
	local Cargo = require(Services.CartCargoService)
	local Carts = require(Services.CartService)
	local Occupants = require(Services.CartOccupantService)
	local Interaction = require(Systems.BrainrotInteractionSystem)
	local World = require(Systems.DevelopmentBrainrotSpawner)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Roaming = require(Systems.DevelopmentBrainrotRoaming)
	local Combat = require(Services.PlayerCombatService)
	local Shield = require(Services.CartShieldService)
	local Sleep = require(Systems.BrainrotSleepSystem)
	local Upgrades = require(RS.Shared.Config.Upgrades)

	-- Camera-ray intent adapter for existing lifecycle fixtures, not gameplay input.
	local function fireAt(player, point)
		local origin = player.Character.HumanoidRootPart.Position
		local offset = point - origin
		return Sleep.HandleFireRequest(player, {
			CameraOrigin = origin,
			CameraDirection = if offset.Magnitude > 0.001 then offset.Unit else -Vector3.zAxis,
		})
	end
	local Return = require(Systems.BaseReturnSystem)
	local Currency = require(Systems.CurrencySystem)
	local Income = require(Systems.BrainrotIncomeSystem)
	local sequence = -38000
	local suiteFixtureItemIds = {}
	local function withRunningSimulation(callback)
		local wasRunning = Run:IsRunning()
		if not wasRunning then
			Run:Run()
		end
		local ok, failure = xpcall(callback, debug.traceback)
		if not wasRunning then
			Run:Pause()
		end
		assert(ok, failure)
	end

	local function cleanupFixtureItems(itemIds)
		for itemId in itemIds do
			Cargo:CancelPendingReturnForTesting(itemId)
			World.DestroyWorldForTesting(itemId)
		end
		for _, model in World.GetWorldModels() do
			local record = World.GetWorldRecord(model)
			if record and itemIds[record.ItemId] then
				World.DestroyWorldForTesting(record.ItemId)
			end
		end
	end

	local function fixture(test)
		Placement.ResetQueryBudgetForTesting()
		assert(Interaction.Stop())
		-- Service heartbeats and deliberately yielding fixture callbacks can finish
		-- after the fixture that minted an item has begun teardown. Reconcile the
		-- exact suite-owned identities before installing the next fixed-geometry
		-- fixture so a late publication cannot become its raycast obstruction.
		cleanupFixtureItems(suiteFixtureItemIds)
		Return:Destroy() -- Production bootstrap no longer starts automatic return/deposit.
		local owned, restores, fixtureItemIds = {}, {}, {}
		local function own(v)
			table.insert(owned, v)
			return v
		end
		local function ownRecord(record)
			fixtureItemIds[record.ItemId] = true
			suiteFixtureItemIds[record.ItemId] = true
			return record
		end
		local function replace(object, key, value)
			local old = object[key]
			table.insert(restores, function()
				object[key] = old
			end)
			object[key] = value
		end
		local function folder(parent, name)
			local found = parent:FindFirstChild(name)
			if found then
				return found
			end
			local v = own(Instance.new("Folder"))
			v.Name, v.Parent = name, parent
			return v
		end
		local root = own(Instance.new("Folder"))
		root.Name, root.Parent = "SPEC_CARGO_LOAD", workspace
		local origin = Vector3.new(24000, 103, 24000)
		local function part(parent, name, position, size)
			local p = Instance.new("Part")
			p.Name, p.Position, p.Size, p.Anchored, p.Parent =
				name, position, size or Vector3.new(2, 2, 2), true, parent
			return p
		end
		part(root, "Ground", origin - Vector3.new(0, 4, 0), Vector3.new(400, 2, 400)):SetAttribute(
			"CartDrivableGround",
			true
		)
		local templates = folder(folder(RS, "StudioAssets"), "Brainrots")
		local template = own(Instance.new("Model"))
		template.Name = "SPEC_CARGO_LOAD_TEMPLATE"
		local body = part(template, "Body", Vector3.zero, Vector3.new(2, 5, 2))
		body.RootPriority = 127
		local detail = part(template, "Detail", Vector3.new(1, 1, 0), Vector3.one)
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Parent = "CaptureAttachment", body
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = body, detail, body
		Instance.new("BodyForce", body).Force = Vector3.new(0, 100, 0)
		Instance.new("ParticleEmitter", body).Enabled = false
		local oldPrompt = Instance.new("ProximityPrompt")
		oldPrompt.Parent = body
		local inert = Instance.new("Script")
		inert.Disabled, inert.Parent = true, template
		template.PrimaryPart, template.Parent = body, templates
		-- Keep this transaction fixture independent of the live Studio-only model
		-- folder while still exercising distinct canonical species identities.
		for _, speciesId in { "BRT_007", "BRT_011", "BRT_015" } do
			local definition = assert(Catalog.Get(speciesId))
			if not templates:FindFirstChild(definition.modelRef) then
				local alias = own(template:Clone())
				alias.Name = definition.modelRef
				alias.Parent = templates
			end
		end
		if not Physics:IsCollisionGroupRegistered("Carts") then
			Physics:RegisterCollisionGroup("Carts")
		end
		sequence -= 1
		local character = Instance.new("Model")
		character.Name, character.Parent = "Character", root
		local hrp = part(character, "HumanoidRootPart", origin + Vector3.new(0, 0, 5))
		part(character, "Head", hrp.Position + Vector3.new(0, 1.5, 0))
		character.PrimaryPart = hrp
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck, humanoid.Parent = false, character
		local removing = own(Instance.new("BindableEvent"))
		local attributes = {}
		local p = {
			Name = "CargoLoadSpec",
			UserId = sequence,
			Parent = Players,
			CameraMaxZoomDistance = 128,
			Character = character,
			CharacterRemoving = removing.Event,
		}
		function p:GetAttribute(k)
			return attributes[k]
		end
		function p:SetAttribute(k, v)
			attributes[k] = v
		end
		local cart = Instance.new("Model")
		cart.Name, cart.Parent = "SpecCart", root
		cart:SetAttribute("CartId", "CRT_001")
		cart:SetAttribute("OwnerUserId", p.UserId)
		cart:SetAttribute("RuntimeCart", true)
		local chassis = part(cart, "Root", origin + Vector3.new(30, -2, 0), Vector3.new(6, 1, 10))
		cart.PrimaryPart = chassis
		local slots = Instance.new("Folder")
		slots.Name, slots.Parent = "CargoSlots", cart
		for _, i in { 5, 3, 1, 4, 2 } do -- Authored extras do not unlock themselves.
			local s = part(slots, "Slot" .. i, origin + Vector3.new(28 + (i - 1) * 2, 0, 3.5), Vector3.one)
			s.Anchored, s.CanCollide, s.Massless = false, false, true
			local a = Instance.new("Attachment")
			a.Name, a.CFrame, a.Parent = "CargoAttachment", CFrame.Angles(0, math.rad(i * 15), 0), s
			local joint = Instance.new("WeldConstraint")
			joint.Part0, joint.Part1, joint.Parent = chassis, s, s
		end
		local current = { Model = cart, OwnerUserId = p.UserId }
		replace(Carts, "GetCart", function(_, who)
			return if who == p then current.Model else nil
		end)
		replace(Carts, "GetCartRecordByOwnerUserId", function(_, id)
			return if id == p.UserId then current else nil
		end)
		replace(Carts, "GetCartRecords", function()
			return { current }
		end)
		local function spawn(awake, speciesId, metadata)
			local record = {
				ItemId = Http:GenerateGUID(false),
				BrainrotId = speciesId or template.Name,
				Metadata = metadata or { Tier = 3, Mutation = { Name = "Original", Quality = 7 } },
				World = {
					Name = "SPEC_LOAD",
					Scale = 1.1,
					SpawnPosition = { X = origin.X, Y = origin.Y, Z = origin.Z },
				},
			}
			ownRecord(record)
			local prepared = assert(World.PrepareWorldRepresentation(record, CFrame.new(origin)))
			local model = assert(World.ActivatePreparedWorld(prepared))
			if not awake and not (metadata and type(metadata.DurableOwnerUserId) == "number") then
				assert(World.TrySleep(model))
			end
			return model, World.GetWorldRecord(model)
		end
		local function carry(speciesId, metadata)
			character:PivotTo(CFrame.new(origin + Vector3.new(0, 0, 5)))
			local m, r = spawn(nil, speciesId, metadata)
			assert(Interaction.TryPickupWorld(p, m, r.ItemId))
			return r
		end
		local function near(slotId)
			character:PivotTo(CFrame.new(slots[slotId].CargoAttachment.WorldPosition + Vector3.new(0, 0, 5)))
		end
		local role = { Driving = false }
		local capacityConfigured = false
		local function configureCapacity(options)
			if not capacityConfigured then
				capacityConfigured = true
				table.insert(restores, function()
					Cargo:ConfigureCapacity(nil)
				end)
			end
			Cargo:ConfigureCapacity(options)
		end
		local setupCount = #restores
		local interactionDeps = {
			World = World,
			CreateItemVisual = function(id)
				return Cargo:CreateItemVisual(id)
			end,
			IsDriving = function()
				return role.Driving
			end,
		}
		local ok, failure = xpcall(function()
			Interaction.Start(interactionDeps)
			Occupants:SetCarryingPredicate(Interaction.IsCarrying)
			Sleep.SetCarryingPredicate(Interaction.IsCarrying)
			Cargo:Start()
			test({
				p = p,
				removing = removing,
				deps = interactionDeps,
				cart = cart,
				root = root,
				chassis = chassis,
				slots = slots,
				template = template,
				origin = origin,
				carry = carry,
				spawn = spawn,
				near = near,
				part = part,
				replace = replace,
				current = current,
				role = role,
				configureCapacity = configureCapacity,
				ownRecord = ownRecord,
			})
		end, debug.traceback)
		for i = #restores, setupCount + 1, -1 do
			restores[i]()
		end
		Interaction.SetActionValidator(nil)
		Combat:_ConfigureForTests(nil)
		Combat:ConfigureTransactions(nil)
		assert(Interaction.Stop())
		Occupants:SetCarryingPredicate(nil)
		Sleep.SetCarryingPredicate(nil)
		-- Diagnostic fixture teardown, not a gameplay inventory-removal endpoint.
		for _, record in Cargo:GetCargoSnapshot(cart) do
			local token = Cargo:DetachForTransfer(cart, record.ItemId)
			if token then
				Cargo:FinalizeTransfer(cart, token)
			end
		end
		for i = #restores, 1, -1 do
			restores[i]()
		end
		-- A fixture may intentionally stop with an unavailable factory/ground, or
		-- fail before its pending return retries. Cancel only records minted by
		-- this fixture so the shared service heartbeat cannot publish them into
		-- the next fixture's fixed raycast corridor.
		cleanupFixtureItems(fixtureItemIds)
		for i = #owned, 1, -1 do
			owned[i]:Destroy()
		end
		assert(ok, failure)
	end

	local function load(f, slotId)
		local r = f.carry()
		f.near(slotId)
		local ok, reason = Interaction.TryPlaceInCargo(f.p, f.cart, slotId, r.ItemId)
		if not ok and reason == "OBSTRUCTED" then
			local target = f.slots[slotId].CargoAttachment.WorldPosition
			local head = f.p.Character:FindFirstChild("Head")
			local origin = if head and head:IsA("BasePart")
				then head.Position
				else f.p.Character.HumanoidRootPart.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { f.p.Character, f.cart }
			params.IgnoreWater = false
			params.RespectCanCollide = false
			local obstruction = workspace:Raycast(origin, target - origin, params)
			error(
				string.format("OBSTRUCTED_BY:%s", if obstruction then obstruction.Instance:GetFullName() else "UNKNOWN"),
				2
			)
		end
		assert(ok, reason)
		return r
	end
	local function fillOtherSlots(f, occupiedSlot)
		for _, slot in { "Slot1", "Slot2", "Slot3" } do
			if slot ~= occupiedSlot then
				load(f, slot)
			end
		end
	end
	local function unchangedCarry(f, r, count)
		expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(r.ItemId)
		expect(f.p:GetAttribute("CarriedItemId")).to.equal(r.ItemId)
		expect(f.p.Character:FindFirstChild("CarriedBrainrot") ~= nil).to.equal(true)
		expect(Cargo:GetCargoCount(f.cart)).to.equal(count or 0)
	end

	local function worldIndividual(id)
		local found, count = nil, 0
		for _, model in World.GetWorldModels() do
			if World.GetWorldRecord(model).ItemId == id then
				found, count = model, count + 1
			end
		end
		return found, count
	end

	local function combatFixture(f, options)
		local players = { [f.p.UserId] = f.p }
		for _, slot in f.cart.CargoSlots:GetChildren() do
			if slot:IsA("BasePart") then
				slot.CanQuery = false
			end
		end
		local clock = 2000
		local function actor(id, position)
			local character = Instance.new("Model")
			character.Name, character.Parent = "Phase10Actor" .. id, f.root
			local root = f.part(character, "HumanoidRootPart", position)
			root.CanCollide = false
			local head = f.part(character, "Head", position + Vector3.yAxis * 2)
			head.CanCollide = false
			local h = Instance.new("Humanoid")
			h.RequiresNeck, h.Parent = false, character
			character.PrimaryPart = root
			local attrs = {}
			local player = { UserId = id, Parent = Players, Character = character, Name = "Phase10Actor" }
			function player:SetAttribute(key, value)
				attrs[key] = value
			end
			function player:GetAttribute(key)
				return attrs[key]
			end
			players[id] = player
			return player
		end
		local banked = {}
		function banked:ClassifyRecord(_player, record)
			return if type(record.Metadata.DurableOwnerUserId) == "number" then "Banked" else "FreshUnbanked"
		end
		function banked:GetOwnedIndividual()
			return nil
		end
		f.deps.Banked = banked
		Combat:_ConfigureForTests({
			Now = function()
				return clock
			end,
			Ready = function()
				return true
			end,
			Camp = function()
				return false
			end,
			Playtime = function()
				return 900
			end,
			PlayerByUserId = function(id)
				return players[id]
			end,
			PlayerFromCharacter = function(character)
				for _, player in players do
					if player.Character == character then
						return player
					end
				end
				return nil
			end,
		})
		local transactions = {
			Cargo = Cargo,
			Carry = Interaction,
			World = World,
			Banked = banked,
			Name = function(id)
				return id
			end,
			Feedback = function() end,
			ValidateContext = function()
				return true
			end,
		}
		Combat:ConfigureTransactions(transactions)
		Interaction.SetActionValidator(function(player)
			return Combat:CanAct(player)
		end)
		local function hitBody(attacker, body, intent)
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances =
				Enum.RaycastFilterType.Exclude, { attacker.Character }
			local offset = body.Position - attacker.Character.PrimaryPart.Position
			local hit = workspace:Raycast(
				attacker.Character.PrimaryPart.Position,
				offset.Unit * (offset.Magnitude + 0.5),
				params
			)
			assert(
				hit and hit.Instance == body,
				"Fixture must use a real first unobstructed torso ray; hit="
					.. (if hit then hit.Instance:GetFullName() else "nil")
					.. "; expected="
					.. body:GetFullName()
			)
			local context = { Character = attacker.Character }
			-- The Shield fixture models a shot already accepted by CaptureSystem.
			-- Other transaction tests keep their existing isolated combat context.
			if options and options.AcceptedShots then
				context.AcceptedRequestId = intent.RequestId
			end
			return Combat:ResolveImpact(attacker, context, hit, hit, intent)
		end
		return {
			Actor = actor,
			Hit = hitBody,
			SetClock = function(value)
				clock = value
			end,
			GetClock = function()
				return clock
			end,
			SetTransactions = function(extra)
				for key, value in extra do
					transactions[key] = value
				end
				Combat:ConfigureTransactions(transactions)
			end,
		}
	end

	describe("Phase 10 actual cargo and held release transactions", function()
		it("native Humanoid death exposes fresh cargo locally and preserves banked slots and the cart", function()
			fixture(function(f)
				local banked = f.carry("BRT_011", { Tier = 3, DurableOwnerUserId = f.p.UserId })
				f.near("Slot2")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", banked.ItemId))
				local fresh = f.carry("BRT_007")
				f.near("Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", fresh.ItemId))
				local originalCharacter = f.p.Character
				originalCharacter:PivotTo(CFrame.new(f.origin + Vector3.new(20, 0, 20)))
				-- This event case needs a complete native R6 assembly. The other
				-- geometry fixtures deliberately use only an anchored Root and Head.
				local rigRoot, rigHead = originalCharacter.HumanoidRootPart, originalCharacter.Head
				rigRoot.Size, rigRoot.CanCollide, rigRoot.Transparency = Vector3.new(2, 2, 1), false, 1
				rigHead.Size, rigHead.CanCollide = Vector3.new(2, 1, 1), true
				local torso = f.part(originalCharacter, "Torso", rigRoot.Position, Vector3.new(2, 2, 1))
				local leftArm = f.part(
					originalCharacter,
					"Left Arm",
					rigRoot.Position + Vector3.new(-1.5, 0, 0),
					Vector3.new(1, 2, 1)
				)
				local rightArm = f.part(
					originalCharacter,
					"Right Arm",
					rigRoot.Position + Vector3.new(1.5, 0, 0),
					Vector3.new(1, 2, 1)
				)
				local leftLeg = f.part(
					originalCharacter,
					"Left Leg",
					rigRoot.Position + Vector3.new(-0.5, -2, 0),
					Vector3.new(1, 2, 1)
				)
				local rightLeg = f.part(
					originalCharacter,
					"Right Leg",
					rigRoot.Position + Vector3.new(0.5, -2, 0),
					Vector3.new(1, 2, 1)
				)
				local function motor(name, parent, child, c0, c1)
					local joint = Instance.new("Motor6D")
					joint.Name, joint.Part0, joint.Part1, joint.C0, joint.C1, joint.Parent =
						name, parent, child, c0, c1, parent
				end
				motor("RootJoint", rigRoot, torso, CFrame.identity, CFrame.identity)
				motor("Neck", torso, rigHead, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
				motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
				motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
				motor("Left Hip", torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
				motor("Right Hip", torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))
				for _, part in originalCharacter:GetChildren() do
					if part:IsA("BasePart") then
						part.Anchored = false
					end
				end
				local rigHumanoid = originalCharacter:FindFirstChildOfClass("Humanoid")
				rigHumanoid.RigType, rigHumanoid.EvaluateStateMachine = Enum.HumanoidRigType.R6, true
				rigHumanoid.RequiresNeck, rigHumanoid.BreakJointsOnDeath = true, false
				rigHumanoid.WalkSpeed, rigHumanoid.AutoRotate = 0, false
				rigHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
				local cartPose, before = f.cart:GetPivot(), World.GetPopulationSnapshot().Effective
				local bankedVisual
				for _, visual in f.cart.CargoVisuals:GetChildren() do
					if visual:GetAttribute("ItemId") == banked.ItemId then
						bankedVisual = visual
					end
				end
				local originalProcess = World.ProcessPendingFreshReleases
				local paused = true
				f.replace(World, "ProcessPendingFreshReleases", function(...)
					return if paused then 0 else originalProcess(...)
				end)
				assert(Interaction._TrackCharacterForTesting(f.p))
				local humanoid = originalCharacter:FindFirstChildOfClass("Humanoid")
				local deaths = 0
				local died = humanoid.Died:Connect(function()
					deaths += 1
				end)
				local deathOk, deathFailure = xpcall(function()
					-- Native Humanoid state transitions need simulation; the suite
					-- normally executes in paused Edit mode, like the terrain fixtures.
					withRunningSimulation(function()
						-- Let the engine discover the complete unanchored assembly.
						task.wait(0.1)
						humanoid:TakeDamage(humanoid.Health)
						local deathDeadline = os.clock() + 2
						while (Cargo:GetCargoCount(f.cart) > 1 or deaths == 0) and os.clock() < deathDeadline do
							task.wait()
						end
						expect(humanoid.Health <= 0).to.equal(true)
						expect(deaths).to.equal(1)
					end)
				end, debug.traceback)
				died:Disconnect()
				assert(deathOk, deathFailure)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1")).to.equal(nil)
				expect(Cargo:GetSlotRecord(f.cart, "Slot2").ItemId).to.equal(banked.ItemId)
				expect(bankedVisual.Parent).to.equal(f.cart.CargoVisuals)
				expect(Carts:GetCart(f.p)).to.equal(f.cart)
				expect(f.cart:GetPivot()).to.equal(cartPose)
				expect(World.GetPopulationSnapshot().Effective).to.equal(before)
				local pending
				for _, item in World.GetPopulationSnapshot().PendingWorldRecords do
					if item.ItemId == fresh.ItemId then
						pending = item
					end
				end
				expect(pending ~= nil).to.equal(true)
				expect(pending.Position).to.equal(cartPose.Position)
				expect(Interaction.HandleCharacterRemoving(f.p, originalCharacter)).to.equal(false)
				paused = false
				local deadline = os.clock() + 4
				local loose
				repeat
					Cargo:ProcessPendingReturns()
					loose = worldIndividual(fresh.ItemId)
					if not loose then
						task.wait(0.05)
					end
				until loose or os.clock() >= deadline
				expect(loose ~= nil).to.equal(true)
				expect(select(2, worldIndividual(fresh.ItemId))).to.equal(1)
				expect(select(2, World.GetWorldRecord(loose))).to.equal("WorldAwake")
				expect((loose:GetPivot().Position - cartPose.Position).Magnitude < 9).to.equal(true)
				expect(World.GetPopulationSnapshot().Effective).to.equal(before)
				-- Old death/removal callbacks must not expose a replacement generation's haul.
				local replacement = originalCharacter:Clone()
				replacement.Parent = f.root
				replacement:FindFirstChildOfClass("Humanoid").Health = 100
				replacement:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 5)))
				f.p.Character = replacement
				assert(Interaction._TrackCharacterForTesting(f.p))
				local nextModel, nextRecord = f.spawn(false, "BRT_007")
				assert(Interaction.TryPickupWorld(f.p, nextModel, nextRecord.ItemId))
				replacement:PivotTo(CFrame.new(f.slots.Slot1.CargoAttachment.WorldPosition + Vector3.new(0, 0, 5)))
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", nextRecord.ItemId))
				f.removing:Fire(originalCharacter)
				expect(Interaction.HandleCharacterRemoving(f.p, originalCharacter)).to.equal(false)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(nextRecord.ItemId)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(2)
			end)
		end)

		it("preflights every fresh departure source and rolls back a failed exact queue handoff", function()
			fixture(function(f)
				local first = f.carry("BRT_007")
				f.near("Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", first.ItemId))
				local second = f.carry("BRT_007")
				f.near("Slot3")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot3", second.ItemId))
				local originalPreflight, originalQueue = World.CanQueueFreshRelease, World.QueueFreshRelease
				local invalid, rejectQueue, queueCalls = true, false, 0
				f.replace(World, "CanQueueFreshRelease", function(record, pose)
					if invalid and record.ItemId == second.ItemId then
						return false, "INVALID_RELEASE"
					end
					return originalPreflight(record, pose)
				end)
				f.replace(World, "QueueFreshRelease", function(...)
					queueCalls += 1
					if rejectQueue then
						return false, "INJECTED_QUEUE_FAILURE"
					end
					return originalQueue(...)
				end)
				f.replace(World, "ProcessPendingFreshReleases", function()
					return 0
				end)
				local revision = Cargo:GetCargoRevision(f.cart)
				local visuals = f.cart.CargoVisuals:GetChildren()
				local released, reason = Cargo:ReleaseFreshForCharacterDeparture(f.cart)
				expect(released).to.equal(false)
				expect(reason).to.equal("INVALID_RELEASE")
				expect(queueCalls).to.equal(0)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(2)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
				invalid, rejectQueue = false, true
				released, reason = Cargo:ReleaseFreshForCharacterDeparture(f.cart)
				expect(released).to.equal(false)
				expect(reason).to.equal("INJECTED_QUEUE_FAILURE")
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(first.ItemId)
				expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(second.ItemId)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
				for _, visual in visuals do
					expect(visual.Parent).to.equal(f.cart.CargoVisuals)
				end
				rejectQueue = false
				expect(Interaction.HandleCharacterRemoving(f.p, f.p.Character)).to.equal(true)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision + 2)
				expect(Interaction.HandleCharacterRemoving(f.p, f.p.Character)).to.equal(false)
				expect(queueCalls).to.equal(3)
			end)
		end)

		it(
			"one exact cargo hit releases same awake individual; protection/stale hints preserve the next occupant",
			function()
				fixture(function(f)
					local first = f.carry("BRT_007")
					f.near("Slot1")
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", first.ItemId))
					local second = f.carry("BRT_007")
					f.near("Slot2")
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", second.ItemId))
					f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(20, 0, 20)))
					local cf = combatFixture(f)
					local visual = f.cart.CargoVisuals:FindFirstChild(first.ItemId)
					-- Cargo names may be display labels; resolve the existing exact target.
					if not visual then
						for _, candidate in f.cart.CargoVisuals:GetChildren() do
							if candidate:GetAttribute("ItemId") == first.ItemId then
								visual = candidate
								break
							end
						end
					end
					local body = assert(visual, "Missing exact cargo visual"):FindFirstChild("Body", true)
					local attacker = cf.Actor(-98001, body.Position + Vector3.new(-14, 0, 0))
					local handled, outcome =
						cf.Hit(attacker, body, { RequestId = 1, TargetItemId = first.ItemId, TargetCartId = "CRT_001" })
					expect(handled).to.equal(true)
					expect(outcome).to.equal("CargoKnockedLoose")
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					local loose, count = worldIndividual(first.ItemId)
					expect(count).to.equal(1)
					local record, state = World.GetWorldRecord(loose)
					expect(state).to.equal("WorldAwake")
					expect(record.ItemId).to.equal(first.ItemId)
					expect(record.BrainrotId).to.equal(first.BrainrotId)
					expect(record.Metadata.Mutation.Quality).to.equal(first.Metadata.Mutation.Quality)
					expect(World.IsWild(record.ItemId)).to.equal(true)
					local secondVisual
					for _, candidate in f.cart.CargoVisuals:GetChildren() do
						if candidate:GetAttribute("ItemId") == second.ItemId then
							secondVisual = candidate
							break
						end
					end
					local secondBody = secondVisual:FindFirstChild("Body", true)
					attacker.Character:PivotTo(CFrame.new(secondBody.Position + Vector3.new(14, 0, 0)))
					local _, protected = cf.Hit(
						attacker,
						secondBody,
						{ RequestId = 2, TargetItemId = second.ItemId, TargetCartId = "CRT_001" }
					)
					expect(protected).to.equal("ProtectedTarget")
					local otherAttacker = cf.Actor(-98004, secondBody.Position + Vector3.new(0, 0, 14))
					local _, globallyProtected = cf.Hit(
						otherAttacker,
						secondBody,
						{ RequestId = 1, TargetItemId = second.ItemId, TargetCartId = "CRT_001" }
					)
					expect(globallyProtected).to.equal("ProtectedTarget")
					expect(Cargo:GetCargoItem(f.cart, second.ItemId) ~= nil).to.equal(true)
					cf.SetClock(2061)
					local _, stale = cf.Hit(
						attacker,
						secondBody,
						{ RequestId = 3, TargetItemId = first.ItemId, TargetCartId = "CRT_001" }
					)
					expect(stale).to.equal("StaleTarget")
					expect(Cargo:GetCargoItem(f.cart, second.ItemId) ~= nil).to.equal(true)
					-- A distinct ordinary capture call is necessary to sleep the loose catch.
					expect(World.TrySleep(loose)).to.equal(true)
					expect(select(2, World.GetWorldRecord(loose))).to.equal("WorldSleeping")
				end)
			end
		)

		it("the existing Shield handoff retains cargo and combat state, then releases once at expiry", function()
			fixture(function(f)
				local record = f.carry("BRT_007")
				f.near("Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", record.ItemId))
				f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(20, 0, 20)))
				local cf = combatFixture(f, { AcceptedShots = true })
				local visual = f.cart.CargoVisuals:GetChildren()[1]
				local body = visual:FindFirstChild("Body", true)
				local attacker = cf.Actor(-98006, body.Position + Vector3.new(-14, 0, 0))
				f.cart:SetAttribute("CartGeneration", 1)
				local cartRecord = { Model = f.cart, OwnerUserId = f.p.UserId, Generation = 1 }
				local ownBase = true
				local actors = { [f.p] = true, [attacker] = true }
				local function session(player)
					return if actors[player] then { Generation = 1, UserId = player.UserId, Player = player } else nil
				end
				local shield = Shield.new({
					Now = cf.GetClock,
					Enabled = function()
						return true
					end,
					IsPlayer = function(player)
						return actors[player] == true
					end,
					Session = session,
					OwnerReady = function(player)
						return player == f.p
					end,
					Capacity = function()
						return 1
					end,
					Cart = function(player)
						return if player == f.p then cartRecord else nil
					end,
					Player = function(userId)
						return if userId == f.p.UserId then f.p else nil
					end,
					CargoRecord = function(cart, slot)
						return Cargo:GetSlotRecord(cart, slot)
					end,
					CargoRevision = function(cart)
						return Cargo:GetCargoRevision(cart)
					end,
					OwnBase = function()
						return if ownBase then "PHASE10_SHIELD_BASE:1:1" else nil
					end,
					ProtectedArea = function()
						return false
					end,
					Feedback = function() end,
				})
				local originalPrepare = World.PrepareFreshRelease
				local originalDiscard = World.DiscardFreshRelease
				local staged, discarded = 0, 0
				f.replace(World, "PrepareFreshRelease", function(...)
					staged += 1
					return originalPrepare(...)
				end)
				f.replace(World, "DiscardFreshRelease", function(token)
					local result = originalDiscard(token)
					if result then
						discarded += 1
					end
					return result
				end)
				local ok, failure = xpcall(function()
					cf.SetClock(1998)
					shield:Start()
					shield:Reconcile(f.p)
					expect(shield:GetSnapshot(f.p).remaining).to.equal(1)
					ownBase = false
					shield:Reconcile(f.p)
					cf.SetTransactions({ Shield = shield })
					local before = World.GetPopulationSnapshot().Effective
					local safePose = World.FindSafeReleasePose
					World.FindSafeReleasePose = function()
						return nil
					end
					local unsafeOk, unsafeHandled, unsafeOutcome = pcall(
						cf.Hit,
						attacker,
						body,
						{ RequestId = 1, TargetItemId = record.ItemId, TargetCartId = "CRT_001" }
					)
					World.FindSafeReleasePose = safePose
					assert(unsafeOk, unsafeHandled)
					expect(unsafeHandled).to.equal(true)
					expect(unsafeOutcome).to.equal("UnsafeDrop")
					expect(shield:GetSnapshot(f.p).remaining).to.equal(1)
					expect(shield:GetSnapshot(f.p).protectedUntil).to.equal(0)
					expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(0)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					staged = 0
					cf.SetClock(2000)
					local handled, blocked = cf.Hit(
						attacker,
						body,
						{ RequestId = 2, TargetItemId = record.ItemId, TargetCartId = "CRT_001" }
					)
					expect(handled).to.equal(true)
					expect(blocked).to.equal("CargoShieldBlocked")
					expect(shield:GetSnapshot(f.p).remaining).to.equal(0)
					expect(shield:GetSnapshot(f.p).protectedUntil).to.equal(2005)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					expect(Cargo:GetCargoItem(f.cart, record.ItemId).ItemId).to.equal(record.ItemId)
					expect(visual.Parent).to.equal(f.cart.CargoVisuals)
					expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(0)
					expect(Combat:GetDiagnostics(f.p).DazeEnd).to.equal(0)
					expect(Combat:GetDiagnostics(attacker).Restrictions).to.equal(nil)
					expect(staged).to.equal(1)
					expect(discarded).to.equal(1)
					expect(select(2, worldIndividual(record.ItemId))).to.equal(0)
					-- Space accepted shots beyond the ordinary launcher cadence; the
					-- second Shield hit must keep the original deadline at t=5.
					cf.SetClock(2002)
					local _, protected = cf.Hit(
						attacker,
						body,
						{ RequestId = 3, TargetItemId = record.ItemId, TargetCartId = "CRT_001" }
					)
					expect(protected).to.equal("CargoShieldBlocked")
					expect(shield:GetSnapshot(f.p).remaining).to.equal(0)
					expect(shield:GetSnapshot(f.p).protectedUntil).to.equal(2005)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(0)
					expect(Combat:GetDiagnostics(attacker).Restrictions).to.equal(nil)
					expect(staged).to.equal(2)
					expect(discarded).to.equal(2)
					cf.SetClock(2005)
					local _, released = cf.Hit(
						attacker,
						body,
						{ RequestId = 4, TargetItemId = record.ItemId, TargetCartId = "CRT_001" }
					)
					expect(released).to.equal("CargoKnockedLoose")
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					expect(shield:GetSnapshot(f.p).remaining).to.equal(0)
					expect(shield:GetSnapshot(f.p).protectedUntil).to.equal(0)
					expect(staged).to.equal(3)
					expect(discarded).to.equal(2)
					expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(2010)
					expect(Combat:GetDiagnostics(attacker).Restrictions[f.p.UserId]).to.equal(2065)
					local loose, count = worldIndividual(record.ItemId)
					expect(count).to.equal(1)
					local releasedRecord, state = World.GetWorldRecord(loose)
					expect(state).to.equal("WorldAwake")
					expect(releasedRecord.ItemId).to.equal(record.ItemId)
					expect(releasedRecord.BrainrotId).to.equal(record.BrainrotId)
					expect(releasedRecord.Metadata.Mutation.Quality).to.equal(record.Metadata.Mutation.Quality)
					expect(World.GetPopulationSnapshot().Effective).to.equal(before)
				end, debug.traceback)
				shield:Stop()
				assert(ok, failure)
			end)
		end)

		it("unsafe cargo staging preserves the exact source visual, count and protection deadlines", function()
			fixture(function(f)
				local record = f.carry("BRT_007")
				f.near("Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", record.ItemId))
				f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(20, 0, 20)))
				local cf = combatFixture(f)
				local visual = f.cart.CargoVisuals:GetChildren()[1]
				local body = visual:FindFirstChild("Body", true)
				local attacker = cf.Actor(-98005, body.Position + Vector3.new(-14, 0, 0))
				local before = World.GetPopulationSnapshot().Effective
				for _, requestId in { 0, -1, 0.5, math.huge, 0 / 0 } do
					local handled, rejected = cf.Hit(
						attacker,
						body,
						{ RequestId = requestId, TargetItemId = record.ItemId, TargetCartId = "CRT_001" }
					)
					expect(handled).to.equal(true)
					expect(rejected).to.equal("StaleTarget")
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(0)
				end
				f.replace(World, "FindSafeReleasePose", function()
					return nil
				end)
				local handled, outcome =
					cf.Hit(attacker, body, { RequestId = 1, TargetItemId = record.ItemId, TargetCartId = "CRT_001" })
				expect(handled).to.equal(true)
				expect(outcome).to.equal("UnsafeDrop")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
				expect(Cargo:GetCargoItem(f.cart, record.ItemId).ItemId).to.equal(record.ItemId)
				expect(visual.Parent).to.equal(f.cart.CargoVisuals)
				expect(World.GetPopulationSnapshot().Effective).to.equal(before)
				expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(0)
				expect(Combat:GetDiagnostics(attacker).Restrictions).to.equal(nil)
				expect(select(2, worldIndividual(record.ItemId))).to.equal(0)
			end)
		end)

		it("fresh held hit commits one same-ID drop and one daze; unsafe staging preserves both", function()
			fixture(function(f)
				local record = f.carry("BRT_007")
				local cf = combatFixture(f)
				local held = f.p.Character.CarriedBrainrot
				local body = held:FindFirstChild("Body", true)
				local attacker = cf.Actor(-98002, body.Position + Vector3.new(0, 0, -14))
				local handled, outcome = cf.Hit(attacker, body, { RequestId = 1, TargetPlayerUserId = f.p.UserId })
				expect(handled).to.equal(true)
				expect(outcome).to.equal("PlayerDazed")
				expect(Interaction.IsCarrying(f.p)).to.equal(false)
				expect(Combat:GetDiagnostics(f.p).DazeEnd).to.equal(2003)
				local loose, count = worldIndividual(record.ItemId)
				expect(count).to.equal(1)
				expect(select(2, World.GetWorldRecord(loose))).to.equal("WorldAwake")
				expect(Interaction.TryPickupWorld(f.p, loose, record.ItemId)).to.equal(false)
				cf.SetClock(2003)
				expect(Combat:CanAct(f.p)).to.equal(true)
				expect(Combat:GetDiagnostics(f.p).ProtectionEnd).to.equal(2008)
				-- After expiry, invalid safe preparation does not drop or begin a new daze.
				cf.SetClock(2061)
				local nextRecord = f.carry("BRT_007")
				local nextBody = f.p.Character.CarriedBrainrot:FindFirstChild("Body", true)
				attacker.Character:PivotTo(CFrame.new(nextBody.Position + Vector3.new(0, 0, -14)))
				f.replace(World, "FindSafeReleasePose", function()
					return nil
				end)
				local _, rejected = cf.Hit(attacker, nextBody, { RequestId = 2, TargetPlayerUserId = f.p.UserId })
				expect(rejected).to.equal("UnsafeDrop")
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(nextRecord.ItemId)
				expect(Combat:IsDazed(f.p)).to.equal(false)
			end)
		end)

		it("held banked original drops secured, asleep, outside ordinary budget and remains owner-only", function()
			fixture(function(f)
				local record = f.carry("BRT_007", { DurableOwnerUserId = f.p.UserId, Mutation = { Quality = 7 } })
				local countBefore = World.GetWildCount()
				local cf = combatFixture(f)
				local body = f.p.Character.CarriedBrainrot:FindFirstChild("Body", true)
				local attacker = cf.Actor(-98003, body.Position + Vector3.new(0, 0, -14))
				local _, protected = cf.Hit(attacker, body, { RequestId = 1, TargetPlayerUserId = f.p.UserId })
				expect(protected).to.equal("ProtectedTarget")
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(record.ItemId)
				expect(Combat:IsDazed(f.p)).to.equal(false)
				local avatarRoot = f.p.Character.PrimaryPart
				attacker.Character:PivotTo(CFrame.new(avatarRoot.Position + Vector3.new(0, 0, 14)))
				local _, outcome = cf.Hit(attacker, avatarRoot, { RequestId = 2, TargetPlayerUserId = f.p.UserId })
				expect(outcome).to.equal("PlayerDazed")
				local secured, count = worldIndividual(record.ItemId)
				expect(count).to.equal(1)
				expect(World.GetWildCount()).to.equal(countBefore)
				expect(World.IsWild(record.ItemId)).to.equal(false)
				expect(select(2, World.GetWorldRecord(secured))).to.equal("WorldSleeping")
				expect(World.GetWorldRecord(secured).Metadata.DurableOwnerUserId).to.equal(f.p.UserId)
				expect(World.TrySleep(secured)).to.equal(false)
				expect(select(2, Interaction.TryPickupWorld(attacker, secured, record.ItemId))).to.equal(
					"BANKED_PROTECTED"
				)
			end)
		end)
	end)

	describe("Task C exact-slot placement access", function()
		it("unlocks one authored slot from owner entitlement without moving existing cargo", function()
			fixture(function(f)
				local originals = {
					load(f, "Slot1"),
					load(f, "Slot2"),
					load(f, "Slot3"),
				}
				local fourth = f.carry()
				f.near("Slot4")
				expect(select(2, Interaction.TryPlaceInCargo(f.p, f.cart, "Slot4", fourth.ItemId))).to.equal(
					"INVALID_SLOT"
				)
				unchangedCarry(f, fourth, 3)

				local cargoOne = table.clone(assert(Upgrades.Get("CARGO_1")))
				cargoOne.definitionStatus = "Complete"
				cargoOne.effectStatus = "Ready"
				cargoOne.releaseStatus = "Released"
				cargoOne.ownershipScope = { kind = "PlayerWide" }
				cargoOne.applicability = { kind = "AllOwnedCarts" }
				f.configureCapacity({
					OwnerStateReader = function(ownerId)
						return {
							status = "Ready",
							userId = ownerId,
							ownedOfferIds = { CARGO_1 = true },
							ownedCarts = {},
						}
					end,
					ResolverOptions = {
						offers = { cargoOne },
						cartDefinitions = { CRT_001 = { CargoCapacity = 3 } },
					},
				})
				local readiness = Cargo:ReconcileCargoCapacity(f.cart, "spec purchase")
				expect(readiness.status).to.equal("Ready")
				expect(Cargo:GetCargoCapacity(f.cart)).to.equal(4)
				expect(f.cart:GetAttribute("CargoUpgradeBonus")).to.equal(1)
				expect(f.slots.Slot4:GetAttribute("CargoSlotEnabled")).to.equal(true)
				for index, original in originals do
					expect(Cargo:GetSlotRecord(f.cart, "Slot" .. index).ItemId).to.equal(original.ItemId)
				end
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot4", fourth.ItemId))
				expect(Cargo:GetSlotRecord(f.cart, "Slot4").ItemId).to.equal(fourth.ItemId)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(4)
				local revision = Cargo:GetCargoRevision(f.cart)
				for _ = 1, 100 do
					Cargo:ReconcileCargoCapacity(f.cart, "idempotency")
				end
				expect(Cargo:GetCargoCapacity(f.cart)).to.equal(4)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)

				local fifth = f.carry()
				f.near("Slot5")
				expect(select(2, Interaction.TryPlaceInCargo(f.p, f.cart, "Slot5", fifth.ItemId))).to.equal(
					"INVALID_SLOT"
				)
				unchangedCarry(f, fifth, 4)
				assert(Interaction.TryDropCarried(f.p, fifth.ItemId))
				f.near("Slot4")
				assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot4", fourth.ItemId))
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot4", fourth.ItemId))
				expect(Cargo:GetSlotRecord(f.cart, "Slot4").ItemId).to.equal(fourth.ItemId)
				f.configureCapacity(nil)
				expect(Cargo:GetCargoCapacity(f.cart)).to.equal(3)
				expect(f.slots.Slot4:GetAttribute("CargoRemovalOnly")).to.equal(true)
				f.near("Slot4")
				assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot4", fourth.ItemId))
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
			end)
		end)

		it("batches physical cargo mounting and removal without bypassing the final validation", function()
			fixture(function(f)
				local service = require(Services.CartAssemblyValidationService)
				local validator = require(RS.Shared.Validation.CartAssemblyValidator)
				local original = validator.Validate
				local validations = 0
				f.replace(validator, "Validate", function(cart, options)
					if cart ~= f.cart then
						return original(cart, options)
					end
					validations += 1
					for _, descendant in cart:GetDescendants() do
						if descendant.Name == "CargoMount" then
							assert(
								descendant.Enabled and descendant.Part0 and descendant.Part1,
								"validated half-mounted cargo"
							)
						end
					end
					return {
						IsValid = true,
						Warnings = {},
						FatalErrors = {},
						ModelName = cart.Name,
						CartId = "SPEC",
						Stage = options.Stage,
					}
				end)
				-- Create the ordinary container before measuring the physical transaction.
				local container = Instance.new("Folder")
				container.Name, container.Parent = "CargoVisuals", f.cart
				assert(service:RegisterCart(f.cart))
				local ok, failure = xpcall(function()
					local baseline = service:GetDiagnostics()
					local record = load(f, "Slot2")
					expect(validations).to.equal(2) -- registration + one complete mount
					expect(Cargo:GetSlotRecord(f.cart, "Slot2").ItemId).to.equal(record.ItemId)
					local token = assert(Cargo:DetachForTransfer(f.cart, record.ItemId))
					assert(Cargo:FinalizeTransfer(f.cart, token))
					expect(validations).to.equal(3)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					expect(service:GetDiagnostics().RetainedObservedInstanceCount).to.equal(
						baseline.RetainedObservedInstanceCount
					)
				end, debug.traceback)
				service:ForgetCart(f.cart, "test cleanup")
				assert(ok, failure)
			end)
		end)
		it("loads a deterministic mixed-species set into the selected physical slots", function()
			fixture(function(f)
				local expected = {
					{ "Slot3", "BRT_007" },
					{ "Slot1", "BRT_011" },
					{ "Slot2", "BRT_015" },
				}
				local ids = {}
				for _, row in expected do
					local record = f.carry(row[2])
					f.near(row[1])
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, row[1], record.ItemId))
					local stored = assert(Cargo:GetSlotRecord(f.cart, row[1]))
					expect(stored.ItemId).to.equal(record.ItemId)
					expect(stored.BrainrotId).to.equal(row[2])
					expect(ids[stored.ItemId]).to.equal(nil)
					ids[stored.ItemId] = true
				end
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
				expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
				for _, visual in f.cart.CargoVisuals:GetChildren() do
					expect(ids[visual:GetAttribute("ItemId")]).to.equal(true)
					expect(visual:GetAttribute("BrainrotId") ~= nil).to.equal(true)
				end
			end)
		end)

		for _, distance in { 13.9, 14, 16 } do
			it("loads through its own rail at slot distance " .. distance, function()
				fixture(function(f)
					local r = f.carry()
					local position = f.slots.Slot2.CargoAttachment.WorldPosition
					f.p.Character:PivotTo(CFrame.new(position + Vector3.new(0, 0, distance)))
					f.part(f.cart, "OwnRail", position + Vector3.new(0, 1, 2), Vector3.new(12, 8, 1))
					local ok, reason = Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId)
					assert(ok, reason)
					expect(Cargo:GetSlotRecord(f.cart, "Slot2").ItemId).to.equal(r.ItemId)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
					expect(Interaction.IsCarrying(f.p)).to.equal(false)
				end)
			end)
		end
		it("rejects outside 16 studs and real external walls without losing carry", function()
			fixture(function(f)
				local r = f.carry()
				local point = f.slots.Slot1.CargoAttachment.WorldPosition
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 16.2)))
				expect(select(2, Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))).to.equal("OUT_OF_REACH")
				unchangedCarry(f, r)
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 14)))
				local wall = f.part(f.root, "ExternalWall", point + Vector3.new(0, 1, 10), Vector3.new(20, 20, 1))
				expect(select(2, Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))).to.equal("OBSTRUCTED")
				unchangedCarry(f, r)
				wall:Destroy()
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))
			end)
		end)
		it("pickup and deliberate replacement use the same reach and preserve released identity", function()
			fixture(function(f)
				local old = load(f, "Slot3")
				local point = f.slots.Slot3.CargoAttachment.WorldPosition
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 16.2)))
				expect(select(2, Interaction.TryPickupCargo(f.p, f.cart, "Slot3", old.ItemId))).to.equal("OUT_OF_REACH")
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 14)))
				assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", old.ItemId))
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(old.ItemId)
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot3", old.ItemId))
				fillOtherSlots(f, "Slot3")
				local incoming = f.carry()
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 16.2)))
				expect(select(2, Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", old.ItemId, incoming.ItemId))).to.equal(
					"OUT_OF_REACH"
				)
				unchangedCarry(f, incoming, 3)
				task.wait(0.65)
				f.p.Character:PivotTo(CFrame.new(point + Vector3.new(0, 0, 14)))
				local ok, reason = Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", old.ItemId, incoming.ItemId)
				assert(ok, reason)
				expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(incoming.ItemId)
				expect(select(2, World.GetWorldRecord(worldIndividual(old.ItemId)))).to.equal("WorldAwake")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
			end)
		end)
	end)

	describe("Unbanked cart-removal restoration", function()
		it("cancels an unfinished fixture-owned return before the next fixture", function()
			local pendingId
			fixture(function(f)
				local record = load(f, "Slot2")
				pendingId = record.ItemId
				f.replace(World, "PrepareWorldRepresentation", function()
					return nil, "FIXTURE_UNAVAILABLE"
				end)
				Cargo:PrepareCartRemoval(f.cart)
				f.cart:Destroy()
				Cargo:ProcessPendingReturns()
				expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, record.ItemId) ~= nil).to.equal(true)
			end)
			expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, pendingId)).to.equal(nil)
			Cargo:ProcessPendingReturns()
			expect(select(2, worldIndividual(pendingId))).to.equal(0)
		end)

		it("legacy secured cargo needs no new sleep flag and retains its ID through pickup and Drop", function()
			local releasedItemId
			fixture(function(f)
				local record = f.ownRecord(assert(Cargo:AddCargo(f.cart, f.template.Name, { Tier = 2 })))
				releasedItemId = record.ItemId
				f.near("Slot1")
				assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", record.ItemId))
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(record.ItemId)
				assert(Interaction.TryDropCarried(f.p, record.ItemId))
				local model, count = worldIndividual(record.ItemId)
				expect(count).to.equal(1)
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
				expect(World.GetWorldRecord(model).Metadata.Tier).to.equal(2)
			end)
			expect(select(2, worldIndividual(releasedItemId))).to.equal(0)
			expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, releasedItemId)).to.equal(nil)
		end)
		it(
			"records all three individuals before deletion, restores distinct awake models and does not repeat cleanup",
			function()
				fixture(function(f)
					local records = { load(f, "Slot3"), load(f, "Slot1"), load(f, "Slot2") }
					local cartPose = f.cart:GetPivot()
					Roaming.Start()
					Cargo:PrepareCartRemoval(f.cart)
					expect(#Cargo:GetRemovalDiagnostics().PendingIds >= 3).to.equal(true)
					f.cart:Destroy()
					Cargo:PrepareCartRemoval(f.cart)
					Cargo:ProcessPendingReturns()
					local models = {}
					for _, record in records do
						local model, count = worldIndividual(record.ItemId)
						expect(count).to.equal(1)
						expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
						expect(World.GetWorldRecord(model).Metadata.Mutation.Quality).to.equal(7)
						expect((model:GetPivot().Position - cartPose.Position).Magnitude < 32).to.equal(true)
						expect(model.Body.CanQuery).to.equal(true)
						expect(model:FindFirstChild("CargoMount", true)).to.equal(nil)
						for _, previous in models do
							expect((previous:GetPivot().Position - model:GetPivot().Position).Magnitude > 3).to.equal(
								true
							)
						end
						table.insert(models, model)
						print("[PHASE10_ID] cart-to-world " .. record.ItemId)
					end
					task.wait(4.2) -- Beyond the obsolete two-second disappearance proposal.
					Cargo:ProcessPendingReturns()
					for _, record in records do
						local model, count = worldIndividual(record.ItemId)
						expect(count).to.equal(1)
						assert(World.TrySleep(model), "Restored cargo must remain recapturable")
					end
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					expect(Interaction.IsCarrying(f.p)).to.equal(false)
				end)
			end
		)

		it("handles direct model destruction at the last moving-cart pose, not the original spawn", function()
			fixture(function(f)
				local record = load(f, "Slot1")
				f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(65, 0, 0))
				task.wait(0.35) -- Shared pose tracker, not a per-cart polling task.
				local pose = f.cart:GetPivot()
				f.cart:Destroy()
				task.wait(0.35)
				Cargo:ProcessPendingReturns()
				local model, count = worldIndividual(record.ItemId)
				expect(count).to.equal(1)
				expect((model:GetPivot().Position - pose.Position).Magnitude < 32).to.equal(true)
			end)
		end)

		for _, fault in { "ground", "factory" } do
			it("retains removed-cart records while " .. fault .. " is unavailable, then restores once", function()
				fixture(function(f)
					local record = load(f, "Slot2")
					local factory = World.PrepareWorldRepresentation
					if fault == "ground" then
						f.replace(f.root.Ground, "CanCollide", false)
						f.replace(f.root.Ground, "CanQuery", false)
					else
						f.replace(World, "PrepareWorldRepresentation", function()
							return nil, "FIXTURE_UNAVAILABLE"
						end)
					end
					Cargo:PrepareCartRemoval(f.cart)
					f.cart:Destroy()
					Cargo:ProcessPendingReturns()
					expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, record.ItemId) ~= nil).to.equal(true)
					expect(select(2, worldIndividual(record.ItemId))).to.equal(0)
					World.PrepareWorldRepresentation = factory
					f.root.Ground.CanCollide, f.root.Ground.CanQuery = true, true
					task.wait(1.15)
					Cargo:ProcessPendingReturns()
					expect(select(2, worldIndividual(record.ItemId))).to.equal(1)
					expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, record.ItemId)).to.equal(nil)
				end)
			end)
		end

		it("does not also release an individual already moved to carry", function()
			fixture(function(f)
				local a, b = load(f, "Slot3"), load(f, "Slot1")
				f.near("Slot3")
				assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", a.ItemId))
				Cargo:PrepareCartRemoval(f.cart)
				f.cart:Destroy()
				Cargo:ProcessPendingReturns()
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(a.ItemId)
				expect(select(2, worldIndividual(a.ItemId))).to.equal(0)
				expect(select(2, worldIndividual(b.ItemId))).to.equal(1)
			end)
		end)

		it("invalidates yielding load staging when the cart is removed without consuming the incoming carry", function()
			fixture(function(f)
				local a, b = load(f, "Slot1"), f.carry()
				f.near("Slot2")
				local factory = Cargo.CreateItemVisual
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory
					task.wait()
					Cargo:PrepareCartRemoval(f.cart)
					f.cart:Destroy()
					return factory(self, id)
				end)
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", b.ItemId)).to.equal(false)
				Cargo:ProcessPendingReturns()
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(b.ItemId)
				expect(select(2, worldIndividual(a.ItemId))).to.equal(1)
			end)
		end)
	end)

	describe("Occupied cargo replacement", function()
		it("rejects premature replacement and keeps the third carried individual intact", function()
			fixture(function(f)
				local a = load(f, "Slot1")
				load(f, "Slot2")
				local c = f.carry()
				f.near("Slot1")
				local ok, reason = Interaction.TryReplaceCargo(f.p, f.cart, "Slot1", a.ItemId, c.ItemId)
				expect(ok).to.equal(false)
				expect(reason).to.equal("EMPTY_SLOT_AVAILABLE")
				unchangedCarry(f, c, 2)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(a.ItemId)
				expect(Cargo:GetSlotRecord(f.cart, "Slot3")).to.equal(nil)
				f.near("Slot3")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot3", c.ItemId))
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
				expect(f.cart:GetAttribute("CargoRevision")).to.equal(3)
			end)
		end)
		it("rechecks the complete slot map after staging before releasing either source", function()
			fixture(function(f)
				local a = load(f, "Slot1")
				fillOtherSlots(f, "Slot1")
				local c = f.carry()
				f.near("Slot1")
				local factory = Cargo.CreateItemVisual
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory
					-- Asset-invalidated fixture; logical records remain untouched.
					f.slots.Slot3.CargoAttachment:Destroy()
					return factory(self, id)
				end)
				local ok = Interaction.TryReplaceCargo(f.p, f.cart, "Slot1", a.ItemId, c.ItemId)
				expect(ok).to.equal(false)
				unchangedCarry(f, c, 3)
				expect(select(2, worldIndividual(a.ItemId))).to.equal(0)
			end)
		end)
		it(
			"replaces one exact full-cart slot, preserving same-species IDs and publishing consistent ownership",
			function()
				fixture(function(f)
					local a = load(f, "Slot3")
					local one, two = load(f, "Slot1"), load(f, "Slot2")
					local b = f.carry()
					f.near("Slot3")
					expect(a.BrainrotId).to.equal(b.BrainrotId)
					expect(a.ItemId == b.ItemId).to.equal(false)
					local observed, consistent = 0, false
					local connection = World.WorldChanged:Connect(function(model)
						local r = World.GetWorldRecord(model)
						if r and r.ItemId == a.ItemId then
							observed += 1
							consistent = not Interaction.IsCarrying(f.p)
								and Cargo:GetSlotRecord(f.cart, "Slot3").ItemId == b.ItemId
								and Cargo:GetCargoCount(f.cart) == 3
								and Cargo:GetCargoRevision(f.cart) == 4
						end
					end)
					local ok, reason = Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", a.ItemId, b.ItemId)
					task.wait()
					connection:Disconnect()
					assert(ok, reason)
					expect(observed).to.equal(1)
					expect(consistent).to.equal(true)
					local released, count = worldIndividual(a.ItemId)
					expect(count).to.equal(1)
					expect(select(2, World.GetWorldRecord(released))).to.equal("WorldAwake")
					expect(World.GetWorldRecord(released).Metadata.Mutation.Quality).to.equal(7)
					expect(math.abs(released:GetScale() - a.World.Scale) < 0.0001).to.equal(true)
					expect(select(2, worldIndividual(b.ItemId))).to.equal(0)
					expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(one.ItemId)
					expect(Cargo:GetSlotRecord(f.cart, "Slot2").ItemId).to.equal(two.ItemId)
					expect(f.cart:GetAttribute("CargoCount")).to.equal(3)
					expect(f.slots.Slot3:GetAttribute("CargoItemId")).to.equal(b.ItemId)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
					expect(f.p:GetAttribute("CarriedItemId")).to.equal(nil)
					expect(f.p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
					expect(Occupants:CanEnterDriver(f.p)).to.equal(true)
					expect(Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", a.ItemId, b.ItemId)).to.equal(false)
					expect(select(2, worldIndividual(a.ItemId))).to.equal(1)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(4)
				end)
			end
		)

		for _, failure in { "cargo factory", "world factory", "registration", "no ground", "activation" } do
			it("preserves both sources on " .. failure .. " failure", function()
				fixture(function(f)
					local a = load(f, "Slot2")
					fillOtherSlots(f, "Slot2")
					local b = f.carry()
					f.near("Slot2")
					local oldVisual = f.cart.CargoVisuals:GetChildren()[1]
					if failure == "cargo factory" then
						f.replace(Cargo, "CreateItemVisual", function()
							return nil
						end)
					elseif failure == "world factory" then
						f.replace(World, "PrepareWorldRepresentation", function()
							return nil, "FIXTURE_FAILURE"
						end)
					elseif failure == "registration" then
						f.replace(Roaming, "Register", function()
							return false
						end)
					elseif failure == "activation" then
						f.replace(World, "ActivatePreparedWorld", function()
							return nil, "FIXTURE_FAILURE"
						end)
					else
						f.replace(f.root.Ground, "CanCollide", false)
						f.replace(f.root.Ground, "CanQuery", false)
					end
					local ok, reason = Interaction.TryReplaceCargo(f.p, f.cart, "Slot2", a.ItemId, b.ItemId)
					expect(ok).to.equal(false)
					if failure == "no ground" then
						expect(reason).to.equal("NO_SAFE_POSE")
					end
					unchangedCarry(f, b, 3)
					expect(Cargo:GetSlotRecord(f.cart, "Slot2").ItemId).to.equal(a.ItemId)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
					expect(oldVisual.Parent).to.equal(f.cart.CargoVisuals)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
					expect(select(2, worldIndividual(a.ItemId))).to.equal(0)
					expect(f.cart.Parent).to.equal(f.root)
				end)
			end)
		end

		for _, change in { "stale old", "stale carry", "slot", "reach", "owner", "current cart", "driver" } do
			it("rejects " .. change .. " without changing either individual", function()
				fixture(function(f)
					local a = load(f, "Slot3")
					fillOtherSlots(f, "Slot3")
					local b = f.carry()
					f.near("Slot3")
					local oldId, carriedId, slot = a.ItemId, b.ItemId, "Slot3"
					if change == "stale old" then
						oldId = "stale"
					elseif change == "stale carry" then
						carriedId = "stale"
					elseif change == "slot" then
						slot = "Slot4"
					elseif change == "reach" then
						f.p.Character:PivotTo(CFrame.new(f.origin))
					elseif change == "owner" then
						f.cart:SetAttribute("OwnerUserId", 1234)
					elseif change == "current cart" then
						f.current.Model = nil
					else
						f.role.Driving = true
					end
					expect(Interaction.TryReplaceCargo(f.p, f.cart, slot, oldId, carriedId)).to.equal(false)
					unchangedCarry(f, b, 3)
					expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(a.ItemId)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
				end)
			end)
		end

		it("uses the cart's moved pose after yielding preparation and rejects overlapping/repeated requests", function()
			fixture(function(f)
				local a = load(f, "Slot2")
				fillOtherSlots(f, "Slot2")
				local b = f.carry()
				f.near("Slot2")
				local factory, loser = Cargo.CreateItemVisual, nil
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory
					task.wait()
					loser = table.pack(Interaction.TryReplaceCargo(f.p, f.cart, "Slot2", a.ItemId, b.ItemId))
					f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(70, 0, 0))
					f.near("Slot2")
					return factory(self, id)
				end)
				local ok, reason = Interaction.TryReplaceCargo(f.p, f.cart, "Slot2", a.ItemId, b.ItemId)
				assert(ok, reason)
				expect(loser[1]).to.equal(false)
				expect(loser[2]).to.equal("RATE_LIMITED")
				local released = assert(worldIndividual(a.ItemId))
				expect((released:GetPivot().Position - f.cart:GetPivot().Position).Magnitude < 32).to.equal(true)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(4)
			end)
		end)

		for _, change in { "reach", "driver", "cart moved during activation" } do
			it("rechecks " .. change .. " after staging", function()
				fixture(function(f)
					local a = load(f, "Slot1")
					fillOtherSlots(f, "Slot1")
					local b = f.carry()
					f.near("Slot1")
					local key = if change == "cart moved during activation"
						then "ActivatePreparedWorld"
						else "PrepareWorldRepresentation"
					local original = World[key]
					f.replace(World, key, function(...)
						task.wait()
						if change == "reach" then
							f.p.Character:PivotTo(CFrame.new(f.origin))
						elseif change == "driver" then
							f.role.Driving = true
						else
							f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(50, 0, 0))
							f.near("Slot1")
						end
						return original(...)
					end)
					expect(Interaction.TryReplaceCargo(f.p, f.cart, "Slot1", a.ItemId, b.ItemId)).to.equal(false)
					unchangedCarry(f, b, 3)
					expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(a.ItemId)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
					expect(select(2, worldIndividual(a.ItemId))).to.equal(0)
				end)
			end)
		end

		it(
			"repairs committed cargo presentation without replaying replacement or deleting the released individual",
			function()
				fixture(function(f)
					local a = load(f, "Slot3")
					fillOtherSlots(f, "Slot3")
					local b = f.carry()
					f.near("Slot3")
					local activation = World.ActivatePreparedWorld
					local released
					f.replace(World, "ActivatePreparedWorld", function(...)
						released = assert(activation(...))
						-- Fault fixture: fail notification after logical commit and lose the new display.
						for _, visual in f.cart.CargoVisuals:GetChildren() do
							if visual:GetAttribute("ItemId") == b.ItemId then
								visual:Destroy()
							end
						end
						error("Injected post-commit presentation failure")
					end)
					assert(Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", a.ItemId, b.ItemId))
					expect(World.GetWorldRecord(released).ItemId).to.equal(a.ItemId)
					expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(b.ItemId)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(4)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
					expect(Interaction.IsCarrying(f.p)).to.equal(false)
				end)
			end
		)

		it("keeps the chassis unchanged and only welds unanchored massless incoming cargo", function()
			fixture(function(f)
				local a = load(f, "Slot3")
				fillOtherSlots(f, "Slot3")
				local b = f.carry()
				f.near("Slot3")
				f.chassis.Anchored = false
				local frame, mass, priority = f.chassis.CFrame, f.chassis.AssemblyMass, f.chassis.RootPriority
				assert(Interaction.TryReplaceCargo(f.p, f.cart, "Slot3", a.ItemId, b.ItemId))
				for _, item in f.cart.CargoVisuals:GetDescendants() do
					if item:IsA("BasePart") then
						expect(item.Anchored).to.equal(false)
						expect(item.Massless).to.equal(true)
						expect(item.CanCollide or item.CanTouch).to.equal(false)
					elseif item:IsA("WeldConstraint") then
						expect(item.Part0:IsDescendantOf(f.cart)).to.equal(true)
						expect(item.Part1:IsDescendantOf(f.cart.CargoVisuals)).to.equal(true)
					end
				end
				expect(f.cart.Parent).to.equal(f.root)
				expect(f.chassis.Anchored).to.equal(false)
				expect(f.chassis.CFrame:FuzzyEq(frame, 0.001)).to.equal(true)
				expect(f.chassis.RootPriority).to.equal(priority)
				expect(math.abs(f.chassis.AssemblyMass - mass) < 0.001).to.equal(true)
				f.chassis.Anchored = true
			end)
		end)
	end)

	describe("Manual exact-slot cargo pickup", function()
		it("rejects a slot replacement made while preparation yielded without removing the replacement", function()
			fixture(function(f)
				local original = load(f, "Slot3")
				local factory = Cargo.CreateItemVisual
				local replacement
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory
					task.wait()
					assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", original.ItemId))
					f.near("Slot1")
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", original.ItemId))
					replacement = load(f, "Slot3")
					return factory(self, id)
				end)
				expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", original.ItemId)).to.equal(false)
				expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(replacement.ItemId)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(original.ItemId)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(4)
				expect(f.cart:GetAttribute("CargoCount")).to.equal(2)
				expect(#f.cart.CargoVisuals:GetChildren()).to.equal(2)
				expect(f.p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
				expect(f.cart.Parent).to.equal(f.root)
			end)
		end)

		it("cycles cargo/carry three times without count drift, dropped fields or weld buildup", function()
			fixture(function(f)
				local r = load(f, "Slot3")
				local factory = World.ActivatePreparedWorld
				local activations = 0
				f.replace(World, "ActivatePreparedWorld", function(...)
					activations += 1
					return factory(...)
				end)
				local chassisFrame = f.chassis.CFrame
				for n = 1, 3 do
					local slotId = if n == 1 then "Slot3" else "Slot2"
					f.near(slotId)
					local source = Cargo:GetSlotRecord(f.cart, slotId)
					expect(math.abs(f.cart.CargoVisuals:GetChildren()[1]:GetScale() - r.World.Scale) < 0.0001).to.equal(
						true
					)
					expect(source.World.Name).to.equal(r.World.Name)
					expect(source.World.Scale).to.equal(r.World.Scale)
					expect(source.World.SpawnPosition.X).to.equal(r.World.SpawnPosition.X)
					local snapshot = Cargo:GetCargoSnapshot(f.cart)[1]
					snapshot.World.Scale = 99
					expect(source.World.Scale).to.equal(r.World.Scale)
					assert(Interaction.TryPickupCargo(f.p, f.cart, slotId, r.ItemId))
					expect(Interaction.GetCarriedRecord(f.p)).to.equal(source)
					expect(Cargo:GetSlotRecord(f.cart, slotId)).to.equal(nil)
					expect(f.slots[slotId]:GetAttribute("CargoItemId")).to.equal(nil)
					expect(f.cart:GetAttribute("CargoCount")).to.equal(0)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(0)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(n * 2)
					expect(Occupants:CanEnterDriver(f.p)).to.equal(false)
					expect(select(2, fireAt(f.p, f.origin))).to.equal("carrying")
					expect(Interaction.GetDiagnostics().CarryConnections).to.equal(4)
					local parts, welds = 0, 0
					for _, child in f.p.Character.CarriedBrainrot:GetDescendants() do
						if child:IsA("BasePart") then
							parts += 1
						end
						if child:IsA("WeldConstraint") then
							welds += 1
							expect(child.Part0:IsDescendantOf(f.cart)).to.equal(false)
						end
					end
					expect(welds).to.equal(parts)
					f.near("Slot2")
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId))
					expect(f.cart:GetAttribute("CargoCount")).to.equal(1)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(n * 2 + 1)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(1)
					expect(Interaction.GetDiagnostics().CarryConnections).to.equal(0)
					expect(Occupants:CanEnterDriver(f.p)).to.equal(true)
				end
				expect(activations).to.equal(0)
				expect(f.chassis.CFrame:FuzzyEq(chassisFrame, 0.001)).to.equal(true)
				expect(f.cart.Parent).to.equal(f.root)
			end)
		end)

		it(
			"Drop after cargo restores an awake moving individual that can be shot and picked up with the same ID",
			function()
				fixture(function(f)
					local r = load(f, "Slot2")
					assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot2", r.ItemId))
					f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 30)))
					Roaming.Start()
					local before = Roaming.GetDiagnostics().Registered
					assert(Interaction.TryDropCarried(f.p, r.ItemId))
					local restored
					for _, m in World.GetWorldModels() do
						if World.GetWorldRecord(m).ItemId == r.ItemId then
							restored = m
						end
					end
					assert(restored, "Dropped cargo individual was not restored to the world")
					expect(select(2, World.GetWorldRecord(restored))).to.equal("WorldAwake")
					expect(Roaming.GetDiagnostics().Registered).to.equal(before + 1)
					local pose = restored:GetPivot().Position
					local deadline = os.clock() + 4
					repeat
						task.wait(0.05)
					until (restored:GetPivot().Position - pose).Magnitude > 0.1 or os.clock() >= deadline
					expect((restored:GetPivot().Position - pose).Magnitude > 0.1).to.equal(true)
					f.p.Character:PivotTo(CFrame.new(restored:GetPivot().Position + Vector3.new(0, 0, 5)))
					local tool = Instance.new("Tool")
					tool.Name = "SleepLauncher"
					tool:SetAttribute("BrainrotSleepLauncher", true)
					local handle = f.part(tool, "Handle", f.p.Character.PrimaryPart.Position)
					local muzzle = Instance.new("Attachment")
					muzzle.Name, muzzle.Parent = "Muzzle", handle
					tool.Parent = f.p.Character
					assert(fireAt(f.p, restored.Body.Position))
					expect(select(2, World.GetWorldRecord(restored))).to.equal("WorldSleeping")
					assert(Interaction.TryPickupWorld(f.p, restored, r.ItemId))
					local carried = Interaction.GetCarriedRecord(f.p)
					expect(carried.ItemId).to.equal(r.ItemId)
					expect(carried.Metadata.Mutation.Quality).to.equal(7)
					expect(carried.World.Scale).to.equal(r.World.Scale)
					expect(carried.World.SpawnPosition.Z).to.equal(r.World.SpawnPosition.Z)
				end)
			end
		)

		it(
			"rejects driver, distant, blocked, stale, foreign and already-carrying pickup without altering cargo",
			function()
				fixture(function(f)
					local r = load(f, "Slot1")
					local visual = f.cart.CargoVisuals:GetChildren()[1]
					f.role.Driving = true
					expect(select(2, Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId))).to.equal("DRIVING")
					f.role.Driving = false
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", "old-id")).to.equal(false)
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot2", r.ItemId)).to.equal(false)
					expect(Interaction.TryPickupCargo(f.p, visual, "Slot1", r.ItemId)).to.equal(false)
					f.current.Model = nil
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
					f.current.Model = f.cart
					f.p.Character:PivotTo(CFrame.new(f.origin))
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
					f.near("Slot1")
					local wall =
						f.part(f.root, "Wall", f.slots.Slot1.Position + Vector3.new(0, 1, 2.5), Vector3.new(12, 8, 1))
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
					wall:Destroy()
					local carried = f.carry()
					f.near("Slot1")
					expect(select(2, Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId))).to.equal(
						"ALREADY_CARRYING"
					)
					unchangedCarry(f, carried, 1)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
					expect(visual.Parent).to.equal(f.cart.CargoVisuals)
				end)
			end
		)

		for _, fault in { "visual", "restoration", "attachment" } do
			it("keeps the source and its display when preparation fails: " .. fault, function()
				fixture(function(f)
					local r = load(f, "Slot3")
					if fault == "visual" then
						f.replace(Cargo, "CreateItemVisual", function()
							return nil
						end)
					elseif fault == "restoration" then
						f.replace(World, "PrepareWorldRepresentation", function()
							return nil
						end)
					else
						f.replace(f.p, "CharacterRemoving", {
							Connect = function()
								error("Injected attachment setup failure")
							end,
						})
					end
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", r.ItemId)).to.equal(false)
					expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(r.ItemId)
					expect(f.cart:GetAttribute("CargoCount")).to.equal(1)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(1)
					expect(Interaction.IsCarrying(f.p)).to.equal(false)
					expect(f.p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
				end)
			end)
		end

		for _, change in { "driver", "character", "owner", "distance", "attachment" } do
			it("rechecks after yielding pickup preparation: " .. change, function()
				fixture(function(f)
					local r = load(f, "Slot1")
					local factory = Cargo.CreateItemVisual
					f.replace(Cargo, "CreateItemVisual", function(self, id)
						task.wait()
						if change == "driver" then
							f.role.Driving = true
						elseif change == "character" then
							f.p.Character = nil
						elseif change == "owner" then
							f.current.Model = nil
						elseif change == "distance" then
							f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(50, 0, 0))
						else
							local a = f.slots.Slot1.CargoAttachment
							local new = a:Clone()
							a:Destroy()
							new.Parent = f.slots.Slot1
						end
						return factory(self, id)
					end)
					expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
					expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(r.ItemId)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(1)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(1)
					expect(Interaction.IsCarrying(f.p)).to.equal(false)
				end)
			end)
		end

		it("interleaved pickup has one winner and a stale request cannot remove a replacement", function()
			fixture(function(f)
				local r = load(f, "Slot3")
				local factory = Cargo.CreateItemVisual
				local winner
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory -- Allow one competing request to finish.
					task.wait()
					winner = Interaction.TryPickupCargo(f.p, f.cart, "Slot3", r.ItemId)
					return factory(self, id)
				end)
				expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", r.ItemId)).to.equal(false)
				expect(winner).to.equal(true)
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(r.ItemId)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(2)
				f.near("Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))
				local replacement = load(f, "Slot3")
				expect(Interaction.TryPickupCargo(f.p, f.cart, "Slot3", r.ItemId)).to.equal(false)
				expect(Cargo:GetSlotRecord(f.cart, "Slot3").ItemId).to.equal(replacement.ItemId)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(2)
				expect(#f.cart.CargoVisuals:GetChildren()).to.equal(2)
				expect(f.cart.Parent).to.equal(f.root)
			end)
		end)
	end)

	describe("Manual exact-slot cargo loading", function()
		it("publishes count once after source retirement without world return or income callbacks", function()
			fixture(function(f)
				local r = f.carry()
				f.near("Slot2")
				local cash, income, returns, notifications = 0, 0, 0, 0
				f.replace(Currency, "AddCash", function()
					cash += 1
				end)
				f.replace(Income, "ApplyCommittedSnapshot", function()
					income += 1
				end)
				local activate = World.ActivatePreparedWorld
				f.replace(World, "ActivatePreparedWorld", function(...)
					returns += 1
					return activate(...)
				end)
				local sourceWasEmpty, countWasCorrect = false, false
				local observed = f.cart:GetAttributeChangedSignal("CargoCount"):Connect(function()
					notifications += 1
					sourceWasEmpty = not Interaction.IsCarrying(f.p)
					countWasCorrect = Cargo:GetSlotRecord(f.cart, "Slot2").ItemId == r.ItemId
						and f.cart:GetAttribute("CargoCount") == Cargo:GetCargoCount(f.cart)
				end)
				local ok, reason = Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId)
				task.wait() -- Also flush deferred attribute signals in Studio's execution mode.
				observed:Disconnect()
				assert(ok, reason)
				expect(sourceWasEmpty and countWasCorrect).to.equal(true)
				expect(notifications).to.equal(1)
				expect(cash + income + returns).to.equal(0)
			end)
		end)

		it(
			"loads 3 then 1 then 2 with original IDs, metadata, one revision per load and no duplicate visuals",
			function()
				fixture(function(f)
					local originals = {}
					for count, index in { 3, 1, 2 } do
						local id = "Slot" .. index
						local r = load(f, id)
						originals[id] = r
						local entry = assert(Cargo:GetSlotRecord(f.cart, id))
						expect(entry.ItemId).to.equal(r.ItemId)
						expect(entry.AttachmentIndex).to.equal(index)
						expect(entry.Metadata.Mutation.Quality).to.equal(7)
						expect(Cargo:GetCargoCount(f.cart)).to.equal(count)
						expect(f.cart:GetAttribute("CargoCount")).to.equal(count)
						expect(Cargo:GetCargoRevision(f.cart)).to.equal(count)
						expect(#f.cart.CargoVisuals:GetChildren()).to.equal(count)
						expect(Interaction.IsCarrying(f.p)).to.equal(false)
						expect(Occupants:CanEnterDriver(f.p)).to.equal(true)
						expect(f.p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
						local visual = f.cart.CargoVisuals["CargoVisual_" .. index .. "_" .. r.BrainrotId]
						expect(visual:GetPivot():FuzzyEq(f.slots[id].CargoAttachment.WorldCFrame, 0.001)).to.equal(true)
						expect(World.GetWorldRecord(visual)).to.equal(nil)
						expect(Collection:HasTag(f.slots[id], "BrainrotCargoSlot")).to.equal(true)
					end
					expect(Cargo:CanAcceptCargo(f.cart)).to.equal(false)
					local token = assert(Cargo:DetachForTransfer(f.cart, originals.Slot1.ItemId))
					assert(Cargo:FinalizeTransfer(f.cart, token))
					expect(Cargo:GetSlotRecord(f.cart, "Slot1")).to.equal(nil)
					for _, i in { 3, 2 } do
						local entry = Cargo:GetSlotRecord(f.cart, "Slot" .. i)
						expect(entry.ItemId).to.equal(originals["Slot" .. i].ItemId)
						expect(entry.AttachmentIndex).to.equal(i)
					end
					load(f, "Slot1")
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
				end)
			end
		)

		it("rejects occupied/full, invalid and stale requests without consuming carry", function()
			fixture(function(f)
				for _, id in { "Slot3", "Slot1", "Slot2" } do
					load(f, id)
				end
				local r = f.carry()
				f.near("Slot2")
				for _, id in { "Slot2", "Slot4", "Root", "Slot01", "Slot0", 2 } do
					expect(Interaction.TryPlaceInCargo(f.p, f.cart, id, r.ItemId)).to.equal(false)
					unchangedCarry(f, r, 3)
				end
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", "stale")).to.equal(false)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
				expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
			end)
		end)

		it("validates actual slot reach and obstruction, not nearby chassis or client metadata", function()
			fixture(function(f)
				local r = f.carry()
				f.p.Character:PivotTo(CFrame.new(f.chassis.Position + Vector3.new(0, 2, -7)))
				local slotPose = f.slots.Slot1.CFrame
				f.slots.Slot1.CFrame += Vector3.new(0, 0, 40) -- Still near chassis, beyond actual slot reach.
				expect(select(2, Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))).to.equal("OUT_OF_REACH")
				unchangedCarry(f, r)
				f.slots.Slot1.CFrame = slotPose
				f.near("Slot1")
				local wall =
					f.part(f.root, "Wall", f.slots.Slot1.Position + Vector3.new(0, 1, 2.5), Vector3.new(12, 8, 1))
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
				wall:Destroy()
				f.current.Model = nil
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
				f.current.Model = f.cart
				f.cart:SetAttribute("OwnerUserId", 12345)
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
				f.cart:SetAttribute("OwnerUserId", f.p.UserId)
				local a = f.slots.Slot1.CargoAttachment
				a.Parent = nil
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
				a.Parent = f.slots.Slot1
				unchangedCarry(f, r)
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))
			end)
		end)

		it("failed staging leaves carry and unlocks the target for a retry", function()
			fixture(function(f)
				local r = f.carry()
				f.near("Slot1")
				local factory = Cargo.CreateItemVisual
				f.replace(Cargo, "CreateItemVisual", function()
					return nil
				end)
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
				unchangedCarry(f, r)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(0)
				Cargo.CreateItemVisual = factory
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))
			end)
		end)

		for _, change in { "moved away", "attachment replaced", "ownership changed", "died" } do
			it("revalidates after yielding staging: " .. change, function()
				fixture(function(f)
					local r = f.carry()
					f.near("Slot1")
					local factory = Cargo.CreateItemVisual
					f.replace(Cargo, "CreateItemVisual", function(self, id)
						task.wait()
						if change == "moved away" then
							f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(100, 0, 0))
						elseif change == "attachment replaced" then
							local old = f.slots.Slot1.CargoAttachment
							local replacement = old:Clone()
							old:Destroy()
							replacement.Parent = f.slots.Slot1
						elseif change == "ownership changed" then
							f.current.Model = nil
						else
							f.p.Character.Humanoid.Health = 0
						end
						return factory(self, id)
					end)
					expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId)).to.equal(false)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(0)
					expect(#f.cart.CargoVisuals:GetChildren()).to.equal(0)
					if change ~= "died" then
						unchangedCarry(f, r)
					end
				end)
			end)
		end

		it("one overlapping request wins the final slot and uses the current moving attachment", function()
			fixture(function(f)
				load(f, "Slot1")
				load(f, "Slot3")
				local r = f.carry()
				f.near("Slot2")
				local factory = Cargo.CreateItemVisual
				local loser
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					task.wait()
					expect(select(2, Cargo:CanInsertAtSlot(f.cart, "Slot2", r))).to.equal("BUSY")
					loser = table.pack(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId))
					f.cart:PivotTo(f.cart:GetPivot() + Vector3.new(1, 0, 0))
					return factory(self, id)
				end)
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId))
				expect(loser[1]).to.equal(false)
				expect(loser[2]).to.equal("BUSY")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(3)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
				expect(#f.cart.CargoVisuals:GetChildren()).to.equal(3)
				local v = f.cart.CargoVisuals["CargoVisual_2_" .. r.BrainrotId]
				expect(v:GetPivot():FuzzyEq(f.slots.Slot2.CargoAttachment.WorldCFrame, 0.001)).to.equal(true)
				expect(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot2", r.ItemId)).to.equal(false)
			end)
		end)

		it("makes an inert rigid display without anchoring or moving the chassis or retaining carry joints", function()
			fixture(function(f)
				local r = f.carry()
				f.near("Slot1")
				f.chassis.Anchored = false
				local frame, priority, mass = f.chassis.CFrame, f.chassis.RootPriority, f.chassis.AssemblyMass
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", r.ItemId))
				local v = f.cart.CargoVisuals:GetChildren()[1]
				for _, item in v:GetDescendants() do
					if item:IsA("BasePart") then
						expect(item.Anchored).to.equal(false)
						expect(item.Massless).to.equal(true)
						expect(item.CanCollide or item.CanTouch).to.equal(false)
						expect(item.RootPriority).to.equal(-127)
						expect(item.CollisionGroup).to.equal("Carts")
					elseif item:IsA("WeldConstraint") then
						expect(item.Part0:IsDescendantOf(f.cart)).to.equal(true)
						expect(item.Part1:IsDescendantOf(v)).to.equal(true)
					else
						expect(
							item:IsA("BodyMover")
								or item:IsA("LuaSourceContainer")
								or item:IsA("Humanoid")
								or item:IsA("ProximityPrompt")
								or item:IsA("ParticleEmitter")
						).to.equal(false)
					end
				end
				expect(f.chassis.CFrame:FuzzyEq(frame, 0.001)).to.equal(true)
				expect(f.chassis.Anchored).to.equal(false)
				expect(f.chassis.RootPriority).to.equal(priority)
				expect(f.chassis.AssemblyRootPart).to.equal(f.chassis)
				expect(math.abs(f.chassis.AssemblyMass - mass) < 0.001).to.equal(true)
				expect(f.template.Body.Anchored).to.equal(true)
				expect(f.template.Body.RootPriority).to.equal(127)
				f.chassis.Anchored = true -- Fixture cleanup, not production behaviour.
			end)
		end)

		it("full cargo permits shooting with empty hands and arrival never unloads", function()
			fixture(function(f)
				for _, id in { "Slot3", "Slot1", "Slot2" } do
					load(f, id)
				end
				f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 5)))
				local model = f.spawn(true)
				local tool = Instance.new("Tool")
				tool.Name = "SleepLauncher"
				tool:SetAttribute("BrainrotSleepLauncher", true)
				tool.RequiresHandle = false
				local handle = f.part(tool, "Handle", f.p.Character.PrimaryPart.Position)
				handle.CanQuery = false
				local muzzle = Instance.new("Attachment")
				muzzle.Name, muzzle.Parent = "Muzzle", handle
				tool.Parent = f.p.Character
				local shot, reason = fireAt(f.p, model:GetPivot().Position)
				assert(shot, reason)
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				local before = Cargo:GetCargoSnapshot(f.cart)
				Return:Step() -- Stopped Phase-6 return system must remain inert.
				task.wait()
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(3)
				expect(f.cart:GetAttribute("CargoCount")).to.equal(3)
				for _, r in before do
					expect(Cargo:GetCargoItem(f.cart, r.ItemId) ~= nil).to.equal(true)
				end
			end)
		end)
	end)
end
