--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)
local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local CartGamepadInputMath = require(ReplicatedStorage.Shared.Utility.CartGamepadInputMath)
local CartGamepadConfigValidator = require(ReplicatedStorage.Shared.Validation.CartGamepadConfigValidator)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Phase10InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)

local CartInputController = require(script.Parent.CartInputController)
local LocalCartResetState = require(script.Parent.Parent.State.LocalCartResetState)
local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local CartGamepadInputState = require(script.Parent.Parent.Utility.CartGamepadInputState)

type GamepadSnapshot = CartGamepadInputState.Snapshot
type PendingDeviceActivationInput = {
	Gamepad: Enum.UserInputType,
	Cart: Model,
	CartRevision: number,
}

local log = Logger.new("CartGamepadInputController")

local CartGamepadInputController = {}

local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local GAMEPAD_TYPES: { [Enum.UserInputType]: boolean } = table.freeze({
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
})

local player = Players.LocalPlayer
local tuning = CartGamepad.Development

local snapshot: GamepadSnapshot = CartGamepadInputState.Create()
local observedCart: Model? = nil
local activeCart: Model? = nil
local activeGamepad: Enum.UserInputType? = nil
local connectedGamepads: { [Enum.UserInputType]: boolean } = {}
local rawLeftStick = Vector2.zero
local rawRightStick = Vector2.zero
local rawLeftTrigger = 0
local started = false
local configValid = false
local windowFocused = true
local textInputFocused = false
local systemMenuOpen = false
local characterInvalidated = false
local observedCartUnavailable = false
local cartRevision = 0
local callbackFailureWarned = false
local callbackDisabled = false
local pendingDeviceActivationInput: PendingDeviceActivationInput? = nil

local connections: { RBXScriptConnection } = {}
local cartConnections: { RBXScriptConnection } = {}

local function disconnectAll(connectionList: { RBXScriptConnection })
	for _, connection in connectionList do
		connection:Disconnect()
	end

	table.clear(connectionList)
end

local function isGamepadType(inputType: Enum.UserInputType): boolean
	return GAMEPAD_TYPES[inputType] == true
end

local function isInputSuppressed(): boolean
	return Phase10InputPolicy.IsBlocked(player, GuiService, UserInputService)
		or not windowFocused
		or textInputFocused
		or systemMenuOpen
		or UserInputService:GetFocusedTextBox() ~= nil
end

