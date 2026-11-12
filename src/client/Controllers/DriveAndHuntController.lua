--!strict
-- Drive-and-Hunt client (Parts A and B): the HOP OUT / CART / LOAD & GO switch button, the
-- jump block while driving, and the launch/call effects. It also starts the scoop feedback
-- (Part D) and raises the first-time hints (Part E). Presentation and requests only:
-- the server decides seating, cart placement and loading (DriveAndHuntService).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.DriveAndHunt)
local Flags = require(Shared.Config.DriveAndHuntFlags)
local CartFlairStyles = require(Shared.Config.CartFlairStyles)
local RemoteNames = require(Shared.Constants.RemoteNames)
local Rules = require(Shared.Utility.DriveAndHuntRules)
local Quality = require(Shared.Utility.ResolvedPresentationQuality)
local StudPop = require(Shared.UI.StudPop)
local Theme = require(Shared.UI.Theme)
local Juice = require(Shared.UI.Juice)

local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)
local AutoLock = require(script.Parent.AutoLockController)
local Hints = require(script.Parent.DriveAndHuntHints)
local ScoopFx = require(script.Parent.ScoopFxController)

local SWITCH_ACTION = "DriveAndHuntSwitch"
local JUMP_SINK = "DriveAndHuntJumpSink"
local BUSY_ATTRIBUTES = {
	"Phase13CinematicActive",
	"Phase13ConsentDialogOpen",
	"Phase13CompareDialogOpen",
}
local HIDE_ATTRIBUTES = { "MenusV2Open", "Phase13ShopOpen", "ChariotTeamMenuOpen" }

local player = Players.LocalPlayer
local Controller = {}
local started = false
local connections: { RBXScriptConnection } = {}
local requestRemote: RemoteEvent? = nil

