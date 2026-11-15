--!strict
-- Stud Pop juice: every animation and sound the design system specifies.
-- TweenService only; one live tween per (instance, channel) so rapid taps never fight.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Juice = {}

-- live tweens keyed by instance then channel; weak keys so destroyed UI is collected
local live: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

local function play(inst: Instance, channel: string, info: TweenInfo, goal: { [string]: any }): Tween
	local perInst = live[inst]
	if not perInst then
		perInst = {}
		live[inst] = perInst
	end
	local prev = perInst[channel]
	if prev then
		prev:Cancel()
	end
	local t = TweenService:Create(inst, info, goal)
	perInst[channel] = t
	t:Play()
	return t
end
Juice.play = play

-- UIScale child used by every scale effect (never tween Size: it fights layouts)
local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("JuiceScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "JuiceScale"
	n.Parent = gui
	return n
end
Juice.scaleOf = scaleOf

------------------------------------------------------------------ sound
local soundCache: { [string]: Sound } = {}
function Juice.sound(name: string, pitchJitter: number?)
	local id = Theme.Sounds[name]
	if not id or id == "" then
		return
	end
	local s = soundCache[name]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = SoundService
		soundCache[name] = s
	end
	local j = pitchJitter or 0.05
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * j
	SoundService:PlayLocalSound(s)
end

------------------------------------------------------------------ reduced motion
-- The game's existing accessibility toggle (player attribute ReducedMotion).
function Juice.reduced(): boolean
	local p = Players.LocalPlayer
	return p ~= nil and p:GetAttribute("ReducedMotion") == true
end

------------------------------------------------------------------ icons
-- Tap feedback on an icon: quick grow + tilt, then an elastic settle (or a full twirl).
-- `rotator` is what spins (pass a wrapper when the icon's own Rotation is owned by a bob loop).
function Juice.iconBounce(icon: GuiObject, twirl: boolean?, rotator: GuiObject?)
	if Juice.reduced() then
		return
	end
	local s = scaleOf(icon)
	play(s, "icon", Theme.Motion.IconPop, { Scale = 1.28 }).Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			play(s, "icon", Theme.Motion.IconSettle, { Scale = 1 })
		end
	end)
	local r = rotator or icon
	if twirl then
		r.Rotation = 0
		play(r, "twirl", Theme.Motion.IconTwirl, { Rotation = 360 }).Completed:Once(function()
			r.Rotation = 0
		end)
	else
		play(r, "twirl", Theme.Motion.IconPop, { Rotation = 14 }).Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				play(r, "twirl", Theme.Motion.IconSettle, { Rotation = 0 })
			end
		end)
	end
end

------------------------------------------------------------------ hover (mouse only; touch has no hover)
function Juice.bindHover(button: GuiButton): () -> ()
	if not UserInputService.MouseEnabled then
		return function() end
	end
	local s = scaleOf(button)
	local a = button.MouseEnter:Connect(function()
		if not Juice.reduced() then
			play(s, "hover", Theme.Motion.Hover, { Scale = Theme.Motion.HoverScale })
		end
	end)
	local b = button.MouseLeave:Connect(function()
		play(s, "hover", Theme.Motion.Hover, { Scale = 1 })
	end)
	return function()
		a:Disconnect()
		b:Disconnect()
	end
end

------------------------------------------------------------------ pop
-- 1 -> peak -> 1. Rewards, coin landings, badge appearance.
function Juice.pop(gui: GuiObject, peak: number?)
	local s = scaleOf(gui)
	local t = play(s, "pop", Theme.Motion.PopOut, { Scale = peak or 1.12 })
	t.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			play(s, "pop", Theme.Motion.PopBack, { Scale = 1 })
		end
	end)
end

