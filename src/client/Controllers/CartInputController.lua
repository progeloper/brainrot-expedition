--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Phase10InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local MountedAimState = require(script.Parent.Parent.State.MountedAimState)

local HandlingMath = require(ReplicatedStorage.Shared.Utility.CartHandlingMath)
local Handling = require(ReplicatedStorage.Shared.Config.CartHandlingConfig)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)
local CartGamepadInputMath = require(ReplicatedStorage.Shared.Utility.CartGamepadInputMath)
local InputRegistry = require(ReplicatedStorage.Shared.Config.CartInputRegistry)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("CartInputController")

type InputDevice = CartMovementTypes.InputDevice
export type CartInputState = CartMovementTypes.CartInputState

local CartInputController = {}
local resetHeldChangedEvent = Instance.new("BindableEvent")
local inputDeviceChangedEvent = Instance.new("BindableEvent")
local KEYBOARD_RESET_SOURCE = "PCKeyboardReset"
local GAMEPAD_RESET_SOURCE = "GamepadReset"
local MOUSE_AIM_SOURCE = "MouseAim"
local GAMEPAD_AIM_SOURCE = "GamepadAim"

local state: CartInputState = {
	Throttle = 0,
	Steering = 0,
	Brake = false,
	ResetHeld = false,
	InputDevice = "KeyboardMouse",
}

local connections: { RBXScriptConnection } = {}
local gamepadCamera = Vector2.zero
local pointerCamera = Vector2.zero
local rightMouseHeld = false
local resetGui: ScreenGui? = nil
local resetButton: TextButton? = nil
local resetFeedback: TextLabel? = nil
local resetVisible = false
local resetEnabled = false
local resetDisplayedText = "Hold Reset"
local resetSources: { [any]: boolean } = {}
local controlModule: any = nil
local cameraOrbitEnabled = false
local pcCameraOrbitEnabled = false
local gamepadCameraOrbitEnabled = false
local cameraTouch: InputObject? = nil
local aimTouch: InputObject? = nil
local windowFocused = true
local started = false
local generation = 0
local needsFreshGesture = true
local lastCameraForward = Vector3.new(0,0,-1)

CartInputController.ResetHeldChanged = resetHeldChangedEvent.Event
CartInputController.InputDeviceChanged = inputDeviceChangedEvent.Event

local function setResetHeld(held: boolean)
	if state.ResetHeld == held then
		return
	end

	state.ResetHeld = held
	resetHeldChangedEvent:Fire(held)
end

local function setResetSource(source: any, held: boolean)
	if held then
		resetSources[source] = true
	else
		resetSources[source] = nil
	end

	setResetHeld(next(resetSources) ~= nil)
end

local function isInputDevice(value: unknown): boolean
	return value == "KeyboardMouse" or value == "Touch" or value == "Gamepad"
end

function CartInputController.SetInputDevice(device: InputDevice): boolean
	if not isInputDevice(device) or state.InputDevice == device then
		return false
	end

	local previousDevice = state.InputDevice

	state.Throttle = 0
	state.Steering = 0
	state.Brake = false
	gamepadCamera = Vector2.zero
	pointerCamera = Vector2.zero
	rightMouseHeld = false
	cameraTouch = nil
	aimTouch = nil
	MountedAimState.ClearRequested()
	table.clear(resetSources)
	setResetHeld(false)
	state.InputDevice = device
	inputDeviceChangedEvent:Fire(device, previousDevice)
	log:Debug("Input device changed from %s to %s", previousDevice, device)

	return true
end

local function loadControlModule(expectedGeneration: number)
	task.spawn(function()
		local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 15)
		local playerModule = playerScripts and playerScripts:WaitForChild("PlayerModule", 15)

		if playerModule == nil or not playerModule:IsA("ModuleScript") then
			return
		end

		local success, module = pcall(require, playerModule)

		if success and started and generation == expectedGeneration then
			controlModule = (module :: any):GetControls()
		end
	end)
end

local function getTouchMove(): Vector2
	if controlModule == nil then
		return Vector2.zero
	end

	local ok, move = pcall(function() return controlModule:GetMoveVector() end)
	if not ok or not HandlingMath.FiniteVector(move) then return Vector2.zero end
	return Vector2.new(move.X, -move.Z)
end

-- Raw adapter axes are camera-local: +X right, +Y forward. Touch reads the
-- active PlayerModule; keyboard/gamepad use the existing input adapters.
local function rawMove(): Vector2
    if state.InputDevice == "Touch" then return getTouchMove() end
    return Vector2.new(state.Steering,state.Throttle)
end
local function eligibleMove(): Vector2
    local blocked = not windowFocused or Phase10InputPolicy.IsBlocked(Players.LocalPlayer,GuiService,UserInputService)
    local raw = rawMove()
    local result
    result,needsFreshGesture=HandlingMath.GestureGate(raw,needsFreshGesture,blocked)
    return result
