--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local BrainrotSaleSystem = require(script.Parent.BrainrotSaleSystem)
local CampFlags = require(ReplicatedStorage.Shared.Config.CampReworkFlags)

local MANAGED_BY = "BrainrotSalePointSystem"
local SIGN_NAME = "SellBrainrotsSign"
local PROMPT_NAME = "SellBrainrotPrompt"
local SIGN_TEXT = "SELL BRAINROTS"
-- Relative to SellStall: left side and rear edge, on its top surface. The
-- display board is aligned to the stall's readable/front direction.
local SELL_SIGN_LOCAL_OFFSET = Vector3.new(-20, 0, 20)

local BrainrotSalePointSystem = {}
local log = Logger.new("BrainrotSalePointSystem")
local started = false
local generation = 0
local setupQueued = false
local registeredPrompt: ProximityPrompt? = nil
local registeredSalePoint: BasePart? = nil
local connections: { RBXScriptConnection } = {}
local warnedUnavailable = false

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function resolveSalePoint(): (BasePart?, Instance?)
	local map = Workspace:FindFirstChild("MapBlockout")
	local patches = if map then map:FindFirstChild("ServiceStallPatches") else nil
	local salePoint = if patches then patches:FindFirstChild("SellStall") else nil
	return if salePoint and salePoint:IsA("BasePart") then salePoint else nil, patches
end

-- Camp Rework: the new Sell stall carries its own SELL sign. Old and new art must never show together,
-- so the legacy board is skipped whenever that stall is in the world, even with the flag off.
local function campSellStallPresent(): boolean
	local map = Workspace:FindFirstChild("MapBlockout")
	local art = map and map:FindFirstChild("MapArt")
	local services = art and art:FindFirstChild("Services")
	local stall = services and services:FindFirstChild("Kiosk_SellStall")
	return stall ~= nil and stall:GetAttribute("CampReworkStall") ~= nil
end

function BrainrotSalePointSystem.UsesCampMenu(): boolean
	return CampFlags.CampRework()
end

local function resolveTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local signs = if assets then assets:FindFirstChild("BaseSigns") else nil
	local source = if signs then signs:FindFirstChild("Sell Sign") else nil
	return if source and source:IsA("Model") then source else nil
end

local function displayBoard(sign: Model): BasePart?
	for _, descendant in sign:GetDescendants() do
		if descendant:IsA("SurfaceGui") then
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") then
				for _, child in descendant:GetDescendants() do
					if child:IsA("TextLabel") then
						return parent
					end
				end
			end
		end
	end
	return nil
end

local function setVisibleLabels(sign: Model): boolean
	local found = false
	for _, descendant in sign:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant.Visible then
			local surface = descendant:FindFirstAncestorOfClass("SurfaceGui")
			if surface and surface:IsDescendantOf(sign) then
				descendant.Text = SIGN_TEXT
				found = true
			end
		end
	end
	return found
end

local function sanitizeClone(sign: Model)
	for _, descendant in sign:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
		then
			descendant:Destroy()
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			if
				(descendant.Part0 and not descendant.Part0:IsDescendantOf(sign))
				or (descendant.Part1 and not descendant.Part1:IsDescendantOf(sign))
			then
				descendant:Destroy()
			end
		elseif descendant:IsA("Constraint") then
			if
				(descendant.Attachment0 and not descendant.Attachment0:IsDescendantOf(sign))
				or (descendant.Attachment1 and not descendant.Attachment1:IsDescendantOf(sign))
			then
				descendant:Destroy()
			end
		end
	end
	for _, descendant in sign:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function placeSign(sign: Model, board: BasePart, salePoint: BasePart)
	-- Match the inspected template's Front (-Z) board direction to SellStall's
	-- existing orientation without using world coordinates.
	local rotation = salePoint.CFrame.Rotation
		* board.CFrame.Rotation:Inverse()
		* sign:GetPivot().Rotation
	sign:PivotTo(rotation)
	local bounds, size = sign:GetBoundingBox()
	local target = salePoint.CFrame:PointToWorldSpace(
		Vector3.new(SELL_SIGN_LOCAL_OFFSET.X, salePoint.Size.Y * 0.5, SELL_SIGN_LOCAL_OFFSET.Z)
	)
	local currentGround = bounds.Position - Vector3.new(0, size.Y * 0.5, 0)
	sign:PivotTo(sign:GetPivot() + (target - currentGround))
end

local function ensureSign(salePoint: BasePart, parent: Instance, source: Model): Model?
	local sign: Model? = nil
	for _, child in parent:GetChildren() do
		if
			child:IsA("Model")
			and child.Name == SIGN_NAME
			and child:GetAttribute("ManagedBy") == MANAGED_BY
		then
			if sign == nil then
				sign = child
			else
				child:Destroy()
			end
		end
	end
	if sign and (displayBoard(sign) == nil or not setVisibleLabels(sign)) then
		sign:Destroy()
		sign = nil
	end
	if sign == nil then
		sign = source:Clone()
		sign.Name = SIGN_NAME
		sign:SetAttribute("ManagedBy", MANAGED_BY)
		sanitizeClone(sign)
		if displayBoard(sign) == nil or not setVisibleLabels(sign) then
			sign:Destroy()
			return nil
		end
		sign.Parent = parent
	else
		sanitizeClone(sign)
		setVisibleLabels(sign)
	end
	local board = displayBoard(sign)
	if not board then
		return nil
	end
	placeSign(sign, board, salePoint)
	return sign
