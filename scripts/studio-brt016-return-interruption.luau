--!nocheck
-- Install only into the isolated Development Play server after the route gate.
-- Actual map/model and production lifecycle; synthetic actor, no profile/storage.
assert(game:GetService("RunService"):IsStudio() and game.PlaceId == 91958083796436)
local S = game.ServerScriptService.Server.Systems
local W, R, N, I =
	require(S.DevelopmentBrainrotSpawner),
	require(S.DevelopmentBrainrotRoaming),
	require(S.NaturalTerritory),
	require(S.BrainrotInteractionSystem)
local cargo = require(game.ServerScriptService.Server.Services.CartCargoService)
local gate = game.ServerScriptService:FindFirstChild("BRT016Closure")
assert(gate and gate:GetAttribute("Done") and not gate:GetAttribute("Error"))
assert(W.GetWildCount() == 0, "Do not overlap a route or retire unrelated individuals")
local original, observedState, model = N.SelectReturnStep, nil, nil
N.SelectReturnStep = function(...)
	local a = table.pack(...)
	local result = original(table.unpack(a, 1, a.n))
	if model and (a[1] - model:GetPivot().Position).Magnitude < 0.01 then
		observedState = a[6]
	end
	return result
end
local evidence, character, event, actor = {}, nil, nil, nil
local ok, failure = xpcall(function()
	R.Start()
	local pose = CFrame.new(-30.1413136, 3, 253.5541992)
	local record = assert(W.CreateWorldRecord("BRT_016", "ReturnInterruption", pose))
	local prepared = assert(W.PrepareWorldRepresentation(record, pose))
	prepared.Model:PivotTo(assert(W.FindSafeReleasePose(prepared, pose, {}, true)))
	model = assert(W.ActivatePreparedWorld(prepared))
	evidence.id = record.ItemId
	evidence.returnRegion = model:GetAttribute("CampReturnRegionId")
	local started = os.clock()
	repeat
		task.wait(0.1)
	until observedState or os.clock() - started > 5
	assert(observedState and evidence.returnRegion == "REGION_JUNGLE")
	task.wait(2)
	local oldState = observedState
	evidence.before = R.GetDiagnostics()
	assert(W.TrySleep(model))
	local firstDeadline = model:GetAttribute("BrainrotSleepUntil")
	local pausedPosition = model:GetPivot().Position
	task.wait(0.5)
	evidence.sleepPaused = R.GetDiagnostics().Paused == 1
		and (model:GetPivot().Position - pausedPosition).Magnitude < 0.01
	assert(evidence.sleepPaused)
	-- The normal world scheduler is intentionally not started in this isolated
	-- server. Advance its existing expiration owner using real elapsed server time.
	repeat
		task.wait(0.1)
	until workspace:GetServerTimeNow() >= firstDeadline
	evidence.expired = W.ProcessSleepExpirations()
	started = os.clock()
	repeat
		task.wait(0.1)
	until observedState ~= oldState or os.clock() - started > 5
	evidence.freshSteering = observedState ~= oldState
	assert(evidence.expired == 1 and evidence.freshSteering, "Sleep retained old return steering")
	assert(W.TrySleep(model))
	local pickupDeadline = model:GetAttribute("BrainrotSleepUntil")
	local p = model:GetPivot().Position
	character = Instance.new("Model")
	character.Name, character.Parent = "BRT016DiagnosticActor", workspace
	local function part(name, position)
		local v = Instance.new("Part")
		v.Name, v.Size, v.Position = name, Vector3.new(2, 2, 1), position
		v.Anchored, v.CanCollide, v.Parent = true, false, character
		return v
	end
	local root = part("HumanoidRootPart", p + Vector3.new(4, 3, 0))
	part("Head", root.Position + Vector3.new(0, 1.5, 0))
	character.PrimaryPart = root
	local h = Instance.new("Humanoid")
	h.RequiresNeck, h.Parent = false, character
	event = Instance.new("BindableEvent")
	local attrs = {}
	actor = {
		Name = "ReturnInterruptionFixture",
		UserId = -709016,
		Parent = game.Players,
		CameraMaxZoomDistance = 128,
		Character = character,
		CharacterRemoving = event.Event,
	}
	function actor:SetAttribute(k, v)
		attrs[k] = v
	end
	function actor:GetAttribute(k)
		return attrs[k]
	end
	I.Start({
		World = W,
		CreateItemVisual = function(id)
			return cargo:CreateItemVisual(id)
		end,
		IsDriving = function()
			return false
		end,
	})
	local picked, reason = I.TryPickupWorld(actor, model, record.ItemId)
	assert(picked, reason)
	local carried = I.GetCarriedRecord(actor)
	evidence.sameCarriedId = carried.ItemId == record.ItemId and carried.BrainrotId == "BRT_016"
	evidence.returnSourceCleared = carried.World.ReturnRegionId == nil
		and carried.World.TerritoryRegionId == nil
	evidence.afterPickup = R.GetDiagnostics()
	evidence.populationAfterPickup = W.GetPopulationSnapshot()
	assert(
		evidence.sameCarriedId
			and evidence.returnSourceCleared
			and evidence.afterPickup.Registered == 0
	)
	repeat
		task.wait(0.1)
	until workspace:GetServerTimeNow() >= pickupDeadline + 1
	evidence.staleWakeCount = W.ProcessSleepExpirations()
	evidence.noGhost = W.GetWorldModelById(record.ItemId) == nil
		and R.GetDiagnostics().Registered == 0
		and W.GetWildCount() == 0
		and I.GetCarriedRecord(actor).ItemId == record.ItemId
	assert(evidence.staleWakeCount == 0 and evidence.noGhost)
	assert(I.ConsumeCarriedBrainrot(actor, record.ItemId, "DiagnosticFixtureCleanup"))
	assert(I.Stop())
	evidence.pass = true
end, debug.traceback)
N.SelectReturnStep = original
if character then
	character:Destroy()
end
if event then
	event:Destroy()
end
evidence.error = not ok and tostring(failure) or nil
script:SetAttribute("Result", game:GetService("HttpService"):JSONEncode(evidence))
script:SetAttribute("Done", true)
print("[BRT016_RETURN_INTERRUPTION] " .. game:GetService("HttpService"):JSONEncode(evidence))
