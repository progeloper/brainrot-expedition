--!nocheck
-- Install only as a temporary ordinary DEV ServerScript after existing gameplay initializes.
-- This reads the actual server VM cache. Never execute this through the privileged MCP require cache.
local Run = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local OWNER = "BR_EnvironmentArt_V2"
local VARIANT = "Bingus_Saved_Studs_13719188279"
assert(Run:IsStudio() and Run:IsServer() and Run:IsRunning(), "Actual ordinary DEV server Play required")
assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
assert(
	script:IsA("Script") and script.Parent == SSS and script:GetAttribute("ReadOnlyEnvironmentQA") == true,
	"Use explicitly owned temporary ServerScript"
)
local label = script:GetAttribute("RunLabel") or "After"
assert(type(label) == "string" and #label <= 64 and label:match("^[%w_%-]+$"), "Bounded RunLabel required")
local Profile = require(SSS.Server.Services.PlayerDataService)
local World = require(SSS.Server.Systems.DevelopmentBrainrotSpawner)
local count = 0
local function copy(value, depth)
	depth = depth or 0
	count += 1
	assert(depth <= 14 and count <= 25000, "Complete readback bound exceeded")
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return value
	end
	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Nonfinite observation")
		return value
	end
	if kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	end
	if kind == "CFrame" then
		return { value:GetComponents() }
	end
	if kind == "Instance" then
		return value:GetFullName()
	end
	if kind ~= "table" then
		return tostring(value)
	end
	local result = {}
	for k, v in value do
		result[k] = copy(v, depth + 1)
	end
	return result
end
local report = {
	schemaVersion = 2,
	scope = "ActualOrdinaryDEVServerScript_ReadOnly",
	label = label,
	placeId = game.PlaceId,
	timestamp = DateTime.now():ToIsoDate(),
	checks = 0,
	failed = 0,
	failures = {},
	players = {},
	gates = {},
	gameplayWrites = 0,
	profileWrites = 0,
	currencyWrites = 0,
	remoteCalls = 0,
	moduleInitOrStartCalls = 0,
	newEnvironmentRuntimeScripts = 0,
	qaScriptTemporary = true,
	screenVisibility = "NotAssessed_ServerEnabledAndBindingAreNotActualPixels",
	fullGameplayAcceptancePassed = false,
	loadedCartTour = "NotRunByCollector",
	phonePerformance = "NotAssessed",
	multiplayerPerformance = "NotAssessed",
}
local function check(condition, name)
	report.checks += 1
	if not condition then
		report.failed += 1
		table.insert(report.failures, name)
	end
end
check(#Players:GetPlayers() > 0, "Actual ordinary player present")
for _, player in Players:GetPlayers() do
	local data, reason = Profile:GetReadableData(player)
	local diagnostics = Profile:GetDiagnostics(player)
	local row = {
		name = player.Name,
		userId = player.UserId,
		status = Profile:GetStatus(player),
		writable = Profile:IsWritable(player),
		readableReason = reason,
		diagnostics = copy(diagnostics),
		profile = data and copy({
			Economy = data.Economy,
			Collection = data.Collection,
			Base = data.Base,
			WorldProgression = data.WorldProgression,
			Progression = data.Progression,
		}) or nil,
	}
	check(
		row.status == "Ready" and row.writable and data ~= nil,
		"Existing initialized readable/writable profile " .. player.Name
	)
	check(
		diagnostics and diagnostics.isolatedTestProfile == false,
		"Ordinary profile rather than isolated fixture " .. player.Name
	)
	table.insert(report.players, row)
end
report.population = copy(World.GetPopulationSnapshot())
check(report.population.Running == true, "Existing actual spawner already running; never initialized by collector")
check(report.population.Target == 42, "Original configured global42 limit")
check(
	report.population.Wild >= 0 and report.population.Reserved >= 0 and report.population.Effective <= 42,
	"Actual current global population<=42"
)
local map = assert(workspace:FindFirstChild("MapBlockout"), "Current map missing")
local layer = assert(map:FindFirstChild("EnvironmentArt_V2"), "Actual installed layer missing")
check(
	layer:GetAttribute("ArtOwner") == OWNER and layer:GetAttribute("EnvironmentV2Status") == "Completed",
	"Installed owned layer completed"
)
report.layer = {
	models = 0,
	visible = 0,
	colliders = 0,
	signFaces = 0,
	baseParts = 0,
	instances = 1 + #layer:GetDescendants(),
	markers = 0,
	artRuntimeRegisteredMarkers = 0,
}
for _, node in layer:GetDescendants() do
	if node:IsA("Model") and node:GetAttribute("EnvironmentId") then
		report.layer.models += 1
	end
	if node:IsA("LuaSourceContainer") or node:IsA("SurfaceGui") or node:IsA("ParticleEmitter") or node:IsA("Light") then
		check(false, "No new runtime/UI/effect instance inside art layer")
	end
	if node:IsA("BasePart") then
		report.layer.baseParts += 1
		local role = node:GetAttribute("EnvironmentRole")
		if role == "Visible" or role == "VisibleSignFace" then
			report.layer.visible += 1
			if role == "VisibleSignFace" then
				report.layer.signFaces += 1
			end
			check(
				node.Anchored
					and not node.CanCollide
					and not node.CanQuery
					and not node.CanTouch
					and node.Transparency == 0,
				"Static opaque nonphysical visible art " .. node.Name
			)
			check(
				node.Material == Enum.Material.Glacier
					and node.MaterialVariant == VARIANT
					and node:GetAttribute("StudsPerTile") == 0.25,
				"Uniform savedstuds " .. node.Name
			)
		elseif role == "Collider" then
			report.layer.colliders += 1
			check(
				node.ClassName == "Part"
					and node.Shape == Enum.PartType.Block
					and node.Anchored
					and node.CanCollide
					and node.CanQuery
					and not node.CanTouch
					and node.Transparency == 1,
				"Exact simple collider flags " .. node.Name
			)
		else
			check(false, "Unclassified new BasePart " .. node.Name)
		end
	end
	if node:IsA("Attachment") and node.Name:match("^Art_") then
		report.layer.markers += 1
		if node:GetAttribute("Art_RuntimeRegistered") ~= false then
			report.layer.artRuntimeRegisteredMarkers += 1
		end
	end
end
check(
	report.layer.models == 147
		and report.layer.visible == 277
		and report.layer.colliders == 305
		and report.layer.baseParts == 582
		and report.layer.instances == 786,
	"Actual installed selected layer count signature"
)
check(
	report.layer.signFaces == 6 and report.layer.markers == 56 and report.layer.artRuntimeRegisteredMarkers == 0,
	"Six signfaces/four inactive markers for14 placed burrows"
)
local gates = map:FindFirstChild("ProgressionGates")
local enabled, bound = 0, 0
for _, gate in gates:GetChildren() do
	local sign = gate:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("GateSign")
	if gui and gui:IsA("SurfaceGui") then
		local part = gui.Adornee
		local usable = part
			and part:IsA("Part")
			and part:IsDescendantOf(layer)
			and part:GetAttribute("EnvironmentRole") == "VisibleSignFace"
		if gui.Enabled then
			enabled += 1
		end
		if usable then
			bound += 1
		end
		check(
			usable and gui.Face == Enum.NormalId.Back and gui.Enabled and not gui.AlwaysOnTop,
			"Original gate GUI binding/FaceBack/Enabled " .. gate.Name
		)
		if usable then
			check(
				part.Size.X == 16
					and part.Size.Y == 5
					and math.abs(part.Size.Z - 0.1) < 1e-6
					and not part.CanCollide
					and not part.CanQuery
					and not part.CanTouch,
				"Approved nonphysical16x5x.1 signface " .. gate.Name
			)
		end
		local labels = {}
		for _, child in gui:GetDescendants() do
			if child:IsA("TextLabel") then
				table.insert(labels, { path = child:GetFullName(), text = child.Text, visible = child.Visible })
			end
		end
		table.insert(
			report.gates,
			{
				gate = gate.Name,
				guiPath = gui:GetFullName(),
				originalSignPath = sign:GetFullName(),
				guiParentUnchanged = gui.Parent == sign,
				enabled = gui.Enabled,
				alwaysOnTop = gui.AlwaysOnTop,
				face = gui.Face.Name,
				adornee = part and part:GetFullName(),
				usableOwnedAdornee = usable == true,
				text = labels,
				actualPixelReadability = "NotAssessed; normal client/cart screenshot required",
				paidPhysicalClosure = "ExistingNotAchieved_PreserveAccessOwner",
			}
		)
	end
end
check(#report.gates == 6 and enabled == 6 and bound == 6, "All six original GUI surfaces present/enabled/bound")
report.surfaceGuiEnabledCount = enabled
report.surfaceGuiUsableOwnedAdorneeCount = bound
local models, parts, attachments = 0, 0, 0
for _, model in RS.StudioAssets.Brainrots:GetChildren() do
	if model:IsA("Model") then
		models += 1
		local bodies = 0
		for _, node in model:GetDescendants() do
			if node:IsA("BasePart") then
				parts += 1
				if node.Name == "Body" then
					bodies += 1
					check(
						node.CanQuery
							and node.Transparency < 1
							and node:FindFirstChild("CaptureAttachment")
							and node:FindFirstChild("CargoAttachment"),
						"Original Body/attachment identity " .. model.Name
					)
				end
				if node.Transparency < 1 then
					check(
						node.Material == Enum.Material.Glacier and node.MaterialVariant == VARIANT,
						"Original visible brainrot savedmaterial " .. model.Name .. "/" .. node.Name
					)
				end
			end
			if node:IsA("Attachment") and (node.Name == "CaptureAttachment" or node.Name == "CargoAttachment") then
				attachments += 1
			end
		end
		check(bodies == 1, "Exactlyone original Body " .. model.Name)
	end
end
check(models == 35 and parts == 890 and attachments == 70, "Original35/890/70 numerical contract")
report.originalBrainrots = {
	models = models,
	baseParts = parts,
	bodyAttachments = attachments,
	fullTypedPropertyAnd357SourcePreservation = "Separate actual Edit verifier; runtime contract count is not full byte/property proof",
}
report.passed = report.failed == 0
report.status = if report.passed
	then "ReadOnlyOrdinaryRuntimeChecksPassed_AcceptancePartial"
	else "ReadOnlyOrdinaryRuntimeChecksFailed"
local encoded = Http:JSONEncode(report)
local chunks = {}
local pos = 1
while pos <= #encoded do
	local last = math.min(#encoded, pos + 59999)
	while last < #encoded do
		local b = string.byte(encoded, last + 1)
		if b and b >= 128 and b <= 191 then
			last -= 1
		else
			break
		end
	end
	local chunk = encoded:sub(pos, last)
	assert(#chunk <= 60000 and utf8.len(chunk), "UTF8-safe chunk required")
	table.insert(chunks, chunk)
	pos = last + 1
end
assert(table.concat(chunks) == encoded, "Complete report bytes required")
local name = "EnvironmentV2_RuntimeReadOnly_" .. label
assert(not SS:FindFirstChild(name), "Use uniqueRunLabel; never overwrite an unrelated/previous report")
local out = Instance.new("Folder")
out.Name = name
out:SetAttribute("ArtOwner", OWNER)
out:SetAttribute("NoRuntimeUse", true)
out:SetAttribute("ReadbackOnly", true)
out:SetAttribute("Complete", false)
out.Parent = SS
for index, text in chunks do
	local node = Instance.new("StringValue")
	node.Name = string.format("Chunk_%04d", index)
	node.Value = text
	node.Parent = out
end
out:SetAttribute("Bytes", #encoded)
out:SetAttribute("ChunkCount", #chunks)
out:SetAttribute("Checks", report.checks)
out:SetAttribute("Failed", report.failed)
out:SetAttribute("Passed", report.passed)
out:SetAttribute("Complete", true)
print(
	"[EnvironmentV2 ReadOnly] "
		.. out:GetFullName()
		.. " chunks="
		.. #chunks
		.. " bytes="
		.. #encoded
		.. " checks="
		.. report.checks
		.. " failed="
		.. report.failed
)
