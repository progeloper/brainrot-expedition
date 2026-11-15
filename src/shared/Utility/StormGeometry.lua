--!strict
-- Pure XZ polygon helpers for the Storm boundary (server guard response and client curtain).
-- Points are Vector2 where .X = world X and .Y = world Z. Polygons may be concave.
local StormGeometry = {}

export type EdgeHit = {
	index: number,
	distance: number,
	point: Vector2, -- closest point on the edge
	normal: Vector2, -- unit outward normal of that edge
}

function StormGeometry.Contains(points: { Vector2 }, x: number, z: number): boolean
	local inside = false
	local count = #points
	local j = count
	for i = 1, count do
		local a, b = points[i], points[j]
		if (a.Y > z) ~= (b.Y > z) then
			local crossX = a.X + (z - a.Y) * (b.X - a.X) / (b.Y - a.Y)
			if x < crossX then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

local function closestOnSegment(a: Vector2, b: Vector2, p: Vector2): Vector2
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared <= 0 then
		return a
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t
end

-- Outward normal of edge i (points[i] -> points[i+1]), tested against the polygon
-- itself so the result is correct for either winding and for concave footprints.
function StormGeometry.EdgeNormal(points: { Vector2 }, index: number): Vector2
	local a = points[index]
	local b = points[index % #points + 1]
	local direction = (b - a).Unit
	local normal = Vector2.new(direction.Y, -direction.X)
	local mid = (a + b) / 2
	if StormGeometry.Contains(points, mid.X + normal.X * 0.05, mid.Y + normal.Y * 0.05) then
		normal = -normal
	end
	return normal
end

-- Every edge, nearest first (stable on ties by edge index).
function StormGeometry.EdgesByDistance(points: { Vector2 }, x: number, z: number): { EdgeHit }
	local p = Vector2.new(x, z)
	local hits: { EdgeHit } = {}
	for i = 1, #points do
		local closest = closestOnSegment(points[i], points[i % #points + 1], p)
		table.insert(hits, {
			index = i,
			distance = (closest - p).Magnitude,
			point = closest,
			normal = StormGeometry.EdgeNormal(points, i),
		})
	end
	table.sort(hits, function(left, right)
		if left.distance ~= right.distance then
			return left.distance < right.distance
		end
		return left.index < right.index
	end)
	return hits
end

function StormGeometry.NearestEdge(points: { Vector2 }, x: number, z: number): EdgeHit
	return StormGeometry.EdgesByDistance(points, x, z)[1]
end

-- Candidate exit points `offset` studs outside each edge, nearest edge first. A
-- candidate that lands back inside the polygon (concave corner) is skipped.
function StormGeometry.ExitCandidates(
	points: { Vector2 },
	x: number,
	z: number,
	offset: number
): { EdgeHit }
	local result: { EdgeHit } = {}
	for _, hit in StormGeometry.EdgesByDistance(points, x, z) do
		local a = points[hit.index]
		local b = points[hit.index % #points + 1]
		-- Keep the exit off the corner so the offset clears both edges of a convex corner.
		local along = math.clamp(
			(hit.point - a):Dot((b - a).Unit),
			math.min(offset, (b - a).Magnitude / 2),
			math.max((b - a).Magnitude - offset, (b - a).Magnitude / 2)
		)
		local base = a + (b - a).Unit * along
		local exit = base + hit.normal * offset
		if not StormGeometry.Contains(points, exit.X, exit.Y) then
			table.insert(
				result,
				{ index = hit.index, distance = hit.distance, point = exit, normal = hit.normal }
			)
		end
	end
	return result
end

-- Split every edge into pieces no longer than maxLength (curtain Beam segments).
function StormGeometry.Segments(
	points: { Vector2 },
	maxLength: number
): { { a: Vector2, b: Vector2, normal: Vector2 } }
	local segments = {}
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		local normal = StormGeometry.EdgeNormal(points, i)
		local pieces = math.max(1, math.ceil((b - a).Magnitude / maxLength))
		for k = 0, pieces - 1 do
			table.insert(
				segments,
				{ a = a:Lerp(b, k / pieces), b = a:Lerp(b, (k + 1) / pieces), normal = normal }
			)
		end
	end
	return segments
end

return table.freeze(StormGeometry)
