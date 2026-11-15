-- Lune CLI. Numeric output comes from the production pure Luau modules.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local T = require("./CompactTransform")
local B = require("./CompactBoundary")
local R = require("./CompactRoute")
local input = serde.decode("json", fs.readFile(process.args[1] or "CompactBaselineInput.json"))
local c = T.Candidate(tonumber(process.args[3]) or 0.75, tonumber(process.args[4]) or 0.75)
local source = B.Extract(input.floors)
local targetFloors = {}
for _, row in ipairs(input.floors) do
	table.insert(targetFloors, T.Rectangle(row, c))
end
local target = B.Extract(targetFloors)
local envelope = { x0 = math.huge, x1 = -math.huge, z0 = math.huge, z1 = -math.huge }
for _, floor in ipairs(targetFloors) do
	envelope.x0 = math.min(envelope.x0, floor.x0)
	envelope.x1 = math.max(envelope.x1, floor.x1)
	envelope.z0 = math.min(envelope.z0, floor.z0)
	envelope.z1 = math.max(envelope.z1, floor.z1)
end
envelope.width = envelope.x1 - envelope.x0
envelope.depth = envelope.z1 - envelope.z0
assert(
	#source.sharedRuns == 18 and #target.sharedRuns == 18,
	"Baseline shared-boundary topology changed"
)
local runs = B.MapRuns(source.sharedRuns, c, T)
local routePlan = R.Build(input.routes, c, T, input.connectivityCaps)
local connectivity = R.ConnectedComponents(routePlan.primitives)
local aprons = R.GateAprons(input.gates, routePlan, input.gateRouteOwners, c, T)
local crossingPlan =
	R.Crossings(input.routes, source.sharedRuns, runs, aprons, input.legacySeparators, c, T)
local subtract = B.Subtract(runs, crossingPlan.openings, 6)
local junctions = B.Junctions(subtract.spans, crossingPlan.openings, 6)
local walls = B.Chunk(junctions.spans, 128, input.floors[1].ground, 6)
local existing = B.ClassifyExisting(input.legacySeparators, source)
local outer = {}
for _, old in ipairs(existing) do
	for _, portion in ipairs(old.portions) do
		if portion.kind == "OuterContainment" then
			local run = {
				id = old.id,
				axis = old.source.axis,
				fixed = old.source.fixed,
				first = portion.first,
				last = portion.last,
				regionId = old.regionId,
				key = old.id,
			}
			local mapped = B.MapRuns({ run }, c, T)[1]
			local cf, size = table.clone(old.source.cframe), table.clone(old.source.size)
			local alongAxis, normalAxis =
				if old.source.axis == "X" then 1 else 3, if old.source.axis == "X" then 3 else 1
			cf[alongAxis] = (mapped.first + mapped.last) / 2
			cf[normalAxis] = mapped.fixed + (old.source.cframe[normalAxis] - old.source.fixed)
			size[alongAxis] = mapped.last - mapped.first
			table.insert(
				outer,
				{
					id = old.id,
					path = old.path,
					regionId = old.regionId,
					sourcePortion = portion,
					targetSemanticSpan = mapped,
					cframe = cf,
					size = size,
					sourceCFrame = old.source.cframe,
					sourceSize = old.source.size,
					sourceFlags = old.source.flags,
					policy = "Preserve captured outer physical containment only; exact inward side offset/thickness/height retained",
				}
			)
		end
	end
end
local order = {
	REGION_CAMP = 1,
	REGION_FOREST = 2,
	REGION_BEACH = 3,
	REGION_SWAMP = 4,
	REGION_JUNGLE = 5,
	REGION_ARCTIC = 6,
	REGION_VOLCANO = 7,
	REGION_GLITCH = 8,
}
local palette = {
	REGION_CAMP = { 165, 192, 174 },
	REGION_FOREST = { 143, 171, 128 },
	REGION_BEACH = { 255, 236, 179 },
	REGION_SWAMP = { 121, 156, 131 },
	REGION_JUNGLE = { 151, 176, 111 },
	REGION_ARCTIC = { 132, 199, 237 },
	REGION_VOLCANO = { 133, 111, 157 },
	REGION_GLITCH = { 132, 144, 233 },
}
for _, wall in ipairs(walls) do
	local p = wall.regionPair
	local region = if order[p[1]] > order[p[2]] then p[1] else p[2]
	wall.tintRegion = region
	wall.tintRGB = palette[region]
