--!strict
-- Current owner-defined action: shoot to sleep, then ordinary E pickup/bank.
-- Existing weapon, aim, daze and shot presentation contracts are retained.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local MountedAimState = require(script.Parent.Parent.State.MountedAimState)
local ThirdPersonAimController = require(script.Parent.ThirdPersonAimController)
local MountedShotPreview = require(ReplicatedStorage.Shared.Utility.MountedShotPreview)
local SeatState = require(ReplicatedStorage.Shared.Utility.HumanoidSeatState)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)
local MaterialPolicy = require(ReplicatedStorage.Shared.Utility.MapArtStaticMaterialPolicy)
local InputRegistry = require(ReplicatedStorage.Shared.Config.CartInputRegistry)
local InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local Feedback = require(script.Parent.Parent.Utility.Phase10Feedback)
local RemoteBinding = require(script.Parent.Parent.Utility.RemoteDependencyBinding)
local SleepRequest: RemoteEvent? = nil

local triggerHeld = false
local touchFireInput: InputObject? = nil
local consentGui: ScreenGui? = nil
local consentStatus: TextLabel? = nil
local DEFAULT_WEAPON_PROFILE = WeaponStats.Resolve(Weapons.StarterWeaponId)
assert(WeaponStats.IsReady(DEFAULT_WEAPON_PROFILE), "Starter weapon profile must be valid")
local BOLT_LENGTH, BOLT_WIDTH = 1.5, 0.25
local ACTION_NAME = "SleepLauncherFire" -- Keep the established G action binding.
local MOUNTED_ACTION = "MountedSleepFire"
local MOUNTED_PREVIEW_STEP = "MountedSleepPreview"
local CombatStrings = require(ReplicatedStorage.Shared.Config.Phase13CombatStrings)
local player = Players.LocalPlayer
local aimController = ThirdPersonAimController.new(player)
local WeaponArt = require(script.Parent.WeaponArtController)
local function selectedProfile()
	local profile = WeaponStats.Resolve(player:GetAttribute("SelectedWeaponId") or Weapons.StarterWeaponId)
	return if WeaponStats.IsReady(profile) then profile else DEFAULT_WEAPON_PROFILE
end
local function refreshWeaponProfile()
	aimController:SetWeaponProfile(selectedProfile())
end
refreshWeaponProfile()
local selectedWeaponConnection = player:GetAttributeChangedSignal("SelectedWeaponId"):Connect(refreshWeaponProfile)
local destroyed = false
-- Adapt the current PlayerModule input, not its source or an independent
-- Camera.CFrame writer. Both shipped PlayerModule layouts expose CameraInput.
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts", 10)
	local playerModule = if scripts then scripts:WaitForChild("PlayerModule", 10) else nil
	local cameraModule = if playerModule then playerModule:WaitForChild("CameraModule", 10) else nil
	local inputModule = if cameraModule then cameraModule:WaitForChild("CameraInput", 10) else nil
	if destroyed then
		return
	end
	local ok, adapter = pcall(function()
		assert(inputModule and inputModule:IsA("ModuleScript"), "PlayerModule.CameraInput unavailable")
		return require(inputModule)
	end)
	if destroyed then
		return
	end
	if not ok or not aimController:SetCameraInput(adapter) then
		warn(
			"[HuntingTracking] CameraInput adapter unavailable; ordinary hunting remains enabled; soft tracking unavailable"
		)
	end
