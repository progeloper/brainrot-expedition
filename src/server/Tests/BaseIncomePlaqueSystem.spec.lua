--!nocheck
-- Phase13 fixture provides48 physical platforms; ground-floor assertions remain12.

return function()
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config.BaseLayoutConfig)
	local System = require(script.Parent.Parent.Systems.BaseIncomePlaqueSystem)
	local Presentation = require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation)
	-- Playtest Fixes 2 Part C raises the cash-pad touch volume (released 14 Nov 2026).
	local Fixes2Flags = require(game:GetService("ReplicatedStorage").Shared.Config.PlaytestFixes2Flags)
	local Fixes2 = require(game:GetService("ReplicatedStorage").Shared.Config.PlaytestFixes2)
	local SENSOR_H = if Fixes2Flags.Part("CashPads") then Fixes2.CashPads.TouchHeightStuds else 1

	local function fixture(callback, fixtureUserId, rotationDegrees)
		System:Destroy()
		local owned = {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local base = own(Instance.new("Model"))
		base.Name = "Phase5DLayoutSpec"
		base:SetAttribute("BaseId", "Base_Layout_Spec")
		base:SetAttribute("OwnerUserId", fixtureUserId or 8101)
		base.Parent = workspace
		local floor = Instance.new("Part")
		floor.Name = "BaseFloor"
		floor.Anchored = true
		floor.Size = Vector3.new(60, 1, 50)
		floor.CFrame = CFrame.new(12000, 20, 12000) * CFrame.Angles(0, math.rad(rotationDegrees or 25), 0)
		floor.Parent = base
		local cartSpawn = Instance.new("Part")
		cartSpawn.Name = "CartSpawn"
		cartSpawn.Anchored = true
		cartSpawn.CFrame = floor.CFrame * CFrame.new(0, 1, -22)
		cartSpawn.Parent = base
		local slots = {}
		for index = 1, 48 do
			local platform = Instance.new("Part")
			platform.Name = "Slot_" .. index
			platform:SetAttribute("SlotIndex", index)
			platform.Anchored = true
			platform.Size = Vector3.new(4, 0.5, 4)
			platform.CFrame = floor.CFrame * CFrame.new(index, 0.75, index)
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name = "BrainrotPlacement"
			marker.Position = Vector3.new(0, 0.25, 0)
			marker.Parent = platform
			slots[index] = table.freeze({ Index = index, Platform = platform, Marker = marker })
		end
		base:PivotTo(floor.CFrame)
		base:SetAttribute("BaseOwnershipRevision", 1)
		local presentationContext = {OwnerUserId=fixtureUserId or 8101,AssignmentRevision=1,ProfileReady=true}
		local function applyCapacity(capacity)
			local token = assert(Presentation.Begin(base, capacity, presentationContext))
			for index, slot in slots do Presentation.BindSlot(slot.Platform, base, index, token) end
			Presentation.Publish(base, token, capacity)
		end
		applyCapacity(48)

		local character = Instance.new("Model")
		character.Name = "OwnerCharacter"
		character.Parent = workspace
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = character
		local limb = Instance.new("Part")
		limb.Name = "LeftFoot"
		limb.Parent = character
		local otherLimb = Instance.new("Part")
		otherLimb.Name = "RightFoot"
		otherLimb.Parent = character
		local player = {
			Name = "Owner",
			UserId = fixtureUserId or 8101,
			Parent = Players,
			Character = character,
		}
		local outsiderCharacter = Instance.new("Model")
		outsiderCharacter.Name = "OutsiderCharacter"
		outsiderCharacter.Parent = workspace
		local outsiderHumanoid = Instance.new("Humanoid")
		outsiderHumanoid.Parent = outsiderCharacter
		local outsiderLimb = Instance.new("Part")
		outsiderLimb.Parent = outsiderCharacter
		local outsider = {
			Name = "Outsider",
			UserId = 8102,
			Parent = Players,
			Character = outsiderCharacter,
		}

		local storage = { Base = base, Records = {} }
		function storage:GetPlatformRecord(platformId)
			return self.Records[platformId]
		end
		local observer
		local storageApi = {}
		function storageApi:GetRegisteredPlatforms(candidate)
			return if candidate == base then slots else nil
		end
		function storageApi:GetStorageForPlayer(subject)
			return if subject == player then storage else nil
		end
		function storageApi:ObserveStorage(value)
			observer = value
			return function()
				observer = nil
			end
		end
		local assigned, releasing
		local baseApi = {}
		function baseApi:GetRegisteredBases()
			return { base }
		end
		function baseApi:GetBase(subject)
			return if subject == player then base else nil
		end
		function baseApi:IsOwner(subject, candidate)
			return subject == player and candidate == base
		end
		function baseApi:SubscribeAssignments(onAssigned, onReleasing)
			assigned, releasing = onAssigned, onReleasing
			return { Disconnect = function() end }
		end

		local now = 10
		local claimCalls = 0
		local snapshots = {}
		for platformId = 1, 12 do
			snapshots[platformId] = {
				Occupied = false,
				IndividualId = nil,
				CatalogueId = nil,
				RatePerSecond = 0,
				UnclaimedCashSnapshot = 0,
				SnapshotServerTime = now,
				Revision = 1,
			}
		end
		local incomeApi = {}
		local refreshBatches = {}
		function incomeApi:GetPlatformIncomeSnapshot(_, platformId)
			return snapshots[platformId]
		end
		function incomeApi:SyncPlatformSnapshot(_, platformId)
			return snapshots[platformId]
		end
		function incomeApi:SyncPlatformSnapshots(requests)
			table.insert(refreshBatches, #requests)
			local result = {}
			for index, request in requests do
				result[index] = snapshots[request.PlatformId]
			end
			return result
		end
		function incomeApi:TryClaimPlatform(subject, _, platformId)
			claimCalls += 1
			if subject ~= player then
				return { ok = false, code = "NotOwner" }
			end
			local snapshot = table.clone(snapshots[platformId])
			snapshot.UnclaimedCashSnapshot = 0.25
			snapshot.SnapshotServerTime = now
			snapshot.Revision += 1
			snapshots[platformId] = snapshot
			return { ok = true, code = "Collected", paid = 4, remainingExact = 0.25 }
		end

		local heartbeatCallback
		assert(System:Init({
			Base = baseApi,
			Storage = storageApi,
			Income = incomeApi,
			Now = function()
				return now
			end,
			GetPlayerByUserId = function(userId)
				return if userId == player.UserId then player else nil
			end,
			GetPlayerFromCharacter = function(candidate)
				if candidate == character then
					return player
				elseif candidate == outsiderCharacter then
					return outsider
				end
				return nil
			end,
			Heartbeat = {
				Connect = function(_, handler)
					heartbeatCallback = handler
					return { Disconnect = function() end }
				end,
			},
		}))
		assert(System:Start())
		local ok, failure = xpcall(function()
			callback({
				Base = base,
				Context = presentationContext,
				ApplyCapacity = applyCapacity,
				Floor = floor,
				Slots = slots,
				Storage = storage,
				Observer = function()
					return observer
				end,
				Assigned = function()
					assigned(player, base)
				end,
				Releasing = function()
					releasing(player, base)
				end,
				Player = player,
				Character = character,
				Limb = limb,
				OtherLimb = otherLimb,
				Outsider = outsider,
				OutsiderLimb = outsiderLimb,
				SetTime = function(value)
					now = value
				end,
				ClaimCalls = function()
					return claimCalls
				end,
				Snapshots = snapshots,
				RefreshBatches = refreshBatches,
				Step = function(dt)
					heartbeatCallback(dt)
				end,
			})
		end, debug.traceback)
		System:Destroy()
		character:Destroy()
		outsiderCharacter:Destroy()
		for index = #owned, 1, -1 do
			owned[index]:Destroy()
		end
		assert(ok, failure)
	end

	describe("Phase 5D physical base and income plaques", function()
		it("hides complete external cash-pad groups19–48 at committed capacity18", function()
			fixture(function(f)
				f.ApplyCapacity(18)
				f.Snapshots[19] = table.clone(f.Snapshots[1])
				f.Snapshots[19].Occupied = true
				f.Snapshots[19].UnclaimedCashSnapshot = 99
				f.Observer().OnCommitted(f.Player, f.Storage)
				for index, plaque in System:GetPlaques(f.Base) do
					expect(plaque.Transparency).to.equal(if index <= 18 then 0 else 1)
					expect(plaque.CanQuery).to.equal(index <= 18)
					expect(plaque.TouchSensor.CanTouch).to.equal(index <= 18)
					expect(plaque.TouchSensor.Transparency).to.equal(1)
					if index > 18 then
						expect(plaque.AmountSurfaceGui.Enabled).to.equal(false)
						expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("")
					end
				end
				expect(System:HandlePlaqueTouch(System:GetPlaques(f.Base)[19], f.Limb).code).to.equal("InvalidPlatform")
				expect(f.ClaimCalls()).to.equal(0)
			end)
		end)
		it("keeps all twelve pad fronts and touch envelopes aligned at multiple base rotations", function()
			for _, rotation in { 0, 90, 217 } do
				fixture(function(f)
					for id, pad in System:GetPlaques(f.Base) do
						local platform = f.Slots[id].Platform
						expect(pad.CFrame.LookVector:Dot(platform.CFrame.LookVector) > 0.999).to.equal(true)
						local toPad = pad.Position - platform.Position
						expect(toPad:Dot(platform.CFrame.LookVector) > 0).to.equal(true)
						local localSensor = pad.CFrame:PointToObjectSpace(pad.TouchSensor.Position)
						expect(math.abs(localSensor.X) < 0.001).to.equal(true)
						expect(math.abs(localSensor.Z) < 0.001).to.equal(true)
						expect(localSensor.Y > 0).to.equal(true)
						expect(pad:FindFirstChildWhichIsA("ProximityPrompt", true)).to.equal(nil)
					end
				end, nil, rotation)
			end
		end)
		it("refreshes settled cash for a bound negative Studio player ID", function()
			fixture(function(f)
				f.Snapshots[1].Occupied = true
				f.Snapshots[1].RatePerSecond = 1.8
				f.Observer().OnBound(f.Player, f.Storage)
				local plaque = System:GetPlaques(f.Base)[1]
				expect(plaque:GetAttribute("BaseOwnerUserId")).to.equal(-2)
				f.Snapshots[1].UnclaimedCashSnapshot = 9
				f.Snapshots[1].Revision += 1
				f.Step(5)
				expect(plaque:GetAttribute("UnclaimedCashSnapshot")).to.equal(9)
				expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("$9")
			end, -2)
		end)
		it("refreshes all bound plaques in one income batch", function()
			fixture(function(f)
				table.clear(f.RefreshBatches)
				f.Observer().OnBound(f.Player, f.Storage)
				expect(#f.RefreshBatches).to.equal(1)
				expect(f.RefreshBatches[1]).to.equal(48)
			end)
		end)
		it("builds the exact legacy two-row layout in base-local space and remains idempotent", function()
			fixture(function(f)
				expect(f.Base:GetAttribute("AuthoredBaseLayout")).to.equal(nil)
				expect(f.Floor.Name).to.equal("BaseFloor")
				local root = f.Base:GetAttribute("Phase5DLayoutPivot")
				expect(typeof(root)).to.equal("CFrame")
				expect(f.Floor.Size.X).to.equal(36)
				expect(f.Floor.Size.Z).to.equal(32)
				local plaques = System:GetPlaques(f.Base)
				expect(#plaques).to.equal(48)
				for platformId = 1, 12 do
					local slot = f.Slots[platformId]
					expect(math.abs(slot.Platform.Size.X - 3 / math.sqrt(2)) < 1e-6).to.equal(true)
					expect(math.abs(slot.Platform.Size.Z - 3 / math.sqrt(2)) < 1e-6).to.equal(true)
					local localPlatform = root:PointToObjectSpace(slot.Platform.Position)
					local expectedSide = if platformId <= 6 then -1 else 1
					local row = if platformId <= 6 then platformId else platformId - 6
					expect(math.abs(localPlatform.X - expectedSide * 7.25) < 0.01).to.equal(true)
					expect(math.abs(localPlatform.Z - Config.PLATFORM_Z_CENTERS[row]) < 0.01).to.equal(true)
					local plaque = plaques[platformId]
					expect(plaque.Name).to.equal("IncomePlaque_" .. platformId)
					expect(plaque:GetAttribute("PlatformId")).to.equal(platformId)
					expect(CollectionService:HasTag(plaque, "BrainrotIncomePlaque")).to.equal(true)
					expect(plaque.Size).to.equal(Vector3.new(3.5, 0.18, 2.25))
					expect(plaque.CFrame.UpVector:Dot(Vector3.yAxis) >= 0.999).to.equal(true)
					expect(plaque.Color).to.equal(Color3.fromRGB(60, 255, 90))
					-- Current live presentation uses the saved uniform stud material.
					expect(plaque.Material).to.equal(Enum.Material.Glacier)
					expect(plaque.MaterialVariant).to.equal("Environment_Saved_Studs_13719188279")
					expect(plaque:GetAttribute("StudsPerTile")).to.equal(4)
					expect(plaque.Transparency).to.equal(0)
					expect(plaque.CanCollide).to.equal(false)
					expect(plaque.CanTouch).to.equal(false)
					expect(plaque.Anchored).to.equal(true)
					local sensor = plaque:FindFirstChild("TouchSensor")
					expect(sensor and sensor:IsA("BasePart")).to.equal(true)
					expect(sensor.Size).to.equal(Vector3.new(3.5, SENSOR_H, 2.25))
					expect(sensor.Transparency).to.equal(1)
					expect(sensor.CanCollide).to.equal(false)
					expect(sensor.CanTouch).to.equal(true)
					expect(sensor.CanQuery).to.equal(false)
					local localPlaque = root:PointToObjectSpace(plaque.Position)
					local expectedX = expectedSide * 4.514339828220179
					expect(math.abs(localPlaque.X - expectedX) < 0.01).to.equal(true)
					local floorTop = root:PointToObjectSpace(f.Floor.Position).Y + f.Floor.Size.Y / 2
					expect(math.abs(localPlaque.Y - 0.11 - floorTop) < 0.01).to.equal(true)
					expect(math.abs(localPlaque.Z - Config.PLATFORM_Z_CENTERS[row]) < 0.01).to.equal(true)
					local localSensor = root:PointToObjectSpace(sensor.Position)
					expect(math.abs(localSensor.X - expectedX) < 0.01).to.equal(true)
					local surface = plaque:FindFirstChild("AmountSurfaceGui")
					expect(surface and surface:IsA("SurfaceGui")).to.equal(true)
					expect(surface.Adornee).to.equal(plaque)
					expect(surface.Face).to.equal(Enum.NormalId.Top)
					expect(surface.SizingMode).to.equal(Enum.SurfaceGuiSizingMode.FixedSize)
					expect(surface.CanvasSize).to.equal(Vector2.new(112, 200))
					expect(surface.MaxDistance).to.equal(35)
					expect(surface.AlwaysOnTop).to.equal(false)
					expect(surface.LightInfluence).to.equal(0)
					expect(surface.Brightness).to.equal(1)
					expect(surface.ClipsDescendants).to.equal(true)
					expect(surface.ZOffset).to.equal(0)
					expect(surface.Active).to.equal(false)
					expect(surface.Enabled).to.equal(false)
					local amount = surface:FindFirstChild("AmountLabel")
					expect(amount and amount:IsA("TextLabel")).to.equal(true)
					expect(amount.Font).to.equal(Enum.Font.FredokaOne)
					expect(amount.AnchorPoint).to.equal(Vector2.new(0.5, 0.5))
					expect(amount.Position).to.equal(UDim2.fromScale(0.5, 0.5))
					expect(amount.Size).to.equal(UDim2.fromOffset(190, 72))
					expect(amount.TextScaled).to.equal(false)
					expect(amount.TextSize).to.equal(36)
					expect(amount.TextWrapped).to.equal(false)
					expect(amount.Rotation).to.equal(-90)
					expect(amount.Text).to.equal("")
					expect(amount:FindFirstChildOfClass("UITextSizeConstraint")).to.equal(nil)
					expect(amount:FindFirstChildOfClass("UIScale")).to.equal(nil)
					expect(amount.AmountStroke.Color).to.equal(Color3.fromRGB(8, 8, 10))
					expect(amount.AmountStroke.Thickness).to.equal(2)
					expect(amount.AmountStroke.ApplyStrokeMode).to.equal(Enum.ApplyStrokeMode.Contextual)
					expect(plaque:FindFirstChild("AmountBillboard")).to.equal(nil)
					expect(plaque:FindFirstChild("IncomeSurfaceGui")).to.equal(nil)
				end
				local pillarCFrames = {}
				for _, descendant in f.Base.Phase5DInterior:GetChildren() do
					if descendant:IsA("BasePart") and descendant.Name:match("^BasePillar_") then
						expect(descendant.Size).to.equal(Vector3.new(0.625, 10, 0.625))
						pillarCFrames[descendant.Name] = descendant.CFrame
					end
				end
				expect(#f.Base.Phase5DInterior:GetChildren() > 0).to.equal(true)
				assert(System:BuildBase(f.Base, f.Player.UserId))
				expect(#System:GetPlaques(f.Base)).to.equal(48)
				expect(#f.Base.IncomePlaques:GetChildren()).to.equal(48)
				for name, oldCFrame in pillarCFrames do
					local pillar = f.Base.Phase5DInterior:FindFirstChild(name)
					expect(pillar and pillar:IsA("BasePart")).to.equal(true)
					expect(pillar.Size).to.equal(Vector3.new(0.625, 10, 0.625))
					expect(pillar.CFrame).to.equal(oldCFrame)
				end
			end)
		end)

		it("allows subsequent steps when a TouchEnded notification was missed", function()
			fixture(function(f)
				local plaque = System:GetPlaques(f.Base)[1]
				expect(System:HandlePlaqueTouch(plaque, f.Limb).code).to.equal("Collected")
				f.SetTime(11)
				expect(System:HandlePlaqueTouch(plaque, f.Limb).code).to.equal("Collected")
				f.SetTime(12)
				expect(System:HandlePlaqueTouch(plaque, f.OtherLimb).code).to.equal("Collected")
				expect(plaque:GetAttribute("ClaimRevision")).to.equal(3)
			end)
		end)

		it("routes one living owner touch to the authoritative claim and absorbs limb spam", function()
			fixture(function(f)
				f.Snapshots[4].Occupied = true
				local plaque = System:GetPlaques(f.Base)[4]
				local first = System:HandlePlaqueTouch(plaque, f.Limb)
				expect(first.code).to.equal("Collected")
				expect(f.ClaimCalls()).to.equal(1)
				expect(plaque:GetAttribute("UnclaimedCashSnapshot")).to.equal(0.25)
				expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("$0")
				expect(plaque.AmountSurfaceGui.Enabled).to.equal(true)
				expect(plaque:GetAttribute("LastClaimUserId")).to.equal(f.Player.UserId)
				expect(plaque:GetAttribute("LastClaimAmount")).to.equal(4)
				expect(plaque:GetAttribute("ClaimResetAmount")).to.equal(0.25)
				expect(plaque:GetAttribute("ClaimRevision")).to.equal(1)
				expect(System:HandlePlaqueTouch(plaque, f.OtherLimb).code).to.equal("Busy")
				expect(f.ClaimCalls()).to.equal(1)
				f.SetTime(11)
				expect(System:HandlePlaqueTouch(plaque, f.Limb).code).to.equal("Collected")
				expect(f.ClaimCalls()).to.equal(2)
				local denied = System:HandlePlaqueTouch(plaque, f.OutsiderLimb)
				expect(denied.code).to.equal("NotOwner")
				expect(f.ClaimCalls()).to.equal(3)
				expect(plaque:GetAttribute("ClaimRevision")).to.equal(2)
			end)
		end)

		it("repairs duplicate/orphan plaques and refreshes only server snapshots", function()
			fixture(function(f)
				local duplicate = Instance.new("Part")
				duplicate.Name = "IncomePlaque_1"
				duplicate:SetAttribute("PlatformId", 1)
				duplicate.Parent = f.Base
				CollectionService:AddTag(duplicate, "BrainrotIncomePlaque")
				local orphan = Instance.new("Part")
				orphan.Name = "IncomePlaque_99"
				orphan:SetAttribute("PlatformId", 99)
				orphan.Parent = f.Base
				CollectionService:AddTag(orphan, "BrainrotIncomePlaque")
				assert(System:BuildBase(f.Base, f.Player.UserId))
				expect(duplicate.Parent == nil or orphan.Parent == nil).to.equal(true)
				expect(#System:GetPlaques(f.Base)).to.equal(48)
				for platformId = 1, 12 do
					local itemId = "deposited-" .. platformId
					f.Storage.Records[platformId] = {
						ItemId = itemId,
						BrainrotId = "BRT_007",
					}
					f.Snapshots[platformId] = {
						Occupied = true,
						IndividualId = itemId,
						CatalogueId = "BRT_007",
						RatePerSecond = 2,
						UnclaimedCashSnapshot = 5.5,
						SnapshotServerTime = 12,
						Revision = 3,
					}
				end
				f.Observer().OnCommitted(f.Player, f.Storage)
				local refreshedPlaques = System:GetPlaques(f.Base)
				for platformId = 1, 12 do
					local plaque = refreshedPlaques[platformId]
					expect(plaque:GetAttribute("IncomeOccupied")).to.equal(true)
					expect(plaque:GetAttribute("UnclaimedCashSnapshot")).to.equal(5.5)
					expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("$5")
					expect(plaque.AmountSurfaceGui.Enabled).to.equal(true)
					local surfaces = 0
					local labels = 0
					for _, child in plaque:GetChildren() do
						if child:IsA("SurfaceGui") and child.Name == "AmountSurfaceGui" then
							surfaces += 1
							for _, descendant in child:GetDescendants() do
								if descendant:IsA("TextLabel") and descendant.Name == "AmountLabel" then
									labels += 1
								end
							end
						end
					end
					expect(surfaces).to.equal(1)
					expect(labels).to.equal(1)
					expect(plaque:FindFirstChild("AmountBillboard")).to.equal(nil)
				end
				f.Releasing()
				expect(#System:GetPlaques(f.Base)).to.equal(0)
				expect(refreshedPlaques[2]:GetAttribute("BaseOwnerUserId")).to.equal(0)
			end)
		end)

		it("hides empty-platform cash even during legacy snapshot arrival", function()
			fixture(function(f)
				local plaque = System:GetPlaques(f.Base)[1]
				f.Snapshots[1] = {
					Occupied = false,
					IndividualId = nil,
					CatalogueId = nil,
					RatePerSecond = 0,
					UnclaimedCashSnapshot = 80,
					SnapshotServerTime = 10,
					Revision = 2,
				}
				f.Observer().OnCommitted(f.Player, f.Storage)
				expect(plaque.AmountSurfaceGui.Enabled).to.equal(false)
				expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("")

				f.Snapshots[1] = {
					Occupied = false,
					IndividualId = nil,
					CatalogueId = nil,
					RatePerSecond = 0,
					UnclaimedCashSnapshot = 0,
					SnapshotServerTime = 11,
					Revision = 3,
				}
				f.Observer().OnCommitted(f.Player, f.Storage)
				expect(plaque.AmountSurfaceGui.Enabled).to.equal(false)
				expect(plaque.AmountSurfaceGui.AmountLabel.Text).to.equal("")
			end)
		end)
	end)
	describe("authored cash-pad geometry and binding regression", function()
		local changedIds = {
			[5] = true,
			[17] = true,
			[18] = true,
			[23] = true,
			[24] = true,
			[29] = true,
			[30] = true,
			[35] = true,
			[36] = true,
			[41] = true,
			[42] = true,
			[47] = true,
			[48] = true,
		}
		local Geometry = require(script.Parent.Parent.Utility.Phase13BaseGeometry)
		for _, rotation in { 0, 90, 180, 270 } do
			it("supports all48 cash-pad approaches below clear6.5-stud bodies at yaw" .. rotation, function()
				fixture(function(f)
					f.Floor.Name = "Foundation"
					f.Floor.Size = Vector3.new(46.66, 1, 79.4625)
					f.Base:SetAttribute("AuthoredBaseLayout", true)
					f.Base:SetAttribute("BaseOrigin", f.Floor.CFrame)
					expect(f.Floor.Parent).to.equal(f.Base)
					expect(f.Base:GetAttribute("AuthoredBaseLayout")).to.equal(true)
					for index = 48, 13, -1 do
						f.Slots[index].Platform:Destroy()
						f.Slots[index] = nil
					end
					for index = 1, 12 do
						local p = f.Slots[index].Platform
						local side = if index <= 6 then -1 else 1
						local row = if side < 0 then index else index - 6
						local pos = Vector3.new(side * 12.77, 0.875, -28.53125 + (row - 1) * 12.18)
						p.Size = Vector3.new(10.16, 0.75, 13.92)
						p.CFrame = f.Floor.CFrame * CFrame.lookAt(pos, Vector3.new(0, pos.Y, pos.Z))
						f.Slots[index].Marker.CFrame = CFrame.new(0, 0.375, 0)
					end
					assert(
						Geometry.Build(f.Base) and Geometry.Apply(f.Base, 48, "BDS_001", false, f.Context),
						"Native measured geometry fixture failed"
					)
					for _, p in f.Base:GetChildren() do
						local index = p:GetAttribute("SlotIndex")
						if p:IsA("BasePart") and type(index) == "number" then
							f.Slots[index] = { Index = index, Platform = p, Marker = p.BrainrotPlacement }
						end
					end
					local sourceFrames = {}
					for _, slot in f.Slots do
						sourceFrames[slot.Index] =
							{ frame = slot.Platform.CFrame, size = slot.Platform.Size, marker = slot.Marker.CFrame }
					end
					local rampFrames = {}
					for _, p in f.Base.Phase13Architecture:GetChildren() do
						if p:GetAttribute("Phase13Role") == "StairRamp" then
							rampFrames[p] = { frame = p.CFrame, size = p.Size }
						end
					end
					local basePivot = f.Base:GetPivot()
					assert(System:BuildBase(f.Base, f.Player.UserId), "Authored plaque factory failed")
					local plaques = System:GetPlaques(f.Base)
					expect(#plaques).to.equal(48)
					local firstPoses = {}
					for index, slot in f.Slots do
						expect(slot.Platform:GetAttribute("SlotIndex")).to.equal(index)
						local plaque = f.Base.IncomePlaques:FindFirstChild("IncomePlaque_" .. index)
						firstPoses[index] = { part = plaque, frame = plaque.CFrame }
						expect(plaque:GetAttribute("PlatformId")).to.equal(index)
						expect(plaque:GetAttribute("BaseId")).to.equal("Base_Layout_Spec")
						expect(plaque.Size).to.equal(Vector3.new(3.5, 0.18, 2.25))
						expect(plaque.TouchSensor.Size).to.equal(Vector3.new(3.5, SENSOR_H, 2.25))
						local relative = plaque.CFrame:ToObjectSpace(plaque.TouchSensor.CFrame)
						expect((relative.Position - Vector3.new(0, 0.09 + SENSOR_H / 2, 0)).Magnitude < 0.005).to.equal(true)
						expect(slot.Platform.CFrame).to.equal(sourceFrames[index].frame)
						expect(slot.Platform.Size).to.equal(sourceFrames[index].size)
						expect(slot.Marker.CFrame).to.equal(sourceFrames[index].marker)
						if index <= 12 then
							local localPlatform = f.Floor.CFrame:PointToObjectSpace(slot.Platform.Position)
							local expectedZ = localPlatform.Z + (if index == 5 then 5.5 else 0)
							local localPlaque = f.Floor.CFrame:PointToObjectSpace(plaque.Position)
							local localSensor = f.Floor.CFrame:PointToObjectSpace(plaque.TouchSensor.Position)
							expect(math.abs(localPlaque.Z - expectedZ) < 0.005).to.equal(true)
							expect(math.abs(localSensor.Z - expectedZ) < 0.005).to.equal(true)
						end
						if not changedIds[index] then
							local front = slot.Platform.CFrame.LookVector
							local raw = slot.Platform.Position
								+ front * (slot.Platform.Size.Z / 2 + 0.55 + plaque.Size.Z / 2)
							local y = f.Floor.Position.Y + f.Floor.Size.Y / 2 + math.floor((index - 1) / 12) * 24 + 0.11
							expect((plaque.Position - Vector3.new(raw.X, y, raw.Z)).Magnitude < 0.005).to.equal(true)
						end
					end
					for p, row in rampFrames do
						expect(p.CFrame).to.equal(row.frame)
						expect(p.Size).to.equal(row.size)
					end
					expect(f.Base:GetPivot()).to.equal(basePivot)
					-- Independent native occupied geometry and support, not an echo of the placement formula.
					local scene = Instance.new("WorldModel")
					scene.Parent = game:GetService("ServerStorage")
					local queryOk, queryReason = xpcall(function()
						local copy = f.Base:Clone()
						copy.Parent = scene
						local filter = { copy.Phase13Architecture, copy.Foundation }
						for _, p in copy:GetChildren() do
							if p:IsA("BasePart") and type(p:GetAttribute("SlotIndex")) == "number" then
								table.insert(filter, p)
							end
						end
						local overlap = OverlapParams.new()
						overlap.FilterType = Enum.RaycastFilterType.Include
						overlap.FilterDescendantsInstances = filter
						overlap.RespectCanCollide = true
						local ray = RaycastParams.new()
						ray.FilterType = Enum.RaycastFilterType.Include
						ray.FilterDescendantsInstances = filter
						ray.RespectCanCollide = true
						local body = Instance.new("Part")
						body.Size = Vector3.new(2, 6.5, 2)
						body.Anchored = true
						body.CanCollide = false
						body.Parent = scene
						for index = 1, 48 do
							local plaque = copy.IncomePlaques:FindFirstChild("IncomePlaque_" .. index)
							body.CFrame = CFrame.new(plaque.Position + Vector3.yAxis * 3.25)
							expect(#scene:GetPartsInPart(body, overlap)).to.equal(0)
							for _, dx in { -0.8, 0, 0.8 } do
								for _, dz in { -0.8, 0, 0.8 } do
									local hit = scene:Raycast(
										plaque.Position + Vector3.new(dx, 0.3, dz),
										Vector3.new(0, -1.5, 0),
										ray
									)
									expect(hit ~= nil).to.equal(true)
									if hit then
										expect(
											hit.Normal.Y > 0.99
												and plaque.Position.Y - hit.Position.Y >= 0
												and plaque.Position.Y - hit.Position.Y < 0.25
										).to.equal(true)
									end
								end
							end
						end
					end, debug.traceback)
					scene:Destroy()
					assert(queryOk, queryReason or "Independent native cash-pad geometry failed")
					assert(System:BuildBase(f.Base, f.Player.UserId), "Idempotent authored plaque rebuild failed")
					for index, row in firstPoses do
						local plaque = f.Base.IncomePlaques:FindFirstChild("IncomePlaque_" .. index)
						expect(plaque).to.equal(row.part)
						expect(plaque.CFrame).to.equal(row.frame)
					end
					f.Snapshots[17] = table.clone(f.Snapshots[5])
					expect(System:HandlePlaqueTouch(firstPoses[5].part, f.Limb).code).to.equal("Collected")
					expect(System:HandlePlaqueTouch(firstPoses[5].part, f.OtherLimb).code).to.equal("Busy")
					expect(System:HandlePlaqueTouch(firstPoses[17].part, f.Limb).code).to.equal("Collected")
					expect(f.ClaimCalls()).to.equal(2)
				end, nil, rotation)
			end)
		end
	end)
end