end
function CartInputController.GetState(): CartInputState
    local raw=eligibleMove()
    return {Throttle=raw.Y,Steering=raw.X,Brake=raw.Magnitude<=Handling.Deadzone,
        ResetHeld=state.ResetHeld,InputDevice=state.InputDevice}
end
function CartInputController.GetWorldIntent(): (Vector3,number)
    local camera=workspace.CurrentCamera
    local direction,magnitude,forward=HandlingMath.WorldIntent(eligibleMove(),if camera then camera.CFrame.LookVector else lastCameraForward,lastCameraForward)
    lastCameraForward=forward
    return direction,magnitude
end
function CartInputController.IsMovementIntentActive(): boolean
    return eligibleMove().Magnitude>Handling.Deadzone
end
function CartInputController.IsWindowFocused(): boolean return windowFocused end

local function isNormalizedIntent(value: number): boolean
	return value == -1 or value == 0 or value == 1
end

local function isFiniteAnalogueIntent(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge and value >= -1 and value <= 1
end

function CartInputController.SetKeyboardMovementIntent(longitudinalIntent: number, steeringIntent: number): boolean
	if not isNormalizedIntent(longitudinalIntent) or not isNormalizedIntent(steeringIntent) then
		log:Warn(
			"Rejected non-normalized keyboard intent Longitudinal=%s Steering=%s",
			tostring(longitudinalIntent),
			tostring(steeringIntent)
		)
		return false
	end

	local changed = state.InputDevice ~= "KeyboardMouse"
		or state.Throttle ~= longitudinalIntent
		or state.Steering ~= steeringIntent

	CartInputController.SetInputDevice("KeyboardMouse")
	state.Throttle = longitudinalIntent
	state.Steering = steeringIntent
	state.Brake = longitudinalIntent < 0

	return changed
end

function CartInputController.SetKeyboardResetHeld(held: boolean): boolean
	if held and not resetEnabled then
		return false
	end

	local previous = state.ResetHeld

	if held then
		CartInputController.SetInputDevice("KeyboardMouse")
	end

	setResetSource(KEYBOARD_RESET_SOURCE, held)

	return state.ResetHeld ~= previous
end

function CartInputController.ClearKeyboardMovementInput(): boolean
	if state.InputDevice ~= "KeyboardMouse" then
		return false
	end

	local changed = state.Throttle ~= 0 or state.Steering ~= 0 or state.Brake

	state.Throttle = 0
	state.Steering = 0
	state.Brake = false

	return changed
end

function CartInputController.SetGamepadMovementIntent(longitudinalIntent: number, steeringIntent: number): boolean
	if not isFiniteAnalogueIntent(longitudinalIntent) or not isFiniteAnalogueIntent(steeringIntent) then
		log:Warn(
			"Rejected invalid gamepad intent Longitudinal=%s Steering=%s",
			tostring(longitudinalIntent),
			tostring(steeringIntent)
		)
		return false
	end

	local deviceChanged = CartInputController.SetInputDevice("Gamepad")
	local changed = deviceChanged or state.Throttle ~= longitudinalIntent or state.Steering ~= steeringIntent

	state.Throttle = longitudinalIntent
	state.Steering = steeringIntent
	state.Brake = longitudinalIntent < 0

	return changed
end

function CartInputController.ClearGamepadMovementInput(): boolean
	if state.InputDevice ~= "Gamepad" then
		return false
	end

	local changed = state.Throttle ~= 0 or state.Steering ~= 0 or state.Brake

	state.Throttle = 0
	state.Steering = 0
	state.Brake = false

	return changed
end

function CartInputController.SetGamepadCameraIntent(yawIntent: number, pitchIntent: number): boolean
	if not isFiniteAnalogueIntent(yawIntent) or not isFiniteAnalogueIntent(pitchIntent) then
		log:Warn("Rejected invalid gamepad camera intent Yaw=%s Pitch=%s", tostring(yawIntent), tostring(pitchIntent))
		return false
	end

	if yawIntent == 0 and pitchIntent == 0 then
		return CartInputController.ClearGamepadCameraIntent()
	end

	local deviceChanged = CartInputController.SetInputDevice("Gamepad")
	local nextIntent = Vector2.new(yawIntent, pitchIntent)
	local changed = deviceChanged or gamepadCamera ~= nextIntent

	gamepadCamera = nextIntent

	return changed
end

function CartInputController.GetGamepadCameraIntent(): Vector2
	return if gamepadCameraOrbitEnabled then gamepadCamera else Vector2.zero
end

function CartInputController.ClearGamepadCameraIntent(): boolean
	local changed = gamepadCamera ~= Vector2.zero

	gamepadCamera = Vector2.zero

	return changed
end

function CartInputController.SetGamepadCameraOrbitEnabled(enabled: boolean)
	if gamepadCameraOrbitEnabled == enabled then
		return
	end

	gamepadCameraOrbitEnabled = enabled
end

function CartInputController.SetGamepadResetHeld(held: boolean): boolean
	if held and not resetEnabled then
		return false
	end

	local previous = state.ResetHeld

	if held then
		CartInputController.SetInputDevice("Gamepad")
	end

	setResetSource(GAMEPAD_RESET_SOURCE, held)

	return state.ResetHeld ~= previous
end

function CartInputController.ClearGamepadInput(): boolean
	local movementChanged = CartInputController.ClearGamepadMovementInput()
	local cameraChanged = CartInputController.ClearGamepadCameraIntent()
	local resetChanged = CartInputController.SetGamepadResetHeld(false)

	return movementChanged or cameraChanged or resetChanged
end

function CartInputController.ClearMovementInput()
	needsFreshGesture = true
	state.Throttle = 0
	state.Steering = 0
	state.Brake = false
end

function CartInputController.GetInputDevice(): InputDevice
	return state.InputDevice
end

function CartInputController.IsResetHeld(): boolean
	return state.ResetHeld
end

function CartInputController.ConsumeCameraOrbit(): Vector2
	local result = pointerCamera

	pointerCamera = Vector2.zero

	return result
end

function CartInputController.ConsumePCCameraOrbit(): Vector2
	local result = pointerCamera

	pointerCamera = Vector2.zero

	return result
end

function CartInputController.SetCameraOrbitEnabled(enabled: boolean)
	cameraOrbitEnabled = enabled
	pointerCamera = Vector2.zero
	cameraTouch = nil

	if not enabled then
		rightMouseHeld = false
	end
end

function CartInputController.SetPCCameraOrbitEnabled(enabled: boolean)
	if pcCameraOrbitEnabled == enabled then
		return
	end

	pcCameraOrbitEnabled = enabled
	pointerCamera = Vector2.zero
	rightMouseHeld = false
end

function CartInputController.SetResetVisible(visible: boolean)
	resetVisible = visible

	if resetButton ~= nil then
		resetButton.Visible = visible
	end

	if resetFeedback ~= nil then
		resetFeedback.Visible = visible and resetDisplayedText ~= "Hold Reset"
	end
end

function CartInputController.SetResetEnabled(enabled: boolean)
	resetEnabled = enabled

	if not enabled then
		table.clear(resetSources)
		setResetHeld(false)
	end
end

function CartInputController.SetResetFeedback(text: string, progress: number)
	local displayedText = if progress > 0 then string.format("%s %d%%", text, math.floor(progress * 100)) else text

	resetDisplayedText = displayedText

	if resetButton ~= nil then
		resetButton.Text = displayedText
	end

	if resetFeedback ~= nil then
		resetFeedback.Text = displayedText
		resetFeedback.Visible = resetVisible and displayedText ~= "Hold Reset"
	end
end

function CartInputController.Start()
	if started then
		return
	end

	started = true
	generation += 1
	local expectedGeneration = generation
	windowFocused = true

	local function reconcilePreferredInput()
		local preferred = UserInputService.PreferredInput
		CartInputController.SetInputDevice(if preferred == Enum.PreferredInput.Touch then "Touch"
			elseif preferred == Enum.PreferredInput.Gamepad then "Gamepad" else "KeyboardMouse")
	end
	reconcilePreferredInput()
	table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(reconcilePreferredInput))

	local function canAim(): boolean
		return windowFocused
			and MountedAimState.GetCart() ~= nil
			and not Phase10InputPolicy.IsBlocked(Players.LocalPlayer, GuiService, UserInputService)
	end

	local function clearAim()
		aimTouch = nil
		MountedAimState.ClearRequested()
	end

	local function setAimStick(position: Vector3)
		local value = Vector2.new(position.X, position.Y)
		local look = CartGamepadInputMath.ApplyRadialDeadzone(value, CartGamepad.Development.CameraStickDeadzone) or Vector2.zero
		if look ~= Vector2.zero then
			CartInputController.SetInputDevice("Gamepad")
		end
		MountedAimState.SetGamepadLook(look)
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch then
				CartInputController.SetInputDevice("Touch")
			end

			if processed then
				return
			end

			if input.UserInputType == InputRegistry.Aim.Mouse then
				if canAim() and not Phase10InputPolicy.IsPointerInteraction(Players.LocalPlayer, Vector2.new(input.Position.X, input.Position.Y)) then
					CartInputController.SetInputDevice("KeyboardMouse")
					MountedAimState.SetRequested(MOUSE_AIM_SOURCE, true)
				end
				rightMouseHeld = pcCameraOrbitEnabled
			elseif input.KeyCode == InputRegistry.Aim.Gamepad then
				if canAim() then
					CartInputController.SetInputDevice("Gamepad")
					MountedAimState.SetRequested(GAMEPAD_AIM_SOURCE, true)
					MountedAimState.SetGamepadLook(Vector2.zero)
					-- A stationary held stick emits no new InputChanged on Aim reentry.
					for _, held in UserInputService:GetGamepadState(input.UserInputType) do
						if held.KeyCode == Enum.KeyCode.Thumbstick2 then
							setAimStick(held.Position)
							break
						end
					end
				end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				if
					canAim()
					and MountedAimState.IsRequested()
					and workspace.CurrentCamera ~= nil
					and input.Position.X > workspace.CurrentCamera.ViewportSize.X * 0.5
					and not Phase10InputPolicy.IsPointerInteraction(Players.LocalPlayer, Vector2.new(input.Position.X, input.Position.Y))
				then
					aimTouch = input
				end
				if
					cameraOrbitEnabled
					and cameraTouch == nil
					and aimTouch ~= input
					and not Phase10InputPolicy.IsPointerInteraction(Players.LocalPlayer, Vector2.new(input.Position.X, input.Position.Y))
					and workspace.CurrentCamera ~= nil
					and input.Position.X > workspace.CurrentCamera.ViewportSize.X * 0.5
				then
					cameraTouch = input
				end
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == InputRegistry.Aim.Mouse then
				rightMouseHeld = false
				MountedAimState.SetRequested(MOUSE_AIM_SOURCE, false)
			elseif input.KeyCode == InputRegistry.Aim.Gamepad then
				MountedAimState.SetRequested(GAMEPAD_AIM_SOURCE, false)
			elseif input == cameraTouch then
				cameraTouch = nil
			end
			if input == aimTouch then
				aimTouch = nil
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if canAim() then
				if input.KeyCode == Enum.KeyCode.Thumbstick2 then
					-- Read raw aiming independently from the cruise-camera adapter.
					setAimStick(input.Position)
				elseif MountedAimState.IsRequested() or MountedAimState.IsActive() then
					if input.UserInputType == Enum.UserInputType.MouseMovement or input == aimTouch then
						MountedAimState.AddPointerDelta(Vector2.new(input.Delta.X, input.Delta.Y))
					end
				end
			end
			if pcCameraOrbitEnabled and input.UserInputType == Enum.UserInputType.MouseMovement then
				if processed then
					pointerCamera = Vector2.zero
					rightMouseHeld = false
				elseif rightMouseHeld then
					CartInputController.SetInputDevice("KeyboardMouse")
					pointerCamera += Vector2.new(input.Delta.X, input.Delta.Y)
				end
			elseif cameraOrbitEnabled and input == cameraTouch then
				CartInputController.SetInputDevice("Touch")
				pointerCamera += Vector2.new(input.Delta.X, input.Delta.Y)
			end
		end)
	)

	table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
		windowFocused = false
		needsFreshGesture = true
		state.Throttle, state.Steering, state.Brake = 0, 0, false
		cameraTouch = nil
		pointerCamera = Vector2.zero
		clearAim()
	end))
	table.insert(connections, UserInputService.WindowFocused:Connect(function()
		windowFocused = true
		reconcilePreferredInput()
	end))
	table.insert(connections, UserInputService.GamepadDisconnected:Connect(function()
		MountedAimState.SetRequested(GAMEPAD_AIM_SOURCE, false)
		MountedAimState.SetGamepadLook(Vector2.zero)
	end))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if not canAim() then
			clearAim()
		end
	end))

	loadControlModule(expectedGeneration)
	log:Info("Input controller started")
end

function CartInputController.Stop()
	if not started then
		return
	end

	started = false
	generation += 1

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)

	gamepadCamera = Vector2.zero
	pointerCamera = Vector2.zero
	rightMouseHeld = false
	cameraOrbitEnabled = false
	pcCameraOrbitEnabled = false
	gamepadCameraOrbitEnabled = false
	cameraTouch = nil
	aimTouch = nil
	MountedAimState.ClearRequested()
	controlModule = nil
	state.Throttle = 0
	state.Steering = 0
	state.Brake = false
	table.clear(resetSources)
	setResetHeld(false)
	CartInputController.SetInputDevice("KeyboardMouse")
	resetVisible = false
	resetEnabled = false
	resetDisplayedText = "Hold Reset"

	if resetGui ~= nil then
		resetGui:Destroy()
		resetGui = nil
		resetButton = nil
		resetFeedback = nil
	end

	log:Info("Input controller stopped")
end

return CartInputController
