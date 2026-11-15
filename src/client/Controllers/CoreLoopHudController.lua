--!strict
-- Core Loop V2 client presentation (CP-A): the RUSH chip + T-10 countdown (H3, board 5) and the Star
-- pillars (B3). Reads only server attributes; decides nothing.
-- L6 gate: until a review group is approved in CoreLoopFx.Approved, its elements render their plain
-- fallback. The chip is a Stud Pop surface built from board 5 (Group 1); the pillars are a single plain
-- Beam per Star in its tier glow colour (Group 2 fallback: shape + colour, no texture or sparkles).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local CoreLoopFlags = require(Shared.Config.CoreLoopFlags)
local Fx = require(Shared.Config.CoreLoopFx)
local Theme = require(Shared.UI.Theme)
local StudPop = require(Shared.UI.StudPop)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)

local Controller = {}

local R = Fx.L4_3_Rush

------------------------------------------------------------------ RUSH chip
type Chip = {
	Root: Frame,
	Face: CanvasGroup,
	Fill: Frame,
	Label: TextLabel,
	Strip: Frame,
	StripFill: Frame,
	Subline: TextLabel,
	Aspect: UIAspectRatioConstraint,
}

-- Same sizing rule as the rest of the Stud Pop HUD: 844x390 px through Theme.px (scales with the
-- viewport height, capped), so the chip keeps its board proportions on any aspect ratio.
local function scaleSize(px: Vector2): UDim2
	return UDim2.fromOffset(Theme.px(px.X), Theme.px(px.Y))
end

local function buildChip(gui: ScreenGui): Chip
	local root = Instance.new("Frame")
	root.Name = "RushChip"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, Theme.px(R.ChipTop))
	root.Size = scaleSize(R.ChipSize)
	root.Visible = false
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = R.ChipSize.X / R.ChipSize.Y
	aspect.Parent = root

	local lipPx = Theme.px(Theme.Size.Lip)
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = Theme.Color.Ink
	lip.BorderSizePixel = 0
	lip.Position = UDim2.fromOffset(0, lipPx)
	lip.Size = UDim2.new(1, 0, 1, -lipPx)
	local lipCorner = Instance.new("UICorner")
	lipCorner.CornerRadius = Theme.Radius.Pill
	lipCorner.Parent = lip
	lip.Parent = root

	local face = StudPop.Surface(root, "alert", Theme.Radius.Pill)
	face.Size = UDim2.new(1, 0, 1, -lipPx)
	face.ZIndex = 2
	local fill = face:FindFirstChild("Fill") :: Frame

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 4
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = content
	content.Parent = face

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0.62)
	row.LayoutOrder = 1
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.Padding = UDim.new(0, Theme.px(8))
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = row
	row.Parent = content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Bolt"
	icon.BackgroundTransparency = 1
	icon.Image = Theme.Icons.Bolt
	icon.Size = UDim2.fromScale(0.13, 1)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.Parent = icon
	icon.Parent = row

	local label = StudPop.Text(
		row,
		"",
		{ display = true, maxPx = R.LabelPx, size = UDim2.fromScale(0, 1), order = 2 }
	)
	-- Board 5 groups the bolt and the words tightly in the centre: size the label to its text.
	label.TextScaled = false
	label.TextSize = Theme.px(R.LabelPx)
	label.AutomaticSize = Enum.AutomaticSize.X

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundColor3 = Theme.Color.Ink
	strip.BackgroundTransparency = 0.6
	strip.BorderSizePixel = 0
	strip.Size = UDim2.fromScale(R.StripSize.X / R.ActiveSize.X, R.StripSize.Y / R.ActiveSize.Y)
	strip.LayoutOrder = 2
	strip.Visible = false
	local stripCorner = Instance.new("UICorner")
	stripCorner.CornerRadius = UDim.new(0.5, 0)
	stripCorner.Parent = strip
	local stripFill = Instance.new("Frame")
	stripFill.Name = "Fill"
	stripFill.BackgroundColor3 = Color3.new(1, 1, 1)
	stripFill.BorderSizePixel = 0
	stripFill.Size = UDim2.fromScale(1, 1)
	stripFill.Parent = strip
	strip.Parent = content

	local subline = StudPop.Text(
		root,
		R.Copy.MegaSubline,
		{ maxPx = R.SublinePx, color = Theme.CoreLoop.MegaA }
	)
	subline.Name = "Subline"
	subline.AnchorPoint = Vector2.new(0.5, 0)
	subline.Position = UDim2.new(0.5, 0, 1, Theme.px(6))
	subline.Size = UDim2.fromScale(1, 0.4)
	subline.Visible = false

	root.Parent = gui
	return {
		Root = root,
		Face = face,
		Fill = fill,
		Label = label,
		Strip = strip,
		StripFill = stripFill,
		Subline = subline,
		Aspect = aspect,
	}
