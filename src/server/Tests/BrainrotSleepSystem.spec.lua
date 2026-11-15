--!nocheck
-- Diagnostic integration checks: real seats, raycasts, world lifecycle and cargo.
-- Only cart-registry/driver-authority lookups are fixture adapters, restored below.
-- These are NOT ordinary-control driving or client presentation playtests.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Http = game:GetService("HttpService")
	local Physics = game:GetService("PhysicsService")
	local Sleep = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
	local DecoySplit = require(script.Parent.Parent.Systems.Behaviours.DecoySplit)
	local DecoyConfig = require(RS.Shared.Config.BrainrotBehaviours).DecoySplit
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	local Carts = require(script.Parent.Parent.Services.CartService)
	local Occupants = require(script.Parent.Parent.Services.CartOccupantService)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)

	local function fixture(callback, role)
		local owned, models = {}, {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local function folder(parent, name)
			local existing = parent:FindFirstChild(name)
			if existing then
				return existing
			end
			local value = own(Instance.new("Folder"))
			value.Name, value.Parent = name, parent
			return value
		end
		local parent = own(Instance.new("Folder"))
		parent.Name, parent.Parent = "SPEC_SLEEP_1B", workspace
		local origin = Vector3.new(9000, 100, 9000)
		local function part(parentObject, name, position, size, class)
			local p = Instance.new(class or "Part")
			p.Name, p.Size, p.Position = name, size or Vector3.new(2, 2, 2), position
			p.Anchored, p.Parent = true, parentObject
			return p
		end
		local assets = folder(folder(RS, "StudioAssets"), "Brainrots")
		local template = own(Instance.new("Model"))
		template.Name = "SPEC_SLEEP_1B_TEMPLATE"
		local body = part(template, "Body", Vector3.zero, Vector3.new(4, 6, 4))
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Parent = "CaptureAttachment", body
		template.PrimaryPart, template.Parent = body, assets

		local cart = Instance.new("Model")
		cart.Name, cart.Parent = "SPEC_FIRING_CART", parent
		cart:SetAttribute("RuntimeCart", true)
		cart:SetAttribute("CartId", "CRT_001")
		local seatName = role or "DriverSeat"
		local seat = part(
			cart,
			seatName,
			origin + Vector3.new(0, 0, 8),
			nil,
			if seatName == "HunterSeat" then "Seat" else "VehicleSeat"
		)
		local muzzle = part(cart, "HarpoonOrigin", origin)
		cart.PrimaryPart = seat
		local slots = Instance.new("Folder")
		slots.Name, slots.Parent = "CargoSlots", cart
		for index = 1, 3 do
			local slot = part(slots, "Slot" .. index, origin + Vector3.new(index * 5, 0, 15))
			local marker = Instance.new("Attachment")
			marker.Name, marker.Parent = "CargoAttachment", slot
		end
		local character = Instance.new("Model")
		character.Name, character.Parent = "SPEC_CHARACTER", parent
		local rootPart = part(character, "HumanoidRootPart", seat.Position + Vector3.new(0, 3, 0))
		part(character, "Torso", rootPart.Position)
		part(character, "Head", rootPart.Position + Vector3.new(0, 2, 0))
		character.PrimaryPart = rootPart
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = character
		local player = {
			Name = "SleepSpecPlayer",
			UserId = -9876,
			Character = character,
			Parent = Players,
			CameraMaxZoomDistance = 128,
		}
		cart:SetAttribute("ActiveDriverUserId", player.UserId)
		cart:SetAttribute("OwnerUserId", player.UserId)
		local ownedRecord = { Model = cart, OwnerUserId = player.UserId }
		local oldRecord, oldControl = Carts.GetCartRecord, Occupants.CanPlayerControlCart
		Carts.GetCartRecord = function(_, p)
			return if p == player then ownedRecord else nil
		end
		local authorized = true
		Occupants.CanPlayerControlCart = function(_, p, model)
			return authorized
				and p == player
				and model == cart
				and seat.Name == "DriverSeat"
				and humanoid.SeatPart == seat
				and seat.Occupant == humanoid
		end
		local function spawn(position, previousRecord)
			local record = previousRecord
				or {
					ItemId = Http:GenerateGUID(false),
					BrainrotId = template.Name,
					Metadata = { Tier = 1, Mutation = { Name = "Preserved" } },
					World = {
						Name = "SPEC_TARGET",
						Scale = 1,
						SpawnPosition = { X = 0, Y = 0, Z = 0 },
					},
				}
			local prepared, reason = World.PrepareWorldRepresentation(record, CFrame.new(position))
			assert(prepared, reason)
			local model, failure = World.ActivatePreparedWorld(prepared)
			if not model then
				World.DiscardPreparedWorld(prepared)
			end
			assert(model, failure)
			table.insert(models, model)
			return model
		end
		local ok, failure = xpcall(function()
			seat:Sit(humanoid)
			task.wait(0.1)
			assert(seat.Occupant == humanoid and humanoid.SeatPart == seat, "Fixture could not seat the humanoid")
			Sleep:Start()
			Sleep:Start()
			Roaming.Start()
			-- These established ray/cover fixtures intentionally exercise a 60 stud
			-- synthetic profile. Phase 13 catalogue ranges are tested separately.
			Sleep.SetWeaponProfileResolver(function()
				return {
					status = "Ready",
					weaponId = "TEST_GEOMETRY",
					definitionRevision = 1,
					damage = 1,
					family = "Bow",
					profileId = "TEST",
					rangeStuds = 60,
					fireIntervalSeconds = 1,
					projectileSpeedStudsPerSecond = 500,
					projectileSpeedAuthority = "PresentationOnly",
					assistAcquireHalfAngleRadians = math.rad(10),
					assistRetainHalfAngleRadians = math.rad(16),
				},
					0
			end)
			callback({
				origin = origin,
				player = player,
				character = character,
				humanoid = humanoid,
				cart = cart,
				seat = seat,
				muzzle = muzzle,
				ownerRecord = ownedRecord,
				setAuthorized = function(value)
					authorized = value
				end,
				template = template,
				spawn = spawn,
				part = part,
				parent = parent,
				useOnFootHumanoid = function()
					-- RunScript does not advance normal character physics, so an
					-- anchored seat fixture retains SeatPart after weld removal.
					-- A fresh Humanoid establishes on-foot state for diagnostics;
					-- actual seat exit is checked separately in Play.
					seat.CanTouch = false
					seat.Disabled = true
					humanoid:Destroy()
					local weld = seat:FindFirstChild("SeatWeld")
					if weld then
						weld:Destroy()
					end
					character:PivotTo(CFrame.new(origin + Vector3.new(20, 3, 8)))
					humanoid = Instance.new("Humanoid")
					humanoid.RequiresNeck = false
					humanoid.Parent = character
					assert(humanoid.SeatPart == nil and not humanoid.Sit, "Fixture is not on foot")
					return humanoid
				end,
				equip = function()
					-- Clone the StarterPack mechanical definition (a labelled measured
					-- synthetic fixture in code-only RunScript). Anchoring is diagnostic only.
					local tool = game:GetService("StarterPack"):WaitForChild("SleepLauncher", 1)
					assert(tool, "Launcher mechanical fixture is required")
					local equipped = tool:Clone()
					equipped.Handle.Anchored = true
					equipped.Parent = character
					equipped.Handle.CFrame = CFrame.new(origin) * equipped.Handle.Muzzle.CFrame:Inverse()
					return equipped
				end,
				fire = function(point)
					local intent = if typeof(point) == "Vector3"
						then { CameraOrigin = origin, CameraDirection = (point - origin).Unit }
						else point
					return Sleep.HandleFireRequest(player, intent)
				end,
				fireRay = function(cameraOrigin, cameraDirection)
					return Sleep.HandleFireRequest(
						player,
						{ CameraOrigin = cameraOrigin, CameraDirection = cameraDirection }
					)
				end,
			})
		end, debug.traceback)
		Carts.GetCartRecord, Occupants.CanPlayerControlCart = oldRecord, oldControl
		Sleep.SetCarryingPredicate(nil)
		Sleep.SetRegionAccessValidator(nil)
		Sleep.SetWeaponProfileResolver(nil)
		Sleep.SetCartHitMultiplierResolver(nil)
		Sleep.SetRequiredHitsResolver(nil)
		Sleep.SetNowProvider(nil)
		Sleep.SetImpactHandler(nil)
		Sleep.SetActionValidator(nil)
		Sleep:Stop() -- Retire only this isolated shot fixture's endpoint/state.
		-- Diagnostic-only cargo teardown before removing fixture terrain/templates.
		for _, record in Cargo:GetCargoSnapshot(cart) do
			local token = Cargo:DetachForTransfer(cart, record.ItemId)
			if token then
				Cargo:FinalizeTransfer(cart, token)
			end
		end
		for _, model in models do
			local record = World.GetWorldRecord(model)
			if record then
				World.DestroyWorldForTesting(record.ItemId)
			end
			model:Destroy()
		end
		for index = #owned, 1, -1 do
			owned[index]:Destroy()
		end
		if not ok then
			error(failure, 0)
		end
	end

	describe("Phase10 accepted special impacts", function()
		it("resolves exactly one terminal outcome without sleeping the new loose destination", function()
			fixture(function(f)
				local clock, calls = 100, 0
				Sleep.SetNowProvider(function()
					return clock
				end)
				local special =
					f.part(f.parent, "SPEC_EXACT_CARGO_PROXY", f.origin - Vector3.zAxis * 10, Vector3.new(4, 6, 4))
				local behind = f.spawn(f.origin - Vector3.zAxis * 22)
				local released
				Sleep.SetImpactHandler(function(_, _, hit)
					if hit.Instance ~= special then
						return false
					end
					calls += 1
					special:Destroy()
					released = f.spawn(f.origin - Vector3.zAxis * 10)
					return true, "CargoKnockedLoose", "Catch knocked loose — put it to sleep!"
				end)
				local shot, failure =
					f.fire({ RequestId = 1, CameraOrigin = f.origin, CameraDirection = -Vector3.zAxis })
				assert(shot, failure)
				expect(calls).to.equal(1)
				expect((shot.Endpoint - (f.origin - Vector3.zAxis * 8)).Magnitude < 0.05).to.equal(true)
				expect(released:GetAttribute("Captured")).to.equal(false)
				expect(behind:GetAttribute("Captured")).to.equal(false)
				local duplicate = f.fire({ RequestId = 1, CameraOrigin = f.origin, CameraDirection = -Vector3.zAxis })
				expect(duplicate).to.equal(nil)
				expect(calls).to.equal(1)
				clock += 1
				local second, reason =
					f.fire({ RequestId = 2, CameraOrigin = f.origin, CameraDirection = -Vector3.zAxis })
				assert(second, reason)
				expect(released:GetAttribute("Captured")).to.equal(true)
				expect(behind:GetAttribute("Captured")).to.equal(false)
			end)
		end)
		it("a rejected protected special hit cannot fall through into wild sleeping", function()
			fixture(function(f)
				local target = f.spawn(f.origin - Vector3.zAxis * 12)
				local firstImpact, calls = nil, 0
				Sleep.SetImpactHandler(function(_, _, hit)
					firstImpact = hit
					calls += 1
					return true, "ProtectedTarget", "Player is protected."
				end)
				local shot, failure = f.fire(f.origin - Vector3.zAxis * 12)
				assert(shot, failure)
				expect(calls).to.equal(1)
				expect(firstImpact.Instance:IsDescendantOf(target)).to.equal(true)
				expect(shot.Endpoint).to.equal(firstImpact.Position)
				expect(target:GetAttribute("Captured")).to.equal(false)
			end)
		end)
	end)

	describe("Unobstructed logical bounds", function()
		it("does not require centre surface hits and still blocks camera/muzzle cover", function()
			fixture(function(f)
				local group = "SPEC_HOLLOW_" .. Http:GenerateGUID(false)
				Physics:RegisterCollisionGroup(group)
				Physics:CollisionGroupSetCollidable(group, "Default", false)
				local ok, err = xpcall(function()
					local target = f.spawn(f.origin + Vector3.new(0, 0, -30))
					Roaming.Pause(target)
					-- Model a centre ray through mesh openings, without changing its
					-- real original dimensions, query flag or awake registration.
					target.Body.CollisionGroup = group
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = { f.character, f.cart }
					params.FilterType = Enum.RaycastFilterType.Exclude
					local function select(muzzle)
						return Sleep.FindCentredHuntTarget(
							muzzle or f.origin,
							f.origin,
							-Vector3.zAxis,
							f.origin - Vector3.zAxis * 60,
							params
						)
					end
					for _ = 1, 10 do
						expect(select().Model).to.equal(target)
					end
					local wall = f.part(f.parent, "RealCover", f.origin + Vector3.new(0, 0, -15), Vector3.new(8, 8, 1))
					expect(select()).to.equal(nil)
					wall.Position = f.origin + Vector3.new(6, 0, -5)
					wall.Size = Vector3.new(2, 8, 2)
					expect(select(f.origin + Vector3.new(8, 0, 0))).to.equal(nil)
				end, debug.traceback)
				Physics:UnregisterCollisionGroup(group)
				assert(ok, err)
			end)
		end)
	end)

	describe("B1 enlarged bounds without hidden aim padding", function()
		local function selectTarget(f, c, d)
			c, d = c or f.origin, d or -Vector3.zAxis
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { f.character, f.cart }
			params.RespectCanCollide = false
			local v = c - f.muzzle.Position
			local axial = v:Dot(d)
			local depth = -axial + math.sqrt(axial * axial - v:Dot(v) + 60 * 60)
			local hit = workspace:Raycast(c, d * depth, params)
			return Sleep.FindCentredHuntTarget(
				f.muzzle.Position,
				c,
				d,
				if hit then hit.Position else c + d * depth,
				params
			)
		end

		it("direct enlarged-bound hit works without extra assistance, without physical proxies", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(5, 0, -30))
				local record = World.GetWorldRecord(target)
				local oldCount, oldSize = #target:GetDescendants(), target.Body.Size
				local oldQuery, oldCollide, oldTouch =
					target.Body.CanQuery, target.Body.CanCollide, target.Body.CanTouch
				for _ = 1, 20 do
					local frame, size = World.GetHuntBounds(target, record)
					expect(size).to.equal(Vector3.new(12, 12, 12))
					expect(frame.Position).to.equal(target.Body.Position)
				end
				expect(#target:GetDescendants()).to.equal(oldCount)
				expect(target.Body.Size).to.equal(oldSize)
				expect(target.Body.CanQuery).to.equal(oldQuery)
				expect(target.Body.CanCollide).to.equal(oldCollide)
				expect(target.Body.CanTouch).to.equal(oldTouch)
				expect(selectTarget(f).Model).to.equal(target)
				local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(shot.Endpoint).to.equal(f.origin + Vector3.new(0, 0, -24))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		it("a slight miss outside enlarged bounds stays a miss; no hidden padding remains", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(6.8, 0, -30))
				local pose = target:GetPivot()
				expect(selectTarget(f)).to.equal(nil)
				local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect((shot.Endpoint - f.origin):Cross(-Vector3.zAxis).Magnitude < 0.002).to.equal(true)
				expect(target:GetPivot()).to.equal(pose)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("close target remains hittable when camera and muzzle start inside its logical bounds", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -5))
				local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect((shot.Endpoint - f.origin).Magnitude > 0.01).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		for _, offset in { Vector3.new(7.6, 0, -30), Vector3.new(6.7, 0, -10), Vector3.new(8.2, 0, -55) } do
			it("rejects misses outside enlarged bounds: " .. tostring(offset), function()
				fixture(function(f)
					local target = f.spawn(f.origin + offset)
					expect(selectTarget(f)).to.equal(nil)
					local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
					expect(shot.Endpoint).to.equal(f.origin - Vector3.zAxis * 60)
					expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
				end)
			end)
		end

		it("third-person camera offset does not introduce hidden padding", function()
			fixture(function(f)
				local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
				local target = f.spawn(f.origin + Vector3.new(1.8, 0, -25))
				expect(selectTarget(f, c, d)).to.equal(nil)
				local shot = assert(f.fireRay(c, d))
				expect((shot.Endpoint - c):Cross(d).Magnitude < 0.002).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("cache ignores decorations, follows the pivot and refreshes only unpadded scale", function()
			fixture(function(f)
				f.template.Body.PivotOffset = CFrame.new(1, 0, 0)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -30))
				local decoration = f.part(
					target,
					"OldHitboxAndEffectFixture",
					target.Body.Position + Vector3.yAxis * 80,
					Vector3.one * 100
				)
				decoration.CanCollide, decoration.CanQuery, decoration.Transparency = false, false, 1
				local record = World.GetWorldRecord(target)
				local frame, size = World.GetHuntBounds(target, record)
				expect(size).to.equal(Vector3.new(12, 12, 12))
				expect(frame.Position).to.equal(target.Body.Position)
				target:PivotTo(CFrame.new(f.origin + Vector3.new(30, 0, -20)) * CFrame.Angles(0, math.pi / 2, 0))
				frame, size = World.GetHuntBounds(target, record)
				expect((frame.Position - target.Body.Position).Magnitude < 0.002).to.equal(true)
				expect(frame.LookVector:Dot(target.Body.CFrame.LookVector) > 0.999).to.equal(true)
				expect(size).to.equal(Vector3.new(12, 12, 12))
				expect(selectTarget(f)).to.equal(nil) -- no ghost at the old location
				target:ScaleTo(2)
				frame, size = World.GetHuntBounds(target, record)
				expect(size).to.equal(Vector3.new(20, 30, 20))
				expect((frame.Position - target.Body.Position).Magnitude < 0.002).to.equal(true)
				expect(select(2, World.GetHuntBounds(target, record))).to.equal(size)
				target:ScaleTo(1)
				expect(select(2, World.GetHuntBounds(target, record))).to.equal(Vector3.new(12, 15, 12))
			end)
		end)

		for _, angle in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			it("oriented logical bounds work at heading " .. angle, function()
				fixture(function(f)
					f.template.Body.Size = Vector3.new(2, 4, 8)
					local rotation = CFrame.Angles(0, angle, 0)
					local target = f.spawn(f.origin + rotation:VectorToWorldSpace(Vector3.new(5, 0, -30)))
					target:PivotTo(CFrame.new(target:GetPivot().Position) * rotation)
					expect(selectTarget(f, f.origin, rotation.LookVector).Model).to.equal(target)
					local shot = assert(f.fireRay(f.origin, rotation.LookVector))
					expect((shot.Endpoint - f.origin):Cross(rotation.LookVector).Magnitude < 0.002).to.equal(true)
					expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				end)
			end)
		end

		it("large bounds crossing a wall do not prove real-body visibility", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(5, 0, -22))
				f.part(f.parent, "CoverInsideHuntBounds", f.origin + Vector3.new(0, 0, -19), Vector3.new(30, 30, 1))
				local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(shot.Endpoint).to.equal(f.origin + Vector3.new(0, 0, -18.5))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it(
			"preserves authored hunt bounds without replicating decorative snout geometry after roaming rotation",
			function()
				fixture(function(f)
					-- Put a visible snout in front of the Body centre after a 90-degree turn.
					local detail = f.part(f.template, "Detail", Vector3.new(3, 0, 0), Vector3.new(2, 2, 2))
					local target = f.spawn(f.origin + Vector3.new(0, 0, -20))
					local record = World.GetWorldRecord(target)
					local _, size, _, parts = World.GetHuntBounds(target, record)
					expect(size).to.equal(Vector3.new(12, 12, 12))
					expect(target:FindFirstChild("Detail")).to.equal(nil)
					expect(parts[target:FindFirstChild("Body", true)]).to.equal(true)
					expect(parts[detail]).to.equal(nil)
					target:PivotTo(CFrame.new(target:GetPivot().Position) * CFrame.Angles(0, -math.pi / 2, 0))
					assert(f.fireRay(f.origin, -Vector3.zAxis))
					expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				end)
			end
		)

		it("original hitboxes, effects, labels and nested carry/cargo decorations are excluded", function()
			fixture(function(f)
				for _, name in
					{
						"OldHitbox",
						"TemporaryEffects",
						"PromptLabel",
						"CapturedNet",
						"CarriedBrainrot",
						"CargoVisuals",
						"Stored_Example",
					}
				do
					local folder = Instance.new("Folder")
					folder.Name, folder.Parent = name, f.template
					f.part(folder, "Decoration", Vector3.yAxis * 100, Vector3.one * 50)
				end
				local target = f.spawn(f.origin + Vector3.new(0, 0, -30))
				local _, size, _, parts = World.GetHuntBounds(target, World.GetWorldRecord(target))
				expect(size).to.equal(Vector3.new(12, 12, 12))
				local count = 0
				for _ in parts do
					count += 1
				end
				expect(count).to.equal(1)
			end)
		end)

		it("body hidden beside an exposed centre path is not a large-box hit", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(5, 0, -30))
				f.part(f.parent, "BodyCoverOnly", f.origin + Vector3.new(4, 0, -24), Vector3.new(3, 20, 1))
				local shot = assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(shot.Endpoint).to.equal(f.origin - Vector3.zAxis * 60)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("an exposed off-centre body cannot be assisted through reticle-ray cover", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(7, 0, -30))
				f.part(f.parent, "ReticleCoverOnly", f.origin + Vector3.new(0, 0, -16), Vector3.new(1, 20, 1))
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("camera-visible body still needs muzzle visibility", function()
			fixture(function(f)
				local c = f.origin + Vector3.new(-6, 0, 28)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -30))
				f.part(f.parent, "MuzzleBodyCover", f.origin + Vector3.new(-0.25, 0, -10), Vector3.new(1, 20, 1))
				assert(f.fireRay(c, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("camera and body visibility do not bypass cover on the muzzle-to-centred-depth segment", function()
			fixture(function(f)
				local c = f.origin + Vector3.new(-6, 0, 28)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -30))
				f.part(
					f.parent,
					"CentredMuzzleSegmentCover",
					f.origin + Vector3.new(-3, 0, -12),
					Vector3.new(0.8, 20, 1)
				)
				assert(f.fireRay(c, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		for _, offset in { Vector3.new(0, 0, -64), Vector3.new(0, 0, 4) } do
			it(
				"rejects real body outside muzzle range or behind view despite intersecting bounds: "
					.. tostring(offset),
				function()
					fixture(function(f)
						local target = f.spawn(f.origin + offset)
						assert(f.fireRay(f.origin, -Vector3.zAxis))
						expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
					end)
				end
			)
		end

		it("overlapping direct bounds choose first ray depth, not nearest world distance", function()
			fixture(function(f)
				local intended = f.spawn(f.origin + Vector3.new(5.8, 0, -20))
				local worldNearest = f.spawn(f.origin + Vector3.new(-0.5, 0, -20.4))
				assert(
					(intended.Body.Position - f.origin).Magnitude > (worldNearest.Body.Position - f.origin).Magnitude,
					"Fixture must distinguish ray depth from world distance"
				)
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(intended))).to.equal("WorldSleeping")
				expect(select(2, World.GetWorldRecord(worldNearest))).to.equal("WorldAwake")
			end)
		end)

		it("valid direct target beats a closer assisted target", function()
			fixture(function(f)
				local direct = f.spawn(f.origin + Vector3.new(-5, 0, -40))
				local assisted = f.spawn(f.origin + Vector3.new(6.5, 0, -20))
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(direct))).to.equal("WorldSleeping")
				expect(select(2, World.GetWorldRecord(assisted))).to.equal("WorldAwake")
			end)
		end)

		it("neither nearby bounds miss is secretly retargeted", function()
			fixture(function(f)
				local smallMiss = f.spawn(f.origin + Vector3.new(-6.3, 0, -40))
				local closer = f.spawn(f.origin + Vector3.new(6.8, 0, -22))
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(smallMiss))).to.equal("WorldAwake")
				expect(select(2, World.GetWorldRecord(closer))).to.equal("WorldAwake")
			end)
		end)

		it("fires at the explicit farther assist lock instead of a nearer world target", function()
			fixture(function(f)
				local locked = f.spawn(f.origin + Vector3.new(4, 0, -30))
				local nearest = f.spawn(f.origin + Vector3.new(-5, 0, -8))
				assert(
					(nearest.Body.Position - f.origin).Magnitude < (locked.Body.Position - f.origin).Magnitude,
					"Fixture must keep the non-locked target physically nearer"
				)
				Sleep.SetRegionAccessValidator(function(_, model)
					expect(model).to.equal(locked)
					return true, nil
				end)
				local lockDirection = (locked.Body.Position - f.origin).Unit
				local shot = assert(f.fire({
					CameraOrigin = f.origin,
					CameraDirection = lockDirection,
					CrosshairDirection = -Vector3.zAxis,
					ShotMode = "ASSIST_LOCK",
					LockedTargetId = locked:GetAttribute("ItemId"),
					LockedTargetKind = "Brainrot",
				}))
				expect(select(2, World.GetWorldRecord(locked))).to.equal("WorldSleeping")
				expect(select(2, World.GetWorldRecord(nearest))).to.equal("WorldAwake")
				expect((shot.Endpoint - shot.Origin).Unit:Dot(lockDirection) > 0.99).to.equal(true)
			end)
		end)

		it("uses the current lock in a three-target scene regardless of proximity or history", function()
			fixture(function(f)
				local nearest = f.spawn(f.origin + Vector3.new(-4.5, 0, -9))
				local locked = f.spawn(f.origin + Vector3.new(3, 0, -28))
				local previous = f.spawn(f.origin + Vector3.new(7, 0, -20))
				assert(f.fire({
					CameraOrigin = f.origin,
					CameraDirection = (locked.Body.Position - f.origin).Unit,
					CrosshairDirection = -Vector3.zAxis,
					ShotMode = "ASSIST_LOCK",
					LockedTargetId = locked:GetAttribute("ItemId"),
					LockedTargetKind = "Brainrot",
				}))
				expect(select(2, World.GetWorldRecord(locked))).to.equal("WorldSleeping")
				expect(select(2, World.GetWorldRecord(nearest))).to.equal("WorldAwake")
				expect(select(2, World.GetWorldRecord(previous))).to.equal("WorldAwake")
			end)
		end)

		it("falls back to free crosshair fire when an assist-lock identity is stale", function()
			fixture(function(f)
				local left = f.spawn(f.origin + Vector3.new(-9, 0, -30))
				local right = f.spawn(f.origin + Vector3.new(9, 0, -30))
				assert(f.fire({
					CameraOrigin = f.origin,
					CameraDirection = Vector3.new(0.1, 0, -1).Unit,
					CrosshairDirection = -Vector3.zAxis,
					ShotMode = "ASSIST_LOCK",
					LockedTargetId = "STALE-ITEM",
					LockedTargetKind = "Brainrot",
				}))
				expect(select(2, World.GetWorldRecord(left))).to.equal("WorldAwake")
				expect(select(2, World.GetWorldRecord(right))).to.equal("WorldAwake")
			end)
		end)

		it("never auto-selects the nearest target in explicit free-crosshair mode", function()
			fixture(function(f)
				local left = f.spawn(f.origin + Vector3.new(-9, 0, -18))
				local right = f.spawn(f.origin + Vector3.new(9, 0, -18))
				assert(f.fire({
					CameraOrigin = f.origin,
					CameraDirection = -Vector3.zAxis,
					CrosshairDirection = -Vector3.zAxis,
					ShotMode = "CROSSHAIR_FREE",
				}))
				expect(select(2, World.GetWorldRecord(left))).to.equal("WorldAwake")
				expect(select(2, World.GetWorldRecord(right))).to.equal("WorldAwake")
			end)
		end)

		it("overlapping direct bounds prefer nearer valid ray depth", function()
			fixture(function(f)
				local farther = f.spawn(f.origin + Vector3.new(-5, 0, -40))
				local nearer = f.spawn(f.origin + Vector3.new(5, 0, -22))
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(select(2, World.GetWorldRecord(nearer))).to.equal("WorldSleeping")
				expect(select(2, World.GetWorldRecord(farther))).to.equal("WorldAwake")
			end)
		end)

		for _, x in { 5, 5.5 } do
			it("tied bounds use stable individual ID regardless of registry iteration at offset " .. x, function()
				fixture(function(f)
					local left = f.spawn(f.origin + Vector3.new(-x, 0, -30))
					local right = f.spawn(f.origin + Vector3.new(x, 0, -30))
					local expected = if World.GetWorldRecord(left).ItemId
							< World.GetWorldRecord(right).ItemId
						then left
						else right
					local other = if expected == left then right else left
					for _ = 1, 10 do
						expect(selectTarget(f).Model).to.equal(expected)
					end
					assert(f.fireRay(f.origin, -Vector3.zAxis))
					expect(select(2, World.GetWorldRecord(expected))).to.equal("WorldSleeping")
					expect(select(2, World.GetWorldRecord(other))).to.equal("WorldAwake")
				end)
			end)
		end

		it("sleeping and detached carried/cargo/base lookalikes have no hunt bounds", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(5, 0, -30))
				local record = World.GetWorldRecord(target)
				assert(World.GetHuntBounds(target, record))
				assert(World.TrySleep(target))
				expect(World.GetHuntBounds(target, record)).to.equal(nil)
				expect(selectTarget(f)).to.equal(nil)
				assert(World.TakeSleepingWorld(target, record))
				for _, name in { "CarryVisual", "CargoVisual", "BaseDisplay" } do
					local display = target:Clone()
					display.Name, display.Parent = name, f.parent
					display.Body.CanCollide, display.Body.CanQuery = false, false
					expect(World.GetHuntBounds(display, record)).to.equal(nil)
				end
				expect(selectTarget(f)).to.equal(nil)
				assert(f.fireRay(f.origin, -Vector3.zAxis))
			end)
		end)

		it("released same-ID individual receives identical logical bounds and normal hit eligibility", function()
			fixture(function(f)
				local original = f.spawn(f.origin + Vector3.new(5, 0, -30))
				local record = World.GetWorldRecord(original)
				local _, size = World.GetHuntBounds(original, record)
				assert(World.TrySleep(original))
				assert(World.TakeSleepingWorld(original, record))
				local restored = f.spawn(f.origin + Vector3.new(5, 0, -30), record)
				expect(select(2, World.GetHuntBounds(restored, World.GetWorldRecord(restored)))).to.equal(size)
				assert(f.fireRay(f.origin, -Vector3.zAxis))
				expect(World.GetWorldRecord(restored).ItemId).to.equal(record.ItemId)
				expect(select(2, World.GetWorldRecord(restored))).to.equal("WorldSleeping")
			end)
		end)
	end)

	describe("Task A centred camera ray", function()
		for _, heading in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			it("side-mounted range endpoint converges to centre at heading " .. heading, function()
				fixture(function(f)
					local rotation = CFrame.Angles(0, heading, 0)
					local c = f.origin + rotation:VectorToWorldSpace(Vector3.new(-6, 0, 28))
					local d = rotation.LookVector
					local shot, reason = f.fireRay(c, d)
					assert(shot, reason)
					expect((shot.Endpoint - c):Cross(d).Magnitude < 0.005).to.equal(true)
					expect(math.abs((shot.Endpoint - shot.Origin).Magnitude - 60) < 0.005).to.equal(true)
					expect((shot.Endpoint - c):Dot(d) > 0).to.equal(true)
				end)
			end)
		end

		for _, zoom in { 0.5, 28, 128 } do
			it("on-foot centre convergence at supported zoom " .. zoom, function()
				fixture(function(f)
					f.useOnFootHumanoid()
					f.equip()
					local c, d = f.origin + Vector3.new(-3, 0, zoom), -Vector3.zAxis
					local shot, reason = f.fireRay(c, d)
					assert(shot, reason)
					expect((shot.Endpoint - c):Cross(d).Magnitude < 0.005).to.equal(true)
					expect(math.abs((shot.Endpoint - shot.Origin).Magnitude - 60) < 0.005).to.equal(true)
				end)
			end)
		end

		it("near centre landmark sets depth instead of extending past it", function()
			fixture(function(f)
				local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
				f.part(f.parent, "CentredLandmark", f.origin + Vector3.new(-6, 0, -16), Vector3.new(2, 6, 2))
				local shot, reason = f.fireRay(c, d)
				assert(shot, reason)
				expect((shot.Endpoint - (f.origin + Vector3.new(-6, 0, -15))).Magnitude < 0.005).to.equal(true)
			end)
		end)

		it("camera-visible aim is still blocked by cover beside the muzzle", function()
			fixture(function(f)
				local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
				local target = f.spawn(f.origin + Vector3.new(-6, 0, -30))
				f.part(f.parent, "MuzzleOnlyCover", f.origin + Vector3.new(0, 0, -3), Vector3.new(2, 6, 1))
				local shot, reason = f.fireRay(c, d)
				assert(shot, reason)
				expect((shot.Endpoint - f.origin).Magnitude < 4).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("camera obstruction behind muzzle rejects rather than firing backward", function()
			fixture(function(f)
				local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
				local wall =
					f.part(f.parent, "BehindMuzzleCover", f.origin + Vector3.new(-6, 0, 10), Vector3.new(3, 6, 2))
				local shot, reason = f.fireRay(c, d)
				expect(shot).to.equal(nil)
				expect(reason).to.equal("camera obstruction behind muzzle")
				wall:Destroy()
				assert(f.fireRay(c, d), "Blocked intent must not consume accepted-shot cooldown")
			end)
		end)

		it("rejects untrusted camera fields and retains the next valid shot", function()
			fixture(function(f)
				for _, intent in
					{
						f.origin,
						{},
						{ CameraOrigin = f.origin, CameraDirection = Vector3.zero },
						{ CameraOrigin = f.origin, CameraDirection = Vector3.new(0, 0, -60) },
						{ CameraOrigin = f.origin, CameraDirection = Vector3.new(0 / 0, 0, -1) },
						{
							CameraOrigin = Vector3.new(math.huge, 0, 0),
							CameraDirection = -Vector3.zAxis,
						},
					}
				do
					expect(Sleep.HandleFireRequest(f.player, intent)).to.equal(nil)
				end
				expect(select(2, f.fireRay(f.origin + Vector3.new(1000, 0, 0), -Vector3.zAxis))).to.equal(
					"camera origin outside permitted offset"
				)
				expect(select(2, f.fireRay(f.origin + Vector3.new(70, 0, 20), -Vector3.zAxis))).to.equal(
					"camera ray misses weapon range"
				)
				expect(select(2, f.fireRay(f.origin + Vector3.new(0, 0, -100), -Vector3.zAxis))).to.equal(
					"no forward aim in weapon range"
				)
				assert(f.fireRay(f.origin, -Vector3.zAxis))
			end)
		end)
	end)

	describe("A2 muzzle/centre agreement without aim assistance", function()
		for _, heading in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			for _, pitch in { -0.45, 0, 0.45 } do
				it("handheld clear miss preserves heading/pitch " .. heading .. "/" .. pitch, function()
					fixture(function(f)
						f.useOnFootHumanoid()
						local tool = f.equip()
						f.cart:PivotTo(CFrame.new(f.origin + Vector3.new(1000, 0, 0)))
						local rotation = CFrame.Angles(0, heading, 0) * CFrame.Angles(pitch, 0, 0)
						local c = f.origin + rotation:VectorToWorldSpace(Vector3.new(2.5, 1, 11))
						local d = rotation.LookVector
						-- Server root yaw deliberately lags current aim. Exact yaw equality
						-- would incorrectly reject legitimate immediately turned shots.
						local shot, reason = f.fireRay(c, d)
						assert(shot, reason)
						expect(shot.Origin).to.equal(tool.Handle.Muzzle.WorldPosition)
						expect((shot.Endpoint - c):Cross(d).Magnitude < 0.005).to.equal(true)
						expect(math.abs((shot.Endpoint - shot.Origin).Magnitude - 60) < 0.005).to.equal(true)
						expect((shot.Endpoint - shot.Origin).Unit:Dot(d) > 0.99).to.equal(true)
						if pitch ~= 0 then
							expect((shot.Endpoint.Y - shot.Origin.Y) * pitch > 0).to.equal(true)
						end
					end)
				end)
			end
		end
		it("rejects near-sideways camera obstruction without skipping cover or spending cooldown", function()
			fixture(function(f)
				local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
				local wall =
					f.part(f.parent, "AlmostMuzzlePlane", f.origin + Vector3.new(-6, 0, -0.55), Vector3.new(2, 6, 1))
				local shot, reason = f.fireRay(c, d)
				expect(shot).to.equal(nil)
				expect(reason).to.equal("aim point too close to muzzle plane")
				wall:Destroy()
				assert(f.fireRay(c, d), "Invalid close geometry consumed the cooldown")
			end)
		end)
		it("keeps ordinary close shoulder parallax and sleeps the actual target", function()
			fixture(function(f)
				f.useOnFootHumanoid()
				f.equip()
				f.cart:PivotTo(CFrame.new(f.origin + Vector3.new(1000, 0, 0)))
				local c, d = f.origin + Vector3.new(2.5, 0, 11), -Vector3.zAxis
				local target = f.spawn(f.origin + Vector3.new(2.5, 0, -8))
				local shot, reason = f.fireRay(c, d)
				assert(shot, reason)
				expect((shot.Endpoint - c):Cross(d).Magnitude < 0.005).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)
		for _, role in { "DriverSeat" } do
			it("excludes camera self-obstruction, tool/cart geometry and non-query effects for " .. role, function()
				fixture(function(f)
					local c, d = f.origin + Vector3.new(-6, 0, 28), -Vector3.zAxis
					f.part(
						f.character,
						"SelfBetweenCameraAndMuzzle",
						f.origin + Vector3.new(-6, 0, 20),
						Vector3.new(3, 3, 3)
					)
					f.part(
						f.cart,
						"OwnCartBetweenCameraAndMuzzle",
						f.origin + Vector3.new(-6, 0, 10),
						Vector3.new(3, 3, 3)
					)
					local effect =
						f.part(f.parent, "NonQueryCosmetic", f.origin + Vector3.new(-6, 0, -10), Vector3.new(3, 3, 3))
					effect.CanCollide, effect.CanQuery = false, false
					local target = f.spawn(f.origin + Vector3.new(-6, 0, -30))
					local shot, reason = f.fireRay(c, d)
					assert(shot, reason)
					expect(shot.Origin).to.equal(f.origin)
					expect((shot.Endpoint - c):Cross(d).Magnitude < 0.005).to.equal(true)
					expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				end, role)
			end)
		end
	end)

	describe("Phase 9 accepted-hit team power", function()
		it("keeps a current valid sleep one-hit with capped owner-cart Hit", function()
			fixture(function(f)
				local calls = 0
				Sleep.SetCartHitMultiplierResolver(function(cart)
					expect(cart).to.equal(f.cart)
					calls += 1
					return 5
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				assert(f.fire(target.Body.Position))
				expect(calls).to.equal(1)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
			end)
		end)

		it("uses the driver's canonical owner cart and preserves fractional future hits", function()
			fixture(function(f)
				local calls, now = 0, 100
				Sleep.SetNowProvider(function()
					return now
				end)
				Sleep.SetCartHitMultiplierResolver(function(cart)
					expect(cart).to.equal(f.cart)
					expect(cart:GetAttribute("OwnerUserId")).to.equal(f.player.UserId)
					calls += 1
					return 1.25
				end)
				Sleep.SetRequiredHitsResolver(function(id)
					expect(id).to.equal(f.template.Name)
					return 5
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				Roaming.Pause(target)
				for hit = 1, 4 do
					now += 2
					assert(f.fire(target.Body.Position))
					expect(select(2, World.GetWorldRecord(target))).to.equal(
						if hit == 4 then "WorldSleeping" else "WorldAwake"
					)
				end
				expect(calls).to.equal(4)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
			end)
		end)

		it("does not apply cart power to a handheld future fixture", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				f.equip()
				local calls, now = 0, 200
				Sleep.SetNowProvider(function()
					return now
				end)
				Sleep.SetRequiredHitsResolver(function()
					return 2
				end)
				Sleep.SetCartHitMultiplierResolver(function()
					calls += 1
					return 5
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				Roaming.Pause(target)
				assert(f.fire(target.Body.Position))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
				now += 2
				assert(f.fire(target.Body.Position))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				expect(calls).to.equal(0)
			end)
		end)

		it("rejected, duplicate and obstructed shots do not add sleep damage or read team power", function()
			fixture(function(f)
				local calls, now = 0, 300
				Sleep.SetNowProvider(function()
					return now
				end)
				Sleep.SetRequiredHitsResolver(function()
					return 2
				end)
				Sleep.SetCartHitMultiplierResolver(function()
					calls += 1
					return 1
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				Roaming.Pause(target)
				local wall = f.part(f.parent, "HitPowerCover", f.origin + Vector3.new(0, 0, -15), Vector3.new(8, 8, 1))
				assert(f.fire(target.Body.Position))
				expect(calls).to.equal(0)
				wall:Destroy()
				now += 2
				local intent = {
					CameraOrigin = f.origin,
					CameraDirection = (target.Body.Position - f.origin).Unit,
					RequestId = 100,
				}
				assert(f.fire(intent))
				expect(calls).to.equal(1)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
				now += 2
				expect(select(2, f.fire(intent))).to.equal("duplicate request")
				expect(calls).to.equal(1)
				intent.RequestId = 101
				assert(f.fire(intent))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		it("resets accumulated sleep damage after the same target wakes", function()
			fixture(function(f)
				local now = 400
				Sleep.SetNowProvider(function()
					return now
				end)
				Sleep.SetRequiredHitsResolver(function()
					return 2.5
				end)
				Sleep.SetCartHitMultiplierResolver(function()
					return 1.25
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				Roaming.Pause(target)
				for cycle = 1, 2 do
					for hit = 1, 2 do
						now += 2
						assert(f.fire(target.Body.Position))
						expect(select(2, World.GetWorldRecord(target))).to.equal(
							if hit == 2 then "WorldSleeping" else "WorldAwake"
						)
					end
					if cycle == 1 then
						assert(World.ResumeWorld(target))
						Roaming.Pause(target)
					end
				end
			end)
		end)
	end)

	describe("Phase 1B mounted aimed sleep shot", function()
		it("ends a non-piercing shot at a decoy without sleeping the real owner", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				local state = DecoySplit.CreateState(0)
				local function createVisual(_, decoyId, encounterId, localFrame, size)
					local model = Instance.new("Model")
					model.Name = decoyId
					model:SetAttribute("EffectKind", "Decoy")
					model:SetAttribute("DecoyId", decoyId)
					model:SetAttribute("EncounterId", encounterId)
					local visual = Instance.new("Part")
					visual.Name, visual.Size, visual.Anchored = "Visual", Vector3.new(2, 4, 2), true
					visual.CanCollide, visual.CanTouch, visual.CanQuery = false, false, false
					visual.Parent = model
					model.PrimaryPart = visual
					local proxy = Instance.new("Part")
					proxy.Name, proxy.Size, proxy.CFrame = "HitProxy", size, model:GetPivot() * localFrame
					proxy.Transparency, proxy.Anchored = 1, true
					proxy.CanCollide, proxy.CanTouch, proxy.CanQuery = false, false, true
					proxy:SetAttribute("EffectKind", "Decoy")
					proxy:SetAttribute("DecoyId", decoyId)
					proxy:SetAttribute("EncounterId", encounterId)
					proxy.Parent = model
					return { Model = model, HitProxy = proxy }
				end
				local context = {
					Authorized = true,
					LifecycleEligible = true,
					RuntimeId = target:GetAttribute("ItemId"),
					BrainrotId = target:GetAttribute("BrainrotId"),
					Position = target:GetPivot().Position,
					Forward = -Vector3.zAxis,
					CourseDirection = -Vector3.zAxis,
					Candidates = {
						{ UserId = f.player.UserId, Character = f.character, Position = f.origin },
					},
					Sensing = true,
					CanSeeCandidate = function()
						return true
					end,
					GetHitEnvelope = function()
						return target:GetPivot(), Vector3.new(2, 4, 2)
					end,
					ResolvePlacement = function(pivot)
						return pivot
					end,
					ResolveFollowPose = function(_, pivot)
						return pivot
					end,
					LaneChoice = 0,
					CreateVisual = createVisual,
				}
				local result = DecoySplit.TryStart(target, state, context, 100, DecoyConfig)
				assert(result.Started, result.Reason)
				local _, front = next(state.decoys)
				front.Model:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, -12)))
				local beforeCargo = Cargo:GetCargoCount(f.cart)
				local shot, reason = f.fireRay(f.origin, -Vector3.zAxis)
				assert(shot, reason)
				expect((shot.Endpoint - (f.origin - Vector3.zAxis * 11)).Magnitude < 0.01).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
				expect(target:GetAttribute("Captured")).to.equal(false)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(beforeCargo)
				expect(DecoySplit.GetDiagnostics().ActiveDecoys).to.equal(1)
				DecoySplit.Interrupt(target, state, 101, "TestCleanup")
			end)
		end)

		it("keeps a concealed brainrot directly hittable by the authoritative shot", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				target:SetAttribute(
					"BrainrotCamouflageSnapshot",
					Http:JSONEncode({
						v = 1,
						runtimeId = target:GetAttribute("ItemId"),
						revision = 1,
						active = true,
						cycleStart = workspace:GetServerTimeNow() - 1.5,
					})
				)
				local shot, reason = f.fire(target.Body.Position)
				assert(shot, reason)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				expect(target.Body.CanQuery).to.equal(true)
			end)
		end)

		it("driver hit sleeps in place without reeling, deletion or cargo gain; later shots do not wake it", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				local pose, scale = target:GetPivot(), target:GetScale()
				local shot, reason = f.fire(target.Body.Position)
				assert(shot, reason)
				expect(shot.Origin).to.equal(f.origin)
				-- Task B stops at the first centred logical-box intersection (25 - 6),
				-- not the old physical surface (25 - 2).
				expect(math.abs((shot.Endpoint - f.origin).Magnitude - 19) < 0.01).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				expect(target:GetAttribute("BrainrotDisplayState")).to.equal("Sleeping")
				expect(target:FindFirstChild("BrainrotSleepIndicator", true)).to.equal(nil)
				task.wait(1.1)
				assert(f.fire(f.origin + Vector3.new(100, 0, 0)), "A cooldown-separated miss should fire")
				task.wait(2.1)
				expect(target.Parent).to.equal(workspace.Runtime.Brainrots)
				expect(target:GetPivot()).to.equal(pose)
				expect(target:GetScale()).to.equal(scale)
				expect(target.Body.CanCollide).to.equal(true)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				for _, item in target:GetDescendants() do
					expect(item:IsA("Beam") or item.Name == "CapturedNet").to.equal(false)
				end
			end)
		end)

		it("aimed miss reaches range without selecting a nearby brainrot", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(8, 0, -20))
				local shot = f.fire(f.origin + Vector3.new(0, 0, -100))
				assert(shot, "Miss must still be accepted")
				expect(shot.Endpoint).to.equal(f.origin + Vector3.new(0, 0, -60))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("first wall blocks sleep and determines the visible shot endpoint", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -35))
				f.part(f.parent, "Wall", f.origin + Vector3.new(0, 0, -12), Vector3.new(15, 15, 2))
				local shot = f.fire(target.Body.Position)
				assert(shot, "Blocked shot is an accepted miss")
				expect(shot.Endpoint).to.equal(f.origin + Vector3.new(0, 0, -11))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("sleeping bodies obstruct a shot without waking or resleeping them or hitting through them", function()
			fixture(function(f)
				local front = f.spawn(f.origin + Vector3.new(0, 0, -15))
				local back = f.spawn(f.origin + Vector3.new(0, 0, -35))
				expect(World.TrySleep(front)).to.equal(true)
				expect(front:FindFirstChild("BrainrotSleepIndicator", true)).to.equal(nil)
				assert(f.fire(back.Body.Position), "Shot should be accepted")
				expect(front:FindFirstChild("BrainrotSleepIndicator", true)).to.equal(nil)
				expect(select(2, World.GetWorldRecord(back))).to.equal("WorldAwake")
			end)
		end)

		it("unregistered lookalike displays cannot become sleeping world targets", function()
			fixture(function(f)
				local display = f.template:Clone()
				display:SetAttribute("BrainrotId", f.template.Name)
				display:SetAttribute("ItemId", "DISPLAY_NOT_WORLD")
				display:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, -20)))
				display.Parent = f.parent
				local shot = f.fire(display.Body.Position)
				assert(shot, "Display obstruction still produces a shot")
				expect(display:GetAttribute("Captured")).to.equal(nil)
				expect(display:FindFirstChild("BrainrotSleepIndicator")).to.equal(nil)
			end)
		end)

		it("range remains 60 studs and cannot sleep a distant target", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -70))
				local shot = f.fire(target.Body.Position)
				assert(shot, "Out-of-range aim is an accepted miss")
				expect((shot.Endpoint - shot.Origin).Magnitude).to.equal(60)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("uses one server-resolved immutable profile and rejects a repeated shot identity", function()
			fixture(function(f)
				local currentTime = 10
				Sleep.SetNowProvider(function()
					return currentTime
				end)
				local selectedProfile = {
					status = "Ready",
					weaponId = "TEST_LONGSHOT",
					definitionRevision = 1,
					rangeStuds = 81,
					fireIntervalSeconds = 1.08,
					projectileSpeedStudsPerSecond = 88,
					projectileSpeedAuthority = "Gameplay",
					assistAcquireHalfAngleRadians = math.rad(8.64),
					assistRetainHalfAngleRadians = math.rad(16),
				}
				Sleep.SetWeaponProfileResolver(function(player)
					expect(player).to.equal(f.player)
					return selectedProfile, 7
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -70))
				local intent = {
					RequestId = 91,
					CameraOrigin = f.origin,
					CameraDirection = -Vector3.zAxis,
					-- These client fields are intentionally ignored.
					WeaponId = "HRP_FORGED",
					RangeStuds = 9999,
				}
				local shot, reason = Sleep.HandleFireRequest(f.player, intent)
				assert(shot, reason)
				expect(shot.WeaponProfile.weaponId).to.equal("TEST_LONGSHOT")
				expect(shot.WeaponProfile.equipmentRevision).to.equal(7)
				expect(shot.WeaponProfile.rangeStuds).to.equal(81)
				expect(table.isfrozen(shot.WeaponProfile)).to.equal(true)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")

				selectedProfile.rangeStuds = 20
				expect(shot.WeaponProfile.rangeStuds).to.equal(81)
				currentTime = 20
				local duplicate, duplicateReason = Sleep.HandleFireRequest(f.player, intent)
				expect(duplicate).to.equal(nil)
				expect(duplicateReason).to.equal("duplicate request")
			end)
		end)

		it("rejects malformed, nonfinite and zero-direction aim without spending the valid shot", function()
			fixture(function(f)
				for _, aim in
					{
						false,
						{},
						"target",
						f.origin,
						Vector3.new(0 / 0, 0, 0),
						Vector3.new(math.huge, 0, 0),
					}
				do
					local shot = f.fire(aim)
					expect(shot).to.equal(nil)
				end
				expect(f.fire(nil)).to.equal(nil)
				assert(f.fire(f.origin + Vector3.new(0, 0, -40)), "Invalid intent must not consume the cooldown")
			end)
		end)

		it("server cooldown rejects rapid repeats and permits another shot after one second", function()
			fixture(function(f)
				assert(f.fire(f.origin + Vector3.new(0, 0, -100)), "First shot rejected")
				local target = f.spawn(f.origin + Vector3.new(15, 0, -20))
				local shot, reason = f.fire(target.Body.Position)
				expect(shot).to.equal(nil)
				expect(reason).to.equal("cooldown")
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
				task.wait(1.05)
				assert(f.fire(target.Body.Position), "Cooldown did not expire")
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		it("retired hunter contexts reject shots with or without a forged hunter identity", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				for _, identity in { f.player.UserId, 123456 } do
					f.cart:SetAttribute("ActiveHunterUserId", identity)
					local shot, reason = f.fire(target.Body.Position)
					expect(shot).to.equal(nil)
					expect(reason).to.equal("not authorized owner driver")
				end
				f.cart:SetAttribute("ActiveHunterUserId", nil)
				expect(f.fire(target.Body.Position)).to.equal(nil)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end, "HunterSeat")
		end)

		it("stranger ownership, stale driver authority and dead characters cannot fire", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				f.ownerRecord.OwnerUserId = 123456
				f.cart:SetAttribute("OwnerUserId", f.player.UserId) -- Client-visible claim supplies no ownership.
				expect(select(2, f.fire(target.Body.Position))).to.equal("no registered owned cart")
				f.ownerRecord.OwnerUserId = f.player.UserId
				f.setAuthorized(false)
				expect(select(2, f.fire(target.Body.Position))).to.equal("not authorized owner driver")
				f.setAuthorized(true)
				f.humanoid.Health = 0
				expect(f.fire(target.Body.Position)).to.equal(nil)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		it("rejects a nested DriverSeat and keeps rejected inputs outside the shot cooldown", function()
			fixture(function(f)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				local nested = Instance.new("Folder")
				nested.Parent = f.cart
				f.seat.Parent = nested
				expect(select(2, f.fire(target.Body.Position))).to.equal("not authorized owner driver")
				f.seat.Parent = f.cart
				assert(f.fire(target.Body.Position), "Rejected driver input must not consume cooldown")
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		it("rejects an unmounted character even when the driver ID and owned cart remain", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				local shot, reason = f.fire(f.origin + Vector3.new(0, 0, -25))
				expect(shot).to.equal(nil)
				expect(reason).to.equal("launcher not equipped")
			end)
		end)

		it("uses the server attachment muzzle, and rejects its removal without accepting a client origin", function()
			fixture(function(f)
				f.muzzle.Name = "MuzzleSupport"
				local attachment = Instance.new("Attachment")
				attachment.Name = "HarpoonOrigin"
				attachment.Position = Vector3.new(3, 1, -2)
				attachment.Parent = f.muzzle
				local actualOrigin = attachment.WorldPosition
				local target = f.spawn(actualOrigin + Vector3.new(0, 0, -25))
				local shot = f.fire(target.Body.Position)
				assert(shot, "Attachment muzzle should fire")
				expect(shot.Origin).to.equal(actualOrigin)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				attachment:Destroy()
				task.wait(1.05)
				local refused, reason = f.fire(actualOrigin + Vector3.new(0, 0, -25))
				expect(refused).to.equal(nil)
				expect(reason).to.equal("no valid HarpoonOrigin")
			end)
		end)

		it("full real cargo fixture still permits sleep shots without changing cargo records", function()
			fixture(function(f)
				for _, group in { "CargoVisuals", "Carts" } do
					if not Physics:IsCollisionGroupRegistered(group) then
						Physics:RegisterCollisionGroup(group)
					end
				end
				for _ = 1, Cargo:GetCargoCapacity(f.cart) do
					assert(Cargo:AddCargo(f.cart, f.template.Name, { Tier = 1 }), "Supported cargo fixture failed")
				end
				expect(Cargo:CanAcceptCargo(f.cart)).to.equal(false)
				local count, revision = Cargo:GetCargoCount(f.cart), Cargo:GetCargoRevision(f.cart)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				assert(f.fire(target.Body.Position), "Full cargo must not block shooting")
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				task.wait(0.5)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(count)
				expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
				expect(target.Parent).to.equal(workspace.Runtime.Brainrots)
			end)
		end)

		it("restored same individual is immediately shootable with cleared sleep presentation", function()
			fixture(function(f)
				local original = f.spawn(f.origin + Vector3.new(0, 0, -25))
				World.TrySleep(original)
				local record = World.GetWorldRecord(original)
				original.Parent = nil
				World.Unregister(original)
				local restored = f.spawn(f.origin + Vector3.new(8, 0, -25), record)
				expect(restored:FindFirstChild("BrainrotSleepIndicator")).to.equal(nil)
				assert(f.fire(restored.Body.Position), "Restored individual must be recapturable")
				local actual, state = World.GetWorldRecord(restored)
				expect(actual.ItemId).to.equal(record.ItemId)
				expect(actual.Metadata.Mutation.Name).to.equal("Preserved")
				expect(state).to.equal("WorldSleeping")
				expect(World.ResumeWorld(restored)).to.equal(true)
				expect(restored:FindFirstChild("BrainrotSleepIndicator")).to.equal(nil)
			end)
		end)
	end)

	describe("Phase 2 shared handheld sleep shot", function()
		it("equipped launcher sleeps a target on foot with no registered cart", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				Carts.GetCartRecord = function()
					return nil
				end
				local tool = f.equip()
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				local shot, reason = f.fire(target.Body.Position)
				assert(shot, reason)
				expect(shot.Origin).to.equal(tool.Handle.Muzzle.WorldPosition)
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
			end)
		end)

		it("backpack, disabled, unmarked and duplicate launchers cannot authorize firing", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				local tool = f.equip()
				local backpack = Instance.new("Backpack")
				backpack.Parent = f.parent
				local aim = f.origin + Vector3.new(0, 0, -25)
				tool.Parent = backpack
				expect(select(2, f.fire(aim))).to.equal("launcher not equipped")
				tool.Parent, tool.Enabled = f.character, false
				expect(select(2, f.fire(aim))).to.equal("launcher not equipped")
				tool.Enabled = true
				tool:SetAttribute("BrainrotSleepLauncher", nil)
				expect(select(2, f.fire(aim))).to.equal("launcher not equipped")
				tool:SetAttribute("BrainrotSleepLauncher", true)
				local second = f.equip()
				expect(select(2, f.fire(aim))).to.equal("multiple launchers equipped")
				second:Destroy()
				assert(f.fire(aim), "Invalid equipment must not consume cooldown")
			end)
		end)

		it("requires the current character's launcher and valid attachment muzzle", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				local tool = f.equip()
				local aim = f.origin + Vector3.new(0, 0, -25)
				tool.Handle.Muzzle:Destroy()
				expect(select(2, f.fire(aim))).to.equal("no valid launcher muzzle")
				tool:Destroy()
				f.equip()
				local oldCharacter = f.character
				local current = Instance.new("Model")
				current.Parent = f.parent
				Instance.new("Humanoid", current).RequiresNeck = false
				f.player.Character = current
				expect(select(2, f.fire(aim))).to.equal("launcher not equipped")
				f.player.Character = oldCharacter
			end)
		end)

		it("other equipped weapons still block handheld use", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				f.equip()
				local other = Instance.new("Tool")
				other.Name, other.Parent = "OtherWeapon", f.character
				expect(select(2, f.fire(f.origin + Vector3.new(0, 0, -25)))).to.equal("using another weapon")
			end)
		end)

		it("nearby cover blocks the real handheld muzzle even when aiming beyond it", function()
			fixture(function(f)
				f.humanoid = f.useOnFootHumanoid()
				f.equip()
				local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
				f.part(f.parent, "NearMuzzleCover", f.origin + Vector3.new(0, 0, -2), Vector3.new(10, 10, 1))
				local shot = f.fire(target.Body.Position)
				assert(shot, "Obstructed shot should still render")
				expect(shot.Endpoint).to.equal(f.origin + Vector3.new(0, 0, -1.5))
				expect(select(2, World.GetWorldRecord(target))).to.equal("WorldAwake")
			end)
		end)

		for _, role in { "DriverSeat" } do
			it(role .. " takes priority over an equipped handheld launcher", function()
				fixture(function(f)
					local tool = f.equip()
					tool.Handle.CFrame += Vector3.new(15, 10, 0)
					local target = f.spawn(f.origin + Vector3.new(0, 0, -25))
					local shot, reason = f.fire(target.Body.Position)
					assert(shot, reason)
					expect(shot.Origin).to.equal(f.muzzle.Position)
					expect(select(2, World.GetWorldRecord(target))).to.equal("WorldSleeping")
				end, role)
			end)
		end

		it("an equipped launcher cannot bypass unauthorized mounted contexts", function()
			fixture(function(f)
				f.equip()
				f.seat.Name = "PassengerSeat"
				expect(select(2, f.fire(f.origin + Vector3.new(0, 0, -25)))).to.equal("not authorized owner driver")
			end)
		end)

		it("mounting, dismounting and re-equipping share the same per-player cooldown", function()
			fixture(function(f)
				local aim = f.origin + Vector3.new(0, 0, -100)
				assert(f.fire(aim), "Mounted shot should fire")
				f.humanoid = f.useOnFootHumanoid()
				local tool = f.equip()
				expect(select(2, f.fire(aim))).to.equal("cooldown")
				tool:Destroy()
				f.equip()
				expect(select(2, f.fire(aim))).to.equal("cooldown")
				task.wait(1.05)
				assert(f.fire(aim), "Handheld should fire after shared cooldown")
				-- Seat re-entry is diagnostic; no client controls are claimed here.
				f.seat.Disabled = false
				f.seat:Sit(f.humanoid)
				task.wait(0.1)
				expect(select(2, f.fire(aim))).to.equal("cooldown")
			end)
		end)

		it("authoritative carry predicate blocks both contexts without consuming cooldown", function()
			fixture(function(f)
				Sleep.SetCarryingPredicate(function(player)
					return player == f.player
				end)
				local aim = f.origin + Vector3.new(0, 0, -25)
				expect(select(2, f.fire(aim))).to.equal("carrying")
				f.humanoid = f.useOnFootHumanoid()
				f.equip()
				expect(select(2, f.fire(aim))).to.equal("carrying")
				Sleep.SetCarryingPredicate(function()
					return false
				end)
				assert(f.fire(aim), "Dropping must not leave a false cooldown")
			end)
		end)
	end)
	for _, case in { { 125, true }, { 125.05, false } } do
		it("enforces approved C3 free-aim visible surface reference at " .. tostring(case[1]) .. " studs", function()
			fixture(function(f)
				local profile = require(game.ReplicatedStorage.Shared.Utility.WeaponStats).Resolve("WPN_C03")
				Sleep.SetWeaponProfileResolver(function()
					return profile, 13
				end)
				local target = f.spawn(f.origin + Vector3.new(0, 0, -100))
				local direction = (target.Body.Position - f.origin).Unit
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { target }
				local nearHit = workspace:Raycast(f.origin, direction * 200, params)
				assert(nearHit, "Native visible model surface reference required")
				target:PivotTo(target:GetPivot() + direction * (case[1] - nearHit.Distance))
				local reference = workspace:Raycast(f.origin, direction * 200, params)
				assert(
					reference and math.abs(reference.Distance - case[1]) < 0.001,
					"Measured native reference must sit at tested range"
				)
				-- Free aim needs both the enlarged hunt-envelope intersection and
				-- the actual visible camera reference within muzzle range. Testing
				-- only the centre or only the enlarged box would exercise a different gate.
				local shot, reason = f.fire(target.Body.Position)
				assert(shot, reason)
				expect(select(2, World.GetWorldRecord(target))).to.equal(
					if case[2] then "WorldSleeping" else "WorldAwake"
				)
			end)
		end)
	end

	it("rejects an unauthorized selected wild target without sleeping or retargeting", function()
		fixture(function(f)
			local target = f.spawn(f.origin + Vector3.new(4, 0, -30))
			local nearer = f.spawn(f.origin + Vector3.new(-5, 0, -8))
			local calls = 0
			Sleep.SetRegionAccessValidator(function(player, model)
				expect(player).to.equal(f.player)
				expect(model).to.equal(target)
				calls += 1
				return false, "RegionAccessRequired"
			end)
			local shot, reason = f.fire({
				CameraOrigin = f.origin,
				CameraDirection = (target.Body.Position - f.origin).Unit,
				CrosshairDirection = -Vector3.zAxis,
				ShotMode = "ASSIST_LOCK",
				LockedTargetId = target:GetAttribute("ItemId"),
				LockedTargetKind = "Brainrot",
			})
			expect(shot).to.equal(nil)
			expect(reason).to.equal("RegionAccessRequired")
			local _, state = World.GetWorldRecord(target)
			expect(state).to.equal("WorldAwake")
			expect(calls > 0).to.equal(true)
			expect(select(2, World.GetWorldRecord(nearer))).to.equal("WorldAwake")
		end)
	end)
end
