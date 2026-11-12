--!strict
-- Drive-and-Hunt first-time hints (Part E). One Stud Pop toast at a time, 3 s each, queued,
-- never stacked, and nothing here takes input. Each hint shows once per session: the game has
-- no onboarding storage and this feature adds no profile field, so "seen" lives in a local
-- player attribute and resets when the player rejoins.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.DriveAndHunt).HintToast
local Flags = require(Shared.Config.DriveAndHuntFlags)
local StudPop = require(Shared.UI.StudPop)
local Theme = require(Shared.UI.Theme)
local Juice = require(Shared.UI.Juice)

export type Target = {
	gui: GuiObject?, -- point at this control (toast sits to its left)
	world: Vector3?, -- or at this place in the world (toast sits above it)
}

local SEEN_ATTRIBUTE = "DriveAndHuntHintsSeen"
local ARROW_COLOR = Color3.fromHex("#FFE14A")

local player = Players.LocalPlayer
local Hints = {}

local seen: { [string]: boolean } = {}
local queue: { { key: string, target: Target? } } = {}
local running = false
local shownCount = 0
local maxOnScreen = 0

local root: Frame? = nil
local toast: Frame? = nil
local label: TextLabel? = nil
local arrow: TextLabel? = nil

local function build()
	if root then
		return
	end
	local screen = StudPop.ScreenGui("DriveAndHuntHints", 7)
	local full = Instance.new("Frame")
	full.Name = "Root"
	full.BackgroundTransparency = 1
	full.Size = UDim2.fromScale(1, 1)
	full.Active = false
	full.Parent = screen

	local frame = Instance.new("Frame")
	frame.Name = "Hint"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(math.max(220, Theme.px(260)), math.max(44, Theme.px(52)))
	frame.Visible = false
	frame.Active = false
	frame.ZIndex = 5
	frame.Parent = full
	local face = StudPop.Surface(frame, "info")
	face.Active = false
	face.Parent = frame
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.9, 0.7)
	text.FontFace = Theme.Font.Display
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.ZIndex = 5
	text.Active = false
	text.Parent = face
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(29, 33, 51)
	stroke.Parent = text

	local pointer = Instance.new("TextLabel")
	pointer.Name = "Arrow"
	pointer.BackgroundTransparency = 1
	pointer.Size = UDim2.fromOffset(math.max(28, Theme.px(34)), math.max(28, Theme.px(34)))
	pointer.FontFace = Theme.Font.Display
	pointer.TextColor3 = ARROW_COLOR
	pointer.TextScaled = true
	pointer.Visible = false
	pointer.Active = false
	pointer.ZIndex = 6
	pointer.Parent = full
	local pointerStroke = Instance.new("UIStroke")
	pointerStroke.Thickness = 3
	pointerStroke.Color = Color3.fromRGB(29, 33, 51)
	pointerStroke.Parent = pointer

	root, toast, label, arrow = full, frame, text, pointer
end

local function visible(object: GuiObject?): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

-- Places the toast and its arrow. Positions are worked out against this gui's own root, so
-- they hold whatever insets the target's ScreenGui uses.
local function place(target: Target?)
	local full, frame, pointer = root :: Frame, toast :: Frame, arrow :: TextLabel
	local origin = full.AbsolutePosition
	local size = frame.AbsoluteSize
	local arrowSize = pointer.AbsoluteSize
	local gap = 6
	local control = if target then target.gui else nil
	if control and visible(control) then
		local at = control.AbsolutePosition - origin
		local midY = at.Y + control.AbsoluteSize.Y * 0.5
		pointer.Text = utf8.char(0x25B6)
		pointer.Position = UDim2.fromOffset(at.X - gap - arrowSize.X, midY - arrowSize.Y * 0.5)
		frame.Position =
			UDim2.fromOffset(at.X - gap * 2 - arrowSize.X - size.X, midY - size.Y * 0.5)
		pointer.Visible = true
		return
	end
	local camera = Workspace.CurrentCamera
	local world = if target then target.world else nil
	if camera and world then
		local point, onScreen = camera:WorldToViewportPoint(world)
		if onScreen then
			local inset = GuiService:GetGuiInset()
			local x = point.X - inset.X - origin.X
			local y = point.Y - inset.Y - origin.Y
			local top = math.max(y - gap * 2 - arrowSize.Y - size.Y, 8)
			x = math.clamp(x, size.X * 0.5 + 8, full.AbsoluteSize.X - size.X * 0.5 - 8)
			pointer.Text = utf8.char(0x25BC)
			pointer.Position = UDim2.fromOffset(x - arrowSize.X * 0.5, top + size.Y + gap)
			frame.Position = UDim2.fromOffset(x - size.X * 0.5, top)
			pointer.Visible = true
			return
		end
	end
	pointer.Visible = false
	frame.Position =
		UDim2.fromOffset((full.AbsoluteSize.X - size.X) * 0.5, full.AbsoluteSize.Y * 0.24)
end

local function run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local entry = table.remove(queue, 1) :: { key: string, target: Target? }
			build()
			local frame, text, pointer = toast :: Frame, label :: TextLabel, arrow :: TextLabel
			text.Text = (Config.Text :: any)[entry.key] or entry.key
			place(entry.target)
			frame.Visible = true
			shownCount += 1
			maxOnScreen = math.max(maxOnScreen, 1)
			Juice.pop(frame)
			local stopBob = if pointer.Visible then Juice.bob(pointer) else nil
			task.wait(Config.Seconds)
			if stopBob then
				stopBob()
			end
			frame.Visible, pointer.Visible = false, false
			task.wait(0.15)
		end
		running = false
	end)
end

-- Queues a hint the first time its key is seen this session. Returns whether it was queued.
function Hints.Show(key: string, target: Target?): boolean
	if not Flags.Part("Hints") or seen[key] or (Config.Text :: any)[key] == nil then
		return false
	end
	if #queue >= Config.MaxQueued then
		return false -- not marked seen: it gets another chance later
	end
	seen[key] = true
	local keys = {}
	for name in seen do
		table.insert(keys, name)
	end
	table.sort(keys)
	player:SetAttribute(SEEN_ATTRIBUTE, table.concat(keys, ","))
	table.insert(queue, { key = key, target = target })
	run()
	return true
end

-- The player has already done what this hint teaches: never show it this session.
function Hints.MarkDone(key: string)
	if not seen[key] then
		seen[key] = true
		for index = #queue, 1, -1 do
			if queue[index].key == key then
				table.remove(queue, index)
			end
		end
	end
end

function Hints.Seen(key: string): boolean
	return seen[key] == true
end

function Hints.GetDiagnostics(): any
	return {
		Shown = shownCount,
		Queued = #queue,
		OnScreen = if toast and toast.Visible then 1 else 0,
		MaxOnScreen = maxOnScreen,
		Seen = player:GetAttribute(SEEN_ATTRIBUTE),
	}
end

return table.freeze(Hints)
