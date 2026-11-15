--!strict
-- Existing repository TestEZ-style DSL, scoped to a fresh PRIVATE native place.
-- Ordinary DEV Play and the original world are expressly rejected.
local Run=game:GetService("RunService")
local Players=game:GetService("Players")
assert(Run:IsStudio() and not Run:IsRunning() and game.PlaceId==0,"Fresh unsaved private native Edit test place required")
assert(game:GetAttribute("CompactMapTestCopyOwner")=="CompactMap_V1","Explicit owned test-copy marker required")
assert(game:GetAttribute("CompactMapTestSourceBundleSHA256")=="b6c37961e3f9cfbbdb1d894299228068f5be2a8441f812b728426fd5046494b8","Fresh captured source authority required")
assert(game:GetAttribute("CompactMapTestCurrentOwnerSourcesVerified")==true,"Root must byte-verify five approved owners/new utility before execution")
assert(game:GetAttribute("BrainrotTestDiagnosticsDisabled")==true,"Disable diagnostics in the owned private copy before execution")
assert(#Players:GetPlayers()==0 and workspace:FindFirstChild("MapBlockout")==nil and workspace:FindFirstChild("Runtime")==nil,"Blank private test world required; never reset the current live world")
for _,v in game:GetService("ServerScriptService"):GetDescendants() do
 if v:IsA("Script") then assert(not v.Enabled,"Private copy bootstraps must be disabled") end
end
local scope=game:GetAttribute("CompactMapTestSpecScope")
assert(scope=="Relevant" or scope=="Full","Explicit Relevant or Full suite scope required")
local relevant={
 ["BaseIncomePlaqueSystem.spec"]=true,["BaseSignSystem.spec"]=true,["BrainrotPlatformPlacement.spec"]=true,
 ["BrainrotPlatformIncome.spec"]=true,["BrainrotSaleSystem.spec"]=true,["BrainrotSalePointSystem.spec"]=true,
 ["RegionSpawnCatalog.spec"]=true,["RegionGuardMath.spec"]=true,["RegionGateDescriptors.spec"]=true,
 ["RegionAccessService.spec"]=true,["WorldProgressionRuntime.spec"]=true,["WorldProgressionPersistence.spec"]=true,
 ["UpgradeService.spec"]=true,["CartSpawnValidator.spec"]=true,["CartResetMath.spec"]=true,
 ["PlayerProfileSchema.spec"]=true,["PlayerSessionIsolation.spec"]=true,["BaseStorageTransfer.spec"]=true,
 ["BankedBrainrotPersistence.spec"]=true,["CampReturnSweep.spec"]=true,
}
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
local failures = {}

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
		table.insert(failures,{scope="TestCase",name=nameWithContext,error=tostring(failure)})
		warn(string.format("[BRAINROT_TEST][FAIL] %s\n%s", nameWithContext, tostring(failure)))
	end
end

local specModules = {}

for _, descendant in testsFolder:GetDescendants() do
	if descendant:IsA("ModuleScript") and string.match(descendant.Name, "%.spec$") ~= nil and (scope=="Full" or relevant[descendant.Name]) then
		table.insert(specModules, descendant)
	end
end

table.sort(specModules, function(left, right)
	return left:GetFullName() < right:GetFullName()
end)

if scope=="Relevant" then
 local found={};for _,m in specModules do found[m.Name]=true end
 for name in relevant do assert(found[name],"Required actual spec missing: "..name) end
end
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
		table.insert(failures,{scope="SpecFile",name=currentSpecName,error=tostring(failure)})
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

local report={schemaVersion=1,status=if passed then "ActualNativePrivateSuitePassed" else "ActualNativePrivateSuiteFailed",scope=scope,totals=totals,failures=failures,
 sourceAuthority="Root byte-verified captured356 with five owner proposals/newUtility",ordinaryGameplayAcceptancePassed=false,placeId=game.PlaceId,
 worldScope="Fresh owned blank test place; specs may create/teardown their private fixtures; main DEV untouched"}
local out=Instance.new("StringValue");out.Name="CompactMapV1_PrivateTests_"..scope;out:SetAttribute("Owner","CompactMap_V1")
out.Value=game:GetService("HttpService"):JSONEncode(report);out.Parent=game:GetService("ServerStorage")
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

return report
