--!strict
-- Camp Rework, Part C (owner-approved 12 Nov 2026): seeded, scored stall layout around the camp
-- landmark. Pure maths (no Instances): world raycasts are injected, so specs can run it headless and
-- the same seed always gives the same layout. The chosen result is written to Config/CampLayout.
--
-- Hard constraints (rejection): rule 2 compact cluster (32–58 from C, pairs ≤ 80 apart), rule 4 Training
-- ramp points outward with ≥ 18 clear flat studs in front, rule 7 clear lanes (20-stud base aprons,
-- 30-stud base→exit corridors, ≥ 12 between footprints/landmark/kiosk), rule 8 organic (no shared axis
-- line, no mirror symmetry).
-- Scores: + sightlines from every base entrance, + earn→spend (Sell opposite Weapons/Carts),
-- − walking (Sell to each other stall), + yaw variety.

export type StallSpec = {
	key: string,
	sector: number, -- degrees, 0 = +X, 90 = +Z
	footprint: Vector2, -- local X width, local Z depth
	offset: Vector2, -- footprint centre in the stall's local XZ (front is local −Z)
	signLocal: Vector3, -- sign centre in the stall's local frame
	height: number,
	faceOutward: boolean?, -- Training: ramp/front points away from the landmark
}

export type Input = {
	seed: number,
	candidates: number,
	center: Vector2,
	radiusMin: number,
	radiusMax: number,
	maxPairDistance: number,
	spacing: number,
	sectorJitter: number,
	yawJitter: number,
	rampClear: number,
	apron: number,
	corridorWidth: number,
	stalls: { StallSpec },
	landmark: { size: Vector2, height: number, topY: number },
	kiosk: { size: Vector2, height: number, radii: { number } },
	bases: { { name: string, entrance: Vector3, frontCenter: Vector2, frontAxis: Vector2, frontHalfWidth: number } },
	exits: { Vector2 },
	eyeHeight: number,
	worldBlocked: ((origin: Vector3, target: Vector3) -> boolean)?,
	weights: { sight: number, earnSpend: number, walking: number, variety: number }?,
}

local G = {}

G.DefaultWeights = { sight = 1, earnSpend = 12, walking = 0.05, variety = 0.08 }

type Rect = { c: Vector2, ax: Vector2, az: Vector2, hx: number, hz: number }

local function yawFacing(dir: Vector2): number
	-- CFrame.Angles(0, yaw, 0).LookVector = (−sin yaw, 0, −cos yaw)
	return math.atan2(-dir.X, -dir.Y)
end

