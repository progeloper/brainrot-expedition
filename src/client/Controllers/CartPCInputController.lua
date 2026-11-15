--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Phase10InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)

local CartInputController = require(script.Parent.CartInputController)
local LocalCartResetState = require(script.Parent.Parent.State.LocalCartResetState)
local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local CartPCInputState = require(script.Parent.Parent.Utility.CartPCInputState)

type PCKey = CartPCInputState.Key
type PCInputSnapshot = CartPCInputState.Snapshot

local log = Logger.new("CartPCInputController")

local CartPCInputController = {}

local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local KEY_BY_CODE: { [Enum.KeyCode]: PCKey } = {
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
}

local player = Players.LocalPlayer
local snapshot: PCInputSnapshot = CartPCInputState.Create()
local observedCart: Model? = nil
local activeCart: Model? = nil
local started = false
local windowFocused = true
local textInputFocused = false
local systemMenuOpen = false
local characterInvalidated = false
local observedCartUnavailable = false
local resetReleaseRequired = false
local cartRevision = 0

local connections: { RBXScriptConnection } = {}
local cartConnections: { RBXScriptConnection } = {}

local function disconnectAll(connectionList: { RBXScriptConnection })
	for _, connection in connectionList do
		connection:Disconnect()
	end

	table.clear(connectionList)
end

local function publishTransition(previous: PCInputSnapshot, nextSnapshot: PCInputSnapshot)
	if
		previous.LongitudinalIntent ~= nextSnapshot.LongitudinalIntent
		or previous.SteeringIntent ~= nextSnapshot.SteeringIntent
	then
		CartInputController.SetKeyboardMovementIntent(nextSnapshot.LongitudinalIntent, nextSnapshot.SteeringIntent)
		log:Debug(
			"Keyboard intent changed Longitudinal=%d Steering=%d",
			nextSnapshot.LongitudinalIntent,
			nextSnapshot.SteeringIntent
		)
	end

	if previous.ResetHeld ~= nextSnapshot.ResetHeld then
		CartInputController.SetKeyboardResetHeld(nextSnapshot.ResetHeld)
		log:Debug("Reset key held changed Held=%s", tostring(nextSnapshot.ResetHeld))
	end
end

local function deactivate(reason: string)
	if not snapshot.Active then
		return
	end

	snapshot = CartPCInputState.Deactivate(snapshot)
	activeCart = nil
	CartInputController.ClearKeyboardMovementInput()
	CartInputController.SetKeyboardResetHeld(false)
	log:Debug("PC cart input deactivated Reason=%s", reason)
end

local function activate(cart: Model, reason: string)
	if snapshot.Active and activeCart == cart then
		return
	end

	if snapshot.Active then
		deactivate("active cart context changed")
	end

	snapshot = CartPCInputState.Activate(snapshot)
	activeCart = cart
	CartInputController.ClearKeyboardMovementInput()
	CartInputController.SetKeyboardResetHeld(false)
	log:Debug(
		"PC cart input activated Cart=%s CartId=%s Reason=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		reason
	)
end

local function isInputSuppressed(): boolean
	return Phase10InputPolicy.IsBlocked(player, GuiService, UserInputService)
		or not windowFocused
		or textInputFocused
		or systemMenuOpen
		or UserInputService:GetFocusedTextBox() ~= nil
end

local function buildActivationContext(): CartPCInputState.ActivationContext
	local cart = observedCart
	local character = player.Character
	local cartAvailable = cart ~= nil and cart.Parent ~= nil and not observedCartUnavailable
	local cartReady = cartAvailable and (cart :: Model):GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) == "Valid"
	local resetSuspended = cartAvailable
		and (
			LocalCartResetState.IsActiveFor(cart)
			or (cart :: Model):GetAttribute(CartResetLifecycle.Attributes.Active) == true
		)

	return {
		ControllerStarted = started,
		PlayerActive = player.Parent == Players,
		CharacterValid = not characterInvalidated and character ~= nil and character.Parent ~= nil,
		CartAvailable = cartAvailable,
		CartReady = cartReady,
		AuthorizedDriver = cart ~= nil and LocalCartState.GetCart() == cart and LocalCartState.IsAuthorizedDriver(),
		ResetSuspended = resetSuspended,
		KeyboardEnabled = UserInputService.KeyboardEnabled,
		InputSuppressed = isInputSuppressed(),
	}
