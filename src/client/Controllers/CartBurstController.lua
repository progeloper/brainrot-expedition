--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Registry = require(ReplicatedStorage.Shared.Config.CartInputRegistry)
local Policy = require(ReplicatedStorage.Shared.Utility.CartBurstInputPolicy)
local Phase10InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local CartInput = require(script.Parent.CartInputController)
local LocalReset = require(script.Parent.Parent.State.LocalCartResetState)
local LocalCart = require(script.Parent.Parent.State.LocalCartState)

local Controller = {}
local player = Players.LocalPlayer
local started = false
local sequence = 0
local windowFocused = true
local held = false
local brakeStopSent = false
local connections: { RBXScriptConnection } = {}
local gui: ScreenGui? = nil
local panel: Frame? = nil
local button: TextButton? = nil
local safeArea: Frame? = nil

local function context(): any
	local cart = LocalCart.GetCart()
	return {
		FeatureEnabled = started and FeatureFlags.EquippedTeamsEnabled,
		AuthorizedDriver = LocalCart.IsAuthorizedDriver(),
		CartAlive = cart ~= nil and cart.Parent ~= nil,
		WindowFocused = windowFocused,
		TextFocused = UserInputService:GetFocusedTextBox() ~= nil,
		SystemMenuOpen = GuiService.MenuIsOpen,
		TeamMenuOpen = Phase10InputPolicy.IsBlocked(player, GuiService, UserInputService),
		ResetActive = LocalReset.IsActiveFor(cart) or (cart ~= nil and cart:GetAttribute("ResetActive") == true),
	}
end

local function request(action: string)
	if not Policy.CanActivate(context()) then
		return
	end
	local cart = LocalCart.GetCart()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("CartBurstRequest")
	if not cart or not remote or not remote:IsA("RemoteEvent") then
		return
	end
	local generation = cart:GetAttribute("CartGeneration")
	if type(generation) ~= "number" then
		return
	end
	sequence += 1
	remote:FireServer({ cart = cart, generation = generation, sequence = sequence, action = action })
end

local function update()
	if not panel or not button then
		return
	end
	local cart = LocalCart.GetCart()
	local capacity = cart and cart:GetAttribute("BurstCapacity")
	local allowed = Policy.CanActivate(context()) and type(capacity) == "number" and capacity > 0
	panel.Visible = allowed
	local u = require(script.Parent.ExactHudController).GetUnit()
	local fixed = require(ReplicatedStorage.Shared.Config.PlaytestExact).Hud
	panel.Size = UDim2.fromOffset(fixed.BurstSize * u, fixed.BurstSize * u)
	if not allowed then
		brakeStopSent = false
		return
	end
	local active = cart:GetAttribute("BurstActive") == true
	local eligible = cart:GetAttribute("BurstRechargeEligibleAt")
	local left = if type(eligible) == "number" then math.max(0, eligible - Workspace:GetServerTimeNow()) else 0
	button.Text = if left > 0 then string.format("Burst\n%.1fs", left) else if active then "Stop\nBurst" else "Burst"
	local energy = cart:GetAttribute("BurstEnergy") or 0
	button.Active = active or energy >= 0.25
	button.Selectable = button.Active
	local braking = CartInput.GetState().Brake
	if active and braking and not brakeStopSent then
		brakeStopSent = true
		request("Stop")
	end
	if not active or not braking then
		brakeStopSent = false
	end
end
local function createHud()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local C = require(ReplicatedStorage.Shared.Config.PlaytestExact).Hud
	gui = Instance.new("ScreenGui")
	gui.Name = "CartBurstGui"
	require(script.Parent.Parent.UI.StudPopUI).skin(gui, { hints = { SafeArea = "plain" }, windowDepth = 0 })
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 20
	gui.Parent = pg
	safeArea = Instance.new("Frame")
	safeArea.Name = "SafeArea"
	safeArea.Size = UDim2.fromScale(1, 1)
	safeArea.BackgroundTransparency = 1
	safeArea.Parent = gui
	panel = Instance.new("Frame")
	panel.Name = "BurstPanel"
	panel.AnchorPoint = Vector2.one
	panel.Position = UDim2.new(1, -C.Top, 1, -218)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = safeArea
	button = Instance.new("TextButton")
	button.Name = "Burst"
	button.Size = UDim2.fromScale(1, 1)
	button.Font = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig).Typography.Font
	button.TextSize = C.StatusText
	button.TextScaled = false
	button.TextStrokeTransparency = 1
	button.TextColor3 = C.Text
	button.BackgroundColor3 = C.Background
	button.BackgroundTransparency = C.Transparency
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, C.Corner)
	corner.Parent = button
	table.insert(
		connections,
		button.Activated:Connect(function()
			request("Toggle")
		end)
	)
end

function Controller.Start()
	if started or not FeatureFlags.EquippedTeamsEnabled then
		return
	end
	started = true
	createHud()
	ContextActionService:BindAction(Registry.Burst.Name, function(_, inputState)
		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			held = false
			return Enum.ContextActionResult.Pass
		end
		if not Policy.CanActivate(context()) then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin and not held then
			held = true
			request("Toggle")
		end
		return Enum.ContextActionResult.Sink
	end, false, Registry.Burst.Keyboard, Registry.Burst.Gamepad)
	table.insert(
		connections,
		UserInputService.WindowFocused:Connect(function()
			windowFocused = true
			update()
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			windowFocused = false
			held = false
			update()
		end)
	)
	table.insert(connections, LocalCart.Changed:Connect(update))
	table.insert(connections, CartInput.InputDeviceChanged:Connect(update))
	table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(update))
	table.insert(connections, player:GetAttributeChangedSignal("ChariotTeamMenuOpen"):Connect(update))
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then
				return
			end
			elapsed = 0
			if not gui then
				createHud()
			end
			update()
		end)
	)
	update()
end

function Controller.Stop()
	if not started then
		return
	end
	request("Stop")
	started = false
	ContextActionService:UnbindAction(Registry.Burst.Name)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
	gui, panel, button, safeArea = nil, nil, nil, nil
	held = false
end

return Controller