local gui: ScreenGui? = nil
local button: any = nil
local holder: Frame? = nil
local scale: UIScale? = nil
local ring: Frame? = nil
local ringGradient: UIGradient? = nil
local ringLabel: TextLabel? = nil
local shownState: string? = nil
local shownEnabled: boolean? = nil
local current: Rules.SwitchState? = nil
local seatedAt = -math.huge
local wasDriving = false
local jumpBlocked = false
local lastBusy: boolean? = nil
local elapsed = 0
local pulseToken = 0
local carryPulse: (() -> ())? = nil
local keyCap: TextLabel? = nil
local lastBystanderPuffAt = -math.huge

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function humanoidOf(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function isDriving(): boolean
	local cart = LocalCartState.GetCart()
	local humanoid = humanoidOf()
	if not cart or not humanoid then
		return false
	end
	local seat = cart:FindFirstChild("DriverSeat")
	return seat ~= nil and humanoid.SeatPart == seat
end

local function anyAttribute(names: { string }): boolean
	for _, name in names do
		-- Some menu attributes hold the open window's name (MenusV2Open = "DailyGift"), not true.
		local value = player:GetAttribute(name)
		if value ~= nil and value ~= false then
			return true
		end
	end
	return false
end

local function isDazed(): boolean
	local deadline = player:GetAttribute("Phase10DazeEnd")
	return type(deadline) == "number" and deadline > Workspace:GetServerTimeNow()
end

local function tagSlowed(cart: Model?): boolean
	local slowUntil = cart and cart:GetAttribute("VillagerSlowUntil")
	return type(slowUntil) == "number" and slowUntil > Workspace:GetServerTimeNow()
end

local function cooldownRemaining(): number
	local readyAt = player:GetAttribute("DriveAndHuntCallReadyAt")
	return if type(readyAt) == "number"
		then math.max(0, readyAt - Workspace:GetServerTimeNow())
		else 0
end

local function compute(): Rules.SwitchState
	local cart = LocalCartState.GetCart()
	local humanoid = humanoidOf()
	local busy = anyAttribute(BUSY_ATTRIBUTES)
	return Rules.SwitchState({
		driving = isDriving(),
		carrying = player:GetAttribute("CarriedItemId") ~= nil,
		allowed = humanoid ~= nil
			and humanoid.Health > 0
			and not busy
			and not isDazed()
			and not tagSlowed(cart),
		cooldownRemaining = cooldownRemaining(),
		hasCart = cart ~= nil,
	})
end

--------------------------------------------------------------------------------
-- Jump block while driving (B2): HOP OUT is the only way out
--------------------------------------------------------------------------------

local function touchJumpButton(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
end

local function setJumpBlocked(blocked: boolean)
	if jumpBlocked == blocked then
		if blocked then
			-- The default touch controls re-show their jump button; keep it hidden while driving.
			local jump = touchJumpButton()
			if jump and jump.Visible then
				jump.Visible = false
			end
		end
		return
	end
	jumpBlocked = blocked
	local humanoid = humanoidOf()
	if blocked then
		-- CartInputController binds nothing to Space/jump, so sinking it removes no cart control.
		ContextActionService:BindActionAtPriority(JUMP_SINK, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 50, Enum.PlayerActions.CharacterJump)
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	else
		ContextActionService:UnbindAction(JUMP_SINK)
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		local jump = touchJumpButton()
		if jump then
			jump.Visible = true
		end
	end
end

--------------------------------------------------------------------------------
-- Switch button (B1)
--------------------------------------------------------------------------------

local LABELS = {
	HopOut = Config.Labels.Driving,
	Cart = Config.Labels.OnFoot,
	LoadAndGo = Config.Labels.Carrying,
}
local VARIANTS = { HopOut = "stop", Cart = "info", LoadAndGo = "go" }

local function pulse(times: number?)
	local target = scale
	if not target then
		return
	end
	pulseToken += 1
	local token = pulseToken
	task.spawn(function()
		for _ = 1, times or 2 do
			if pulseToken ~= token then
				return
			end
			TweenService:Create(
				target,
				TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1.18 }
			):Play()
			task.wait(0.16)
			TweenService:Create(
				target,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
			task.wait(0.22)
		end
	end)
end

local function request()
	local remote, state = requestRemote, current
	if not remote or not state or not state.enabled or not state.action then
		if state and not state.enabled and holder then
			Juice.shake(holder, Theme.px(4), 0.18)
		end
		return
	end
	if state.action == "HopOut" then
		-- A double tap must not bounce the player out the moment they are seated.
		if os.clock() - seatedAt < Config.HopOut.SeatedGraceSeconds then
			return
		end
		-- The server lands the player on the side of the cart nearest the locked brainrot.
		remote:FireServer("HopOut", { target = AutoLock.GetLockModel() })
		Hints.MarkDone("HopOut")
	else
		remote:FireServer(state.action)
		if state.action == "LoadAndGo" then
			Hints.MarkDone("LoadAndGo")
		end
	end
end

local function buildButton()
	local screen = StudPop.ScreenGui("DriveAndHunt", 6)
	gui = screen
	local width, height = math.max(88, Theme.px(112)), math.max(88, Theme.px(88))
	local frame = Instance.new("Frame")
	frame.Name = "SwitchButton"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(1, 1)
	-- Fixed spot above the right-hand action cluster; FIRE sits at bottom -202..-138.
	frame.Position = UDim2.new(1, -Theme.px(16), 1, -214)
	frame.Size = UDim2.fromOffset(width, height)
	frame.Parent = screen
	holder = frame
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = frame
	scale = uiScale

	button = StudPop.Button(frame, {
		variant = "info",
		text = Config.Labels.OnFoot,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		onClick = request,
	})
	-- Stud Pop buttons default to a wide 3:1 plate; this one is a chunky thumb target (>= 88 px
	-- both ways) whose two-word labels wrap onto two lines.
	local aspect = button.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect.AspectRatio = width / height
	end
	button.Label.Size = UDim2.fromScale(0.92, 1)
	button.Label.TextWrapped = true

	local timer = Instance.new("Frame")
	timer.Name = "CooldownRing"
	timer.AnchorPoint = Vector2.new(0.5, 0.5)
	timer.Position = UDim2.fromScale(0.5, 0.5)
	timer.Size = UDim2.fromOffset(height - 14, height - 14)
	timer.BackgroundColor3 = Color3.fromRGB(29, 33, 51)
	timer.BackgroundTransparency = 0.35
	timer.Visible = false
	timer.ZIndex = 20
	timer.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = timer
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.max(4, Theme.px(6))
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = timer
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = stroke
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.ZIndex = 21
	label.Parent = timer
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.25, 0), UDim.new(0.25, 0)
	pad.Parent = label
	ring, ringGradient, ringLabel = timer, gradient, label

	-- Keyboard players see which key the button is on.
	local cap = Instance.new("TextLabel")
	cap.Name = "KeyCap"
	cap.Position = UDim2.fromOffset(-6, -6)
	cap.Size = UDim2.fromOffset(math.max(24, Theme.px(26)), math.max(24, Theme.px(26)))
	cap.BackgroundColor3 = Color3.fromRGB(29, 33, 51)
	cap.Text = Config.Input.Keyboard.Name
	cap.Font = Enum.Font.FredokaOne
	cap.TextColor3 = Color3.new(1, 1, 1)
	cap.TextScaled = true
	cap.ZIndex = 30
	cap.Active = false
	cap.Visible = false
	cap.Parent = frame
	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(0, 6)
	capCorner.Parent = cap
	local capStroke = Instance.new("UIStroke")
	capStroke.Thickness = 2
	capStroke.Color = Color3.new(1, 1, 1)
	capStroke.Parent = cap
	local capPad = Instance.new("UIPadding")
	capPad.PaddingTop, capPad.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
	capPad.Parent = cap
	keyCap = cap
end

local function render(state: Rules.SwitchState)
	local screen = gui
	if not screen or not button then
		return
	end
	screen.Enabled = not anyAttribute(HIDE_ATTRIBUTES) and not anyAttribute(BUSY_ATTRIBUTES)
	if keyCap then
		keyCap.Visible = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
	end
	if shownState ~= state.state or shownEnabled ~= state.enabled then
		shownState, shownEnabled = state.state, state.enabled
		button.setText(LABELS[state.state] or state.state)
		button.setVariant(if state.enabled then VARIANTS[state.state] else "locked")
		if carryPulse then
			carryPulse()
			carryPulse = nil
		end
		if state.pulse and holder then
			carryPulse = Juice.breathe(holder)
			pulse(2)
		end
		if state.state == "LoadAndGo" and state.enabled then
			Hints.Show("LoadAndGo", { gui = holder })
		end
	end
	local timer, gradient, label = ring, ringGradient, ringLabel
	if timer and gradient and label then
		local cooling = state.cooldown > 0
		timer.Visible = cooling
		if cooling then
			gradient.Rotation = 360 * (1 - state.cooldown / Config.Call.CooldownSeconds) - 90
			label.Text = tostring(math.ceil(state.cooldown))
		end
	end
end

--------------------------------------------------------------------------------
-- Effects (A4): pooled puff, one Highlight, visual-only pop
--------------------------------------------------------------------------------

local puffPart: Part? = nil
local puffEmitter: ParticleEmitter? = nil
local highlight: Highlight? = nil

local function lowQuality(): boolean
	return Quality.GetTier(player:GetAttribute("VFXQuality")) == "Low"
end

local function flairColor(cart: Model?): Color3
	local style = if cart then (CartFlairStyles.Carts :: any)[cart:GetAttribute("CartId")] else nil
	return if style and typeof(style.Primary) == "Color3"
		then style.Primary
		else Color3.fromRGB(214, 214, 224)
end

local function puff(position: Vector3, color: Color3, bystander: boolean?)
	local part, emitter = puffPart, puffEmitter
	if not part or not emitter then
		part = Instance.new("Part")
		part.Name = "DriveAndHuntPuff"
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Transparency = 1
		part.Size = Vector3.new(6, 1, 6)
		emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
		emitter.Speed = NumberRange.new(6, 12)
		emitter.SpreadAngle = Vector2.new(180, 60)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 5),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 0.3
		emitter.Parent = part
		part.Parent = Workspace
		puffPart, puffEmitter = part, emitter
	end
	part.Position = position
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter:Emit(
		if bystander
			then Config.Fx.BystanderParticles
			elseif lowQuality() then Config.Fx.ParticlesLow
			else Config.Fx.Particles
	)
