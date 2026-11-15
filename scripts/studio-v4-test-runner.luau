-- Voxel V4 targeted runner: same dependency-free TestEZ-style DSL as
-- studio-test-runner.luau, restricted to VoxelCreatureV4.spec (only what changed).
-- Disposable Rojo build in Edit mode; no historical suites, profiles or Play.
-- Executes the repository's dependency-free TestEZ-style companion suite.
-- CartCarryGuard runs separately in studio-native-boarding-test-runner.luau:
-- Edit-mode RunScript does not advance native Humanoid seat state/cooldowns.
-- Supported DSL, audited on 2026-08-03: describe, it, expect(...).to.equal,
-- expect(...).never.to.equal, expect(function).to.throw, and
-- expect(function).never.to.throw.

-- The suite reports each test result itself. Keep the optional live transaction
-- trace out of headless output so long suites remain bounded and deterministic.
game:SetAttribute("BrainrotTestDiagnosticsDisabled", true)

-- Rojo owns code and deliberately excludes the creator-owned Studio materials.
-- Supply the same saved material dependency only in this disposable test place.
local materials=game:GetService("MaterialService")
if not materials:FindFirstChild("Bingus_Saved_Studs_13719188279") then
	local studs=Instance.new("MaterialVariant")
	studs.Name="Bingus_Saved_Studs_13719188279"
	studs.BaseMaterial=Enum.Material.Glacier
	studs.StudsPerTile=.25
	studs.ColorMap="rbxassetid://10509831729"
	studs.NormalMap="rbxassetid://10509831753"
	studs.Parent=materials
end

-- Match the current live environment material dependency as well. Both
-- material libraries remain creator-owned and excluded from the Rojo build.
if not materials:FindFirstChild("Environment_Saved_Studs_13719188279") then
 local studs=Instance.new("MaterialVariant")
 studs.Name="Environment_Saved_Studs_13719188279"
 studs.BaseMaterial=Enum.Material.Glacier
 studs.StudsPerTile=4
 studs.ColorMap="rbxassetid://10509831729"
 studs.NormalMap="rbxassetid://10509831753"
 studs.Parent=materials
end

-- The saved creature stud binding (v979: AF2_Creature_SmoothPlastic, same saved
-- stud images) is creator-owned and excluded from Rojo; mirror it here only.
if not materials:FindFirstChild("AF2_Creature_SmoothPlastic") then
	local studs=Instance.new("MaterialVariant")
	studs.Name="AF2_Creature_SmoothPlastic"
	studs.BaseMaterial=Enum.Material.SmoothPlastic
	studs.StudsPerTile=.55
	studs.ColorMap="rbxassetid://126387978066468"
	studs.NormalMap="rbxassetid://124160206245321"
	studs.Parent=materials
end

local ServerScriptService = game:GetService("ServerScriptService")

local testsFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Tests")
local suiteStack = {}
local totals = {
	Files = 0,
	FileErrors = 0,
	Tests = 0,
	Passed = 0,
	Failed = 0,
}

local currentSpecName = "<none>"

local function formatValue(value)
	local valueType = typeof(value)

	if valueType == "string" then
		return string.format("%q", value)
	elseif valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return tostring(value)
	elseif valueType == "Instance" then
		return string.format("<%s %s>", value.ClassName, value:GetFullName())
	elseif valueType == "table" or valueType == "function" then
		return string.format("<%s>", valueType)
	end

	return string.format("<%s %s>", valueType, tostring(value))
end

local function fullTestName(testName)
	local segments = { currentSpecName }

	for _, suiteName in suiteStack do
		table.insert(segments, suiteName)
	end

	table.insert(segments, testName)

	return table.concat(segments, " > ")
end

local expectationMetatable = {}

