--!nocheck
-- Detached DEV Edit measurement only. No gameplay requires, initialization, registration or Source assignments.
local N = {}
local EXPECTED_SCALE = [==[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotVisualScale = {}

BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO = 0.64
-- Body-only bounds of the project's intended default R15 gameplay rig, measured
-- once with a clean HumanoidDescription (no accessories, Tools or HumanoidRootPart).
BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS = 5.457267761230469
BrainrotVisualScale.TARGET_HEIGHT_STUDS = BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS
	* BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO
BrainrotVisualScale.TOLERANCE_STUDS = math.max(0.03, BrainrotVisualScale.TARGET_HEIGHT_STUDS * 0.01)

local EXCLUDED_NAME_FRAGMENTS = {
	"hitbox",
	"proxy",
	"helper",
	"prompt",
	"indicator",
	"debug",
	"selection",
	"effect",
	"label",
	"capturednet",
	"carriedbrainrot",
	"cargovisual",
	"stored_",
}

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

-- This predicate deliberately does not depend on CanQuery/CanCollide. Carry,
-- cargo and storage presentations disable those properties after creation, but
-- their visible geometry must still measure identically to the world model.
function BrainrotVisualScale.IsVisualPart(part: BasePart, model: Model): boolean
	if not part:IsDescendantOf(model) or part.Transparency >= 1 then
		return false
	end
	local ancestor: Instance? = part
	while ancestor and ancestor ~= model do
		if ancestor:IsA("Tool") or ancestor:GetAttribute("BrainrotVisualHelper") == true then
			return false
		end
		local name = string.lower(ancestor.Name)
		for _, fragment in EXCLUDED_NAME_FRAGMENTS do
			if string.find(name, fragment, 1, true) then
				return false
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

-- Returns visual bounds in model-pivot space so callers can position the model
-- after scaling without allowing invisible gameplay geometry to affect contact.
function BrainrotVisualScale.GetVisualBounds(model: Model): (CFrame?, Vector3?, string?)
	local pivot = model:GetPivot()
	local low = Vector3.one * math.huge
	local high = Vector3.one * -math.huge
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and BrainrotVisualScale.IsVisualPart(descendant, model) then
			count += 1
			local frame = pivot:ToObjectSpace(descendant.CFrame)
			local half = descendant.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame * (half * Vector3.new(x, y, z))
						low = low:Min(point)
						high = high:Max(point)
					end
				end
			end
		end
	end
	if count == 0 then
		return nil, nil, "NO_VISIBLE_PARTS"
	end
	local size = high - low
	if not finite(size.X) or not finite(size.Y) or not finite(size.Z) or size.Y <= 0.0001 then
		return nil, nil, "INVALID_VISIBLE_BOUNDS"
	end
	return CFrame.new((low + high) / 2), size, nil
end

function BrainrotVisualScale.GetVisualHeight(model: Model): (number?, string?)
	local _, size, reason = BrainrotVisualScale.GetVisualBounds(model)
	if not size then
		return nil, reason
	end
	return size.Y, nil
end

function BrainrotVisualScale.GetCanonicalModelScale(model: Model): (number?, string?)
	local height, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not height then
		return nil, reason
	end
	local currentScale = model:GetScale()
	local scale = currentScale * (BrainrotVisualScale.TARGET_HEIGHT_STUDS / height)
	if not finite(scale) or scale <= 0 then
		return nil, "INVALID_CANONICAL_SCALE"
	end
	return scale, nil
end

-- Absolute and idempotent: correction is always derived from current visible
-- height, never from a previous lifecycle multiplier.
function BrainrotVisualScale.ApplyCanonicalScale(
	model: Model,
	context: string?
): (boolean, number?, string?)
	local currentHeight, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not currentHeight then
		return false, nil, reason
	end
	local currentScale = model:GetScale()
	local correction = BrainrotVisualScale.TARGET_HEIGHT_STUDS / currentHeight
	local newScale = currentScale * correction
	if
		not finite(currentScale)
		or currentScale <= 0
		or not finite(correction)
		or correction <= 0
		or not finite(newScale)
		or newScale <= 0
	then
		return false, nil, "INVALID_SCALE"
	end
	model:ScaleTo(newScale)
	local measured, measureReason = BrainrotVisualScale.GetVisualHeight(model)
	if not measured then
		return false, nil, measureReason
	end
	if ReplicatedStorage:GetAttribute("BrainrotScaleTrace") == true then
		print(
			string.format(
				"[BrainrotScale] context=%s model=%s item=%s before=%.6f target=%.6f correction=%.6f scale=%.6f after=%.6f",
				context or "unspecified",
				model:GetFullName(),
				tostring(model:GetAttribute("ItemId")),
				currentHeight,
				BrainrotVisualScale.TARGET_HEIGHT_STUDS,
				correction,
				model:GetScale(),
				measured
			)
		)
	end
	if
		math.abs(measured - BrainrotVisualScale.TARGET_HEIGHT_STUDS)
		> BrainrotVisualScale.TOLERANCE_STUDS
	then
		return false, measured, "TARGET_NOT_REACHED"
	end
	return true, measured, nil
end

return table.freeze(BrainrotVisualScale)
]==]
local SCALE_SHA = "c1982d3caa30bbbe32ceacd75cecf724c6ce6240026b53cf7d5bb68559b1ab4b"
local SOURCE_HASHES = {
	["ReplicatedStorage.Shared.Utility.BrainrotVisualScale"] = "c1982d3caa30bbbe32ceacd75cecf724c6ce6240026b53cf7d5bb68559b1ab4b",
	["ServerScriptService.Server.Systems.DevelopmentBrainrotSpawner"] = "8d199357e561523c4045eab6ce62d49a3bb67034bbe3ae47270f5b606166a743",
	["ServerScriptService.Server.Systems.DevelopmentBrainrotRoaming"] = "c54eca8daf7dd925dcddf4bcee09c87e6c3ccc54aacdd750e6073b74d5cbe4c0",
}
local OWNER = "BR_EnvironmentArt_V2_NativeWildExtent_QA"
local latestChunks
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
-- Pure conservative envelope from explicit pivot-relative points. No claim that box corners are rendered vertices.
function N.MeasurePositions(points)
	assert(type(points) == "table" and #points > 0, "Explicit finite geometry points required")
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local radial = 0
	for _, p in points do
		assert(type(p) == "table" and #p == 3, "XYZ point required")
		for axis = 1, 3 do
			assert(finite(p[axis]), "Finite point required")
			low[axis] = math.min(low[axis], p[axis])
			high[axis] = math.max(high[axis], p[axis])
		end
		radial = math.max(radial, math.sqrt(p[1] * p[1] + p[3] * p[3]))
	end
	return {
		min = low,
		max = high,
		size = { high[1] - low[1], high[2] - low[2], high[3] - low[3] },
		centreOffset = { (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2 },
		rootRadialExtent = radial,
		rotatingRootFootprintDiameter = 2 * radial,
		pointCount = #points,
		method = "Conservative pivot-relative extent-box envelope; not exact render-vertex radial maximum",
	}
end
local function corners(frame, size, pivot)
	local relative = pivot:ToObjectSpace(frame)
	local half = size / 2
	local points = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local p = relative * (half * Vector3.new(x, y, z))
				table.insert(points, { p.X, p.Y, p.Z })
			end
		end
	end
	return points
end
local function append(target, points)
	for _, point in points do
		table.insert(target, point)
	end
end
local function guardSources(context)
	local rows = {}
	for path, sha in SOURCE_HASHES do
		local captured
		for _, row in context.sources do
			if row.path == path then
				captured = row
				break
			end
		end
		assert(captured, "Fresh captured source missing: " .. path)
		local node = assert(context.refs[captured.key], "Current source identity missing")
		assert(node.Source == captured.source, "Actual current source changed: " .. path)
		assert(
			game:GetService("ScriptEditorService"):GetEditorSource(node) == captured.editorSource,
			"Current editor buffer changed: " .. path
		)
		if path == "ReplicatedStorage.Shared.Utility.BrainrotVisualScale" then
			assert(node.Source == EXPECTED_SCALE, "Approved scale bytes differ")
		end
		table.insert(rows, { path = path, bytes = #node.Source, sha256 = sha, exactReadbackMatchesCaptured = true })
	end
	table.sort(rows, function(a, b)
		return a.path < b.path
	end)
	return rows
end
function N.Run(options)
	options = options or {}
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Correct DEV Edit required; do not run during UI import ownership/Play"
	)
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	local Audit = options.auditAPI or assert(shared.EnvironmentV2AuditAPI, "Pass exact Audit API")
	local context = options.baseline or assert(shared.EnvironmentV2Baseline, "Fresh baseline required")
	assert(
		context.sourcesSHA256 == "ee0fac1b3cbbfa848181ecfa6997d0ba1dc0ab7091a6e778513b24ce41a55846",
		"Fresh357-source bundle binding required"
	)
	local sourceRows = guardSources(context)
	local Scale = assert(loadstring(EXPECTED_SCALE, "EnvironmentV2_ExactCurrentVisualScale"))()
	local templates = game:GetService("ReplicatedStorage").StudioAssets.Brainrots
	local sourceModels = {}
	for _, node in templates:GetChildren() do
		if node:IsA("Model") then
			table.insert(sourceModels, node)
		end
	end
	table.sort(sourceModels, function(a, b)
		return a.Name < b.Name
	end)
	assert(#sourceModels == 35, "Exactly35 accepted native templates required")
	local key = select(1, Audit.KeyFactory())
	local originals, before = {}, {}
	for _, model in sourceModels do
		table.insert(originals, model)
		for _, node in model:GetDescendants() do
			table.insert(originals, node)
		end
	end
	for _, node in originals do
		before[node] = Audit.Record(node, key)
	end
	local SS = game:GetService("ServerStorage")
	local stage = Instance.new("Folder")
	stage.Name = "EnvironmentV2_NativeWildExtents_QA_" .. game:GetService("HttpService"):GenerateGUID(false)
	stage:SetAttribute("ArtOwner", OWNER)
	stage:SetAttribute("NoRuntimeUse", true)
	stage.Parent = SS
	local r = {
		schemaVersion = 2,
		status = "Measuring",
		nativeExecuted = true,
		models = 35,
		rows = {},
		failures = {},
		worldWrites = 0,
		sourceWrites = 0,
		gameplayRequires = 0,
		gameplayInitOrStart = 0,
		runtimeRegistrations = 0,
		scaleSourceSHA256 = SCALE_SHA,
		sourceEvidence = sourceRows,
		assetSourceSHA256 = "f9e940205f6c35805cff5674ef0079347090d4a8a431b02dbef457b3aba05dec",
		W = 24,
		H = 22,
		clearHeight = 21.96,
		roamerPoseContract = "Current world factory preserves canonical scale and ground pivot; current roaming uses yaw-only poses. No actor path or profile edits.",
		scope = "All35 assets including3Teased; no release eligibility/spawn changes. Native PartOperation extent boxes and ordinary primitive envelopes are conservative, separately labeled from CFrame/Size proxies.",
	}
	local cloned, destroyed = 0, 0
	local clones = {}
	local ok, reason = xpcall(function()
		for index, template in sourceModels do
			assert(template.Name == string.format("BRT_%03d", index), "Stable35 IDs/order changed")
			local clone = assert(template:Clone(), "Template clone failed")
			table.insert(clones, clone)
			cloned += 1
			clone.Parent = stage
			for _, node in clone:GetDescendants() do
				assert(not node:IsA("LuaSourceContainer"), "Unexpected script inside accepted template")
				for _, tag in game:GetService("CollectionService"):GetTags(node) do
					game:GetService("CollectionService"):RemoveTag(node, tag)
				end
			end
			for _, tag in game:GetService("CollectionService"):GetTags(clone) do
				game:GetService("CollectionService"):RemoveTag(clone, tag)
			end
			local body = clone:FindFirstChild("Body", true)
			assert(
				body
					and body:IsA("BasePart")
					and body.CanQuery
					and body.Transparency < 1
					and body:FindFirstChild("CaptureAttachment")
					and body:FindFirstChild("CargoAttachment"),
				"Current factory Body/attachment prerequisite failed"
			)
			local scaled, proxyHeight, scaleReason =
				Scale.ApplyCanonicalScale(clone, "NativeWildExtentQA_SameWorldPreparedRule")
			assert(scaled, scaleReason)
			clone:PivotTo(CFrame.identity)
			local pivot = clone:GetPivot()
			local proxyPoints, nativePoints, parts = {}, {}, {}
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					if Scale.IsVisualPart(part, clone) then
						local proxy = corners(part.CFrame, part.Size, pivot)
						append(proxyPoints, proxy)
						local native, method
						if part:IsA("PartOperation") then
							local available, extentFrame, extentSize = pcall(function()
								return part.ExtentsCFrame, part.ExtentsSize
							end)
							if
								available
								and typeof(extentFrame) == "CFrame"
								and typeof(extentSize) == "Vector3"
								and extentSize.X > 0
								and extentSize.Y > 0
								and extentSize.Z > 0
							then
								native = corners(extentFrame, extentSize, pivot)
								method = "ActualPartOperationExtentsCFrameExtentsSize"
							else
								error(
									"NATIVE_EXTENTS_UNSUPPORTED:"
										.. template.Name
										.. "/"
										.. part.Name
										.. "; no proxy fallback. Actual mesh-vertex measurement is required before any maximum/fit pass."
								)
							end
						elseif part.ClassName == "Part" then
							native = proxy
							method = "OrdinaryPartPrimitiveCFrameSizeConservativeEnvelope"
						else
							error(
								"NATIVE_GEOMETRY_CLASS_UNSUPPORTED:" .. part.ClassName .. "; no proxy-only render claim"
							)
						end
						append(nativePoints, native)
						table.insert(parts, {
							name = part.Name,
							class = part.ClassName,
							method = method,
							proxy = N.MeasurePositions(proxy),
							native = N.MeasurePositions(native),
						})
					end
				end
			end
			local native, proxy = N.MeasurePositions(nativePoints), N.MeasurePositions(proxyPoints)
			table.insert(r.rows, {
				id = template.Name,
				canonicalScale = clone:GetScale(),
				proxyTargetHeight = proxyHeight,
				groundPivot = { pivot:GetComponents() },
				native = native,
				proxy = proxy,
				parts = parts,
				fitsRootYawTurningWidth = native.rotatingRootFootprintDiameter <= 24,
				fitsTopClearanceAtUnchangedGroundPivot = native.max[2] <= 21.96,
				fitsHeightSpan = native.size[2] <= 21.96,
				belowGroundPivotDepth = math.max(0, -native.min[2]),
				floorContactAdjusted = false,
				corridorFloorContact = "Report native below-pivot geometry explicitly; no scale or grounding correction performed. Separate full L-sweep/floor placement remains required.",
			})
			clone:Destroy()
			destroyed += 1
			task.wait()
		end
	end, debug.traceback)
	stage:Destroy()
	for _, clone in clones do
		clone:Destroy()
		assert(clone.Parent == nil, "Temporary clone orphan after cleanup")
	end
	r.temporaryStageRemoved = stage.Parent == nil
	r.temporaryClonesCreated = cloned
	r.temporaryClonesDestroyed = cloned
	r.normalCompletedCloneDestroyCount = destroyed
	local preservationChecks = 0
	for _, node in originals do
		preservationChecks += 1
		assert(
			node:IsDescendantOf(templates) and Audit.Equal(Audit.Record(node, key), before[node], 1e-6),
			"Original template changed during measurement"
		)
	end
	guardSources(context)
	r.originalTemplateNodesChecked = preservationChecks
	r.originalTemplatePropertiesUnchanged = true
	r.actualSourceReadbackUnchanged = true
	if ok then
		r.status = "NativeExtentMeasurementPassed"
		r.maximum = {
			rootRadialExtent = 0,
			rotatingRootFootprintDiameter = 0,
			width = 0,
			height = 0,
			depth = 0,
			topAbovePivot = 0,
			belowGroundPivotDepth = 0,
		}
		r.all35TurnWidthAndTopEnvelopePassed = true
		for _, row in r.rows do
			local values = {
				rootRadialExtent = row.native.rootRadialExtent,
				rotatingRootFootprintDiameter = row.native.rotatingRootFootprintDiameter,
				width = row.native.size[1],
				height = row.native.size[2],
				depth = row.native.size[3],
				topAbovePivot = row.native.max[2],
				belowGroundPivotDepth = row.belowGroundPivotDepth,
			}
			for field, value in values do
				if value > r.maximum[field] then
					r.maximum[field] = value
					r.maximum[field .. "Species"] = row.id
				end
			end
			if
				not (row.fitsRootYawTurningWidth and row.fitsTopClearanceAtUnchangedGroundPivot and row.fitsHeightSpan)
			then
				r.all35TurnWidthAndTopEnvelopePassed = false
			end
		end
	else
		r.status = "FailedNativeExtentMeasurement"
		r.failures = { tostring(reason) }
		r.maximum = nil
		r.all35TurnWidthAndTopEnvelopePassed = false
	end
	r.fullBurrowSweepPassed = false
	r.geometryPassDoesNotEnableRuntimeBurrows = true
	local encoded = game:GetService("HttpService"):JSONEncode(r)
	latestChunks = Audit.UTF8Chunks(encoded)
	shared.EnvironmentV2WildNativeExtentsResult = r
	return {
		status = r.status,
		modelsCompleted = #r.rows,
		chunks = #latestChunks,
		bytes = #encoded,
		maximum = r.maximum,
		all35TurnWidthAndTopEnvelopePassed = r.all35TurnWidthAndTopEnvelopePassed,
		temporaryStageRemoved = r.temporaryStageRemoved,
		originalTemplatePropertiesUnchanged = r.originalTemplatePropertiesUnchanged,
		sourceWrites = 0,
		fullBurrowSweepPassed = false,
	}
end
function N.GetChunk(index)
	assert(latestChunks and latestChunks[index], "Completed actual measurement chunk missing")
	return { index = index, text = latestChunks[index], bytes = #latestChunks[index], chunks = #latestChunks }
end
return N