end

-- Visual-only pop: flair and body visuals only. Colliders, seats, wheels' physics parts and
-- the Root are never resized, and nothing here replicates.
local function pop(cart: Model)
	local glow = highlight
	if not glow then
		glow = Instance.new("Highlight")
		glow.Name = "DriveAndHuntPop"
		glow.FillColor, glow.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight = glow
	end
	glow.Adornee, glow.Parent = cart, cart
	glow.FillTransparency, glow.OutlineTransparency = 0.25, 0
	TweenService:Create(
		glow,
		TweenInfo.new(Config.Fx.BeatSeconds),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	):Play()
	task.delay(Config.Fx.BeatSeconds + 0.05, function()
		if glow.Adornee == cart then
			glow.Adornee, glow.Parent = nil, nil
		end
	end)
	if lowQuality() or Juice.reduced() then
		return
	end
	local visual = cart:FindFirstChild("Visual")
	if not visual then
		return
	end
	local scales = Config.Fx.PopScales
	local count = 0
	for _, part in visual:GetDescendants() do
		if count >= Config.Fx.PopPartsMax then
			break
		end
		if
			part:IsA("BasePart")
			and not part.CanCollide
			and not part:IsA("Seat")
			and not part:IsA("VehicleSeat")
			and part ~= cart.PrimaryPart
		then
			count += 1
			local rest = part.Size
			part.Size = rest * scales[1]
			local up = TweenService:Create(
				part,
				TweenInfo.new(
					Config.Fx.BeatSeconds * 0.6,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				),
				{ Size = rest * scales[2] }
			)
			up.Completed:Once(function()
				TweenService:Create(
					part,
					TweenInfo.new(Config.Fx.BeatSeconds * 0.4),
					{ Size = rest * scales[3] }
				):Play()
			end)
			up:Play()
		end
	end