local function isGamepadDeviceActive(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

local function clearRawInput()
	rawLeftStick = Vector2.zero
	rawRightStick = Vector2.zero
	rawLeftTrigger = 0
end

local function publishTransition(previous: GamepadSnapshot, nextSnapshot: GamepadSnapshot)
	if
		previous.LongitudinalIntent ~= nextSnapshot.LongitudinalIntent
		or previous.SteeringIntent ~= nextSnapshot.SteeringIntent
	then
		local movementWasActive = previous.LongitudinalIntent ~= 0 or previous.SteeringIntent ~= 0
		local movementIsActive = nextSnapshot.LongitudinalIntent ~= 0 or nextSnapshot.SteeringIntent ~= 0

		CartInputController.SetGamepadMovementIntent(nextSnapshot.LongitudinalIntent, nextSnapshot.SteeringIntent)

		if movementWasActive ~= movementIsActive then
			log:Debug("Gamepad movement intent %s", if movementIsActive then "active" else "neutral")
		end
	end

	if previous.CameraIntent ~= nextSnapshot.CameraIntent then
		local cameraWasActive = previous.CameraIntent ~= Vector2.zero
		local cameraIsActive = nextSnapshot.CameraIntent ~= Vector2.zero

		if nextSnapshot.CameraIntent == Vector2.zero then
			CartInputController.ClearGamepadCameraIntent()
		else
			CartInputController.SetGamepadCameraIntent(nextSnapshot.CameraIntent.X, nextSnapshot.CameraIntent.Y)
		end

		if cameraWasActive ~= cameraIsActive then
			log:Debug("Gamepad camera intent %s", if cameraIsActive then "active" else "cleared")
		end
	end

	if previous.ResetHeld ~= nextSnapshot.ResetHeld then
		CartInputController.SetGamepadResetHeld(nextSnapshot.ResetHeld)
		log:Debug("Gamepad reset held changed Held=%s", tostring(nextSnapshot.ResetHeld))
	end
end

local function clearActiveIntent(reason: string)
	local previous = snapshot
	local nextSnapshot, changed = CartGamepadInputState.Clear(previous)

	clearRawInput()
	snapshot = nextSnapshot

	if changed then
		publishTransition(previous, nextSnapshot)
	else
		CartInputController.ClearGamepadInput()
	end

	if changed then
		log:Debug("Gamepad input neutralised Reason=%s", reason)
	end
end

local function deactivate(reason: string, preservePendingInput: boolean?)
	local wasActive = snapshot.Active

	if not preservePendingInput then
		pendingDeviceActivationInput = nil
	end

	if wasActive then
		snapshot = CartGamepadInputState.Deactivate(snapshot)
	else
		snapshot = CartGamepadInputState.Clear(snapshot)
	end

	clearRawInput()
	activeCart = nil
	CartInputController.ClearGamepadInput()

	if wasActive then
		log:Debug("Gamepad cart input deactivated Reason=%s", reason)
	end
end

local function activate(cart: Model, reason: string)
	if snapshot.Active and activeCart == cart then
		return
	end

	if snapshot.Active then
		deactivate("active cart context changed")
	end

	clearRawInput()
	snapshot = CartGamepadInputState.Activate(snapshot)
	activeCart = cart
	CartInputController.SetInputDevice("Gamepad")
	CartInputController.ClearGamepadInput()
	log:Debug(
		"Gamepad cart input activated Cart=%s CartId=%s Controller=%s Reason=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		if activeGamepad ~= nil then activeGamepad.Name else "none",
		reason
	)
end

local function buildActivationContext(): CartGamepadInputState.ActivationContext
	local cart = observedCart
	local character = player.Character
	local gamepad = activeGamepad
	local cartAvailable = cart ~= nil and cart.Parent ~= nil and not observedCartUnavailable
	local cartReady = cartAvailable and (cart :: Model):GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) == "Valid"
	local resetSuspended = cartAvailable
		and (
			LocalCartResetState.IsActiveFor(cart)
			or (cart :: Model):GetAttribute(CartResetLifecycle.Attributes.Active) == true
		)

	return {
		ControllerStarted = started and configValid and not callbackDisabled,
		PlayerActive = player.Parent == Players,
		CharacterValid = not characterInvalidated and character ~= nil and character.Parent ~= nil,
		CartAvailable = cartAvailable,
		CartReady = cartReady,
		AuthorizedDriver = cart ~= nil and LocalCartState.GetCart() == cart and LocalCartState.IsAuthorizedDriver(),
		ResetSuspended = resetSuspended,
		GamepadConnected = UserInputService.GamepadEnabled and gamepad ~= nil and connectedGamepads[gamepad] == true,
		GamepadDeviceActive = isGamepadDeviceActive(),
		InputSuppressed = isInputSuppressed(),
	}
end

local function reconcile(reason: string, preservePendingInput: boolean?)
	local cart = observedCart
	local canActivate = CartGamepadInputState.CanActivate(buildActivationContext())

	if canActivate and cart ~= nil then
		activate(cart, reason)
	else
		deactivate(reason, preservePendingInput)
	end
end

local function bindObservedCart(cart: Model?)
	if observedCart == cart then
		return
	end

	disconnectAll(cartConnections)
	cartRevision += 1
	observedCart = cart
	observedCartUnavailable = cart == nil or cart.Parent == nil

	if cart == nil then
		return
	end

	local expectedRevision = cartRevision

	local function refresh(reason: string)
		if started and observedCart == cart and cartRevision == expectedRevision then
			reconcile(reason)
		end
	end

	table.insert(
		cartConnections,
		cart:GetAttributeChangedSignal(ASSEMBLY_STATE_ATTRIBUTE):Connect(function()
			refresh("assembly readiness changed")
		end)
	)
	table.insert(
		cartConnections,
		cart:GetAttributeChangedSignal(CartResetLifecycle.Attributes.Active):Connect(function()
			refresh("reset lifecycle changed")
		end)
	)
	table.insert(
		cartConnections,
		cart.AncestryChanged:Connect(function(_, parent)
			if started and observedCart == cart and cartRevision == expectedRevision then
				observedCartUnavailable = parent == nil
				refresh(if parent == nil then "cart removed from hierarchy" else "cart reparented")
			end
		end)
	)
	table.insert(
		cartConnections,
		cart.Destroying:Connect(function()
			if started and observedCart == cart and cartRevision == expectedRevision then
				observedCartUnavailable = true
				deactivate("cart destroyed")
			end
		end)
	)
end

