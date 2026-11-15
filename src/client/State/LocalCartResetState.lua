--!strict

local LocalCartResetState = {}

local changedEvent = Instance.new("BindableEvent")
local activeCart: Model? = nil
local active = false
local revision = 0

LocalCartResetState.Changed = changedEvent.Event

function LocalCartResetState.SetActive(
	cart: Model?,
	nextActive: boolean,
	expectedRevision: number?
): number
	if expectedRevision ~= nil and revision ~= expectedRevision then
		return revision
	end

	if not nextActive and cart ~= nil and activeCart ~= cart then
		return revision
	end

	local previousCart = activeCart
	local nextCart = if nextActive then cart else nil

	if active == nextActive and activeCart == nextCart then
		return revision
	end

	active = nextActive
	activeCart = nextCart
	revision += 1
	changedEvent:Fire(if nextActive then activeCart else cart or previousCart, active, revision)

	return revision
end

function LocalCartResetState.IsActiveFor(cart: Model?): boolean
	return active and cart ~= nil and activeCart == cart
end

function LocalCartResetState.GetRevision(): number
	return revision
end

return LocalCartResetState
