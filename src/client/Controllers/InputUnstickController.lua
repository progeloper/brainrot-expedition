--!strict
-- Playtest Fixes 2, Part A: the game never gets stuck.
--   * DEV trace (always on in Studio; live only with ReplicatedStorage.InputTrace = true): every
--     blocked drive/fire press logs the menu attributes, SelectedObject, CarriedItemId, the cart
--     assembly state and the input-gate fields. Throttled to one line per second.
--   * Flag-gated (InputUnstick): a 1 Hz watchdog that heals open-menu attributes with no matching
--     visible window, warns when a seated driver stays blocked, makes HUD buttons non-selectable
--     (the two HUD windows get D-pad Left/Right shortcuts in the client Bootstrap).
-- Attribute reads only; no remotes. The server stays authoritative for every action.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config.PlaytestFixes2).InputUnstick
local InputRegistry = require(ReplicatedStorage.Shared.Config.CartInputRegistry)
local InputUnstick = require(script.Parent.Parent.Utility.InputUnstick)
local Policy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local MenusV2 = require(script.Parent.Parent.UI.MenusV2)

local player = Players.LocalPlayer
local Controller = {}
local started = false

local MENU_ATTRIBUTES = {
	"MenusV2Open",
	"Phase13ShopOpen",
	"ChariotTeamMenuOpen",
	"RetentionPublicInspectOpen",
	"Phase13CinematicActive",
	"Phase13ConsentDialogOpen",
	"Phase13CompareDialogOpen",
}

local DRIVE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonL2] = true,
}
local FIRE_KEYS: { [Enum.KeyCode]: boolean } = {
	[InputRegistry.Fire.Keyboard] = true,
	[InputRegistry.Fire.Gamepad] = true,
}

local function traceOn(): boolean
	return RunService:IsStudio() or ReplicatedStorage:GetAttribute("InputTrace") == true
end

