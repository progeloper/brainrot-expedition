--!strict
-- Pure helpers for the first-session visual checkpoint. Reads existing odds and
-- income definitions; never changes or rolls them.
local RS = game:GetService("ReplicatedStorage")
local Phase12 = require(RS.Shared.Config.Phase12)
local MutationCatalog = require(RS.Shared.Config.MutationCatalog)
local Phase12Rules = require(RS.Shared.Utility.Phase12Rules)

local Rules = {}

-- "1 in X" text for a probability. Whole numbers from 10 upward, one decimal below.
function Rules.FormatOdds(probability: number?): string?
	if
		type(probability) ~= "number"
		or probability ~= probability
		or probability <= 0
		or probability > 1
	then
		return nil
	end
	local x = 1 / probability
	if x >= 10 then
		return string.format("1 in %d", math.floor(x + 0.5))
	end
	local rounded = math.floor(x * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("1 in %d", rounded)
	end
	return string.format("1 in %.1f", rounded)
end

-- Absolute chance of a spawn carrying this mutation (None/Normal returns nil).
function Rules.MutationProbability(mutationId: any, totalChance: number?): number?
	local id = Phase12Rules.NormalizeMutation(mutationId)
	if id == nil or id == "None" then
		return nil
	end
	local entry = MutationCatalog.ById[id]
	if not entry then
		return nil
	end
	return (if totalChance == nil then Phase12.MutationChance else totalChance) * entry.share
end

-- Tier chance within a region's configured tier weights.
function Rules.TierProbability(tierWeights: { [string]: number }?, tier: string?): number?
	if type(tierWeights) ~= "table" or type(tier) ~= "string" then
		return nil
	end
	local total = 0
	for _, weight in pairs(tierWeights) do
		if type(weight) == "number" and weight > 0 then
			total += weight
		end
	end
	local weight = tierWeights[tier]
	if total <= 0 or type(weight) ~= "number" or weight <= 0 then
		return nil
	end
	return weight / total
end

-- Same effective rate the name tag shows: catalogue rate x mutation multiplier.
function Rules.EffectiveIncome(cashPerSecond: number?, mutationId: any): number?
	if type(cashPerSecond) ~= "number" then
		return nil
	end
	local ok, multiplier = pcall(Phase12Rules.MutationMultiplier, mutationId or "None")
	return cashPerSecond * (if ok and type(multiplier) == "number" then multiplier else 1)
end

-- Clip an upright box so its top is no higher than capY. Returns nil when nothing
-- of the box remains, or the original box when it is not upright.
function Rules.ClipBoxTop(frame: CFrame, size: Vector3, capY: number): (CFrame?, Vector3?)
	if math.abs(frame.UpVector.Y) < 0.99 then
		return frame, size
	end
	local half = size.Y / 2
	local bottom, top = frame.Position.Y - half, frame.Position.Y + half
	if top <= capY then
		return frame, size
	end
	if capY - bottom < 1 then
		return nil, nil
	end
	local height = capY - bottom
	local rotation = frame - frame.Position
	local centre = Vector3.new(frame.Position.X, bottom + height / 2, frame.Position.Z)
	return CFrame.new(centre) * rotation, Vector3.new(size.X, height, size.Z)
end

export type Rect = { MinX: number, MinY: number, MaxX: number, MaxY: number }

-- Overlap area divided by the smaller rectangle's area (0 when disjoint).
function Rules.OverlapFraction(a: Rect, b: Rect): number
	local w = math.min(a.MaxX, b.MaxX) - math.max(a.MinX, b.MinX)
	local h = math.min(a.MaxY, b.MaxY) - math.max(a.MinY, b.MinY)
	if w <= 0 or h <= 0 then
		return 0
	end
	local areaA = (a.MaxX - a.MinX) * (a.MaxY - a.MinY)
	local areaB = (b.MaxX - b.MinX) * (b.MaxY - b.MinY)
	local smaller = math.min(areaA, areaB)
	return if smaller > 0 then (w * h) / smaller else 0
end

-- Greedy declutter: rects are in priority order; returns a keep flag per index.
function Rules.Declutter(rects: { Rect }, threshold: number): { boolean }
	local keep = {}
	local kept: { Rect } = {}
	for index, rect in ipairs(rects) do
		local clear = true
		for _, other in ipairs(kept) do
			if Rules.OverlapFraction(rect, other) >= threshold then
				clear = false
				break
			end
		end
		keep[index] = clear
		if clear then
			table.insert(kept, rect)
		end
	end
	return keep
end

-- Point where a screen-edge arrow should sit for an off-screen target.
-- screenPoint is the target projected to the viewport (behind-camera already mirrored).
function Rules.EdgePoint(screenPoint: Vector2, viewport: Vector2, margin: number): (Vector2, number)
	local centre = viewport / 2
	local direction = screenPoint - centre
	if direction.Magnitude < 1e-3 then
		direction = Vector2.new(0, -1)
	end
	local halfW, halfH = math.max(centre.X - margin, 1), math.max(centre.Y - margin, 1)
	local scale = math.min(
		halfW / math.max(math.abs(direction.X), 1e-6),
		halfH / math.max(math.abs(direction.Y), 1e-6)
	)
	local point = centre + direction * scale
	return point, math.deg(math.atan2(direction.Y, direction.X))
end

return table.freeze(Rules)
