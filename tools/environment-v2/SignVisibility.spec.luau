local function expect(condition, message)
	assert(condition, message or "Pure sign visibility regression failed")
end
local Verify = require("./Verify")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local repo = "/Users/noahodukoya/development/Roblox/BrainrotExpedition/"
local manifest =
	serde.decode("json", fs.readFile(repo .. "docs/environment-v2/FrozenApplyManifest.json"))
local old = serde.decode(
	"json",
	fs.readFile(repo .. "docs/environment-v2/revisions/v1/FrozenApplyManifest.json")
)
local count = 0
local function case(name, callback)
	callback()
	count += 1
	print("PASS " .. name)
end
local function box(x, y, z, sx, sy, sz)
	return { x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, { sx, sy, sz }
end
case("ray crosses opaque box continuously", function()
	local f, s = box(0, 0, 0, 2, 2, 2)
	expect(Verify.SignSegmentIntersectsBox({ -3, 0, 0 }, { 3, 0, 0 }, f, s))
end)
case("parallel clear and grazing rays stay clear", function()
	local f, s = box(0, 0, 0, 2, 2, 2)
	expect(not Verify.SignSegmentIntersectsBox({ -3, 2, 0 }, { 3, 2, 0 }, f, s))
	expect(not Verify.SignSegmentIntersectsBox({ -3, 1, 0 }, { 3, 1, 0 }, f, s))
end)
case("viewpoint inside obstacle is rejected even on zero segment", function()
	local f, s = box(0, 0, 0, 2, 2, 2)
	expect(Verify.SignSegmentIntersectsBox({ 0, 0, 0 }, { 0, 0, 0 }, f, s))
	expect(not Verify.SignSegmentIntersectsBox({ 2, 0, 0 }, { 2, 0, 0 }, f, s))
end)
case("rotated native box uses its own axes", function()
	local f = { 3, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0 }
	expect(Verify.SignSegmentIntersectsBox({ 3, 0, -3 }, { 3, 0, 3 }, f, { 4, 2, 1 }))
	expect(not Verify.SignSegmentIntersectsBox({ 4, 0, -3 }, { 4, 0, 3 }, f, { 4, 2, 1 }))
end)
case("invalid finite geometry does not silently pass", function()
	local f, s = box(0, 0, 0, 2, 2, 2)
	expect(not pcall(Verify.SignSegmentIntersectsBox, { 0 / 0, 0, 0 }, { 0, 0, 0 }, f, s))
end)
local function hitCount(row, all)
	local p = row.signFaceProxy
	local f = p.cframe
	local n = 0
	for _, u in { -1, -0.5, 0, 0.5, 1 } do
		for _, v in { -1, 0, 1 } do
			local localPoint = { u * 8, v * 2.5, 0.05 }
			local endpoint = {}
			for axis = 1, 3 do
				endpoint[axis] = f[axis]
					+ f[axis + 3] * localPoint[1]
					+ f[axis + 6] * localPoint[2]
					+ f[axis + 9] * localPoint[3]
			end
			for _, other in all do
				for _, c in other.colliders or {} do
					if
						Verify.SignSegmentIntersectsBox(
							p.clearanceEvidence.legalViewpoint,
							endpoint,
							c.cframe,
							c.size
						)
					then
						n += 1
					end
				end
			end
		end
	end
	return n
end
local currentById = {}
for _, r in manifest.objects do
	currentById[r.id] = r
end
case("exact two approved poses and cameras are accepted", function()
	for _, id in { "Gate_Volcano_Header_01", "Gate_Jungle_Header_01" } do
		local r = currentById[id]
		expect(Verify.SignPresentationCorrection(r.signFaceProxy, r))
	end
end)
case("correction cannot authorize different pose camera or owner", function()
	local r = currentById.Gate_Volcano_Header_01
	for _, kind in { "pose", "camera", "owner", "scope" } do
		local p = serde.decode("json", serde.encode("json", r.signFaceProxy))
		local owner = { id = r.id }
		if kind == "pose" then
			p.cframe[1] += 1
		elseif kind == "camera" then
			p.clearanceEvidence.legalViewpoint[1] += 1
		elseif kind == "owner" then
			owner.id = "Gate_Beach_Header_01"
		else
			p.sourceContractSHA256 = string.rep("0", 64)
		end
		expect(not pcall(Verify.SignPresentationCorrection, p, owner))
	end
end)
case("unknown sign override is rejected", function()
	local p = { presentationOverride = "Anything", clearanceEvidence = {} }
	expect(not pcall(Verify.SignPresentationCorrection, p, {}))
end)
case("all six source poses clear full face samples against all305 planned colliders", function()
	local signs, colliders = 0, 0
	for _, r in manifest.objects do
		colliders += #(r.colliders or {})
	end
	expect(colliders == 305)
	for _, r in manifest.objects do
		if r.signFaceProxy then
			signs += 1
			expect(hitCount(r, manifest.objects) == 0, r.id .. " blocked")
		end
	end
	expect(signs == 6)
end)
case("old actual occluded Volcano and Jungle poses are reproduced", function()
	local found = 0
	for _, r in old.objects do
		if r.id == "Gate_Volcano_Header_01" or r.id == "Gate_Jungle_Header_01" then
			r.signFaceProxy.clearanceEvidence.legalViewpoint =
				currentById[r.id].signFaceProxy.clearanceEvidence.legalViewpoint
			expect(hitCount(r, manifest.objects) > 0, r.id .. " must reproduce blocker")
			found += 1
		end
	end
	expect(found == 2)
end)
print("TOTAL " .. count .. " pure sign visibility tests passed; native execution not asserted")