end)
local cooldownUntil = 0
local requestSequence, bindingGeneration = 0, 0
local boundLauncher: Tool? = nil
local launcherConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local observedCharacter: Model? = nil
local backpackConnection: RBXScriptConnection? = nil
local hiddenLauncherParts: { [BasePart]: number } = {}
local launcherLabels: { [Tool]: { Name: string, Tip: string, ManualActivationOnly: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local HUNTING_TOOLTIP = "Equip Hunting · aim and fire to sleep"

-- ViewportPointToRay and this GUI both use DEVICE-safe coordinates, including
-- the top-bar area. Core-UI insets/pointer coordinates never enter aiming.
local reticleGui = Instance.new("ScreenGui")
reticleGui.Name = "SleepAimReticle"
reticleGui.ResetOnSpawn = false
reticleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
reticleGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
reticleGui.Enabled = false
local reticle = Instance.new("Frame")
reticle.Name = "HollowCross"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(26, 26)
reticle.BackgroundTransparency = 1
reticle.BorderSizePixel = 0
reticle.Active = false
reticle.Parent = reticleGui
-- Inner edges (including the one-pixel outlines) stop at +/-4 pixels.
for name, shape in
	{
		Top = { 0, -9, 2, 8 },
		Bottom = { 0, 9, 2, 8 },
		Left = { -9, 0, 8, 2 },
		Right = { 9, 0, 8, 2 },
	}
do
	local arm = Instance.new("Frame")
	arm.Name, arm.AnchorPoint = name, Vector2.new(0.5, 0.5)
	arm.Position = UDim2.new(0.5, shape[1], 0.5, shape[2])
	arm.Size = UDim2.fromOffset(shape[3], shape[4])
	arm.BackgroundColor3, arm.BorderSizePixel = Color3.new(1, 1, 1), 0
	arm.Active, arm.Parent = false, reticle
	local outline = Instance.new("UIStroke")
	outline.Thickness, outline.Color = 1, Color3.fromRGB(25, 35, 40)
	outline.Parent = arm
end
reticleGui.Parent = player:WaitForChild("PlayerGui")
local fireSafeArea = Instance.new("Frame")
fireSafeArea.Name, fireSafeArea.Size, fireSafeArea.BackgroundTransparency = "FireSafeArea", UDim2.fromScale(1, 1), 1
fireSafeArea.Parent = reticleGui
require(script.Parent.Parent.UI.StudPopUI).skin(fireSafeArea, { hints = { MountedFire = "go", MountedAim = "info" }, windowDepth = 0 })
local fireButton = Instance.new("TextButton")
fireButton.Name = "MountedFire"
fireButton.AnchorPoint, fireButton.Position = Vector2.new(1, 0), UDim2.new(1, -20, 1, -202)
fireButton.Size = UDim2.fromOffset(64, 64)
fireButton.Text, fireButton.TextSize, fireButton.Font = "Fire", 20, Enum.Font.GothamBold
fireButton.BackgroundColor3, fireButton.TextColor3 = Color3.fromRGB(30, 36, 42), Color3.fromRGB(220, 245, 255)
fireButton.BackgroundTransparency, fireButton.Visible = 0.15, false
fireButton.Parent = fireSafeArea
local touchAimToggled = false
local aimButton = Instance.new("TextButton")
aimButton.Name, aimButton.AnchorPoint = "MountedAim", Vector2.new(1, 0)
aimButton.Position, aimButton.Size = UDim2.new(1, -96, 1, -202), UDim2.fromOffset(64, 64)
aimButton.Text, aimButton.TextSize, aimButton.Font = "Aim", 18, Enum.Font.GothamBold
aimButton.BackgroundColor3, aimButton.TextColor3 = Color3.fromRGB(30, 36, 42), Color3.fromRGB(220, 245, 255)
aimButton.BackgroundTransparency, aimButton.Visible, aimButton.Parent = 0.15, false, fireSafeArea
local aimCorner = Instance.new("UICorner")
aimCorner.CornerRadius, aimCorner.Parent = UDim.new(0, 16), aimButton
local fireLayoutConnection = fireSafeArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local size = fireSafeArea.AbsoluteSize
	local top = if size.Y < 340 and size.X < 384 then 122 else math.max(8, size.Y - 202)
	local y = math.clamp(top, 8, math.max(8, size.Y - 72))
	fireButton.Position, aimButton.Position = UDim2.new(1, -20, 0, y), UDim2.new(1, -96, 0, y)
end)
local fireCorner = Instance.new("UICorner")
fireCorner.CornerRadius, fireCorner.Parent = UDim.new(0, 16), fireButton
local impactDot = Instance.new("Frame")
impactDot.Name, impactDot.AnchorPoint = "MountedImpactDot", Vector2.new(0.5, 0.5)
impactDot.Size, impactDot.BorderSizePixel = UDim2.fromOffset(5, 5), 0
impactDot.BackgroundColor3, impactDot.Visible = Color3.fromRGB(130, 240, 255), false
impactDot.Active, impactDot.Parent = false, reticleGui
local impactCorner = Instance.new("UICorner")
impactCorner.CornerRadius, impactCorner.Parent = UDim.new(1, 0), impactDot
local impactStroke = Instance.new("UIStroke")
impactStroke.Thickness, impactStroke.Color, impactStroke.Parent = 1, Color3.fromRGB(15, 20, 25), impactDot
local targetHighlight = Instance.new("Highlight")
targetHighlight.Name, targetHighlight.DepthMode = "SleepSelectedTarget", Enum.HighlightDepthMode.Occluded
targetHighlight.FillTransparency, targetHighlight.OutlineTransparency = 1, 0.12
targetHighlight.Enabled, targetHighlight.Parent = false, Workspace
local targetLabel = Instance.new("TextLabel")
targetLabel.Name, targetLabel.BackgroundTransparency = "TargetStatus", 1
targetLabel.AnchorPoint, targetLabel.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.5, 22)
targetLabel.Size, targetLabel.Font, targetLabel.TextSize = UDim2.fromOffset(250, 24), Enum.Font.GothamBold, 15
targetLabel.Text, targetLabel.Visible, targetLabel.Parent = "", false, reticleGui
local targetStroke = Instance.new("UIStroke")
targetStroke.Color, targetStroke.Thickness, targetStroke.Parent = Color3.fromRGB(8, 8, 10), 2, targetLabel
local refreshReticle: () -> ()
local traceContext: (string) -> ()

local function isLauncher(tool: Instance): boolean
	return tool:IsA("Tool")
		and (tool.Name == "SleepLauncher" or tool.Name == "Hunting")
		and tool:GetAttribute("BrainrotSleepLauncher") == true
end

local function labelLauncher(child: Instance)
	if not isLauncher(child) then
		return
	end
	local tool = child :: Tool
	if not launcherLabels[tool] then
		launcherLabels[tool] = { Name = tool.Name, Tip = tool.ToolTip, ManualActivationOnly = tool.ManualActivationOnly }
	end
	-- Local hotbar label only. The server asset/authorization name remains
	-- SleepLauncher; there is still exactly one native equip toggle.
	tool.Name, tool.ToolTip = "Hunting", HUNTING_TOOLTIP
end

local function restoreLauncherPresentation()
	for part, previous in hiddenLauncherParts do
		if part.Parent and part.LocalTransparencyModifier == 1 then
			part.LocalTransparencyModifier = previous
		end
	end
	table.clear(hiddenLauncherParts)
