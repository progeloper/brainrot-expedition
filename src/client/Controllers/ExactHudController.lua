--!nocheck
-- One event-fed HUD. No legacy status/render loop creates a second presentation.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Gui = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local C = require(RS.Shared.Config.PlaytestExact).Hud
local fontEnum = require(RS.Shared.Config.BrainrotDisplayConfig).Typography.Font
local Formatter = require(RS.Shared.Utility.CurrencyFormatter)
local Queue = require(RS.Shared.Utility.ExactMessageQueue)
local M = require(RS.Shared.Config.PlaytestMeasurements)
local StudPopUI = require(script.Parent.Parent.UI.StudPopUI)
local StudPopHud = require(script.Parent.Parent.UI.Screens.HudScreen)
local Hud = {}
local gui, safe, status, list, toast, rare, primary, drop, connection
local rows = {}
local queue = Queue.new()
local action, dropCallback
local cargoCount, cargoCapacity, cargoCart, loadUntil = 0, nil, nil, 0
local previousCamp, entrySerial, lastSecond, lastWarning = false, 0, nil, nil
local timerBinding, escapeGui, escapeAnchor
local seenLoads = {}
local offsets = {}
local connections = {}
local serial = 0
local layoutError = nil
local nextLayout = 0
local function shown(x)
	local c = x
	while c and c ~= Players.LocalPlayer.PlayerGui do
		if c:IsA("GuiObject") and not c.Visible then
			return false
		end
		if c:IsA("ScreenGui") and not c.Enabled then
			return false
		end
		c = c.Parent
	end
	return true
end
local function rect(x)
	return { x.AbsolutePosition.X, x.AbsolutePosition.Y, x.AbsoluteSize.X, x.AbsoluteSize.Y }
end
local function intersect(a, b)
	return a[1] < b[1] + b[3] and a[1] + a[3] > b[1] and a[2] < b[2] + b[4] and a[2] + a[4] > b[2]
end
function Hud.Unit(size)
	return math.clamp(math.min(size.X / C.ReferenceWidth, size.Y / C.ReferenceHeight), C.MinimumScale, C.MaximumScale)
end
local function unit()
	return Hud.Unit(safe.AbsoluteSize)
end
local function text(parent, name)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Text = ""
	t.Font = fontEnum
	t.TextScaled = false
	t.RichText = false
	t.TextStrokeTransparency = 1
	t.TextWrapped = false
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.TextColor3 = C.Text
	t.Parent = parent
	return t
end
local function panel(parent, name, kind)
	local f = Instance.new(kind or "Frame")
	f.Name = name
	f.BackgroundColor3 = C.Background
	f.BackgroundTransparency = C.Transparency
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = parent
	local corner = Instance.new("UICorner")
	corner.Name = "Corner"
	corner.Parent = f
	return f
end
local function labelPanel(parent, name)
	local f = panel(parent, name, "CanvasGroup")
	local t = text(f, "Text")
	return f, t
end
local function sizeText(base)
	return base * unit() + (offsets[base] or 0)
end
local function refreshAccessibility()
	for _, base in ipairs({ C.StatusText, C.ToastText, C.RareTitle, C.RareDetail, C.ActionText, C.ObjectText }) do
		local ok, value = pcall(TextService.GetTextSizeOffsetAsync, TextService, base * unit(), Font.fromEnum(fontEnum))
		if ok then
			offsets[base] = math.max(0, value)
		end
	end
end
local function controls()
	local pg = Players.LocalPlayer.PlayerGui
	local result = {}
	local function add(x)
		if x and x:IsA("GuiObject") and shown(x) and x.AbsoluteSize.X > 0 then
			local r = rect(x)
			r[1] -= safe.AbsolutePosition.X
			r[2] -= safe.AbsolutePosition.Y
			table.insert(result, r)
		end
	end
	local touch = pg:FindFirstChild("TouchGui")
	local f = touch and touch:FindFirstChild("TouchControlFrame")
	if f then
		for _, n in ipairs({ "JumpButton", "DynamicThumbstickFrame", "ThumbstickFrame" }) do
			add(f:FindFirstChild(n))
		end
	end
	local aim = pg:FindFirstChild("SleepAimReticle")
	local fire = aim and aim:FindFirstChild("FireSafeArea")
	if fire then
		for _, n in ipairs({ "MountedFire", "MountedAim" }) do
			add(fire:FindFirstChild(n))
		end
	end
	local context = pg:FindFirstChild("ContextActionGui")
	local group = context and context:FindFirstChild("ContextButtonFrame")
	if group then
		for _, v in group:GetChildren() do
			add(v)
		end
	end
	local burst = pg:FindFirstChild("CartBurstGui")
	local area = burst and burst:FindFirstChild("SafeArea")
	add(area and area:FindFirstChild("BurstPanel"))
	return result
