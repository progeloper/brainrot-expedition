--!strict
-- Client visuals for villager guards: a V4 box model over each invisible server root,
-- "?"/"!" bubbles, nametags (<= 40 studs), idle loops and give-up tantrums.
-- Pure presentation: the server owns every state. Started only when
-- FeatureFlags.VillagerGuardsEnabled is true.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)
local Roster = require(ReplicatedStorage.Shared.Config.VillagerRoster)
local Builder = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local OutfitSets = require(ReplicatedStorage.Shared.Config.VillagerOutfitSets)
local Kits = ReplicatedStorage.Shared.Config.VillagerKits
-- Guards on the one animated body (rig + animation brief v5, D.2); off unless the flag is on.
local AnimationPlayer = require(script.Parent.VillagerAnimationPlayer)

local player = Players.LocalPlayer
local Controller = {}

type View = {
	root: Model,
	model: Model,
	row: any,
	offsets: { [BasePart]: CFrame },
	hat: { BasePart },
	bubble: BillboardGui,
	bubbleText: TextLabel,
	shout: BillboardGui,
	shoutText: TextLabel,
	shoutToken: number,
	nametag: BillboardGui,
	state: string,
	stateAt: number,
	pose: CFrame,
	hatThrown: boolean,
	connections: { RBXScriptConnection },
	body: AnimationPlayer.BodyView?, -- set when the guard uses the animated body
}

local REGION_BUBBLE: { [string]: Color3 } = {
	REGION_FOREST = Color3.fromHex("#8DFF3A"),
	REGION_BEACH = Color3.fromHex("#2EE9FF"),
	REGION_SWAMP = Color3.fromHex("#14C79F"),
	REGION_JUNGLE = Color3.fromHex("#FFD447"),
	REGION_ARCTIC = Color3.fromHex("#7FE8FF"),
	REGION_VOLCANO = Color3.fromHex("#FF8A2A"),
	REGION_GLITCH = Color3.fromHex("#FF49E1"),
}

local rowsById: { [string]: any } = {}
for _, region in Roster do
	for _, row in region.villagers do
		rowsById[row.id] = row
	end
end

local views: { [Model]: View } = {}
local visualFolder: Folder? = nil
local started = false
local lodTimer = 0

local function detailTier(): string
	local tier = player:GetAttribute("WorldDetailTier")
	if tier == "Reduced" or tier == "Minimal" then
		return tier
	end
	if player:GetAttribute("VFXQuality") == "Low" then
		return "Reduced"
	end
	return "Full"
end