end

local function suspendLauncherPresentation(suspended: boolean)
	if not suspended then
		restoreLauncherPresentation()
		return
	end
	if not boundLauncher then
		return
	end
	for _, child in boundLauncher:GetDescendants() do
		if child:IsA("BasePart") and hiddenLauncherParts[child] == nil then
			hiddenLauncherParts[child] = child.LocalTransparencyModifier
			child.LocalTransparencyModifier = 1
		end
	end
end

local function hasOtherWeapon(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and not isLauncher(child) then
			return true
		end
	end
	return false
end

local function getMountedCart(): Model?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local seat = humanoid.SeatPart
	if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) or seat.Occupant ~= humanoid then
		return nil
	end
	local runtime = Workspace:FindFirstChild("Runtime")
	local carts = if runtime then runtime:FindFirstChild("Carts") else nil
	local ancestor = seat.Parent
	while ancestor and ancestor ~= carts do
		if ancestor:IsA("Model") and ancestor.Parent == carts and ancestor:GetAttribute("RuntimeCart") == true then
			if
				seat == ancestor:FindFirstChild("DriverSeat")
				and ancestor == LocalCartState.GetCart()
				and LocalCartState.IsAuthorizedDriver()
			then
				return ancestor
			end

			return nil
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function traceEnabled(): boolean
	-- Opt-in, Studio-only boundary traces; absent/false in ordinary play.
	return RunService:IsStudio() and ReplicatedStorage:GetAttribute("HuntingAimTrace") == true
end

local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and math.abs(value.X) < math.huge
		and value.Y == value.Y
		and math.abs(value.Y) < math.huge
		and value.Z == value.Z
		and math.abs(value.Z) < math.huge
end

local effects = Instance.new("Folder")
effects.Name, effects.Parent = "SleepBoltEffects", Workspace
local function clearMountedPreview()
    impactDot.Visible = false
end
-- The old anchored blue Handle copy at HarpoonOrigin was a cosmetic preview,
-- not a mounted weapon. The real equipped art and impact preview own presentation.
local bolts: { [Model]: any } = {}
local boltConnection: RBXScriptConnection? = nil

local function destroySleepBolt(model: Model)
	bolts[model] = nil
	model:Destroy() -- Only this controller's cosmetic model, never a target/cart.
end

local function positionBolt(bolt: any)
	local front = math.min(bolt.Length, math.max(0.001, bolt.Speed * bolt.Elapsed))
	local tail = math.max(0, front - BOLT_LENGTH)
	local length = front - tail
	local middle = bolt.Origin + bolt.Direction * ((front + tail) * 0.5)
	local frame = CFrame.lookAt(middle, middle + bolt.Direction)
	for _, part in bolt.Parts do
		local width = part:GetAttribute("BoltWidth")
		part.Size = Vector3.new(width, width, length)
		part.CFrame = frame -- Primitive's long Z axis follows the immutable shot.
	end
end

local function updateSleepBolts(dt: number)
	for model, bolt in bolts do
		if model.Parent ~= effects or bolt.Arrived then
			destroySleepBolt(model)
		else
			bolt.Elapsed += math.max(dt, 0)
			positionBolt(bolt)
			-- Present the clamped endpoint for one frame, including near hits whose
			-- entire flight fits inside a frame; retire it on the next update.
			bolt.Arrived = bolt.Elapsed * bolt.Speed >= bolt.Length
		end
	end
	if next(bolts) == nil and boltConnection then
		boltConnection:Disconnect()
		boltConnection = nil
	end
end

local function renderShot(origin: any, endpoint: any, presentedProfile: any?)
	if destroyed or not finiteVector(origin) or not finiteVector(endpoint) then
		return
	end
	local profile = if WeaponStats.IsReady(presentedProfile) then presentedProfile else DEFAULT_WEAPON_PROFILE
	local segment = endpoint - origin
	local length = segment.Magnitude
	if length <= 0.001 or length > profile.rangeStuds + 0.1 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "SleepBolt"
	local parts = {}
	for _, style in
		{
			{ "WhiteCore", BOLT_WIDTH, Color3.new(1, 1, 1), 0 },
			{ "RedHalo", BOLT_WIDTH * 2.5, Color3.fromRGB(255, 12, 20), 0.7 },
			{ "SoftRedEdge", BOLT_WIDTH * 3, Color3.fromRGB(255, 0, 12), 0.9 },
		}
	do
		local part = Instance.new("Part")
		part.Name, part.Material = style[1], Enum.Material.Neon
		if style[1] ~= "WhiteCore" then
			part.Shape = Enum.PartType.Ball -- Layered translucent ellipsoids, not a hard red box around the white core.
		end
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.CastShadow, part.Color, part.Transparency = false, style[3], style[4]
		part:SetAttribute("BoltWidth", math.min(style[2], length))
		MaterialPolicy.Apply(part, Enum.Material.Neon)
		part.Parent = model
		table.insert(parts, part)
	end
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = Color3.fromRGB(255, 0, 10), 4, 2, false
	light.Parent = parts[1]
	local bolt = {
		Origin = origin,
		Direction = segment / length,
		Length = length,
		Speed = profile.projectileSpeedStudsPerSecond,
		Elapsed = 0,
		Parts = parts,
	}
	positionBolt(bolt)
	bolts[model] = bolt
	model.Parent = effects
	if not boltConnection then
		boltConnection = RunService.RenderStepped:Connect(updateSleepBolts)
	end
	if traceEnabled() then
		print(
			string.format(
				"[HuntingAim][bolt] acceptedM=%s acceptedE=%s length=%.2f cosmeticSpeed=%d",
				tostring(origin),
				tostring(endpoint),
				length,
				profile.projectileSpeedStudsPerSecond
			)
		)
	end
