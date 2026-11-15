--!nocheck
-- Isolated diagnostic fixtures, not driving/network playtests. Real world,
-- visual factory, raycasts and welds; fake Player signals/driver role only.
return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Interaction = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	local Visuals = require(script.Parent.Parent.Services.CartCargoService)
	local Sleep = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
	local VisualScale = require(RS.Shared.Utility.BrainrotVisualScale)

	-- Camera-ray intent adapter for existing lifecycle fixtures, not gameplay input.
	local function fireAt(player, point)
		local origin = player.Character.HumanoidRootPart.Position
		local offset = point - origin
		return Sleep.HandleFireRequest(player, {
			CameraOrigin = origin,
			CameraDirection = if offset.Magnitude > 0.001 then offset.Unit else -Vector3.zAxis,
		})
	end
	local Occupants = require(script.Parent.Parent.Services.CartOccupantService)

	local function fixture(callback)
		Placement.ResetQueryBudgetForTesting()
		assert(Interaction.Stop())
		local owned = {}
		local function own(v)
			table.insert(owned, v)
			return v
		end
		local function folder(parent, name)
			local existing = parent:FindFirstChild(name)
			if existing then
				return existing
			end
			local v = own(Instance.new("Folder"))
			v.Name, v.Parent = name, parent
			return v
		end
		local root = own(Instance.new("Folder"))
		root.Name, root.Parent = "SPEC_CARRY", workspace
		local origin = Vector3.new(12000, 102.5, 12000)
		local function part(parent, name, point, size)
			local v = Instance.new("Part")
			v.Name, v.Position, v.Size = name, point, size or Vector3.new(2, 2, 2)
			v.Anchored, v.Parent = true, parent
			return v
		end
		local ground = part(root, "Ground", origin - Vector3.new(0, 3.5, 0), Vector3.new(300, 2, 300))
		ground:SetAttribute("CartDrivableGround", true)
		local blockers = Instance.new("Folder")
		blockers.Name, blockers.Parent = "TemporaryObstacles", root
		local templates = folder(folder(RS, "StudioAssets"), "Brainrots")
		local template = own(Instance.new("Model"))
		template.Name = "SPEC_CARRY_TEMPLATE"
		local body = part(template, "Body", Vector3.zero, Vector3.new(2, 5, 2))
		body.RootPriority = 127
		body.Massless = false
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Parent = "CaptureAttachment", body
		local extra = part(template, "Detail", Vector3.new(1.5, 0, 0), Vector3.new(1, 1, 1))
		local joint = Instance.new("WeldConstraint")
		joint.Part0, joint.Part1, joint.Parent = body, extra, body
		Instance.new("BodyForce", body).Force = Vector3.new(0, 4, 0)
		Instance.new("ParticleEmitter", body).Enabled = false
		local inert = Instance.new("Script")
		inert.Disabled, inert.Parent = true, template
		template.PrimaryPart, template.Parent = body, templates
		local drivers = {}
		local deps = {
			World = table.clone(World),
			CreateItemVisual = function(id)
				return Visuals:CreateItemVisual(id)
			end,
			IsDriving = function(player)
				return drivers[player.UserId] == true
			end,
		}
		local nextUserId = -20000
		local fixturePlayers = {}
		local function newPlayer(offset)
			nextUserId -= 1
			local c = Instance.new("Model")
			c.Name, c.Parent = "CarryCharacter" .. tostring(-nextUserId), root
			local r = part(c, "HumanoidRootPart", origin + (offset or Vector3.new(0, 0.5, 5)))
			part(c, "Head", r.Position + Vector3.new(0, 1.5, 0))
			c.PrimaryPart = r
			local h = Instance.new("Humanoid")
			h.RequiresNeck, h.Parent = false, c
			local event = own(Instance.new("BindableEvent"))
			local attrs = {}
			local p = {
				Name = "CarrySpecPlayer",
				UserId = nextUserId,
				Parent = Players,
				CameraMaxZoomDistance = 128,
				Character = c,
				CharacterRemoving = event.Event,
			}
			function p:SetAttribute(key, value)
				attrs[key] = value
			end
			function p:GetAttribute(key)
				return attrs[key]
			end
			table.insert(fixturePlayers, p)
			return p, event
		end
		local function spawn(offset, awake)
			local record = {
				ItemId = Http:GenerateGUID(false),
				BrainrotId = template.Name,
				Metadata = { Tier = 3, Mutation = { Name = "Original", Value = 17 } },
				World = {
					Name = "SPEC_SLEEPER",
					Scale = 1,
					SpawnPosition = { X = origin.X, Y = origin.Y, Z = origin.Z },
				},
			}
			local prepared, reason =
				World.PrepareWorldRepresentation(record, CFrame.new(origin + (offset or Vector3.zero)))
			assert(prepared, reason)
			local model, failure = World.ActivatePreparedWorld(prepared)
			assert(model, failure)
			if not awake then
				assert(World.TrySleep(model))
			end
			return model, World.GetWorldRecord(model)
		end
		local function findIndividual(id)
			local result, count = nil, 0
			for _, model in World.GetWorldModels() do
				if World.GetWorldRecord(model).ItemId == id then
					result = model
					count += 1
				end
			end
			return result, count
		end
		Interaction.Start(deps)
		Interaction.Start(deps)
		Sleep.SetCarryingPredicate(Interaction.IsCarrying)
		Occupants:SetCarryingPredicate(Interaction.IsCarrying, Interaction.CarryChanged)
		Roaming.Start()
		local ok, failure = xpcall(function()
			callback({
				origin = origin,
				parent = root,
				part = part,
				spawn = spawn,
				player = newPlayer,
				deps = deps,
				drivers = drivers,
				template = template,
				find = findIndividual,
				ground = ground,
				blockers = blockers,
			})
		end, debug.traceback)
		deps.World.ActivatePreparedWorld = World.ActivatePreparedWorld
		deps.World.PrepareWorldRepresentation = World.PrepareWorldRepresentation
		blockers:Destroy()
		ground.Parent = root
		for _, player in fixturePlayers do
			Interaction._DiscardCarryForTesting(player)
		end
		assert(Interaction.Stop(), "Carry fixture could not restore its records")
		Sleep.SetCarryingPredicate(nil)
		Interaction.SetRegionAccessValidator(nil)
		Occupants:SetCarryingPredicate(nil)
		for _, model in World.GetWorldModels() do
			if World.GetWorldRecord(model).BrainrotId == template.Name then
				World.DestroyWorldForTesting(model:GetAttribute("ItemId"))
				model:Destroy()
				World.Unregister(model)
			end
		end
		for i = #owned, 1, -1 do
			owned[i]:Destroy()
		end
		if not ok then
			error(failure, 0)
		end
	end

	describe("Phase 3 one-brainrot carrying", function()
		it("boarding during pickup preparation prevents carry commit and preserves the sleeping individual", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				local factory = f.deps.CreateItemVisual
				f.deps.CreateItemVisual = function(id)
					task.wait()
					f.drivers[p.UserId] = true -- Simulate the occupant authority winning the race.
					return factory(id)
				end
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("DRIVING")
				expect(Interaction.GetCarriedRecord(p)).to.equal(nil)
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				expect(p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
				f.drivers[p.UserId] = false
			end)
		end)

		it(
			"server carry notifications revoke eligibility and Drop restores it without trusting the UI mirror",
			function()
				fixture(function(f)
					local p = f.player()
					local model, record = f.spawn()
					expect(Occupants:CanEnterDriver(p)).to.equal(true)
					local before = Occupants:GetDiagnostics().SharedConnectionCount
					Occupants:SetCarryingPredicate(Interaction.IsCarrying, Interaction.CarryChanged)
					expect(Occupants:GetDiagnostics().SharedConnectionCount).to.equal(before)
					assert(Interaction.TryPickupWorld(p, model, record.ItemId))
					p:SetAttribute("CarriedItemId", nil)
					expect(Occupants:CanEnterDriver(p)).to.equal(false)
					assert(Interaction.TryDropCarried(p, record.ItemId))
					expect(Occupants:CanEnterDriver(p)).to.equal(true)
					expect(select(2, World.GetWorldRecord(f.find(record.ItemId)))).to.equal("WorldAwake")
				end)
			end
		)

		it("rejects awake, forged display, descendant-part, stale ID, and retired representation requests", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn(nil, true)
				expect(Interaction.TryPickupWorld(p, model, record.ItemId)).to.equal(false)
				assert(World.TrySleep(model))
				expect(Interaction.TryPickupWorld(p, model.Body, record.ItemId)).to.equal(false)
				expect(Interaction.TryPickupWorld(p, model, "wrong-id")).to.equal(false)
				local display = model:Clone()
				display.Parent = f.parent
				expect(Interaction.TryPickupWorld(p, display, record.ItemId)).to.equal(false)
				model.Parent = nil
				World.Unregister(model)
				expect(Interaction.TryPickupWorld(p, model, record.ItemId)).to.equal(false)
				model:Destroy()
				expect(Interaction.GetCarriedRecord(p)).to.equal(nil)
			end)
		end)

		it("rejects driving, dead, missing-current-character, out-of-reach and wall-blocked pickup", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				f.drivers[p.UserId] = true
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("DRIVING")
				f.drivers[p.UserId] = false
				local character = p.Character
				p.Character = nil
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("NOT_LIVING")
				p.Character = character
				character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 20)))
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("OUT_OF_REACH")
				character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0.5, 5)))
				local wall = f.part(f.parent, "Cover", f.origin + Vector3.new(0, 1, 2.5), Vector3.new(8, 10, 0.5))
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("OBSTRUCTED")
				wall:Destroy()
				character.Humanoid.Health = 0
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("NOT_LIVING")
				expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
			end)
		end)

		it("transfers immutable ID/metadata with a safe visible rigid assembly and no world controller", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				model:SetAttribute("Tier", 999)
				model:SetAttribute("ItemId", "visual-tampering")
				local before = Roaming.GetDiagnostics().Registered
				local ok, reason = Interaction.TryPickupWorld(p, model, record.ItemId)
				assert(ok, reason)
				local carried = Interaction.GetCarriedRecord(p)
				expect(carried.ItemId).to.equal(record.ItemId)
				expect(carried.Metadata.Tier).to.equal(3)
				expect(carried.Metadata.Mutation.Name).to.equal("Original")
				expect(function()
					carried.Metadata.Tier = 9
				end).to.throw()
				expect(p:GetAttribute("CarriedItemId")).to.equal(record.ItemId)
				expect(World.GetWorldRecord(model)).to.equal(nil)
				expect(Roaming.GetDiagnostics().Registered).to.equal(before - 1)
				local visual = p.Character.CarriedBrainrot
				expect(visual:GetScale()).to.equal(record.World.Scale)
				expect(visual:GetAttribute("Captured")).to.equal(true)
				expect(visual:FindFirstChild("BrainrotSleepIndicator")).to.equal(nil)
				local parts, welds = 0, 0
				for _, item in visual:GetDescendants() do
					if item:IsA("BasePart") then
						parts += 1
						expect(item.Anchored or item.CanCollide or item.CanTouch).to.equal(false)
						expect(item.Massless).to.equal(true)
						expect(item.RootPriority).to.equal(-127)
					end
					if item:IsA("WeldConstraint") then
						welds += 1
					end
					expect(item:IsA("LuaSourceContainer") or item:IsA("BodyMover") or item:IsA("ParticleEmitter")).to.equal(
						false
					)
				end
				expect(welds).to.equal(parts) -- N-1 internal + exactly one avatar weld.
				expect(visual.PrimaryPart.CarryCharacterWeld.Part0).to.equal(p.Character.HumanoidRootPart)
				expect(f.template.Body.RootPriority).to.equal(127)
				expect(f.template.Body.CanQuery).to.equal(true)
				expect(p.Character.HumanoidRootPart.RootPriority).to.equal(0)
				expect(p.Character.Humanoid.WalkSpeed).to.equal(16)
			end)
		end)

		it("blocks a second pickup, firing and driver entry through authoritative predicates", function()
			fixture(function(f)
				local p = f.player()
				local one, a = f.spawn()
				local two, b = f.spawn(Vector3.new(5, 0, 1))
				assert(Interaction.TryPickupWorld(p, one, a.ItemId))
				expect(select(2, Interaction.TryPickupWorld(p, two, b.ItemId))).to.equal("ALREADY_CARRYING")
				expect(select(2, fireAt(p, f.origin))).to.equal("carrying")
				expect(select(2, Occupants:CanEnterDriver(p))).to.equal("carrying a brainrot")
				p:SetAttribute("CarriedItemId", nil) -- UI mirror never authorizes.
				expect(Interaction.IsCarrying(p)).to.equal(true)
				expect(Occupants:CanEnterDriver(p)).to.equal(false)
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(a.ItemId)
			end)
		end)

		it("sale consumption clears carry without publishing a world return", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				local rejected, rejection = Interaction.ConsumeCarriedBrainrot(
					p,
					record.ItemId,
					"BrainrotSale",
					function()
						return false, "AWARD_FAILED"
					end
				)
				expect(rejected).to.equal(nil)
				expect(rejection).to.equal("AWARD_FAILED")
				expect(Interaction.GetCarriedRecord(p)).to.equal(record)
				expect(p.Character:FindFirstChild("CarriedBrainrot") ~= nil).to.equal(true)

				local consumed =
					assert(Interaction.ConsumeCarriedBrainrot(p, record.ItemId, "BrainrotSale", function(current)
						expect(current).to.equal(record)
						return true, nil
					end))
				expect(consumed).to.equal(record)
				expect(Interaction.GetCarriedRecord(p)).to.equal(nil)
				expect(p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
				expect(f.find(record.ItemId)).to.equal(nil)
			end)
		end)

		it("two contenders interleaved during preparation have exactly one winner", function()
			fixture(function(f)
				local p1 = f.player(Vector3.new(-3, 0.5, 5))
				local p2 = f.player(Vector3.new(3, 0.5, 5))
				local model, record = f.spawn()
				local normal = f.deps.CreateItemVisual
				f.deps.CreateItemVisual = function(id)
					f.deps.CreateItemVisual = normal
					assert(Interaction.TryPickupWorld(p2, model, record.ItemId))
					return normal(id)
				end
				expect(Interaction.TryPickupWorld(p1, model, record.ItemId)).to.equal(false)
				expect(Interaction.GetCarriedRecord(p1)).to.equal(nil)
				expect(Interaction.GetCarriedRecord(p2).ItemId).to.equal(record.ItemId)
				expect(Interaction.GetDiagnostics().Carried).to.equal(1)
			end)
		end)

		it("keeps sleep server-wide when the initiating player leaves and lets another player win", function()
			fixture(function(f)
				local initiator = f.player(Vector3.new(-3, 0.5, 5))
				local picker = f.player(Vector3.new(3, 0.5, 5))
				local model, record = f.spawn(nil, true)
				expect(World.TrySleep(model)).to.equal(true)
				initiator.Parent = nil
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				expect(Interaction.TryPickupWorld(picker, model, record.ItemId)).to.equal(true)
				expect(Interaction.GetCarriedRecord(picker).ItemId).to.equal(record.ItemId)
				expect(Interaction.GetCarriedRecord(initiator)).to.equal(nil)
				expect(f.find(record.ItemId)).to.equal(nil)
			end)
		end)

		it("preparation failure or source waking during preparation leaves ownership in the world", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				local normal = f.deps.CreateItemVisual
				f.deps.CreateItemVisual = function()
					return nil
				end
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("PREPARATION_FAILED")
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				f.deps.CreateItemVisual = function(id)
					World.ResumeWorld(model)
					return normal(id)
				end
				expect(Interaction.TryPickupWorld(p, model, record.ItemId)).to.equal(false)
				expect(Interaction.GetCarriedRecord(p)).to.equal(nil)
				expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
			end)
		end)

		it("post-commit attachment failure restores the same individual awake", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				local setter = p.SetAttribute
				p.SetAttribute = function(self, key, value)
					if value then
						error("Injected attach setup failure")
					end
					setter(self, key, value)
				end
				expect(select(2, Interaction.TryPickupWorld(p, model, record.ItemId))).to.equal("ATTACHMENT_FAILED")
				local restored, count = f.find(record.ItemId)
				expect(count).to.equal(1)
				expect(select(2, World.GetWorldRecord(restored))).to.equal("WorldAwake")
				expect(Interaction.IsCarrying(p)).to.equal(false)
			end)
		end)

		it("unexpected carry cleanup releases once, near the carrier, with original normal-world physics", function()
			fixture(function(f)
				local p, removing = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				local character = p.Character
				character:PivotTo(CFrame.new(f.origin + Vector3.new(25, 0.5, 25)))
				assert(Interaction.HandleUnexpectedCarryCleanup(p, character))
				removing:Fire(character)
				expect(Interaction.HandleUnexpectedCarryCleanup(p, character)).to.equal(false)
				local restored, count = f.find(record.ItemId)
				expect(count).to.equal(1)
				expect((restored:GetPivot().Position - character:GetPivot().Position).Magnitude < 9).to.equal(true)
				expect(select(2, World.GetWorldRecord(restored))).to.equal("WorldAwake")
				expect(restored.Body.CanQuery and restored.Body.CanCollide and restored.Body.CanTouch).to.equal(true)
				expect(restored.Body.Massless).to.equal(false)
				expect(World.GetWorldRecord(restored).Metadata.Mutation.Value).to.equal(17)
				expect(character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
				expect(p:GetAttribute("CarriedItemId")).to.equal(nil)
				expect(Interaction.GetDiagnostics().CarryConnections).to.equal(0)
				assert(World.TrySleep(restored), "Returned individual must be recapturable")
			end)
		end)

		it("old character-removal events cannot release the replacement character's new carry", function()
			fixture(function(f)
				local p, removing = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				local old = p.Character
				assert(Interaction.HandleCharacterRemoving(p, old))
				local nextPlayer = f.player(Vector3.new(4, 0.5, 5))
				p.Character = nextPlayer.Character
				local nextModel, nextRecord = f.spawn(Vector3.new(5, 0, 1))
				old.Parent = nil
				assert(Interaction.TryPickupWorld(p, nextModel, nextRecord.ItemId))
				removing:Fire(old)
				expect(Interaction.HandleCharacterRemoving(p, old)).to.equal(false)
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(nextRecord.ItemId)
				old:Destroy()
			end)
		end)

		it("disconnect-style removal and visual loss restore via the shared cleanup guard", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				p.Parent = nil -- Diagnostic disconnected Player, not an actual second client.
				local deadline = os.clock() + 2
				repeat
					task.wait(0.05)
				until not Interaction.IsCarrying(p) or os.clock() >= deadline
				expect(Interaction.IsCarrying(p)).to.equal(false)
				expect(select(2, f.find(record.ItemId))).to.equal(1)
				p.Parent = Players
				local nextModel, nextRecord = f.spawn(Vector3.new(5, 0, 0))
				assert(Interaction.TryPickupWorld(p, nextModel, nextRecord.ItemId))
				p.Character.CarriedBrainrot:Destroy()
				deadline = os.clock() + 2
				repeat
					task.wait(0.05)
				until not Interaction.IsCarrying(p) or os.clock() >= deadline
				expect(Interaction.IsCarrying(p)).to.equal(false)
				expect(select(2, f.find(nextRecord.ItemId))).to.equal(1)
			end)
		end)

		it(
			"return preparation survives source removal and an activation failure retains the record for retry",
			function()
				fixture(function(f)
					local p = f.player()
					local model, record = f.spawn()
					assert(Interaction.TryPickupWorld(p, model, record.ItemId))
					local parent = f.template.Parent
					f.template.Parent = nil
					assert(Interaction.HandleUnexpectedCarryCleanup(p, p.Character))
					expect(select(2, f.find(record.ItemId))).to.equal(1)
					f.template.Parent = parent
					local nextModel, nextRecord = f.spawn(Vector3.new(5, 0, 0))
					assert(Interaction.TryPickupWorld(p, nextModel, nextRecord.ItemId))
					f.deps.World.ActivatePreparedWorld = function()
						return nil, "INJECTED_FAILURE"
					end
					expect(Interaction.HandleUnexpectedCarryCleanup(p, p.Character)).to.equal(false)
					expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(nextRecord.ItemId)
					expect(Interaction.GetDiagnostics().Returning).to.equal(1)
					f.deps.World.ActivatePreparedWorld = World.ActivatePreparedWorld
					task.wait(1.4)
					expect(Interaction.IsCarrying(p)).to.equal(false)
					expect(select(2, f.find(nextRecord.ItemId))).to.equal(1)
				end)
			end
		)

		it("fresh carried death and reset release the same individual locally", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				p.Character.Humanoid.Health = 0
				task.wait(0.4)
				expect(Interaction.IsCarrying(p)).to.equal(false)
				local _, count = f.find(record.ItemId)
				expect(count).to.equal(1)
				local nextPlayer = f.player(Vector3.new(4, 0.5, 5))
				p.Character = nextPlayer.Character
				local other, otherRecord = f.spawn(Vector3.new(5, 0, 1))
				assert(Interaction.TryPickupWorld(p, other, otherRecord.ItemId))
				local replacement = f.player(Vector3.new(20, 0.5, 20))
				p.Character = replacement.Character
				task.wait(0.4)
				expect(Interaction.IsCarrying(p)).to.equal(false)
				expect(select(2, f.find(otherRecord.ItemId))).to.equal(1)
				expect(Interaction.GetDiagnostics().CarryConnections).to.equal(0)
			end)
		end)

		it("prompt lifecycle and repeated start/stop do not accumulate retired-model listeners", function()
			fixture(function(f)
				local initialSharedConnections = Interaction.GetDiagnostics().SharedConnections
				expect(initialSharedConnections > 0).to.equal(true)
				for _ = 1, 4 do
					local model = f.spawn(nil, true)
					expect(Interaction.GetDiagnostics().Prompts).to.equal(0)
					World.TrySleep(model)
					task.wait()
					expect(Interaction.GetDiagnostics().Prompts).to.equal(1)
					local prompt = model:FindFirstChild("BrainrotPickup", true)
					assert(prompt and prompt:IsA("ProximityPrompt"), "Sleeping world prompt was not created")
					expect(prompt.MaxActivationDistance).to.equal(14)
					expect(prompt.RequiresLineOfSight).to.equal(false)
					expect(prompt.Exclusivity).to.equal(Enum.ProximityPromptExclusivity.AlwaysShow)
					expect(model:FindFirstChild("BrainrotSleepIndicator", true)).to.equal(nil)
					World.ResumeWorld(model)
					task.wait()
					expect(Interaction.GetDiagnostics().Prompts).to.equal(0)
					World.TrySleep(model)
					model:Destroy()
					World.Unregister(model)
					task.wait()
					expect(Interaction.GetDiagnostics().Prompts).to.equal(0)
				end
				assert(Interaction.Stop())
				expect(Interaction.GetDiagnostics().SharedConnections).to.equal(0)
				Interaction.Start(f.deps)
				expect(Interaction.GetDiagnostics().SharedConnections).to.equal(initialSharedConnections)
			end)
		end)
	end)

	describe("Phase 4 drop, wake and ordinary recapture", function()
		it(
			"retains the exact carried individual over an anchored decorative roof and releases after authored ground returns",
			function()
				fixture(function(f)
					local p = f.player()
					local source, record = f.spawn()
					assert(Interaction.TryPickupWorld(p, source, record.ItemId))
					local visual = p.Character.CarriedBrainrot
					f.ground:SetAttribute("CartDrivableGround", nil)
					f.ground.Name = "DecorativeRoof"
					expect(Interaction.TryDropCarried(p, record.ItemId)).to.equal(false)
					expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(record.ItemId)
					expect(p.Character.CarriedBrainrot).to.equal(visual)
					expect(select(2, f.find(record.ItemId))).to.equal(0)
					f.ground:SetAttribute("CartDrivableGround", true)
					task.wait(0.3)
					expect(Interaction.TryDropCarried(p, record.ItemId)).to.equal(true)
					expect(Interaction.IsCarrying(p)).to.equal(false)
					expect(select(2, f.find(record.ItemId))).to.equal(1)
				end)
			end
		)

		it("preserves trusted banked ownership in an owner-only secured world drop", function()
			fixture(function(f)
				local Policy = require(script.Parent.Parent.Services.DeparturePolicy)
				local p = f.player()
				local model, record = f.spawn(Vector3.new(0, 0, 0))
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				f.deps.Banked = {
					GetOwnedIndividual = function(_, subject, individualId)
						return if subject == p and individualId == record.ItemId
							then { speciesId = record.BrainrotId }
							else nil
					end,
				}
				f.deps.DeparturePolicy = Policy
				local dropped, reason = Interaction.TryDropCarried(p, record.ItemId)
				expect(dropped).to.equal(true)
				expect(reason).to.equal(nil)
				expect(Interaction.IsCarrying(p)).to.equal(false)
				local _, worldCount = f.find(record.ItemId)
				expect(worldCount).to.equal(1)
				f.deps.Banked = nil
				f.deps.DeparturePolicy = nil
			end)
		end)

		it("allows an immediate ordinary beam after Drop, with no release-specific immunity", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				assert(Interaction.TryDropCarried(p, record.ItemId))
				model = f.find(record.ItemId)
				local tool = Instance.new("Tool")
				tool.Name = "SleepLauncher"
				tool:SetAttribute("BrainrotSleepLauncher", true)
				local handle = f.part(tool, "Handle", p.Character.PrimaryPart.Position)
				local muzzle = Instance.new("Attachment")
				muzzle.Name, muzzle.Parent = "Muzzle", handle
				tool.Parent = p.Character
				assert(fireAt(p, model.Body.Position))
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
			end)
		end)

		it("rejects unsupported species bounds even when the centre has ground", function()
			fixture(function(f)
				local p = f.player()
				local model, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, model, record.ItemId))
				f.ground.Parent = nil
				local ledge = f.part(f.blockers, "TooNarrow", f.origin - Vector3.new(0, 3.5, 0), Vector3.new(1, 2, 1))
				local staged = assert(World.PrepareWorldRepresentation(record, CFrame.new(f.origin)))
				local pose = World.FindSafeReleasePose(staged, CFrame.new(f.origin), {}, true)
				World.DiscardPreparedWorld(staged)
				ledge:Destroy()
				expect(pose).to.equal(nil)
				expect(Interaction.IsCarrying(p)).to.equal(true)
			end)
		end)

		it("rejects empty/stale intents and never drops a newly carried different individual", function()
			fixture(function(f)
				local p = f.player()
				expect(select(2, Interaction.TryDropCarried(p, "none"))).to.equal("EMPTY_HANDS")
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				for _, stale in { false, {}, "different" } do
					expect(select(2, Interaction.TryDropCarried(p, stale))).to.equal("STALE_ID")
				end
				assert(Interaction.TryDropCarried(p, record.ItemId))
				expect(Interaction.TryDropCarried(p, record.ItemId)).to.equal(false)
				local b, nextRecord = f.spawn(Vector3.new(-5, 0, 4))
				assert(Interaction.TryPickupWorld(p, b, nextRecord.ItemId))
				expect(select(2, Interaction.TryDropCarried(p, record.ItemId))).to.equal("STALE_ID")
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(nextRecord.ItemId)
				expect(select(2, f.find(record.ItemId))).to.equal(1)
			end)
		end)

		it("thin enclosing walls reject Drop without deleting or detaching the carried visual", function()
			fixture(function(f)
				local p = f.player()
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				local visual = p.Character.CarriedBrainrot
				local position = p.Character:GetPivot().Position
				for _, x in { -2, 2 } do
					f.part(f.blockers, "Side", position + Vector3.new(x, 0, 0), Vector3.new(0.2, 16, 5))
					f.part(f.blockers, "End", position + Vector3.new(0, 0, x), Vector3.new(5, 16, 0.2))
				end
				expect(select(2, Interaction.TryDropCarried(p, record.ItemId))).to.equal("NO_SAFE_POSE")
				expect(Interaction.GetCarriedRecord(p)).to.equal(record)
				expect(p.Character.CarriedBrainrot).to.equal(visual)
				expect(visual.PrimaryPart.CarryCharacterWeld.Enabled).to.equal(true)
				expect(visual.PrimaryPart.CarryCharacterWeld.Part0).to.equal(p.Character.PrimaryPart)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
			end)
		end)

		it("nearby cart geometry is not ground and Drop changes neither cart nor character physics", function()
			fixture(function(f)
				local p = f.player()
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				local cart = Instance.new("Model")
				cart.Name, cart.Parent = "DiagnosticCartObstacle", f.blockers
				cart:SetAttribute("RuntimeCart", true)
				local chassis = f.part(cart, "Chassis", f.origin + Vector3.new(0, 0, -1), Vector3.new(4, 4, 4))
				local cartPose = chassis.CFrame
				local root = p.Character.PrimaryPart
				local avatarPose, anchored, massless = root.CFrame, root.Anchored, root.Massless
				assert(Interaction.TryDropCarried(p, record.ItemId))
				local returned = f.find(record.ItemId)
				local localBounds, size = VisualScale.GetVisualBounds(returned)
				local bounds = returned:GetPivot() * localBounds
				local expectedBottom = f.ground.Position.Y + f.ground.Size.Y / 2 + 0.15
				expect(math.abs(bounds.Position.Y - size.Y / 2 - expectedBottom) < 0.01).to.equal(true)
				expect(math.abs(returned:GetPivot().X - f.origin.X) >= 4).to.equal(true)
				expect(chassis.CFrame).to.equal(cartPose)
				expect(chassis.Anchored).to.equal(true)
				expect(root.CFrame).to.equal(avatarPose)
				expect(root.Anchored).to.equal(anchored)
				expect(root.Massless).to.equal(massless)
			end)
		end)

		it("voluntary void drop and lifecycle cleanup retain the same local pending source", function()
			fixture(function(f)
				local p = f.player()
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(500, 0.5, 500)))
				expect(select(2, Interaction.TryDropCarried(p, record.ItemId))).to.equal("NO_SAFE_POSE")
				expect(Interaction.IsCarrying(p)).to.equal(true)
				expect(Interaction.HandleUnexpectedCarryCleanup(p, p.Character)).to.equal(false)
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(record.ItemId)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
			end)
		end)

		it("absent ground blocks even forced fallback, retaining the record until support returns", function()
			fixture(function(f)
				local p = f.player()
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				f.ground.Parent = nil
				expect(select(2, Interaction.TryDropCarried(p, record.ItemId))).to.equal("NO_SAFE_POSE")
				expect(Interaction.HandleUnexpectedCarryCleanup(p, p.Character)).to.equal(false)
				p.Parent = nil
				p.Character:Destroy()
				p.Character = nil
				task.wait(1.3)
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(record.ItemId)
				expect(Interaction.GetDiagnostics().Returning).to.equal(1)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
				f.ground.Parent = f.parent
				task.wait(1.3)
				expect(Interaction.IsCarrying(p)).to.equal(false)
				expect(select(2, f.find(record.ItemId))).to.equal(1)
			end)
		end)

		it("failed activation restores the same carry and rechecks a changed character after preparation", function()
			fixture(function(f)
				local p = f.player()
				local a, record = f.spawn()
				assert(Interaction.TryPickupWorld(p, a, record.ItemId))
				local old = p.Character
				local visual = old.CarriedBrainrot
				f.deps.World.ActivatePreparedWorld = function()
					return nil, "INJECTED_FAILURE"
				end
				expect(Interaction.TryDropCarried(p, record.ItemId)).to.equal(false)
				expect(old.CarriedBrainrot).to.equal(visual)
				expect(visual.PrimaryPart.CarryCharacterWeld.Enabled).to.equal(true)
				f.deps.World.ActivatePreparedWorld = World.ActivatePreparedWorld
				task.wait(0.3)
				f.deps.World.PrepareWorldRepresentation = function(item, pose)
					task.wait() -- Actual yield: source can change while preparation is pending.
					p.Character = f.player(Vector3.new(25, 0.5, 25)).Character
					return World.PrepareWorldRepresentation(item, pose)
				end
				expect(select(2, Interaction.TryDropCarried(p, record.ItemId))).to.equal("SOURCE_CHANGED")
				expect(Interaction.GetCarriedRecord(p).ItemId).to.equal(record.ItemId)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
				f.deps.World.PrepareWorldRepresentation = World.PrepareWorldRepresentation
				assert(Interaction.HandleUnexpectedCarryCleanup(p, old))
				expect(select(2, f.find(record.ItemId))).to.equal(1)
			end)
		end)

		it(
			"three real shot/pickup/drop cycles preserve identity, normal motion, one model/controller and no carry welds",
			function()
				fixture(function(f)
					local p = f.player()
					local model, record = f.spawn(nil, true)
					local tool = Instance.new("Tool")
					tool.Name, tool.RequiresHandle = "SleepLauncher", true
					tool:SetAttribute("BrainrotSleepLauncher", true)
					local handle = f.part(tool, "Handle", p.Character.PrimaryPart.Position)
					handle.CanCollide = false
					local muzzle = Instance.new("Attachment")
					muzzle.Name, muzzle.Parent = "Muzzle", handle
					tool.Parent = p.Character -- Supported isolated equipped-Tool fixture, not physical user input.
					local registered = Roaming.GetDiagnostics().Registered
					for _ = 1, 3 do
						p.Character:PivotTo(CFrame.new(model.Body.Position + Vector3.new(0, 0.5, 5)))
						handle.CFrame = p.Character.PrimaryPart.CFrame
						local shot, failure = fireAt(p, model.Body.Position)
						assert(shot, failure)
						expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
						assert(Interaction.TryPickupWorld(p, model, record.ItemId))
						expect(Roaming.GetDiagnostics().Registered).to.equal(registered - 1)
						expect(select(2, f.find(record.ItemId))).to.equal(0)
						local retired = model
						assert(Interaction.TryDropCarried(p, record.ItemId))
						model = f.find(record.ItemId)
						World.Unregister(retired) -- Retired callbacks cannot retire the new same-ID model.
						retired:Destroy()
						expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
						expect(World.GetWorldRecord(model).Metadata.Mutation.Value).to.equal(17)
						expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
						expect(select(2, f.find(record.ItemId))).to.equal(1)
						expect(Roaming.GetDiagnostics().Registered).to.equal(registered)
						expect(Roaming.GetDiagnostics().Running).to.equal(registered)
						expect(Interaction.GetDiagnostics().Carried).to.equal(0)
						expect(Interaction.GetDiagnostics().CarryConnections).to.equal(0)
						expect(p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
						expect(model:FindFirstChild("CarryCharacterWeld", true)).to.equal(nil)
						expect(model:FindFirstChild("BrainrotSleepIndicator", true)).to.equal(nil)
						expect(Interaction.TryPickupWorld(p, model, record.ItemId)).to.equal(false)
						local start = model:GetPivot().Position
						task.wait(4)
						expect((model:GetPivot().Position - start).Magnitude > 0.1).to.equal(true)
						expect((model:GetPivot().Position - start).Magnitude <= 21).to.equal(true)
						print("[PHASE10_ID] three-cycle-drop-recapture " .. record.ItemId)
					end
					-- No numeric old escape duration exists in the current contract; explicitly
					-- check 12 additional seconds rather than claiming an unspecified timeout.
					task.wait(12)
					expect(select(2, f.find(record.ItemId))).to.equal(1)
					expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
					expect(Roaming.GetDiagnostics().Registered).to.equal(registered)
				end)
			end
		)
	end)
	it("checks wild pickup permission without blocking an already legitimate carried drop", function()
		fixture(function(f)
			local player = f.player()
			local model, record = f.spawn()
			local allow = false
			Interaction.SetRegionAccessValidator(function(actor, target)
				expect(actor).to.equal(player)
				expect(target).to.equal(model)
				return allow, "RegionAccessRequired"
			end)
			local ok, reason = Interaction.TryPickupWorld(player, model, record.ItemId)
			expect(ok).to.equal(false)
			expect(reason).to.equal("RegionAccessRequired")
			expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
			expect(Interaction.IsCarrying(player)).to.equal(false)
			allow = true
			assert(Interaction.TryPickupWorld(player, model, record.ItemId))
			allow = false
			assert(Interaction.TryDropCarried(player, record.ItemId))
			expect(Interaction.IsCarrying(player)).to.equal(false)
		end)
	end)
end