end

local function setGradient(fill: Frame, kind: "Alert" | "Rush" | "Mega")
	local gradient = fill:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return
	end
	if kind == "Alert" then
		local r = Theme.ramp("alert")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, r.hi),
			ColorSequenceKeypoint.new(0.52, r.base),
			ColorSequenceKeypoint.new(1, r.lo),
		})
	else
		gradient.Rotation = 0 -- RushStates.dc.html: linear-gradient(90deg, …)
		local a = if kind == "Rush" then Theme.CoreLoop.RushA else Theme.CoreLoop.MegaA
		local b = if kind == "Rush" then Theme.CoreLoop.RushB else Theme.CoreLoop.MegaB
		gradient.Color = ColorSequence.new(a, b)
	end
end

------------------------------------------------------------------ Countdown
type Countdown = { Root: Frame, Digit: TextLabel, Scale: UIScale, SetRemaining: (number) -> () }

-- Radial drain (board 5: conic #ff3d9e over #ffffff22). Two half masks, each holding a full disc
-- whose UIGradient hides one half; rotating the gradients sweeps the visible wedge clockwise from 12.
local function radial(parent: Frame, colour: Color3): (number) -> ()
	local gradients = {}
	for _, side in { "Right", "Left" } do
		local holder = Instance.new("Frame")
		holder.Name = "Half" .. side
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = true
		holder.Size = UDim2.fromScale(0.5, 1)
		holder.Position = UDim2.fromScale(if side == "Right" then 0.5 else 0, 0)
		local discFrame = Instance.new("Frame")
		discFrame.BackgroundColor3 = colour
		discFrame.BorderSizePixel = 0
		discFrame.Size = UDim2.fromScale(2, 1)
		discFrame.Position = UDim2.fromScale(if side == "Right" then -1 else 0, 0)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = discFrame
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = discFrame
		discFrame.Parent = holder
		holder.Parent = parent
		gradients[side] = gradient
	end
	return function(fraction: number)
		local angle = math.clamp(fraction, 0, 1) * 360
		gradients.Right.Rotation = math.clamp(angle, 0, 180)
		gradients.Left.Rotation = math.clamp(angle, 180, 360)
	end
end

local function buildCountdown(gui: ScreenGui): Countdown
	local root = Instance.new("Frame")
	root.Name = "RushCountdown"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.42)
	root.Size = UDim2.fromOffset(Theme.px(R.CountdownRing), Theme.px(R.CountdownRing))
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	root.BackgroundTransparency = 0.87 -- #ffffff22 track
	root.Visible = false
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local setRemaining = radial(root, Theme.CoreLoop.RushA)
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size =
		UDim2.fromScale(R.CountdownDisc / R.CountdownRing, R.CountdownDisc / R.CountdownRing)
	disc.BackgroundColor3 = Theme.Color.Ink
	disc.BackgroundTransparency = 0.2
	disc.ZIndex = 3
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(0.5, 0)
	discCorner.Parent = disc
	disc.Parent = root
	local digit = StudPop.Text(
		disc,
		"",
		{ display = true, maxPx = R.CountdownDigitPx, color = Theme.Color.Burst }
	)
	local stroke = digit:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = Theme.px(R.CountdownStroke)
	end
	root.Parent = gui
	digit.ZIndex = 4
	return { Root = root, Digit = digit, Scale = scale, SetRemaining = setRemaining }
