--!strict
-- Pure, testable rules for the V5 world presentation (Storm, toys, quality tiers).
local Rules = {}

-- Regions whose Storm this player sees: every gated region not personally unlocked.
function Rules.LockedKeys(summary: any, ordered: { any }): { [string]: boolean }
	local locked = {}
	local unlocks = if type(summary) == "table"
			and type(summary.personalUnlocks) == "table"
		then summary.personalUnlocks
		else {}
	for _, definition in ordered do
		if definition.index > 1 and unlocks[definition.key] ~= true then
			locked[definition.key] = true
		end
	end
	return locked
end

-- Quality tier from the saved graphics level (1-10, 0 = automatic) and a median frame-time probe.
-- A slow probe drops exactly one tier. Terrain, landmarks, Storm, gates and signs never drop.
function Rules.SelectTier(
	savedQualityLevel: number,
	medianFrameMs: number?,
	dropAboveMs: number
): string
	local order = { "Full", "Reduced", "Minimal" }
	local index = if savedQualityLevel == 0 or savedQualityLevel >= 7
		then 1
		elseif savedQualityLevel >= 4 then 2
		else 3
	if medianFrameMs and medianFrameMs > dropAboveMs then
		index = math.min(index + 1, #order)
	end
	return order[index]
end

function Rules.Median(samples: { number }): number?
	if #samples == 0 then
		return nil
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local mid = (#sorted + 1) / 2
	return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

-- Traversal toys never let a carrier (or a seated cart driver) gain speed or height.
function Rules.ToyAllowed(isCarrying: boolean, isSeated: boolean): boolean
	return not isCarrying and not isSeated
end

-- One-shot client push velocity (unit outward normal, Y = 0).
function Rules.PushVelocity(normal: Vector3, speed: number, lift: number, seated: boolean): Vector3
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 1e-6 then
		return Vector3.zero
	end
	return flat.Unit * speed + Vector3.yAxis * (if seated then lift * 0.4 else lift)
end

-- Session-only POI discovery: returns the POI names newly entered at this position.
-- Client-side Storm prediction: the first locked region containing (x, z), with the outward normal
-- and exit point of its nearest edge, as a StormPush-shaped message; nil when not inside one.
function Rules.PredictPush(
	locked: { [string]: boolean },
	boundaries: { [string]: any },
	geometry: any,
	position: Vector3
): any?
	for key in locked do
		local boundary = boundaries[key]
		if boundary and geometry.Contains(boundary.points, position.X, position.Z) then
			local hit = geometry.NearestEdge(boundary.points, position.X, position.Z)
			return {
				kind = "Push",
				regionKey = key,
				normal = Vector3.new(hit.normal.X, 0, hit.normal.Y),
				exit = Vector3.new(hit.point.X, position.Y, hit.point.Y),
				predicted = true,
			}
		end
	end
	return nil
end

function Rules.Discover(
	pois: { any },
	seen: { [string]: boolean },
	x: number,
	z: number
): { string }
	local found = {}
	for _, poi in pois do
		local dx, dz = x - poi.center[1], z - poi.center[2]
		if not seen[poi.name] and dx * dx + dz * dz <= poi.radius * poi.radius then
			seen[poi.name] = true
			table.insert(found, poi.name)
		end
	end
	return found
end

return table.freeze(Rules)