end

local function getOnFootHuntingCharacter(): Model?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local tool = boundLauncher
	if
		not character
		or not humanoid
		or humanoid.Health <= 0
		or SeatState.IsSeated(humanoid)
		or player:GetAttribute("CarriedItemId") ~= nil
		or not tool
		or ThirdPersonAimController.GetHeldLauncher(character) ~= tool
		or tool.Parent ~= character
		or not tool.Enabled
		or not isLauncher(tool)
		or hasOtherWeapon(character)
	then
		return nil
	end
	return character
end

local function canRequestFire(): boolean
	if not SleepRequest then
		return false
	end
	if
		player:GetAttribute("Phase13CinematicActive") == true
		or player:GetAttribute("Phase13ConsentDialogOpen") == true
		or player:GetAttribute("Phase13CompareDialogOpen") == true
	then
		return false
	end
	-- Presentation only; the server uses the interaction owner's predicate.
	if
		InputPolicy.IsDazed(player)
		or aimController:IsInputSuspended()
		or player:GetAttribute("CarriedItemId") ~= nil
	then
		return false
	end
	return getMountedCart() ~= nil or (getOnFootHuntingCharacter() ~= nil and aimController:IsActive())
end

local function showWeaponCrosshair(): boolean
	return canRequestFire()
end

refreshReticle = function()
	aimController:SetCharacter(getOnFootHuntingCharacter())
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	suspendLauncherPresentation(
		player:GetAttribute("CarriedItemId") ~= nil or (humanoid ~= nil and SeatState.IsSeated(humanoid))
	)
	reticleGui.Enabled = showWeaponCrosshair()
	local cart = getMountedCart()
	local touchPrimary = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	fireButton.Visible = touchPrimary and canRequestFire()
	aimButton.Visible = fireButton.Visible and cart ~= nil
	if boundLauncher and launcherLabels[boundLauncher] then
		-- The dedicated button owns touch firing; camera/joystick taps must not
		-- also invoke the equipped Tool's native activation route.
		boundLauncher.ManualActivationOnly = touchPrimary or launcherLabels[boundLauncher].ManualActivationOnly
	end
	if cart == nil then
		touchAimToggled = false
		MountedAimState.SetRequested("Touch", false)
		clearMountedPreview()
	end
	if not reticleGui.Enabled then
		targetHighlight.Enabled, targetHighlight.Adornee, targetLabel.Visible = false, nil, false
	end
	traceContext("ContextChanged")
end

aimController.OnContextChanged = function()
	reticleGui.Enabled = showWeaponCrosshair()
end

local contextKey = ""
traceContext = function(reason: string)
	if not traceEnabled() then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	local equipped, stored = 0, 0
	for _, container in { character, backpack } do
		for _, child in container:GetChildren() do
			if isLauncher(child) then
				if container == character then
					equipped += 1
				else
					stored += 1
				end
			end
		end
	end
	local key = string.format(
		"character=%s carrying=%s seated=%s seat=%s hunting=%s equipped=%d backpack=%d canAim=%s canFire=%s cross=%s bound=%s generation=%d",
		tostring(character),
		tostring(player:GetAttribute("CarriedItemId")),
		tostring(humanoid and humanoid.Sit),
		tostring(humanoid and humanoid.SeatPart),
		tostring(equipped > 0),
		equipped,
		stored,
		tostring(aimController:IsActive()),
		tostring(canRequestFire()),
		tostring(reticleGui.Enabled),
		tostring(boundLauncher),
		bindingGeneration
	)
	if key ~= contextKey or reason == "FireBlocked" then
		contextKey = key
		print("[HuntingContext] reason=" .. reason .. " " .. key)
	end
end

