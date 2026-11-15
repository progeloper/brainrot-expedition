--!strict
-- Local presentation/request state only. No custody, permissions or transfers.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotInteraction)
local State = {}
State.__index = State

function State.new(sessionId: string)
	return setmetatable({ SessionId = sessionId, Sequence = 0, Pending = nil :: any, ShopPriorityKeys = {}, ShopPressConsumed = false }, State)
end

-- Only the current E/ButtonX cargo/base gesture owns this local Shop priority.
-- It is a UI conflict latch, never custody, permissions or a server input claim.
function State:TrackShopPriorityKey(key: Enum.KeyCode, down: boolean, primary: boolean): boolean
	if key ~= Enum.KeyCode.E and key ~= Enum.KeyCode.ButtonX then return false end
	self.ShopPriorityKeys[key] = if down then true else nil
	if down and (primary or self.Pending ~= nil) then self.ShopPressConsumed = true end
	if not down and next(self.ShopPriorityKeys) == nil then self.ShopPressConsumed = false end
	return true
end

function State:ClearShopPriorityKeys()
	table.clear(self.ShopPriorityKeys)
	self.ShopPressConsumed = false
end

function State:HasShopPriority(primary: boolean): boolean
	return primary or self.Pending ~= nil or self.ShopPressConsumed
end

-- The caller owns a bounded registry of tagged prompts created by Phase13Runtime.
-- Use its existing authored/content overlay so region hiding never captures our
-- local false value as authored; releasing while hidden does not reveal it.
function State.UpdateShopPromptPriority(registry: any, muted: any, suppress: boolean, canRestore: any)
	for prompt, previous in muted do
		if not registry[prompt] or not suppress then
			-- A streamed/untagged instance can be unparented and reused later.
			-- Release our content mask even while it has no current parent.
			if prompt:GetAttribute("BaseContent_Enabled") == false then
				prompt:SetAttribute("BaseContent_Enabled", previous.Content)
			end
			if prompt.Parent then
				if not prompt.Enabled and canRestore(prompt)
					and prompt:GetAttribute("BaseAuthored_Enabled") == true
					and prompt:GetAttribute("BaseContent_Enabled") ~= false then
					prompt.Enabled = true
				end
			end
			muted[prompt] = nil
		end
	end
	if not suppress then return end
	for prompt in registry do
		if prompt.Parent and prompt:IsA("ProximityPrompt")
			and (prompt.Name == "Phase13ShopPrompt" or prompt.Name == "Phase13BaseUpgradePrompt")
			and (prompt.KeyboardKeyCode == Enum.KeyCode.E or prompt.GamepadKeyCode == Enum.KeyCode.ButtonX)
			and prompt:GetAttribute("BaseAuthored_Enabled") == true
			and prompt:GetAttribute("BaseContent_Enabled") ~= false and prompt.Enabled then
			muted[prompt] = { Content = prompt:GetAttribute("BaseContent_Enabled") }
			prompt:SetAttribute("BaseContent_Enabled", false)
			prompt.Enabled = false
		end
	end
end


-- Presentation only. A single selected platform owns this local player's dwell;
-- changing character/target or losing any eligibility discards the elapsed time.
function State:PlatformPromptReady(
	target: any,
	character: any,
	eligible: boolean,
	now: number
): boolean
	if not eligible or target == nil or character == nil then
		self.DwellTarget, self.DwellCharacter, self.DwellSince = nil, nil, nil
		return false
	end
	if self.DwellTarget ~= target or self.DwellCharacter ~= character then
		self.DwellTarget, self.DwellCharacter, self.DwellSince = target, character, now
	end
	return now - self.DwellSince >= Config.PLATFORM_PROMPT_DWELL_SECONDS
end

function State.IsPlatformFront(platformFrame: CFrame, playerPosition: Vector3): boolean
	local offset = playerPosition - platformFrame.Position
	local forward = platformFrame.LookVector
	return Vector3.new(offset.X, 0, offset.Z):Dot(Vector3.new(forward.X, 0, forward.Z)) >= 0
end

local function destroyPlatformView(entry: any)
	entry.PlatformViewSnapshot = nil
	for _, connection in entry.PlatformViewConnections or {} do
		connection:Disconnect()
	end
	entry.PlatformViewConnections = nil
	if entry.PlatformView then
		entry.PlatformView:Destroy()
		entry.PlatformView = nil
	end
