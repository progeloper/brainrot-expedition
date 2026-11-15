--!strict
-- Playtest Fixes 2, Part A (InputUnstick): selection and menu-state helpers shared by MenusV2, the
-- input policy and the unstick watchdog. Pure helpers take their inputs; the rest read the
-- local player. No remotes, no server state.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flags = require(ReplicatedStorage.Shared.Config.PlaytestFixes2Flags)

local InputUnstick = {}

-- Menu ScreenGuis and the player attributes that say each one is open.
InputUnstick.MenuGuis = table.freeze({
	MenusV2 = table.freeze({ "MenusV2Open", "Phase13ConsentDialogOpen" }),
	Phase13PlatformComparison = table.freeze({ "Phase13CompareDialogOpen" }),
} :: { [string]: { string } })

function InputUnstick.Enabled(): boolean
	return Flags.Part("InputUnstick")
end

local function attributeSet(value: any): boolean
	return value ~= nil and value ~= false and value ~= ""
end
InputUnstick.AttributeSet = attributeSet

-- The ScreenGui (LayerCollector) a GUI object sits in, or nil.
function InputUnstick.LayerOf(object: Instance): LayerCollector?
	local node: Instance? = object
	while node do
		if node:IsA("LayerCollector") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- True when `object` is drawn: every GuiObject up the chain is Visible and its layer is Enabled
-- and parented under `root` (the PlayerGui).
function InputUnstick.IsShown(object: Instance?, root: Instance?): boolean
	if typeof(object) ~= "Instance" or not object:IsA("GuiObject") or not root then
		return false
	end
	local node: Instance? = object
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return node == root
end

-- Pure: should this selection count as "a menu is open"? Only when it is a visible descendant of a
-- menu ScreenGui whose open attribute is set. `getAttribute(name)` reads the player's attribute.
function InputUnstick.SelectionBlocks(
	selected: Instance?,
	root: Instance?,
	getAttribute: (string) -> any
): boolean
	if typeof(selected) ~= "Instance" or not InputUnstick.IsShown(selected, root) then
		return false
	end
	local layer = InputUnstick.LayerOf(selected :: Instance)
	local attributes = layer and InputUnstick.MenuGuis[layer.Name]
	if not attributes then
		return false
	end
	for _, name in attributes do
		if attributeSet(getAttribute(name)) then
			return true
		end
	end
	return false
end

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

-- A1: clear GuiService.SelectedObject when it is orphaned/hidden, or (with `closing`) inside the
-- window that is closing. A selection inside `keep` (the window that stays/opens) survives.
-- Returns true when it cleared the selection.
function InputUnstick.ClearSelection(closing: Instance?, keep: Instance?): boolean
	local selected = GuiService.SelectedObject
	if not selected then
		return false
	end
	local root = playerGui()
	if keep and selected:IsDescendantOf(keep) and InputUnstick.IsShown(selected, root) then
		return false
	end
	local player = Players.LocalPlayer
	local orphaned = not InputUnstick.IsShown(selected, root)
	local inClosing = closing ~= nil and selected:IsDescendantOf(closing)
	-- With no menu open at all, a stray selection (e.g. a HUD button) only hijacks the stick and A.
	local inOpenMenu = player ~= nil
		and InputUnstick.SelectionBlocks(selected, root, function(name)
			return player:GetAttribute(name)
		end)
	if orphaned or inClosing or not inOpenMenu then
		GuiService.SelectedObject = nil
		return true
	end
	return false
end

-- A3: the first selectable, visible GuiButton inside `window` (layout order, then reading order).
function InputUnstick.FirstSelectable(window: Instance): GuiObject?
	local root = playerGui()
	local best: GuiObject? = nil
	local bestKey = math.huge
	for _, d in window:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Active and InputUnstick.IsShown(d, root) then
			local p = d.AbsolutePosition
			local key = p.Y * 100000 + p.X
			if key < bestKey then
				best, bestKey = d, key
			end
		end
	end
	return best
end

return table.freeze(InputUnstick)