local function requestFire()
	refreshReticle()
	if not canRequestFire() then
		traceContext("FireBlocked")
		return
	end
	local now = os.clock()
	if now < cooldownUntil then
		return
	end
	local cart = getMountedCart()
	local snapshot = aimController:GetShotSnapshot(cart ~= nil)
	if not snapshot or not canRequestFire() then
		return
	end
	local ray = snapshot.ShotRay
	local selectedTarget = aimController:GetCrosshairTarget(cart)
	-- Deliberate player/cargo targeting always retains the exact crosshair ray.
	-- Never let a wild assistance lock redirect an aimed PvP shot.
	if selectedTarget then
		ray = snapshot.CrosshairRay
		snapshot = { Mode = "CROSSHAIR_FREE", CrosshairRay = ray }
	end
	cooldownUntil = now + selectedProfile().fireIntervalSeconds
	requestSequence += 1
	if traceEnabled() then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local muzzle = if cart
			then cart:FindFirstChild("HarpoonOrigin", true)
			elseif boundLauncher then boundLauncher:FindFirstChild("Muzzle", true)
			else nil
		local frame = if muzzle and muzzle:IsA("Attachment")
			then muzzle.WorldCFrame
			elseif muzzle and muzzle:IsA("BasePart") then muzzle.CFrame
			else nil
		print(
			string.format(
				"[HuntingAim][send] request=%d tracking=%s mode=%s C=%s D=%s rootForward=%s muzzle=%s M=%s muzzleForward=%s grip=%s",
				requestSequence,
				tostring(aimController:GetTrackingId()),
				snapshot.Mode,
				tostring(ray.Origin),
				tostring(ray.Direction),
				if root and root:IsA("BasePart") then tostring(root.CFrame.LookVector) else "none",
				if muzzle then muzzle:GetFullName() else "none",
				tostring(frame and frame.Position),
				tostring(frame and frame.LookVector),
				tostring(boundLauncher and boundLauncher.Grip)
			)
		)
	end
	-- WORLD camera origin + UNIT centre direction. Never a client muzzle/hit.
	local remote = SleepRequest
	if not remote then
		return
	end
	remote:FireServer({
		RequestId = requestSequence,
		CameraOrigin = ray.Origin,
		CameraDirection = ray.Direction,
		CrosshairDirection = snapshot.CrosshairRay.Direction,
		ShotMode = snapshot.Mode,
		LockedTargetId = snapshot.TargetId,
		LockedTargetKind = snapshot.TargetKind,
		TargetItemId = if selectedTarget then selectedTarget.ItemId else nil,
		TargetCartId = if selectedTarget then selectedTarget.CartId else nil,
		TargetPlayerUserId = if selectedTarget then selectedTarget.PlayerUserId else nil,
	})
end

local function triggerStart()
	triggerHeld = true
	requestFire()
end
local function triggerStop()
	triggerHeld = false
	touchFireInput = nil
end
local function closeConsent()
	triggerHeld = false
	if consentGui then
		consentGui:Destroy()
		consentGui = nil
		consentStatus = nil
	end
	player:SetAttribute("Phase13ConsentDialogOpen", nil)
end
local function openConsent()
	if consentGui then
		return
	end
	triggerHeld = false
	player:SetAttribute("Phase13ConsentDialogOpen", true)
	local screen = Instance.new("ScreenGui")
	screen.Name = "ProtectionOptOut"
	require(script.Parent.Parent.UI.StudPopUI).skin(screen)
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 90
	screen.Parent = player:WaitForChild("PlayerGui")
	consentGui = screen
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(350, 190)
	panel.BackgroundColor3 = Color3.fromRGB(30, 22, 48)
	panel.Parent = screen
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(350, 190)
	constraint.MinSize = Vector2.new(280, 170)
	constraint.Parent = panel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -24, 0, 100)
	text.Position = UDim2.fromOffset(12, 8)
	text.BackgroundTransparency = 1
	text.TextWrapped = true
	text.TextSize = 20
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = CombatStrings.ProtectionQuestion
	text.Parent = panel
	consentStatus = text
	local function button(name, x)
		local item = Instance.new("TextButton")
		item.Name = name
		item.Text = name
		item.Size = UDim2.new(0.5, -18, 0, 48)
		item.Position = UDim2.new(x, 12, 1, -60)
		item.TextSize = 18
		item.Font = Enum.Font.GothamBold
		item.TextColor3 = Color3.new(1, 1, 1)
		item.BackgroundColor3 = Color3.fromRGB(75, 56, 108)
		item.Parent = panel
		return item
	end
	local cancel = button(CombatStrings.Cancel, 0)
	local confirm = button(CombatStrings.EndProtection, 0.5)
	GuiService.SelectedObject = cancel
	cancel.Activated:Connect(closeConsent)
	confirm.Activated:Connect(function()
		if not consentGui or player:GetAttribute("Phase13ProtectionOptOutPending") == true then
			return
		end
		text.Text = CombatStrings.SavingChoice
		confirm.Active = false
		cancel.Visible = false
		local remote = ReplicatedStorage:FindFirstChild("Remotes")
			and ReplicatedStorage.Remotes:FindFirstChild("ProtectionOptOutRequest")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer({ confirm = true, operationId = HttpService:GenerateGUID(false) })
		else
			text.Text = CombatStrings.ProtectionUnavailable
			confirm.Visible = false
			cancel.Visible = true
		end
	end)
end
local optOutConnection: RBXScriptConnection? = nil
local function bindOptOut(remote)
	if optOutConnection or not remote:IsA("RemoteEvent") then
		return
	end
	optOutConnection = remote.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		triggerHeld = false
		if result.status == "Saved" then
			closeConsent()
			Feedback.Show(CombatStrings.ProtectionEnded)
		elseif result.status == "Unavailable" or result.status == "Rejected" then
			closeConsent()
			Feedback.Show(result.message or "Your protection remains active.")
		elseif consentStatus then
			consentStatus.Text = result.message or CombatStrings.SavingChoice
		end
	end)
end
local optFolder = ReplicatedStorage:WaitForChild("Remotes")
local initialOpt = optFolder:FindFirstChild("ProtectionOptOutRequest")
if initialOpt then
	bindOptOut(initialOpt)
end
local optAddedConnection = optFolder.ChildAdded:Connect(function(child)
	if child.Name == "ProtectionOptOutRequest" then
		bindOptOut(child)
	end
end)

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function unbindLauncher()
	triggerHeld = false
	touchFireInput = nil
	if boundLauncher and boundLauncher.Parent and launcherLabels[boundLauncher] then
		boundLauncher.ManualActivationOnly = launcherLabels[boundLauncher].ManualActivationOnly
	end
	bindingGeneration += 1
	aimController:SetCharacter(nil)
	restoreLauncherPresentation()
	boundLauncher = nil
	disconnectAll(launcherConnections)
	refreshReticle()
