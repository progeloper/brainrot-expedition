--!strict
-- Pure XZ helpers for the V5 island edge (server out-of-bounds response and client mist).
-- A rect is { min: Vector2, max: Vector2 }, where Vector2.Y = world Z.
local IslandEdgeMath = {}

export type Rect = { min: Vector2, max: Vector2 }

-- True when (x, z) lies more than `margin` studs outside the rect.
function IslandEdgeMath.IsOutside(rect: Rect, margin: number, x: number, z: number): boolean
	return x < rect.min.X - margin
		or x > rect.max.X + margin
		or z < rect.min.Y - margin
		or z > rect.max.Y + margin
end

-- Signed distance to the nearest rect edge (positive inside), the closest point on the rect
-- boundary, and the unit inward normal of that edge. Outside a corner the normal points back
-- along the diagonal toward the corner.
function IslandEdgeMath.Nearest(rect: Rect, x: number, z: number): (number, Vector2, Vector2)
	local p = Vector2.new(x, z)
	local clamped =
		Vector2.new(math.clamp(x, rect.min.X, rect.max.X), math.clamp(z, rect.min.Y, rect.max.Y))
	if clamped ~= p then
		local back = clamped - p
		return -back.Magnitude, clamped, back.Unit
	end
	local candidates = {
		{ x - rect.min.X, Vector2.new(rect.min.X, z), Vector2.new(1, 0) },
		{ rect.max.X - x, Vector2.new(rect.max.X, z), Vector2.new(-1, 0) },
		{ z - rect.min.Y, Vector2.new(x, rect.min.Y), Vector2.new(0, 1) },
		{ rect.max.Y - z, Vector2.new(x, rect.max.Y), Vector2.new(0, -1) },
	}
	local best = candidates[1]
	for i = 2, 4 do
		if candidates[i][1] < best[1] then
			best = candidates[i]
		end
	end
	return best[1], best[2], best[3]
end

-- Landing probes `inset` studs inside the rect from the nearest edge point, in the given order.
-- Each probe is clamped so it stays at least `inset` from every edge (corners stay inside).
function IslandEdgeMath.Landings(rect: Rect, x: number, z: number, insets: { number }): { Vector2 }
	local _, point, normal = IslandEdgeMath.Nearest(rect, x, z)
	local result = {}
	for _, inset in insets do
		local probe = point + normal * inset
		local lo = rect.min + Vector2.one * inset
		local hi = rect.max - Vector2.one * inset
		if lo.X <= hi.X and lo.Y <= hi.Y then
			table.insert(
				result,
				Vector2.new(math.clamp(probe.X, lo.X, hi.X), math.clamp(probe.Y, lo.Y, hi.Y))
			)
		end
	end
	return result
end

-- Rect outline as a closed polygon (for the mist curtain), expanded by `offset`.
function IslandEdgeMath.Outline(rect: Rect, offset: number): { Vector2 }
	local lo, hi = rect.min - Vector2.one * offset, rect.max + Vector2.one * offset
	return {
		Vector2.new(lo.X, lo.Y),
		Vector2.new(hi.X, lo.Y),
		Vector2.new(hi.X, hi.Y),
		Vector2.new(lo.X, hi.Y),
	}
end

return table.freeze(IslandEdgeMath)