------------------------------------------------------------------ press
-- Face drops onto its lip (Lip frame sits Theme.Size.Lip px lower), scale 0.96.
-- Returns a disconnect function.
function Juice.bindPress(button: GuiButton, face: GuiObject, restPos: UDim2, pressedPos: UDim2, opts: { sound: string?, locked: (() -> boolean)? }?): () -> ()
	local s = scaleOf(face)
	local conns: { RBXScriptConnection } = {}
	local function down()
		play(face, "press", Theme.Motion.PressDown, { Position = pressedPos })
		play(s, "press", Theme.Motion.PressDown, { Scale = Theme.Motion.PressScale })
	end
	local function up()
		play(face, "press", Theme.Motion.Release, { Position = restPos })
		play(s, "press", Theme.Motion.Release, { Scale = 1 })
	end
	table.insert(conns, button.MouseButton1Down:Connect(down))
	table.insert(conns, button.MouseButton1Up:Connect(up))
	table.insert(conns, button.MouseLeave:Connect(up))
	table.insert(conns, button.Activated:Connect(function()
		local isLocked = opts and opts.locked and opts.locked()
		if isLocked then
			Juice.sound("Error", 0)
			Juice.shake(face, 3, 0.2)
		else
			Juice.sound((opts and opts.sound) or "Click")
		end
	end))
	return function()
		for _, c in conns do
			c:Disconnect()
		end
	end
end

------------------------------------------------------------------ shake
function Juice.shake(gui: GuiObject, px: number, duration: number)
	local origin = gui.Position
	local amp = Theme.px(px)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		if e >= duration or not gui.Parent then
			conn:Disconnect()
			gui.Position = origin
			return
		end
		local k = 1 - e / duration
		gui.Position = origin + UDim2.fromOffset((math.random() * 2 - 1) * amp * k, (math.random() * 2 - 1) * amp * k)
	end)
end

------------------------------------------------------------------ shine sweep
-- A white diagonal bar crosses `surface` every Theme.Motion.ShineEvery seconds.
-- `surface` must clip: a CanvasGroup (keeps rounded corners) or ClipsDescendants frame.
function Juice.shine(surface: GuiObject): () -> ()
	local bar = Instance.new("Frame")
	bar.Name = "Shine"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.Size = UDim2.fromScale(0.35, 2)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Rotation = 18
	bar.Position = UDim2.fromScale(-0.4, 0.5)
	bar.ZIndex = 50
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = bar
	bar.Parent = surface
	local alive = true
	task.spawn(function()
		while alive and bar.Parent do
			bar.Position = UDim2.fromScale(-0.4, 0.5)
			play(bar, "shine", TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.4, 0.5) })
			task.wait(Theme.Motion.ShineEvery)
		end
	end)
	return function()
		alive = false
		bar:Destroy()
	end
end

------------------------------------------------------------------ breathe (the ONE primary button per screen)
function Juice.breathe(gui: GuiObject): () -> ()
	local s = scaleOf(gui)
	local t = play(s, "breathe", Theme.Motion.Breathe, { Scale = 1.045 })
	return function()
		t:Cancel()
		s.Scale = 1
	end
end

------------------------------------------------------------------ sparkles (4-point twinkles)
-- Spawns `n` twinkles at random spots over `gui`, once. Call on a loop for ambient sparkle.
function Juice.sparkles(gui: GuiObject, n: number, color: Color3?)
	for _ = 1, n do
		local sz = Theme.px(math.random(10, 18))
		local sp: GuiObject
		if Theme.Images.Sparkle ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = Theme.Images.Sparkle
			img.ImageColor3 = color or Color3.new(1, 1, 1)
			sp = img
		else
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color or Color3.new(1, 1, 1)
			f.Rotation = 45
			sp = f
		end
		sp.AnchorPoint = Vector2.new(0.5, 0.5)
		sp.Position = UDim2.fromScale(math.random(5, 95) / 100, math.random(5, 95) / 100)
		sp.Size = UDim2.fromOffset(sz, sz)
		sp.ZIndex = gui.ZIndex + 5
		sp.Parent = gui
		local s = scaleOf(sp)
		s.Scale = 0
		local grow = play(s, "tw", TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		play(sp, "tw", TweenInfo.new(0.7, Enum.EasingStyle.Linear), { Rotation = sp.Rotation + 90 })
		grow.Completed:Once(function()
			play(s, "tw", TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }).Completed:Once(function()
				sp:Destroy()
			end)
		end)
	end
end

-- Ambient twinkle loop (primary button, gem pill, best-value pack). Returns stop().
function Juice.twinkleLoop(gui: GuiObject, every: number, color: Color3?): () -> ()
	local alive = true
	task.spawn(function()
		while alive and gui.Parent do
			Juice.sparkles(gui, 1, color)
			task.wait(every * (0.7 + math.random() * 0.6))
		end
	end)
	return function()
		alive = false
	end
end

