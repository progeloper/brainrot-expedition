--!strict
-- Pure numerical geometry. Arrays are Roblox XYZ / CFrame:GetComponents order.
-- No Instances, Services, mutation of inputs, rounding or module-level state.
local T = {}
local K = { 136, 313, 420, 432 }
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function checkedPoint(p)
	assert(
		type(p) == "table" and #p == 3 and finite(p[1]) and finite(p[2]) and finite(p[3]),
		"Finite XYZ point required"
	)
end
function T.Candidate(b, outer)
	local w, d = 96 * b, 110 * b
	local t = w + 8
	local r = 4 * math.ceil((t + w / 2 + d / 2 + 8) / 4)
	local h = 4 * math.ceil((r + d / 2 + 12) / 4)
	local c =
		{ b = b, t = t, r = r, h = h, outer = outer, origin = { -19, 0.04999995231628418, -46 } }
	T.Validate(c)
	return c
end
function T.Validate(c)
	assert(
		type(c) == "table" and finite(c.b) and c.b > 0 and finite(c.outer) and c.outer > 0,
		"Positive finite factors required"
	)
	assert(
		finite(c.t) and finite(c.r) and finite(c.h) and 0 < c.t and c.t < c.r and c.r < c.h - 12,
		"Strictly increasing target knots required"
	)
	checkedPoint(c.origin)
	return true
end
local function mapPositive(a, sources, targets, outer)
	local previousSource, previousTarget = 0, 0
	for i, k in ipairs(sources) do
		if a <= k then
			return previousTarget
				+ (a - previousSource) * (targets[i] - previousTarget) / (k - previousSource)
		end
		previousSource, previousTarget = k, targets[i]
	end
	return previousTarget + (a - previousSource) * outer
end
function T.MapAxis(d, c)
	T.Validate(c)
	assert(finite(d), "Finite axis required")
	local value = mapPositive(math.abs(d), K, { c.t, c.r, c.h - 12, c.h }, c.outer)
	return if d < 0 then -value else value
end
function T.InverseAxis(d, c)
	T.Validate(c)
	assert(finite(d), "Finite axis required")
	local value = mapPositive(math.abs(d), { c.t, c.r, c.h - 12, c.h }, K, 1 / c.outer)
	return if d < 0 then -value else value
end
function T.Point(p, c)
	checkedPoint(p)
	return {
		c.origin[1] + T.MapAxis(p[1] - c.origin[1], c),
		p[2],
		c.origin[3] + T.MapAxis(p[3] - c.origin[3], c),
	}
end
function T.InversePoint(p, c)
	checkedPoint(p)
	return {
		c.origin[1] + T.InverseAxis(p[1] - c.origin[1], c),
		p[2],
		c.origin[3] + T.InverseAxis(p[3] - c.origin[3], c),
	}
end
function T.RigidFrame(cf, c)
	assert(type(cf) == "table" and #cf == 12, "Captured CFrame components required")
	local p = T.Point({ cf[1], cf[2], cf[3] }, c)
	local out = { p[1], p[2], p[3] }
	for i = 4, 12 do
		assert(finite(cf[i]), "Finite rotation required")
		out[i] = cf[i]
	end
	return out
end
function T.Rectangle(r, c)
	assert(
		finite(r.x0)
			and finite(r.x1)
			and finite(r.z0)
			and finite(r.z1)
			and r.x0 < r.x1
			and r.z0 < r.z1,
		"Positive source rectangle required"
	)
	local lo = T.Point({ r.x0, r.y or 0, r.z0 }, c)
	local hi = T.Point({ r.x1, r.y or 0, r.z1 }, c)
	return {
		id = r.id,
		regionId = r.regionId,
		x0 = lo[1],
		x1 = hi[1],
		z0 = lo[3],
		z1 = hi[3],
		y = r.y,
		thickness = r.thickness,
	}
end
function T.Floor(cf, size, c)
	assert(
		#cf == 12 and #size == 3 and size[1] > 0 and size[2] > 0 and size[3] > 0,
		"Valid floor bounds required"
	)
	local identity = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	for i, v in ipairs(identity) do
		assert(
			math.abs(cf[i + 3] - v) < 1e-6,
			"Only verified axis-aligned unrotated floor rectangles supported"
		)
	end
	local r = T.Rectangle(
		{
			x0 = cf[1] - size[1] / 2,
			x1 = cf[1] + size[1] / 2,
			z0 = cf[3] - size[3] / 2,
			z1 = cf[3] + size[3] / 2,
			y = cf[2],
			thickness = size[2],
		},
		c
	)
	return { (r.x0 + r.x1) / 2, cf[2], (r.z0 + r.z1) / 2, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, {
		r.x1 - r.x0,
		size[2],
		r.z1 - r.z0,
	}
end
function T.SubdivideSegment(a, b, c)
	checkedPoint(a)
	checkedPoint(b)
	T.Validate(c)
	local stations = { 0, 1 }
	for _, axis in ipairs({ 1, 3 }) do
		local delta = b[axis] - a[axis]
		if math.abs(delta) > 1e-12 then
			for _, k in ipairs(K) do
				for _, sign in ipairs({ -1, 1 }) do
					local station = (c.origin[axis] + sign * k - a[axis]) / delta
					if station > 1e-12 and station < 1 - 1e-12 then
						table.insert(stations, station)
					end
				end
			end
		end
	end
	table.sort(stations)
	local sourcePoints, targetPoints, unique = {}, {}, {}
	for _, s in ipairs(stations) do
		if #unique == 0 or math.abs(s - unique[#unique]) > 1e-12 then
			table.insert(unique, s)
			local p =
				{ a[1] + (b[1] - a[1]) * s, a[2] + (b[2] - a[2]) * s, a[3] + (b[3] - a[3]) * s }
			table.insert(sourcePoints, p)
			table.insert(targetPoints, T.Point(p, c))
		end
	end
	return { sourcePoints = sourcePoints, targetPoints = targetPoints, sourceParameters = unique }
end
function T.Polyline(points, c)
	assert(#points >= 1, "Polyline is empty")
	local target, segments = {}, {}
	if #points == 1 then
		return { points = { T.Point(points[1], c) }, segments = {} }
	end
	for index = 1, #points - 1 do
		local split = T.SubdivideSegment(points[index], points[index + 1], c)
		for j, p in ipairs(split.targetPoints) do
			if index == 1 or j > 1 then
				table.insert(target, p)
			end
		end
		for j = 1, #split.targetPoints - 1 do
			table.insert(
				segments,
				{
					sourceSegmentIndex = index - 1,
					sourceT0 = split.sourceParameters[j],
					sourceT1 = split.sourceParameters[j + 1],
					a = split.targetPoints[j],
					b = split.targetPoints[j + 1],
				}
			)
		end
	end
	return { points = target, segments = segments }
end
function T.Polygon(points, c)
	assert(#points >= 3, "Polygon needs3points")
	local xyz = {}
	for _, p in ipairs(points) do
		table.insert(xyz, { p[1], 0, p[2] })
	end
	if xyz[1][1] ~= xyz[#xyz][1] or xyz[1][3] ~= xyz[#xyz][3] then
		table.insert(xyz, { xyz[1][1], 0, xyz[1][3] })
	end
	local out = {}
	for _, p in ipairs(T.Polyline(xyz, c).points) do
		table.insert(out, { p[1], p[3] })
	end
	return out
end
return T
