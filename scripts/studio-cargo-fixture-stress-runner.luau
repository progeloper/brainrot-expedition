-- Focused Phase 7 unblock diagnostic. This deliberately reuses the production
-- BrainrotCargoLoading spec factory and its real service paths; it does not
-- duplicate cargo logic. The original three phases remain unchanged; an extra
-- LegacyIsolation phase covers direct AddCargo ownership and the subsequent
-- ground-unavailable -> factory-unavailable fixture boundary.

-- This runner intentionally executes thousands of production-path cases. The
-- transaction trace is valuable for live diagnosis but changes this bounded
-- stress run into gigabytes of duplicate output, so silence only that optional
-- diagnostic channel before any production module is required.
game:SetAttribute("BrainrotTestDiagnosticsDisabled", true)

local ServerScriptService = game:GetService("ServerScriptService")
local spec = ServerScriptService.Server.Tests:FindFirstChild("BrainrotCargoLoading.spec")
assert(spec and spec:IsA("ModuleScript"), "BrainrotCargoLoading.spec is unavailable")

local ITERATIONS = 500
local iteration = 0
local suiteStack = {}
local failures = {}
local selectedRuns = 0
local currentPhase = "Focused"

local phases = {
	{
		Name = "Focused",
		Fragments = {
			"retains removed-cart records while factory is unavailable",
			"does not also release an individual already moved to carry",
			"rejects premature replacement and keeps the third carried individual intact",
		},
	},
	{
		Name = "Broad",
		Fragments = {
			"cancels an unfinished fixture-owned return before the next fixture",
			"unlocks one authored slot from owner entitlement",
			"does not also release an individual already moved to carry",
			"invalidates yielding load staging when the cart is removed",
			"rejects premature replacement and keeps the third carried individual intact",
			"rechecks the complete slot map after staging",
		},
	},
	{
		Name = "Cascade",
		Fragments = {
			"interleaved pickup has one winner and a stale request cannot remove a replacement",
			"publishes count once after source retirement without world return or income callbacks",
			"loads 3 then 1 then 2 with original IDs",
			"rejects occupied/full, invalid and stale requests without consuming carry",
		},
	},
	{
		Name = "LegacyIsolation",
		Fragments = {
			"legacy secured cargo needs no new sleep flag",
			"retains removed-cart records while ground is unavailable",
			"retains removed-cart records while factory is unavailable",
		},
	},
}
local selectedFragments = phases[1].Fragments

local function selected(name)
	for _, fragment in selectedFragments do
		if string.find(name, fragment, 1, true) then
			return true
		end
	end
	return false
end

local expectationMetatable = {}

function expectationMetatable.__index(expectation, key)
	if key == "to" then
		return expectation
	elseif key == "never" then
		return setmetatable({
			Actual = rawget(expectation, "Actual"),
			Negated = not rawget(expectation, "Negated"),
		}, expectationMetatable)
	elseif key == "equal" then
		return function(expected)
			local actual = rawget(expectation, "Actual")
			local negated = rawget(expectation, "Negated")
			local equal = actual == expected
			if (negated and equal) or (not negated and not equal) then
				error(
					string.format(
						"Expected %s %sto equal %s",
						tostring(actual),
						if negated then "not " else "",
						tostring(expected)
					),
					2
				)
			end
		end
	elseif key == "throw" then
		return function()
			local ok = pcall(rawget(expectation, "Actual"))
			local negated = rawget(expectation, "Negated")
			if (negated and not ok) or (not negated and ok) then
				error("Unexpected throw result", 2)
			end
		end
	end
	error("Unsupported expectation member " .. tostring(key), 2)
end

local function expectValue(actual)
	return setmetatable({ Actual = actual, Negated = false }, expectationMetatable)
end

local function describe(name, callback)
	table.insert(suiteStack, name)
	local ok, failure = xpcall(callback, debug.traceback)
	table.remove(suiteStack)
	if not ok then
		error(failure, 0)
	end
end

local function it(name, callback)
	if not selected(name) then
		return
	end
	selectedRuns += 1
	local ok, failure = xpcall(callback, debug.traceback)
	if not ok then
		local path = table.concat(suiteStack, " > ") .. " > " .. name
		table.insert(failures, {
			Iteration = iteration,
			Name = path,
			Failure = tostring(failure),
		})
		warn(
			string.format(
				"[CARGO_STRESS][FAIL] phase=%s iteration=%d test=%s\n%s",
				currentPhase,
				iteration,
				path,
				tostring(failure)
			)
		)
	end
end

local factory = require(spec)
local originalEnvironment = getfenv(factory)
local totalFailures = 0
local totalSelectedRuns = 0

for _, phase in phases do
	currentPhase = phase.Name
	selectedFragments = phase.Fragments
	table.clear(failures)
	selectedRuns = 0
	for index = 1, ITERATIONS do
		iteration = index
		table.clear(suiteStack)
		setfenv(
			factory,
			setmetatable({
				describe = describe,
				it = it,
				expect = expectValue,
			}, { __index = originalEnvironment })
		)
		local ok, failure = xpcall(factory, debug.traceback)
		if not ok then
			table.insert(failures, {
				Iteration = iteration,
				Name = "spec registration",
				Failure = tostring(failure),
			})
		end
	end
	local cargo = require(ServerScriptService.Server.Services.CartCargoService)
	local diagnostics = cargo:GetRemovalDiagnostics()
	print(
		string.format(
			"[CARGO_STRESS_SUMMARY] phase=%s iterations=%d selectedRuns=%d failures=%d pendingReturns=%d rng=not_used",
			phase.Name,
			ITERATIONS,
			selectedRuns,
			#failures,
			#diagnostics.PendingIds
		)
	)
	for _, failure in failures do
		print(
			string.format(
				"[CARGO_STRESS_FAILURE] phase=%s iteration=%d test=%s failure=%s",
				phase.Name,
				failure.Iteration,
				failure.Name,
				failure.Failure
			)
		)
	end
	totalFailures += #failures
	totalSelectedRuns += selectedRuns
end

local finalDiagnostics =
	require(ServerScriptService.Server.Services.CartCargoService):GetRemovalDiagnostics()
print(
	string.format(
		"[CARGO_STRESS_TOTAL] phases=%d iterationsPerPhase=%d selectedRuns=%d failures=%d pendingReturns=%d",
		#phases,
		ITERATIONS,
		totalSelectedRuns,
		totalFailures,
		#finalDiagnostics.PendingIds
	)
)

if totalFailures > 0 or #finalDiagnostics.PendingIds > 0 then
	error(
		string.format(
			"Cargo fixture stress retained failures=%d pendingReturns=%d",
			totalFailures,
			#finalDiagnostics.PendingIds
		),
		0
	)
end