local function reducedMotion(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function template(row: any): Model?
	local assets = ReplicatedStorage:FindFirstChild("CodeAssets")
	local villagers = assets and assets:FindFirstChild("Villagers")
	local name = Builder.TemplateName(row.kit, row.variant, OutfitSets.Token(row))
	local found = villagers and villagers:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found:Clone()
	end
	-- Fallback: build from the same kit/outfit data the native template was installed from.
	local module = Kits:FindFirstChild(row.kit)
	if module and module:IsA("ModuleScript") then
		return Builder.Build(require(module) :: any, {}, row.variant, OutfitSets.ForRow(row))
	end
	return nil
end

-- "{name}" in a shout becomes the chased player's display name (Pappagallo Pazzo).
local function shoutText(row: any, targetUserId: any): string
	local text = row.shout or "!"
	if string.find(text, "{name}", 1, true) then
		local target = if type(targetUserId) == "number"
			then Players:GetPlayerByUserId(targetUserId)
			else nil
		local name = if target then string.upper(target.DisplayName) else "THIEF"
		text = string.gsub(text, "{name}", function()
			return name
		end)
	end
	return text
end

local function makeLabel(parent: Instance, text: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = size
	stroke.Color = Color3.fromRGB(8, 8, 10)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function buildView(root: Model): View?
	local id = root:GetAttribute("VillagerId")
	local row = if type(id) == "string" then rowsById[id] else nil
	if not row then
		return nil
	end
	local offsets: { [BasePart]: CFrame } = {}
	local hat: { BasePart } = {}
	local model: Model
	local head: Instance?
	local height: number
	local body: AnimationPlayer.BodyView? = nil
	-- Approved guard skin on the animated body; anything else keeps the old template.
	local skin = if AnimationPlayer.Available() then AnimationPlayer.SkinFor(row.id) else nil
	if skin then
		body = AnimationPlayer.Build(row, skin, visualFolder :: Folder)
		local built = (body :: AnimationPlayer.BodyView).model
		model = built
		head = (body :: AnimationPlayer.BodyView).head
		height = (body :: AnimationPlayer.BodyView).height
	else
		local found = template(row)
		if not found then
			return nil
		end
		model = found
		Builder.ApplyPalette(model, row.palette)
		model.Name = "VillagerVisual_" .. row.id
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local origin = model:GetPivot()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				offsets[part] = origin:ToObjectSpace(part.CFrame)
				if part:GetAttribute("Group") == "Hat" then
					table.insert(hat, part)
				end
			end
		end
		head = model:FindFirstChild("Head") or model:FindFirstChild("Body")
		height = Builder.Height(
			require(Kits:FindFirstChild(row.kit) :: ModuleScript) :: any,
			row.variant,
			OutfitSets.ForRow(row)
		)
	end
	-- Bubbles and the name tag ride the Head bone on the animated body (offset from y 3.65).
	local anchor: BasePart = if body
		then (body :: AnimationPlayer.BodyView).head
		else (model.PrimaryPart or head) :: BasePart
	local anchorY = if body then 3.65 else 0

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "VillagerBubble"
	bubble.Size = UDim2.fromOffset(64, 64)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, height + 1.6 - anchorY, 0)
	bubble.AlwaysOnTop = false
	bubble.MaxDistance = 220
	bubble.LightInfluence = 0
	bubble.Enabled = false
	local bubbleText = makeLabel(bubble, "?", 4)
	bubble.Adornee = anchor
	bubble.Parent = model

	-- Character shout under the "!" (shown for a moment on the wind-up).
	local shout = Instance.new("BillboardGui")
	shout.Name = "VillagerShout"
	shout.Size = UDim2.fromOffset(240, 30)
	shout.StudsOffsetWorldSpace = Vector3.new(0, height + 0.5 - anchorY, 0)
	shout.MaxDistance = 160
	shout.LightInfluence = 0
	shout.Enabled = false
	local shoutLabel = makeLabel(shout, "", 2.5)
	shoutLabel.TextColor3 = Color3.fromHex("#FFD447")
	shout.Adornee = anchor
	shout.Parent = model

	local nametag = Instance.new("BillboardGui")
	nametag.Name = "VillagerNametag"
	nametag.Size = UDim2.fromOffset(150, 22)
	nametag.StudsOffsetWorldSpace = Vector3.new(0, height + 0.5 - anchorY, 0)
	nametag.MaxDistance = Config.NametagDistance
	nametag.LightInfluence = 0
	makeLabel(nametag, row.name, 2)
	nametag.Adornee = anchor
	nametag.Parent = model

	model.Parent = visualFolder
	local view: View = {
		root = root,
		model = model,
		row = row,
		offsets = offsets,
		hat = hat,
		bubble = bubble,
		bubbleText = bubbleText,
		shout = shout,
		shoutText = shoutLabel,
		shoutToken = 0,
		nametag = nametag,
		state = "Idle",
		stateAt = 0,
		pose = root:GetPivot(),
		hatThrown = false,
		connections = {},
		body = body,
	}
	return view
end

local function popBubble(view: View, text: string, colour: Color3)
	view.bubbleText.Text = text
	view.bubbleText.TextColor3 = colour
	view.bubble.Enabled = true
	if reducedMotion() then
		view.bubble.Size = UDim2.fromOffset(64, 64)
		return
	end
	view.bubble.Size = UDim2.fromOffset(20, 20)
	TweenService
		:Create(view.bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = if text == "!" then UDim2.fromOffset(84, 84) else UDim2.fromOffset(64, 64),
		})
		:Play()
end