end

local function bindLauncher(tool: Tool)
	if boundLauncher == tool then
		return
	end
	unbindLauncher()
	boundLauncher = tool
	bindingGeneration += 1
	local generation = bindingGeneration
	labelLauncher(tool)
	table.insert(launcherConnections, tool.Deactivated:Connect(triggerStop))
	table.insert(launcherConnections, tool:GetAttributeChangedSignal("BrainrotSleepLauncher"):Connect(refreshReticle))
	table.insert(launcherConnections, tool:GetPropertyChangedSignal("Name"):Connect(refreshReticle))
	table.insert(launcherConnections, tool:GetPropertyChangedSignal("Enabled"):Connect(refreshReticle))
	-- Native activation owns on-foot primary input; mounted contexts use the
	-- single gated mounted action even with the handheld launcher stowed.
	table.insert(
		launcherConnections,
		tool.Activated:Connect(function()
			if
				boundLauncher == tool
				and bindingGeneration == generation
				and tool.Parent == player.Character
				and getMountedCart() == nil
			then
				triggerStart()
			end
		end)
	)
	table.insert(
		launcherConnections,
		tool.Unequipped:Connect(function()
			if boundLauncher == tool and bindingGeneration == generation and tool.Parent ~= player.Character then
				unbindLauncher()
			end
		end)
	)
	table.insert(
		launcherConnections,
		tool.AncestryChanged:Connect(function()
			if boundLauncher == tool and bindingGeneration == generation and tool.Parent ~= player.Character then
				unbindLauncher()
			end
		end)
	)
	table.insert(
		launcherConnections,
		tool.Destroying:Connect(function()
			if boundLauncher == tool and bindingGeneration == generation then
				unbindLauncher()
			end
		end)
	)
	table.insert(launcherConnections, tool.DescendantAdded:Connect(refreshReticle))
	table.insert(
		launcherConnections,
		tool.DescendantRemoving:Connect(function()
			task.defer(function()
				if not destroyed and boundLauncher == tool and bindingGeneration == generation then
					refreshReticle()
				end
			end)
		end)
	)
	refreshReticle()
end

local function bindCharacter(character: Model?)
	observedCharacter = character
	disconnectAll(characterConnections)
	unbindLauncher()
	if not character then
		return
	end
	local observedHumanoid: Humanoid? = nil
	local function refreshLauncher()
		if player.Character ~= character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid ~= observedHumanoid then
			observedHumanoid = humanoid
			table.insert(characterConnections, humanoid.Seated:Connect(refreshReticle))
			table.insert(characterConnections, humanoid.StateChanged:Connect(refreshReticle))
			table.insert(characterConnections, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(refreshReticle))
			table.insert(characterConnections, humanoid:GetPropertyChangedSignal("Sit"):Connect(refreshReticle))
			table.insert(characterConnections, humanoid.HealthChanged:Connect(refreshReticle))
		end
		for _, child in character:GetChildren() do
			if isLauncher(child) then
				bindLauncher(child :: Tool)
				refreshReticle()
				return
			end
		end
		unbindLauncher()
	end
	table.insert(characterConnections, character.ChildAdded:Connect(refreshLauncher))
	table.insert(characterConnections, character.ChildRemoved:Connect(refreshLauncher))
	refreshLauncher()
end

local function observeBackpack(child: Instance)
	if not child:IsA("Backpack") then
		return
	end
	if backpackConnection then
		backpackConnection:Disconnect()
	end
	backpackConnection = child.ChildAdded:Connect(labelLauncher)
	for _, tool in child:GetChildren() do
		labelLauncher(tool)
	end
end
local backpackAddedConnection = player.ChildAdded:Connect(observeBackpack)
local backpack = player:FindFirstChildOfClass("Backpack")
if backpack then
	observeBackpack(backpack)
end

-- One server-confirmed notification -> one bolt per observer. No prediction,
-- old beam, duplicate result handler or cosmetic sleep callback.
local function receiveSleepResult(origin, endpoint, result, presentedProfile)
	if type(result) == "table" and result.ImpactKind == "ProtectionOptOutRequired" then
		openConsent()
	end
	if type(result) == "table" and result.Phase10Message then
		Feedback.Show(result.Phase10Message)
	end
	if traceEnabled() and type(result) == "table" and result.PlayerId == player.UserId then
		print(
			string.format(
				"[HuntingAim][result] request=%s accepted=%s reason=%s item=%s slept=%s",
				tostring(result.RequestId),
				tostring(result.Accepted),
				tostring(result.Reason),
				tostring(result.ItemId),
				tostring(result.Slept)
			)
		)
	end
	renderShot(origin, endpoint, presentedProfile)
	if finiteVector(origin) then
		-- Camp Rework weapon feedback (drum snap, petal/piston kick, emitter burst). Presentation only.
		pcall(WeaponArt.OnShot, origin)
	end
