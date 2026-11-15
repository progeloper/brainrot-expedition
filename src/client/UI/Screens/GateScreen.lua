--!nocheck
-- MenusV2 world gate window (replaces WorldProgressionGui.GatePanel / AccessNotice).
-- View only: WorldProgressionController keeps the summary, the two-step confirm and the
-- WorldProgressionRequest call. Every word shown comes from WorldProgressionPresentation.Build
-- (title, body, action, enabled) or from the server (notices).
--   Screen.open(model, handlers, anchor)  handlers = { onPrimary = fn, onClose = fn(instant) }
--   Screen.update(model)                  re-render in place (summary / confirm / pending changes)
--   Screen.close(instant)                 animated close + MenusV2.cleared("Gate")
--   Screen.toast(text, kind, seconds)     access notices ("good" | "alert" | "stop")
-- model = { title, body, action, enabled, confirming?, pending?, unlocked?, notice? }
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Plate, Theme = Common.Plate, Common.Theme
local P = Theme.Plate
local px = Theme.px

local WINDOW_ID = "Gate"
local TITLE_PX = 32
local TITLE_MIN_PX = 18
local LINE_PX = 15
local BUTTON_H = 46

local TOAST_COLOR = {
	good = P.Color.Cash,
	alert = Color3.fromHex("#FFD447"),
	stop = Color3.fromHex("#FF6B7A"),
}
local SHORTFALL = Color3.fromHex("#FF6B7A")
local NOTICE = Color3.fromHex("#FFD447")

local Screen = {}

local window = nil
local handlers = nil
local isOpen = false
local lines: ScrollingFrame? = nil
local buttonHolder: Frame? = nil
local buttonBag = nil
local titleSig, bodySig, buttonSig = nil, nil, nil
local lastToast: Instance? = nil

-- Long confirm titles ("Unlock Glitch Zone permanently?") shrink to stay left of the ✕.
local function fitTitle()
	local w = window
	local holder = w and w.Header:FindFirstChild("Title", true)
	if not holder then
		return
	end
	local labels = {}
	for _, child in holder:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextSize = px(TITLE_PX)
			table.insert(labels, child)
		end
	end
	local function fit()
		if window ~= w or not isOpen or #labels == 0 or not labels[1].Parent then
			return
		end
		local available = w.contentSize().X - px(100)
		local needed = labels[1].TextBounds.X * 1.05 -- the title idles up to 1.05x
		if available > 0 and needed > available then
			local size = math.max(px(TITLE_MIN_PX), math.floor(labels[1].TextSize * available / needed))
			for _, label in labels do
				label.TextSize = size
			end
		end
	end
	task.defer(fit)
	task.delay(0.5, fit) -- again once the pop-in scale has settled
end

local function lineColor(text: string): Color3
	if text == "OR" then
		return P.Color.Hint
	elseif string.sub(text, 1, 10) == "Shortfall:" then
		return SHORTFALL
	end
	return P.Color.White
end

local function addLine(text: string, color: Color3, order: number)
	local label = Plate.Label(lines, text, {
		size = LINE_PX,
		font = P.Font.Body,
		color = color,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		order = order,
		name = "Line",
	})
	label.TextScaled = false
	label.TextSize = px(LINE_PX)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -px(12), 0, 0)
	return label
end

local function renderBody(model)
	if not lines then
		return
	end
	for _, child in lines:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	for _, text in string.split(model.body or "", "\n\n") do
		if text ~= "" then
			order += 1
			addLine(text, lineColor(text), order)
		end
	end
	if type(model.notice) == "string" and model.notice ~= "" then
		addLine(model.notice, NOTICE, order + 1)
	end
end

