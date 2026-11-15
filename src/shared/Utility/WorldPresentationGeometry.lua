--!nocheck
local RS = game:GetService("ReplicatedStorage")
local C = require(RS.Shared.Config.PlaytestExact)
local M = require(RS.Shared.Config.PlaytestMeasurements)
local Geometry = require(RS.Shared.Config.CartGeometry)
local VoxelV4 = require(RS.Shared.Utility.VoxelCreatureRegistry)
local function body(species)
	return VoxelV4.SpeciesMeasurement(species, M.Species[species])
end
local API = {}
function API.Body(species)
	return body(species)
end
function API.GroundPivot(species, support)
	local measured = assert(body(species), "Unmeasured species")
	return support * CFrame.new(0, C.BodyGroundClearanceStuds, 0) * measured.G:Inverse()
end
function API.Layout(entries, columns, front, noseOrRear, supportY)
	local depths, poses = {}, {}
	local gap = C.Cargo.GapBetweenBodiesStuds
	for i, e in ipairs(entries) do
		local b = assert(body(e.speciesId), "Unmeasured species")
		local row = math.floor(((e.index or i) - 1) / columns) + 1
		depths[row] = math.max(depths[row] or 0, b.normalizedSize.Z)
	end
	local lo = Vector3.one * math.huge
	local hi = -lo
	for i, e in ipairs(entries) do
		local b = body(e.speciesId)
		local w, d = b.normalizedSize.X, b.normalizedSize.Z
		local row = math.floor(((e.index or i) - 1) / columns) + 1
		local z = noseOrRear + (if front then -1 else 1) * C.Cargo.DriverToCargoClearanceStuds
		for r = 1, row - 1 do
			z += (if front then -1 else 1) * ((depths[r] or 0) + gap)
		end
		z += (if front then -1 else 1) * d / 2
		local x = if columns == 1 then 0 else (if ((e.index or i) - 1) % 2 == 0 then -1 else 1) * (gap / 2 + w / 2)
		local g = Vector3.new(x, supportY, z)
		poses[i] = {
			support = CFrame.new(g),
			pivot = API.GroundPivot(e.speciesId, CFrame.new(g)),
			ground = g,
			size = b.normalizedSize,
		}
		lo = lo:Min(g - Vector3.new(w / 2, 0, d / 2))
		hi = hi:Max(g + Vector3.new(w / 2, b.normalizedSize.Y, d / 2))
	end
	return poses, lo, hi
end
function API.Cart(id)
	return Geometry[id]
end
return table.freeze(API)
