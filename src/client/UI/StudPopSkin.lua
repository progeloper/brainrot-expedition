--!nocheck
-- Stud Pop v2 skin for controller-built ScreenGuis (view layer only).
--
-- Controllers keep building, positioning, wiring and updating their own instances; this module only
-- restyles what they create (and keeps restyling as they rebuild), so every button still fires the
-- same remote with the same arguments. Colour = meaning: a button's variant comes from its words
-- (BUY/CLAIM/EQUIP -> go, CLOSE/CANCEL/SELL -> stop, Robux -> robux, disabled -> locked, else info).
--
-- Attach(gui, {
--   hints = { [instanceName] = "primary" | "go" | "stop" | "info" | "robux" | "alert" | "locked"
--             | "window" | "card" | "scrim" | "title" | "hide" | "skip" | "plain" },
--   windows = { name, ... },     -- frames to style as the violet window body
-- })
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Skin = {}

local MARK = "StudPopSkinned"
local OWNED = "StudPopOwned" -- instances built by Stud Pop screens; never reskinned
local ROBUX_GLYPH = utf8.char(0xE002)

local WORDS = {
	stop = { "close", "cancel", "exit", "sell", "unequip", "remove", "decline", "leave", "end protection", "not now", "skip", "back" },
	go = {
		"buy", "claim", "equip", "confirm", "purchase", "upgrade", "select", "unlock", "yes", "rebirth", "place",
		"load", "drive", "pick", "track", "save", "apply", "replace", "swap", "train", "use", "collect", "open gate",
		"fire", "burst", "pin", "feature", "get",
	},
	locked = { "need ", "locked", "coming soon", "unavailable", "not enough", "owned", "equipped", "maxed", "max level" },
}

local function px(n: number): number
	return Theme.px(n)
end

local function lower(s: string?): string
	return string.lower(s or "")
end

local function hasWord(text: string, list: { string }): boolean
	for _, w in list do
		if w == "x" then
			if text == "x" or text == "✕" or text == "×" then
				return true
			end
		elseif string.find(text, w, 1, true) then
			return true
		end
	end
	return false
end

function Skin.ClassifyButton(button: GuiButton, hint: string?): string
	if hint and Theme.Variant[hint] then
		return hint
	end
	local t = lower(if button:IsA("TextButton") then button.Text else "")
	local n = lower(button.Name)
	if button.Active == false or button:GetAttribute("StudPopLocked") == true then
		return "locked"
	end
	if string.find(t, "r$", 1, true) or string.find(t, ROBUX_GLYPH, 1, true) or string.find(n, "robux", 1, true) then
		return "robux"
	end
	if hasWord(t, WORDS.locked) then
		return "locked"
	end
	if t == "x" or t == "✕" or t == "×" or hasWord(t, WORDS.stop) or hasWord(n, { "close", "cancel" }) then
		return "stop"
	end
	if hasWord(t, WORDS.go) then
		return "go"
	end
	return "info"
end

------------------------------------------------------------------ primitives
local function firstOf(parent: Instance, className: string): Instance?
	for _, c in parent:GetChildren() do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end

local function corner(gui: GuiObject, radius: UDim)
	local c = firstOf(gui, "UICorner") or Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = gui
end

local function borderStroke(gui: GuiObject, thickness: number, color: Color3?): UIStroke
	local s
	for _, c in gui:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			s = c
			break
		end
	end
	s = s or Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Color.Ink
	s.Thickness = px(thickness)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Transparency = 0
	s.Parent = gui
	return s
end

local function gloss(gui: GuiObject, radius: UDim)
	local f = gui:FindFirstChild("StudPopGloss")
	if not f then
		f = Instance.new("Frame")
		f.Name = "StudPopGloss"
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.Active = false
		f.Interactable = false
		f.Size = UDim2.fromScale(1, 0.45)
		f:SetAttribute(OWNED, true)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new(0.74, 0.9)
		g.Parent = f
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = f
		f.Parent = gui
	end
	f.ZIndex = gui.ZIndex
	if not gui:FindFirstChild("StudPopShade") then
		local shade = Instance.new("Frame")
		shade.Name = "StudPopShade"
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.8
		shade.BorderSizePixel = 0
		shade.Active = false
		shade.Interactable = false
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.fromScale(0, 1)
		shade.Size = UDim2.fromScale(1, 0.16)
		shade.ZIndex = gui.ZIndex
		shade:SetAttribute(OWNED, true)
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = shade
		shade.Parent = gui
	end
