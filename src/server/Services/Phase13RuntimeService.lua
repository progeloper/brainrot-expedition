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
local Service = {}
local started = false
local event = nil
local request = nil
local anchors = {}
local rate = {}
local reconcileQueue = {}
local sacrificePreviews = {}
local function invalidateAssignedBase(player)
	local assignment = Bases:GetAssignment(player)
	if assignment == nil or not Bases:IsCurrentAssignment(assignment) then return false end
	local base = assignment.Base
	if base:GetAttribute("OwnerUserId") ~= player.UserId
		or base:GetAttribute("BaseOwnershipRevision") ~= assignment.Generation then return false end
	local unavailableState = string.format("0:%d:%d:0", player.UserId, assignment.Generation)
	if base:GetAttribute("BasePresentationState") ~= unavailableState or base:GetAttribute("BasePresentationReady") ~= false then
		SlotPresentation.Invalidate(base, player.UserId, assignment.Generation)
	end
	if started then reconcileQueue[player] = true end
	return true
end
function Service:OnProfileDiagnostic(player, diagnostic)
	if type(diagnostic) ~= "table" or not ({SessionLost=true,LoadRejected=true,CloseUnconfirmed=true})[diagnostic.kind] then return false end
	-- A late failure notification from an earlier session must not hide a recovered owner.
	if Profiles:GetStatus(player) ~= "Failed" then return false end
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
	if not character or not character:IsDescendantOf(workspace) or not humanoid or humanoid.Health <= 0 then
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
		return anchors.Cart ~= nil and near(player, anchors.Cart.Position, 12) or dock ~= nil and near(
			player,
			dock.Position,
			18
		),
			"SHOP_REQUIRED"
	elseif category == "Weapon" then
		return anchors.Weapon ~= nil and near(player, anchors.Weapon.Position, 12) or anchors.Kit ~= nil and near(
			player,
			anchors.Kit.Position,
			12
		),
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
		local v2Folder = template:GetAttribute("Phase13ArtVersion") == 2 and template:FindFirstChild("Phase13Appearance")
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
					weld.Part0 = if type(rotorName) == "string" then art:FindFirstChild(rotorName) or handle else handle
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
		handle.Transparency = if #art:GetChildren()>0 then 1 else source.Transparency
		handle:SetAttribute("Phase13HelperHandle",#art:GetChildren()>0)
		local grip=if v2Folder then nil else sourceArt:FindFirstChild("Grip",true)
		if grip and grip:IsA("BasePart")then
			tool.Grip=source.CFrame:ToObjectSpace(grip.CFrame)
			local attachment=handle:FindFirstChild("RightGripAttachment")
			if attachment and attachment:IsA("Attachment")then attachment.CFrame=tool.Grip end
		end
		handle.Color = source.Color
		handle.Material = source.Material
		handle.MaterialVariant = source.MaterialVariant
		local muzzle = handle:FindFirstChild("Muzzle")
		local sm = source:FindFirstChild("Muzzle")
		if muzzle and sm then
			muzzle.CFrame = sm.CFrame
		end
		local finish = AppearanceRules.ResolveFinish(data, "Weapon", id)
		-- Reset the source handle color before the shared finish pass; no cumulative tint.
		handle:SetAttribute("Phase13FinishOriginalColor", source.Color)
		AppearanceRules.Apply(handle, finish, "Weapon", id)
		AppearanceRules.Apply(art, finish, "Weapon", id)
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
	if assignment == nil or assignment.Base ~= base or not Bases:IsCurrentAssignment(assignment) then
		return false
	end
	if
		not Geometry.Apply(
			base,
			Rules.GetCapacity(data),
			data.Phase13.SelectedBaseDesignId,
			AppearanceRules.ResolveFinish(data, "Base", data.Phase13.SelectedBaseDesignId),
			{ OwnerUserId = player.UserId, AssignmentRevision = assignment.Generation, ProfileReady = true }
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
			for _, row in Config.CartRows do if row.id == selected then assetName = row.assetName; break end end
			AppearanceRules.Apply(art, AppearanceRules.ResolveFinish(data, "Cart", selected), "Cart", assetName)
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
		attachmentCosmetics = CosmeticPresenter.Snapshot(data, Bases:GetBase(player), Carts:GetCart(player)),
		busy = Transactions:IsBusy(player),
		configurationVersion = Config.ConfigurationVersion,
		-- P15 economy: Gems, income breakdown, Gem shop, Prestige and the server storm.
		economy = GemRules.Snapshot(data, workspace:GetServerTimeNow()),
		mutationStormSeconds = MutationStorm.Remaining(),
		-- Camp Rework: special weapons (pedestals, shop rows) and sell-back eligibility.
		campRework = CampFlags.CampRework(),
		specials = if CampFlags.CampRework() then SpecialRules.Snapshot(data) else nil,
	}
end
local function makeAnchor(model, category)
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
	anchors[category] = found
	local prompt = found:FindFirstChild("Phase13ShopPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Phase13ShopPrompt"
		prompt.Parent = found
	end
	prompt.ActionText = if category == "Weapon"
		then "Browse weapons"
		elseif category == "Cart" then "Browse carts"
		else "Manage kit"
	prompt.ObjectText = if category == "Weapon" then "WEAPONS" elseif category == "Cart" then "CARTS" else "KIT"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	SlotPresentation.Capture(prompt)
	CollectionService:AddTag(prompt, SHOP_PROMPT_TAG)
	prompt.Triggered:Connect(function(player)
		if near(player, found.Position, 12) then
			event:FireClient(player, { kind = "Open", category = if category == "Kit" then "Weapon" else category })
		end
	end)
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
			prompt.ActionText = "Expand / design"
			prompt.ObjectText = "Your base"
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Parent = attachment
			SlotPresentation.Capture(prompt)
			CollectionService:AddTag(prompt, SHOP_PROMPT_TAG)
			prompt.Triggered:Connect(function(player)
				if Bases:GetBase(player) == base and near(player, baseEntrance(base).Position, 12) then
					event:FireClient(player, { kind = "Open", category = "Base" })
				end
			end)
		end
	end
	local services = workspace.MapBlockout:FindFirstChild("MapArt")
		and workspace.MapBlockout.MapArt:FindFirstChild("Services")
	if services then
		for name, category in
			{ Kiosk_WeaponHarpoonStall = "Weapon", Kiosk_BuyCartStall = "Cart", Kiosk_KitStall = "Kit" }
		do
			local model = services:FindFirstChild(name)
			if model then
				makeAnchor(model, category)
			end
		end
	end
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
			if not Carry.HandleAuthoritativeRecovery(oldPlayer, newPlayer, canonicalData, previousData) then
				return false
			end
			if not Cargo:HandleAuthoritativeRecovery(oldPlayer, newPlayer, canonicalData, previousData) then
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
				local item = type(payload.itemId) == "string" and EconomyConfig.GemShopById[payload.itemId]
				if not item then
					return { ok = false, code = "UNKNOWN_ITEM" }
				end
				if item.kind == "MutationStorm" and not MutationStorm.CanAdd(item.seconds) then
					return { ok = false, code = "STORM_FULL" }
				end
				return Transactions:CommitCritical(player, payload.operationId, "GemShop", function(data, at)
					return GemRules.ApplyShopItem(data, payload.itemId, at)
				end, {
					onConfirmed = function(result)
						if type(result) == "table" and result.kind == "MutationStorm" then
							MutationStorm.Activate(player, result.seconds, "Gems")
						end
						pcall(CurrencyMirror.SyncBalance, CurrencyMirror, player)
						return true
					end,
				})
			elseif payload.action == "CosmeticPurchase" then
				for key in payload do
					if key ~= "action" and key ~= "id" and key ~= "operationId" then return {ok=false,code="INVALID_REQUEST"} end
				end
				if not self:ValidateContext(player, "Appearance", false) then return {ok=false,code="OWN_BASE_REQUIRED"} end
				if not CosmeticPresenter.Ready(payload.id) then return {ok=false,code="PRESENTATION_UNAVAILABLE"} end
				return Transactions:CommitCritical(player, payload.operationId, "CosmeticPurchase", function(data)
					return AttachmentCosmetics.ApplyPurchase(data, payload.id)
				end, {onConfirmed=function(result)
 local ok=self:Reconcile(player,nil)
 if ok then pcall(function()require(script.Parent.RetentionService):ObserveCosmeticConfirmed(player,result,payload.operationId)end)end
 return ok
 end})
			elseif payload.action == "Appearance" then
				local allowed = self:ValidateContext(player, "Appearance", false)
				if not allowed then
					return { ok = false, code = "OWN_BASE_REQUIRED" }
				end
				local key = payload.key
				local value = payload.value
				local selectedData = Profiles:GetReadableData(player)
				if AttachmentCosmetics.IsSlot(key) and value ~= "None" and not CosmeticPresenter.Ready(value) then return {ok=false,code="PRESENTATION_UNAVAILABLE"} end
				local canSelect, selectionReason = AppearanceRules.CanSelect(selectedData, key, value)
				if not canSelect then
					return { ok = false, code = selectionReason }
				end
				return Transactions:CommitCritical(player, payload.operationId, "Appearance", function(data)
					local owned, why = AppearanceRules.CanSelect(data, key, value)
					if not owned then
						return false, { code = why }
					end
					data.Commerce.Appearance = data.Commerce.Appearance or {}
					data.Commerce.Appearance[key] = value
					return true, { category = "Cosmetic", key = key, value = value }
				end, {
					onConfirmed = function()
						local data = Profiles:GetReadableData(player)
						if data then
							for k, v in data.Commerce.Appearance do
								player:SetAttribute("Appearance_" .. k, v)
							end
						end
						local reconciled = self:Reconcile(player, nil)
						if reconciled then pcall(function()require(script.Parent.RetentionService):ObserveCosmeticConfirmed(player,{key=key,value=value},payload.operationId)end)end
						return reconciled
					end,
				})
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
