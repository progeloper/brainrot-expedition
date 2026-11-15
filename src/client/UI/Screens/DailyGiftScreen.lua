--!nocheck
-- "Daily Gift" window (Dialog header, the "Free Gift!" look). Contextual entry for the Retention
-- supplies claim; the same claim also lives in Brainrots > Quests ("Quests" button here goes there).
--   * when a supply claim is available it auto-opens ONCE per UTC day (server dayKey) per session;
--     otherwise (another menu is open) a small Plate toast with a Claim button shows at most once per
--     claimable period (dayKey + lifetime claims). Both memories are session-only module locals.
--   * Claim -> retention.Request({ action = "ClaimSupply" }) (the legacy payload); disabled while
--     IsRequestPending("ClaimSupply"). "Can claim" = RetentionPresentation.Supply(...).enabled, the
--     same rule the Quests tab's claim uses.
-- Every amount is the server's (supplies.rewardCash / tiles / checkpoints). The daily Gem amount is not
-- in the snapshot (DATA_CONTRACT §5), so the window says Gems ride along without inventing a number.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local View = require(ReplicatedStorage.Shared.Utility.RetentionPresentation)
local CashFormat = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Plate, Theme = Common.Plate, Common.Theme
local P = Theme.Plate
local px = Theme.px

local Screen = {}

local ID = "DailyGift"
local player = Players.LocalPlayer
local retention = nil
local deps = nil -- { shop, retention } handed to BrainrotsScreen by the "Quests" button
local started = false
local window = nil
local renderBag = nil
local autoOpenedDay = nil -- session-only: UTC dayKey the window last auto-opened on
local surfacedPeriod = nil -- session-only: claimable period already auto-opened or toasted
local toast = nil -- { root: Frame, bag }
local wasClaimable = false
local closeToken = 0
local connections: { RBXScriptConnection } = {}

local function snap()
	return retention and retention.GetSnapshot()
end

local function pending(): boolean
	return retention ~= nil and retention.IsRequestPending("ClaimSupply") == true
end

local function supplyView(s)
	return View.Supply(s, pending())
end

local function canClaim(s): boolean
	local v = supplyView(s)
	return v.enabled == true and v.state == "Available"
end

local function periodKey(s): string
	local sup = s and s.supplies or {}
	return tostring(s and s.dayKey) .. ":" .. tostring(sup.lifetimeClaims)
end

-- another window/menu owns the screen right now
local function menuBusy(): boolean
	return MenusV2.currentId() ~= nil
		or player:GetAttribute("Phase13ShopOpen") == true
		or player:GetAttribute("TeamManagementOpen") == true
		or player:GetAttribute("ChariotTeamMenuOpen") == true
end

