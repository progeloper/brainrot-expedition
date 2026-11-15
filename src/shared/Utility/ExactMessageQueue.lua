--!strict
local C = require(script.Parent.Parent.Config.PlaytestExact).Hud
local Queue = {}
function Queue.new()
	local active, pending, completed = nil, {}, {}
	local api = {}
	function api.Push(message, now)
		if completed[message.id] then
			return false
		end
		if active and active.id == message.id then
			active.title, active.detail = message.title, message.detail
			return false
		end
		for i, row in ipairs(pending) do
			if row.id == message.id then
				pending[i] = message
				return false
			end
		end
		if not active then
			message.since = now
			active = message
			return true
		end
		if #pending >= C.QueueCapacity then
			local index = nil
			if message.rare then
				for i, row in ipairs(pending) do
					if not row.rare then
						index = i
						break
					end
				end
				index = index or 1
			else
				for i = #pending, 1, -1 do
					if not pending[i].rare then
						index = i
						break
					end
				end
				if not index then
					return false
				end
			end
			completed[pending[index].id] = true
			table.remove(pending, index)
		end
		table.insert(pending, message)
		return true
	end
	function api.Step(now)
		if active then
			local total = C.FadeIn + (if active.rare then C.RareHold + C.RareFadeOut else C.ToastHold + C.ToastFadeOut)
			if now - active.since >= total then
				completed[active.id] = true
				active = nil
			end
		end
		if not active and #pending > 0 then
			local first = 1
			for i, row in ipairs(pending) do
				if row.rare then
					first = i
					break
				end
			end
			active = table.remove(pending, first)
			active.since = now
		end
		return active, #pending
	end
	function api.Defer(dt)
		if active then
			active.since += dt
		end
	end
	function api.Alpha(now)
		if not active then
			return 0
		end
		local age = now - active.since
		local hold = if active.rare then C.RareHold else C.ToastHold
		local fade = if active.rare then C.RareFadeOut else C.ToastFadeOut
		return math.clamp(math.min(age / C.FadeIn, (C.FadeIn + hold + fade - age) / fade), 0, 1)
	end
	return api
end
return table.freeze(Queue)
