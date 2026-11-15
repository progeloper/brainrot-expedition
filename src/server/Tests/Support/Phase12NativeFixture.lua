--!nocheck
-- Reused native ground/cart/hand/source fixture from BrainrotCargoLoading.spec.
-- Real placement, world registry, carry and cargo owners; only actor/cart registry is fake.
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Physics = game:GetService("PhysicsService")
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)
	local Services, Systems = script.Parent.Parent.Parent.Services, script.Parent.Parent.Parent.Systems
	local Cargo = require(Services.CartCargoService)
	local Carts = require(Services.CartService)
	local Occupants = require(Services.CartOccupantService)
	local Interaction = require(Systems.BrainrotInteractionSystem)
	local World = require(Systems.DevelopmentBrainrotSpawner)
	local Placement = require(script.Parent.Parent.Parent.Utility.CartLocalPlacement)
	local Combat = require(Services.PlayerCombatService)
	local Sleep = require(Systems.BrainrotSleepSystem)

	local Return = require(Systems.BaseReturnSystem)
	local sequence = -38000
	local suiteFixtureItemIds = {}
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
		root.Name, root.Parent = "SPEC_PHASE12_ESCAPE", workspace
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
		for _, definition in Catalog.GetAll() do
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
		replace(Carts, "GetCartRecord", function(_, who)
			return if who == p then current else nil
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

return fixture
