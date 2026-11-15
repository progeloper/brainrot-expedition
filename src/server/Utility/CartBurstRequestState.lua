--!strict

local RequestState = {}

local function integer(value: any): boolean
	return type(value) == "number" and value == value and value > 0
		and value < 2147483647 and value % 1 == 0
end

function RequestState.IsValid(request: any): boolean
	if type(request) ~= "table" then return false end
	local count = 0
	for key in request do
		if key ~= "cart" and key ~= "generation" and key ~= "sequence" and key ~= "action" then return false end
		count += 1
	end
	return count == 4 and typeof(request.cart) == "Instance" and request.cart:IsA("Model")
		and integer(request.sequence) and integer(request.generation)
		and (request.action == "Toggle" or request.action == "Stop")
end

function RequestState.Accept(state: any, player: any, sequence: number, at: number): (boolean, string?)
	local window = state.RequestWindows[player]
	if not window or at - window.at >= 1 then
		window = { at = at, count = 0 }
		state.RequestWindows[player] = window
	end
	if window.count >= 10 then return false, "RATE_LIMITED" end
	window.count += 1
	if sequence <= (state.Requests[player] or 0) then return false, "REPEATED_REQUEST" end
	state.Requests[player] = sequence
	return true, nil
end

return table.freeze(RequestState)
