--!strict
-- Local first-session guidance: a "HUNT HERE" beacon at the Forest mouth, floor
-- chevrons along a client path from the player to it, and a screen-edge arrow
-- when the beacon is off-screen. Shown only before the first durable bank and only
-- while the player stands in the hub. Purely local presentation; owns no camera.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.FirstSessionVisuals)
local Rules = require(ReplicatedStorage.Shared.Utility.FirstSessionVisualRules)
local Hud = require(ReplicatedStorage.Shared.Config.PlaytestExact).Hud

local G = Config.Guide
local Controller = {}
local player = Players.LocalPlayer
local started = false
local folder: Folder? = nil
local chevronFolder: Folder? = nil
local beaconTop: BasePart? = nil
local arrowGui: ScreenGui? = nil
local arrow: Frame? = nil
local active = false
local pathOrigin: Vector3? = nil
local lastPathAt = -math.huge
local pathing = false
local chevrons: { BasePart } = {}

local function completed(): boolean
	local done = player:GetAttribute(G.CompletionAttribute)
	return type(done) == "number" and done > 0
end

local function shouldGuide(): boolean
	return not completed() and player:GetAttribute("Phase13RegionId") == G.HubRegionId
end

local beaconShown = true
local function setBeaconShown(value: boolean)
	if beaconShown == value or not folder then
		return
	end
	beaconShown = value
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Chevron" and d.Name ~= "BeaconTop" then
			d.LocalTransparencyModifier = if value then 0 else 1
		elseif d:IsA("PointLight") then
			d.Enabled = value
		end
	end
end

local function buildBeacon()
	local root = Instance.new("Folder")
	root.Name = "FirstSessionGuide"
	-- Navigation presentation: RegionVisibilityController must not cull it by region.
	root:SetAttribute("GlobalNavigationFacade", true)
	local base = G.Beacon
	local column = Instance.new("Part")
	column.Name = "BeaconColumn"
	column.Shape = Enum.PartType.Cylinder
	column.Size = Vector3.new(G.BeaconHeight, 3, 3)
	column.CFrame = CFrame.new(base.X, G.BeaconHeight / 2, base.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	column.Color = G.BeaconColour
	column.Material = Enum.Material.Neon
	column.Transparency = 0.25
	column.Anchored, column.CanCollide, column.CanQuery, column.CanTouch = true, false, false, false
	column.CastShadow = false
	column.Parent = root
	local ring = Instance.new("Part")
	ring.Name = "BeaconRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 16, 16)
	ring.CFrame = CFrame.new(base.X, 0.25, base.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = G.BeaconColour
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Parent = root
	local top = Instance.new("Part")
	top.Name = "BeaconTop"
	top.Size = Vector3.new(1, 1, 1)
	top.Transparency = 1
	top.CFrame = CFrame.new(base.X, G.BeaconHeight + 2, base.Z)
	top.Anchored, top.CanCollide, top.CanQuery, top.CanTouch = true, false, false, false
	top.Parent = root
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = G.BeaconColour, 32, 1.5, false
	light.Parent = ring
	local board = Instance.new("BillboardGui")
	board.Name = "BeaconLabel"
	board.Size = UDim2.fromOffset(190, 58)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	board.MaxDistance = 900
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.Enabled = false -- setActive owns it
	board.Adornee = top
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = G.Label
	title.TextColor3 = G.BeaconColour
	title.TextStrokeTransparency = 0.1
	title.Parent = board
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.Size = UDim2.fromScale(1, 0.38)
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.Text = G.SubLabel
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.1
	sub.Parent = board
	board.Parent = top
	local chevronsRoot = Instance.new("Folder")
	chevronsRoot.Name = "Chevrons"
	chevronsRoot.Parent = root
	root.Parent = Workspace
	folder, chevronFolder, beaconTop = root, chevronsRoot, top
end

local function buildArrow()
	local screen = Instance.new("ScreenGui")
	screen.Name = "FirstSessionGuideArrow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30
	screen.Enabled = false
	local frame = Instance.new("Frame")
	frame.Name = "Arrow"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(150, 40)
	frame.BackgroundColor3 = Hud.Background
	frame.BackgroundTransparency = Hud.Transparency
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = G.BeaconColour
	stroke.Thickness = 2
	stroke.Parent = frame
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromOffset(36, 40)
	glyph.Font = Enum.Font.FredokaOne
	glyph.TextSize = 26
	-- Plain ASCII: the HUD font has no arrow glyphs.
	glyph.Text = ">"
	glyph.TextColor3 = G.BeaconColour
	glyph.Parent = frame
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(34, 0)
	text.Size = UDim2.new(1, -40, 1, 0)
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 18
	text.Text = "Hunt: Forest"
	text.TextColor3 = Hud.Text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = frame
	frame.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	arrowGui, arrow = screen, frame
end

local function clearChevrons()
	for _, c in ipairs(chevrons) do
		c:Destroy()
	end
	table.clear(chevrons)
end

local function chevronAt(position: Vector3, direction: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = "Chevron"
	p.Size = Vector3.new(G.ChevronSize, 0.1, G.ChevronSize)
	p.CFrame = CFrame.lookAt(position, position + direction)
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 20
	surface.MaxDistance = 220
	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = Enum.Font.FredokaOne
	glyph.TextScaled = true
	glyph.Text = "▲"
	glyph.TextColor3 = G.BeaconColour
	glyph.TextStrokeTransparency = 0.4
	glyph.Parent = surface
	surface.Parent = p
	p.Parent = chevronFolder
	return p
end

local function rebuildPath(from: Vector3)
	if pathing then
		return
	end
	pathing = true
	lastPathAt = os.clock()
	pathOrigin = from
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})
		local ok = pcall(function()
			path:ComputeAsync(from, G.Beacon + Vector3.new(0, 3, 0))
		end)
		pathing = false
		if not ok or path.Status ~= Enum.PathStatus.Success or not active then
			return
		end
		clearChevrons()
		local waypoints = path:GetWaypoints()
		local carried = G.ChevronSpacing * 0.6
		for i = 2, #waypoints do
			local a, b = waypoints[i - 1].Position, waypoints[i].Position
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local length = flat.Magnitude
			if length > 1e-3 then
				local direction = flat.Unit
				local along = G.ChevronSpacing - carried
				while along <= length and #chevrons < G.ChevronLimit do
					local at = a + direction * along
					table.insert(chevrons, chevronAt(Vector3.new(at.X, 0.15, at.Z), direction))
					along += G.ChevronSpacing
				end
				carried = (carried + length) % G.ChevronSpacing
			end
		end
	end)
