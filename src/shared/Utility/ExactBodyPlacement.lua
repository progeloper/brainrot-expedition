--!strict
-- Only revision-keyed verified geometry is eligible. No guessed H/bounds.
local C = require(script.Parent.Parent.Config.PlaytestExact)
local Placement = {}
-- `multiplier` (Playtest Fixes size ladder) overrides C.BrainrotHeightMultiplier for this model.
function Placement.Normalize(model, metadata, H, multiplier)
	if type(H) ~= "number" or H <= 0 or H ~= H or math.abs(H) == math.huge then
		return false, "MISSING_REFERENCE_RIG"
	end
	if not metadata or metadata.verified ~= true then
		return false, "MEASUREMENT_BLOCKED"
	end
	local h0 = metadata.ymax - metadata.ymin
	if h0 <= 0 or h0 ~= h0 or math.abs(h0) == math.huge then
		return false, "INVALID_BODY_BOUNDS"
	end
	local target = metadata.s0 * (multiplier or C.BrainrotHeightMultiplier) * H / h0
	model:ScaleTo(target)
	return true, target
end
function Placement.Pivot(support, G)
	return support * CFrame.new(0, C.BodyGroundClearanceStuds, 0) * G:Inverse()
end
function Placement.Cargo(rows, deckTop, driverRear)
	local depths = { 0, 0, 0 }
	local result = {}
	local config = C.Cargo
	for _, v in ipairs(rows) do
		local r = math.floor((v.index - 1) / config.Columns) + 1
		assert(r <= config.MaximumRows, "Maximum cargo rows exceeded")
		depths[r] = math.max(depths[r], v.depth)
	end
	for _, v in ipairs(rows) do
		local r = math.floor((v.index - 1) / config.Columns) + 1
		local column = (v.index - 1) % config.Columns
		local front = driverRear + config.DriverToCargoClearanceStuds
		for k = 1, r - 1 do
			front += depths[k] + config.GapBetweenBodiesStuds
		end
		result[v.id] = Vector3.new(
			(if column == 0 then -1 else 1) * (config.GapBetweenBodiesStuds / 2 + v.width / 2),
			deckTop + config.RackGroundClearanceForBodiesStuds,
			front + v.depth / 2
		)
	end
	return result
end
function Placement.CameraDistance(corners, verticalFov, aspect, D0)
	local a = math.tan(math.rad(verticalFov) / 2) * C.Cargo.CameraFrameFraction
	local b = math.tan(math.atan(math.tan(math.rad(verticalFov) / 2) * aspect))
		* C.Cargo.CameraFrameFraction
	local fitted = -math.huge
	for _, v in ipairs(corners) do
		fitted = math.max(fitted, math.abs(v.Y) / a - v.Z, math.abs(v.X) / b - v.Z)
	end
	return math.max(D0, fitted + C.Cargo.CameraMarginStuds)
end
return table.freeze(Placement)
