--!strict
-- Pure route reconstruction and crossing policy. Input route IDs/control graph are
-- immutable. Widths are authored stud distances, never nonlinear-scaled masks.
local R = {}
local EPS = 1e-9
local function copy(row)
	return table.clone(row)
end
local function square(p, w)
	local h = w / 2
	return { { p[1] - h, p[3] - h }, { p[1] + h, p[3] - h }, { p[1] + h, p[3] + h }, {
		p[1] - h,
		p[3] + h,
	} }
end
local function ribbon(a, b, w)
	local dx, dz = b[1] - a[1], b[3] - a[3]
	local len = math.sqrt(dx * dx + dz * dz)
	if len < EPS then
		return square(a, w)
	end
	local x, z = -dz / len * w / 2, dx / len * w / 2
	return { { a[1] + x, a[3] + z }, { b[1] + x, b[3] + z }, { b[1] - x, b[3] - z }, {
		a[1] - x,
		a[3] - z,
	} }
end
local function length(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end
local function localPolygon(g, n, rows)
	local u = { n[3], 0, -n[1] }
	local out = {}
	for _, p in ipairs(rows) do
		table.insert(out, { g[1] + n[1] * p[1] + u[1] * p[2], g[3] + n[3] * p[1] + u[3] * p[2] })
	end
	return out
end
function R.Build(routes, c, T, caps)
	local result = { routes = {}, primitives = {}, caps = {}, routeById = {} }
	for _, source in ipairs(routes) do
		assert(not result.routeById[source.id], "Duplicate semantic route ID")
		assert(source.requiredWidth > 0 and #source.points > 0, "Route controls/width missing")
		local transformed = T.Polyline(source.points, c)
		local row = {
			id = source.id,
			role = source.role,
			footprintType = source.footprintType,
			width = source.requiredWidth,
			sourcePoints = source.points,
			controlPoints = {},
			points = transformed.points,
			segments = transformed.segments,
			destination = source.destination,
			sourceFacing = source.sourceFacing,
			arcLengthStations = { 0 },
			sourceEndpointSquares = source.endpointSquares,
		}
		for _, p in ipairs(source.points) do
			table.insert(row.controlPoints, T.Point(p, c))
		end
		for i = 2, #row.points do
			row.arcLengthStations[i] = row.arcLengthStations[i - 1]
				+ length(row.points[i - 1], row.points[i])
		end
		result.routeById[row.id] = row
		table.insert(result.routes, row)
		if source.footprintType == "square" then
			assert(#source.points == 1, "Square route expects a single identity node")
			table.insert(
				result.primitives,
				{
					id = row.id .. "/Square",
					routeId = row.id,
					kind = "FixedWidthSquare",
					width = row.width,
					polygon = square(row.points[1], row.width),
				}
			)
		elseif source.footprintType == "polyline" or source.footprintType == "stairSquares" then
			-- The raster slice depth is not a road width. Preserve every authored control
			-- station; build the physical 36-stud diagonal corridor along those stations.
			for i, seg in ipairs(row.segments) do
				table.insert(
					result.primitives,
					{
						id = row.id .. "/Segment/" .. i,
						routeId = row.id,
						kind = "ConstantWidthRibbon",
						width = row.width,
						sourceSegmentIndex = seg.sourceSegmentIndex,
						sourceT0 = seg.sourceT0,
						sourceT1 = seg.sourceT1,
						polygon = ribbon(seg.a, seg.b, row.width),
					}
				)
			end
			-- Fixed square joins preserve existing orthogonal endpoint/junction semantics.
			-- Diagonal joins use a regular bevel envelope, not an enlarged raster box.
			for i, p in ipairs(row.points) do
				if source.endpointSquares and (source.footprintType ~= "stairSquares") then
					table.insert(
						result.primitives,
						{
							id = row.id .. "/Join/" .. i,
							routeId = row.id,
							kind = "FixedWidthSquareJoin",
							width = row.width,
							polygon = square(p, row.width),
						}
					)
				end
			end
		else
			error("Unknown authoritative route footprint: " .. tostring(source.footprintType))
		end
	end
	for _, cap in ipairs(caps or {}) do
		local owner = result.routeById[cap.routeId]
		assert(owner, "Contact cap has no semantic owner")
		local a = T.Point(cap.frozenSourceEndpoint, c)
		local b = T.Point(
			{ cap.visualContactXZ[1], cap.frozenSourceEndpoint[2], cap.visualContactXZ[2] },
			c
		)
		assert(
			length(a, owner.controlPoints[cap.sourcePointIndex + 1]) < 0.01,
			"Contact cap endpoint does not bind owner control"
		)
		local row = {
			id = cap.id,
			routeId = cap.routeId,
			sourcePointIndex = cap.sourcePointIndex,
			a = a,
			b = b,
			width = cap.widthStuds,
			polygon = ribbon(a, b, cap.widthStuds),
			sourceLength = cap.lengthStuds,
			targetLength = length(a, b),
			graphPolicy = "Existing visual contact; no additional logical edge",
		}
		table.insert(result.caps, row)
		table.insert(
			result.primitives,
			{
				id = cap.id,
				routeId = cap.routeId,
				kind = "ExistingContactCap",
				width = row.width,
				polygon = row.polygon,
			}
		)
	end
	return result
end
function R.GateAprons(gates, plan, owners, c, T)
	local output = {}
	local ownerByName = {}
	for _, o in ipairs(owners) do
		ownerByName[o.gate] = o
	end
	for _, gate in ipairs(gates) do
		local o = ownerByName[gate.name]
		assert(o, "Gate has no verified source route relation")
		local route = plan.routeById[o.routeId]
		assert(route, "Gate route missing")
		local oldG, newG, n = gate.ground, T.Point(gate.ground, c), gate.normal
		assert(
			n[2] == 0 and math.abs(n[1]) + math.abs(n[3]) == 1,
			"Only verified cardinal gate normals supported"
		)
		local u = { n[3], 0, -n[1] }
		local sourceSegment = route.sourcePoints[o.segment + 1]
		local nextSegment = route.sourcePoints[o.segment + 2]
		assert(sourceSegment and nextSegment, "Gate source segment missing")
		local normalAxis = if n[1] ~= 0 then 1 else 3
		local delta = nextSegment[normalAxis] - sourceSegment[normalAxis]
		assert(math.abs(delta) > EPS, "Gate owner must cross its plane")
		local t = (oldG[normalAxis] - sourceSegment[normalAxis]) / delta
		assert(t >= -EPS and t <= 1 + EPS, "Gate does not bind stated source segment")
		local sourceIntersection = {
			sourceSegment[1] + (nextSegment[1] - sourceSegment[1]) * t,
			oldG[2],
			sourceSegment[3] + (nextSegment[3] - sourceSegment[3]) * t,
		}
		local intersection = T.Point(sourceIntersection, c)
		local offset = (intersection[1] - newG[1]) * u[1] + (intersection[3] - newG[3]) * u[3]
		local half = route.width / 2
		local lo, hi = math.min(-12, offset - half), math.max(12, offset + half)
		local surface = localPolygon(
			newG,
			n,
			{
				{ -48, offset - half },
				{ -32, lo },
				{ 32, lo },
				{ 48, offset - half },
				{ 48, offset + half },
				{ 32, hi },
				{ -32, hi },
				{ -48, offset + half },
			}
		)
		local driving = localPolygon(
			newG,
			n,
			{
				{ -48, offset - half },
				{ -32, -12 },
				{ 32, -12 },
				{ 48, offset - half },
				{ 48, offset + half },
				{ 32, 12 },
				{ -32, 12 },
				{ -48, offset + half },
			}
		)
		local leftTaper = localPolygon(
			newG,
			n,
			{ { -48, offset - half }, { -32, -12 }, { -32, 12 }, { -48, offset + half } }
		)
		local throat = localPolygon(newG, n, { { -32, -12 }, { 32, -12 }, { 32, 12 }, { -32, 12 } })
		local rightTaper = localPolygon(
			newG,
			n,
			{ { 32, -12 }, { 48, offset - half }, { 48, offset + half }, { 32, 12 } }
		)
		local structural = localPolygon(newG, n, { { -2, -18 }, { 2, -18 }, { 2, 18 }, { -2, 18 } })
		local row = {
			id = "Gate_" .. gate.name,
			name = gate.name,
			regionPair = gate.regionPair,
			ground = newG,
			sourceGround = oldG,
			normal = n,
			tangent = u,
			routeId = o.routeId,
			sourceSegmentIndex = o.segment,
			sourceIntersection = sourceIntersection,
			intersection = intersection,
			lateralRouteOffset = offset,
			ordinaryWidth = route.width,
			usableWidth = 24,
			structuralWidth = 36,
			throatEachSide = 32,
			taperEachSide = 16,
			surfacePolygon = surface,
			drivingPolygon = driving,
			structuralPolygon = structural,
			wallProtectedPolygons = { structural, leftTaper, throat, rightTaper },
			descriptorFrames = {},
			fitStatus = "NotRun",
		}
		-- Gate bundles are rigid translations: safe offsets/prompt distance preserve
		-- their genuine local physical distances; they are not fed through f again.
		for _, key in ipairs({
			"thresholdCFrame",
			"safeCartCFrame",
			"safeCharacterCFrame",
			"interactionCFrame",
		}) do
			local frame = gate[key]
			assert(frame and #frame == 12, "Captured gate descriptor missing")
			local new = copy(frame)
			new[1] += newG[1] - oldG[1]
			new[3] += newG[3] - oldG[3]
			row.descriptorFrames[key] = new
		end
		table.insert(output, row)
	end
	return output
end
local function intersection(a, b, run)
	local normalAxis = if run.axis == "X" then 3 else 1
	local alongAxis = if run.axis == "X" then 1 else 3
	local delta = b[normalAxis] - a[normalAxis]
	if math.abs(delta) <= EPS then
		return nil
	end
	local t = (run.fixed - a[normalAxis]) / delta
	if t < -EPS or t > 1 + EPS then
		return nil
	end
	local along = a[alongAxis] + (b[alongAxis] - a[alongAxis]) * t
	if along < run.first - EPS or along > run.last + EPS then
		return nil
	end
	return t, { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
function R.Crossings(routes, sourceRuns, targetRuns, aprons, legacyRows, c, T)
	local records, openings, parallel = {}, {}, {}
	local seen = {}
	local mapped = {}
	for _, r in ipairs(targetRuns) do
		mapped[r.id] = r
	end
	for _, route in ipairs(routes) do
		if route.footprintType ~= "square" then
			for si = 1, #route.points - 1 do
				local a, b = route.points[si], route.points[si + 1]
				for _, run in ipairs(sourceRuns) do
					local t, p = intersection(a, b, run)
					if p then
						local key = route.id
							.. "/"
							.. run.id
							.. "/"
							.. string.format("%.9f/%.9f", p[1], p[3])
						if not seen[key] then
							seen[key] = true
							local gate = nil
							for _, apron in ipairs(aprons) do
								if
									apron.routeId == route.id
									and apron.sourceSegmentIndex == si - 1
									and table.concat(apron.regionPair, "/")
										== table.concat(run.regionPair, "/")
								then
									gate = apron
								end
							end
							local blockers = {}
							for _, old in ipairs(legacyRows) do
								local along = if run.axis == "X" then p[1] else p[3]
								if
									old.axis == run.axis
									and math.abs(old.fixed - run.fixed) < 0.01
									and along > old.first + 0.01
									and along < old.last - 0.01
								then
									table.insert(blockers, old.id)
								end
							end
							local q = T.Point(p, c)
							local row = {
								id = "X_" .. route.id .. "_" .. run.id .. "_" .. tostring(si - 1),
								routeId = route.id,
								sourceSegmentIndex = si - 1,
								sourceParameter = t,
								runId = run.id,
								regionPair = run.regionPair,
								sourceIntersection = p,
								intersection = q,
								width = route.requiredWidth,
								evidence = {
									"Complete authoritative route/control graph",
									"Fresh floor-union shared seam",
								},
								legacyRestrictionIds = blockers,
							}
							if gate then
								row.owningGate = gate.name
								row.accessPolicy = "ExistingPaidGate"
								row.apertureWidth = gate.structuralWidth
								row.clearWidth = gate.usableWidth
								row.apertureCentre = gate.ground
								row.evidence[3] =
									"Live threshold anchor plus verified gate-local route relation"
								table.insert(
									openings,
									{
										id = gate.id,
										crossingId = row.id,
										polygons = gate.wallProtectedPolygons,
										accessPolicy = row.accessPolicy,
									}
								)
							elseif #blockers > 0 then
								row.accessPolicy = "ExistingEquivalentRestriction"
								row.apertureWidth = 0
								row.evidence[3] =
									"Fresh captured physical separator intersects this original route; retain existing closure"
							else
								local free = run.regionPair[1] == "REGION_CAMP"
									and run.regionPair[2] == "REGION_FOREST"
								row.accessPolicy = if free
									then "ExistingFreeCampForestRoad"
									else "ExistingUnframedRoadWithServerRegionPermission"
								row.apertureWidth =
									math.max(if free then 36 else 24, route.requiredWidth + 4)
								row.clearWidth = row.apertureWidth
								row.apertureCentre = q
								local target = mapped[run.id]
								local h = row.apertureWidth / 2
								local poly
								if target.axis == "X" then
									poly = {
										{ q[1] - h, target.fixed - 4 },
										{ q[1] + h, target.fixed - 4 },
										{ q[1] + h, target.fixed + 4 },
										{ q[1] - h, target.fixed + 4 },
									}
								else
									poly = {
										{ target.fixed - 4, q[3] - h },
										{ target.fixed + 4, q[3] - h },
										{ target.fixed + 4, q[3] + h },
										{ target.fixed - 4, q[3] + h },
									}
								end
								table.insert(
									openings,
									{
										id = row.id,
										crossingId = row.id,
										polygons = { poly },
										accessPolicy = row.accessPolicy,
									}
								)
							end
							table.insert(records, row)
						end
					elseif
						math.abs((if run.axis == "X" then b[3] - a[3] else b[1] - a[1])) <= EPS
					then
						local normalAxis = if run.axis == "X" then 3 else 1
						local alongAxis = if run.axis == "X" then 1 else 3
						local first, last =
							math.max(run.first, math.min(a[alongAxis], b[alongAxis])),
							math.min(run.last, math.max(a[alongAxis], b[alongAxis]))
						if last - first > EPS then
							local qa = T.Point(a, c)
							local target = mapped[run.id]
							local distance = math.abs(qa[normalAxis] - target.fixed)
							if distance < route.requiredWidth / 2 + 3 - 0.01 then
								table.insert(
									parallel,
									{
										routeId = route.id,
										sourceSegmentIndex = si - 1,
										runId = run.id,
										regionPair = run.regionPair,
										targetDistance = distance,
										requiredDistance = route.requiredWidth / 2 + 3,
										shortfall = route.requiredWidth / 2 + 3 - distance,
										status = "CandidateFitConflict",
										policy = "No inferred longitudinal opening or unverified offset",
									}
								)
							end
						end
					end
				end
			end
		end
	end
	for _, gate in ipairs(aprons) do
		local found = false
		for _, row in ipairs(records) do
			if row.owningGate == gate.name then
				found = true
			end
		end
		assert(found, "Named paid gate did not bind a genuine route crossing: " .. gate.name)
	end
	return {
		records = records,
		openings = openings,
		parallelConflicts = parallel,
		documentedOnFootConnectors = "No additional connector inferred; explicit fresh evidence required",
	}
end
-- Numeric polygon connectedness is separate from logical access policy. Touching
-- convex corridor primitives form one component; gates can still deny crossing.
function R.ConnectedComponents(primitives)
	local parents, bounds = {}, {}
	for i, row in ipairs(primitives) do
		parents[i] = i
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(row.polygon) do
			x0 = math.min(x0, p[1])
			x1 = math.max(x1, p[1])
			z0 = math.min(z0, p[2])
			z1 = math.max(z1, p[2])
		end
		bounds[i] = { x0, x1, z0, z1 }
	end
	local function root(i)
		while parents[i] ~= i do
			parents[i] = parents[parents[i]]
			i = parents[i]
		end
		return i
	end
	local function touches(a, b)
		for _, poly in ipairs({ a, b }) do
			for i, p in ipairs(poly) do
				local q = poly[i % #poly + 1]
				local axis = { -(q[2] - p[2]), q[1] - p[1] }
				local alo, ahi, blo, bhi = math.huge, -math.huge, math.huge, -math.huge
				for _, v in ipairs(a) do
					local d = v[1] * axis[1] + v[2] * axis[2]
					alo = math.min(alo, d)
					ahi = math.max(ahi, d)
				end
				for _, v in ipairs(b) do
					local d = v[1] * axis[1] + v[2] * axis[2]
					blo = math.min(blo, d)
					bhi = math.max(bhi, d)
				end
				if math.min(ahi, bhi) < math.max(alo, blo) - EPS then
					return false
				end
			end
		end
		return true
	end
	for i = 1, #primitives do
		for j = i + 1, #primitives do
			local a, b = bounds[i], bounds[j]
			if
				a[1] <= b[2] + EPS
				and b[1] <= a[2] + EPS
				and a[3] <= b[4] + EPS
				and b[3] <= a[4] + EPS
				and root(i) ~= root(j)
			then
				if touches(primitives[i].polygon, primitives[j].polygon) then
					parents[root(j)] = root(i)
				end
			end
		end
	end
	local components = {}
	local lookup = {}
	for i, row in ipairs(primitives) do
		local id = root(i)
		if not lookup[id] then
			lookup[id] = { primitiveIds = {}, routeIds = {} }
			table.insert(components, lookup[id])
		end
		table.insert(lookup[id].primitiveIds, row.id)
		lookup[id].routeIds[row.routeId] = true
	end
	return {
		count = #components,
		components = components,
		primitiveCount = #primitives,
		scope = "Convex numerical surface union only; no drivability/access inference",
	}
end
return R
