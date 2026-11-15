--!strict
-- Playtest Fixes Part F (server, presentation only):
--   * Kiosk_GemsStall is authored into MapArt.Services. While FeatureFlags.PlaytestFixesV1Enabled /
--     GemsStall is off it is moved out of the world at server start, so the game is exactly as before.
--   * With it on, the NEWS kiosk gets a read-only board (headline, one line, "Codes → Settings") from
--     Config.PlaytestFixes.NewsBoard. Its Passes & Gems prompt is client-side (PassesKiosk), which
--     re-points to the Gems stall under the same flag.
-- No remotes, no prompts, no server location gate (the Passes window never had one).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlaytestFlags = require(ReplicatedStorage.Shared.Config.PlaytestFixesFlags)
local Config = require(ReplicatedStorage.Shared.Config.PlaytestFixes)

local Stalls = {}
local started = false

local function services(): Instance?
	local map = Workspace:FindFirstChild("MapBlockout")
	local art = map and map:FindFirstChild("MapArt")
	return art and art:FindFirstChild("Services")
end

local function hideGemsStall(folder: Instance)
	local stall = folder:FindFirstChild(Config.GemsStall.ModelName)
	if not stall then
		return
	end
	local holder = ServerStorage:FindFirstChild("_PlaytestFixesHidden")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "_PlaytestFixesHidden"
		holder.Parent = ServerStorage
	end
	stall.Parent = holder
end

-- Pure-ish: the board's frame on the kiosk's customer front (pivot LookVector), at standing height.
function Stalls.BoardFrame(
	kioskPivot: CFrame,
	boxFrame: CFrame,
	boxSize: Vector3,
	floorY: number
): CFrame
	local look = Vector3.new(kioskPivot.LookVector.X, 0, kioskPivot.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local inBox = boxFrame:VectorToObjectSpace(look)
	local halfDepth = math.abs(inBox.X) * boxSize.X / 2 + math.abs(inBox.Z) * boxSize.Z / 2
	local centre = Vector3.new(
		boxFrame.Position.X,
		floorY + Config.NewsBoard.PanelCentreHeight,
		boxFrame.Position.Z
	) + look * (halfDepth + 0.15)
	-- The panel's Front face points at the customer.
	return CFrame.lookAt(centre, centre + look)
end

local function buildNewsBoard(kiosk: Model)
	if kiosk:FindFirstChild("PlaytestNewsBoard") then
		return
	end
	local board = Config.NewsBoard
	local box, size = kiosk:GetBoundingBox()
	local floorY = box.Position.Y - size.Y / 2
	local panel = Instance.new("Part")
	panel.Name = "PlaytestNewsBoard"
	panel.Size = Vector3.new(board.PanelSize.X, board.PanelSize.Y, 0.3)
	panel.CFrame = Stalls.BoardFrame(kiosk:GetPivot(), box, size, floorY)
	panel.Anchored = true
	panel.CanCollide, panel.CanQuery, panel.CanTouch = false, false, false
	panel.CastShadow = false
	panel.Color = Color3.fromHex("#1D2133")
	panel.Material = Enum.Material.SmoothPlastic
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NewsBoardText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = board.PixelsPerStud
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.04, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	local function line(
		order: number,
		text: string,
		height: number,
		colour: Color3,
		font: Enum.Font
	)
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. order
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(0.92, height)
		label.BackgroundTransparency = 1 -- nothing transparent sits in FRONT of the text; this is the label itself
		label.Text = text
		label.TextScaled = true
		label.TextWrapped = true
		label.Font = font
		label.TextColor3 = colour
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromHex("#0B0D16")
		label.Parent = gui
	end
	line(1, board.Headline, 0.32, Color3.fromHex("#FFE14A"), Enum.Font.LuckiestGuy)
	line(2, board.Line, 0.34, Color3.new(1, 1, 1), Enum.Font.FredokaOne)
	line(3, board.Footer, 0.18, Color3.fromHex("#2EE9FF"), Enum.Font.FredokaOne)
	panel.Parent = kiosk
end

function Stalls.Start()
	if started then
		return
	end
	started = true
	local folder = services()
	if not folder then
		return
	end
	if not PlaytestFlags.Part("GemsStall") then
		hideGemsStall(folder)
		return
	end
	local kiosk = folder:FindFirstChild(Config.GemsStall.NewsModelName)
	if kiosk and kiosk:IsA("Model") then
		buildNewsBoard(kiosk)
	end
end

return Stalls
