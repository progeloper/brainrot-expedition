--!strict
-- Escape Ring presentation for the chased player and their cart passengers only:
-- a pooled ground ring of Neon box segments, a HUD distance-to-safety arc, the
-- "ESCAPED!" moment, "BONK!" on a tag and the "SNEAKY!" popup. The server decides
-- everything; this only plays effects. Started only when VillagerGuardsEnabled is true.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local Rules = require(ReplicatedStorage.Shared.Utility.VillagerChaseRules)

local player = Players.LocalPlayer
local Controller = {}

local SEGMENTS = Config.RingSegments
local ARC_DOTS = 24
local FONT = Enum.Font.FredokaOne
local STROKE = Color3.fromRGB(8, 8, 10)

local started = false
local ringFolder: Folder? = nil
local segments: { BasePart } = {}
local gui: ScreenGui? = nil
local arcFrame: Frame? = nil
local arcDots: { Frame } = {}
local banner: TextLabel? = nil
local bonus: TextLabel? = nil
local active: any = nil -- { center, radius, colour, chaseId }
local tagged = false
local bannerToken = 0
local shakeUntil = 0
local groundParams = RaycastParams.new()

local function colourOf(hex: any): Color3
	if type(hex) == "string" then
		local ok, colour = pcall(Color3.fromHex, hex)
		if ok then
			return colour
		end
	end
	return Color3.new(1, 1, 1)
end

