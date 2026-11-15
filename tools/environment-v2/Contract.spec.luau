local function expect(condition)
	assert(condition, "Pure environment contract regression failed")
end
local Audit = require("./AuditBaseline")
local Verify = require("./Verify")
local passed = 0
local function case(name, fn)
	fn()
	passed += 1
	print("PASS " .. name)
end
local function budget()
	return {
		visible = 384,
		colliders = 360,
		baseParts = 744,
		instances = 1500,
		triangles = 40000,
		meshIds = 36,
		scenery = 133,
		trees = 36,
		boundary = 64,
		motifs = 4,
		burrows = 15,
		heroes = 8,
	}
end
case("frozen colorRGB group alias is accepted exactly", function()
	local color = Verify.PaletteRGB({ colorRGB = { 143, 171, 128 }, groupId = "A" }, {})
	expect(color[1] == 143 and color[2] == 171 and color[3] == 128)
end)
case("out-of-range or nonbyte RGB cannot be silently clamped", function()
	for _, color in { { 256, 0, 0 }, { 0, -1, 0 }, { 0, 0, 0.5 }, { 0, 0, math.huge } } do
		expect(not pcall(Verify.PaletteRGB, { colorRGB = color }, {}))
	end
end)
case("conflicting color aliases are rejected", function()
	expect(not pcall(Verify.PaletteRGB, { colorRGB = { 1, 2, 3 }, color = { 1, 2, 4 } }, {}))
end)
case("all independent authored ceilings accepted at their boundary", function()
	expect(Verify.ValidateCounts(budget()))
end)
for _, limit in
	{
		{ "visible", 385 },
		{ "colliders", 361 },
		{ "baseParts", 751 },
		{ "instances", 1501 },
		{ "triangles", 40001 },
		{ "meshIds", 37 },
		{ "scenery", 134 },
		{ "trees", 37 },
		{ "motifs", 5 },
	}
do
	case("reject exceeded " .. limit[1], function()
		local b = budget()
		b[limit[1]] = limit[2]
		if limit[1] == "visible" or limit[1] == "colliders" then
			b.baseParts = b.visible + b.colliders
		end
		expect(not pcall(Verify.ValidateCounts, b))
	end)
end
case("seventy safety boundary modules report unmet target without raising hard budgets", function()
	local b = budget()
	b.boundary = 70
	expect(Verify.ValidateCounts(b))
	local target = Verify.BoundaryTarget(b.boundary)
	expect(target.target == 64 and target.actual == 70 and target.met == false and target.status == "NotMet")
end)
case("boundary target rejects invalid counts", function()
	for _, value in { -1, 1.5, math.huge } do
		local b = budget()
		b.boundary = value
		expect(not pcall(Verify.ValidateCounts, b))
	end
end)
local function campException()
	return {
		{
			id = "Burrow_Camp_Unplaced",
			role = "Burrow",
			prototypeId = "BurrowCore",
			regionId = "REGION_CAMP",
			reason = "Full immutable scene search could not fit canonical shell/apron",
			evidence = {
				status = "NoFitAfterFullDeterministicSearch",
				baselineSceneSHA256 = string.rep("a", 64),
				assetSourceSHA256 = string.rep("b", 64),
				minimumBoundaryDepthTested = 8,
				allCardinalYawsTested = true,
				gridStepStuds = 4,
				exactProjectionTested = true,
				candidatesEvaluated = 128,
			},
		},
	}
end
case("only the documented Camp no-fit contract permits fourteen burrows", function()
	local b = budget()
	b.burrows = 14
	expect(Verify.ValidateCounts(b, campException()))
end)
case("other region omission cannot use the Camp exception", function()
	local b, exception = budget(), campException()
	b.burrows = 14
	exception[1].regionId = "REGION_FOREST"
	expect(not pcall(Verify.ValidateCounts, b, exception))
end)
case("prepared or incomplete Camp search is rejected", function()
	local b, exception = budget(), campException()
	b.burrows = 14
	exception[1].evidence.exactProjectionTested = false
	expect(not pcall(Verify.ValidateCounts, b, exception))
end)
case("Camp no-fit without exact tested source identity is rejected", function()
	local b, exception = budget(), campException()
	b.burrows = 14
	exception[1].evidence.assetSourceSHA256 = nil
	expect(not pcall(Verify.ValidateCounts, b, exception))
end)
case("multiple missing mandatory slots are rejected", function()
	local b, exception = budget(), campException()
	b.burrows = 13
	exception[2] = exception[1]
	expect(not pcall(Verify.ValidateCounts, b, exception))
end)
case("dictionary omission cannot evade dense-array validation", function()
	local b = budget()
	expect(not pcall(Verify.ValidateCounts, b, { Camp = campException()[1] }))
end)
local function triangleException()
	return {
		originalLimit = 40000,
		maximumApprovedActual = 44000,
		sourceProjectedTriangles = 43558,
		actualInstalledTriangles = 43558,
		sourceSHA256 = "f9e940205f6c35805cff5674ef0079347090d4a8a431b02dbef457b3aba05dec",
		baselineSceneSHA256 = "f396b10caf4d1ab7e6b9aa8dd61fcab89bc904f33d95c899de887ac9950089e9",
		basis = "CurrentUserBrickDirective",
		reason = "Selected smaller-brick composition retains14 terraces and14 ruins",
	}
