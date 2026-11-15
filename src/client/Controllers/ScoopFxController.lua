--!strict
-- Drive-and-Hunt scoop feedback (Part D), client-side presentation only:
--   * pulsing ground rings + a down-arrow on sleeping wild brainrots near the driven cart;
--   * the "magnet pull": a local copy of the brainrot flies into its cargo slot, then a pop
--     and a "+1" beside the cargo HUD row;
--   * cargo full: a gold HOME arrow on the HUD plus the existing world pointer and beam.
-- The real brainrot and the cargo are server-owned and are never moved or changed here.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.DriveAndHunt).Scoop
local Flags = require(Shared.Config.DriveAndHuntFlags)
local BrainrotCatalog = require(Shared.Config.BrainrotCatalog)
local Palette = require(Shared.Config.VoxelCreaturePalette)
local Quality = require(Shared.Utility.ResolvedPresentationQuality)
local StudPop = require(Shared.UI.StudPop)
local Theme = require(Shared.UI.Theme)
local Juice = require(Shared.UI.Juice)

local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local WorldPointer = require(script.Parent.Parent.UI.Screens.WorldPointer)
local Hints = require(script.Parent.DriveAndHuntHints)

local FULL_ATTRIBUTE = "DriveAndHuntCargoFullAt"
local GOLD = Color3.fromHex("#FFE14A")
local INK = Color3.fromRGB(29, 33, 51)

type Ring = {
	parts: { Part },
	arrow: BillboardGui,
	arrowLabel: TextLabel,
	model: Model?,
	itemId: string?,
	proxy: Model?,
	frame: CFrame,
	colour: Color3,
	height: number,
	radius: number?,
	segments: number,
}
type Pending = { proxy: Model?, frame: CFrame, colour: Color3, expires: number }

local player = Players.LocalPlayer
local Controller = {}
local started = false
local connections: { RBXScriptConnection } = {}

local folder: Folder? = nil
local rings: { Ring } = {}
local ringByModel: { [Model]: Ring } = {}
local pending: { [string]: Pending } = {}
local nearest: { Model } = {}
local nearestDistance: { number } = {}
local scanElapsed, pulseElapsed = 0, 0
local flights = 0
local stats = { RingsPeak = 0, Flights = 0, Fallbacks = 0, PlusOnes = 0, FullSignals = 0 }

local hudRoot: Frame? = nil
local plusOne: TextLabel? = nil
local homeArrow: Frame? = nil
local homeGlyph: TextLabel? = nil
local homeUntil = 0
local stopHomePulse: (() -> ())? = nil
local popPart: Part? = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function lowQuality(): boolean
	return Quality.GetTier(player:GetAttribute("VFXQuality")) == "Low"
end

local function drivenCart(): Model?
	local cart = LocalCartState.GetCart()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not cart or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local seat = cart:FindFirstChild("DriverSeat")
	return if seat and humanoid.SeatPart == seat then cart else nil
end

local function rarityColour(model: Model): Color3
	local mutation = model:GetAttribute("MutationId")
	local hex = if type(mutation) == "string" then (Palette.MutationTag :: any)[mutation] else nil
	if not hex then
		local rarity = BrainrotCatalog.GetRarity(model:GetAttribute("BrainrotId"))
		local tier = if rarity then (Palette.RarityTiers :: any)[rarity] else nil
		hex = if tier then (tier.glow or tier.primary) else nil
	end
	local ok, colour = pcall(Color3.fromHex, if type(hex) == "string" then hex else "#FFFFFF")
	return if ok then colour else Color3.new(1, 1, 1)
end

local function effectsFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "DriveAndHuntScoopFx"
	created.Parent = Workspace
	folder = created
	return created
end

--------------------------------------------------------------------------------
-- Rings (D2): pooled, at most MaxRings x RingSegments Neon parts, drivers only
--------------------------------------------------------------------------------