local function throwHat(view: View)
	if view.hatThrown or #view.hat == 0 or detailTier() ~= "Full" or reducedMotion() then
		return
	end
	view.hatThrown = true
	task.delay(Config.TantrumSeconds + 0.4, function()
		view.hatThrown = false
	end)
end

local function onState(view: View)
	local state = view.root:GetAttribute("State")
	local stateAt = view.root:GetAttribute("StateAt")
	if type(state) ~= "string" then
		return
	end
	view.state = state
	view.stateAt = if type(stateAt) == "number" then stateAt else Workspace:GetServerTimeNow()
	local regionColour = REGION_BUBBLE[view.root:GetAttribute("RegionId") :: any]
		or Color3.new(1, 1, 1)
	if state == "Suspicious" then
		popBubble(view, "?", regionColour)
	elseif state == "WindUp" or state == "Chase" then
		if view.bubbleText.Text ~= "!" or not view.bubble.Enabled then
			popBubble(view, "!", Color3.fromHex("#FFD447"))
			if state == "WindUp" then
				view.shoutToken += 1
				local token = view.shoutToken
				view.shoutText.Text = shoutText(view.row, view.root:GetAttribute("TargetUserId"))
				view.shout.Enabled = true
				view.nametag.Enabled = false
				task.delay(1.6, function()
					if view.shoutToken == token then
						view.shout.Enabled = false
						view.nametag.Enabled = true
					end
				end)
			end
			view.bubbleText.TextColor3 = Color3.fromHex("#FF3B30")
		end
	elseif state == "GiveUp" then
		view.bubble.Enabled = false
		if view.row.tantrum == "StompHatThrow" then
			throwHat(view)
		end
	else
		view.bubble.Enabled = false
	end
end

local function attach(root: Instance)
	if not root:IsA("Model") or views[root] then
		return
	end
	local view = buildView(root)
	if not view then
		return
	end
	views[root] = view
	table.insert(
		view.connections,
		root:GetAttributeChangedSignal("StateAt"):Connect(function()
			onState(view)
		end)
	)
	table.insert(
		view.connections,
		root:GetAttributeChangedSignal("State"):Connect(function()
			onState(view)
		end)
	)
	onState(view)
end

local function detach(root: Instance)
	local view = views[root :: Model]
	if not view then
		return
	end
	views[root :: Model] = nil
	for _, connection in view.connections do
		connection:Disconnect()
	end
	if view.body then
		AnimationPlayer.Destroy(view.body)
	else
		view.model:Destroy()
	end
end

