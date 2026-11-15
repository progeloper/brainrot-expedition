--!strict
-- One primary RGBA quad per rift, driven only by the existing coordinator tick.
-- No Parts, lighting changes, particles, connections, waits, jobs or asset preloads.
local Workspace = game:GetService("Workspace")
local Renderer = {}
local CAPS = table.freeze({ Low = 1, Medium = 2, High = 3 })
local MAX_POOL = 3
local WHITE = Color3.new(1, 1, 1)
Renderer.PendingAsset = table.freeze({
	Installed = false,
	PrimaryImage = "",
	Width = 0,
	Height = 0,
	VerticalLongAxis = false,
	AngleDegrees = 0,
	NormalClientVerified = false,
})
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value: any): boolean
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function smooth(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end
local function quality(value: any): string
	return if CAPS[value] then value else "Low"
end
local function assetReady(asset: any): (boolean, string?)
	if type(asset) ~= "table" or asset.Installed ~= true then
		return false, "RIFT_PRIMARY_UNINSTALLED"
	end
	local id = if type(asset.PrimaryImage) == "string" then asset.PrimaryImage:match("^rbxassetid://(%d+)$") else nil
	if not id or not tonumber(id) or tonumber(id) <= 0 then
		return false, "RIFT_PRIMARY_REFERENCE_INVALID"
	end
	if
		not finite(asset.Width)
		or not finite(asset.Height)
		or asset.Width < 1
		or asset.Height < 1
		or asset.Width > 2048
		or asset.Height > 2048
	then
		return false, "RIFT_PRIMARY_DIMENSIONS_REQUIRED"
	end
	if asset.VerticalLongAxis ~= true then
		return false, "RIFT_PRIMARY_REQUIRES_UPRIGHT_LONG_AXIS"
	end
	if not finite(asset.AngleDegrees) or math.abs(asset.AngleDegrees) > 180 then
		return false, "RIFT_PRIMARY_ORIENTATION_REQUIRED"
	end
	return true
end

-- Absolute-time sampling is independent of receipt/quality/camera transitions.
-- Reset opening is anchored to deadline-60, not a fresh timer at T-30/T-10.
function Renderer.SampleTimeline(event: any, serverNow: number): any
	local startTime = event.startTime
	local endTime = event.deadline
	local phase, progress, width, length, stage, convergence = "NotStarted", 0, 0, 0, 0, 0
	if event.mode == "Reset" then
		local remaining = event.resetDeadline - serverNow
		startTime = event.resetDeadline - 60
		stage = if remaining > 30 then 1 elseif remaining > 10 then 2 else 3
		local age = serverNow - startTime
		if age >= 0 then
			if age < 2 then
				phase, progress = "Opening", age / 2
				width, length = 0.025 + 0.975 * smooth(progress), 0.65 + 0.35 * smooth(progress)
			else
				phase, progress, width, length = "Holding", math.clamp(age / 60, 0, 1), 1, 1
			end
			convergence = math.clamp((10 - remaining) / 10, 0, 1) * 0.65
		end
	elseif event.mode == "Collapse" then
		local duration = endTime - startTime
		progress = math.clamp((serverNow - startTime) / duration, 0, 1)
		if serverNow >= startTime then
			phase, width, length = "Sealing", 1 - smooth(progress), 1 - 0.9 * smooth(progress)
			stage, convergence = 3, 0.65
		end
	else
		local duration = endTime - startTime
		local fraction = math.clamp((serverNow - startTime) / duration, 0, 1)
		-- Epoch timestamps can round (start+1.2)-start slightly above 1.2.
		local edge = if duration <= 1.2 + 0.000001 then 0.25 else 0.20
		if serverNow >= startTime then
			if fraction < edge then
				phase, progress = "Opening", fraction / edge
				width, length = 0.025 + 0.975 * smooth(progress), 0.65 + 0.35 * smooth(progress)
			elseif fraction <= 1 - edge then
				phase, progress, width, length = "Holding", (fraction - edge) / (1 - 2 * edge), 1, 1
			else
				phase, progress = "Sealing", (fraction - (1 - edge)) / edge
				width, length = 1 - smooth(progress), 1 - 0.9 * smooth(progress)
			end
		end
	end
	if serverNow >= endTime then
		phase, progress, width, length = "Ended", 1, 0, 0
	end
	return {
		phase = phase,
		phaseProgress = progress,
		age = math.max(0, serverNow - startTime),
		startTime = startTime,
		deadline = endTime,
		widthScale = width,
		lengthScale = length,
		resetStage = stage,
		convergence = convergence,
		visible = phase ~= "NotStarted" and phase ~= "Ended",
	}
end

function Renderer.Create(guiParent: Instance, descriptor: any?, attachmentParent: Instance?): any
	assert(typeof(guiParent) == "Instance", "Rift GUI owner required")
	local anchorOwner = attachmentParent or Workspace.Terrain
	assert(
		typeof(anchorOwner) == "Instance" and anchorOwner:IsA("BasePart"),
		"Existing Terrain/BasePart attachment owner required"
	)
	local asset = if type(descriptor) == "table" then table.freeze(table.clone(descriptor)) else Renderer.PendingAsset
	local pool, active = {}, nil
	local generation, destroyed, lastNow, lastOffset, lastTier, lastReduced = 0, false, 0, Vector3.zero, "Low", false
	local diagnostics = {
		eventStarts = 0,
		eventReleases = 0,
		staleReleases = 0,
		createdSlots = 0,
		textureAssignments = 0,
		qualityChanges = 0,
		peakActiveRifts = 0,
	}
	local api = {}
	local function set(instance: Instance, property: string, value: any)
		if instance[property] ~= value then
			instance[property] = value
		end
	end
	local function resetSlot(slot: any)
		if slot.gui.Parent then
			slot.gui.Enabled, slot.gui.Size = false, UDim2.fromScale(0, 0)
			slot.gui.AlwaysOnTop, slot.gui.LightInfluence, slot.gui.Brightness = false, 0, 1
			slot.gui.StudsOffset, slot.gui.StudsOffsetWorldSpace = Vector3.zero, Vector3.zero
			slot.image.Visible, slot.image.ImageTransparency = false, 1
			slot.image.ImageColor3, slot.image.Rotation = WHITE, 0
			slot.image.Size, slot.image.Position = UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5)
		end
		if slot.anchor.Parent then
			slot.anchor.Position = Vector3.zero
		end
		slot.active = false
	end
	local function acquire(index: number): any
		local slot = pool[index]
		if slot then
			return slot
		end
		assert(index <= MAX_POOL, "Rift pool cap")
		local anchor = Instance.new("Attachment")
		anchor.Name, anchor.Visible, anchor.Parent = "SpaceRiftAnchor_" .. index, false, anchorOwner
		local gui = Instance.new("BillboardGui")
		gui.Name, gui.Adornee, gui.AlwaysOnTop, gui.LightInfluence, gui.Brightness =
			"SpaceRift_" .. index, anchor, false, 0, 1
		gui.Enabled, gui.Active, gui.ClipsDescendants, gui.MaxDistance = false, false, false, 700
		gui.Size, gui.Parent = UDim2.fromScale(0, 0), guiParent
		local image = Instance.new("ImageLabel")
		image.Name, image.BackgroundTransparency, image.BorderSizePixel = "ApprovedTornPrimary", 1, 0
		image.AnchorPoint, image.Position, image.Size =
			Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
		image.ScaleType, image.Image, image.Visible = Enum.ScaleType.Stretch, asset.PrimaryImage, false
		image.Parent = gui
		slot = { anchor = anchor, gui = gui, image = image, active = false }
		pool[index] = slot
		diagnostics.createdSlots += 1
		diagnostics.textureAssignments += 1
		resetSlot(slot)
		return slot
	end
	local function release(): boolean
		if not active or active.released then
			return false
		end
		active.released = true
		for _, slot in pool do
			resetSlot(slot)
		end
		active = nil
		diagnostics.eventReleases += 1
		return true
	end
	function api.Step(serverNow: number, cameraOffset: Vector3?, tier: string?, reducedMotion: boolean?): any
		if destroyed then
			return nil
		end
		if not guiParent.Parent or not anchorOwner.Parent then
			api.Destroy()
			return nil
		end
		if not finite(serverNow) then
			return nil
		end
		local nextTier = quality(tier or lastTier)
		if active and nextTier ~= lastTier then
			diagnostics.qualityChanges += 1
		end
		lastNow, lastOffset, lastTier, lastReduced =
			serverNow, if vector(cameraOffset) then cameraOffset else lastOffset, nextTier, reducedMotion == true
		if not active then
			return nil
		end
		local state = Renderer.SampleTimeline(active.event, serverNow)
		active.sample = state
		if state.phase == "Ended" then
			release()
			return state
		end
		local selectedAsset = active.asset or asset
		if selectedAsset ~= asset and serverNow - active.firstObservedAt >= 2 then
			local resident = false
			for _, slot in pool do
				if slot.active and slot.image.IsLoaded then
					resident = true
					break
				end
			end
			if not resident then
				active.asset, selectedAsset = asset, asset
				diagnostics.optionalFallbacks = (diagnostics.optionalFallbacks or 0) + 1
			end
		end
		local desired = math.min(active.event.requestedRifts, CAPS[nextTier])
		if active.event.mode == "Reset" and state.resetStage == 1 then
			desired = 1
		end
		local stageScale = if active.event.mode == "Reset"
			then (if state.resetStage == 1 then 0.86 elseif state.resetStage == 2 then 0.94 else 1)
			else 1
		local pulse = if state.phase == "Holding"
				and nextTier ~= "Low"
				and not lastReduced
			then 1 + 0.012 * math.sin(state.age * 4 + active.event.seed)
			else 1
		for index = 1, MAX_POOL do
			if index <= desired then
				local slot = acquire(index)
				if not slot.gui.Parent or not slot.anchor.Parent or not slot.image.Parent then
					api.Destroy()
					return nil
				end
				if slot.image.Image ~= selectedAsset.PrimaryImage then
					slot.image.Image = selectedAsset.PrimaryImage
					diagnostics.textureAssignments += 1
				end
				local secondary = index > 1
				local scale = if secondary then 0.36 else 1
				local height = active.event.height * scale * stageScale * state.lengthScale
				local width = active.event.height
					* (selectedAsset.Width / selectedAsset.Height)
					* scale
					* stageScale
					* state.widthScale
					* pulse
				local position = active.event.position + lastOffset + active.offsets[index] * (1 - state.convergence)
				set(slot.anchor, "WorldPosition", position)
				local angle = selectedAsset.AngleDegrees + active.angles[index]
				local sine, cosine = math.abs(math.sin(math.rad(angle))), math.abs(math.cos(math.rad(angle)))
				-- Include the rotated transparent tile in the billboard cache bounds so
				-- needle tips/branches are not clipped by its original rectangle.
				local canvasWidth = width * cosine + height * sine
				local canvasHeight = height * cosine + width * sine
				set(slot.gui, "Size", UDim2.fromScale(canvasWidth, canvasHeight))
				set(slot.gui, "Enabled", state.visible)
				set(
					slot.image,
					"Size",
					UDim2.fromScale(width / math.max(0.001, canvasWidth), height / math.max(0.001, canvasHeight))
				)
				set(slot.image, "Rotation", angle)
				set(slot.image, "ImageTransparency", 0)
				set(slot.image, "ImageColor3", active.event.tint)
				-- Native image residency is visibility-dependent. Hiding until IsLoaded
				-- latches a valid fetched image forever; its transparent quad must be
				-- enabled to become resident. Pending residency stays explicit below.
				set(slot.image, "Visible", state.visible)
				slot.active = state.visible
			elseif pool[index] and pool[index].active then
				resetSlot(pool[index])
			end
		end
		active.count = if state.visible then desired else 0
		diagnostics.peakActiveRifts = math.max(diagnostics.peakActiveRifts, active.count)
		return state
	end
	function api.Start(spec: any, serverNow: number, tier: string?, reducedMotion: boolean?): (any?, string?)
		if destroyed then
			return nil, "RIFT_RENDERER_DESTROYED"
		end
		local ready, reason = assetReady(asset)
		if not ready then
			return nil, reason
		end
		if
			type(spec) ~= "table"
			or type(spec.eventId) ~= "string"
			or spec.eventId == ""
			or #spec.eventId > 256
			or not finite(serverNow)
			or not vector(spec.position)
		then
			return nil, "RIFT_EVENT_INVALID"
		end
		local mode = if spec.mode == "Reset" then "Reset" elseif spec.mode == "Collapse" then "Collapse" else "Spawn"
		local startTime = if mode == "Reset" and finite(spec.resetDeadline)
			then spec.resetDeadline - 60
			else spec.startTime
		local deadline = spec.deadline
		if
			not finite(startTime)
			or not finite(deadline)
			or deadline <= startTime
			or (mode == "Reset" and not finite(spec.resetDeadline))
		then
			return nil, "RIFT_AUTHORITATIVE_TIMELINE_REQUIRED"
		end
		if serverNow >= deadline then
			return nil, "RIFT_EVENT_EXPIRED"
		end
		-- A remote can arrive between frame samples. An ended reset must not
		-- retain priority over a valid new event until the next coordinator tick.
		if active and serverNow >= active.event.deadline then
			release()
		end
		if active and active.resetPriority and mode == "Spawn" then
			return nil, "RIFT_RESET_HAS_PRIORITY"
		end
		if active and active.event.eventId == spec.eventId then
			if active.event.startTime ~= startTime or active.event.deadline ~= deadline then
				return nil, "RIFT_EVENT_ID_TIMELINE_CHANGED"
			end
			api.Step(serverNow, lastOffset, tier, reducedMotion)
			if destroyed or not active then
				return nil, "RIFT_OWNER_REMOVED"
			end
			return active.handle
		end
		release()
		generation += 1
		local handle = table.freeze({ eventId = spec.eventId, generation = generation })
		local rank = if finite(spec.rank) then math.clamp(spec.rank, 2, 6) else 2
		local event = {
			eventId = spec.eventId,
			tint = if typeof(spec.tint) == "Color3"
				then Color3.new(
					math.clamp(spec.tint.R, 0, 1),
					math.clamp(spec.tint.G, 0, 1),
					math.clamp(spec.tint.B, 0, 1)
				)
				else WHITE,
			mode = mode,
			startTime = startTime,
			deadline = deadline,
			resetDeadline = spec.resetDeadline,
			position = spec.position,
			seed = if finite(spec.seed) then math.floor(spec.seed) else 1,
			height = if finite(spec.height) then math.clamp(spec.height, 12, 90) else 50 * (0.82 + rank * 0.05),
			requestedRifts = if finite(spec.requestedRifts)
				then math.clamp(math.floor(spec.requestedRifts), 1, MAX_POOL)
				else math.clamp(rank - 1, 1, MAX_POOL),
		}
		local rng = Random.new(event.seed)
		local selectedAsset = if assetReady(spec.variantAsset)
				and spec.variantAsset.PrimaryImage ~= asset.PrimaryImage
			then table.freeze(table.clone(spec.variantAsset))
			else asset
		active = {
			asset = selectedAsset,
			firstObservedAt = serverNow,
			handle = handle,
			event = event,
			resetPriority = mode ~= "Spawn",
			released = false,
			count = 0,
			offsets = {
				Vector3.zero,
				Vector3.new(-34, rng:NextNumber(-3, 6), rng:NextNumber(-6, 6)),
				Vector3.new(32, rng:NextNumber(-3, 6), rng:NextNumber(-6, 6)),
			},
			angles = { 0, rng:NextNumber(-8, 8), rng:NextNumber(-8, 8) },
		}
		diagnostics.eventStarts += 1
		api.Step(serverNow, Vector3.zero, tier, reducedMotion)
		if destroyed or not active then
			return nil, "RIFT_OWNER_REMOVED"
		end
		return handle
	end
	function api.Collapse(handle: any, startTime: number, duration: number): (boolean, string?)
		if not active or active.handle ~= handle then
			return false, "RIFT_STALE_EVENT_OWNER"
		end
		if not finite(startTime) or not finite(duration) or duration <= 0 then
			return false, "RIFT_COLLAPSE_TIMELINE_INVALID"
		end
		if active.event.mode == "Collapse" then
			return false, "RIFT_ALREADY_COLLAPSING"
		end
		active.event.mode, active.event.startTime, active.event.deadline = "Collapse", startTime, startTime + duration
		return true
	end
	function api.Stop(handle: any): boolean
		if active and active.handle == handle then
			return release()
		end
		diagnostics.staleReleases += 1
		return false
	end
	function api.Destroy()
		if destroyed then
			return
		end
		release()
		destroyed = true
		for _, slot in pool do
			slot.gui:Destroy()
			slot.anchor:Destroy()
		end
		table.clear(pool)
	end
	function api.GetDiagnostics(): any
		local result = table.clone(diagnostics)
		local ready, reason = assetReady(asset)
		result.assetInstalled, result.assetReason = ready, reason
		result.normalClientAssetVerified = asset.NormalClientVerified == true
		result.destroyed, result.poolSlots, result.activeRifts = destroyed, #pool, if active then active.count else 0
		result.visibleRifts, result.pendingImages = 0, 0
		local coverage = 0
		local camera = Workspace.CurrentCamera
		for _, slot in pool do
			if slot.active then
				if slot.image.Visible and slot.image.IsLoaded then
					result.visibleRifts += 1
				else
					result.pendingImages += 1
				end
				if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
					local size = slot.gui.AbsoluteSize
					coverage += math.min(1, (size.X * size.Y) / (camera.ViewportSize.X * camera.ViewportSize.Y))
				end
			end
		end
		result.fullSizeLayersPerRift, result.guiTrianglesPerRift, result.primaryTextureReferences =
			1, 4, if ready then 1 else 0
		result.dominantRifts = if result.activeRifts > 0 then 1 else 0
		result.secondaryRifts = math.max(0, result.activeRifts - result.dominantRifts)
		result.accentParticles, result.worldBaseParts, result.dynamicLights, result.connections, result.jobs =
			0, 0, 0, 0, 0
		result.screenCoverageUpperBound = coverage
		result.screenCoverageIsAlphaAware = false
		result.current = if active
			then {
				eventId = active.event.eventId,
				generation = active.handle.generation,
				startTime = active.event.startTime,
				deadline = active.event.deadline,
				mode = active.event.mode,
				sample = active.sample,
			}
			else nil
		result.quality, result.reducedMotion, result.lastSampleTime = lastTier, lastReduced, lastNow
		return result
	end
	return api
end
return Renderer
