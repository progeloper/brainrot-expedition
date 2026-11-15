local function expect(condition)
	assert(condition, "Pure native extent envelope regression failed")
end
local N = require("./MeasureWildNativeExtents")
local passed = 0
local function case(name, fn)
	fn()
	passed += 1
	print("PASS " .. name)
end
case("radial envelope includes root offset rather than half bbox size", function()
	local r = N.MeasurePositions({ { 0, 0, 0 }, { 8, 2, 0 } })
	expect(
		r.size[1] == 8 and r.centreOffset[1] == 4 and r.rootRadialExtent == 8 and r.rotatingRootFootprintDiameter == 16
	)
	expect(r.rotatingRootFootprintDiameter > 12)
end)
case("rotating envelope combines both horizontal axes", function()
	local r = N.MeasurePositions({ { -3, -1, -4 }, { 3, 2, 4 } })
	expect(r.rootRadialExtent == 5 and r.rotatingRootFootprintDiameter == 10 and r.size[2] == 3)
end)
case("native proxy discrepancy remains numerically distinct", function()
	local proxy = N.MeasurePositions({ { 0, 0, 0 }, { 0, 3.49, 5.21804566681385 } })
	local native = N.MeasurePositions({ { 0, 0, 0 }, { 0, 3.49, 5.747914791107178 } })
	expect(math.abs((native.max[3] - proxy.max[3]) - 0.5298691242933273) < 1e-12)
	expect(native.rotatingRootFootprintDiameter > proxy.rotatingRootFootprintDiameter)
end)
case("below-ground pivot depth is not hidden by height span", function()
	local r = N.MeasurePositions({ { 0, -0.7, 0 }, { 0, 3.49, 0 } })
	expect(r.min[2] == -0.7 and math.abs(r.size[2] - 4.19) < 1e-9 and r.max[2] == 3.49)
end)
case("unsupported empty or nonfinite measurements cannot pass", function()
	expect(not pcall(N.MeasurePositions, {}))
	expect(not pcall(N.MeasurePositions, { { 0, math.huge, 0 } }))
	expect(not pcall(N.MeasurePositions, { { 0, 0 / 0, 0 } }))
end)
print("WILD_NATIVE_EXTENT_PURE_TESTS " .. passed .. " passed0failed; native geometry not executed")
return { passed = passed, failed = 0, nativeExecuted = false }