end
local function free(r, reserved)
	if r[1] < 0 or r[2] < 0 or r[1] + r[3] > safe.AbsoluteSize.X or r[2] + r[4] > safe.AbsoluteSize.Y then
		return false
	end
	for _, v in reserved do
		if intersect(r, v) then
			return false
		end
	end
	return true
end
local function assign(x, r)
	x.Position = UDim2.fromOffset(r[1], r[2])
	x.Size = UDim2.fromOffset(r[3], r[4])
end
local function actionLayout(reserved)
	local u = unit()
	local w, h = safe.AbsoluteSize.X, safe.AbsoluteSize.Y
	local margin = C.Top * u
	local gap = C.AlternateGap * u
	local rightTop, rightLeft = h - margin, w - margin
	for _, r in reserved do
		if r[1] + r[3] / 2 > w / 2 and r[2] + r[4] / 2 > h / 2 then
			rightTop = math.min(rightTop, r[2])
			rightLeft = math.min(rightLeft, r[1])
		end
	end
	local pw, dw = C.ActionWidth * u, C.DropWidth * u
	local bh = math.max(C.ActionHeight * u, sizeText(C.ActionText) + sizeText(C.ObjectText) + 2 * C.Padding * u)
	if pw + dw + gap > w - 2 * margin then
		pw, dw = C.NarrowActionWidth * u, C.NarrowDropWidth * u
	end
	local total = pw + (if dropCallback then dw + gap else 0)
	local tries = {
		{ w - margin - total, rightTop - gap - bh },
		{ rightLeft - gap - total, h - margin - bh },
		{ w - margin - total, rightTop - 2 * gap - 2 * bh },
	}
	layoutError = nil
	for _, p in tries do
		local pr = { p[1] + total - pw, p[2], pw, bh }
		local dr = { p[1], p[2], dw, bh }
		if free(pr, reserved) and (not dropCallback or free(dr, reserved)) then
			assign(primary, pr)
			assign(drop, dr)
			return
		end
	end
	-- Next row separates Drop without reducing target height or hiding actions.
	local pr = { math.max(margin, w - margin - pw), math.max(margin, rightTop - gap - bh), pw, bh }
	local dr = { pr[1] + pw - dw, pr[2] - gap - bh, dw, bh }
	if free(pr, reserved) and (not dropCallback or free(dr, reserved)) then
		assign(primary, pr)
		assign(drop, dr)
		return
	end
	layoutError = "ACTION_LAYOUT_NO_FREE_RECTANGLE"
	assign(primary, pr)
	assign(drop, dr)
