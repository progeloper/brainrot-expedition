--!strict

-- Binds the purchase interface only to an explicitly authored existing stall.
-- This task does not create map geometry or guess from thematic names.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local UpgradeService = require(script.Parent.Parent.Services.UpgradeService)

local STALL_TAG = "CartUpgradeStall"
local PROMPT_NAME = "CartUpgradePrompt"
local MANAGED_BY = "CartUpgradePointSystem"

local CartUpgradePointSystem = {}
local log = Logger.new("CartUpgradePointSystem")
local started = false
local prompt: ProximityPrompt? = nil
local stall: BasePart? = nil
local connections: { any } = {}
local warnedCode: string? = nil

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function resolveStall(): (BasePart?, string?)
	local candidates = {}
	for _, tagged in CollectionService:GetTagged(STALL_TAG) do
		if tagged:IsA("BasePart") and tagged:IsDescendantOf(Workspace) then
			table.insert(candidates, tagged)
		end
	end
	if #candidates == 0 then
		return nil, "MISSING_TAGGED_STALL"
	elseif #candidates > 1 then
		return nil, "AMBIGUOUS_TAGGED_STALL"
	end
	return candidates[1], nil
end

local function warnOnce(code: string)
	if warnedCode == code then
		return
	end
	warnedCode = code
	log:Warn(
		"Cart upgrade point unavailable code=%s; author exactly one existing BasePart with CollectionService tag %s",
		code,
		STALL_TAG
	)
end

local function ensurePrompt(target: BasePart): ProximityPrompt
	local found: ProximityPrompt? = nil
	for _, child in target:GetChildren() do
		if
			child:IsA("ProximityPrompt")
			and child.Name == PROMPT_NAME
			and child:GetAttribute("ManagedBy") == MANAGED_BY
		then
			if found == nil then
				found = child
			else
				child:Destroy()
			end
		end
	end
	if found == nil then
		found = Instance.new("ProximityPrompt")
		found.Name = PROMPT_NAME
		found:SetAttribute("ManagedBy", MANAGED_BY)
		found.Parent = target
	end
	found.ActionText = "Upgrade Cart"
	found.ObjectText = "Cart Upgrades"
	found.KeyboardKeyCode = Enum.KeyCode.E
	found.GamepadKeyCode = Enum.KeyCode.ButtonX
	found.MaxActivationDistance = InteractionConfig.SELL_INTERACTION_DISTANCE
	found.HoldDuration = 0
	found.RequiresLineOfSight = false
	found.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	found.ClickablePrompt = true
	found.Enabled = true
	return found
end

function CartUpgradePointSystem:EnsurePoint(): boolean
	local resolved, reason = resolveStall()
	if resolved == nil then
		prompt, stall = nil, nil
		warnOnce(reason or "STALL_UNAVAILABLE")
		return false
	end
	warnedCode = nil
	stall = resolved
	prompt = ensurePrompt(resolved)
	return true
end

function CartUpgradePointSystem:HandlePromptTriggered(
	triggeredPrompt: ProximityPrompt,
	player: Player
): boolean
	if
		not started
		or triggeredPrompt ~= prompt
		or stall == nil
		or triggeredPrompt.Parent ~= stall
		or not stall:IsDescendantOf(Workspace)
	then
		return false
	end
	local result = UpgradeService:OpenShop(player, stall)
	return result.ok == true
end

function CartUpgradePointSystem:Start(): boolean
	if started then
		return self:EnsurePoint()
	end
	started = true
	table.insert(
		connections,
		ProximityPromptService.PromptTriggered:Connect(function(triggeredPrompt, player)
			self:HandlePromptTriggered(triggeredPrompt, player)
		end)
	)
	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal(STALL_TAG):Connect(function()
			self:EnsurePoint()
		end)
	)
	table.insert(
		connections,
		CollectionService:GetInstanceRemovedSignal(STALL_TAG):Connect(function()
			self:EnsurePoint()
		end)
	)
	return self:EnsurePoint()
end

function CartUpgradePointSystem:Stop()
	started = false
	disconnectAll()
	if prompt and prompt.Parent and prompt:GetAttribute("ManagedBy") == MANAGED_BY then
		prompt:Destroy()
	end
	prompt, stall = nil, nil
	warnedCode = nil
end

return CartUpgradePointSystem
