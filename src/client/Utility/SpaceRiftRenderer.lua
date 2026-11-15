--!nocheck
local RS = game:GetService("ReplicatedStorage")
local C = require(RS.Shared.Config.PlaytestExact).Rift
local Anchors = require(RS.Shared.Config.WorldRiftAnchors)
local Legacy = require(script.Parent.LegacyRebirthRiftRenderer)
local Renderer = { SampleTimeline = Legacy.SampleTimeline, PendingAsset = Legacy.PendingAsset }
function Renderer.Create(parent, asset, attachmentParent)
	local transient = Legacy.Create(parent, asset, attachmentParent)
	local api = {}
	local active
	local parts = {}
	local generation = 0
	local folder = Instance.new("Folder")
	folder.Name = "FixedWorldRifts"
	folder.Parent = workspace
	local function release()
		if active and active.rebirth then
			transient.Stop(active.handle)
		end
		for _, r in parts do
			r.part:Destroy()
		end
		table.clear(parts)
		active = nil
	end
	function api.Start(spec, now, tier, reduced)
		if active and active.id == spec.eventId then
			return active.handle
		end
		release()
		generation += 1
		if string.sub(spec.eventId or "", 1, 8) == "rebirth:" then
			local handle, reason = transient.Start(spec, now, tier, reduced)
			if handle then
				active = { id = spec.eventId, handle = handle, rebirth = true }
			end
			return handle, reason
		end
		if type(spec.deadline) ~= "number" or spec.deadline <= now then
			return nil, "RIFT_EVENT_EXPIRED"
		end
		local handle = { id = spec.eventId, generation = generation }
		active = {
			id = spec.eventId,
			handle = handle,
			deadline = spec.deadline,
			startTime = spec.startTime,
			rebirth = false,
		}
		local source = require(RS.Shared.Config.PlaytestPresentationMetadata).RiftSource
		local rng = Random.new(spec.seed or 1)
		local offsets = {
			Vector3.zero,
			Vector3.new(
				source.LeftX,
				rng:NextNumber(source.Ymin, source.Ymax),
				rng:NextNumber(source.Zmin, source.Zmax)
			),
			Vector3.new(
				source.RightX,
				rng:NextNumber(source.Ymin, source.Ymax),
				rng:NextNumber(source.Zmin, source.Zmax)
			),
		}
		local baseHeight = spec.height or C.DefaultHeight
		local height = baseHeight
		local width = if spec.height then height * asset.Width / asset.Height else C.DefaultWidth
		for i = 1, math.min(C.AnchorCount, spec.requestedRifts or 1) do
			height = baseHeight * (if i == 1 then 1 else source.SecondaryScale)
			width = (if spec.height then baseHeight * asset.Width / asset.Height else C.DefaultWidth)
				* (if i == 1 then 1 else source.SecondaryScale)

			local angle = math.rad(asset.AngleDegrees)
			local canvasWidth = width * math.abs(math.cos(angle)) + height * math.abs(math.sin(angle))
			local canvasHeight = height * math.abs(math.cos(angle)) + width * math.abs(math.sin(angle))
			local p = Instance.new("Part")
			p.Name = "WorldTear_" .. i
			p.Size = Vector3.new(canvasWidth, canvasHeight, C.Thickness)
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			local anchor = if typeof(spec.sourceAnchor) == "CFrame" then spec.sourceAnchor + offsets[i] else Anchors[i]
			p.CFrame = anchor
			p:SetAttribute("SourceAnchor", anchor)
			p:SetAttribute(
				"AnchorProvenance",
				if typeof(spec.sourceAnchor) == "CFrame"
					then "A: authoritative natural-spawn CFrame"
					else "C: source-owned Camp decorative placement"
			)
			p.Parent = folder
			local row = { part = p, images = {} }
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local surface = Instance.new("SurfaceGui")
				surface.Name = face.Name
				surface.Adornee = p
				surface.Face = face
				surface.AlwaysOnTop = false
				surface.LightInfluence = 0
				surface.CanvasSize = Vector2.new(canvasWidth, canvasHeight) * (asset.Height / height)
				surface.Parent = p
				local image = Instance.new("ImageLabel")
				image.Name = "ApprovedTear"
				image.BackgroundTransparency = 1
				image.AnchorPoint = Vector2.new(0.5, 0.5)
				image.Position = UDim2.fromScale(0.5, 0.5)
				image.Size = UDim2.fromScale(width / canvasWidth, height / canvasHeight)
				image.Image = asset.PrimaryImage
				image.Rotation = asset.AngleDegrees
				image.Parent = surface
				table.insert(row.images, image)
			end
			table.insert(parts, row)
		end
		return handle
	end
	function api.Step(now, offset, tier, reduced)
		if not active then
			return nil
		end
		if active.rebirth then
			return transient.Step(now, offset, tier, reduced)
		end
		if now >= active.deadline then
			release()
			return nil
		end
		local camera = workspace.CurrentCamera
		local ordered = {}
		for i, r in parts do
			table.insert(ordered, {
				row = r,
				distance = camera and (r.part.Position - camera.CFrame.Position).Magnitude or math.huge,
				index = i,
			})
		end
		table.sort(ordered, function(a, b)
			return if a.distance ~= b.distance then a.distance < b.distance else a.index < b.index
		end)
		for i, v in ordered do
			local pulse = not reduced and i <= C.AnimatedCap and v.distance <= C.Range
			local alpha = if pulse
				then C.PulseBase + C.PulseAmplitude * math.sin(2 * math.pi * now / C.PulsePeriod)
				else 1
			for _, image in v.row.images do
				image.ImageTransparency = 1 - alpha
			end
		end
		return { phase = "Holding", visible = true }
	end
	function api.Collapse(handle, now, duration)
		if not active or active.handle ~= handle then
			return false, "RIFT_STALE_EVENT_OWNER"
		end
		if active.rebirth then
			return transient.Collapse(handle, now, duration)
		end
		active.deadline = now + duration
		return true
	end
	function api.Stop(handle)
		if active and active.handle == handle then
			release()
			return true
		end
		return false
	end
	function api.Destroy()
		release()
		transient.Destroy()
		folder:Destroy()
	end
	function api.GetDiagnostics()
		local out = transient.GetDiagnostics()
		out.worldRifts = #parts
		out.activeRifts = #parts
		out.visibleRifts = 0
		out.pendingImages = 0
		out.fixedAnchors = true
		for _, r in parts do
			for _, image in r.images do
				if image.IsLoaded then
					out.visibleRifts += 1
				else
					out.pendingImages += 1
				end
			end
		end
		return out
	end
	return api
end
return Renderer
