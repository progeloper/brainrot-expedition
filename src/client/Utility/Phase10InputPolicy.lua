--!strict

-- UI mirrors only. Server interaction/driver authority checks the same deadlines.
local Workspace = game:GetService("Workspace")
local InputUnstick = require(script.Parent.InputUnstick)
local Policy = {}

function Policy.IsDazed(player: any, now: number?): boolean
	if not player or type(player.GetAttribute) ~= "function" then
		return false
	end
	local deadline = player:GetAttribute("Phase10DazeEnd")
	return type(deadline) == "number" and deadline > (now or Workspace:GetServerTimeNow())
end

-- Playtest Fixes 2 Part A: with InputUnstick on, a GUI selection blocks gameplay only when it is a
-- visible descendant of an open menu gui (a stale HUD/orphaned selection never blocks).
local function selectionBlocks(player: any, guiService: any, unstick: boolean?): boolean
	local selected = guiService.SelectedObject
	if selected == nil then
		return false
	end
	local on = if unstick == nil then InputUnstick.Enabled() else unstick
	if not on then
		return true
	end
	local root = if type(player.FindFirstChildOfClass) == "function"
		then player:FindFirstChildOfClass("PlayerGui")
		else nil
	return InputUnstick.SelectionBlocks(selected, root, function(name)
		return if type(player.GetAttribute) == "function" then player:GetAttribute(name) else nil
	end)
end

-- `unstick` overrides the InputUnstick flag (tests only).
function Policy.IsMenuOpen(
	player: any,
	guiService: any,
	inputService: any,
	unstick: boolean?
): boolean
	if not player then
		return false
	end
	-- every Plate window (stalls, Brainrots, Inventory, Team, Cargo bay, gate, dialogs) registers
	-- through MenusV2.setOpen, which publishes its id in MenusV2Open
	if
		guiService.MenuIsOpen
		or selectionBlocks(player, guiService, unstick)
		or inputService:GetFocusedTextBox() ~= nil
		or (
			type(player.GetAttribute) == "function"
			and (
				-- every Plate window (stalls, Brainrots, Inventory, Team, Cargo bay, gate, dialogs)
				-- registers through MenusV2.setOpen, which publishes its id here
				(type(player:GetAttribute("MenusV2Open")) == "string" and player:GetAttribute("MenusV2Open") ~= "")
				or player:GetAttribute("Phase13ShopOpen") == true
				or player:GetAttribute("ChariotTeamMenuOpen") == true
				or player:GetAttribute("RetentionPublicInspectOpen") == true
			)
		)
	then
		return true
	end
	return false
end

function Policy.IsBlocked(player: any, guiService: any, inputService: any): boolean
	return Policy.IsDazed(player) or Policy.IsMenuOpen(player, guiService, inputService)
end

function Policy.IsPointerInteraction(player: any, position: Vector2): boolean
	if not player or type(player.FindFirstChildOfClass) ~= "function" then
		return false
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	-- Run only for a primary press, not per frame. Native processed input also
	-- rejects CoreGui chat/prompts before the hunting listener reaches this.
	for _, object in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		local ancestor: Instance? = object
		while ancestor and ancestor ~= playerGui do
			if ancestor:IsA("GuiButton") or ancestor:IsA("TextBox") then
				return true
			end
			if ancestor:IsA("GuiObject") and ancestor.Active then
				return true
			end
			ancestor = ancestor.Parent
		end
	end
	return false
end

function Policy.IsCargoShieldProtected(visual: Instance, now: number?): boolean
	local container = visual.Parent
	local cart = if container and container.Name == "CargoVisuals" then container.Parent else nil
	if not cart or not cart:IsA("Model") or cart:GetAttribute("RuntimeCart") ~= true then
		return false
	end
	local remaining = cart:GetAttribute("ShieldRemaining")
	local expires = cart:GetAttribute("ShieldProtectionExpiresAt")
	return (type(remaining) == "number" and remaining > 0)
		or (type(expires) == "number" and expires > (now or Workspace:GetServerTimeNow()))
end

return table.freeze(Policy)