end

local function minTextSize(t: TextLabel | TextButton | TextBox, floor: number)
	if t.TextScaled then
		local c = firstOf(t, "UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		if c.MinTextSize < floor then
			c.MinTextSize = floor
		end
		if c.MaxTextSize < floor then
			c.MaxTextSize = floor
		end
		c.Parent = t
	elseif t.TextSize < floor then
		t.TextSize = floor
	end
end

local function inkText(t: TextLabel | TextButton | TextBox, display: boolean)
	t.FontFace = if display then Theme.Font.Display else Theme.Font.Body
	t.TextStrokeColor3 = Theme.Color.Ink
	t.TextStrokeTransparency = 0.05
	minTextSize(t, Theme.Size.MinText)
end

------------------------------------------------------------------ buttons
-- Buttons get a solid variant fill plus the gloss dome and bottom shade children. (A UIGradient on a
-- TextButton would also tint its label, breaking "loud frame, calm label".)
local painting: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function applyVariant(button: GuiButton, variant: string)
	button:SetAttribute("StudPopVariant", variant)
	painting[button] = true
	button.BackgroundColor3 = Theme.ramp(variant).base
	painting[button] = nil
end

-- Squash on press (<100 ms), overshoot-and-settle on release, hover lift on mouse, and a tap
-- reward: icons inside the button bounce, "do it" buttons throw a couple of sparkles, locked
-- buttons shake. ReducedMotion keeps only the small press squash.
local function buttonIcons(button: GuiButton): { GuiObject }
	local found = {}
	for _, d in button:GetDescendants() do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" and not d:GetAttribute(OWNED) then
			table.insert(found, d)
			if #found >= 2 then
				break
			end
		end
	end
	return found
end

local function pressJuice(button: GuiButton)
	local s = Juice.scaleOf(button)
	button.MouseButton1Down:Connect(function()
		Juice.play(s, "press", Theme.Motion.PressDown, {
			Scale = if Juice.reduced() then 0.96 else Theme.Motion.PressScale,
		})
	end)
	local function release()
		Juice.play(s, "press", Theme.Motion.Release, { Scale = 1 })
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	Juice.bindHover(button)
	button.Activated:Connect(function()
		local variant = button:GetAttribute("StudPopVariant")
		if variant == "locked" then
			Juice.shake(button, 3, 0.18)
			Juice.sound("Error", 0)
			return
		end
		Juice.sound("Click")
		for _, ic in buttonIcons(button) do
			Juice.iconBounce(ic)
		end
		if (variant == "go" or variant == "robux") and not Juice.reduced() then
			Juice.sparkles(button, 2)
		end
	end)
end

-- The ONE breathing primary per screen: breathes and twinkles only while visible.
local function primaryLoop(button: GuiButton)
	local stopBreathe, stopTwinkle
	local function sync()
		local on = button.Visible and button.Parent ~= nil
		if on and not stopBreathe then
			stopBreathe = Juice.breathe(button)
			stopTwinkle = Juice.twinkleLoop(button, 1.4)
		elseif not on and stopBreathe then
			stopBreathe()
			stopTwinkle()
			stopBreathe, stopTwinkle = nil, nil
		end
	end
	button:GetPropertyChangedSignal("Visible"):Connect(sync)
	button.AncestryChanged:Connect(sync)
	sync()
end

function Skin.Button(button: GuiButton, hint: string?)
	if button:GetAttribute(MARK) then
		return
	end
	button:SetAttribute(MARK, true)
	local transparentHit = button.BackgroundTransparency >= 0.95
	button.AutoButtonColor = false
	local radius = UDim.new(0, px(if hint == "primary" then 18 else 12))
	if not transparentHit then
		-- read the controller's state colour (grey DISABLED fills) before repainting
		local _, sat, val = button.BackgroundColor3:ToHSV()
		button:SetAttribute("StudPopLocked", sat < 0.16 and val < 0.5)
		button.BackgroundTransparency = 0
		corner(button, radius)
		borderStroke(button, Theme.Size.Stroke - 1)
		gloss(button, radius)
	end
	if button:IsA("TextButton") then
		inkText(button, true)
		button.TextColor3 = Theme.Color.Text
	end
	if not firstOf(button, "UISizeConstraint") then
		local min = Instance.new("UISizeConstraint")
		min.MinSize = Vector2.new(0, Theme.Size.TouchMin)
		min.Parent = button
	end

	local function reclassify()
		if transparentHit then
			return
		end
		applyVariant(button, Skin.ClassifyButton(button, if hint == "primary" then "go" else hint))
	end
	reclassify()
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if painting[button] or transparentHit then
			return
		end
		-- Controllers signal state with colour (e.g. a grey DISABLED fill). Read it, then repaint.
		local _, s, v = button.BackgroundColor3:ToHSV()
		button:SetAttribute("StudPopLocked", s < 0.16 and v < 0.5)
		button.BackgroundTransparency = 0
		reclassify()
	end)
	if button:IsA("TextButton") then
		button:GetPropertyChangedSignal("Text"):Connect(reclassify)
		button:GetPropertyChangedSignal("TextColor3"):Connect(function()
			if button.TextColor3 ~= Theme.Color.Text then
				button.TextColor3 = Theme.Color.Text
			end
		end)
		button:GetPropertyChangedSignal("Font"):Connect(function()
			if button.FontFace ~= Theme.Font.Display then
				button.FontFace = Theme.Font.Display
			end
		end)
	end
	button:GetPropertyChangedSignal("Active"):Connect(reclassify)
	pressJuice(button)
	if hint == "primary" then
		primaryLoop(button)
	end