end
local function layout()
	if not safe or safe.AbsoluteSize.X <= 0 then
		return
	end
	local u = unit()
	-- Stud Pop: pills + rail own the top-left; status rows hang right-aligned under Settings (top-right).
	local studPop = true -- the Stud Pop HUD (pills + rail) is the only HUD
	local statusX, statusY = C.Top * u, C.Top * u
	local anchor = if studPop then StudPopHud.StatusAnchor() else nil
	if anchor then
		statusX = anchor.X - safe.AbsolutePosition.X - C.StatusWidth * u
		statusY = anchor.Y - safe.AbsolutePosition.Y
	end
	status.Position = UDim2.fromOffset(statusX, statusY)
	status.Size = UDim2.fromOffset(C.StatusWidth * u, 0)
	list.Padding = UDim.new(0, C.RowGap * u)
	for _, row in rows do
		row.frame.Corner.CornerRadius = UDim.new(0, C.Corner * u)
		row.frame.Size = UDim2.fromOffset(
			C.StatusWidth * u,
			math.max(C.SafeHeight * u, sizeText(C.StatusText) + C.VerticalTextGap * u)
		)
		row.text.Position = UDim2.fromOffset(C.Padding * u, 0)
		row.text.Size = UDim2.new(1, -2 * C.Padding * u, 1, 0)
		row.text.TextSize = sizeText(C.StatusText)
	end
	for _, p in ipairs({ toast, rare, primary, drop }) do
		p.Corner.CornerRadius = UDim.new(0, C.Corner * u)
	end
	primary.Action.TextSize = sizeText(C.ActionText)
	primary.Object.TextSize = sizeText(C.ObjectText)
	drop.Action.TextSize = sizeText(C.ActionText)
	for _, p in ipairs({ primary, drop }) do
		p.Action.Position = UDim2.fromOffset(C.Padding * u, C.Padding * u)
		p.Action.Size = UDim2.new(1, -2 * C.Padding * u, 0, sizeText(C.ActionText) + C.VerticalTextGap * u)
	end
	primary.Object.Position =
		UDim2.fromOffset(C.Padding * u, C.Padding * u + sizeText(C.ActionText) + C.VerticalTextGap * u)
	primary.Object.Size = UDim2.new(1, -2 * C.Padding * u, 0, sizeText(C.ObjectText) + C.VerticalTextGap * u)
	local reserved = controls()
	actionLayout(reserved)
	local width = math.min(C.ToastWidth * u, safe.AbsoluteSize.X - 2 * C.Top * u)
	local height = math.max(C.ToastHeight * u, sizeText(C.ToastText) + 2 * C.VerticalTextGap * u)
	local below = { C.Top * u, C.Top * u + list.AbsoluteContentSize.Y + C.ToastGap * u, width, height }
	local beside = { C.Top * u + C.StatusWidth * u + C.AlternateGap * u, C.Top * u, width, height }
	if anchor then
		-- right-aligned under the status rows, or to their left
		local right = statusX + C.StatusWidth * u
		below = { right - width, statusY + list.AbsoluteContentSize.Y + C.ToastGap * u, width, height }
		beside = { statusX - C.AlternateGap * u - width, statusY, width, height }
	end
	local target = if free(below, reserved) then below elseif free(beside, reserved) then beside else nil
	toast:SetAttribute("DeferredForControls", target == nil)
	if target then
		assign(toast, target)
	end
	local rw = math.min(C.RareWidth * u, safe.AbsoluteSize.X - 2 * C.Top * u)
	local rh = math.max(
		C.RareHeight * u,
		sizeText(C.RareTitle) + sizeText(C.RareDetail) + C.VerticalTextGap * u + 2 * C.Padding * u
	)
	local rareTop = C.Top * u
	if studPop then
		-- below the Stud Pop top band (pills/chips/phone rail) and below a catch reveal on screen
		local hudGui = StudPopHud.Gui()
		if hudGui then
			rareTop = math.max(rareTop, hudGui.AbsolutePosition.Y + StudPopHud.TopBand() - safe.AbsolutePosition.Y)
		end
		local reveal = Players.LocalPlayer.PlayerGui:FindFirstChild("StudPopCatchReveal")
		local revealBottom = reveal and reveal:GetAttribute("ActiveBottom")
		if type(revealBottom) == "number" then
			rareTop = math.max(rareTop, revealBottom - safe.AbsolutePosition.Y + C.ToastGap * u)
		end
	end
	assign(rare, { (safe.AbsoluteSize.X - rw) / 2, rareTop, rw, rh })
	for _, p in ipairs({ toast, rare }) do
		p.Title.Position = UDim2.fromOffset(C.Padding * u, C.Padding * u)
		p.Title.Size =
			UDim2.new(1, -2 * C.Padding * u, 0, if p == rare then sizeText(C.RareTitle) else height - 2 * C.Padding * u)
		p.Title.TextSize = sizeText(if p == rare then C.RareTitle else C.ToastText)
	end
	rare.Detail.Position =
		UDim2.fromOffset(C.Padding * u, C.Padding * u + sizeText(C.RareTitle) + C.VerticalTextGap * u)
	rare.Detail.Size = UDim2.new(1, -2 * C.Padding * u, 0, sizeText(C.RareDetail))
	rare.Detail.TextSize = sizeText(C.RareDetail)
end
local function clearEscape()
	timerBinding = nil
	if escapeGui then
		escapeGui:Destroy()
		escapeGui = nil
	end
	if escapeAnchor then
		escapeAnchor:Destroy()
		escapeAnchor = nil
	end
end
local function updateEscape()
	local b = timerBinding
	if not b then
		return
	end
	local m = b.model
	local left = b.deadline - workspace:GetServerTimeNow()
	if
		not m.Parent
		or m:GetAttribute("BrainrotDisplayState") ~= "Carried"
		or m:GetAttribute("BindGeneration") ~= b.generation
		or m:GetAttribute("PresentationRevision") ~= b.revision
		or left <= 0
	then
		clearEscape()
		return
	end
	if os.clock() - b.last < C.RelevanceInterval then
		return
	end
	b.last = os.clock()
	escapeGui.Text.Text = string.format("Escapes in %.1fs", math.ceil(math.max(0, left) * 10) / 10)
	escapeGui.Size = UDim2.fromOffset(C.EscapeWidth * unit(), math.max(C.EscapeHeight * unit(), sizeText(C.StatusText)))
	escapeGui.Text.TextSize = sizeText(C.StatusText)
