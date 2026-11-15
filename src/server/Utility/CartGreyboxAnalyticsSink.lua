--!strict

local MAXIMUM_EVENT_COUNT = 256
local MAXIMUM_RUNTIME_CART_COUNT = 512

export type Payload = { [string]: any }

export type Event = {
	Name: string,
	Payload: Payload,
}

export type Provider = {
	Emit: (self: Provider, eventName: string, payload: Payload) -> (),
}

local events: { Event } = {}
local totalEmittedCount = 0
local runtimeCartIds: { string } = {}
local eventCountsByRuntimeCartId: { [string]: { [string]: number } } = {}

local function recordRuntimeCartEvent(eventName: string, payload: Payload)
	local runtimeCartId = payload.RuntimeCartId

	if type(runtimeCartId) ~= "string" or runtimeCartId == "" then
		return
	end

	local counts = eventCountsByRuntimeCartId[runtimeCartId]

	if counts == nil then
		if #runtimeCartIds >= MAXIMUM_RUNTIME_CART_COUNT then
			local removedRuntimeCartId = table.remove(runtimeCartIds, 1)

			eventCountsByRuntimeCartId[removedRuntimeCartId] = nil
		end

		counts = {}
		eventCountsByRuntimeCartId[runtimeCartId] = counts
		table.insert(runtimeCartIds, runtimeCartId)
	end

	counts[eventName] = (counts[eventName] or 0) + 1
end

local provider: Provider = table.freeze({
	Emit = function(_self: Provider, eventName: string, payload: Payload)
		totalEmittedCount += 1
		recordRuntimeCartEvent(eventName, payload)

		if #events >= MAXIMUM_EVENT_COUNT then
			table.remove(events, 1)
		end

		table.insert(
			events,
			table.freeze({
				Name = eventName,
				Payload = table.freeze(table.clone(payload)),
			})
		)
	end,
}) :: any

local CartGreyboxAnalyticsSink = {}

function CartGreyboxAnalyticsSink.GetProvider(): Provider
	return provider
end

function CartGreyboxAnalyticsSink.GetEvents(): { Event }
	return table.clone(events)
end

function CartGreyboxAnalyticsSink.GetEventCount(): number
	return #events
end

function CartGreyboxAnalyticsSink.GetTotalEmittedCount(): number
	return totalEmittedCount
end

function CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
	runtimeCartId: string,
	eventName: string
): number
	local counts = eventCountsByRuntimeCartId[runtimeCartId]

	return if counts ~= nil then counts[eventName] or 0 else 0
end

function CartGreyboxAnalyticsSink.GetTrackedRuntimeCartCount(): number
	return #runtimeCartIds
end

function CartGreyboxAnalyticsSink.Clear()
	table.clear(events)
	table.clear(runtimeCartIds)
	table.clear(eventCountsByRuntimeCartId)
end

return table.freeze(CartGreyboxAnalyticsSink)
