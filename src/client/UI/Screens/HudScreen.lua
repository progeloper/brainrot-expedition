--!nocheck
-- The HUD (view only):
--   top-left  Cash pill (player attribute `Cash`) + Gem pill (attribute `Gems`), count-up on change;
--             display only. Below them, live chips for an active 2× Cash boost / Mutation Storm.
--   rail      exactly two menu buttons: Brainrots (pink) and Inventory (blue). Shops open only at
--             their camp stalls; Rebirth at the base entrance; Settings is the gear in Inventory.
--             Landscape phones: one row under the pills. Taller screens: a left column.
-- The contextual action (PICK UP / LOAD / PLACE / DROP) stays in ExactHud bottom-right; its status
-- rows hang top-right (StatusAnchor). While a menu is open the HUD steps aside.
-- Income (+$X/s) is not shown: the game publishes no total income rate and the UI must not compute one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudPopUI = require(script.Parent.Parent.StudPopUI)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)
local Theme = StudPopUI.Theme
local StudPop = StudPopUI.StudPop

local Screen = {}

local gui: ScreenGui? = nil
local rail: Frame? = nil
local pill = nil
local gemPill = nil
-- Playtest Fixes 2 C3: the counter rolls when the first claim coin lands (see Screen.HoldCash).
local cashPadsOn =
	require(game:GetService("ReplicatedStorage").Shared.Config.PlaytestFixes2Flags).Part("CashPads")
local cashHoldUntil = 0
local cashHeld = false
local chips = nil
local settingsRoot: GuiObject? = nil
local railButtons = {}
local connections = {}
local actions = {}
local menuOpen = false

export type Actions = {
	openBrainrots: (() -> ())?, -- the two HUD windows
	openInventory: (() -> ())?,
}

-- Baseline (844x390) sizes; Theme.px grows them up to Theme.MaxScale on bigger screens.
local SIZE = {
	Margin = 10,
	Gap = 8,
	PillH = 44,
	CashW = 180,
	GemW = 170,
	PillGap = 14, -- room for the pills' oversized icons, which deliberately break out of the pill
	ChipH = 40,
	ChipW = 150,
	CellW = 58,
	CellH = 70,
	Settings = 48,
}

local px = Theme.px

local function cashValue(): number
	local v = Players.LocalPlayer:GetAttribute("Cash")
	return if type(v) == "number" then v else 0
end

local function gemValue(): number
	local v = Players.LocalPlayer:GetAttribute("Gems")
	return if type(v) == "number" then v else 0
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function wideScreen(): boolean
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	return vp.X / math.max(vp.Y, 1) > 1.6
end

local function pillSize(p, w: number)
	p.Root.Size = UDim2.fromOffset(px(w), px(SIZE.PillH))
	local a = p.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if a then
		a.AspectRatio = w / SIZE.PillH
	end
	-- the kit's row (icon + 52% amount + "+") is wider than the pill; narrow the amount so the
	-- "+" stays inside its own pill instead of covering the next one
	local row = p.Root:FindFirstChild("Content")
	local amount = row and row:FindFirstChild("Label")
	if amount and amount:IsA("GuiObject") then
		amount.Size = UDim2.fromScale(0.36, 1)
	end
	-- the "+" stays a 48 px tap target; icon-only (the kit draws both the icon and a "+" label)
	local plus = p.Root:FindFirstChild("Button_+", true)
	if plus and plus:IsA("GuiObject") then
		plus.Size = UDim2.fromScale(0.28, 1.2)
		local min = plus:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
		min.MinSize = Vector2.new(px(Theme.Size.TouchMin), px(Theme.Size.TouchMin))
		min.Parent = plus
		local plusLabel = plus:FindFirstChild("Label", true)
		if plusLabel and plusLabel:IsA("GuiObject") and Theme.Icons.Plus ~= "" then
			plusLabel.Visible = false
		end
	end
end

