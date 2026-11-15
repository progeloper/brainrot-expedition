--!nocheck
-- Pure finite OBB math. No Instances, engine calls, mutable global state or gameplay requires.
local M = {}
local EPS = 1e-6
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function vector(v)
	assert(type(v) == "table" and #v == 3, "Dense XYZ required")
	for _, n in v do
		assert(finite(n), "Finite XYZ required")
	end
	return v
end
local function add(a, b)
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function mul(a, s)
	return { a[1] * s, a[2] * s, a[3] * s }
end
local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function axes(frame)
	assert(type(frame) == "table" and #frame == 12, "Dense CFrame12 required")
	for _, n in frame do
		assert(finite(n), "Finite CFrame required")
	end
	local out = {
		{ frame[4], frame[7], frame[10] },
		{ frame[5], frame[8], frame[11] },
		{ frame[6], frame[9], frame[12] },
	}
	for i = 1, 3 do
		assert(math.abs(dot(out[i], out[i]) - 1) <= 1e-4, "Unit rotation axes required")
		for j = i + 1, 3 do
			assert(math.abs(dot(out[i], out[j])) <= 1e-4, "Orthogonal rotation axes required")
		end
	end
	assert(dot(cross(out[1], out[2]), out[3]) > 0.999, "Right-handed rotation required")
	return out
end
function M.Transform(frame, point)
	local aa = axes(frame)
	return add(
		{ frame[1], frame[2], frame[3] },
		add(mul(aa[1], point[1]), add(mul(aa[2], point[2]), mul(aa[3], point[3])))
	)
end
function M.Box(frame, size)
	vector(size)
	for _, n in size do
		assert(n > 0, "Positive OBB size required")
	end
	return { centre = { frame[1], frame[2], frame[3] }, half = mul(size, 0.5), axes = axes(frame) }
end
function M.WildBox(frame, native, horizontalPadding, verticalPadding)
	vector(native.min)
	vector(native.max)
	assert(
		finite(horizontalPadding)
			and horizontalPadding >= 0
			and finite(verticalPadding)
			and verticalPadding >= 0,
		"Finite nonnegative padding required"
	)
	local size = sub(native.max, native.min)
	for _, n in size do
		assert(n > 0, "Strict native min/max bounds required")
	end
	local aa = axes(frame)
	return {
		centre = M.Transform(frame, mul(add(native.min, native.max), 0.5)),
		half = add(mul(size, 0.5), { horizontalPadding, verticalPadding, horizontalPadding }),
		axes = aa,
	}
end
function M.Radius(native)
	vector(native.min)
	vector(native.max)
	local radius = 0
	for _, x in { native.min[1], native.max[1] } do
		for _, z in { native.min[3], native.max[3] } do
			radius = math.max(radius, math.sqrt(x * x + z * z))
		end
	end
	return radius
end
function M.TurnBox(frame, native, horizontalPadding, verticalPadding)
	local r = M.Radius(native) + horizontalPadding
	return M.WildBox(
		frame,
		{ min = { -r, native.min[2], -r }, max = { r, native.max[2], r } },
		0,
		verticalPadding
	)
end
local function projectRadius(box, axis)
	local r = 0
	for i = 1, 3 do
		r += box.half[i] * math.abs(dot(box.axes[i], axis))
	end
	return r
end
-- Exact continuous translation of a fixed-orientation OBB through t in [0,1].
-- SAT axes are the 3+3 face normals and 9 nondegenerate edge cross products.
-- A zero-area tangency is not a positive-volume collision.
function M.Sweep(startBox, movement, obstacle, tolerance)
	vector(movement)
	tolerance = tolerance or EPS
	assert(finite(tolerance) and tolerance >= 0, "Finite tolerance required")
	local candidateAxes = {}
	for _, a in startBox.axes do
		table.insert(candidateAxes, a)
	end
	for _, a in obstacle.axes do
		table.insert(candidateAxes, a)
	end
	for _, a in startBox.axes do
		for _, b in obstacle.axes do
			local c = cross(a, b)
			local length = math.sqrt(dot(c, c))
			if length > 1e-9 then
				table.insert(candidateAxes, mul(c, 1 / length))
			end
		end
	end
	local delta = sub(startBox.centre, obstacle.centre)
	local enter, leave, wholeMargin = 0, 1, -math.huge
	local separated = false
	for _, axis in candidateAxes do
		local d, v = dot(delta, axis), dot(movement, axis)
		local radius = projectRadius(startBox, axis) + projectRadius(obstacle, axis)
		local endpoint = d + v
		local minimumAbsolute = if d * endpoint <= 0
			then 0
			else math.min(math.abs(d), math.abs(endpoint))
		wholeMargin = math.max(wholeMargin, minimumAbsolute - radius)
		local strictRadius = math.max(0, radius - tolerance)
		if math.abs(v) < 1e-12 then
			if math.abs(d) >= strictRadius then
				separated = true
			end
		else
			local a, b = (-strictRadius - d) / v, (strictRadius - d) / v
			if a > b then
				a, b = b, a
			end
			enter, leave = math.max(enter, a), math.min(leave, b)
		end
	end
	local hit = not separated and enter <= leave and leave > 0 and enter < 1
	return {
		intersects = hit,
		tEnter = enter,
		tExit = leave,
		wholeSweepSeparatingGap = math.max(0, wholeMargin),
		axesChecked = #candidateAxes,
	}
end
function M.Frame(position, yaw)
	vector(position)
	assert(finite(yaw), "Finite yaw required")
	local c, s = math.cos(yaw), math.sin(yaw)
	return { position[1], position[2], position[3], c, 0, s, 0, 1, 0, -s, 0, c }
end
function M.Heading(a, b)
	vector(a)
	vector(b)
	local x, z = b[1] - a[1], b[3] - a[3]
	assert(x * x + z * z > 1e-9, "Nonzero horizontal route segment required")
	return math.atan2(-x, -z)
end
function M.Close(a, b, tolerance)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i, n in a do
		if not finite(n) or not finite(b[i]) or math.abs(n - b[i]) > tolerance then
			return false
		end
	end
	return true
end
-- Exact SAT between a convex XZ polygon extruded through a vertical interval
-- and a general native OBB. Concave reservations must be decomposed first.
function M.ConvexPrismIntersectsBox(polygon, lowY, highY, obstacle, tolerance)
	tolerance = tolerance or EPS
	assert(
		#polygon >= 3 and finite(lowY) and finite(highY) and highY > lowY,
		"Finite convex prism required"
	)
	local candidateAxes = { { 0, 1, 0 } }
	local edgeDirections = { { 0, 1, 0 } }
	local points = {}
	for i, p in polygon do
		assert(#p == 2 and finite(p[1]) and finite(p[2]), "Finite XZ polygon required")
		table.insert(points, { p[1], lowY, p[2] })
		table.insert(points, { p[1], highY, p[2] })
		local q = polygon[i % #polygon + 1]
		local dx, dz = q[1] - p[1], q[2] - p[2]
		local length = math.sqrt(dx * dx + dz * dz)
		assert(length > 1e-9, "Nondegenerate polygon edge required")
		table.insert(candidateAxes, { -dz / length, 0, dx / length })
		table.insert(edgeDirections, { dx / length, 0, dz / length })
	end
	for _, axis in obstacle.axes do
		table.insert(candidateAxes, axis)
	end
	for _, edge in edgeDirections do
		for _, axis in obstacle.axes do
			local normal = cross(edge, axis)
			local length = math.sqrt(dot(normal, normal))
			if length > 1e-9 then
				table.insert(candidateAxes, mul(normal, 1 / length))
			end
		end
	end
	for _, axis in candidateAxes do
		local low, high = math.huge, -math.huge
		for _, point in points do
			local projected = dot(point, axis)
			low = math.min(low, projected)
			high = math.max(high, projected)
		end
		local centre, radius = dot(obstacle.centre, axis), projectRadius(obstacle, axis)
		if math.min(high, centre + radius) - math.max(low, centre - radius) <= tolerance then
			return false
		end
	end
	return true
end

M.Sub = sub
M.Vector = vector
M.Finite = finite
return M
