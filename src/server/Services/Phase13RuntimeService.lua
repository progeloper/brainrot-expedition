--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SHOP_PROMPT_TAG = "Phase13ShopInteraction"
local Config = require(RS.Shared.Config.Phase13)
local Rules = require(RS.Shared.Utility.Phase13Rules)
local CommerceRules = require(RS.Shared.Utility.Phase13CommerceRules)
local AppearanceRules = require(RS.Shared.Utility.Phase13AppearanceRules)
local PlaytestFlags = require(RS.Shared.Config.PlaytestFixesFlags)
local WeaponFx = require(RS.Shared.Utility.WeaponFxLibrary)
local AttachmentCosmetics = require(RS.Shared.Utility.Phase14CosmeticRules)
local CosmeticPresenter = require(script.Parent.Parent.Utility.Phase14CosmeticPresenter)
local CreatureReplication = require(script.Parent.CreatureReplicationService)
local Weapons = require(RS.Shared.Config.Weapons)
local Profiles = require(script.Parent.PlayerDataService)
local Transactions = require(script.Parent.Phase13Service)
local Commerce = require(script.Parent.Phase13CommerceService)
local Analytics = require(script.Parent.Phase13AnalyticsService)
local GemRules = require(RS.Shared.Utility.GemRules)
local EconomyConfig = require(RS.Shared.Config.Economy)
local MutationStorm = require(script.Parent.MutationStormService)
local CurrencyMirror = require(script.Parent.Parent.Systems.CurrencySystem)
local Geometry = require(script.Parent.Parent.Utility.Phase13BaseGeometry)
local SlotPresentation = require(RS.Shared.Utility.BaseSlotPresentation)
local Bases = require(script.Parent.Parent.Systems.PlayerBaseSystem)
local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
local Carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
local Cargo = require(script.Parent.CartCargoService)
local Carts = require(script.Parent.CartService)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local WorldReady = require(script.Parent.PlayerWorldLifecycle)
local Combat = require(script.Parent.PlayerCombatService)
local Reset = require(script.Parent.Phase12WorldService)
local CampFlags = require(RS.Shared.Config.CampReworkFlags)
local SpecialRules = require(RS.Shared.Utility.SpecialWeaponRules)
local SaleSystem = require(script.Parent.Parent.Systems.BrainrotSaleSystem)
local Banked = require(script.Parent.BankedBrainrotService)
local Training = require(script.Parent.TrainingService)
local Service = {}
local started = false
local event = nil
local request = nil
local campEvent = nil
local basePrompts = {}
local rebirthReadyClock = 0
local anchors = {}
local rate = {}
local reconcileQueue = {}
local sacrificePreviews = {}
local function invalidateAssignedBase(player)
	local assignment = Bases:GetAssignment(player)
	if assignment == nil or not Bases:IsCurrentAssignment(assignment) then
		return false
	end
	local base = assignment.Base
	if
		base:GetAttribute("OwnerUserId") ~= player.UserId
		or base:GetAttribute("BaseOwnershipRevision") ~= assignment.Generation
	then
		return false
	end
	local unavailableState = string.format("0:%d:%d:0", player.UserId, assignment.Generation)
	if
		base:GetAttribute("BasePresentationState") ~= unavailableState
		or base:GetAttribute("BasePresentationReady") ~= false
	then
		SlotPresentation.Invalidate(base, player.UserId, assignment.Generation)
	end
	if started then
		reconcileQueue[player] = true
	end
	return true
end
function Service:OnProfileDiagnostic(player, diagnostic)
	if
		type(diagnostic) ~= "table"
		or not ({ SessionLost = true, LoadRejected = true, CloseUnconfirmed = true })[diagnostic.kind]
	then
		return false
	end
	-- A late failure notification from an earlier session must not hide a recovered owner.
	if Profiles:GetStatus(player) ~= "Failed" then
		return false
	end
	return invalidateAssignedBase(player)
end
local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function near(player, position, range)
	local root = rootOf(player)
	return root ~= nil and (root.Position - position).Magnitude <= range
end
local function baseEntrance(base)
	return base.Foundation.CFrame * CFrame.new(0, 3, -base.Foundation.Size.Z / 2 + 2)
end
local function salePoint()
	local map = workspace:FindFirstChild("MapBlockout")
	local patches = map and map:FindFirstChild("ServiceStallPatches")
	local point = patches and patches:FindFirstChild("SellStall")
	return if point and point:IsA("BasePart") then point else nil
