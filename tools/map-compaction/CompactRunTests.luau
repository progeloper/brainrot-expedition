local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local T = require("./CompactTransform")
local B = require("./CompactBoundary")
local R = require("./CompactRoute")
local run = require("./CompactRouteTests")
local input = serde.decode("json", fs.readFile(process.args[1] or "CompactBaselineInput.json"))
local before = serde.encode("json", input)
local results = run(T, B, R, input)
assert(before == serde.encode("json", input), "Planner mutated captured baseline")
results.inputPreserved = true
results.runtime = "Official Lune 0.10.5 / local Luau"
results.baselineManagedContentSHA256 = input.baselineManagedContentSHA256
results.actualStudioTests = "NotRun"
fs.writeFile(process.args[2] or "CompactTestResults.json", serde.encode("json", results, true))
for _, row in ipairs(results.cases) do
	if not row.passed then
		print(row.name .. ": " .. row.error)
	end
end
print(string.format("%d passed, %d failed", results.passed, results.failed))
assert(results.failed == 0, "Pure geometry test failures")