end
local sleepBinding = RemoteBinding.new({
	Root = ReplicatedStorage,
	Name = "SleepRequest",
	OnRemote = function(remote)
		SleepRequest = remote
		triggerHeld = false
		refreshReticle()
		return if remote then remote.OnClientEvent:Connect(receiveSleepResult) else nil
	end,
	OnState = function(status, reason)
		player:SetAttribute("SleepDependencyState", status)
		player:SetAttribute("SleepDependencyReason", reason)
		if status == "Unavailable" then
			Feedback.Show("Sleep launcher unavailable · server registration")
		end
	end,
})
local carryConnection = player:GetAttributeChangedSignal("CarriedItemId"):Connect(refreshReticle)
local cartConnection = LocalCartState.Changed:Connect(refreshReticle)
local dazeConnection = player:GetAttributeChangedSignal("Phase10DazeEnd"):Connect(refreshReticle)
local lastCorrection = player:GetAttribute("Phase10CartCorrectionAt")
local correctionConnection = player:GetAttributeChangedSignal("Phase10CartCorrectionAt"):Connect(function()
	local at = player:GetAttribute("Phase10CartCorrectionAt")
	if type(at) == "number" and (type(lastCorrection) ~= "number" or at > lastCorrection) then
		lastCorrection = at
		Feedback.Show("Cart corrected.")
	end
end)
local characterAddedConnection = player.CharacterAdded:Connect(bindCharacter)
local characterRemovingConnection = player.CharacterRemoving:Connect(function(character)
	if character == observedCharacter then
		bindCharacter(nil)
	end
end)
bindCharacter(player.Character)
ContextActionService:BindAction(ACTION_NAME, function(_: string, inputState: Enum.UserInputState)
	if not canRequestFire() then
		if inputState == Enum.UserInputState.Begin then
			traceContext("FireBlocked")
		end
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		triggerStart()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		triggerStop()
	end
	return Enum.ContextActionResult.Sink
end, false, InputRegistry.Fire.Keyboard)
ContextActionService:BindActionAtPriority(MOUNTED_ACTION, function(_: string, state: Enum.UserInputState)
	if getMountedCart() == nil or not canRequestFire() then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		triggerStart()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		triggerStop()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 1, InputRegistry.Fire.Gamepad)
local mountedMouseConnection = UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or getMountedCart() == nil then
		return
	end
	if InputPolicy.IsPointerInteraction(player, Vector2.new(input.Position.X, input.Position.Y)) then
		return
	end
	requestFire()
end)
local touchFireConnection = fireButton.Activated:Connect(function()
	if selectedProfile().family ~= "Gun" then
		requestFire()
	end
end)
local touchHeldStart = fireButton.InputBegan:Connect(function(input)
	if
		(input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1)
		and selectedProfile().family == "Gun"
		and touchFireInput == nil
	then
		touchFireInput = input
		triggerStart()
	end
end)
local releaseConnection = UserInputService.InputEnded:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input == touchFireInput
		or input.KeyCode == InputRegistry.Fire.Keyboard
		or input.KeyCode == InputRegistry.Fire.Gamepad
	then
		triggerStop()
	end
end)
local focusReleaseConnection = UserInputService.WindowFocusReleased:Connect(triggerStop)
local touchHeldEnd = fireButton.InputEnded:Connect(function(input)
	if input == touchFireInput then
		triggerStop()
	end
end)
local preferredInputConnection = UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshReticle)
local function updateTouchAimPresentation()
	aimButton.Text = if touchAimToggled then "Aim On" else "Aim"
	aimButton.BackgroundColor3 = if touchAimToggled then Color3.fromRGB(35, 90, 110) else Color3.fromRGB(30, 36, 42)
end
local touchAimConnection = aimButton.Activated:Connect(function()
	local cart = getMountedCart()
	if not cart or MountedAimState.GetCart() ~= cart or not canRequestFire() then
		return
	end
	touchAimToggled = not touchAimToggled
	MountedAimState.SetRequested("Touch", touchAimToggled)
	updateTouchAimPresentation()
end)
local mountedAimConnection = MountedAimState.Changed:Connect(function()
	if not MountedAimState.IsRequested() then
		touchAimToggled = false
	end
	updateTouchAimPresentation()
	if not MountedAimState.IsActive() then
		clearMountedPreview()
	end
end)

-- The cart camera owns Camera+1. Preview reads its final frame and the exact
-- same centre ray that requestFire snapshots fresh at the moment of firing.
RunService:BindToRenderStep(MOUNTED_PREVIEW_STEP, Enum.RenderPriority.Camera.Value + 2, function()
	local cart = getMountedCart()
	local camera = Workspace.CurrentCamera
	if destroyed or not cart or not camera or not MountedAimState.IsActive(cart) or not canRequestFire() then
		clearMountedPreview()
		return
	end
	local muzzle = cart:FindFirstChild("HarpoonOrigin", true)
	local origin = if muzzle and muzzle:IsA("Attachment")
		then muzzle.WorldPosition
		elseif muzzle and muzzle:IsA("BasePart") then muzzle.Position
		else nil
	local snapshot = aimController:GetShotSnapshot(true)
	if not origin or not snapshot then
		clearMountedPreview()
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { cart }
	if player.Character then
		table.insert(excluded, player.Character)
	end
	local ownCart = LocalCartState.GetCart()
	if ownCart and ownCart ~= cart and ownCart:GetAttribute("OwnerUserId") == player.UserId then
		table.insert(excluded, ownCart)
	end
	params.FilterDescendantsInstances, params.IgnoreWater, params.RespectCanCollide = excluded, false, false
	local preview = MountedShotPreview.Resolve(
		origin,
		snapshot.CrosshairRay,
		aimController:GetWeaponProfile().rangeStuds,
		function(start, direction)
			return Workspace:Raycast(start, direction, params)
		end
	)
	if not preview then
		clearMountedPreview()
		return
	end
	local screen, visible = camera:WorldToViewportPoint(preview.Endpoint)
	impactDot.Position, impactDot.Visible = UDim2.fromOffset(screen.X, screen.Y), visible and screen.Z > 0
	impactDot.BackgroundColor3 = if preview.Blocked then Color3.fromRGB(255, 70, 65) else Color3.fromRGB(130, 240, 255)
	impactDot:SetAttribute("Blocked", preview.Blocked)

end)