end
case("only exact selected brick composition can use documented triangle exception", function()
	local b = budget()
	b.triangles = 43558
	expect(Verify.ValidateCounts(b, nil, triangleException()))
	expect(b.triangles > 40000)
end)
case("triangle exception cannot hide actual native projection mismatch", function()
	local b = budget()
	b.triangles = 43560
	expect(not pcall(Verify.ValidateCounts, b, nil, triangleException()))
end)
case("triangle exception cannot raise source or scene permission generally", function()
	for _, key in { "sourceSHA256", "baselineSceneSHA256", "basis" } do
		local b, e = budget(), triangleException()
		b.triangles = 43558
		e[key] = "unreviewed"
		expect(not pcall(Verify.ValidateCounts, b, nil, e))
	end
end)
case("triangle exception cannot exceed44000 or loosen other budgets", function()
	local b, e = budget(), triangleException()
	b.triangles = 44001
	e.actualInstalledTriangles = 44001
	expect(not pcall(Verify.ValidateCounts, b, nil, e))
	b, e = budget(), triangleException()
	b.triangles = 43558
	b.colliders = 361
	b.baseParts = b.visible + b.colliders
	expect(not pcall(Verify.ValidateCounts, b, nil, e))
end)
case("all parts must be role-counted; hidden root cannot consume slack", function()
	local b = budget()
	b.baseParts = 745
	expect(not pcall(Verify.ValidateCounts, b))
end)
case("mandatory burrow cannot be silently omitted", function()
	local b = budget()
	b.burrows = 14
	expect(not pcall(Verify.ValidateCounts, b))
end)
case("mandatory hero slots cannot be silently omitted", function()
	local b = budget()
	b.heroes = 7
	expect(not pcall(Verify.ValidateCounts, b))
end)
case("NaN or fractional costs cannot evade budget", function()
	local b = budget()
	b.triangles = 0 / 0
	expect(not pcall(Verify.ValidateCounts, b))
	b = budget()
	b.meshIds = 1.5
	expect(not pcall(Verify.ValidateCounts, b))
end)
case("duplicate full-name refs retain distinct identities", function()
	expect(
		not Audit.Equal(
			{ type = "Instance", key = "Part[1]", path = "Sell Sign.Part" },
			{ type = "Instance", key = "Part[2]", path = "Sell Sign.Part" },
			0
		)
	)
end)
case("archived ref keeps exact identity despite path change", function()
	expect(
		Audit.Equal(
			{ type = "Instance", key = "Part[1]", path = "Workspace.OldArt.Part" },
			{ type = "Instance", key = "Part[1]", path = "ServerStorage.Archive.Part" },
			0
		)
	)
end)
case("nil differs from missing property and zero", function()
	expect(not Audit.Equal({ type = "nil" }, nil, 0))
	expect(not Audit.Equal({ type = "nil" }, 0, 0))
end)
case("unapproved attribute addition is visible to equality", function()
	expect(not Audit.Equal({ Owner = 1 }, { Owner = 1, Added = 2 }, 0))
end)
case("bounded native float tolerance does not accept large movement", function()
	expect(Audit.Equal({ 1, 2, 3 }, { 1.0000005, 2, 3 }, 1e-6))
	expect(not Audit.Equal({ 1, 2, 3 }, { 1.001, 2, 3 }, 1e-6))
end)
for _, example in
	{
		{ "ASCII large source", string.rep("a", 500161) },
		{ "accented boundary", string.rep("a", 59999) .. "é" .. string.rep("b", 60001) },
		{ "four-byte boundary", string.rep("a", 59998) .. "🧱" .. string.rep("b", 60001) },
		{ "mixed report", string.rep("BRT_007×🧱\n", 14000) },
	}
do
	case("UTF8 complete bounded " .. example[1], function()
		local chunks = Audit.UTF8Chunks(example[2])
		expect(table.concat(chunks) == example[2])
		for _, c in chunks do
			expect(#c <= 60000 and utf8.len(c) ~= nil)
		end
	end)
end
print("ENVIRONMENT_V2_PURE_TESTS " .. passed .. " passed 0 failed")
return {
	passed = passed,
	failed = 0,
	scope = "Pure contracts only; no Roblox collision/import/gameplay/visual pass inferred",
}