end

------------------------------------------------------------------ panels
function Skin.Window(frame: GuiObject)
	if frame:GetAttribute(MARK) then
		return
	end
	frame:SetAttribute(MARK, true)
	frame.BackgroundTransparency = 0
	corner(frame, Theme.Radius.Lg)
	borderStroke(frame, Theme.Size.Stroke)
	local isGroup = frame:IsA("CanvasGroup") -- a gradient on a CanvasGroup would tint its children
	frame.BackgroundColor3 = if isGroup then Theme.Color.Panel else Color3.new(1, 1, 1)
	if not isGroup then
		local g = frame:FindFirstChild("StudPopRamp") or Instance.new("UIGradient")
		g.Name = "StudPopRamp"
		g.Rotation = 90
		g.Color = ColorSequence.new(Theme.Color.PanelHi, Theme.Color.Panel)
		g.Parent = frame
	end
	if Theme.StudTexture ~= "" and frame:IsA("Frame") then
		local studs = Instance.new("ImageLabel")
		studs.Name = "StudPopStuds"
		studs.BackgroundTransparency = 1
		studs.Image = Theme.StudTexture
		studs.ImageTransparency = 0.93
		studs.ScaleType = Enum.ScaleType.Tile
		studs.TileSize = UDim2.fromOffset(px(Theme.StudTilePx * 2), px(Theme.StudTilePx * 2))
		studs.Size = UDim2.fromScale(1, 1)
		studs.ZIndex = frame.ZIndex
		studs.Active = false
		studs.Interactable = false
		studs:SetAttribute(OWNED, true)
		local c = Instance.new("UICorner")
		c.CornerRadius = Theme.Radius.Lg
		c.Parent = studs
		studs.Parent = frame
	end
	local guard = false
	frame:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if guard then
			return
		end
		guard = true
		frame.BackgroundColor3 = if frame:IsA("CanvasGroup") then Theme.Color.Panel else Color3.new(1, 1, 1)
		guard = false
	end)	Skin.WindowMotion(frame)
end