local function newRing(): Ring
	local parts = table.create(Config.RingSegments)
	for index = 1, Config.RingSegments do
		local part = Instance.new("Part")
		part.Name = "RingSegment"
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new(1.3, 0.2, 0.45)
		parts[index] = part
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DriveAndHuntScoopArrow"
	billboard.Size = UDim2.fromScale(2.4, 2.4)
	billboard.LightInfluence = 0
	billboard.MaxDistance = Config.RingRadius * 2.5
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = utf8.char(0x25BC)
	glyph.FontFace = Theme.Font.Display
	glyph.TextScaled = true
	glyph.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = glyph
	billboard.Parent = player:WaitForChild("PlayerGui")
	return {
		parts = parts,
		arrow = billboard,
		arrowLabel = glyph,
		model = nil,
		itemId = nil,
		proxy = nil,
		frame = CFrame.identity,
		colour = Color3.new(1, 1, 1),
		height = 4,
		segments = Config.RingSegments,
	}
end

-- A local, inert copy made while the brainrot still exists, so it can fly after the server
-- has removed the real one. It carries no tags, ids or scripts.
local function makeProxy(model: Model): Model?
	local ok, copy = pcall(function()
		return model:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	for _, name in { "ItemId", "Captured", "BrainrotSleepUntil", "Phase10TargetKind" } do
		copy:SetAttribute(name, nil)
	end
	for _, tag in CollectionService:GetTags(copy) do
		CollectionService:RemoveTag(copy, tag)
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch = true, false, false, false
			item.CastShadow = false
		elseif
			item:IsA("LuaSourceContainer")
			or item:IsA("ProximityPrompt")
			or item:IsA("BillboardGui")
			or item:IsA("Sound")
			or item:IsA("Highlight")
			or item:IsA("ParticleEmitter")
		then
			item:Destroy()
			continue
		end
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
	end
	copy.Name = "DriveAndHuntScoopProxy"
	return copy
end

local function layRing(ring: Ring)
	local centre = ring.frame.Position
	local count = ring.segments
	local parent = effectsFolder()
	for index, part in ring.parts do
		if index > count then
			part.Parent = nil
			continue
		end
		local angle = (index - 1) / count * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
			* (ring.radius or Config.RingStuds)
		part.CFrame = CFrame.lookAt(
			centre + offset + Vector3.new(0, 0.2, 0),
			centre + Vector3.new(0, 0.2, 0)
		) * CFrame.Angles(0, math.pi / 2, 0)
		part.Color = ring.colour
		part.Parent = parent
	end
end

local function releaseRing(ring: Ring, keepProxy: boolean)
	local model, itemId = ring.model, ring.itemId
	if model then
		ringByModel[model] = nil
	end
	for _, part in ring.parts do
		part.Parent = nil
	end
	ring.arrow.Enabled, ring.arrow.Adornee = false, nil
	if keepProxy and itemId then
		-- The server removed it: the scoop message may still be on its way.
		pending[itemId] = {
			proxy = ring.proxy,
			frame = ring.frame,
			colour = ring.colour,
			expires = os.clock() + 1,
		}
	elseif ring.proxy then
		ring.proxy:Destroy()
	end
	ring.model, ring.itemId, ring.proxy = nil, nil, nil
end

local function assignRing(ring: Ring, model: Model, itemId: string)
	local body = model:FindFirstChild("Body", true)
	ring.model, ring.itemId = model, itemId
	ring.frame = model:GetPivot()
	ring.colour = rarityColour(model)
	ring.height = if body and body:IsA("BasePart") then body.Size.Y * 0.5 + 3 else 4
	-- Playtest Fixes size ladder: the ground ring grows with the brainrot (ratio to the shared height).
	local ratio = model:GetAttribute("PlaytestSizeRatio")
	ring.radius = Config.RingStuds * (if type(ratio) == "number" and ratio > 0 then ratio else 1)
	ring.segments = if lowQuality() then Config.RingSegmentsLow else Config.RingSegments
	ring.proxy = makeProxy(model)
	ringByModel[model] = ring
	layRing(ring)
	ring.arrowLabel.TextColor3 = ring.colour
	ring.arrow.Adornee = if body and body:IsA("BasePart") then body else model.PrimaryPart
	ring.arrow.StudsOffsetWorldSpace = Vector3.new(0, ring.height, 0)
	ring.arrow.Enabled = ring.arrow.Adornee ~= nil
	Hints.Show("Sleep", { world = ring.frame.Position })
end

local function releaseAll()
	for _, ring in rings do
		if ring.model then
			releaseRing(ring, false)
		end
	end
end

local function scanRings()
	local now = os.clock()
	for itemId, entry in pending do
		if entry.expires < now then
			if entry.proxy then
				entry.proxy:Destroy()
			end
			pending[itemId] = nil
		end
	end
	local cart = drivenCart()
	local runtime = Workspace:FindFirstChild("Runtime")
	local brainrots = if runtime then runtime:FindFirstChild("Brainrots") else nil
	if not cart or not brainrots then
		releaseAll()
		return
	end
	-- The MaxRings nearest sleeping wild brainrots (scratch arrays are reused).
	local origin = cart:GetPivot().Position
	local limit = Config.RingRadius * Config.RingRadius
	table.clear(nearest)
	table.clear(nearestDistance)
	for _, model in brainrots:GetChildren() do
		if
			not model:IsA("Model")
			or model:GetAttribute("Captured") ~= true
			or model:GetAttribute("Phase10Banked") == true
			or type(model:GetAttribute("ItemId")) ~= "string"
		then
			continue
		end
		local offset = model:GetPivot().Position - origin
		local distance = offset.X * offset.X + offset.Z * offset.Z
		if distance > limit then
			continue
		end
		local slot = #nearest + 1
		while slot > 1 and nearestDistance[slot - 1] > distance do
			slot -= 1
		end
		if slot <= Config.MaxRings then
			table.insert(nearest, slot, model)
			table.insert(nearestDistance, slot, distance)
			nearest[Config.MaxRings + 1], nearestDistance[Config.MaxRings + 1] = nil, nil
		end
	end
	for _, ring in rings do
		local model = ring.model
		if model then
			local gone = model.Parent ~= brainrots
			if gone or not table.find(nearest, model) then
				releaseRing(ring, gone)
			end
		end
	end
	local active = 0
	for _, model in nearest do
		if not ringByModel[model] then
			local free: Ring? = nil
			for _, ring in rings do
				if not ring.model then
					free = ring
					break
				end
			end
			if not free and #rings < Config.MaxRings then
				free = newRing()
				table.insert(rings, free)
			end
			if free then
				assignRing(free, model, model:GetAttribute("ItemId") :: string)
			end
		end
		active += 1
	end
	stats.RingsPeak = math.max(stats.RingsPeak, active)
end

local function pulseRings()
	local t = os.clock()
	for _, ring in rings do
		if not ring.model then
			continue
		end
		local count = ring.segments
		local head = (t * 1.4) % 1 * count
		for index = 1, count do
			local behind = (head - index) % count / count
			ring.parts[index].Transparency = 0.05 + 0.7 * behind
		end
		ring.arrow.StudsOffsetWorldSpace = Vector3.new(0, ring.height + 0.5 * math.sin(t * 5), 0)
	end
end

--------------------------------------------------------------------------------
-- HUD pieces: "+1" beside the cargo row, gold HOME arrow
--------------------------------------------------------------------------------

local function cargoRow(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("PlaytestExactHud")
	local row = hud and hud:FindFirstChild("Cargo", true)
	return if row and row:IsA("GuiObject") and row.Visible then row else nil
end

local function buildHud()
	if hudRoot then
		return
	end
	local screen = StudPop.ScreenGui("DriveAndHuntScoop", 91)
	local full = Instance.new("Frame")
	full.Name = "Root"
	full.BackgroundTransparency = 1
	full.Size = UDim2.fromScale(1, 1)
	full.Active = false
	full.Parent = screen

	local plus = Instance.new("TextLabel")
	plus.Name = "PlusOne"
	plus.BackgroundTransparency = 1
	plus.Size = UDim2.fromOffset(math.max(44, Theme.px(52)), math.max(30, Theme.px(36)))
	plus.Text = "+1"
	plus.FontFace = Theme.Font.Display
	plus.TextColor3 = Color3.fromHex("#7CFF6B")
	plus.TextScaled = true
	plus.Visible = false
	plus.Active = false
	plus.Parent = full
	local plusStroke = Instance.new("UIStroke")
	plusStroke.Thickness = 3
	plusStroke.Color = INK
	plusStroke.Parent = plus

	local home = Instance.new("Frame")
	home.Name = "HomeArrow"
	home.BackgroundTransparency = 1
	home.Size = UDim2.fromOffset(math.max(88, Theme.px(104)), math.max(30, Theme.px(36)))
	home.Visible = false
	home.Active = false
	home.Parent = full
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.BackgroundTransparency = 1
	word.Size = UDim2.fromScale(0.62, 1)
	word.Text = "HOME"
	word.FontFace = Theme.Font.Display
	word.TextColor3 = GOLD
	word.TextScaled = true
	word.Parent = home
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.82, 0.5)
	glyph.Size = UDim2.fromScale(0.34, 1)
	glyph.Text = utf8.char(0x25B2)
	glyph.FontFace = Theme.Font.Display
	glyph.TextColor3 = GOLD
	glyph.TextScaled = true
	glyph.Parent = home
	for _, item in { word, glyph } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = INK
		stroke.Parent = item
	end
	hudRoot, plusOne, homeArrow, homeGlyph = full, plus, home, glyph
end

-- Offset inside this gui's root for an element `width` wide placed beside the cargo row:
-- to its right when there is room, otherwise to its left (the row sits at the screen edge).
local function besideCargo(width: number, extraY: number): UDim2
	local full = hudRoot :: Frame
	local row = cargoRow()
	if row then
		local at = row.AbsolutePosition - full.AbsolutePosition
		local right = at.X + row.AbsoluteSize.X + 8
		local x = if right + width <= full.AbsoluteSize.X then right else at.X - 8 - width
		return UDim2.fromOffset(math.max(x, 8), at.Y + extraY)
	end
	return UDim2.new(0, 16, 0.3, extraY)
end

local function showPlusOne()
	buildHud()
	local plus = plusOne :: TextLabel
	stats.PlusOnes += 1
	plus.Position = besideCargo(plus.AbsoluteSize.X, -4)
	plus.TextTransparency = 0
	local stroke = plus:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	plus.Visible = true
	Juice.pop(plus, 1.5)
	local serial = stats.PlusOnes
	task.delay(Config.PlusOneSeconds, function()
		if serial == stats.PlusOnes then
			plus.Visible = false
		end
	end)
end

local function showCargoFull()
	buildHud()
	stats.FullSignals += 1
	homeUntil = os.clock() + Config.FullSeconds
	local home = homeArrow :: Frame
	home.Position = besideCargo(home.AbsoluteSize.X, 0)
	if not home.Visible then
		home.Visible = true
		stopHomePulse = Juice.breathe(home)
	end
	-- The existing gold world arrow and beam, pointed at the player's own base.
	local base = WorldPointer.ownBase()
	if base then
		WorldPointer.show(base, Config.FullSeconds, "HOME")
	end
end

local function updateHome()
	local home, glyph = homeArrow, homeGlyph
	if not home or not glyph or not home.Visible then
		return
	end
	if os.clock() >= homeUntil then
		home.Visible = false
		if stopHomePulse then
			stopHomePulse()
			stopHomePulse = nil
		end
		return
	end
	local camera = Workspace.CurrentCamera
	local base = WorldPointer.ownBase()
	local character = player.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not camera or not base or not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	-- Screen-relative bearing: 0 = straight ahead of the camera, clockwise positive.
	local toBase = camera.CFrame:VectorToObjectSpace(base:GetPivot().Position - rootPart.Position)
	glyph.Rotation = math.deg(math.atan2(toBase.X, -toBase.Z))
end

--------------------------------------------------------------------------------
-- Magnet pull (D3)
--------------------------------------------------------------------------------

local function slotPosition(cart: Model, itemId: string): Vector3
	local visuals = cart:FindFirstChild("CargoVisuals")
	if visuals then
		for _, item in visuals:GetChildren() do
			if item:IsA("Model") and item:GetAttribute("ItemId") == itemId then
				return item:GetPivot().Position
			end
		end
	end
	local slots = cart:FindFirstChild("CargoSlots")
	if slots then
		for _, slot in slots:GetChildren() do
			if slot:IsA("BasePart") and slot:GetAttribute("CargoItemId") == itemId then
				return slot.Position
			end
		end
	end
	return cart:GetPivot().Position + Vector3.new(0, 3, 0)
end

local function popAt(position: Vector3, colour: Color3)
	local part = popPart
	if not part then
		part = Instance.new("Part")
		part.Name = "ScoopPop"
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.CastShadow = false
		popPart = part
	end
	part.Color = colour
	part.Size = Vector3.one * 1.2
	part.Transparency = 0.15
	part.Position = position
	part.Parent = effectsFolder()
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 5, Transparency = 1 }
	)
	tween.Completed:Once(function()
		if part.Transparency >= 0.99 then
			part.Parent = nil
		end
	end)
	tween:Play()