local function protected(actor: Player?): boolean
	if not actor then
		return true
	end
	local serverNow = Workspace:GetServerTimeNow()
	local deadline = actor:GetAttribute("Phase10ProtectionEnd")
	return actor:GetAttribute("Phase10InCamp") == true
		or actor:GetAttribute("Phase10BeginnerProtected") == true
		or InputPolicy.IsDazed(actor, serverNow)
		or (type(deadline) == "number" and deadline > serverNow)
end

local nextContextUpdate = 0
local contextConnection = RunService.RenderStepped:Connect(function()
	if triggerHeld and not canRequestFire() then
		triggerStop()
	end
	if triggerHeld and selectedProfile().family == "Gun" then
		requestFire()
	end
	if os.clock() < nextContextUpdate then
		return
	end
	nextContextUpdate = os.clock() + 0.1
	refreshReticle() -- Menus, expired deadlines and owner/cart context changes.
	if not reticleGui.Enabled then
		return
	end
	local cart = getMountedCart()
	local selected = aimController:GetCrosshairTarget(cart)
	if not selected then
		targetHighlight.Enabled, targetHighlight.Adornee, targetLabel.Visible = false, nil, false
		for _, arm in reticle:GetChildren() do
			if arm:IsA("Frame") then
				arm.BackgroundColor3 = Color3.new(1, 1, 1)
			end
		end
		return
	end
	local victim = Players:GetPlayerByUserId(selected.PlayerUserId)
	local unavailable = selected.Banked
		or selected.PlayerUserId == player.UserId
		or protected(victim)
		or protected(player)
		or (selected.Kind == "Cargo" and InputPolicy.IsCargoShieldProtected(selected.Model))
	local capacity = if cart then cart:GetAttribute("CargoCapacity") else nil
	local count = if cart then cart:GetAttribute("CargoCount") else nil
	local theft = selected.Kind == "Cargo"
		or selected.Kind == "Held"
		or (victim and type(victim:GetAttribute("CarriedItemId")) == "string")
	local full = theft and cart ~= nil and type(capacity) == "number" and type(count) == "number" and count >= capacity
	local color = if unavailable or full then Color3.fromRGB(255, 216, 77) else Color3.fromRGB(110, 255, 84)
	targetHighlight.Adornee, targetHighlight.OutlineColor, targetHighlight.Enabled =
		require(script.Parent.CreaturePresentationController).ResolveVisual(selected.Model), color, true
	targetLabel.Text, targetLabel.TextColor3, targetLabel.Visible =
		if full
			then "Cargo full"
			elseif unavailable then "Protected"
			elseif selected.Kind == "Player" then "Daze"
			else "Knock loose",
		color,
		true
	for _, arm in reticle:GetChildren() do
		if arm:IsA("Frame") then
			arm.BackgroundColor3 = color
		end
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	if boltConnection then
		boltConnection:Disconnect()
		boltConnection = nil
	end
	for model in bolts do
		destroySleepBolt(model)
	end
	effects:Destroy()
	unbindLauncher()
	disconnectAll(characterConnections)
	sleepBinding:Destroy()
	characterAddedConnection:Disconnect()
	characterRemovingConnection:Disconnect()
	carryConnection:Disconnect()
	cartConnection:Disconnect()
	dazeConnection:Disconnect()
	correctionConnection:Disconnect()
	contextConnection:Disconnect()
	selectedWeaponConnection:Disconnect()
	touchHeldStart:Disconnect()
	touchHeldEnd:Disconnect()
	preferredInputConnection:Disconnect()
	optAddedConnection:Disconnect()
	releaseConnection:Disconnect()
	focusReleaseConnection:Disconnect()
	if optOutConnection then
		optOutConnection:Disconnect()
	end
	closeConsent()
	touchFireConnection:Disconnect()
	touchAimConnection:Disconnect()
	mountedAimConnection:Disconnect()
	MountedAimState.SetRequested("Touch", false)
	RunService:UnbindFromRenderStep(MOUNTED_PREVIEW_STEP)
	clearMountedPreview()
	mountedMouseConnection:Disconnect()
	fireLayoutConnection:Disconnect()
	backpackAddedConnection:Disconnect()
	if backpackConnection then
		backpackConnection:Disconnect()
	end
	aimController:Destroy()
	for tool, previous in launcherLabels do
		if tool.Parent then
			tool.ManualActivationOnly = previous.ManualActivationOnly
			if tool.Name == "Hunting" then
				tool.Name = previous.Name
			end
			if tool.ToolTip == HUNTING_TOOLTIP then
				tool.ToolTip = previous.Tip
			end
		end
	end
	reticleGui:Destroy()
	targetHighlight:Destroy()
	ContextActionService:UnbindAction(ACTION_NAME)
	ContextActionService:UnbindAction(MOUNTED_ACTION)
end)