end
function Hud.Start()
	if gui then
		return
	end
	local p = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "PlaytestExactHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 90
	gui.Parent = p:WaitForChild("PlayerGui")
	safe = Instance.new("Frame")
	safe.Name = "SafeArea"
	safe.Size = UDim2.fromScale(1, 1)
	safe.BackgroundTransparency = 1
	safe.Parent = gui
	status = Instance.new("Frame")
	status.Name = "StatusGroup"
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.BackgroundTransparency = 1
	status.Parent = safe
	list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = status
	for i, n in ipairs({ "SafeZone", "Cargo", "Reset", "Wallet" }) do
		local f, t = labelPanel(status, n)
		f.LayoutOrder = i
		rows[n] = { frame = f, text = t }
	end
	toast = panel(safe, "OrdinaryToast", "CanvasGroup")
	text(toast, "Title")
	rare = panel(safe, "RareCard", "CanvasGroup")
	text(rare, "Title")
	text(rare, "Detail")
	primary = panel(safe, "Primary", "TextButton")
	primary.Text = ""
	text(primary, "Action")
	text(primary, "Object")
	drop = panel(safe, "Drop", "TextButton")
	drop.Text = ""
	text(drop, "Action")
	drop.Action.Text = "Drop"
	table.insert(
		connections,
		primary.Activated:Connect(function()
			if action and action.activate then
				action.activate()
			end
		end)
	)
	table.insert(
		connections,
		drop.Activated:Connect(function()
			if dropCallback then
				dropCallback()
			end
		end)
	)
	table.insert(
		connections,
		safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			layout()
			task.spawn(refreshAccessibility)
		end)
	)
	table.insert(connections, list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(layout))
	table.insert(
		connections,
		Gui:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
			refreshAccessibility()
			layout()
		end)
	)
	task.spawn(function()
		refreshAccessibility()
		layout()
	end)
	StudPopUI.skin(gui, {
		hints = { Primary = "primary", Drop = "stop", RareCard = "card", OrdinaryToast = "card", SafeArea = "plain", StatusGroup = "plain" },
	})
	connection = Run.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local camp = p:GetAttribute("Phase10InCamp") == true
		rows.SafeZone.frame.Visible = camp
		rows.SafeZone.text.Text = "🛡 Safe zone"
		rows.Cargo.frame.Visible = cargoCapacity ~= nil
		rows.Cargo.text.Text =
			string.format("Cargo %d/%d%s", cargoCount, cargoCapacity or 0, if now < loadUntil then " ✓" else "")
		-- Stud Pop shows Cash in the HUD pill (same attribute); the legacy row stays for flag-off.
		rows.Wallet.frame.Visible = false -- Cash lives in the HUD pill (same attribute)
		-- Stud Pop: status rows step aside while a menu window is open (no overlap with windows).
		status.Visible = not StudPopHud.MenuOpen()
		local cash = p:GetAttribute("Cash")
		rows.Wallet.text.Text = if type(cash) == "number"
			then Formatter.FormatCompactCash(cash)
			else "Wallet loading…"
		if camp and not previousCamp then
			entrySerial += 1
			local fresh = false
			local c = p.Character and p.Character:FindFirstChild("CarriedBrainrot")
			fresh = c ~= nil and c:GetAttribute("Phase10Banked") ~= true
			local cargo = cargoCart and cargoCart:FindFirstChild("CargoVisuals")
			if cargo then
				for _, m in cargo:GetChildren() do
					if m:GetAttribute("Phase10Banked") ~= true then
						fresh = true
						break
					end
				end
			end
			if fresh then
				Hud.Message("camp-entry:" .. entrySerial, "Drive onto your base to bank your cargo", false)
			end
		end
		previousCamp = camp
		local second = math.floor(workspace:GetServerTimeNow())
		if second ~= lastSecond then
			lastSecond = second
			local deadline = workspace:GetAttribute("Phase12ResetDeadline")
			rows.Reset.frame.Visible = type(deadline) == "number"
			if type(deadline) == "number" then
				local left = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
				rows.Reset.text.Text = string.format("Rare wave %d:%02d", math.floor(left / 60), left % 60)
				if left == C.ResetWarning and lastWarning ~= deadline then
					lastWarning = deadline
					Hud.Message("reset:" .. deadline, "Rare wave in 10s", false)
				end
			end
		end
		if now >= nextLayout then
			layout()
			nextLayout = now + C.RelevanceInterval
		end
		local message = queue.Step(now)
		toast.Visible = false
		rare.Visible = false
		if message then
			local target = if message.rare then rare else toast
			if target == toast and toast:GetAttribute("DeferredForControls") == true then
				queue.Defer(dt)
			else
				target.Visible = true
				target.Title.Text = message.title
				target.GroupTransparency = 1 - queue.Alpha(now)
				if message.rare then
					target.Detail.Text = message.detail or ""
				end
			end
		end
		primary.Visible = action ~= nil
		drop.Visible = dropCallback ~= nil
		updateEscape()
	end)