-- Per-frame pose: smooth toward the 10 Hz server root, then add the state animation.
local function animate(view: View, dt: number, now: number, cameraPosition: Vector3)
	local target = view.root:GetPivot()
	view.pose = view.pose:Lerp(target, 1 - math.exp(-12 * dt))
	local distance = (view.pose.Position - cameraPosition).Magnitude
	local tier = detailTier()
	local calm = reducedMotion()
	if view.body then
		-- Animated body: the clips do the acting; only the Glitch flicker is added here.
		local pose = view.pose
		if view.row.flicker and tier == "Full" and not calm and math.random() < 0.035 then
			pose *= CFrame.new((math.random() - 0.5) * 0.6, 0, 0)
		end
		AnimationPlayer.Update(view.body, pose, dt, now, view.root)
		return
	end
	local elapsed = now - view.stateAt
	local lift, tilt, yaw, roll = 0, 0, 0, 0
	local state = view.state
	if state == "Idle" then
		if tier == "Full" and not calm and distance <= Config.IdleAnimationDistance then
			local phase = now * 2 + (#view.row.id % 7)
			if view.row.idle == "Sweep" then
				yaw = math.sin(phase) * 0.18
			elseif view.row.idle == "Knit" then
				tilt = math.sin(phase * 1.5) * 0.06
			else
				lift = math.abs(math.sin(phase * 1.4)) * 0.18
			end
		end
	elseif state == "Suspicious" then
		roll = if calm then 0 else math.sin(now * 3) * 0.12 -- curious head tilt
		lift = if calm then 0 else math.abs(math.sin(now * 8)) * 0.15
	elseif state == "WindUp" then
		-- Little hop on "!".
		local t = math.clamp(elapsed / Config.WindUpSeconds, 0, 1)
		lift = if calm then 0 else math.sin(t * math.pi) * 1.1
	elseif state == "Chase" then
		lift = if calm then 0 else math.abs(math.sin(now * 14)) * 0.35
		tilt = -0.18
	elseif state == "GiveUp" then
		local t = math.clamp(elapsed / Config.TantrumSeconds, 0, 1)
		if not calm and t < 1 then
			local tantrum = view.row.tantrum
			if tantrum == "StompHatThrow" then
				lift = math.abs(math.sin(elapsed * 18)) * 0.5
			elseif tantrum == "WhistleFlail" then
				roll = math.sin(elapsed * 26) * 0.25
				lift = math.abs(math.sin(elapsed * 12)) * 0.2
			else
				yaw = math.sin(elapsed * 30) * 0.3
				lift = math.abs(math.sin(elapsed * 10)) * 0.4
			end
		end
	elseif state == "Return" then
		lift = if calm then 0 else math.abs(math.sin(now * 7)) * 0.12
		tilt = 0.08 -- grumbling slouch
	end
	-- Glitch Zone villagers flicker: a rare one-frame sideways jump (Full detail only).
	local jitter = 0
	if view.row.flicker and tier == "Full" and not calm and math.random() < 0.035 then
		jitter = (math.random() - 0.5) * 0.6
	end
	local pose = view.pose * CFrame.new(jitter, lift, 0) * CFrame.Angles(tilt, yaw, roll)
	-- Hat flies up and comes back down during the Plodder tantrum.
	local hatOffset = CFrame.identity
	if view.hatThrown then
		local t = math.clamp(elapsed / Config.TantrumSeconds, 0, 1)
		hatOffset = CFrame.new(0, math.sin(t * math.pi) * 3.2, -math.sin(t * math.pi) * 0.8)
			* CFrame.Angles(t * 6.2, 0, 0)
	end
	local parts, cframes = {}, {}
	for part, offset in view.offsets do
		table.insert(parts, part)
		if view.hatThrown and part:GetAttribute("Group") == "Hat" then
			table.insert(cframes, pose * hatOffset * offset)
		else
			table.insert(cframes, pose * offset)
		end
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Controller.Start()
	if started then
		return
	end
	started = true
	local newFolder = Instance.new("Folder")
	newFolder.Name = "VillagerVisuals"
	newFolder.Parent = Workspace
	visualFolder = newFolder
	if AnimationPlayer.Available() then
		AnimationPlayer.Preload()
	end

	local function watch(folder: Instance)
		folder.ChildAdded:Connect(attach)
		folder.ChildRemoved:Connect(detach)
		for _, child in folder:GetChildren() do
			attach(child)
		end
	end
	task.spawn(function()
		local folder = Workspace:WaitForChild("Villagers", 30)
		if folder then
			watch(folder)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = Workspace:GetServerTimeNow()
		local cameraPosition = camera.CFrame.Position
		-- Animation LOD for the animated bodies, every 0.25 s (brief D.3).
		lodTimer += dt
		if lodTimer >= AnimationPlayer.LodSeconds then
			lodTimer = 0
			local entries = {}
			for root, view in views do
				if view.body then
					table.insert(
						entries,
						{ view = view.body, root = root, position = view.pose.Position }
					)
				end
			end
			if #entries > 0 then
				AnimationPlayer.RefreshLod(entries, camera)
			end
		end
		for root, view in views do
			if root.Parent == nil or root.PrimaryPart == nil then
				continue
			end
			-- Far, idle villagers are not animated (server sleeps them too).
			if view.state == "Idle" and (view.pose.Position - cameraPosition).Magnitude > 300 then
				continue
			end
			animate(view, dt, now, cameraPosition)
		end
	end)
end

-- For EscapeRingController's on-screen check.
function Controller.GetVisualPositions(): { Vector3 }
	local out = {}
	for _, view in views do
		table.insert(out, view.pose.Position)
	end
	return out
end

return Controller