end

------------------------------------------------------------------ Saved tag (A7, L3.11 fallback)
-- Group 5 is not approved, so this is the plain fallback: a blue text bubble with the countdown.
local savedTags: { [Model]: BillboardGui } = {}

local function updateSavedTags(t: number)
	local folder = Workspace:FindFirstChild("Runtime")
	local brainrots = folder and folder:FindFirstChild("Brainrots")
	local localId = Players.LocalPlayer.UserId
	local seen: { [Model]: boolean } = {}
	if brainrots then
		for _, model in brainrots:GetChildren() do
			local untilAt = model:GetAttribute("SavedUntil")
			if
				model:IsA("Model")
				and model:GetAttribute("SavedOwnerUserId") == localId
				and type(untilAt) == "number"
				and untilAt > t
			then
				seen[model] = true
				local tag = savedTags[model]
				if not tag then
					tag = Instance.new("BillboardGui")
					tag.Name = "CoreLoopSavedTag"
					tag.Size = UDim2.fromOffset(Theme.px(150), Theme.px(46))
					tag.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
					tag.MaxDistance = 120
					tag.AlwaysOnTop = not (
						RunService:IsStudio()
						and ReplicatedStorage:GetAttribute("CoreLoopCaptureMode") == true
					)
					local bubble = Instance.new("Frame")
					bubble.Size = UDim2.fromScale(1, 1)
					bubble.BackgroundColor3 = Theme.CoreLoop.Saved
					local corner = Instance.new("UICorner")
					corner.CornerRadius = Theme.Radius.Md
					corner.Parent = bubble
					local stroke = Instance.new("UIStroke")
					stroke.Color = Theme.Color.Ink
					stroke.Thickness = Theme.px(Theme.Size.Stroke)
					stroke.Parent = bubble
					local title = StudPop.Text(
						bubble,
						"",
						{ display = true, maxPx = 18, size = UDim2.fromScale(1, 0.6) }
					)
					title.Name = "Title"
					local line = StudPop.Text(
						bubble,
						"BANK & COME BACK",
						{ maxPx = 14, size = UDim2.fromScale(1, 0.4) }
					)
					line.Position = UDim2.fromScale(0, 0.6)
					bubble.Parent = tag
					tag.Adornee = model
					tag.Parent = model
					savedTags[model] = tag
				end
				local left = math.max(0, math.ceil(untilAt - t))
				local title = tag:FindFirstChild("Title", true) :: TextLabel?
				if title then
					title.Text = string.format("SAVED %d:%02d", left // 60, left % 60)
				end
			end
		end
	end
	for model, tag in table.clone(savedTags) do
		if not seen[model] then
			tag:Destroy()
			savedTags[model] = nil
		end
	end
end

------------------------------------------------------------------ Lucky Meter (C1, L4.1, board 4)
-- Sits under the live CashPill, left-aligned, 8 px gap (board px scaled by the pill's real height).
type Meter = {
	Root: Frame,
	Badge: Frame,
	Bar: Frame,
	Fill: Frame,
	Gloss: Frame,
	Value: TextLabel,
	Scale: UIScale,
	Burst: TextLabel,
	Shown: number,
	FullUntil: number,
}
local M = Fx.L4_1_Meter

local function clover(parent: Frame)
	-- The board's clover badge icon (four circles), built from frames until CL_IconClover is uploaded.
	for i, offset in
		{
			Vector2.new(0.3, 0.3),
			Vector2.new(0.7, 0.3),
			Vector2.new(0.3, 0.7),
			Vector2.new(0.7, 0.7),
		}
	do
		local leaf = Instance.new("Frame")
		leaf.Name = "Leaf" .. i
		leaf.AnchorPoint = Vector2.new(0.5, 0.5)
		leaf.Position =
			UDim2.fromScale(0.25 + (offset.X - 0.3) * 1.25, 0.25 + (offset.Y - 0.3) * 1.25)
		leaf.Size = UDim2.fromScale(0.4, 0.4)
		leaf.BackgroundColor3 = Color3.new(1, 1, 1)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = leaf
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Color.Ink
		stroke.Thickness = 1.5
		stroke.Parent = leaf
		leaf.Parent = parent
	end
end

local function buildMeter(gui: ScreenGui): Meter
	local root = Instance.new("Frame")
	root.Name = "LuckyMeter"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(Theme.px(M.Badge + 6 + M.Bar.X), Theme.px(M.Badge))
	local scale = Instance.new("UIScale")
	scale.Parent = root
	-- Badge: go gradient circle, ink outline + 4 px lip.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromScale(M.Badge / (M.Badge + 6 + M.Bar.X), 1)
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0.5, 0)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Theme.Color.Ink
	badgeStroke.Thickness = Theme.px(Theme.Size.Stroke)
	badgeStroke.Parent = badge
	local badgeGradient = Instance.new("UIGradient")
	badgeGradient.Name = "Ramp"
	badgeGradient.Rotation = 90
	local go = Theme.ramp("go")
	badgeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, go.hi),
		ColorSequenceKeypoint.new(0.52, go.base),
		ColorSequenceKeypoint.new(1, go.lo),
	})
	badgeGradient.Parent = badge
	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.55, 0.55)
	icon.BackgroundTransparency = 1
	clover(icon)
	icon.Parent = badge
	local badgeAspect = Instance.new("UIAspectRatioConstraint")
	badgeAspect.Parent = badge
	badge.Parent = root
	-- Bar: 260 x 26 Panel trough, Lucky fill with studs + gloss, 4 px ink outline.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.fromScale(1, 0.5)
	bar.Size = UDim2.fromScale(M.Bar.X / (M.Badge + 6 + M.Bar.X), M.Bar.Y / M.Badge)
	bar.BackgroundColor3 = Theme.Color.Panel
	bar.ClipsDescendants = true
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = bar
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Theme.Color.Ink
	barStroke.Thickness = Theme.px(Theme.Size.Stroke)
	barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barStroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.CoreLoop.Lucky
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	local edge = Instance.new("UIStroke")
	edge.Color = Theme.Color.Ink
	edge.Thickness = Theme.px(3)
	edge.Parent = fill
	if Theme.StudTexture ~= "" then
		local studs = Instance.new("ImageLabel")
		studs.BackgroundTransparency = 1
		studs.Image = Theme.StudTexture
		studs.ImageTransparency = Theme.StudTransparency
		studs.ScaleType = Enum.ScaleType.Tile
		studs.TileSize = UDim2.fromOffset(Theme.px(14), Theme.px(14))
		studs.Size = UDim2.fromScale(1, 1)
		studs.Parent = fill
	end
	fill.Parent = bar
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.fromScale(0, 0.45)
	gloss.Parent = bar
	local label =
		StudPop.Text(bar, "LUCKY", { maxPx = M.LabelPx, align = Enum.TextXAlignment.Left })
	label.Position = UDim2.fromOffset(Theme.px(10), 0)
	label.Size = UDim2.fromScale(0.5, 1)
	label.ZIndex = 3
	local value = StudPop.Text(bar, "0%", { maxPx = M.LabelPx, align = Enum.TextXAlignment.Right })
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -Theme.px(10), 0, 0)
	value.Size = UDim2.fromScale(0.4, 1)
	value.ZIndex = 3
	bar.Parent = root
	-- "LUCKY STAR!" starburst sticker over the badge on full (board 4).
	local burst = StudPop.Text(
		root,
		"LUCKY\nSTAR!",
		{ display = true, maxPx = 12, color = Color3.new(1, 1, 1) }
	)
	burst.Name = "Burst"
	burst.Size = UDim2.fromOffset(Theme.px(96), Theme.px(54))
	burst.Position = UDim2.fromOffset(-Theme.px(28), -Theme.px(54))
	burst.Rotation = -8
	burst.BackgroundColor3 = Theme.Color.Burst
	burst.BackgroundTransparency = 0
	burst.Visible = false
	local burstCorner = Instance.new("UICorner")
	burstCorner.CornerRadius = UDim.new(0.3, 0)
	burstCorner.Parent = burst
	local burstStroke = Instance.new("UIStroke")
	burstStroke.Color = Theme.Color.Ink
	burstStroke.Thickness = Theme.px(3)
	burstStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	burstStroke.Parent = burst
	root.Parent = gui
	return {
		Root = root,
		Badge = badge,
		Bar = bar,
		Fill = fill,
		Gloss = gloss,
		Value = value,
		Scale = scale,
		Burst = burst,
		Shown = 0,
		FullUntil = 0,
	}
