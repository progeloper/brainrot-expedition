--!strict

local Presentation = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Presentation.IsSnapshot(value: any): boolean
	return type(value) == "table"
		and finite(value.capacity) and value.capacity % 1 == 0 and value.capacity >= 0 and value.capacity <= 3
		and finite(value.remaining) and value.remaining % 1 == 0 and value.remaining >= 0 and value.remaining <= value.capacity
		and finite(value.protectedUntil) and value.protectedUntil >= 0
		and finite(value.revision) and value.revision >= 0 and value.revision % 1 == 0
		and type(value.lifecycleId) == "string" and value.lifecycleId ~= ""
		and finite(value.cartGeneration) and value.cartGeneration > 0 and value.cartGeneration % 1 == 0
end

function Presentation.Read(cart: Model): any?
	local currentGeneration = cart:GetAttribute("CartGeneration")
	if cart:GetAttribute("ShieldCartGeneration") ~= currentGeneration then return nil end
	local value = {
		capacity = cart:GetAttribute("ShieldCapacity"), remaining = cart:GetAttribute("ShieldRemaining"),
		protectedUntil = cart:GetAttribute("ShieldProtectionExpiresAt"), revision = cart:GetAttribute("ShieldRevision"),
		lifecycleId = cart:GetAttribute("ShieldLifecycleId"), cartGeneration = currentGeneration,
	}
	return if Presentation.IsSnapshot(value) then table.freeze(value) else nil
end

function Presentation.Accept(previous: any?, value: any, cartGeneration: number?): boolean
	if not Presentation.IsSnapshot(value) or value.cartGeneration ~= cartGeneration then return false end
	return not previous or previous.cartGeneration ~= value.cartGeneration
		or previous.lifecycleId ~= value.lifecycleId or value.revision >= previous.revision
end

function Presentation.View(value: any?, now: number): any
	if not value then return { visible = false, active = false, seconds = 0, title = "", status = "" } end
	local seconds = math.max(0, value.protectedUntil - now)
	local active = seconds > 0
	return {
		visible = value.capacity > 0 or active, active = active, seconds = seconds,
		title = "Shield " .. value.remaining .. "/" .. value.capacity,
		status = if active then string.format("Cargo protected · %.1f s", seconds) else "Automatic · refills at your base",
	}
end

function Presentation.SameWindow(expected: any, current: any?): boolean
	return type(expected) == "table" and type(current) == "table"
		and type(expected.lifecycleId) == "string" and expected.lifecycleId ~= ""
		and expected.cartGeneration == current.cartGeneration
		and expected.lifecycleId == current.lifecycleId and expected.protectedUntil == current.protectedUntil
end

function Presentation.PreserveNewerReserve(previous: any?, incoming: any?, sameCart: boolean): any?
	if sameCart and type(previous) == "table" and type(incoming) == "table"
		and previous.lifecycleId == incoming.lifecycleId and finite(previous.revision) and finite(incoming.revision)
		and incoming.revision < previous.revision then return previous end
	return incoming
end

function Presentation.ShouldClearFeedback(value: any?, identity: any?, observed: any, now: number): boolean
	if not identity or not finite(identity.revision) or observed.cartGeneration ~= identity.cartGeneration
		or (observed.lifecycleId ~= nil and observed.lifecycleId ~= identity.lifecycleId)
		or not finite(observed.revision) or observed.revision < identity.revision then return false end
	if value == nil then return true end
	return value.lifecycleId == identity.lifecycleId and value.cartGeneration == identity.cartGeneration
		and value.revision >= identity.revision and value.capacity == 0 and value.protectedUntil <= now
end

function Presentation.Layout(safeSize: Vector2): any
	local width = if safeSize.Y < 340 and safeSize.X < 552 then math.max(96, safeSize.X - 384) else 180
	return {
		Position = UDim2.fromOffset(20, 62), Size = UDim2.fromOffset(width, if width < 160 then 84 else 60),
	}
end

return table.freeze(Presentation)