local function selectGamepad(gamepad: Enum.UserInputType, _freshResetPress: boolean)
	if not isGamepadType(gamepad) then
		return
	end

	connectedGamepads[gamepad] = true

	if activeGamepad == gamepad then
		return
	end

	pendingDeviceActivationInput = nil

	if snapshot.Active then
		clearActiveIntent("active controller changed")
	else
		clearRawInput()
	end

	activeGamepad = gamepad
	log:Debug("Active gamepad changed Controller=%s", gamepad.Name)
end

local function chooseConnectedGamepad(): Enum.UserInputType?
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		if isGamepadType(gamepad) then
			connectedGamepads[gamepad] = true
			return gamepad
		end
	end

	return nil
end

local function setProcessedMovement()
    -- Preserve raw stick axes. The shared adapter applies the single radial
    -- deadzone/curve; the old trigger reverse gear is retired.
    local resolved = {LongitudinalIntent=rawLeftStick.Y,SteeringIntent=rawLeftStick.X}

	local previous = snapshot
	local nextSnapshot, changed, updateError = CartGamepadInputState.SetMovementIntent(
		previous,
		resolved.LongitudinalIntent,
		resolved.SteeringIntent,
		previous.ContextRevision
	)

	if updateError ~= nil then
		log:Warn("Gamepad movement state rejected: %s", updateError)
		clearActiveIntent("invalid movement state")
		return
	end

	if changed then
		snapshot = nextSnapshot
		publishTransition(previous, nextSnapshot)
	end
end

local function setProcessedCamera()
	local resolved, resolveError = CartGamepadInputMath.ResolveCamera(rawRightStick, tuning.CameraStickDeadzone)

	if resolved == nil then
		log:Warn("Gamepad camera input rejected: %s", resolveError or "unknown")
		clearActiveIntent("invalid camera input")
		return
	end

	local previous = snapshot
	local nextSnapshot, changed, updateError =
		CartGamepadInputState.SetCameraIntent(previous, resolved, previous.ContextRevision)

	if updateError ~= nil then
		log:Warn("Gamepad camera state rejected: %s", updateError)
		clearActiveIntent("invalid camera state")
		return
	end

	if changed then
		snapshot = nextSnapshot
		publishTransition(previous, nextSnapshot)
	end
end

local function setResetHeld(held: boolean)
	local previous = snapshot
	local nextSnapshot, changed = CartGamepadInputState.SetResetHeld(previous, held, previous.ContextRevision)

	if changed then
		snapshot = nextSnapshot
		publishTransition(previous, nextSnapshot)
	end
end

local function prepareGamepadInput(input: InputObject, gameProcessedEvent: boolean): boolean
	if not isGamepadType(input.UserInputType) then
		return false
	end

	local gamepadChanged = activeGamepad ~= input.UserInputType
	local freshResetPress = input.KeyCode == Enum.KeyCode.DPadDown
		and input.UserInputState == Enum.UserInputState.Begin
		and not gameProcessedEvent
		and not isInputSuppressed()

	selectGamepad(input.UserInputType, freshResetPress)

	local pendingInput: PendingDeviceActivationInput? = nil

	if not isGamepadDeviceActive() then
		local context = buildActivationContext()

		context.GamepadDeviceActive = true

		if
			not gameProcessedEvent
			and not isInputSuppressed()
			and CartGamepadInputState.CanActivate(context)
			and observedCart ~= nil
		then
			pendingInput = {
				Gamepad = input.UserInputType,
				Cart = observedCart,
				CartRevision = cartRevision,
			}
		end
	end

	if gamepadChanged or not snapshot.Active or not isGamepadDeviceActive() then
		reconcile("gamepad input observed", pendingInput ~= nil)
	end

	pendingDeviceActivationInput = pendingInput

	return activeGamepad == input.UserInputType and snapshot.Active and isGamepadDeviceActive()
end

local function handleAnalogueInput(input: InputObject, gameProcessedEvent: boolean)
	if
		input.KeyCode ~= Enum.KeyCode.Thumbstick1
		and input.KeyCode ~= Enum.KeyCode.Thumbstick2
		and input.KeyCode ~= Enum.KeyCode.ButtonL2
	then
		return
	end

	if not prepareGamepadInput(input, gameProcessedEvent) then
		return
	end

	if not CartGamepadInputState.CanProcessInput(snapshot, gameProcessedEvent, isInputSuppressed()) then
		if gameProcessedEvent and snapshot.Active then
			clearActiveIntent("gamepad input processed by another context")
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local nextStick, readError = CartGamepadInputMath.ReadMovementStick(input.Position)

		if nextStick == nil then
			log:Warn("Gamepad movement stick rejected: %s", readError or "unknown")
			clearActiveIntent("invalid movement-stick position")
			return
		end

		rawLeftStick = nextStick
		setProcessedMovement()
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local nextStick, readError = CartGamepadInputMath.ReadCameraStick(input.Position)

		if nextStick == nil then
			log:Warn("Gamepad camera stick rejected: %s", readError or "unknown")
			clearActiveIntent("invalid camera-stick position")
			return
		end

		rawRightStick = nextStick
		setProcessedCamera()
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		local nextTrigger, readError = CartGamepadInputMath.ReadLeftTrigger(input.Position)

		if nextTrigger == nil then
			log:Warn("Gamepad left trigger rejected: %s", readError or "unknown")
			clearActiveIntent("invalid left-trigger position")
			return
		end

		rawLeftTrigger = nextTrigger
		setProcessedMovement()
	end