end

local function finishScoop(cart: Model?, itemId: string, colour: Color3)
	if cart and cart.Parent then
		popAt(slotPosition(cart, itemId), colour)
	end
	showPlusOne()
	-- No sound here: AudioController already plays the S6 load cue for every own cargo load
	-- (scoops included). Playing it again doubled the sound.
	Hints.Show("Scoop")
	Hints.MarkDone("Sleep") -- they have driven over one: no need to tell them to
end

-- Called for the driver's own drive-by scoop (server "Scoop" effect message).
function Controller.OnScoop(itemId: string)
	if not started then
		return
	end
	local cart = LocalCartState.GetCart()
	local proxy: Model?, from: CFrame?, colour = nil, nil, Color3.new(1, 1, 1)
	for _, ring in rings do
		if ring.itemId == itemId then
			proxy, from, colour = ring.proxy, ring.frame, ring.colour
			ring.proxy = nil
			releaseRing(ring, false)
			break
		end
	end
	local waiting = pending[itemId]
	if waiting then
		pending[itemId] = nil
		if not proxy then
			proxy, from, colour = waiting.proxy, waiting.frame, waiting.colour
		elseif waiting.proxy then
			waiting.proxy:Destroy()
		end
	end
	if not proxy or not from or not cart or Juice.reduced() then
		if proxy then
			proxy:Destroy()
		end
		stats.Fallbacks += 1
		finishScoop(cart, itemId, colour)
		return
	end
	stats.Flights += 1
	flights += 1
	local start: CFrame = from
	local startScale = proxy:GetScale()
	local scaled = not lowQuality()
	local began = os.clock()
	proxy:PivotTo(start)
	proxy.Parent = effectsFolder()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - began) / Config.MagnetSeconds, 0, 1)
		if alpha >= 1 or not cart.Parent or not proxy.Parent then
			connection:Disconnect()
			proxy:Destroy()
			flights -= 1
			finishScoop(cart, itemId, colour)
			return
		end
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local target = slotPosition(cart, itemId)
		local position = start.Position:Lerp(target, eased)
			+ Vector3.new(0, Config.MagnetArcHeight * math.sin(math.pi * alpha), 0)
		if scaled then
			proxy:ScaleTo(startScale * (1 + (Config.MagnetEndScale - 1) * alpha))
		end
		proxy:PivotTo(start.Rotation + position)
	end)