function expectationMetatable.__index(expectation, key)
	if key == "to" then
		return expectation
	elseif key == "never" then
		return setmetatable({
			PackedActual = rawget(expectation, "PackedActual"),
			Negated = not expectation.Negated,
		}, expectationMetatable)
	elseif key == "equal" then
		return function(expected)
			local actual = rawget(expectation, "PackedActual")[1]
			local equal = actual == expected
			local passed = if expectation.Negated then not equal else equal

			if not passed then
				error(
					string.format(
						"Expected %s %sto equal %s",
						formatValue(actual),
						if expectation.Negated then "not " else "",
						formatValue(expected)
					),
					2
				)
			end
		end
	elseif key == "throw" then
		return function()
			local actual = rawget(expectation, "PackedActual")[1]

			if type(actual) ~= "function" then
				error(
					string.format("Expected a function for throw assertion, got %s", type(actual)),
					2
				)
			end

			local callSucceeded, callResult = pcall(actual)
			local threw = not callSucceeded
			local passed = if expectation.Negated then not threw else threw

			if not passed then
				error(
					if expectation.Negated
						then string.format(
							"Expected function not to throw, got %s",
							tostring(callResult)
						)
						else "Expected function to throw",
					2
				)
			end
		end
	end

	error(string.format("Unsupported expectation member %q", tostring(key)), 2)
end

local function expectValue(actual)
	return setmetatable({
		PackedActual = table.pack(actual),
		Negated = false,
	}, expectationMetatable)
end

local function describe(name, callback)
	assert(type(name) == "string", "describe name must be a string")
	assert(type(callback) == "function", "describe callback must be a function")

	table.insert(suiteStack, name)
	local succeeded, failure = xpcall(callback, debug.traceback)
	table.remove(suiteStack)

	if not succeeded then
		error(failure, 0)
	end
end

local function it(name, callback)
	assert(type(name) == "string", "it name must be a string")
	assert(type(callback) == "function", "it callback must be a function")

	totals.Tests += 1
	local nameWithContext = fullTestName(name)
	local succeeded, failure = xpcall(callback, debug.traceback)

	if succeeded then
		totals.Passed += 1
		print(string.format("[BRAINROT_TEST][PASS] %s", nameWithContext))
	else
		totals.Failed += 1
		warn(string.format("[BRAINROT_TEST][FAIL] %s\n%s", nameWithContext, tostring(failure)))
	end
end

local specModules = {}

for _, descendant in testsFolder:GetDescendants() do
	if descendant:IsA("ModuleScript") and descendant.Name == "VoxelCreatureV4.spec" then
		table.insert(specModules, descendant)
	end
end

table.sort(specModules, function(left, right)
	return left:GetFullName() < right:GetFullName()
end)

print(string.format("[BRAINROT_TEST_DISCOVERY] files=%d", #specModules))

for _, specModule in specModules do
	totals.Files += 1
	currentSpecName = specModule.Name
	table.clear(suiteStack)

	local testsBefore = totals.Tests
	local passedBefore = totals.Passed
	local failedBefore = totals.Failed
	local succeeded, failure = xpcall(function()
		local specFactory = require(specModule)

		assert(type(specFactory) == "function", "spec ModuleScript must return a function")

		local originalEnvironment = getfenv(specFactory)
		local testEnvironment = setmetatable({
			describe = describe,
			it = it,
			expect = expectValue,
		}, {
			__index = originalEnvironment,
		})

		setfenv(specFactory, testEnvironment)
		specFactory()
	end, debug.traceback)

	if not succeeded then
		totals.FileErrors += 1
		warn(
			string.format("[BRAINROT_TEST][FILE_ERROR] %s\n%s", currentSpecName, tostring(failure))
		)
	end

	print(
		string.format(
			"[BRAINROT_TEST_FILE] name=%s tests=%d passed=%d failed=%d fileError=%s",
			currentSpecName,
			totals.Tests - testsBefore,
			totals.Passed - passedBefore,
			totals.Failed - failedBefore,
			tostring(not succeeded)
		)
	)
end

local passed = totals.Files > 0
	and totals.FileErrors == 0
	and totals.Tests > 0
	and totals.Failed == 0
	and totals.Passed == totals.Tests

print(
	string.format(
		"[BRAINROT_TEST_SUMMARY] files=%d fileErrors=%d tests=%d passed=%d failed=%d",
		totals.Files,
		totals.FileErrors,
		totals.Tests,
		totals.Passed,
		totals.Failed
	)
)
print(string.format("[BRAINROT_TEST_RESULT] %s", if passed then "PASS" else "FAIL"))

if not passed then
	error(
		string.format(
			"[BRAINROT_TEST_FAILURE] files=%d fileErrors=%d tests=%d passed=%d failed=%d",
			totals.Files,
			totals.FileErrors,
			totals.Tests,
			totals.Passed,
			totals.Failed
		),
		0
	)
end