-- not a moment to pop anything (loading / dead / cinematic / Roblox menu)
local function notReady(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum == nil
		or hum.Health <= 0
		or player:GetAttribute("Phase13CinematicActive") == true
		or player:GetAttribute("Phase13ConsentDialogOpen") == true
		or game:GetService("GuiService").MenuIsOpen
end

local function claim()
	if not retention or pending() or not canClaim(snap()) then
		return
	end
	retention.Request({ action = "ClaimSupply" })
end

local closeWindow

-- Info navigation: leave the gift and land on Brainrots > Quests.
local function openQuests()
	closeWindow(false)
	local module = script.Parent:FindFirstChild("BrainrotsScreen")
	if module then
		require(module).open(deps or { retention = retention }, "Quests")
	end
end

------------------------------------------------------------------ toast
local function hideToast()
	if toast then
		local t = toast
		toast = nil
		t.bag.clean()
		if t.root.Parent then
			t.root:Destroy()
		end
	end
end

local function showToast()
	hideToast()
	local gui = MenusV2.Gui()
	local bag = Plate.Bag()
	local root = Instance.new("Frame")
	root.Name = "DailyGiftToast"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, px(64))
	root.Size = UDim2.fromOffset(px(300), px(60))
	root.BackgroundColor3 = P.Color.WindowBody
	root.ZIndex = 70
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.Radius.Button)
	c.Parent = root
	local st = Instance.new("UIStroke")
	st.Thickness = px(3)
	st.Color = P.Color.Ink
	st.Parent = root
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(P.Header.Dialog[1], P.Header.Dialog[#P.Header.Dialog])
	g.Parent = root
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	bag.add(root)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = Theme.Icons.Gift
	icon.Size = UDim2.fromOffset(px(44), px(44))
	icon.Position = UDim2.fromOffset(px(8), px(8))
	icon.ZIndex = 6
	icon.Parent = root
	Plate.Label(root, "Daily Gift ready!", {
		size = 20,
		min = 14,
		font = P.Font.Title,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -px(170), 1, 0),
		position = UDim2.fromOffset(px(58), 0),
		z = 6,
	})
	Plate.Button(root, {
		variant = "go",
		text = "Claim",
		size = UDim2.fromOffset(px(100), px(48)),
		position = UDim2.new(1, -px(8), 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = 20,
		bag = bag,
		name = "Claim",
		onClick = function()
			claim()
			hideToast()
		end,
	})
	-- lift the whole toast above windows, keeping the kit's relative layering
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 66
		end
	end
	root.Parent = gui
	local sc = Juice.scaleOf(root)
	if Juice.reduced() then
		sc.Scale = 1
	else
		sc.Scale = 0.4
		TweenService:Create(sc, P.Motion.CardPop, { Scale = 1 }):Play()
	end
	toast = { root = root, bag = bag }
	local mine = toast
	task.delay(8, function()
		if toast == mine then
			hideToast()
		end
	end)
end

------------------------------------------------------------------ window
local function tileText(i: number, tile): (string, string)
	local cash = if tile and type(tile.rewardCash) == "number"
		then CashFormat.FormatCompactCash(tile.rewardCash)
		else "—"
	local state = if not tile
		then "—"
		elseif tile.claimed then "Claimed"
		elseif tile.next then "Today"
		else "Day " .. i
	return cash, state
end

local function render(pop: boolean)
	if not window or not window.isOpen() then
		return
	end
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local content = window.Content
	local s = snap()
	local sup = s and s.supplies or {}
	local view = supplyView(s)
	window.setStat(
		if type(sup.cyclePosition) == "number" then "Day " .. sup.cyclePosition .. "/7" else nil
	)

	local root = Instance.new("Frame")
	root.Name = "GiftBody"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 5
	root.Parent = content
	renderBag.add(root)

	-- hero: today's reward from the server
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.BackgroundTransparency = 1
	hero.Size = UDim2.fromScale(1, 0.4)
	hero.ZIndex = 5
	hero.Parent = root
	local gift = Instance.new("ImageLabel")
	gift.Name = "GiftIcon"
	gift.BackgroundTransparency = 1
	gift.Image = Theme.Icons.Gift
	gift.SizeConstraint = Enum.SizeConstraint.RelativeYY
	gift.Size = UDim2.fromScale(0.95, 0.95)
	gift.ZIndex = 6
	gift.Parent = hero
	if not Juice.reduced() then
		renderBag.add(Juice.bob(gift))
	end
	local heroText = if type(sup.rewardCash) == "number"
		then CashFormat.FormatExactCash(sup.rewardCash) .. " Cash"
		else "Reward unavailable"
	local headline = if sup.claimedToday then "Today's gift claimed" else "Today's gift"
	Plate.Label(hero, headline, {
		size = 16,
		min = 14,
		color = P.Color.Hint,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.fromScale(0.8, 0.28),
		position = UDim2.fromScale(0.19, 0),
		z = 6,
	})
	local big = Plate.Label(hero, heroText, {
		size = 30,
		min = 16,
		font = P.Font.Title,
		color = P.Color.Cash,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.fromScale(0.8, 0.42),
		position = UDim2.fromScale(0.19, 0.28),
		z = 6,
	})
	big.Name = "HeroAmount"
	local extra = "+ free Gems"
	local checkpoint = sup.checkpoints
		and sup.checkpoints[if sup.nextLifetimeClaim == 7
			then 1
			elseif sup.nextLifetimeClaim == 14 then 2
			else 0]
	if checkpoint and not sup.claimedToday then
		extra ..= " · also earns " .. tostring(checkpoint.label)
	end
	Plate.Label(hero, extra, {
		size = 16,
		min = 14,
		color = Theme.Color.GemHi,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.fromScale(0.8, 0.3),
		position = UDim2.fromScale(0.19, 0.7),
		z = 6,
	})

	-- 7-day strip (server tiles)
	local tiles = sup.tiles
	if type(tiles) == "table" and #tiles > 0 then
		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.BackgroundTransparency = 1
		strip.Position = UDim2.fromScale(0, 0.43)
		strip.Size = UDim2.fromScale(1, 0.3)
		strip.ZIndex = 5
		strip.Parent = root
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, px(6))
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = strip
		local n = math.min(#tiles, 7)
		for i = 1, n do
			local tile = tiles[i]
			local bg = if tile.next
				then P.Tier.T6
				elseif tile.claimed then P.Tier.Dark
				elseif i == 7 then P.Tier.WonGold
				else P.Tier.T3
			local f = Instance.new("Frame")
			f.Name = "Day" .. i
			f.LayoutOrder = i
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.Size = UDim2.new(1 / n, -px(6), 1, 0)
			f.ZIndex = 6
			f.Parent = strip
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(0, P.Radius.Card)
			cr.Parent = f
			local sk = Instance.new("UIStroke")
			sk.Thickness = px(if tile.next then 3 else 2)
			sk.Color = if tile.next then P.Color.WellRim else P.Color.Ink
			sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			sk.Parent = f
			local gr = Instance.new("UIGradient")
			gr.Rotation = 90
			gr.Color = ColorSequence.new(bg[1], bg[#bg])
			gr.Parent = f
			local cash, state = tileText(i, tile)
			Plate.Label(
				f,
				cash,
				{
					size = 18,
					min = 14,
					font = P.Font.Title,
					frameSize = UDim2.fromScale(1, 0.55),
					z = 7,
				}
			)
			Plate.Label(
				f,
				state,
				{
					size = 15,
					min = 14,
					frameSize = UDim2.fromScale(1, 0.45),
					position = UDim2.fromScale(0, 0.55),
					z = 7,
				}
			)
			if tile.next and not Juice.reduced() then
				renderBag.add(Juice.pulse(sk, 0, 0.6))
			end
		end
	end

	-- action row
	local row = Instance.new("Frame")
	row.Name = "Action"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0, 0.77)
	row.Size = UDim2.fromScale(1, 0.23)
	row.ZIndex = 5
	row.Parent = root
	Plate.Button(row, {
		variant = "info",
		text = "Quests",
		size = UDim2.fromOffset(px(96), px(48)),
		position = UDim2.new(1, -px(4), 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = 18,
		bag = renderBag,
		name = "Quests",
		onClick = openQuests,
	})
	local size = UDim2.fromOffset(px(220), px(48))
	local pos = UDim2.fromScale(0.5, 0.5)
	local anchor = Vector2.new(0.5, 0.5)
	if view.state == "Claimed" then
		Plate.StateWell(
			row,
			"Claimed today",
			{ size = size, position = pos, anchor = anchor, bag = renderBag, textSize = 18 }
		)
	elseif view.state == "Available" and view.enabled then
		Plate.Button(row, {
			variant = "go",
			text = "Claim",
			icon = Theme.Icons.Gift,
			primary = true, -- the window's one breathing primary
			size = size,
			position = pos,
			anchor = anchor,
			textSize = 22,
			bag = renderBag,
			name = "Claim",
			onClick = claim,
		})
	else
		Plate.Button(row, {
			variant = "locked",
			lockedReason = view.text,
			text = view.text,
			size = size,
			position = pos,
			anchor = anchor,
			textSize = 18,
			bag = renderBag,
		})
	end
	if pop and not Juice.reduced() then
		Juice.pop(big, 1.12)
	end
end

closeWindow = function(instant: boolean?)
	closeToken += 1
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	if window then
		window.close(instant)
	end
	MenusV2.cleared(ID)
end

function Screen.open()
	if not retention then
		return false
	end
	hideToast()
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Dialog",
			title = "Daily Gift",
			icon = Theme.Icons.Gift,
			aspect = 1.9,
			widthScale = 0.7,
			heightScale = 0.8,
			maxSize = Vector2.new(600, 316),
			onClose = function()
				closeWindow(false)
			end,
		})
	end
	MenusV2.setOpen(ID, function(instant)
		closeWindow(instant)
	end)
	window.open()
	window.clearContent()
	wasClaimable = canClaim(snap())
	task.defer(render, true)
	return true
end

function Screen.close(instant: boolean?)
	closeWindow(instant)
end

function Screen.isOpen(): boolean
	return window ~= nil and window.isOpen()
end

------------------------------------------------------------------ watcher
local function evaluate()
	local s = snap()
	local claimable = canClaim(s)
	if Screen.isOpen() then
		render(false)
		-- claimed while open: let the "Claimed today" state land, then close (no loop; one timer)
		if wasClaimable and not claimable and s and s.supplies and s.supplies.claimedToday then
			closeToken += 1
			local token = closeToken
			task.delay(2, function()
				if token == closeToken and Screen.isOpen() then
					closeWindow(false)
				end
			end)
		end
		wasClaimable = claimable
		return
	end
	wasClaimable = claimable
	if not claimable then
		hideToast()
		return
	end
	if notReady() then
		return -- re-evaluated on the next snapshot / attribute / character change
	end
	local period = periodKey(s)
	if surfacedPeriod == period then
		return
	end
	surfacedPeriod = period
	if not menuBusy() and autoOpenedDay ~= s.dayKey then
		autoOpenedDay = s.dayKey
		Screen.open()
	else
		showToast() -- another menu is open, or today's auto-open already happened
	end
end

-- retention = RetentionController (GetSnapshot, Request, Changed, IsRequestPending).
-- d (optional) = the HUD windows' deps { shop = Phase13ShopController, retention = RetentionController };
-- it is passed on to BrainrotsScreen.open(d, "Quests"). Without it the Quests tab still works.
function Screen.Start(r, d)
	if started or not r or not r.Changed then
		return false
	end
	started = true
	retention = r
	deps = if type(d) == "table" then d else { retention = r }
	local function queue()
		task.defer(evaluate)
	end
	table.insert(connections, r.Changed.Event:Connect(queue))
	for _, name in
		{ "Phase13ShopOpen", "MenusV2Open", "Phase13CinematicActive" }
	do
		table.insert(connections, player:GetAttributeChangedSignal(name):Connect(queue))
	end
	table.insert(
		connections,
		player.CharacterAdded:Connect(function()
			task.delay(2, evaluate)
		end)
	)
	queue()
	return true
end

function Screen.Stop()
	started = false
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	hideToast()
	if window and window.isOpen() then
		closeWindow(true)
	end
end

return Screen