end

--------------------------------------------------------------------------------

local function step(dt: number)
	scanElapsed += dt
	pulseElapsed += dt
	if scanElapsed >= 1 / Config.RingScanHz then
		scanElapsed = 0
		scanRings()
	end
	if pulseElapsed >= 1 / Config.RingPulseHz then
		pulseElapsed = 0
		pulseRings()
		updateHome()
	end
end

function Controller.Start()
	if started or not Flags.Part("ScoopFx") then
		return
	end
	started = true
	table.insert(connections, RunService.Heartbeat:Connect(step))
	table.insert(
		connections,
		player:GetAttributeChangedSignal(FULL_ATTRIBUTE):Connect(function()
			if player:GetAttribute(FULL_ATTRIBUTE) ~= nil and drivenCart() then
				showCargoFull()
			end
		end)
	)
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	releaseAll()
	for itemId, entry in pending do
		if entry.proxy then
			entry.proxy:Destroy()
		end
		pending[itemId] = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	started = false
end

function Controller.GetDiagnostics(): any
	local active, segments = 0, 0
	for _, ring in rings do
		if ring.model then
			active += 1
			segments += ring.segments
		end
	end
	local result = table.clone(stats) :: any
	result.RingsPooled, result.RingsActive, result.SegmentsActive = #rings, active, segments
	result.FlightsActive = flights
	result.HomeShown = homeArrow ~= nil and homeArrow.Visible
	return result
end

return Controller