end
function Hud.Message(id, title, rareEvent, detail)
	Hud.Start()
	-- toast blip; retention rewards already play their own jingle
	if string.sub(tostring(id), 1, 10) ~= "retention:" then
		require(script.Parent.Parent.Utility.AudioCue).Play("U7", { bus = "UI", cooldown = 0.6 })
	end
	queue.Push({ id = tostring(id), title = title, rare = rareEvent == true, detail = detail }, os.clock())
end
function Hud.Feedback(message, id)
	serial += 1
	Hud.Message(id or ("local-feedback:" .. serial), message, false)
end
function Hud.Cargo(cart, count, capacity)
	Hud.Start()
	cargoCart, cargoCount, cargoCapacity = cart, count or 0, capacity
end
function Hud.LoadCommitted(cart, id, operation)
	Hud.Start()
	if operation and seenLoads[operation] then
		return
	end
	if operation then
		seenLoads[operation] = true
	end
	cargoCart = cart
	loadUntil = os.clock() + C.LoadCheckSeconds
end
function Hud.Action(value, onDrop)
	Hud.Start()
	action, dropCallback = value, onDrop
	primary.Action.Text = value and value.action or ""
	primary.Object.Text = value and value.name or ""
	primary.Visible = value ~= nil
	drop.Visible = onDrop ~= nil
	layout()
	Players.LocalPlayer:SetAttribute("ExactSelectedIndividualId", value and value.individualId or nil)
end
function Hud.Escape(_, deadline, eligible, model)
	Hud.Start()
	if not eligible or not model or type(deadline) ~= "number" or deadline <= workspace:GetServerTimeNow() then
		clearEscape()
		return
	end
	local revision, generation = model:GetAttribute("PresentationRevision"), model:GetAttribute("BindGeneration")
	if
		timerBinding
		and timerBinding.model == model
		and timerBinding.revision == revision
		and timerBinding.generation == generation
	then
		timerBinding.deadline = deadline
		return
	end
	clearEscape()
	local meta = require(game:GetService("ReplicatedStorage").Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(model, M.Species[model:GetAttribute("BrainrotId")])
	local root = model.PrimaryPart
	if not meta or not root then
		return
	end
	escapeAnchor = Instance.new("Attachment")
	escapeAnchor.Name = "HandEscapeAnchor"
	escapeAnchor.Position = root.CFrame:PointToObjectSpace(
		model:GetPivot():PointToWorldSpace(meta.normalizedTop + Vector3.yAxis * C.EscapeAbove)
	)
	escapeAnchor.Parent = root
	escapeGui = Instance.new("BillboardGui")
	escapeGui.Name = "HandEscapeWarning"
	escapeGui.Adornee = escapeAnchor
	escapeGui.AlwaysOnTop = false
	escapeGui.Parent = model
	text(escapeGui, "Text").Size = UDim2.fromScale(1, 1)
	timerBinding =
		{ model = model, deadline = deadline, revision = revision, generation = generation, last = -math.huge }
	updateEscape()
end
function Hud.GetUnit()
	Hud.Start()
	return unit()
end
function Hud.GetDiagnostics()
	local out = { rectangles = {}, layoutError = layoutError, escapeVisible = escapeGui ~= nil }
	if safe then
		out.safeArea = rect(safe)
		out.u = unit()
		for _, p in ipairs({ status, toast, rare, primary, drop }) do
			out.rectangles[p.Name] = { bounds = rect(p), visible = p.Visible }
		end
		for n, r in rows do
			out.rectangles[n] = {
				bounds = rect(r.frame),
				visible = r.frame.Visible,
				text = r.text.Text,
				TextBounds = { r.text.TextBounds.X, r.text.TextBounds.Y },
			}
		end
	end
	local message, pending = queue.Step(os.clock())
	out.activeMessages = if message then 1 else 0
	out.pendingMessages = pending
	return out
end
function Hud.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	clearEscape()
	if gui then
		gui:Destroy()
		gui = nil
	end
end
return Hud