------------------------------------------------------------------ icon bob (HUD icons; offset per icon so the rail never moves in sync)
function Juice.bob(icon: GuiObject, offset: number?): () -> ()
	local rest = icon.Position
	local alive = true
	task.delay(offset or 0, function()
		if not alive then
			return
		end
		play(icon, "bob", TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = rest - UDim2.fromOffset(0, Theme.px(4)),
			Rotation = 3,
		})
	end)
	icon.Rotation = -3
	return function()
		alive = false
		icon.Position = rest
		icon.Rotation = 0
	end
end

------------------------------------------------------------------ float (badges)
function Juice.float(gui: GuiObject): () -> ()
	local rest = gui.Position
	local half = Theme.Motion.FloatPeriod / 2
	local info = TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local a = play(gui, "float", info, { Position = rest - UDim2.fromOffset(0, Theme.px(3)), Rotation = gui.Rotation + 4 })
	return function()
		a:Cancel()
		gui.Position = rest
	end
end

------------------------------------------------------------------ pulse (Mythic / Celestial frames)
function Juice.pulse(stroke: UIStroke, from: number, to: number): () -> ()
	stroke.Thickness = from
	local t = play(stroke, "pulse", TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = to })
	return function()
		t:Cancel()
	end
end

------------------------------------------------------------------ rainbow (Secret, best deal)
function Juice.rainbow(gradient: UIGradient): () -> ()
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#FF4B67")),
		ColorSequenceKeypoint.new(0.2, Color3.fromHex("#FFAE3D")),
		ColorSequenceKeypoint.new(0.4, Color3.fromHex("#72E65B")),
		ColorSequenceKeypoint.new(0.6, Color3.fromHex("#6DEBFF")),
		ColorSequenceKeypoint.new(0.8, Color3.fromHex("#B86CFF")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#FF4B67")),
	})
	local t = play(gradient, "rainbow", TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = gradient.Rotation + 360 })
	return function()
		t:Cancel()
	end
end

------------------------------------------------------------------ count up
-- Rolls a TextLabel from `from` to `to` (never snaps). Uses Theme.abbreviate unless `format` given.
local counters: { [TextLabel]: NumberValue } = setmetatable({}, { __mode = "k" }) :: any
function Juice.countUp(label: TextLabel, from: number, to: number, format: ((number) -> string)?)
	local fmt = format or Theme.abbreviate
	local prev = counters[label]
	if prev then
		from = prev.Value -- continue from wherever the last roll got to
		prev:Destroy() -- also kills its tween and Changed connection
	end
	local nv = Instance.new("NumberValue")
	nv.Value = from
	counters[label] = nv
	nv.Changed:Connect(function(v: number)
		label.Text = fmt(math.floor(v + 0.5))
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(Theme.Motion.CountUpSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = to })
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			label.Text = fmt(to)
			if counters[label] == nv then
				counters[label] = nil
			end
			nv:Destroy()
		end
	end)
	tw:Play()
end

------------------------------------------------------------------ fly to (coins from world to pill)
-- Spawns `count` icons at a world position and flies them into `target` (e.g. the coin pill icon).
-- Cash: fast burst (stagger 0.05). Gems: pass stagger 0.12 and sound "GemTing" so each rock lands on its own.
function Juice.flyTo(screenGui: ScreenGui, image: string, worldPos: Vector3, target: GuiObject, count: number?, onEach: (() -> ())?, stagger: number?, landSound: string?)
	local cam = workspace.CurrentCamera
	if not cam or image == "" then
		return
	end
	local p, onScreen = cam:WorldToViewportPoint(worldPos)
	if not onScreen then
		return
	end
	local inset = if screenGui.IgnoreGuiInset then Vector2.zero else game:GetService("GuiService"):GetGuiInset()
	local startPt = Vector2.new(p.X, p.Y) - inset
	local endPt = target.AbsolutePosition + target.AbsoluteSize / 2
	local n = count or 6
	local sz = Theme.px(34)
	for i = 1, n do
		task.delay((i - 1) * (stagger or 0.05), function()
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = image
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Size = UDim2.fromOffset(sz, sz)
			img.Position = UDim2.fromOffset(startPt.X + math.random(-30, 30), startPt.Y + math.random(-30, 30))
			img.ZIndex = 100
			img.Parent = screenGui
			local t = TweenService:Create(img, TweenInfo.new(0.45 + math.random() * 0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.fromOffset(endPt.X, endPt.Y), Size = UDim2.fromOffset(sz * 0.6, sz * 0.6) })
			t.Completed:Once(function()
				img:Destroy()
				Juice.pop(target, 1.15)
				Juice.sound(landSound or "Click", 0.15)
				if landSound == "GemTing" then
					Juice.sparkles(target, 2, Theme.Color.GemGlint)
				end
				if onEach then
					onEach()
				end
			end)
			t:Play()
		end)
	end