local function reducedMotion(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function lowDetail(): boolean
	local tier = player:GetAttribute("WorldDetailTier")
	return tier == "Reduced" or tier == "Minimal" or player:GetAttribute("VFXQuality") == "Low"
end

local function myCart(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local node: Instance? = seat
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("CartId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function focusPosition(): Vector3?
	local cart = myCart()
	if cart then
		return cart:GetPivot().Position
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function label(parent: Instance, name: string, text: string, stroke: number): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = FONT
	item.Text = text
	item.TextScaled = true
	item.TextColor3 = Color3.new(1, 1, 1)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	local outline = Instance.new("UIStroke")
	outline.Thickness = stroke
	outline.Color = STROKE
	outline.Parent = item
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = if stroke >= 3 then 72 else 34
	limit.Parent = item
	item.Parent = parent
	return item
end

local function ensureGui()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "EscapeRingHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 41
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Distance-to-safety arc: dots on an upper semicircle that light up as the cart nears the edge.
	local frame = Instance.new("Frame")
	frame.Name = "SafetyArc"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0.035)
	frame.Size = UDim2.fromOffset(180, 56)
	frame.Visible = false
	frame.Parent = screen
	arcFrame = frame
	for index = 1, ARC_DOTS do
		local angle = math.pi * (index - 1) / (ARC_DOTS - 1)
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. index
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(7, 7)
		dot.Position = UDim2.new(0.5, -math.cos(angle) * 84, 1, -math.sin(angle) * 48 - 4)
		dot.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
		dot.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = STROKE
		stroke.Parent = dot
		dot.Parent = frame
		table.insert(arcDots, dot)
	end
	local caption = label(frame, "Caption", "ESCAPE THE RING", 2)
	caption.Position = UDim2.new(0.5, 0, 1, 2)
	caption.Size = UDim2.fromOffset(170, 18)

	local title = label(screen, "Banner", "ESCAPED!", 3.5)
	title.Position = UDim2.fromScale(0.5, 0.22)
	title.Size = UDim2.fromScale(0.62, 0.13)
	title.Visible = false
	banner = title
	local sub = label(screen, "Bonus", "", 2.5)
	sub.Position = UDim2.fromScale(0.5, 0.33)
	sub.Size = UDim2.fromScale(0.5, 0.07)
	sub.TextColor3 = Color3.fromHex("#FFD447")
	sub.Visible = false
	bonus = sub
end

local function ensureRing()
	if ringFolder then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "EscapeRing"
	folder.Parent = Workspace
	ringFolder = folder
	for index = 1, SEGMENTS do
		local part = Instance.new("Part")
		part.Name = "RingSegment" .. index
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Transparency = 1
		part.Size = Vector3.new(1, 0.5, 1.4)
		part.Parent = folder
		table.insert(segments, part)
	end
	local include: { Instance } = { Workspace.Terrain }
	local map = Workspace:FindFirstChild("MapBlockout")
	if map then
		table.insert(include, map)
	end
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = include
end

local function placeRing()
	if not active then
		return
	end
	local center: Vector3 = active.center
	local radius: number = active.radius
	local chord = 2 * math.pi * radius / SEGMENTS
	local colour = colourOf(active.colour)
	for index, part in segments do
		local angle = (index - 0.5) / SEGMENTS * math.pi * 2
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local hit = Workspace:Raycast(
			Vector3.new(x, center.Y + 60, z),
			Vector3.new(0, -160, 0),
			groundParams
		)
		local y = if hit then hit.Position.Y else center.Y
		part.Size = Vector3.new(chord * 0.82, 0.5, 1.4)
		part.CFrame = CFrame.new(x, y + 0.35, z) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		part.Color = colour
		part.Transparency = 0.15
	end
	if arcFrame then
		arcFrame.Visible = true
	end
end

local function hideRing()
	for _, part in segments do
		part.Transparency = 1
	end
	if arcFrame then
		arcFrame.Visible = false
	end
end

local function showBanner(text: string, sub: string?, colour: Color3?, seconds: number)
	ensureGui()
	local title = banner :: TextLabel
	local line = bonus :: TextLabel
	bannerToken += 1
	local token = bannerToken
	title.Text = text
	title.TextColor3 = colour or Color3.new(1, 1, 1)
	title.Visible = true
	line.Text = sub or ""
	line.Visible = sub ~= nil and sub ~= ""
	if not reducedMotion() then
		title.Size = UDim2.fromScale(0.3, 0.06)
		TweenService
			:Create(title, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(0.62, 0.13),
			})
			:Play()
	end
	task.delay(seconds, function()
		if bannerToken == token then
			title.Visible = false
			line.Visible = false
		end
	end)
end

local function burst(position: Vector3, colour: Color3, count: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = 0.8
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(14, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = anchor
	anchor.Parent = Workspace
	emitter:Emit(count)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

local function fovPunch()
	if reducedMotion() then
		return
	end
	player:SetAttribute("EscapeFovPunch", 6)
	task.delay(0.3, function()
		player:SetAttribute("EscapeFovPunch", nil)
	end)
end

local function bonk()
	local cart = myCart()
	local position = if cart then cart:GetPivot().Position else focusPosition()
	if position then
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromOffset(150, 56)
		board.AlwaysOnTop = false
		board.LightInfluence = 0
		local text = label(board, "Bonk", "BONK!", 3)
		text.Position = UDim2.fromScale(0.5, 0.5)
		text.Size = UDim2.fromScale(1, 1)
		text.TextColor3 = Color3.fromHex("#FFD447")
		board.Parent = holder
		holder.Parent = Workspace
		task.delay(0.9, function()
			holder:Destroy()
		end)
	end
	if not reducedMotion() then
		shakeUntil = os.clock() + 0.3
	end
end

local function onEvent(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind == "ChaseStarted" or kind == "ChaseRecentred" then
		ensureGui()
		ensureRing()
		if kind == "ChaseStarted" then
			tagged = false
		end
		active = {
			center = payload.center,
			radius = payload.radius,
			colour = payload.colour,
			chaseId = payload.chaseId,
		}
		placeRing()
	elseif kind == "ChaseTag" then
		tagged = true
		bonk()
	elseif kind == "ChaseEnded" then
		local colour = colourOf(payload.colour)
		active = nil
		hideRing()
		local lines = {}
		if payload.clean then
			table.insert(lines, "CLEAN ESCAPE! ⭐")
		end
		if payload.closeCall and #lines < 2 then
			table.insert(lines, "CLOSE CALL!")
		end
		showBanner("ESCAPED!", table.concat(lines, "   "), nil, 2.2)
		fovPunch()
		local position = focusPosition()
		if position then
			burst(position, colour, if lowDetail() then 14 else 36)
		end
		Controller.EscapeCompleted:Fire(payload.clean == true, tagged)
	elseif kind == "Sneaky" then
		showBanner("SNEAKY!", nil, Color3.fromHex("#B9A6FF"), 1.4)
	end
end

local escapeEvent = Instance.new("BindableEvent")
Controller.EscapeCompleted = escapeEvent

function Controller.Start()
	if started then
		return
	end
	started = true
	ensureGui()
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		local remote = remotes and remotes:WaitForChild(RemoteNames.VillagerGuardEvent, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(onEvent)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if active then
			-- Gentle pulse + safety arc fill.
			local pulse = 0.15 + (math.sin(os.clock() * 4) + 1) * 0.12
			for _, part in segments do
				part.Transparency = pulse
			end
			local position = focusPosition()
			if position then
				local fraction =
					math.clamp(Rules.FlatDistance(position, active.center) / active.radius, 0, 1)
				local lit = math.floor(fraction * ARC_DOTS + 0.5)
				local colour = colourOf(active.colour)
				for index, dot in arcDots do
					dot.BackgroundColor3 = if index <= lit
						then colour
						else Color3.fromRGB(40, 40, 48)
				end
			end
		end
	end)
	RunService:BindToRenderStep("EscapeRingShake", Enum.RenderPriority.Camera.Value + 2, function()
		if os.clock() < shakeUntil then
			local camera = Workspace.CurrentCamera
			if camera then
				local strength = (shakeUntil - os.clock()) / 0.3 * 0.35
				camera.CFrame *= CFrame.new(
					(math.random() - 0.5) * strength,
					(math.random() - 0.5) * strength,
					0
				)
			end
		end
	end)
end

return Controller