end

-- Only base-platform prompts opt into this compact native-prompt view. Cargo,
-- wild pickups and shop prompts retain their existing presentation and timing.
function State.UpdatePlatformView(entry: any, playerGui: Instance, touch: boolean, gamepad: boolean)
	if entry.Kind ~= "Base" or not entry.Prompt then
		return
	end
	local prompt = entry.Prompt
	local view = entry.PlatformView
	-- PlayerGui may be replaced on respawn; never reuse a destroyed view.
	if view and (view.Parent ~= playerGui or not view:FindFirstChild("Action")) then
		destroyPlatformView(entry)
		view = nil
	end
	local enabled = prompt.Enabled and entry.Shown == true
	local actionText, objectText = prompt.ActionText, prompt.ObjectText
	local snapshot = entry.PlatformViewSnapshot
	if
		view
		and snapshot
		and snapshot.View == view
		and snapshot.Prompt == prompt
		and snapshot.Marker == entry.Marker
		and snapshot.Touch == touch
		and snapshot.Gamepad == gamepad
		and snapshot.ActionText == actionText
		and snapshot.ObjectText == objectText
		and snapshot.Enabled == enabled
	then
		-- PromptHidden may immediately hide the owned view between refreshes.
		-- Keep actual visibility responsive even when all presentation inputs match.
		if view.Enabled ~= enabled then
			view.Enabled = enabled
		end
		return
	end
	if not view then
		view = Instance.new("BillboardGui")
		view.Name = "PlatformInteraction"
		view.ResetOnSpawn = false
		entry.PlatformViewConnections = {}
		view.Adornee = entry.Marker
		view.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
		view.AlwaysOnTop = true
		view.Active = true
		view.Enabled = false
		view.Parent = playerGui
		local button = Instance.new("TextButton")
		button.Name, button.Size = "Action", UDim2.fromScale(1, 1)
		button.BackgroundColor3 = Color3.fromRGB(30, 36, 42)
		button.BackgroundTransparency, button.Text = 0.15, ""
		button.Parent = view
		local key = Instance.new("TextLabel")
		key.Name, key.Size = "Key", UDim2.new(0, 32, 1, 0)
		key.BackgroundTransparency, key.TextSize = 1, 22
		key.TextColor3, key.Font = Color3.new(1, 1, 1), Enum.Font.GothamBold
		key.Parent = button
		for _, definition in { { "ActionText", 17, 2 }, { "ObjectText", 14, 25 } } do
			local text = Instance.new("TextLabel")
			text.Name, text.TextSize = definition[1], definition[2]
			text.Position, text.Size = UDim2.fromOffset(34, definition[3]), UDim2.new(1, -38, 0, 21)
			text.BackgroundTransparency, text.TextColor3 = 1, Color3.new(1, 1, 1)
			text.Font, text.TextXAlignment = Enum.Font.Gotham, Enum.TextXAlignment.Left
			text.TextTruncate = Enum.TextTruncate.AtEnd
			text.Parent = button
		end
		table.insert(
			entry.PlatformViewConnections,
			button.InputBegan:Connect(function(input)
				if
					prompt.Enabled
					and (
						input.UserInputType == Enum.UserInputType.Touch
						or input.UserInputType == Enum.UserInputType.MouseButton1
					)
				then
					prompt:InputHoldBegin()
				end
			end)
		)
		table.insert(
			entry.PlatformViewConnections,
			button.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					prompt:InputHoldEnd()
				end
			end)
		)
		entry.PlatformView = view
	end
	view.Size = if touch then UDim2.fromOffset(180, 56) else UDim2.fromOffset(150, 48)
	view.Action.Key.Text = if touch then "•" elseif gamepad then "X" else "E"
	view.Action.ActionText.Text, view.Action.ObjectText.Text = actionText, objectText
	view.Enabled = enabled
	entry.PlatformViewSnapshot = {
		View = view,
		Prompt = prompt,
		Marker = entry.Marker,
		Touch = touch,
		Gamepad = gamepad,
		ActionText = actionText,
		ObjectText = objectText,
		Enabled = enabled,
	}
end

