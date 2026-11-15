--!strict
-- Data status banner: a Plate pill at the top centre (below the HUD's top band) while the player's
-- data is loading, unavailable, or slow to save. Reads player attributes only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme) :: any
local Plate = require(ReplicatedStorage.Shared.UI.Plate) :: any

local P = Theme.Plate
local px = Theme.px

-- tint by status: neutral while loading, alert orange for a slow save, stop red when unavailable
local TINT = {
	Loading = Color3.fromHex("#F7F5FC"),
	Warning = Color3.fromHex("#FFD447"),
	Failed = Color3.fromHex("#FF6B7A"),
}
local TEXT_PX = 16

local Controller = {}

local player = Players.LocalPlayer
local connections: { RBXScriptConnection } = {}
local pill: Frame? = nil
local label: TextLabel? = nil
local accent: Frame? = nil
local guiOverride: Instance? = nil
local started = false

local function ensurePill(): Frame?
	if pill and pill.Parent then
		return pill
	end
	local playerGui = guiOverride or player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerDataStatusGui"
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = false
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- ink outline, #2B2D38 body, Builder Sans Bold; grows with its sentence
	local nextPill: Frame = Plate.frame(gui, "Status", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.WindowBody,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.025),
		Size = UDim2.fromOffset(px(120), px(36)),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px(P.Radius.Button))
	corner.Parent = nextPill
	local outline = Instance.new("UIStroke")
	outline.Color = P.Color.Ink
	outline.Thickness = px(P.Stroke.Outline)
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = nextPill
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, px(12))
	padding.PaddingRight = UDim.new(0, px(14))
	padding.Parent = nextPill
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, px(8))
	row.Parent = nextPill
	local nextAccent: Frame = Plate.frame(nextPill, "Tint", {
		BackgroundTransparency = 0,
		BackgroundColor3 = TINT.Loading,
		Size = UDim2.fromOffset(px(10), px(10)),
		LayoutOrder = 1,
		ZIndex = 2,
	})
	local dot = Instance.new("UICorner")
	dot.CornerRadius = UDim.new(0.5, 0)
	dot.Parent = nextAccent
	local dotOutline = Instance.new("UIStroke")
	dotOutline.Color = P.Color.Ink
	dotOutline.Thickness = px(2)
	dotOutline.Parent = nextAccent
	local nextLabel: TextLabel = Plate.Label(nextPill, "", {
		name = "Message",
		size = TEXT_PX,
		font = P.Font.Body,
		color = TINT.Loading,
		order = 2,
		z = 2,
	})
	nextLabel.TextScaled = false
	nextLabel.TextSize = px(TEXT_PX)
	nextLabel.AutomaticSize = Enum.AutomaticSize.X
	nextLabel.Size = UDim2.fromScale(0, 1)

	if not guiOverride then
		-- keep the banner below the HUD's top band (pills/chips/phone rail)
		local hud = require(script.Parent.Parent.UI.Screens.HudScreen) :: any
		task.spawn(function()
			while gui.Parent do
				local hudGui = hud.Gui()
				if hudGui and nextPill.Parent then
					local top = hudGui.AbsolutePosition.Y + hud.TopBand() - gui.AbsolutePosition.Y
					nextPill.Position = UDim2.new(0.5, 0, 0, math.max(8, top))
				end
				task.wait(1)
			end
		end)
	end
	pill, label, accent = nextPill, nextLabel, nextAccent
	return nextPill
end

local function statusMessage(): (string?, string)
	local status = player:GetAttribute("PlayerDataStatus")
	if status == "Loading" or status == nil then
		return "Loading your data…", "Loading"
	end
	if status == "Failed" then
		return "Your data session is unavailable. Please rejoin.", "Failed"
	end
	if player:GetAttribute("PlayerDataSaveWarning") == true then
		return "Saving is taking longer than usual.", "Warning"
	end
	return nil, "Loading"
end

local function update()
	local currentPill = ensurePill()
	if not currentPill or not label or not accent then
		return
	end
	local message, kind = statusMessage()
	currentPill.Visible = message ~= nil
	label.Text = message or ""
	label.TextColor3 = TINT[kind]
	accent.BackgroundColor3 = TINT[kind]
end

function Controller.Start(dependencies: any?)
	if started then
		return
	end
	started = true
	guiOverride = if dependencies then dependencies.PlayerGui else nil
	player = if dependencies and dependencies.Player then dependencies.Player else Players.LocalPlayer
	table.insert(connections, player:GetAttributeChangedSignal("PlayerDataStatus"):Connect(update))
	table.insert(connections, player:GetAttributeChangedSignal("PlayerDataSaveWarning"):Connect(update))
	table.insert(
		connections,
		player.ChildAdded:Connect(function(child)
			if child:IsA("PlayerGui") then
				update()
			end
		end)
	)
	update()
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if pill then
		local gui = pill:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			gui:Destroy()
		end
	end
	pill, label, accent = nil, nil, nil
	guiOverride = nil
	started = false
end

return Controller