local function rotate(v: Vector2, yaw: number): Vector2
	-- local (x, z) -> world (x, z) for CFrame.Angles(0, yaw, 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	return Vector2.new(v.X * c + v.Y * s, -v.X * s + v.Y * c)
end

local function rect(center: Vector2, yaw: number, offset: Vector2, size: Vector2): Rect
	return {
		c = center + rotate(offset, yaw),
		ax = rotate(Vector2.new(1, 0), yaw),
		az = rotate(Vector2.new(0, 1), yaw),
		hx = size.X / 2,
		hz = size.Y / 2,
	}
end

local function corners(r: Rect): { Vector2 }
	local out = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		table.insert(out, r.c + r.ax * (r.hx * s[1]) + r.az * (r.hz * s[2]))
	end
	return out
end

local function pointInRect(p: Vector2, r: Rect): boolean
	local d = p - r.c
	return math.abs(d:Dot(r.ax)) <= r.hx + 1e-6 and math.abs(d:Dot(r.az)) <= r.hz + 1e-6
end

local function segPointDistance(a: Vector2, b: Vector2, p: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

local function segmentsIntersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local function cross(o: Vector2, p: Vector2, q: Vector2): number
		return (p.X - o.X) * (q.Y - o.Y) - (p.Y - o.Y) * (q.X - o.X)
	end
	local d1, d2 = cross(c, d, a), cross(c, d, b)
	local d3, d4 = cross(a, b, c), cross(a, b, d)
	return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end

local function segRectDistance(a: Vector2, b: Vector2, r: Rect): number
	if pointInRect(a, r) or pointInRect(b, r) then
		return 0
	end
	local cs = corners(r)
	local best = math.huge
	for i = 1, 4 do
		local p, q = cs[i], cs[i % 4 + 1]
		if segmentsIntersect(a, b, p, q) then
			return 0
		end
		best = math.min(best, segPointDistance(a, b, p), segPointDistance(p, q, a), segPointDistance(p, q, b))
	end
	return best
end

-- Minimum distance between two rectangles (0 when they overlap).
function G.RectDistance(r1: Rect, r2: Rect): number
	local c1, c2 = corners(r1), corners(r2)
	for _, p in c1 do
		if pointInRect(p, r2) then
			return 0
		end
	end
	for _, p in c2 do
		if pointInRect(p, r1) then
			return 0
		end
	end
	local best = math.huge
	for i = 1, 4 do
		local a, b = c1[i], c1[i % 4 + 1]
		best = math.min(best, segRectDistance(a, b, r2))
	end
	return best
end

-- 3D segment vs vertical box (rect extruded from y=0 to height).
local function segmentHitsBox(o: Vector3, t: Vector3, r: Rect, height: number): boolean
	-- sample along the XZ segment; box is convex so a fine sampling is exact enough for sightlines
	local steps = 40
	for i = 1, steps - 1 do
		local f = i / steps
		local p = o:Lerp(t, f)
		if p.Y >= 0 and p.Y <= height and pointInRect(Vector2.new(p.X, p.Z), r) then
			return true
		end
	end
	return false
end

local function stddev(values: { number }): number
	local mean = 0
	for _, v in values do
		mean += v
	end
	mean /= #values
	local acc = 0
	for _, v in values do
		acc += (v - mean) ^ 2
	end
	return math.sqrt(acc / #values)
end

local function angleBetween(a: Vector2, b: Vector2): number
	local d = math.clamp(a.Unit:Dot(b.Unit), -1, 1)
	return math.deg(math.acos(d))
end

-- One candidate layout from the RNG stream.
local function sample(input: Input, rng: Random): any
	local placed = {}
	for _, spec in input.stalls do
		local angle = math.rad(spec.sector + rng:NextNumber(-input.sectorJitter, input.sectorJitter))
		-- Random radius inside the band, biased inward (u²): Sell sits opposite the Weapons/Carts pair
		-- and every pair must stay ≤ 80 studs apart, which only fits in the inner part of the band.
		local u = rng:NextNumber()
		local radius = input.radiusMin + (input.radiusMax - input.radiusMin) * u * u
		local pos = input.center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local toCenter = (input.center - pos).Unit
		local facing = if spec.faceOutward then -toCenter else toCenter
		local yaw = yawFacing(facing) + math.rad(rng:NextNumber(-input.yawJitter, input.yawJitter))
		placed[spec.key] = { spec = spec, pos = pos, yaw = yaw, angle = angle, radius = radius }
	end
	return placed
end

local function evaluate(input: Input, placed: any): (boolean, string?, any)
	local center = input.center
	local landmarkRect = rect(center, 0, Vector2.zero, input.landmark.size)
	local rects = {}
	for key, p in placed do
		rects[key] = rect(p.pos, p.yaw, p.spec.offset, p.spec.footprint)
	end
	-- rule 2: compact cluster
	for _, p in placed do
		local d = (p.pos - center).Magnitude
		if d < input.radiusMin - 1e-6 or d > input.radiusMax + 1e-6 then
			return false, "RULE2_RADIUS"
		end
	end
	local keys = {}
	for key in placed do
		table.insert(keys, key)
	end
	table.sort(keys)
	for i = 1, #keys do
		for j = i + 1, #keys do
			local a, b = placed[keys[i]], placed[keys[j]]
			if (a.pos - b.pos).Magnitude > input.maxPairDistance then
				return false, "RULE2_PAIR_DISTANCE"
			end
			-- rule 7 spacing
			if G.RectDistance(rects[keys[i]], rects[keys[j]]) < input.spacing then
				return false, "RULE7_SPACING"
			end
			-- rule 8 axis lines
			if math.abs(a.pos.X - b.pos.X) < 2 or math.abs(a.pos.Y - b.pos.Y) < 2 then
				return false, "RULE8_SHARED_AXIS"
			end
		end
		if G.RectDistance(rects[keys[i]], landmarkRect) < input.spacing then
			return false, "RULE7_LANDMARK_SPACING"
		end
	end
	-- rule 7 aprons + corridors
	for key, r in rects do
		for _, base in input.bases do
			local axis = Vector2.new(-base.frontAxis.Y, base.frontAxis.X)
			local a = base.frontCenter + axis * base.frontHalfWidth
			local b = base.frontCenter - axis * base.frontHalfWidth
			-- the apron is the 20-stud band in front of the base front edge
			if segRectDistance(a, b, r) < input.apron then
				return false, "RULE7_APRON:" .. key
			end
			local apronPoint = base.frontCenter + base.frontAxis * input.apron
			local nearest, best = nil, math.huge
			for _, exit in input.exits do
				local d = (exit - apronPoint).Magnitude
				if d < best then
					nearest, best = exit, d
				end
			end
			if nearest and segRectDistance(apronPoint, nearest, r) < input.corridorWidth / 2 then
				return false, "RULE7_CORRIDOR:" .. key
			end
		end
	end
	-- rule 4: Training ramp outward + clear flat space in front
	local kiosk = nil
	for key, p in placed do
		if p.spec.faceOutward then
			local frontZ = p.spec.offset.Y - p.spec.footprint.Y / 2
			local zone = rect(p.pos, p.yaw, Vector2.new(p.spec.offset.X, frontZ - input.rampClear / 2),
				Vector2.new(p.spec.footprint.X, input.rampClear))
			for other, r in rects do
				if other ~= key and G.RectDistance(zone, r) <= 0 then
					return false, "RULE4_RAMP_BLOCKED"
				end
			end
			if G.RectDistance(zone, landmarkRect) <= 0 then
				return false, "RULE4_RAMP_LANDMARK"
			end
			local outward = (p.pos - center).Unit
			local look = rotate(Vector2.new(0, -1), p.yaw)
			if look:Dot(outward) < math.cos(math.rad(45)) then
				return false, "RULE4_RAMP_NOT_OUTWARD"
			end
			p.rampZone = zone
		end
	end
	-- rule 8: not mirror-symmetric (about any line through C at 0/45/90/135°)
	for _, deg in { 0, 45, 90, 135 } do
		local n = Vector2.new(math.cos(math.rad(deg)), math.sin(math.rad(deg)))
		local mirrored = 0
		for _, p in placed do
			local d = p.pos - center
			local reflected = center + d - n * (2 * d:Dot(n))
			for _, q in placed do
				if (q.pos - reflected).Magnitude < 3 then
					mirrored += 1
					break
				end
			end
		end
		if mirrored == #keys then
			return false, "RULE8_MIRROR"
		end
	end
	-- Announcements kiosk: beside the landmark in the widest gap, facing the bigger group of entrances.
	do
		local angles = {}
		for _, p in placed do
			table.insert(angles, math.deg(p.angle) % 360)
		end
		table.sort(angles)
		local gapStart, gapSize = 0, -1
		for i = 1, #angles do
			local a, b = angles[i], angles[i % #angles + 1] + (if i == #angles then 360 else 0)
			if b - a > gapSize then
				gapStart, gapSize = a, b - a
			end
		end
		local mid = math.rad(gapStart + gapSize / 2)
		local dir = Vector2.new(math.cos(mid), math.sin(mid))
		-- face the larger group of base entrances on that side (count within ±70°)
		local count = 0
		for _, base in input.bases do
			local to = Vector2.new(base.entrance.X, base.entrance.Z) - center
			if angleBetween(to, dir) <= 70 then
				count += 1
			end
		end
		for _, radius in input.kiosk.radii do
			local pos = center + dir * radius
			local yaw = yawFacing(dir)
			local r = rect(pos, yaw, Vector2.zero, input.kiosk.size)
			local ok = G.RectDistance(r, landmarkRect) >= input.spacing * 0.5
			for _, other in rects do
				if G.RectDistance(r, other) < input.spacing then
					ok = false
				end
			end
			for _, p in placed do
				if p.rampZone and G.RectDistance(r, p.rampZone) <= 0 then
					ok = false
				end
			end
			if ok then
				kiosk = { pos = pos, yaw = yaw, entrancesFaced = count }
				break
			end
		end
		if not kiosk then
			return false, "KIOSK_NO_ROOM"
		end
	end
	-- Scores
	local weights = input.weights or G.DefaultWeights
	local sightTable = {}
	local sight = 0
	local kioskRect = rect(kiosk.pos, kiosk.yaw, Vector2.zero, input.kiosk.size)
	local landmarkTop = Vector3.new(center.X, input.landmark.topY, center.Y)
	for _, base in input.bases do
		local origin = Vector3.new(base.entrance.X, input.eyeHeight, base.entrance.Z)
		local function visible(target: Vector3, ignoreKey: string?): boolean
			for key, p in placed do
				if key ~= ignoreKey and segmentHitsBox(origin, target, rects[key], p.spec.height) then
					return false
				end
			end
			if ignoreKey ~= "Landmark" and segmentHitsBox(origin, target, landmarkRect, input.landmark.height) then
				return false
			end
			if segmentHitsBox(origin, target, kioskRect, input.kiosk.height) then
				return false
			end
			if input.worldBlocked and input.worldBlocked(origin, target) then
				return false
			end
			return true
		end
		local seesLandmark = visible(landmarkTop, "Landmark")
		local signs = {}
		for _, key in keys do
			local p = placed[key]
			local local3 = p.spec.signLocal
			local xz = p.pos + rotate(Vector2.new(local3.X, local3.Z), p.yaw)
			if visible(Vector3.new(xz.X, local3.Y, xz.Y), key) then
				table.insert(signs, key)
			end
		end
		sight += math.min(#signs, 3) + (if seesLandmark then 2 else 0)
		table.insert(sightTable, { base = base.name, landmark = seesLandmark, signs = signs })
	end
	local sell = placed.Sell
	local pairMid = ((placed.Weapons.pos + placed.Carts.pos) / 2) - center
	local earnAngle = angleBetween(sell.pos - center, pairMid)
	local walking = (sell.pos - placed.Weapons.pos).Magnitude + (sell.pos - placed.Carts.pos).Magnitude
		+ (sell.pos - placed.Training.pos).Magnitude
	local yaws = {}
	for _, key in keys do
		table.insert(yaws, math.deg(placed[key].yaw))
	end
	local variety = stddev(yaws)
	local breakdown = {
		sightlines = sight * weights.sight,
		earnSpend = (earnAngle / 180) * weights.earnSpend,
		walking = -walking * weights.walking,
		variety = variety * weights.variety,
	}
	local total = breakdown.sightlines + breakdown.earnSpend + breakdown.walking + breakdown.variety
	local walkTable = {}
	for i = 1, #keys do
		for j = i + 1, #keys do
			table.insert(walkTable, { a = keys[i], b = keys[j], studs = (placed[keys[i]].pos - placed[keys[j]].pos).Magnitude })
		end
	end
	-- every base must see the landmark and at least two signs (reported; scored above)
	local allSee = true
	for _, row in sightTable do
		if not row.landmark or #row.signs < 2 then
			allSee = false
		end
	end
	return true, nil, {
		total = total,
		breakdown = breakdown,
		earnSpendAngle = earnAngle,
		walkingStuds = walking,
		sightTable = sightTable,
		walkTable = walkTable,
		allBasesSee = allSee,
		kiosk = kiosk,
	}
end

-- Generate `candidates` seeded layouts, reject rule breakers, score the rest, best first.
function G.Generate(input: Input): any
	local rng = Random.new(input.seed)
	local survivors = {}
	local rejections: { [string]: number } = {}
	for index = 1, input.candidates do
		local placed = sample(input, rng)
		local ok, reason, result = evaluate(input, placed)
		if ok then
			result.index = index
			result.placed = placed
			table.insert(survivors, result)
		else
			local key = string.match(reason or "?", "^[^:]+") or "?"
			rejections[key] = (rejections[key] or 0) + 1
		end
	end
	table.sort(survivors, function(a, b)
		-- layouts where every base sees the landmark + 2 signs always rank first
		if a.allBasesSee ~= b.allBasesSee then
			return a.allBasesSee
		end
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.index < b.index
	end)
	return { ranked = survivors, rejections = rejections, candidates = input.candidates }
end

-- Exposed for specs.
G.Rect = rect
G.YawFacing = yawFacing
G.Rotate = rotate
G.Evaluate = evaluate

return table.freeze(G)