end

local function handleInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if input.KeyCode == Enum.KeyCode.ButtonL2 then
		handleAnalogueInput(input, gameProcessedEvent)
	end
end

local function handleInputEnded(input: InputObject)
	if not isGamepadType(input.UserInputType) then
		return
	end

	if input.KeyCode == Enum.KeyCode.DPadDown then
		if activeGamepad ~= input.UserInputType then
			return
		end
		setResetHeld(false)
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 and activeGamepad == input.UserInputType then
		rawLeftTrigger = 0

		if snapshot.Active then
			setProcessedMovement()
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 and activeGamepad == input.UserInputType then
		rawLeftStick = Vector2.zero

		if snapshot.Active then
			setProcessedMovement()
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and activeGamepad == input.UserInputType then
		rawRightStick = Vector2.zero

		if snapshot.Active then
			setProcessedCamera()
		end
	end
end

local function applyPendingDeviceActivationInput()
	local pendingInput = pendingDeviceActivationInput

	if pendingInput == nil then
		return
	end

	pendingDeviceActivationInput = nil

	local gamepad = activeGamepad

	if
		not snapshot.Active
		or gamepad == nil
		or not isGamepadDeviceActive()
		or pendingInput.Gamepad ~= gamepad
		or pendingInput.Cart ~= activeCart
		or pendingInput.Cart ~= observedCart
		or pendingInput.CartRevision ~= cartRevision
	then
		return
	end

	local succeeded, inputs = pcall(function()
		return UserInputService:GetGamepadState(gamepad)
	end)

	if not succeeded then
		log:Warn("Active gamepad state could not be sampled after device handoff")
		return
	end

	for _, input in inputs do
		if
			input.KeyCode == Enum.KeyCode.Thumbstick1
			or input.KeyCode == Enum.KeyCode.Thumbstick2
			or input.KeyCode == Enum.KeyCode.ButtonL2
		then
			handleAnalogueInput(input, false)
		elseif
			input.KeyCode == Enum.KeyCode.DPadDown
			and input.UserInputState ~= Enum.UserInputState.End
			and input.UserInputState ~= Enum.UserInputState.Cancel
		then
			handleInputBegan(input, false)
		end
	end
end

local function handleCallback(callback: (...any) -> (), ...: any)
	if callbackDisabled then
		return
	end

	local succeeded, failure = pcall(callback, ...)

	if succeeded then
		callbackFailureWarned = false
		return
	end

	if not callbackFailureWarned then
		callbackFailureWarned = true
		log:Warn("Gamepad input callback failed: %s", tostring(failure))
	end

	callbackDisabled = true
	deactivate("input callback failure")
end