end

local function reconcile(reason: string)
	local cart = observedCart
	local canActivate = CartPCInputState.CanActivate(buildActivationContext())

	if canActivate and cart ~= nil then
		activate(cart, reason)
	else
		deactivate(reason)
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

local function handleInputTransition(key: PCKey, held: boolean)
	local previous = snapshot
	local nextSnapshot, changed = CartPCInputState.SetKey(previous, key, held, previous.ContextRevision)

	if not changed then
		return
	end

	snapshot = nextSnapshot
	publishTransition(previous, nextSnapshot)
end

local function handleInputBegan(input: InputObject, gameProcessedEvent: boolean)
	local key = KEY_BY_CODE[input.KeyCode]

	if key == "R" then
		if resetReleaseRequired then
			return
		end

		resetReleaseRequired = true
	end

	if key == nil or not CartPCInputState.CanProcessInput(snapshot, gameProcessedEvent, isInputSuppressed()) then
		return
	end

	handleInputTransition(key, true)
end

local function handleInputEnded(input: InputObject)
	local key = KEY_BY_CODE[input.KeyCode]

	if key == "R" then
		resetReleaseRequired = false
	end

	if key == nil or not snapshot.Active then
		return
	end

	handleInputTransition(key, false)
end

function CartPCInputController.Start()
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
	resetReleaseRequired = UserInputService:IsKeyDown(Enum.KeyCode.R)
	bindObservedCart(LocalCartState.GetCart())

	table.insert(connections, UserInputService.InputBegan:Connect(handleInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(handleInputEnded))
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

			if not UserInputService:IsKeyDown(Enum.KeyCode.R) then
				resetReleaseRequired = false
			end

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
		UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(function()
			reconcile("keyboard availability changed")
		end)
	)
	table.insert(
		connections,
		CartInputController.InputDeviceChanged:Connect(function(nextDevice)
			if nextDevice == "KeyboardMouse" then
				return
			end

			local clearedSnapshot, changed = CartPCInputState.Clear(snapshot)

			snapshot = clearedSnapshot
			resetReleaseRequired = UserInputService:IsKeyDown(Enum.KeyCode.R)

			if changed then
				log:Debug("PC cart input cleared for active device %s", nextDevice)
			end
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
	log:Debug("PC input controller started")
end

-- Core Loop V2 trip bot (Studio QA only): drive with the same W/A/S/D intents a keyboard produces.
function CartPCInputController._BotInput(key: PCKey, held: boolean)
	if not game:GetService("RunService"):IsStudio() then
		return
	end
	if held and not CartPCInputState.CanProcessInput(snapshot, false, isInputSuppressed()) then
		return
	end
	handleInputTransition(key, held)
end

function CartPCInputController.Stop()
	if not started then
		return
	end

	local wasActive = snapshot.Active

	deactivate("controller stopped")
	started = false
	cartRevision += 1
	disconnectAll(connections)
	disconnectAll(cartConnections)
	observedCart = nil
	activeCart = nil
	windowFocused = true
	textInputFocused = false
	systemMenuOpen = false
	characterInvalidated = false
	observedCartUnavailable = false
	resetReleaseRequired = false
	snapshot = CartPCInputState.Create()

	if not wasActive then
		CartInputController.ClearKeyboardMovementInput()
		CartInputController.SetKeyboardResetHeld(false)
	end

	log:Debug("PC input controller stopped")
end

return CartPCInputController