end

local function setMeter(meter: Meter, percent: number)
	local fraction = math.clamp(percent / 100, 0, 1)
	local visible = percent >= M.HideBelowPercent -- fills under 4% are hidden (14 Nov rule)
	meter.Fill.Visible = visible
	meter.Gloss.Visible = visible
	TweenService
		:Create(meter.Fill, TweenInfo.new(M.FillSeconds), { Size = UDim2.fromScale(fraction, 1) })
		:Play()
	TweenService
		:Create(
			meter.Gloss,
			TweenInfo.new(M.FillSeconds),
			{ Size = UDim2.fromScale(fraction, 0.45) }
		)
		:Play()
	meter.Value.Text = string.format("%d%%", math.floor(percent))
	meter.Shown = percent
end

local function meterFloaty(meter: Meter, gain: number, reason: string?)
	local sneak = reason == "SNEAK SHOT"
	local text = if sneak
		then "SNEAK SHOT +" .. math.floor(gain + 0.5)
		else "+" .. math.floor(gain + 0.5)
	local label = StudPop.Text(meter.Root, text, {
		maxPx = 16,
		color = if sneak then Color3.fromRGB(201, 168, 255) else Color3.fromRGB(141, 255, 58),
		align = Enum.TextXAlignment.Left,
	})
	label.Position = UDim2.new(1, Theme.px(6), 0, 0)
	label.Size = UDim2.new(0, Theme.px(140), 1, 0)
	TweenService:Create(label, TweenInfo.new(M.FloatySeconds), {
		Position = UDim2.new(1, Theme.px(6), 0, -Theme.px(14)),
		TextTransparency = 1,
	}):Play()
	task.delay(M.FloatySeconds, function()
		label:Destroy()
	end)