function CartGamepadInputController.Start()
	if started then
		return
	end

	started = true
	table.insert(
		connections,
		player:GetAttributeChangedSignal("Phase10DazeEnd"):Connect(function()
			reconcile("daze changed")
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal("ChariotTeamMenuOpen"):Connect(function()
			reconcile("menu changed")
		end)
	)
	windowFocused = true
	textInputFocused = UserInputService:GetFocusedTextBox() ~= nil
	systemMenuOpen = false
	characterInvalidated = false
	observedCartUnavailable = false
	callbackFailureWarned = false
	callbackDisabled = false
	pendingDeviceActivationInput = nil
	table.clear(connectedGamepads)
	activeGamepad = chooseConnectedGamepad()

	local validation = CartGamepadConfigValidator.Validate(CartGamepad)

	configValid = validation.IsValid

	if not configValid then
		log:Warn("Gamepad configuration invalid: %s", table.concat(validation.Errors, "; "))
		return
	end

	bindObservedCart(LocalCartState.GetCart())

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			handleCallback(handleInputBegan, input, processed)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, processed)
			handleCallback(handleAnalogueInput, input, processed)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			handleCallback(handleInputEnded, input)
		end)
	)
	table.insert(
		connections,
		UserInputService.GamepadConnected:Connect(function(gamepad)
			if isGamepadType(gamepad) then
				connectedGamepads[gamepad] = true

				if activeGamepad == nil then
					selectGamepad(gamepad, false)
				end

				log:Debug("Gamepad connected Controller=%s", gamepad.Name)
				reconcile("gamepad connected")
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.GamepadDisconnected:Connect(function(gamepad)
			connectedGamepads[gamepad] = nil

			if activeGamepad == gamepad then
				deactivate("active gamepad disconnected")
				activeGamepad = chooseConnectedGamepad()
			end

			log:Debug("Gamepad disconnected Controller=%s", gamepad.Name)
			reconcile("gamepad disconnected")
		end)
	)
	table.insert(
		connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType)
			if isGamepadType(inputType) then
				selectGamepad(inputType, false)
			end

			local pendingInput = pendingDeviceActivationInput
			local preservePendingInput = pendingInput ~= nil
				and isGamepadType(inputType)
				and inputType == pendingInput.Gamepad
				and not isGamepadDeviceActive()
				and pendingInput.Gamepad == activeGamepad

			reconcile("last input type changed", preservePendingInput)
		end)
	)
	table.insert(
		connections,
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			reconcile("preferred input changed")

			if isGamepadDeviceActive() then
				applyPendingDeviceActivationInput()
			else
				pendingDeviceActivationInput = nil
			end
		end)
	)
	table.insert(
		connections,
		UserInputService:GetPropertyChangedSignal("GamepadEnabled"):Connect(function()
			if not UserInputService.GamepadEnabled then
				deactivate("gamepad input unavailable")
			end

			reconcile("gamepad availability changed")
		end)
	)
	table.insert(
		connections,
		CartInputController.InputDeviceChanged:Connect(function(nextDevice)
			if nextDevice ~= "Gamepad" then
				pendingDeviceActivationInput = nil
				deactivate("shared input device changed")
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			windowFocused = false
			reconcile("application focus lost")
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocused:Connect(function()
			windowFocused = true
			reconcile("application focus restored")
		end)
	)
	table.insert(
		connections,
		UserInputService.TextBoxFocused:Connect(function()
			textInputFocused = true
			reconcile("text input focused")
		end)
	)
	table.insert(
		connections,
		UserInputService.TextBoxFocusReleased:Connect(function()
			textInputFocused = false
			reconcile("text input released")
		end)
	)
	table.insert(
		connections,
		GuiService.MenuOpened:Connect(function()
			systemMenuOpen = true
			reconcile("system menu opened")
		end)
	)
	table.insert(
		connections,
		GuiService.MenuClosed:Connect(function()
			systemMenuOpen = false
			reconcile("system menu closed")
		end)
	)
	table.insert(
		connections,
		LocalCartState.Changed:Connect(function(cart)
			bindObservedCart(cart)
			reconcile("authoritative driver state changed")
		end)
	)
	table.insert(
		connections,
		LocalCartResetState.Changed:Connect(function(cart)
			if cart == nil or cart == observedCart then
				reconcile("local reset suspension changed")
			end
		end)
	)
	table.insert(
		connections,
		player.CharacterAdded:Connect(function()
			characterInvalidated = false
			reconcile("local character added")
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			characterInvalidated = true
			reconcile("local character removing")
		end)
	)
	table.insert(
		connections,
		player.AncestryChanged:Connect(function(_, parent)
			if parent ~= Players then
				deactivate("local player removed")
			end
		end)
	)

	reconcile("controller started")
	log:Debug("Gamepad input controller started")
end

function CartGamepadInputController.Stop()
	if not started then
		return
	end

	deactivate("controller stopped")
	started = false
	configValid = false
	cartRevision += 1
	disconnectAll(connections)
	disconnectAll(cartConnections)
	observedCart = nil
	activeCart = nil
	activeGamepad = nil
	table.clear(connectedGamepads)
	clearRawInput()
	windowFocused = true
	textInputFocused = false
	systemMenuOpen = false
	characterInvalidated = false
	observedCartUnavailable = false
	callbackFailureWarned = false
	callbackDisabled = false
	pendingDeviceActivationInput = nil
	snapshot = CartGamepadInputState.Create()
	CartInputController.ClearGamepadInput()
	log:Debug("Gamepad input controller stopped")
end

return CartGamepadInputController