end

------------------------------------------------------------------ window entrance / exit
-- Pop a window in: scale 0.7 -> 1 with overshoot and a small tilt that rights itself, then its
-- buttons pop in one after another. Reduced motion: no scale or tilt.
function Juice.windowIn(window: GuiObject)
	if Juice.reduced() then
		return
	end
	local s = scaleOf(window)
	s.Scale = 0.7
	play(s, "win", Theme.Motion.WindowIn, { Scale = 1 })
	local rot = window.Rotation
	window.Rotation = rot - 3
	play(window, "winRot", Theme.Motion.WindowIn, { Rotation = rot })
	local buttons: { GuiObject } = {}
	for _, d in window:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible and #buttons < Theme.Motion.StaggerMax then
			table.insert(buttons, d)
		end
	end
	for i, b in buttons do
		local bs = scaleOf(b)
		bs.Scale = 0.55
		task.delay(0.06 + i * Theme.Motion.StaggerStep, function()
			if b.Parent then
				play(bs, "enter", Theme.Motion.Release, { Scale = 1 })
			end
		end)
	end
end

-- A window the controller just hid (or whose ScreenGui it disabled) cannot be animated in place
-- without lying to that controller about its state, so a throwaway copy shrinks and fades out on
-- `layer` (a ScreenGui with the same insets) while the real window is already gone.
function Juice.windowOutGhost(window: GuiObject, layer: ScreenGui, rect: { number }, maxDescendants: number?)
	if Juice.reduced() or rect[3] <= 0 or rect[4] <= 0 then
		return
	end
	if #window:GetDescendants() > (maxDescendants or 900) then
		return
	end
	local ok, ghost = pcall(function()
		return window:Clone()
	end)
	if not ok or not ghost then
		return
	end
	local holder = Instance.new("CanvasGroup")
	holder.Name = "WindowOutGhost"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(rect[1] - layer.AbsolutePosition.X, rect[2] - layer.AbsolutePosition.Y)
	holder.Size = UDim2.fromOffset(rect[3], rect[4])
	holder.Active = false
	holder.Interactable = false
	for _, c in ghost:GetChildren() do
		if c:IsA("UISizeConstraint") or c:IsA("UIAspectRatioConstraint") then
			c:Destroy()
		end
	end
	ghost.AnchorPoint = Vector2.zero
	ghost.Position = UDim2.new()
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.Visible = true
	ghost.Parent = holder
	holder.Parent = layer
	local s = scaleOf(holder)
	play(s, "out", Theme.Motion.WindowOut, { Scale = 0.82 })
	play(holder, "out", Theme.Motion.WindowOut, { GroupTransparency = 1, Rotation = 2 }).Completed:Once(function()
		holder:Destroy()
	end)
end

------------------------------------------------------------------ window open / close
-- `group` is the window's CanvasGroup; `scrim` the full-screen dim frame.
function Juice.open(group: CanvasGroup, scrim: GuiObject?)
	group.Visible = true
	local s = scaleOf(group)
	s.Scale = if Juice.reduced() then 1 else 0.7
	group.GroupTransparency = 1
	play(s, "win", Theme.Motion.Open, { Scale = 1 })
	play(group, "win", TweenInfo.new(0.15), { GroupTransparency = 0 })
	if scrim then
		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		play(scrim, "win", TweenInfo.new(0.2), { BackgroundTransparency = Theme.ScrimTransparency })
	end
	Juice.sound("Click")
end

function Juice.close(group: CanvasGroup, scrim: GuiObject?)
	local s = scaleOf(group)
	play(s, "win", Theme.Motion.Close, { Scale = if Juice.reduced() then 1 else 0.82 })
	local t = play(group, "win", Theme.Motion.Close, { GroupTransparency = 1 })
	t.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			group.Visible = false
		end
	end)
	if scrim then
		local ts = play(scrim, "win", Theme.Motion.Close, { BackgroundTransparency = 1 })
		ts.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				scrim.Visible = false
			end
		end)
	end
end

return Juice