end

local function onFx(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind == "Launch" or kind == "Call" or kind == "LoadAndGo" then
		local cart = payload.cart
		if typeof(cart) == "Instance" and cart:IsA("Model") then
			seatedAt = os.clock()
			pop(cart)
			AudioCue.Play("S8_" .. math.random(1, 2), { volume = 0.9 })
		end
	elseif kind == "Puff" then
		if typeof(payload.at) == "Vector3" then
			local color = if typeof(payload.color) == "Color3"
				then payload.color
				else flairColor(LocalCartState.GetCart())
			-- A puff well away from the local player's own cart is someone else's: fewer
			-- particles, and at most one every BystanderPuffInterval seconds.
			local own = LocalCartState.GetCart()
			local mine = own ~= nil and (own:GetPivot().Position - payload.at).Magnitude < 20
			if not mine then
				if os.clock() - lastBystanderPuffAt < Config.Fx.BystanderPuffInterval then
					return
				end
				lastBystanderPuffAt = os.clock()
			end
			puff(payload.at, color, not mine)
		end
	elseif kind == "Pulse" then
		pulse(3)
		if payload.hint == "Unreachable" then
			Hints.Show("HopOut", { gui = holder })
		end
	elseif kind == "Scoop" then
		if type(payload.itemId) == "string" then
			ScoopFx.OnScoop(payload.itemId)
		end
	end
end

--------------------------------------------------------------------------------

local function step(dt: number)
	elapsed += dt
	if elapsed < 0.1 then
		return
	end
	elapsed = 0
	local driving = isDriving()
	if driving and not wasDriving then
		seatedAt = math.max(seatedAt, os.clock() - 0.1)
	end
	wasDriving = driving
	if Flags.Part("SwitchButton") then
		setJumpBlocked(driving)
		local state = compute()
		current = state
		render(state)
	end
	-- Open menus count as busy too, so the gate launch never moves the player mid-menu.
	local busy = anyAttribute(BUSY_ATTRIBUTES) or anyAttribute(HIDE_ATTRIBUTES)
	if busy ~= lastBusy and requestRemote then
		lastBusy = busy
		requestRemote:FireServer("Busy", busy)
	end
end

function Controller.Start()
	if started or not Flags.Enabled() then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestEvent = remotes:WaitForChild(RemoteNames.DriveAndHuntRequest, 30)
	local fx = remotes:WaitForChild(RemoteNames.DriveAndHuntFx, 30)
	if
		not requestEvent
		or not requestEvent:IsA("RemoteEvent")
		or not fx
		or not fx:IsA("RemoteEvent")
	then
		started = false
		return
	end
	requestRemote = requestEvent
	table.insert(connections, fx.OnClientEvent:Connect(onFx))
	if Flags.Part("SwitchButton") then
		-- Theme.px reads the viewport at build time; wait until it is sized.
		local camera = Workspace.CurrentCamera
		while camera and camera.ViewportSize.Y < 200 do
			task.wait(0.1)
			camera = Workspace.CurrentCamera
		end
		buildButton()
		ContextActionService:BindAction(SWITCH_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				request()
			end
			return Enum.ContextActionResult.Pass
		end, false, Config.Input.Keyboard, Config.Input.Gamepad)
	end
	ScoopFx.Start()
	if Flags.Part("AutoLock") and Flags.Part("Hints") then
		table.insert(
			connections,
			AutoLock.Changed:Connect(function()
				if AutoLock.HasLock() and isDriving() then
					local playerGui = player:FindFirstChildOfClass("PlayerGui")
					local fire = playerGui and playerGui:FindFirstChild("MountedFire", true)
					Hints.Show(
						"Lock",
						{ gui = if fire and fire:IsA("GuiObject") then fire else nil }
					)
				end
			end)
		)
	end
	table.insert(connections, RunService.Heartbeat:Connect(step))
	table.insert(
		connections,
		player.CharacterAdded:Connect(function()
			jumpBlocked = false
			ContextActionService:UnbindAction(JUMP_SINK)
		end)
	)
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ContextActionService:UnbindAction(SWITCH_ACTION)
	setJumpBlocked(false)
	ScoopFx.Stop()
	if gui then
		gui:Destroy()
		gui = nil
	end
	started = false
end

return Controller