------------------------------------------------------------------ window motion
-- Pop-in when a skinned window becomes shown (its Visible, or its ScreenGui's Enabled, turns on);
-- a ghost copy pops out when the controller hides it. The controller's own state flips instantly,
-- exactly as before; only the picture animates.
local fxLayers: { [Instance]: ScreenGui } = setmetatable({}, { __mode = "k" }) :: any
local enabledAt: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local function fxLayer(source: ScreenGui): ScreenGui
	local layer = fxLayers[source]
	if layer and layer.Parent then
		return layer
	end
	layer = Instance.new("ScreenGui")
	layer.Name = "StudPopFx_" .. source.Name
	layer.ResetOnSpawn = false
	layer.IgnoreGuiInset = source.IgnoreGuiInset
	layer.ScreenInsets = source.ScreenInsets
	layer.DisplayOrder = source.DisplayOrder
	layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	layer:SetAttribute(OWNED, true)
	layer.Parent = source.Parent
	fxLayers[source] = layer
	return layer
end

local function shownNow(frame: GuiObject): boolean
	local c: Instance? = frame
	while c do
		if c:IsA("GuiObject") and not c.Visible then
			return false
		end
		if c:IsA("ScreenGui") then
			return c.Enabled
		end
		c = c.Parent
	end
	return false
end

function Skin.WindowMotion(frame: GuiObject)
	local screen = frame:FindFirstAncestorOfClass("ScreenGui")
	if not screen or frame:GetAttribute("StudPopMotion") then
		return
	end
	frame:SetAttribute("StudPopMotion", true)
	-- a controller that already scales this window (e.g. the sell dialog's WindowScale) keeps its own entrance
	local ownScale = false
	for _, c in frame:GetChildren() do
		if c:IsA("UIScale") and c.Name ~= "JuiceScale" then
			ownScale = true
		end
	end
	local shown = shownNow(frame)
	-- controllers that rebuild on open create the window right after enabling the gui
	if shown and not ownScale and enabledAt[screen] and os.clock() - enabledAt[screen] < 0.4 then
		Juice.windowIn(frame)
	end
	local rect = { 0, 0, 0, 0 }
	local function remember()
		if shown then
			rect = { frame.AbsolutePosition.X, frame.AbsolutePosition.Y, frame.AbsoluteSize.X, frame.AbsoluteSize.Y }
		end
	end
	remember()
	local function sync()
		local now = shownNow(frame)
		if now == shown then
			remember()
			return
		end
		shown = now
		if now then
			if not ownScale then
				Juice.windowIn(frame)
			end
			task.defer(remember)
		else
			Juice.windowOutGhost(frame, fxLayer(screen), rect)
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	screen:GetPropertyChangedSignal("Enabled"):Connect(sync)
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(remember)
	frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(remember)
end

-- Cards keep the controller's fill (it can encode state, e.g. a highlighted goal) under a gloss ramp.
function Skin.Card(frame: GuiObject)
	if frame:GetAttribute(MARK) then
		return
	end
	frame:SetAttribute(MARK, true)
	corner(frame, Theme.Radius.Md)
	borderStroke(frame, Theme.Size.Stroke - 1)
	if frame:IsA("Frame") or frame:IsA("ScrollingFrame") then
		local g = frame:FindFirstChild("StudPopRamp") or Instance.new("UIGradient")
		g.Name = "StudPopRamp"
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(175, 170, 205))
		g.Parent = frame
	end
end

function Skin.Scrim(frame: GuiObject)
	if frame:GetAttribute(MARK) then
		return
	end
	frame:SetAttribute(MARK, true)
	frame.BackgroundColor3 = Theme.Color.Scrim
	if frame.BackgroundTransparency < Theme.ScrimTransparency then
		frame.BackgroundTransparency = Theme.ScrimTransparency
	end
	-- fade the dim in whenever it appears
	local target = frame.BackgroundTransparency
	local screen = frame:FindFirstAncestorOfClass("ScreenGui")
	local was = shownNow(frame)
	local function sync()
		local now = shownNow(frame)
		if now and not was then
			frame.BackgroundTransparency = 1
			Juice.play(frame, "scrim", Theme.Motion.ScrimIn, { BackgroundTransparency = target })
		end
		was = now
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	if screen then
		screen:GetPropertyChangedSignal("Enabled"):Connect(sync)
	end
end

function Skin.Title(label: TextLabel)
	if label:GetAttribute(MARK) then
		return
	end
	label:SetAttribute(MARK, true)
	inkText(label, true)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	local g = Instance.new("UIGradient")
	g.Name = "StudPopRamp"
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#FFF6B0")),
		ColorSequenceKeypoint.new(0.4, Theme.Color.Burst),
		ColorSequenceKeypoint.new(1, Theme.Color.BurstLo),
	})
	g.Parent = label