local function layout()
	if not rail or not gui or not pill then
		return
	end
	local m, g = px(SIZE.Margin), px(SIZE.Gap)
	pill.Root.Position = UDim2.fromOffset(m, m)
	pillSize(pill, SIZE.CashW)
	if gemPill then
		gemPill.Root.Position = UDim2.fromOffset(m + px(SIZE.CashW) + px(SIZE.PillGap), m)
		pillSize(gemPill, SIZE.GemW)
	end
	local y = m + px(SIZE.PillH) + g
	if chips then
		chips.Position = UDim2.fromOffset(m, y)
		chips.Size = UDim2.fromOffset(2 * px(SIZE.ChipW) + g, px(SIZE.ChipH))
		if chips.Visible then
			y += px(SIZE.ChipH) + g
		end
	end
	local visible = 0
	for _, b in railButtons do
		if b.Visible then
			visible += 1
		end
	end
	local wide = wideScreen()
	local columns = if wide then math.max(visible, 1) else 1
	local rows = math.ceil(visible / columns)
	local grid = rail:FindFirstChildOfClass("UIGridLayout")
	local cw, ch = px(SIZE.CellW), px(SIZE.CellH)
	grid.CellSize = UDim2.fromOffset(cw, ch)
	grid.CellPadding = UDim2.fromOffset(px(6), px(6))
	rail.Position = UDim2.fromOffset(m, y)
	rail.Size = UDim2.fromOffset(columns * cw + (columns - 1) * px(6), rows * ch + (rows - 1) * px(6))
	-- the band other top-of-screen UI (rare card, catch reveal, data banner) must start below
	local band = if wide then y + rail.Size.Y.Offset + g else y
	gui:SetAttribute("TopBand", band)
	if settingsRoot then
		settingsRoot.Size = UDim2.fromOffset(px(SIZE.Settings), px(SIZE.Settings))
		settingsRoot.Position = UDim2.new(1, -m, 0, m)
	end
end

local function hudButton(name: string, variant: string, icon: string, order: number, onClick: () -> ())
	local b = StudPop.HudButton(rail, { variant = variant, icon = icon, text = name, order = order, onClick = onClick })
	b.Size = UDim2.fromScale(1, 1)
	local a = b:FindFirstChildOfClass("UIAspectRatioConstraint")
	if a then
		a:Destroy()
	end
	-- Caption: fixed 14 px floor at the 844x390 baseline (TextScaled shrank it below the rule).
	local caption = b:FindFirstChild("Label")
	if caption and caption:IsA("TextLabel") then
		caption.TextScaled = false
		caption.TextSize = px(Theme.Size.MinText)
		caption.Size = UDim2.new(1.5, 0, 0, px(Theme.Size.MinText + 4))
		caption.Position = UDim2.new(-0.25, 0, 1, -px(Theme.Size.MinText + 3))
	end
	table.insert(railButtons, b)
	return b
end

-- Menus that take the screen: the HUD steps aside while any is open.
local MENU_ATTRIBUTES = { "MenusV2Open", "Phase13ShopOpen", "ChariotTeamMenuOpen", "Phase13ConsentDialogOpen", "Phase13CompareDialogOpen" }
local function computeMenuOpen(): boolean
	local p = Players.LocalPlayer
	for _, a in MENU_ATTRIBUTES do
		local v = p:GetAttribute(a)
		if v == true or (type(v) == "string" and v ~= "") then
			return true
		end
	end
	return false
end