function State:Begin(
	kind: string,
	itemId: string,
	target: any,
	character: Model?,
	carryId: any,
	now: number
): any?
	if self.Pending then
		return nil
	end
	self.ShopPressConsumed = self.ShopPressConsumed or next(self.ShopPriorityKeys) ~= nil
	self.Sequence += 1
	local request = {
		Token = self.SessionId .. ":" .. self.Sequence,
		Kind = kind,
		ItemId = itemId,
		Target = target,
		Character = character,
		CarryId = carryId,
		ExpiresAt = now + Config.REQUEST_TIMEOUT,
	}
	self.Pending = request
	return request
end

function State:Finish(token: string): boolean
	if not self.Pending or self.Pending.Token ~= token then
		return false
	end
	self.Pending = nil
	return true
end

function State:Expire(now: number): boolean
	local pending = self.Pending
	return pending ~= nil and now >= pending.ExpiresAt and self:Finish(pending.Token)
end

function State.CargoAction(carrying: boolean, occupied: boolean, full: boolean): string?
	if carrying then
		return if not occupied then "Cargo" elseif full then "Replace" else nil
	end
	return if occupied then "Pickup" else nil
end

function State.IsPickup(context: any): boolean
	return context.Action == "Pickup"
		or (context.Action == "Base" and context.CarryId == nil and context.Occupant ~= nil)
end

function State.RequestItemId(context: any): string?
	local id = if State.IsPickup(context) then context.Occupant else context.CarryId
	return if type(id) == "string" then id else nil
end

-- Physics-driven CFrame changes do not fire property-change signals. One
-- bounded poll keeps ALL spatial prompts current, including a moving cart
-- approaching a stationary player. Event-driven refreshes remain immediate.
function State.WatchSpatialContext(
	heartbeat: RBXScriptSignal,
	refresh: () -> ()
): RBXScriptConnection
	local elapsed = 0
	return heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			refresh()
		end
	end)
end

function State.Choose(
	candidates: { any },
	previous: any?,
	preferred: Instance?,
	holding: boolean?
): any?
	local best, current, pointed = nil, nil, nil
	for _, candidate in candidates do
		if candidate.Target == preferred then
			pointed = candidate
		end
		if previous and candidate.Target == previous.Target then
			current = candidate
		end
		if
			not best
			or candidate.Distance < best.Distance
			or (
				candidate.Distance == best.Distance
				and (
					if candidate.Cart == best.Cart
							and candidate.SlotIndex
							and best.SlotIndex
						then candidate.SlotIndex < best.SlotIndex
						else candidate.Key < best.Key
				)
			)
		then
			best = candidate
		end
	end
	if current and holding then
		return current
	end
	if pointed then
		return pointed
	end
	if current and best and current.Distance <= best.Distance + Config.SELECTION_HYSTERESIS then
		return current
	end
	return best
end

-- One prompt/activation listener for the life of a stable slot anchor. Contents
-- and Enabled are local presentation updates, not reasons to replace the prompt.
function State.EnsurePrompt(
	entry: any,
	trigger: (any) -> (),
	hold: (any, boolean) -> (),
	shown: (any, boolean) -> ()
)
	if entry.Prompt and entry.Prompt.Parent == entry.Marker then
		return entry.Prompt
	end
	State.RemovePrompt(entry)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlaceCarriedBrainrot"
	prompt.Enabled = false
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Config.PLACEMENT_INTERACT_RADIUS
	prompt.HoldDuration = 0
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.ClickablePrompt = true
	prompt.Style = Enum.ProximityPromptStyle.Custom
	entry.Prompt = prompt
	entry.PromptConnections = {
		prompt.Triggered:Connect(function()
			trigger(entry)
		end),
		prompt.PromptButtonHoldBegan:Connect(function()
			hold(entry, true)
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			hold(entry, false)
		end),
		prompt.PromptShown:Connect(function()
			entry.Shown = true
			shown(entry, true)
		end),
		prompt.PromptHidden:Connect(function()
			entry.Shown = false
			if entry.PlatformView then
				entry.PlatformView.Enabled = false
			end
			shown(entry, false)
		end),
	}
	prompt.Parent = entry.Marker
	return prompt
end

function State.RemovePrompt(entry: any)
	destroyPlatformView(entry)
	for _, connection in entry.PromptConnections or {} do
		connection:Disconnect()
	end
	entry.PromptConnections = nil
	if entry.Prompt then
		entry.Prompt:Destroy()
	end
	entry.Prompt, entry.Shown = nil, false
end

return State