end

local function meterFull(meter: Meter)
	meter.FullUntil = os.clock() + M.FullSeconds
	meter.Fill.BackgroundColor3 = Theme.CoreLoop.LuckyFull
	meter.Value.Text = "FULL!"
	meter.Burst.Visible = true
	AudioCue.Play(Fx.L5_Cues.CL_METER_FULL)
	task.delay(M.FullSeconds, function()
		meter.Burst.Visible = false
		meter.Fill.BackgroundColor3 = Theme.CoreLoop.Lucky
		setMeter(meter, 0)
	end)
end

------------------------------------------------------------------ Start
function Controller.Start()
	local rushOn = CoreLoopFlags.Part("Rush")
	local starsOn = CoreLoopFlags.Part("Stars")
	if not rushOn and not starsOn then
		return
	end
	local camera = Workspace.CurrentCamera
	while camera.ViewportSize.Y < 200 do
		task.wait(0.1)
	end
	local gui = StudPop.ScreenGui("CoreLoopHud", 5)
	local chip = if rushOn then buildChip(gui) else nil
	local countdown = if rushOn then buildCountdown(gui) else nil
	-- The meter shares the Stud Pop HUD's ScreenGui settings so its positions use the same origin as the
	-- live CashPill and Rail (StudPopHud).
	local meterGui = StudPop.ScreenGui("CoreLoopMeter", 5)
	local meter = if CoreLoopFlags.Part("LuckyMeter") then buildMeter(meterGui) else nil
	local player = Players.LocalPlayer
	if meter then
		setMeter(meter, player:GetAttribute("LuckyMeter") or 0)
		player:GetAttributeChangedSignal("LuckyMeter"):Connect(function()
			if os.clock() >= meter.FullUntil then
				setMeter(meter, player:GetAttribute("LuckyMeter") or 0)
			end
		end)
		task.spawn(function()
			local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
			local remote = remotes and remotes:WaitForChild("CoreLoopEvent", 30)
			if remote and remote:IsA("RemoteEvent") then
				remote.OnClientEvent:Connect(function(payload)
					if type(payload) ~= "table" then
						return
					end
					if payload.kind == "Meter" then
						meterFloaty(meter, payload.gain or 0, payload.reason)
					elseif payload.kind == "LuckyFull" then
						meterFull(meter)
						StudPop.Toast(gui, "LUCKY STAR INCOMING!", "go")
					elseif payload.kind == "Toast" and type(payload.text) == "string" then
						StudPop.Toast(
							gui,
							payload.text,
							if type(payload.tone) == "string" then payload.tone else "go"
						)
					end
				end)
			end
		end)
	end
	local guiRoot = Instance.new("Frame")
	guiRoot.Name = "Origin"
	guiRoot.BackgroundTransparency = 1
	guiRoot.Size = UDim2.fromScale(1, 1)
	guiRoot.Parent = meterGui

	local lastSecond = -1
	local lastPillarUpdate = 0
	local bobStarted = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = Workspace:GetServerTimeNow()
		if meter then
			-- Track the live CashPill: under it, left edges aligned, gap 8 board px; scale with its height.
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			local pill = playerGui and playerGui:FindFirstChild("CashPill", true)
			if pill and pill:IsA("GuiObject") and pill.AbsoluteSize.Y > 0 then
				local hud = pill:FindFirstAncestorOfClass("ScreenGui")
				if
					hud
					and (
						meterGui.IgnoreGuiInset ~= hud.IgnoreGuiInset
						or meterGui.ScreenInsets ~= hud.ScreenInsets
					)
				then
					meterGui.IgnoreGuiInset = hud.IgnoreGuiInset
					meterGui.ScreenInsets = hud.ScreenInsets
				end
				local k = pill.AbsoluteSize.Y / Theme.px(34)
				meter.Scale.Scale = k
				local top = pill.AbsolutePosition.Y
					+ pill.AbsoluteSize.Y
					+ Theme.px(M.GapUnderCash) * k
				-- Board 1 puts the meter under the Cash pill; the live HUD has the left Rail there, so the
				-- meter starts just right of the Rail (logged deviation), at the board's vertical position.
				local left = pill.AbsolutePosition.X
				local rail = hud and hud:FindFirstChild("Rail")
				if rail and rail:IsA("GuiObject") and rail.Visible then
					if rail.AbsolutePosition.Y < top + Theme.px(M.Badge) * k then
						left = math.max(
							left,
							rail.AbsolutePosition.X + rail.AbsoluteSize.X + Theme.px(8)
						)
					end
				end
				meter.Root.Position = UDim2.fromOffset(
					left - guiRoot.AbsolutePosition.X,
					top - guiRoot.AbsolutePosition.Y
				)
				meter.Root.Visible = pill.Visible
			end
			local pulsing = meter.Shown >= M.PulseAt and os.clock() >= meter.FullUntil
			local wave = math.sin(os.clock() / M.PulseSeconds * 2 * math.pi)
			meter.Bar.Rotation = 0
			meter.Badge.Rotation = if pulsing then 8 * wave else 0
			local bump = if pulsing then 1 + (M.PulseScale - 1) * (0.5 + 0.5 * wave) else 1
			meter.Scale.Scale *= bump
		end
		if chip and countdown then
			local state = Workspace:GetAttribute("RushState")
			local startsAt = Workspace:GetAttribute("RushStartsAt")
			local endsAt = Workspace:GetAttribute("RushEndsAt")
			local mega = Workspace:GetAttribute("RushMega") == true
			local showChip, showCountdown = false, false
			if type(startsAt) == "number" and type(endsAt) == "number" then
				if state == "Warning" then
					local left = math.max(0, math.ceil(startsAt - t))
					if left <= CoreLoop.Rush.CountdownSeconds then
						showCountdown = true
						countdown.Digit.Text = tostring(math.max(1, left))
						countdown.SetRemaining((startsAt - t) / CoreLoop.Rush.CountdownSeconds)
						if left ~= lastSecond then
							lastSecond = left
							countdown.Scale.Scale = R.CountdownTickScale
							TweenService:Create(
								countdown.Scale,
								TweenInfo.new(R.CountdownTickSeconds, Enum.EasingStyle.Back),
								{ Scale = 1 }
							):Play()
							AudioCue.Play(
								Fx.L5_Cues.CL_RUSH_TICK,
								{ pitch = if left <= 3 then 1.122 else 1 }
							)
						end
					else
						showChip = true
						setGradient(chip.Fill, if mega then "Mega" else "Alert")
						chip.Root.Size = scaleSize(R.ChipSize)
						chip.Aspect.AspectRatio = R.ChipSize.X / R.ChipSize.Y
						chip.Label.TextSize = Theme.px(if mega then R.MegaLabelPx else R.LabelPx)
						chip.Label.Text = string.format(
							if mega then R.Copy.MegaWarning else R.Copy.Warning,
							left // 60,
							left % 60
						)
						chip.Strip.Visible = false
						chip.Subline.Visible = false
						-- Gentle bob (ambient; no button).
						local bob = math.sin((os.clock() - bobStarted) / R.BobSeconds * 2 * math.pi)
							* R.BobPx
						chip.Root.Position = UDim2.new(0.5, 0, 0, Theme.px(R.ChipTop + bob))
					end
				elseif state == "Rush" or state == "Mega" then
					showChip = true
					local left = math.max(0, math.ceil(endsAt - t))
					local size = if mega then R.MegaActiveSize else R.ActiveSize
					setGradient(chip.Fill, if mega then "Mega" else "Rush")
					chip.Root.Size = scaleSize(size)
					chip.Aspect.AspectRatio = size.X / size.Y
					chip.Root.Position = UDim2.new(0.5, 0, 0, Theme.px(R.ChipTop))
					chip.Label.TextSize =
						Theme.px(if mega then R.MegaActiveLabelPx else R.ActiveLabelPx)
					chip.Label.Text = string.format(
						if mega then R.Copy.MegaActive else R.Copy.Active,
						left // 60,
						left % 60
					)
					chip.Strip.Visible = true
					local length = if mega
						then CoreLoop.Rush.MegaSeconds
						else CoreLoop.Rush.RushSeconds
					chip.StripFill.Size =
						UDim2.fromScale(math.clamp((endsAt - t) / length, 0, 1), 1)
					chip.Subline.Visible = mega
				end
			end
			chip.Root.Visible = showChip
			countdown.Root.Visible = showCountdown
		end
		if starsOn and os.clock() - lastPillarUpdate >= 0.2 then
			lastPillarUpdate = os.clock()
			-- Pillars moved to CoreLoopFxController (full L3.2/L3.3 look behind the review gate).
			updateSavedTags(t)
		end
	end)
end

return Controller