end
function Service:ValidateContext(player, category, insideMutation)
	if Profiles:GetStatus(player) ~= "Ready" or not WorldReady:IsReady(player) then
		return false, "NOT_READY"
	end
	if not insideMutation and not Profiles:IsWritable(player) then
		return false, "BUSY"
	end
	local canAct, reason = Combat:CanAct(player, insideMutation == true)
	if not canAct then
		return false, reason or "BUSY"
	end
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not character
		or not character:IsDescendantOf(workspace)
		or not humanoid
		or humanoid.Health <= 0
	then
		return false, "NOT_READY"
	end
	if not root or not Regions.ContainsPosition("REGION_CAMP", root.Position, 16) then
		return false, "CAMP_REQUIRED"
	end
	local resetAllowed, resetReason = Reset:CanCommit(nil, root.Position, player)
	if not resetAllowed then
		return false, resetReason or "RESET_ACTIVE"
	end
	local base = Bases:GetBase(player)
	if category == "Rebirth" or category == "Design" or category == "Appearance" then
		return base ~= nil and near(player, baseEntrance(base).Position, 12), "OWN_BASE_REQUIRED"
	elseif category == "Cart" then
		local dock = base and base:FindFirstChild("CartSpawn")
		return anchors.Cart ~= nil and near(player, anchors.Cart.Position, 12)
			or dock ~= nil and near(player, dock.Position, 18),
			"SHOP_REQUIRED"
	elseif category == "Weapon" then
		-- The Kit kiosk was removed (Camp Rework); it opened this same Weapons menu.
		return anchors.Weapon ~= nil and near(player, anchors.Weapon.Position, 12), "SHOP_REQUIRED"
	elseif category == "Training" then
		return CampFlags.Training() and anchors.Training ~= nil and near(
			player,
			anchors.Training.Position,
			12
		),
			"SHOP_REQUIRED"
	elseif category == "Sell" then
		local point = salePoint()
		return CampFlags.CampRework() and point ~= nil and near(player, point.Position, 14),
			"SHOP_REQUIRED"
	end
	return false, "INVALID_CATEGORY"