end

local function ensurePrompt(salePoint: BasePart): ProximityPrompt
	local prompt: ProximityPrompt? = nil
	for _, child in salePoint:GetChildren() do
		if
			child:IsA("ProximityPrompt")
			and child.Name == PROMPT_NAME
			and child:GetAttribute("ManagedBy") == MANAGED_BY
		then
			if prompt == nil then
				prompt = child
			else
				child:Destroy()
			end
		end
	end
	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt:SetAttribute("ManagedBy", MANAGED_BY)
		prompt.Parent = salePoint
	end
	if BrainrotSalePointSystem.UsesCampMenu() then
		-- Counter prompt opens the Sell menu (brainrots + Cash weapons/carts at 25% back).
		prompt.ActionText = "Open"
		prompt.ObjectText = "SELL"
	else
		prompt.ActionText = "Sell Brainrot"
		prompt.ObjectText = SIGN_TEXT
	end
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = InteractionConfig.SELL_INTERACTION_DISTANCE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.ClickablePrompt = true
	prompt.Enabled = true
	return prompt
end

function BrainrotSalePointSystem:EnsureSalePoint(): boolean
	local salePoint, parent = resolveSalePoint()
	local skipLegacySign = BrainrotSalePointSystem.UsesCampMenu() or campSellStallPresent()
	if salePoint and parent and skipLegacySign then
		warnedUnavailable = false
		for _, child in parent:GetChildren() do
			if child:IsA("Model") and child.Name == SIGN_NAME and child:GetAttribute("ManagedBy") == MANAGED_BY then
				child:Destroy()
			end
		end
		registeredPrompt = ensurePrompt(salePoint)
		registeredSalePoint = salePoint
		return true
	end
	local source = resolveTemplate()
	if not salePoint or not parent or not source then
		registeredPrompt, registeredSalePoint = nil, nil
		if not warnedUnavailable then
			warnedUnavailable = true
			log:Warn(
				"Sale point unavailable: expected Workspace.MapBlockout.ServiceStallPatches.SellStall and ReplicatedStorage.StudioAssets.BaseSigns.Sell Sign"
			)
		end
		return false
	end
	warnedUnavailable = false
	local sign = ensureSign(salePoint, parent, source)
	if not sign then
		registeredPrompt, registeredSalePoint = nil, nil
		log:Warn("Sale sign unavailable: canonical template has no visible SurfaceGui label")
		return false
	end
	registeredPrompt = ensurePrompt(salePoint)
	registeredSalePoint = salePoint
	return true
end

function BrainrotSalePointSystem:HandlePromptTriggered(
	prompt: ProximityPrompt,
	player: Player
): boolean
	if
		not started
		or prompt ~= registeredPrompt
		or prompt.Parent ~= registeredSalePoint
		or registeredSalePoint == nil
		or not registeredSalePoint:IsDescendantOf(Workspace)
	then
		return false
	end
	if BrainrotSalePointSystem.UsesCampMenu() then
		-- The Sell menu offers the carried brainrot (existing preview dialog) plus sell-back rows.
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local update = remotes and remotes:FindFirstChild("Phase13Update")
		if update and update:IsA("RemoteEvent") then
			update:FireClient(player, { kind = "Open", category = "Sell" })
			return true
		end
	end
	-- CreatePreview owns current carry/ownership/catalogue/range validation and
	-- fires OpenBrainrotSaleDialog only when it returns a sanitized preview.
	local preview = BrainrotSaleSystem:CreatePreview(player)
	return preview ~= nil
end

local function queueSetup(currentGeneration: number)
	if setupQueued then
		return
	end
	setupQueued = true
	task.defer(function()
		setupQueued = false
		if started and generation == currentGeneration then
			BrainrotSalePointSystem:EnsureSalePoint()
		end
	end)
end

function BrainrotSalePointSystem:Start(): boolean
	if started then
		return self:EnsureSalePoint()
	end
	started = true
	generation += 1
	local currentGeneration = generation
	table.insert(
		connections,
		ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
			self:HandlePromptTriggered(prompt, player)
		end)
	)
	table.insert(
		connections,
		Workspace.DescendantAdded:Connect(function(instance)
			if
				instance.Name == "MapBlockout"
				or instance.Name == "ServiceStallPatches"
				or instance.Name == "SellStall"
			then
				queueSetup(currentGeneration)
			end
		end)
	)
	table.insert(
		connections,
		ReplicatedStorage.DescendantAdded:Connect(function(instance)
			if
				instance.Name == "StudioAssets"
				or instance.Name == "BaseSigns"
				or instance.Name == "Sell Sign"
			then
				queueSetup(currentGeneration)
			end
		end)
	)
	return self:EnsureSalePoint()
end

function BrainrotSalePointSystem:Stop()
	started = false
	generation += 1
	setupQueued = false
	disconnectAll()
	if
		registeredPrompt
		and registeredPrompt.Parent
		and registeredPrompt:GetAttribute("ManagedBy") == MANAGED_BY
	then
		registeredPrompt:Destroy()
	end
	registeredPrompt, registeredSalePoint = nil, nil
end

return BrainrotSalePointSystem
