--!nocheck
-- Menu navigation core for the Stud Pop Plate windows (view + navigation only).
--   * one ScreenGui "MenusV2" holds every Plate window; only one window is open at a time
--   * Back / Escape / ButtonB closes the top window; B opens Brainrots, I opens Inventory
--   * stall windows auto-close (with their close animation) when the player walks more than
--     MaxActivationDistance + 6 studs from the stall prompt, dies, or drives off in a cart (5 Hz check)
-- Screens register themselves; controllers keep every remote call.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local StudPop = require(ReplicatedStorage.Shared.UI.StudPop)
-- Playtest Fixes 2 Part A (flag-gated): every close clears its selection; menus pick their own first
-- gamepad selection; gamepad B always closes the top window.
local InputUnstick = require(script.Parent.Parent.Utility.InputUnstick)

local MenusV2 = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local current: { id: string, close: (boolean?) -> (), anchor: ProximityPrompt?, at: number }? = nil
local watchToken = 0
local hotkeys: { [Enum.KeyCode]: () -> () } = {}
local started = false

function MenusV2.Gui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = StudPop.ScreenGui("MenusV2", 75)
	g:SetAttribute("StudPopOwned", true)
	gui = g
	return g
end

local function seated(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart ~= nil
end

-- 5 Hz: leave the stall, die or drive off -> close (animated).
local function watchStall(prompt: ProximityPrompt, token: number)
	task.spawn(function()
		local wasSeated = seated()
		while token == watchToken and current and current.anchor == prompt do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local part = prompt.Parent
			local pos = if part and part:IsA("BasePart") then part.Position
				elseif part and part:IsA("Attachment") then part.WorldPosition
				elseif part and part:IsA("Model") then part:GetPivot().Position
				else nil
			local tooFar = root and pos and (root.Position - pos).Magnitude > prompt.MaxActivationDistance + 6
			local dead = not hum or hum.Health <= 0
			local droveOff = seated() and not wasSeated
			if tooFar or dead or droveOff or not prompt.Parent then
				MenusV2.closeCurrent()
				return
			end
			task.wait(0.2)
		end
	end)
end

local function gamepadLast(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

-- The visible Plate window frames ("<key>_Window") in the menus gui.
function MenusV2.visibleWindows(): { GuiObject }
	local out = {}
	local g = gui
	if g and g.Parent then
		for _, child in g:GetChildren() do
			if child:IsA("GuiObject") and child.Visible and child.Name:sub(-7) == "_Window" then
				table.insert(out, child)
			end
		end
	end
	return out
end

-- True when anything at all is drawn in the menus gui (any visible child). The watchdog only heals
-- when this is false, so a window that is not a Plate "_Window" frame is never closed by mistake.
function MenusV2.anyDrawn(): boolean
	local g = gui
	if g and g.Parent then
		for _, child in g:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				return true
			end
		end
	end
	return false
end

-- A1: after a window closes (or is replaced) the selection never outlives it.
local function clearSelectionAfterClose()
	if not InputUnstick.Enabled() then
		return
	end
	if current then
		-- replaced: drop any selection; the new window picks its own below
		GuiService.SelectedObject = nil
	else
		InputUnstick.ClearSelection(gui, nil)
	end
end

-- A3: on a gamepad, the opening window selects its first button once it has drawn.
local function pickFirstSelection(token: number)
	if not InputUnstick.Enabled() then
		return
	end
	task.delay(0.25, function()
		if
			token ~= watchToken
			or not current
			or GuiService.SelectedObject ~= nil
			or not gamepadLast()
		then
			return
		end
		local windows = MenusV2.visibleWindows()
		local window = windows[#windows]
		local first = window and InputUnstick.FirstSelectable(window)
		if first then
			GuiService.SelectedObject = first
		end
	end)
end

-- Opens `id` (closing any other window first). `close` runs the screen's animated close.
function MenusV2.setOpen(id: string, close: (boolean?) -> (), anchor: ProximityPrompt?)
	local replaced = false
	if current and current.id ~= id then
		local prev = current
		current = nil
		prev.close(false)
		replaced = true
	end
	current = { id = id, close = close, anchor = anchor, at = os.clock() }
	player:SetAttribute("MenusV2Open", id)
	watchToken += 1
	if replaced then
		clearSelectionAfterClose()
	end
	if anchor then
		watchStall(anchor, watchToken)
	end
	pickFirstSelection(watchToken)
end

-- Screens call this when they finish closing (by ✕, scrim or code).
function MenusV2.cleared(id: string)
	if current and current.id == id then
		current = nil
		player:SetAttribute("MenusV2Open", nil)
		watchToken += 1
		clearSelectionAfterClose()
	end
end

function MenusV2.closeCurrent()
	if current then
		local c = current
		current = nil
		player:SetAttribute("MenusV2Open", nil)
		watchToken += 1
		c.close(false)
		clearSelectionAfterClose()
	end
end

-- A2 watchdog: the attribute says a window is open but MenusV2 holds none (or none is drawn).
-- Clears the state without running a close animation; returns true when it healed something.
function MenusV2.healStale(): boolean
	local attr = player:GetAttribute("MenusV2Open")
	if current == nil and InputUnstick.AttributeSet(attr) then
		player:SetAttribute("MenusV2Open", nil)
		watchToken += 1
		InputUnstick.ClearSelection(gui, nil)
		return true
	end
	if current ~= nil and not MenusV2.anyDrawn() and os.clock() - current.at > 1 then
		local c = current
		current = nil
		player:SetAttribute("MenusV2Open", nil)
		watchToken += 1
		pcall(c.close, true)
		InputUnstick.ClearSelection(gui, nil)
		return true
	end
	return false
end

-- The stall/base prompt the player just used (the server's Open event doesn't name it): the nearest
-- enabled shop prompt within its activation range.
local PROMPT_NAMES = {
	Phase13ShopPrompt = true,
	SellBrainrotPrompt = true,
	Phase13BaseUpgradePrompt = true,
	PassesKioskPrompt = true, -- Gems stall (Playtest Fixes F2); only used when that window anchors
}
function MenusV2.nearestPrompt(): ProximityPrompt?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDist = nil, math.huge
	-- every stall, sell counter and base entrance prompt lives under MapBlockout (DATA_CONTRACT §2)
	local scope = workspace:FindFirstChild("MapBlockout") or workspace
	for _, d in scope:GetDescendants() do
		if d:IsA("ProximityPrompt") and PROMPT_NAMES[d.Name] then
			local parent = d.Parent
			local pos = if parent and parent:IsA("BasePart") then parent.Position
				elseif parent and parent:IsA("Attachment") then parent.WorldPosition
				else nil
			if pos then
				local dist = (root.Position - pos).Magnitude
				if dist < bestDist and dist <= d.MaxActivationDistance + 4 then
					best, bestDist = d, dist
				end
			end
		end
	end
	return best
end

function MenusV2.currentId(): string?
	return current and current.id or nil
end

-- Seconds since the current window was (re)opened; math.huge when nothing is open.
function MenusV2.currentAge(): number
	return if current then os.clock() - current.at else math.huge
end

function MenusV2.bindKey(key: Enum.KeyCode, fn: () -> ())
	hotkeys[key] = fn
end

function MenusV2.Start()
	if started then
		return false
	end
	started = true
	MenusV2.Gui()
	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		-- Escape is taken by Roblox's own menu on PC; Backspace and gamepad B close the top window.
		-- With a window open, gamepad B closes it even when the engine also used B to drop the
		-- selection (processed), so one press always closes (Playtest Fixes 2, A1).
		-- The Team window owns B itself (it steps back out of sub-views first).
		local padBack = k == Enum.KeyCode.ButtonB
			and current ~= nil
			and InputUnstick.Enabled()
			and player:GetAttribute("ChariotTeamMenuOpen") ~= true
		if
			(not processed or padBack)
			and (
				k == Enum.KeyCode.Escape
				or k == Enum.KeyCode.ButtonB
				or k == Enum.KeyCode.Backspace
			)
		then
			if current then
				MenusV2.closeCurrent()
			end
			return
		end
		local fn = hotkeys[k]
		if fn and not GuiService.MenuIsOpen then
			fn()
		end
	end)
	player.CharacterRemoving:Connect(function()
		MenusV2.closeCurrent()
	end)
	return true
end

return MenusV2