end

local function updateArrow(now: number)
	if not arrowGui or not arrow or not beaconTop then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera or not active then
		arrowGui.Enabled = false
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(beaconTop.Position)
	local viewport = camera.ViewportSize
	local visible = onScreen
		and point.Z > 0
		and point.X > 0
		and point.X < viewport.X
		and point.Y > 0
		and point.Y < viewport.Y
	if visible then
		arrowGui.Enabled = false
		return
	end
	local screen = Vector2.new(point.X, point.Y)
	if point.Z < 0 then
		-- Behind the camera: mirror through the centre so the arrow points the right way.
		screen = viewport - screen
	end
	local edge, angle = Rules.EdgePoint(screen, viewport, G.EdgeArrowMargin)
	arrow.Position = UDim2.fromOffset(edge.X, edge.Y)
	local glyph = arrow:FindFirstChild("Glyph") :: TextLabel?
	if glyph then
		glyph.Rotation = angle
	end
	arrow.BackgroundTransparency = Hud.Transparency + 0.1 * math.sin(now * 4)
	arrowGui.Enabled = true
end

local function setActive(value: boolean)
	if active == value then
		return
	end
	active = value
	-- The "HUNT HERE" label only makes sense from the hub side of the mouth.
	local label = folder and folder:FindFirstChild("BeaconLabel", true) :: BillboardGui?
	if label then
		label.Enabled = value
	end
	if not value then
		clearChevrons()
		pathOrigin = nil
		if arrowGui then
			arrowGui.Enabled = false
		end
	end
end

function Controller.Start(): boolean
	if started then
		return false
	end
	started = true
	buildBeacon()
	buildArrow()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		setBeaconShown(not completed())
		setActive(shouldGuide())
		if active then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local stale = pathOrigin == nil
					or (root.Position - pathOrigin).Magnitude > G.RepathDistance
					or now - lastPathAt > G.RepathSeconds and #chevrons == 0
				if stale then
					rebuildPath(root.Position)
				end
			end
			for index, chevron in ipairs(chevrons) do
				local surface = chevron:FindFirstChildOfClass("SurfaceGui")
				local glyph = surface and surface:FindFirstChildOfClass("TextLabel")
				if glyph then
					glyph.TextTransparency = 0.15
						+ 0.45 * (0.5 + 0.5 * math.sin(now * 5 - index * 0.6))
				end
			end
		end
		updateArrow(now)
	end)
	return true
end

return Controller