function Screen.Start(actionTable: Actions)
	if gui then
		return false
	end
	actions = actionTable
	-- Theme.px() reads the viewport when a part is built; wait for a sized viewport at client start.
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		local cam = workspace.CurrentCamera
		if cam and cam.ViewportSize.Y >= 200 then
			break
		end
		task.wait(0.1)
	end
	if gui then
		return false
	end
	gui = StudPop.ScreenGui("StudPopHud", 30)
	gui:SetAttribute("StudPopOwned", true)

	-- top-left Cash pill ("+" opens Shop > Cash)
	-- the pills are displays, not shop buttons (shops open only at their stalls)
	pill = StudPop.CashPill(gui, cashValue(), nil)
	pill.Root.Name = "CashPill"
	table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
		if not cashPadsOn then
			pill.set(cashValue())
			return
		end
		-- Playtest Fixes 2 C3: a pad claim's coins land on the counter; the claim's ClaimRevision
		-- arrives in the same replication batch, so wait a beat before showing a rise.
		task.delay(0.03, function()
			if os.clock() < cashHoldUntil then
				cashHeld = true
			elseif pill then
				pill.set(cashValue())
			end
		end)
	end))

	-- Gem pill to the right of Cash; "+" opens the Gems tab (Gem shop + Gem packs).
	gemPill = StudPop.GemPill(gui, gemValue(), nil)
	gemPill.Root.Name = "GemPill"
	local lastGems = gemValue()
	table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal("Gems"):Connect(function()
		local now = gemValue()
		gemPill.set(now)
		if now > lastGems then
			StudPop.Toast(gui, "+" .. tostring(now - lastGems) .. " GEMS!", "gem")
		end
		lastGems = now
	end))

	-- Live status chips: active 2× Cash boost and server Mutation Storm (tap = Gems tab).
	chips = Instance.new("Frame")
	chips.Name = "EconomyChips"
	chips.BackgroundTransparency = 1
	chips.Visible = false
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, px(SIZE.Gap))
	chipLayout.Parent = chips
	chips.Parent = gui
	local function chip(name: string, variant: string, order: number)
		local b = StudPop.Button(chips, {
			variant = variant,
			text = name,
			size = UDim2.fromOffset(px(SIZE.ChipW), px(SIZE.ChipH)),
		})
		b.Root.Name = name
		b.Root.LayoutOrder = order
		local ar = b.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
		if ar then
			ar:Destroy()
		end
		return b
	end
	local boostChip = chip("Boost", "alert", 1)
	local stormChip = chip("Storm", "gem", 2)
	task.spawn(function()
		local Economy = require(game:GetService("ReplicatedStorage").Shared.Config.Economy)
		while gui do
			local now = workspace:GetServerTimeNow()
			local boostUntil = Players.LocalPlayer:GetAttribute("CashBoostUntil")
			local boostLeft = if type(boostUntil) == "number" then boostUntil - now else 0
			local stormUntil = workspace:GetAttribute(Economy.MutationStorm.Attribute)
			local stormLeft = if type(stormUntil) == "number" then stormUntil - now else 0
			boostChip.Root.Visible = boostLeft > 0
			stormChip.Root.Visible = stormLeft > 0
			if boostLeft > 0 then
				boostChip.setText("2× CASH " .. clock(boostLeft))
			end
			if stormLeft > 0 then
				stormChip.setText("STORM " .. clock(stormLeft))
			end
			local visible = boostLeft > 0 or stormLeft > 0
			if chips.Visible ~= visible then
				chips.Visible = visible
				layout()
			end
			task.wait(1)
		end
	end)

	-- rail
	rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.Parent = rail
	rail.Parent = gui
	-- exactly two menu buttons: Brainrots (pink) and Inventory (blue), >= 56 px
	SIZE.CellW, SIZE.CellH = 64, 78
	local shots = require(ReplicatedStorage.Shared.Config.UIDisplayShots)
	local brainrotIcon = shots.get("BRT_002")
	local brainrotsButton = hudButton("Brainrots", "robux", if brainrotIcon ~= "" then brainrotIcon else Theme.Icons.Index, 1, function()
		Screen.clearNewCatches()
		if actions.openBrainrots then
			actions.openBrainrots()
		end
	end)
	hudButton("Inventory", "info", Theme.Icons.Shop, 2, function()
		if actions.openInventory then
			actions.openInventory()
		end
	end)
	-- red dot = brainrots caught since the window was last opened (session only; a real waiting thing)
	local dot = brainrotsButton:FindFirstChild("Dot", true)
	Screen._newDot = dot
	if dot and dot:IsA("GuiObject") and not Juice.reduced() then
		local sc = Juice.scaleOf(dot)
		Juice.play(sc, "pulse", TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 })
	end
	-- Rebirth lives at the base entrance prompt (the server relabels it "Rebirth — Ready!"); the HUD
	-- only says so once per session when the server's RebirthReady attribute turns true.
	do
		local told = false
		local function apply()
			if not told and Players.LocalPlayer:GetAttribute("RebirthReady") == true then
				told = true
				require(ReplicatedStorage.Shared.UI.Plate).Toast(gui, "Rebirth ready at your base!", { color = Color3.fromHex("#FFD447"), top = px(96) })
			end
		end
		table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal("RebirthReady"):Connect(apply))
		task.delay(6, apply)
	end

	-- no cog on the HUD (Settings is the gear in the Inventory header); an invisible anchor keeps
	-- the status rows' top-right position
	local anchor = Instance.new("Frame")
	anchor.Name = "TopRightAnchor"
	anchor.BackgroundTransparency = 1
	anchor.AnchorPoint = Vector2.new(1, 0)
	anchor.Parent = gui
	settingsRoot = anchor

	-- Visibility: hidden during cinematics and while a menu is open (windows never cover HUD chrome).
	local function syncVisible()
		menuOpen = computeMenuOpen()
		gui.Enabled = not menuOpen and Players.LocalPlayer:GetAttribute("Phase13CinematicActive") ~= true
	end
	for _, a in MENU_ATTRIBUTES do
		table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal(a):Connect(syncVisible))
	end
	table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal("Phase13CinematicActive"):Connect(syncVisible))

	-- a slow tick as a safety net for menu state that changes without an attribute signal
	task.spawn(function()
		while gui do
			syncVisible()
			task.wait(0.25)
		end
	end)

	local cam = workspace.CurrentCamera
	if cam then
		table.insert(connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	end
	layout()
	syncVisible()
	return true
end

-- Bottom of the HUD's top band (pills, chips and — on landscape phones — the rail), in ScreenGui pixels.
-- Top-of-screen UI (rare card, catch reveal, data banner) starts below it.
-- Playtest Fixes 2 C3 (CashPadController): hold Cash rises for `seconds` (coins in flight), then
-- ReleaseCash rolls the counter up on the first landing. Always self-releases.
function Screen.HoldCash(seconds: number)
	cashHoldUntil = math.max(cashHoldUntil, os.clock() + seconds)
	task.delay(seconds + 0.1, function()
		if cashHeld and os.clock() >= cashHoldUntil then
			Screen.ReleaseCash()
		end
	end)
end

function Screen.ReleaseCash()
	cashHoldUntil = 0
	cashHeld = false
	if pill then
		pill.set(cashValue())
	end
end

function Screen.CashPillRoot(): GuiObject?
	return if pill then pill.Root else nil
end

function Screen.TopBand(): number
	if not gui then
		return 0
	end
	return gui:GetAttribute("TopBand") or 0
end

-- Absolute top-right point where ExactHud's status rows hang (just under Settings, right-aligned).
function Screen.StatusAnchor(): Vector2?
	if not gui or not settingsRoot then
		return nil
	end
	local s = settingsRoot
	return Vector2.new(s.AbsolutePosition.X + s.AbsoluteSize.X, s.AbsolutePosition.Y + s.AbsoluteSize.Y + px(SIZE.Gap))
end

-- MenusV2 red dot: brainrots caught since the Brainrots window was last opened (session only).
local newCatches = 0
function Screen.noteCatch()
	newCatches += 1
	local dot = Screen._newDot
	if dot and dot:IsA("TextLabel") then
		dot.Text = if newCatches > 9 then "9+" else tostring(newCatches)
		dot.Visible = true
	end
end
function Screen.clearNewCatches()
	newCatches = 0
	local dot = Screen._newDot
	if dot and dot:IsA("GuiObject") then
		dot.Visible = false
	end
end

function Screen.MenuOpen(): boolean
	return menuOpen
end

function Screen.Gui(): ScreenGui?
	return gui
end

function Screen.Stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(railButtons)
	if gui then
		gui:Destroy()
	end
	gui, rail, pill, gemPill, chips, settingsRoot = nil, nil, nil, nil, nil, nil
end

return Screen
