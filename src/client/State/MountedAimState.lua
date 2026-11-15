--!strict

-- Local mounted-view intent only. The camera owns the seat context and whether
-- its aiming view is active; this state grants no firing or vehicle authority.
local function new()
	local changed = Instance.new("BindableEvent")
	local context: Model? = nil
	local activeCart: Model? = nil
	local requested: { [string]: boolean } = {}
	local pointerDelta = Vector2.zero
	local gamepadLook = Vector2.zero
	local state = { Changed = changed.Event }

	local function isRequested(): boolean
		return context ~= nil and next(requested) ~= nil
	end

	function state.GetCart(): Model?
		return context
	end

	function state.SetContext(cart: Model?)
		if context == cart then
			return
		end
		context = cart
		activeCart = nil
		table.clear(requested)
		pointerDelta, gamepadLook = Vector2.zero, Vector2.zero
		changed:Fire()
	end

	function state.SetRequested(source: string, held: boolean)
		local previous = isRequested()
		if held and context ~= nil then
			requested[source] = true
		else
			requested[source] = nil
		end
		if previous ~= isRequested() then
			pointerDelta = Vector2.zero
			changed:Fire()
		end
	end

	state.IsRequested = isRequested

	function state.ClearRequested()
		local previous = isRequested()
		table.clear(requested)
		pointerDelta, gamepadLook = Vector2.zero, Vector2.zero
		if previous then
			changed:Fire()
		end
	end

	function state.SetActive(cart: Model?, active: boolean)
		if active and (cart == nil or cart ~= context) then
			return
		end
		if not active and cart ~= nil and activeCart ~= cart then
			return
		end
		local nextCart = if active then cart else nil
		if activeCart ~= nextCart then
			activeCart = nextCart
			changed:Fire()
		end
	end

	function state.IsActive(cart: Model?): boolean
		return activeCart ~= nil and (cart == nil or activeCart == cart)
	end

	function state.AddPointerDelta(delta: Vector2)
		if context ~= nil then
			pointerDelta += delta
		end
	end

	function state.ConsumePointerDelta(): Vector2
		local result = pointerDelta
		pointerDelta = Vector2.zero
		return result
	end

	function state.SetGamepadLook(value: Vector2)
		gamepadLook = if context ~= nil then value else Vector2.zero
	end

	function state.GetGamepadLook(): Vector2
		return gamepadLook
	end

	function state.ClearLook()
		pointerDelta, gamepadLook = Vector2.zero, Vector2.zero
	end

	function state.Destroy()
		context, activeCart = nil, nil
		table.clear(requested)
		state.ClearLook()
		changed:Destroy()
	end

	return state
end

local MountedAimState = new()
MountedAimState.new = new

return MountedAimState