local function renderButton(model)
	if not buttonHolder then
		return
	end
	if buttonBag then
		buttonBag.clean()
	end
	buttonHolder:ClearAllChildren()
	local bag = Plate.Bag()
	buttonBag = bag
	local size = UDim2.new(0.74, 0, 0, px(BUTTON_H))
	local position = UDim2.fromScale(0.5, 0.45)
	local anchor = Vector2.new(0.5, 0.5)
	if model.pending then
		-- "Saving your unlock…": nothing to press until the server answers
		Plate.Button(buttonHolder, { variant = "tabOff", text = model.action, size = size, position = position, anchor = anchor, bag = bag, name = "PrimaryAction" })
	elseif model.unlocked then
		Plate.StateWell(buttonHolder, model.action, { size = size, position = position, anchor = anchor, bag = bag })
	elseif model.enabled then
		Plate.Button(buttonHolder, {
			variant = "go",
			text = model.action,
			icon = if model.confirming then Theme.Icons.Cash else nil,
			primary = true,
			size = size,
			position = position,
			anchor = anchor,
			bag = bag,
			name = "PrimaryAction",
			onClick = function()
				if handlers then
					handlers.onPrimary()
				end
			end,
		})
	else
		Plate.LockedButton(buttonHolder, model.action, { size = size, position = position, anchor = anchor, bag = bag, name = "PrimaryAction" })
	end
end

local function build()
	local content = window.Content
	local buttonArea = px(BUTTON_H + 12)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Requirements"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -buttonArea)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = px(6)
	scroll.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	scroll.ZIndex = 5
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(4))
	list.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(4))
	pad.PaddingTop = UDim.new(0, px(2))
	pad.PaddingBottom = UDim.new(0, px(4))
	pad.Parent = scroll
	scroll.Parent = content
	lines = scroll
	buttonHolder = Plate.frame(content, "Action", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, buttonArea),
		ZIndex = 5,
	})
	-- the window clears its content bag on close; the button loops go with it
	window.bag.add(function()
		if buttonBag then
			buttonBag.clean()
			buttonBag = nil
		end
	end)
end

function Screen.update(model)
	if not isOpen or not window or type(model) ~= "table" then
		return
	end
	if model.title ~= titleSig then
		titleSig = model.title
		window.setTitle(model.title)
		fitTitle()
	end
	local nextBody = tostring(model.body) .. "\0" .. tostring(model.notice or "")
	if nextBody ~= bodySig then
		bodySig = nextBody
		renderBody(model)
	end
	local kind = if model.pending then "pending" elseif model.unlocked then "unlocked" elseif model.enabled then "go" else "locked"
	local nextButton = kind .. "\0" .. tostring(model.action) .. "\0" .. tostring(model.confirming == true)
	if nextButton ~= buttonSig then
		buttonSig = nextButton
		renderButton(model)
	end
end

function Screen.open(model, nextHandlers, anchor: ProximityPrompt?)
	handlers = nextHandlers
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Dialog",
			title = model.title,
			aspect = 1.75,
			widthScale = 0.72,
			heightScale = 0.84,
			maxSize = Vector2.new(575, 328),
			onClose = function()
				if handlers then
					handlers.onClose(false)
				end
			end,
		})
	end
	MenusV2.setOpen(WINDOW_ID, function(instant)
		if handlers then
			handlers.onClose(instant)
		end
	end, anchor)
	isOpen = true
	titleSig, bodySig, buttonSig = nil, nil, nil
	window.open()
	window.clearContent()
	build()
	Screen.update(model)
end

function Screen.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	lines, buttonHolder = nil, nil
	titleSig, bodySig, buttonSig = nil, nil, nil
	if window then
		window.close(instant) -- cleans the content bag (and the button loops)
	end
	MenusV2.cleared(WINDOW_ID)
end

function Screen.isOpen(): boolean
	return isOpen
end

-- Unlock confirmed by the server.
function Screen.celebrate()
	Juice.sound("Purchase")
	if isOpen and window and not Juice.reduced() then
		Juice.sparkles(window.Root, 8, P.Color.Cash)
	end
end

-- Access notices and unlock results. One at a time; long sentences shrink to stay on screen.
-- `seconds` is passed through for Plate.Toast (ignored until the kit supports a hold time).
function Screen.toast(text: any, kind: string?, seconds: number?)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	if lastToast and lastToast.Parent then
		lastToast:Destroy()
	end
	local gui = MenusV2.Gui()
	local pill = Plate.Toast(gui, text, { color = TOAST_COLOR[kind or "alert"] or TOAST_COLOR.alert, seconds = seconds })
	lastToast = pill
	local label = pill:FindFirstChildWhichIsA("TextLabel")
	if label then
		local available = gui.AbsoluteSize.X - px(56)
		local needed = label.TextBounds.X
		if available > 0 and needed > available then
			label.TextSize = math.max(px(Theme.Size.MinText), math.floor(label.TextSize * available / needed))
		end
	end
	return pill
end

return Screen