local function seatedCart(): (Model?, boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return nil, false
	end
	local node: Instance? = seat
	while node and not (node:IsA("Model") and node:GetAttribute("RuntimeCart") == true) do
		node = node.Parent
	end
	local cart = if node and node:IsA("Model") then node else nil
	local driver = cart ~= nil and cart:GetAttribute("ActiveDriverUserId") == player.UserId
	return cart, driver
end

-- One line describing everything that can block a drive or fire press.
function Controller.Snapshot(): string
	local parts = {}
	for _, name in MENU_ATTRIBUTES do
		local value = player:GetAttribute(name)
		if value ~= nil and value ~= false then
			table.insert(parts, string.format("%s=%s", name, tostring(value)))
		end
	end
	local selected = GuiService.SelectedObject
	table.insert(parts, "Selected=" .. (if selected then selected:GetFullName() else "nil"))
	table.insert(parts, "CoreMenu=" .. tostring(GuiService.MenuIsOpen))
	table.insert(parts, "TextBox=" .. tostring(UserInputService:GetFocusedTextBox() ~= nil))
	table.insert(parts, "Dazed=" .. tostring(Policy.IsDazed(player)))
	table.insert(parts, "Carried=" .. tostring(player:GetAttribute("CarriedItemId")))
	local cart, driver = seatedCart()
	if cart then
		table.insert(
			parts,
			string.format(
				"Cart=%s driver=%s assembly=%s",
				cart.Name,
				tostring(driver),
				tostring(cart:GetAttribute("AssemblyValidationState"))
			)
		)
	end
	table.insert(
		parts,
		"IsMenuOpen=" .. tostring(Policy.IsMenuOpen(player, GuiService, UserInputService))
	)
	table.insert(parts, "Unstick=" .. tostring(InputUnstick.Enabled()))
	return table.concat(parts, " ")
end

local function blockedNow(): boolean
	if Policy.IsBlocked(player, GuiService, UserInputService) then
		return true
	end
	if player:GetAttribute("CarriedItemId") ~= nil then
		return true
	end
	local cart, driver = seatedCart()
	return cart ~= nil and driver and cart:GetAttribute("AssemblyValidationState") ~= "Valid"
end

local lastTraceAt = -math.huge
local function trace(kind: string, input: InputObject)
	if not traceOn() or os.clock() - lastTraceAt < Config.TraceCooldownSeconds then
		return
	end
	if not blockedNow() then
		return
	end
	lastTraceAt = os.clock()
	print(
		string.format(
			"[InputUnstick] blocked %s (%s): %s",
			kind,
			input.KeyCode.Name,
			Controller.Snapshot()
		)
	)
end

--------------------------------------------------------------------------------
-- Watchdog (flag-gated)
--------------------------------------------------------------------------------

local staleCounts: { [string]: number } = {}
local seatedBlockedTicks = 0

local function devWarn(text: string)
	if traceOn() then
		warn("[InputUnstick] " .. text)
	end
end

local function staleFor(key: string, stale: boolean): boolean
	if not stale then
		staleCounts[key] = 0
		return false
	end
	staleCounts[key] = (staleCounts[key] or 0) + 1
	if staleCounts[key] >= Config.StaleTicks then
		staleCounts[key] = 0
		return true
	end
	return false
end

local function tick()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	-- MenusV2Open with no MenusV2 window (or none drawn)
	local menusAttr = InputUnstick.AttributeSet(player:GetAttribute("MenusV2Open"))
	local menusStale = menusAttr and (MenusV2.currentId() == nil or not MenusV2.anyDrawn())
	if staleFor("MenusV2Open", menusStale) and MenusV2.healStale() then
		devWarn("healed stale MenusV2Open")
	end
	-- Phase13ShopOpen without the shop window
	local shopStale = player:GetAttribute("Phase13ShopOpen") == true
		and MenusV2.currentId() ~= "shop"
	if staleFor("Phase13ShopOpen", shopStale) then
		local ok, healed = pcall(function()
			return (require(script.Parent.Phase13ShopController) :: any).HealStale()
		end)
		if ok and healed then
			devWarn("healed stale Phase13ShopOpen")
		end
	end
	-- ChariotTeamMenuOpen without the Team window
	local teamStale = player:GetAttribute("ChariotTeamMenuOpen") == true
		and MenusV2.currentId() ~= "Team"
	if staleFor("ChariotTeamMenuOpen", teamStale) then
		local ok, healed = pcall(function()
			return (require(script.Parent.ChariotTeamController) :: any).HealStale()
		end)
		if ok and healed then
			devWarn("healed stale ChariotTeamMenuOpen")
		elseif player:GetAttribute("ChariotTeamMenuOpen") == true then
			player:SetAttribute("ChariotTeamMenuOpen", nil)
			devWarn("cleared stale ChariotTeamMenuOpen")
		end
	end
	-- RetentionPublicInspectOpen: nothing in the current client sets it, so any value is stale.
	if
		staleFor(
			"RetentionPublicInspectOpen",
			player:GetAttribute("RetentionPublicInspectOpen") == true
		)
	then
		player:SetAttribute("RetentionPublicInspectOpen", nil)
		devWarn("cleared stale RetentionPublicInspectOpen")
	end
	-- Phase13CompareDialogOpen without its dialog gui
	local compareStale = player:GetAttribute("Phase13CompareDialogOpen") == true
		and (playerGui == nil or playerGui:FindFirstChild("Phase13PlatformComparison") == nil)
	if staleFor("Phase13CompareDialogOpen", compareStale) then
		player:SetAttribute("Phase13CompareDialogOpen", nil)
		devWarn("cleared stale Phase13CompareDialogOpen")
	end
	-- A selection that is hidden/orphaned, or outside any open menu, only hijacks the stick and A.
	local selected = GuiService.SelectedObject
	local selectionStale = selected ~= nil
		and not InputUnstick.SelectionBlocks(selected, playerGui, function(name)
			return player:GetAttribute(name)
		end)
	if staleFor("SelectedObject", selectionStale) and InputUnstick.ClearSelection(nil, nil) then
		devWarn(
			"cleared stray SelectedObject " .. (if selected then selected:GetFullName() else "?")
		)
	end
	-- A4: a seated driver who stays blocked
	local cart, driver = seatedCart()
	if cart and driver and blockedNow() then
		seatedBlockedTicks += 1
		if seatedBlockedTicks * (1 / Config.WatchdogHz) > Config.SeatedBlockWarnSeconds then
			devWarn("seated driver blocked: " .. Controller.Snapshot())
			seatedBlockedTicks = 0
		end
	else
		seatedBlockedTicks = 0
	end
end

--------------------------------------------------------------------------------
-- A3: HUD buttons are not auto-selectable
--------------------------------------------------------------------------------

local function unselectable(object: Instance)
	if
		object:IsA("GuiButton")
		and object.Selectable
		and object:GetAttribute("PadSelectable") ~= true
	then
		local layer = InputUnstick.LayerOf(object)
		if layer and InputUnstick.MenuGuis[layer.Name] == nil and layer.Name ~= "TouchGui" then
			object.Selectable = false
		end
	end
end

local function watchHudButtons(playerGui: PlayerGui)
	for _, d in playerGui:GetDescendants() do
		unselectable(d)
	end
	playerGui.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then
			-- wait a frame: builders set Parent before their own Selectable/name properties
			task.defer(unselectable, d)
		end
	end)
end

function Controller.Start()
	if started then
		return
	end
	started = true
	-- DEV trace: keyboard/gamepad drive + fire presses, mouse fire, touch is traced on the stick.
	UserInputService.InputBegan:Connect(function(input)
		if DRIVE_KEYS[input.KeyCode] then
			trace("drive", input)
		elseif
			FIRE_KEYS[input.KeyCode] or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			trace("fire", input)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			trace("touch", input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.6 then
			trace("drive", input)
		end
	end)
	if not InputUnstick.Enabled() then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	watchHudButtons(playerGui)
	task.spawn(function()
		while true do
			task.wait(1 / Config.WatchdogHz)
			local ok, err = pcall(tick)
			if not ok then
				devWarn("watchdog error: " .. tostring(err))
			end
		end
	end)
end

return Controller