end
local function applyWeapon(player)
	local data = Profiles:GetReadableData(player)
	if not data then
		return false
	end
	local id = data.Phase13.SelectedWeaponId
	local folder = RS.CodeAssets:FindFirstChild("Weapons")
	local template = folder and folder:FindFirstChild(id)
	if not template then
		return false
	end
	local function apply(tool)
		if not tool:IsA("Tool") or tool.Name ~= "SleepLauncher" then
			return
		end
		local handle = tool:FindFirstChild("Handle")
		local source = template:FindFirstChild("Handle")
		if not handle or not source or not handle:IsA("BasePart") or not source:IsA("BasePart") then
			return
		end
		local old = tool:FindFirstChild("Phase13WeaponArt")
		if old then
			old:Destroy()
		end
		local art = Instance.new("Model")
		art.Name = "Phase13WeaponArt"
		local sourceArt = template:FindFirstChild("Phase13WeaponArt") or template
		local v2Folder = template:GetAttribute("Phase13ArtVersion") == 2
			and template:FindFirstChild("Phase13Appearance")
		-- Playtest Fixes C4: v1 weapons (WPN_C01, WPN_G01) get Trailwood v2 art from
		-- CodeAssets.PlaytestArtV2 while WeaponFx is on. Same Handle frame; muzzle moves to the new tip.
		local artOverride = if PlaytestFlags.Part("WeaponFx")
			then RS.CodeAssets:FindFirstChild("PlaytestArtV2")
				and RS.CodeAssets.PlaytestArtV2:FindFirstChild(id)
			else nil
		if artOverride and artOverride:FindFirstChild("Phase13Appearance") then
			v2Folder = artOverride.Phase13Appearance
		else
			artOverride = nil
		end
		if v2Folder then
			-- Camp Rework art: clone the folder in one go so Beams keep their attachments, then
			-- re-weld to the live Handle. SPINS/MOVES groups ride one rotor Weld each (CampAnimRotor tag).
			local folder = v2Folder:Clone()
			for _, d in folder:GetDescendants() do
				if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
					d:Destroy()
				end
			end
			local parts = {}
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") then
					part.CFrame = handle.CFrame * source.CFrame:ToObjectSpace(part.CFrame)
					part.Anchored = false
					part.Massless = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					table.insert(parts, part)
				end
			end
			for _, part in parts do
				part.Parent = art
			end
			for _, part in parts do
				if string.sub(part.Name, 1, 10) == "AnimRotor_" then
					local motor = Instance.new("Weld")
					motor.Name = "ArtMotor"
					motor.Part0 = handle
					motor.Part1 = part
					motor.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
					motor.Parent = part
					CollectionService:AddTag(part, "CampAnimRotor")
				else
					local rotorName = part:GetAttribute("CampAnimRotor")
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = if type(rotorName) == "string"
						then art:FindFirstChild(rotorName) or handle
						else handle
					weld.Part1 = part
					weld.Parent = part
				end
			end
			folder:Destroy()
		end
		for _, part in (if v2Folder then {} else sourceArt:GetDescendants()) do
			if part:IsA("BasePart") and part ~= source then
				local p = part:Clone()
				for _, child in p:GetDescendants() do
					if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end
				p.CFrame = handle.CFrame * source.CFrame:ToObjectSpace(part.CFrame)
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = p
				weld.Parent = p
				p.Parent = art
			end
		end
		handle.Size = source.Size
		handle.Transparency = if #art:GetChildren() > 0 then 1 else source.Transparency
		handle:SetAttribute("Phase13HelperHandle", #art:GetChildren() > 0)
		local grip = if v2Folder then nil else sourceArt:FindFirstChild("Grip", true)
		if grip and grip:IsA("BasePart") then
			tool.Grip = source.CFrame:ToObjectSpace(grip.CFrame)
			local attachment = handle:FindFirstChild("RightGripAttachment")
			if attachment and attachment:IsA("Attachment") then
				attachment.CFrame = tool.Grip
			end
		end
		handle.Color = source.Color
		handle.Material = source.Material
		handle.MaterialVariant = source.MaterialVariant
		local muzzle = handle:FindFirstChild("Muzzle")
		local sm = source:FindFirstChild("Muzzle")
		if muzzle and sm then
			muzzle.CFrame = sm.CFrame
		end
		if muzzle and artOverride and typeof(artOverride:GetAttribute("MuzzleZ")) == "number" then
			muzzle.Position = Vector3.new(
				artOverride:GetAttribute("MuzzleX") :: number,
				artOverride:GetAttribute("MuzzleY") :: number,
				artOverride:GetAttribute("MuzzleZ") :: number
			)
		end
		local finish = AppearanceRules.ResolveFinish(data, "Weapon", id)
		-- Reset the source handle color before the shared finish pass; no cumulative tint.
		handle:SetAttribute("Phase13FinishOriginalColor", source.Color)
		AppearanceRules.Apply(handle, finish, "Weapon", id)
		AppearanceRules.Apply(art, finish, "Weapon", id)
		-- Playtest Fixes Part C: idle/signature effects on the existing art parts (flag-gated).
		if PlaytestFlags.Part("WeaponFx") then
			WeaponFx.Author(art, id, handle)
		end
		art.Parent = tool
		tool:SetAttribute("SelectedWeaponId", id)
		tool.ToolTip = Weapons.Get(id).displayName
	end
	if player.Character then
		for _, tool in player.Character:GetChildren() do
			apply(tool)
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			apply(tool)
		end
	end
	return true
end
function Service:Reconcile(player, receipt)
	local data = Profiles:GetReadableData(player)
	local base = Bases:GetBase(player)
	local profileStatus = Profiles:GetStatus(player)
	if not data or profileStatus == "Failed" or profileStatus == "Recovering" then
		invalidateAssignedBase(player)
		return false
	end
	if receipt and receipt.Kind == "Rebirth" and receipt.Result.route == "Collection" then
		local ids = receipt.Preflight and receipt.Preflight.ids
		if not ids then
			ids = {}
		end
		if Carry.ReconcileOwnedSacrifice and not Carry.ReconcileOwnedSacrifice(player, ids) then
			return false
		end
		if Cargo.ReconcileOwnedSacrifice and not Cargo:ReconcileOwnedSacrifice(player, ids) then
			return false
		end
	end
	if player.Parent ~= Players then
		return true
	end
	if not base then
		return false
	end
	-- Readable data includes in-memory critical mutations before their covering save.
	-- Queue/cart callbacks must retain the previous committed presentation during that interval.
	if
		receipt == nil
		and Transactions:IsBusy(player)
		and not Profiles:IsRevisionConfirmed(player, Profiles:GetCurrentRevision(player) or 0)
	then
		return false
	end
	local assignment = Bases:GetAssignment(player)
	if
		assignment == nil
		or assignment.Base ~= base
		or not Bases:IsCurrentAssignment(assignment)
	then
		return false
	end
	if
		not Geometry.Apply(
			base,
			Rules.GetCapacity(data),
			data.Phase13.SelectedBaseDesignId,
			AppearanceRules.ResolveFinish(data, "Base", data.Phase13.SelectedBaseDesignId),
			{
				OwnerUserId = player.UserId,
				AssignmentRevision = assignment.Generation,
				ProfileReady = true,
			}
		)
	then
		return false
	end
	if not Storage:ReconcilePlayerFromProfile(player) then
		return false
	end
	applyWeapon(player)
	local cart = Carts:GetCart(player)
	if cart then
		local art = cart:FindFirstChild("Visual")
		if art then
			local selected = data.Phase13.SelectedCartId
			local assetName = art.Name
			for _, row in Config.CartRows do
				if row.id == selected then
					assetName = row.assetName
					break
				end
			end
			AppearanceRules.Apply(
				art,
				AppearanceRules.ResolveFinish(data, "Cart", selected),
				"Cart",
				assetName
			)
		end
	end
	CosmeticPresenter.Reconcile(player, data, base, cart)
	Carts:ReconcileOwnerPerformance(player.UserId, "Phase13Confirmed")
	Cargo:ReconcileOwnerCapacity(player.UserId, "Phase13Confirmed")
	return true
end
local function snapshot(player)
	local data = Profiles:GetReadableData(player)
	if not data then
		return { ok = false, code = "NOT_READY" }
	end
	local p = data.Phase13
	return {
		ok = true,
		balance = data.Economy.Balance,
		capacity = Rules.GetCapacity(data),
		rebirthCount = p.RebirthCount,
		previewRevision = p.EligibilityRevision,
		nextSequence = p.OperationSequence + 1,
		ownedWeapons = p.OwnedWeaponIds,
		ownedCarts = p.OwnedCartIds,
		ownedDesigns = p.OwnedBaseDesigns,
		selectedWeapon = p.SelectedWeaponId,
		selectedCart = p.SelectedCartId,
		selectedDesign = p.SelectedBaseDesignId,
		speedLevel = p.SpeedLevel,
		cargoLevel = p.CargoLevel,
		commerce = Commerce:GetCatalogue(player),
		appearance = data.Commerce.Appearance,
		attachmentCosmetics = CosmeticPresenter.Snapshot(
			data,
			Bases:GetBase(player),
			Carts:GetCart(player)
		),
		busy = Transactions:IsBusy(player),
		configurationVersion = Config.ConfigurationVersion,
		-- P15 economy: Gems, income breakdown, Gem shop, Prestige and the server storm.
		economy = GemRules.Snapshot(data, workspace:GetServerTimeNow()),
		mutationStormSeconds = MutationStorm.Remaining(),
		-- Camp Rework: special weapons (pedestals, shop rows) and sell-back eligibility.
		campRework = CampFlags.CampRework(),
		specials = if CampFlags.CampRework() then SpecialRules.Snapshot(data) else nil,
		training = Training.Snapshot(data),
		-- Favourite lock: ids of the owned brainrots the player starred (they cannot be sold).
		favourites = Banked:GetFavourites(player),
	}
end
-- Camp Rework stalls carry a marker for their prompt (counter, or the Training speedometer post).
local function campAnchorMarker(model)
	local slots = model:FindFirstChild("CampSlots")
	if not slots then
		return nil
	end
	for _, child in slots:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("CampAnchor") ~= nil then
			return child
		end
	end
	return nil
end
local CAMP_OBJECT_TEXT = { Weapon = "WEAPONS", Cart = "CARTS", Training = "TRAINING" }
local function makeAnchor(model, category)
	local campStall = CampFlags.CampRework() and model:GetAttribute("CampReworkStall") ~= nil
	local found = model:FindFirstChild("Phase13ShopAnchor")
	if not found then
		found = Instance.new("Part")
		found.Name = "Phase13ShopAnchor"
		found.Size = Vector3.one
		found.CFrame = model:GetPivot() + Vector3.new(0, 3, 0)
		found.Transparency = 1
		found.Anchored = true
		found.CanCollide = false
		found.CanTouch = false
		found.CanQuery = false
		found.Parent = model
	end
	local marker = if campStall then campAnchorMarker(model) else nil
	if marker then
		found.CFrame = marker.CFrame
	end
	anchors[category] = found
	local prompt = found:FindFirstChild("Phase13ShopPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Phase13ShopPrompt"
		prompt.Parent = found
	end
	if campStall then
		prompt.ActionText = "Open"
		prompt.ObjectText = CAMP_OBJECT_TEXT[category] or string.upper(category)
	else
		prompt.ActionText = if category == "Weapon" then "Browse weapons" else "Browse carts"
		prompt.ObjectText = if category == "Weapon" then "WEAPONS" else "CARTS"
	end
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("CampCategory", category)
	SlotPresentation.Capture(prompt)
	CollectionService:AddTag(prompt, SHOP_PROMPT_TAG)
	prompt.Triggered:Connect(function(player)
		if near(player, found.Position, 12) then
			event:FireClient(player, { kind = "Open", category = category })
		end
	end)
	return prompt
end
function Service:Start(_options)
	if started then
		return false
	end
	started = true
	local folder = RS:WaitForChild("Remotes")
	event = folder:FindFirstChild("Phase13Update") or Instance.new("RemoteEvent")
	event.Name = "Phase13Update"
	event.Parent = folder
	request = folder:FindFirstChild("Phase13Request") or Instance.new("RemoteFunction")
	request.Name = "Phase13Request"
	request.Parent = folder
	-- Camp Rework presentation broadcast (sale coin burst, training level-up). Server -> clients only.
	campEvent = folder:FindFirstChild("CampReworkEvent") or Instance.new("RemoteEvent")
	campEvent.Name = "CampReworkEvent"
	campEvent.Parent = folder
	Service.CampEvent = campEvent
	if CampFlags.CampRework() then
		SaleSystem.SubscribeCommitted(function(player)
			campEvent:FireAllClients({ kind = "SaleBurst", userId = player.UserId })
		end)
	end
	local patches = workspace:WaitForChild("MapBlockout"):WaitForChild("PlayerBasePatches")
	for _, base in patches:GetChildren() do
		if base:IsA("Model") and base:FindFirstChild("Foundation") then
			Geometry.Build(base)
			Geometry.Apply(base, 12, Config.InitialDesignId, false)
			local attachment = Instance.new("Attachment")
			attachment.Name = "Phase13UpgradeEntrance"
			attachment.WorldCFrame = baseEntrance(base)
			attachment.Parent = base.Foundation
			attachment.WorldCFrame = baseEntrance(base)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Phase13BaseUpgradePrompt"
			-- Rebirth UI v2: one name everywhere. "Rebirth — Ready!" is set per owner below.
			prompt.ActionText = if CampFlags.RebirthUi() then "Rebirth" else "Expand / design"
			basePrompts[base] = prompt
			prompt.ObjectText = "Your base"
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Parent = attachment
			SlotPresentation.Capture(prompt)
			CollectionService:AddTag(prompt, SHOP_PROMPT_TAG)
			prompt.Triggered:Connect(function(player)
				if
					Bases:GetBase(player) == base and near(player, baseEntrance(base).Position, 12)
				then
					event:FireClient(player, { kind = "Open", category = "Base" })
				end
			end)
		end
	end
	local services = workspace.MapBlockout:FindFirstChild("MapArt")
		and workspace.MapBlockout.MapArt:FindFirstChild("Services")
	if services then
		local stalls = { Kiosk_WeaponHarpoonStall = "Weapon", Kiosk_BuyCartStall = "Cart" }
		if CampFlags.Training() then
			stalls.Kiosk_TrainingStall = "Training"
		end
		for name, category in stalls do
			local model = services:FindFirstChild(name)
			if model then
				local prompt = makeAnchor(model, category)
				if category == "Training" then
					Training:BindPrompt(prompt, model)
				end
			end
		end
	end
	-- Playtest Fixes Part F: Gems stall hidden while its flag is off; NEWS board panel when on.
	require(script.Parent.Parent.Systems.PlaytestCampStalls).Start()
	Transactions:Start({
		Telemetry = Analytics,
		ValidateContext = function(...)
			return self:ValidateContext(...)
		end,
		PreflightOwned = function(player, req)
			local data = Profiles:GetReadableData(player)
			if not data then
				return nil, "NOT_READY"
			end
			local ids = {}
			local descriptors = {}
			if req.route == "Collection" then
				for id, record in data.Collection.BrainrotInstances do
					table.insert(ids, id)
					if #descriptors < 48 then
						table.insert(descriptors, {
							individualId = id,
							speciesId = record.speciesId,
							mutationId = record.mutationId or "None",
						})
					end
				end
				table.sort(ids)
			end
			sacrificePreviews[player] = { ids = ids, descriptors = descriptors }
			if Carry.PreflightOwnedSacrifice then
				local ok, reason = Carry.PreflightOwnedSacrifice(player, ids)
				if not ok then
					return nil, reason
				end
			end
			if Cargo.PreflightOwnedSacrifice then
				local ok, reason = Cargo:PreflightOwnedSacrifice(player, ids)
				if not ok then
					return nil, reason
				end
			end
			return { ids = ids }
		end,
		ReconcileRecovery = function(oldPlayer, newPlayer, canonicalData, previousData)
			-- A newly acquired backend snapshot is the sole authority here. The departed
			-- Player's old readable handle and uncertain transaction are fenced already.
			if
				not Carry.HandleAuthoritativeRecovery(
					oldPlayer,
					newPlayer,
					canonicalData,
					previousData
				)
			then
				return false
			end
			if
				not Cargo:HandleAuthoritativeRecovery(
					oldPlayer,
					newPlayer,
					canonicalData,
					previousData
				)
			then
				return false
			end
			sacrificePreviews[oldPlayer] = nil
			reconcileQueue[oldPlayer] = nil
			return true
		end,
		ReconcileOwned = function(player, receipt)
			return self:Reconcile(player, receipt)
		end,
		PrepareCartSelection = function(player, id)
			return Carts:PrepareOwnedCartSelection(player, id)
		end,
		CommitCartSelection = function(player, token, id)
			if not Carts:CommitOwnedCartSelection(player, token, id) then
				return false
			end
			return self:Reconcile(player, nil)
		end,
	})
	require(script.Parent.SpecialWeaponService):Start()
	Transactions:SubscribeConfirmed(function(player, result)
		if result.kind == "Rebirth" then
			local preview = sacrificePreviews[player]
			result.presentation = {
				plot = Bases:GetBase(player),
				sacrificedIndividuals = preview and preview.descriptors or {},
				branch = result.result.route,
			}
			sacrificePreviews[player] = nil
			-- Visual cache authorization follows the durable boundary and never changes its reward.
			pcall(
				CreatureReplication.AuthorizePresentation,
				CreatureReplication,
				player,
				result.presentation.sacrificedIndividuals
			)
		end
		event:FireClient(player, { kind = "Confirmed", response = result })
	end)
	local function readyPlayer(player)
		reconcileQueue[player] = true
		pcall(CurrencyMirror.SyncBalance, CurrencyMirror, player)
		local data = Profiles:GetReadableData(player)
		if data then
			for k, v in data.Commerce.Appearance or {} do
				player:SetAttribute("Appearance_" .. k, v)
			end
		end
		player.CharacterAdded:Connect(function(character)
			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					task.defer(applyWeapon, player)
				end
			end)
			task.defer(applyWeapon, player)
		end)
	end
	Profiles:SubscribeReady(readyPlayer)
	Profiles:SubscribeDiagnostics(function(player, diagnostic)
		self:OnProfileDiagnostic(player, diagnostic)
	end)
	for _, player in Players:GetPlayers() do
		if Profiles:GetReadableData(player) then
			readyPlayer(player)
		end
	end
	Bases:SubscribeAssignments(function(player)
		reconcileQueue[player] = true
	end, function(_player, base)
		CosmeticPresenter.ReleaseBase(base)
	end)
	Carts.CartSpawned:Connect(function(record)
		local player = Players:GetPlayerByUserId(record.OwnerUserId)
		if player then
			reconcileQueue[player] = true
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			Transactions:Step()
			CosmeticPresenter.Step()
			for player in reconcileQueue do
				if self:Reconcile(player, nil) then
					reconcileQueue[player] = nil
				end
			end
			for _, player in Players:GetPlayers() do
				Analytics:SetWorldReady(player, WorldReady:IsReady(player))
			end
			rebirthReadyClock += 1
			if CampFlags.RebirthUi() and rebirthReadyClock % 4 == 0 then
				-- every ~2 s: mirror READY (either route) to the HUD glow and the owner's base prompt
				for _, player in Players:GetPlayers() do
					local data = Profiles:GetReadableData(player)
					local ready = false
					if data and data.Phase13 then
						local ok, value = pcall(Rules.RebirthReady, data)
						ready = ok and value == true
					end
					player:SetAttribute("RebirthReady", ready)
					local base = Bases:GetBase(player)
					local prompt = base and basePrompts[base]
					if prompt then
						prompt.ActionText = if ready then "Rebirth — Ready!" else "Rebirth"
					end
				end
			end
		end
	end)
	request.OnServerInvoke = function(player, payload)
		if type(payload) ~= "table" or type(payload.action) ~= "string" then
			return { ok = false, code = "INVALID_REQUEST" }
		end
		local t = os.clock()
		local r = rate[player] or { at = t, tokens = 8 }
		r.tokens = math.min(8, r.tokens + (t - r.at) * 4)
		r.at = t
		rate[player] = r
		if r.tokens < 1 then
			return { ok = false, code = "BUSY" }
		end
		r.tokens -= 1
		local ok, result = pcall(function()
			if payload.action == "Snapshot" then
				return snapshot(player)
			elseif payload.action == "Quote" then
				local quote = Transactions:QuoteRebirth(player, payload.rewardId, payload.route)
				pcall(Analytics.ObserveRebirthQuote, Analytics, player, quote)
				return quote
			elseif payload.action == "Rebirth" then
				pcall(Analytics.ObserveRebirthConfirm, Analytics, player, payload)
				return Transactions:Rebirth(player, payload)
			elseif payload.action == "Purchase" then
				return Transactions:Purchase(player, payload)
			elseif payload.action == "SellBack" then
				-- Camp Rework: Cash weapons/carts at 25% back, at the Sell counter only.
				if not CampFlags.CampRework() then
					return { ok = false, code = "UNAVAILABLE" }
				end
				for key in payload do
					if
						key ~= "action"
						and key ~= "category"
						and key ~= "id"
						and key ~= "operationId"
					then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				if
					payload.category ~= "Weapon" and payload.category ~= "Cart"
					or type(payload.id) ~= "string"
				then
					return { ok = false, code = "INVALID_REQUEST" }
				end
				local allowed, why = self:ValidateContext(player, "Sell", false)
				if not allowed then
					return { ok = false, code = why or "SHOP_REQUIRED" }
				end
				return Transactions:CommitCritical(
					player,
					payload.operationId,
					"SellBack",
					function(data)
						return Rules.ApplySellBack(data, payload.category, payload.id)
					end,
					{
						validate = function()
							return self:ValidateContext(player, "Sell", true)
						end,
						onConfirmed = function()
							pcall(CurrencyMirror.SyncBalance, CurrencyMirror, player)
							campEvent:FireAllClients({ kind = "SaleBurst", userId = player.UserId })
							return self:Reconcile(player, nil)
						end,
					}
				)
			elseif payload.action == "TrainingRoller" then
				for key in payload do
					if key ~= "action" and key ~= "rollerId" and key ~= "operationId" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				return Training:PurchaseRoller(player, payload, function(inside)
					return self:ValidateContext(player, "Training", inside)
				end)
			elseif payload.action == "SellCarried" then
				-- Opens the existing carried-brainrot sale dialog from the Sell menu.
				if not CampFlags.CampRework() then
					return { ok = false, code = "UNAVAILABLE" }
				end
				local preview, reason = SaleSystem:CreatePreview(player)
				return if preview
					then { ok = true }
					else { ok = false, code = reason or "NOT_CARRYING" }
			elseif payload.action == "Favourite" then
				-- Stars or unstars one owned brainrot. No location rule: it only ever blocks a sale.
				for key in payload do
					if key ~= "action" and key ~= "id" and key ~= "value" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				if Profiles:GetStatus(player) ~= "Ready" then
					return { ok = false, code = "NOT_READY" }
				end
				local outcome = Banked:SetFavourite(player, payload.id, payload.value)
				return {
					ok = outcome.ok == true,
					code = outcome.code,
					favourite = if outcome.ok == true then payload.value == true else nil,
				}
			elseif payload.action == "SellList" then
				-- Sell stall: the player's banked brainrots with authoritative sale values (read-only).
				if not CampFlags.CampRework() then
					return { ok = false, code = "UNAVAILABLE" }
				end
				for key in payload do
					if key ~= "action" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				return SaleSystem:ListBanked(player)
			elseif payload.action == "SellBanked" then
				-- Sell stall: sells the picked banked brainrots from their platforms in one request.
				if not CampFlags.CampRework() then
					return { ok = false, code = "UNAVAILABLE" }
				end
				for key in payload do
					if key ~= "action" and key ~= "ids" and key ~= "expectedTotal" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				local allowed, why = self:ValidateContext(player, "Sell", false)
				if not allowed then
					return { ok = false, code = why or "SHOP_REQUIRED" }
				end
				return SaleSystem:SellBanked(player, payload.ids, payload.expectedTotal)
			elseif payload.action == "Select" then
				return Transactions:Select(player, payload)
			elseif payload.action == "Status" then
				return Transactions:GetOperation(player, payload.operationId)
			elseif payload.action == "OfferView" then
				return Commerce:ObserveOffers(player, payload.group)
			elseif payload.action == "Prompt" then
				return Commerce:Prompt(player, payload.offerId)
			elseif payload.action == "GemShop" then
				for key in payload do
					if key ~= "action" and key ~= "itemId" and key ~= "operationId" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				local item = type(payload.itemId) == "string"
					and EconomyConfig.GemShopById[payload.itemId]
				if not item then
					return { ok = false, code = "UNKNOWN_ITEM" }
				end
				if item.kind == "MutationStorm" and not MutationStorm.CanAdd(item.seconds) then
					return { ok = false, code = "STORM_FULL" }
				end
				return Transactions:CommitCritical(
					player,
					payload.operationId,
					"GemShop",
					function(data, at)
						return GemRules.ApplyShopItem(data, payload.itemId, at)
					end,
					{
						onConfirmed = function(result)
							if type(result) == "table" and result.kind == "MutationStorm" then
								MutationStorm.Activate(player, result.seconds, "Gems")
							end
							if type(result) == "table" and result.kind == "Trail" then
								-- Playtest Fixes 2 Part G: show the new trail in Inventory > Trails at once.
								pcall(function()
									require(script.Parent.LegsTrainingService).Publish(player)
								end)
							end
							pcall(CurrencyMirror.SyncBalance, CurrencyMirror, player)
							return true
						end,
					}
				)
			elseif payload.action == "CosmeticPurchase" then
				for key in payload do
					if key ~= "action" and key ~= "id" and key ~= "operationId" then
						return { ok = false, code = "INVALID_REQUEST" }
					end
				end
				if not self:ValidateContext(player, "Appearance", false) then
					return { ok = false, code = "OWN_BASE_REQUIRED" }
				end
				if not CosmeticPresenter.Ready(payload.id) then
					return { ok = false, code = "PRESENTATION_UNAVAILABLE" }
				end
				return Transactions:CommitCritical(
					player,
					payload.operationId,
					"CosmeticPurchase",
					function(data)
						return AttachmentCosmetics.ApplyPurchase(data, payload.id)
					end,
					{
						onConfirmed = function(result)
							local ok = self:Reconcile(player, nil)
							if ok then
								pcall(function()
									require(script.Parent.RetentionService):ObserveCosmeticConfirmed(
										player,
										result,
										payload.operationId
									)
								end)
							end
							return ok
						end,
					}
				)
			elseif payload.action == "Appearance" then
				local allowed = self:ValidateContext(player, "Appearance", false)
				if not allowed then
					return { ok = false, code = "OWN_BASE_REQUIRED" }
				end
				local key = payload.key
				local value = payload.value
				local selectedData = Profiles:GetReadableData(player)
				if
					AttachmentCosmetics.IsSlot(key)
					and value ~= "None"
					and not CosmeticPresenter.Ready(value)
				then
					return { ok = false, code = "PRESENTATION_UNAVAILABLE" }
				end
				local canSelect, selectionReason =
					AppearanceRules.CanSelect(selectedData, key, value)
				if not canSelect then
					return { ok = false, code = selectionReason }
				end
				return Transactions:CommitCritical(
					player,
					payload.operationId,
					"Appearance",
					function(data)
						local owned, why = AppearanceRules.CanSelect(data, key, value)
						if not owned then
							return false, { code = why }
						end
						data.Commerce.Appearance = data.Commerce.Appearance or {}
						data.Commerce.Appearance[key] = value
						return true, { category = "Cosmetic", key = key, value = value }
					end,
					{
						onConfirmed = function()
							local data = Profiles:GetReadableData(player)
							if data then
								for k, v in data.Commerce.Appearance do
									player:SetAttribute("Appearance_" .. k, v)
								end
							end
							local reconciled = self:Reconcile(player, nil)
							if reconciled then
								pcall(function()
									require(script.Parent.RetentionService):ObserveCosmeticConfirmed(
										player,
										{ key = key, value = value },
										payload.operationId
									)
								end)
							end
							return reconciled
						end,
					}
				)
			end
			return { ok = false, code = "INVALID_REQUEST" }
		end)
		return if ok then result else { ok = false, code = "UNAVAILABLE" }
	end
	Players.PlayerRemoving:Connect(function(player)
		rate[player] = nil
		reconcileQueue[player] = nil
		sacrificePreviews[player] = nil
	end)
	Analytics:Start()
	Commerce:Start({
		Transactions = Transactions,
		Currency = CurrencyMirror,
		OnMutationStorm = function(player, seconds)
			MutationStorm.Activate(player, seconds, "Robux")
		end,
	})
	return true
end
return Service