end
local plan = {
	schemaVersion = 1,
	migrationId = input.migrationId,
	baselineManagedContentSHA256 = input.baselineManagedContentSHA256,
	beforeManifestSHA256 = input.beforeManifestSHA256,
	sourceBundleSHA256 = input.sourceBundleSHA256,
	actualRoadBindingsSHA256 = input.actualRoadBindingsSHA256,
	sourceLayoutVersion = input.sourceLayoutVersion,
	routePointsCanonicalSHA256 = input.routePointsCanonicalSHA256,
	candidate = c,
	selectedCandidate = false,
	applyEligible = false,
	fitStatus = "NotRun",
	sourceEvidence = input.sourceEvidence,
	floors = targetFloors,
	floorEnvelope = envelope,
	sourceRegionAreas = source.regionAreas,
	targetRegionAreas = target.regionAreas,
	sourceSharedRuns = source.sharedRuns,
	sharedRuns = runs,
	sourceOuterRuns = source.outerRuns,
	existingSeparatorClassification = existing,
	retainedOuterContainment = outer,
	routes = routePlan.routes,
	routePrimitives = routePlan.primitives,
	connectivityCaps = routePlan.caps,
	routeConnectivity = connectivity,
	gateAprons = aprons,
	crossings = crossingPlan.records,
	approvedOpeningPolygons = crossingPlan.openings,
	wallCuts = subtract.cuts,
	unresolvedParallelCorridors = crossingPlan.parallelConflicts,
	junctions = junctions.junctions,
	junctionConflicts = junctions.failures,
	walls = walls,
	wallFlags = {
		Anchored = true,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
		CastShadow = true,
		Transparency = 0,
		Reflectance = 0,
		CollisionGroup = "Default",
		CollisionFidelity = "Box",
		RenderFidelity = "Automatic",
		DoubleSided = false,
		Material = "Glacier",
		MaterialVariant = "Bingus_Saved_Studs_13719188279",
		StudsPerTile = 0.25,
		StudMaterialAssetId = 13719188279,
	},
	wallAssetStatus = "Native shared cuboid ID not bound; source geometry/Part fallback only",
	wallBudget = {
		maximumChunkLength = 128,
		count = #walls,
		targetCount = 128,
		partCountTargetPassed = #walls <= 128,
		sourceClosedCuboidTriangles = #walls * 12,
		actualNativeTriangles = "NotMeasured",
	},
	limitations = {
		"Numeric plan is not a selected/fit-passed candidate or live installation",
		"Native route polygon union/mesh import and installed geometry readback remain required; numeric465-primitives surface component is1",
		"All frozen base/service/spawn/landmark and loaded-cart fit checks must pass",
		"Corner relief remains under each paid gate ID; physical side/jamb and neighbor-access validation required",
		"Source mesh/UV identities and static stud appearance must be preserved by application",
		"Existing outer containment must retain original instance references/physical local offsets",
	},
}
fs.writeFile(process.args[2] or "CompactDraftPlan.json", serde.encode("json", plan, true))
print(
	serde.encode(
		"json",
		{
			candidate = c,
			sharedRuns = #runs,
			routes = #plan.routes,
			crossings = #plan.crossings,
			openings = #plan.approvedOpeningPolygons,
			walls = #walls,
			outerPortions = #outer,
			parallelConflicts = #plan.unresolvedParallelCorridors,
			junctionConflicts = #plan.junctionConflicts,
			applyEligible = false,
		},
		true
	)
)