end

local function isOverlayFrame(frame: GuiObject): boolean
	return frame.Size.X.Scale >= 0.99 and frame.Size.Y.Scale >= 0.99 and frame.BackgroundTransparency > 0.05
end

------------------------------------------------------------------ dispatcher
local function ownedByStudPop(inst: Instance): boolean
	local c = inst
	while c do
		if c:GetAttribute(OWNED) then
			return true
		end
		c = c.Parent
	end
	return false
end

local function skipped(inst: Instance, hints, root: Instance): boolean
	local c = inst
	while c and c ~= root do
		if hints[c.Name] == "skip" then
			return true
		end
		c = c.Parent
	end
	return false
end

local function depthBelow(inst: Instance, root: Instance): number
	local d, c = 0, inst
	while c and c ~= root do
		if c:IsA("GuiObject") then
			d += 1
		end
		c = c.Parent
	end
	return d
end

function Skin.Apply(inst: Instance, root: Instance, options)
	local hints = options.hints or {}
	if inst:GetAttribute(MARK) or ownedByStudPop(inst) or skipped(inst, hints, root) then
		return
	end
	local hint = inst:GetAttribute("StudPopHint") or hints[inst.Name]
	if hint == "hide" and inst:IsA("GuiObject") then
		inst:SetAttribute(MARK, true)
		inst.Visible = false
		inst:GetPropertyChangedSignal("Visible"):Connect(function()
			if inst.Visible then
				inst.Visible = false
			end
		end)
		return
	end
	if hint == "plain" then
		return
	end
	if inst:IsA("GuiButton") then
		Skin.Button(inst, hint)
	elseif inst:IsA("TextLabel") then
		if hint == "title" or (options.titles and options.titles[inst.Name]) then
			Skin.Title(inst)
		else
			inst:SetAttribute(MARK, true)
			local display = inst.TextSize >= 20 or string.find(lower(inst.Name), "title", 1, true) ~= nil
				or string.find(lower(inst.Name), "heading", 1, true) ~= nil
			inkText(inst, display)
		end
		if inst.BackgroundTransparency < 0.9 then
			corner(inst, Theme.Radius.Sm)
		end
	elseif inst:IsA("TextBox") then
		inst:SetAttribute(MARK, true)
		inkText(inst, false)
	elseif inst:IsA("ScrollingFrame") then
		inst:SetAttribute(MARK, true)
		inst.ScrollBarImageColor3 = Theme.Color.TextMuted
		if inst.BackgroundTransparency < 0.9 then
			Skin.Card(inst)
		end
	elseif inst:IsA("Frame") or inst:IsA("CanvasGroup") then
		if hint == "window" or (options.windows and table.find(options.windows, inst.Name)) then
			Skin.Window(inst)
		elseif hint == "scrim" then
			Skin.Scrim(inst)
		elseif hint == "card" then
			Skin.Card(inst)
		elseif inst.BackgroundTransparency < 0.9 then
			if isOverlayFrame(inst) then
				Skin.Scrim(inst)
			elseif depthBelow(inst, root) <= (options.windowDepth or 1) then
				Skin.Window(inst)
			else
				Skin.Card(inst)
			end
		end
	end
end

-- Restyles everything under `gui` now and whatever the controller adds later. Returns detach().
function Skin.Attach(gui: Instance, options: any?)
	local opts = options or {}
	if gui:IsA("ScreenGui") then
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then
				enabledAt[gui] = os.clock()
			end
		end)
	end
	for _, d in gui:GetDescendants() do
		Skin.Apply(d, gui, opts)
	end
	local conn = gui.DescendantAdded:Connect(function(d)
		-- defer so the controller finishes setting Text/Size/colours before we read them
		task.defer(function()
			if d.Parent then
				Skin.Apply(d, gui, opts)
			end
		end)
	end)
	return function()
		conn:Disconnect()
	end
end

-- Convenience for screens that only exist in a controller's local scope.
function Skin.PlayerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

return Skin
