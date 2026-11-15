--!strict

local Layout = {}

function Layout.Resolve(safeSize: Vector2): any
	local short = safeSize.Y < 340
	local besideReset = short and safeSize.X >= 384
	local right = if besideReset then 132 else 16
	local width = math.min(220, math.max(48, safeSize.X - right - 16))
	local top = if short then (if safeSize.X < 552 and besideReset then 64 else 8)
		else math.max(8, safeSize.Y - 218 - 98)
	return {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -right, 0, top),
		Size = UDim2.fromOffset(width, 98),
	}
end

return table.freeze(Layout)
