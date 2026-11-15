--!strict
-- TerrainRedesign (V5) Storm: the see-through violet curtain around regions this player has not
-- unlocked, approach feedback, the push response and the unlock celebration. Presentation only:
-- the server guard decides access and owns the fallback move; this controller never grants entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TextChatService = game:GetService("TextChatService")

local Progression = require(ReplicatedStorage.Shared.Config.WorldProgression)
local Boundaries = require(ReplicatedStorage.Shared.Config.StormBoundaries)
local Atmosphere = require(ReplicatedStorage.Shared.Config.RegionAtmosphere)
local FirstSession = require(ReplicatedStorage.Shared.Config.FirstSessionVisuals)
local Names = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local Geometry = require(ReplicatedStorage.Shared.Utility.StormGeometry)
local Rules = require(ReplicatedStorage.Shared.Utility.WorldPresentationRules)
local IslandEdge = require(ReplicatedStorage.Shared.Config.IslandEdge)
local EdgeMath = require(ReplicatedStorage.Shared.Utility.IslandEdgeMath)

local Storm = Atmosphere.Storm
local player = Players.LocalPlayer
local Controller = {}

local started = false
local root: Folder? = nil
local curtains: { [string]: { segments: { any }, accent: Color3 } } = {}
-- Out-of-bounds sea mist around the island coast (CP-D); shares the Beam budget with the Storm.
local mistSegments: { any } = {}
local Mist = IslandEdge.Mist
local locked: { [string]: boolean } = {}
local banner: TextLabel? = nil
local tint: ColorCorrectionEffect? = nil
local rumble: Sound? = nil
local rumbleHost: Attachment? = nil
local guideBeam: Beam? = nil
local guideTarget: Attachment? = nil
local sparkHost: Attachment? = nil
local sparks: ParticleEmitter? = nil
local lastNoticeAt = -math.huge
local approachKey: string? = nil
-- Client prediction runs only once the server's summary has replaced the all-locked default, so a
-- player standing in a region they own is never pushed out of it while the snapshot is loading.
local summaryKnown = false

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function reducedMotion(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function sound(id: string, parent: Instance, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = parent
	return s
end

local function playOnce(id: string, volume: number)
	local s = sound(id, workspace.CurrentCamera or workspace, volume)
	s.PlayOnRemove = false
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function anchorPart(name: string, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	return part
end

-- One curtain segment: a tall violet swirl Beam plus a thin accent rim Beam at its base.
local function buildSegment(
	parent: Instance,
	a: Vector2,
	b: Vector2,
	normal: Vector2,
	accent: Color3,
	look: any?
): any
	local mid = (a + b) / 2
	local edge = Vector3.new(b.X - a.X, 0, b.Y - a.Y)
	local length = edge.Magnitude
	local axis = Vector3.new(normal.X, 0, normal.Y)
	local part = anchorPart(
		if look then "MistSegment" else "StormSegment",
		Vector3.new(mid.X, if look then look.BaseY else -1, mid.Y)
	)
	local function attach(y: number): Attachment
		local attachment = Instance.new("Attachment")
		-- Beam width follows the attachment SecondaryAxis: lay it along the edge, facing outward.
		attachment.CFrame = CFrame.fromMatrix(Vector3.new(0, y, 0), axis, edge.Unit)
		attachment.Parent = part
		return attachment
	end
	local bottom, top, rimTop =
		attach(0), attach(if look then look.Height else Storm.Height), attach(Storm.RimHeight)
	local body = Instance.new("Beam")
	body.Name = "Body"
	body.Attachment0, body.Attachment1 = bottom, top
	body.FaceCamera = false
	body.Segments = 1
	body.Width0, body.Width1 = length + 0.5, length + 0.5
	body.Texture = Storm.Texture
	body.TextureMode = Enum.TextureMode.Wrap
	body.TextureLength = Storm.TextureLength
	body.TextureSpeed = Storm.TextureSpeed
	body.LightEmission = if look then look.LightEmission else Storm.LightEmission
	body.LightInfluence = 0
	body.Color = ColorSequence.new(hex(if look then look.Body else Storm.Body))
	body.Transparency = if look
		then NumberSequence.new(look.TransparencyBase, look.TransparencyTop)
		else NumberSequence.new(Storm.TransparencyBase, Storm.TransparencyTop)
	body.Parent = part
	local rim = Instance.new("Beam")
	rim.Name = "Rim"
	rim.Attachment0, rim.Attachment1 = bottom, rimTop
	rim.FaceCamera = false
	rim.Segments = 1
	rim.Width0, rim.Width1 = length + 0.5, length + 0.5
	rim.LightEmission = 1
	rim.LightInfluence = 0
	rim.Color = ColorSequence.new(accent)
	rim.Transparency = NumberSequence.new(0.05, 0.9)
	rim.Parent = part
	part.Parent = parent
	return {
		part = part,
		body = body,
		rim = rim,
		top = top,
		mid = Vector3.new(mid.X, 0, mid.Y),
		enabled = true,
	}
end

-- Shared edges with another region this player also may not enter are interior; skip them.
local function edgeFacesAccessibleGround(key: string, mid: Vector2, normal: Vector2): boolean
	local probe = mid + normal * 6
	for otherKey in locked do
		if otherKey ~= key then
			local other = Boundaries[otherKey]
			if other and Geometry.Contains(other.points, probe.X, probe.Y) then
				return false
			end
		end
	end
	return true
end

local function buildCurtain(key: string)
	local boundary = Boundaries[key]
	if not boundary or not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = key
	local accent = hex(Storm.Accents[key] or "#FFFFFF")
	local segments = {}
	for _, segment in Geometry.Segments(boundary.points, Storm.SegmentLength) do
		local mid = (segment.a + segment.b) / 2
		if edgeFacesAccessibleGround(key, mid, segment.normal) then
			table.insert(
				segments,
				buildSegment(folder, segment.a, segment.b, segment.normal, accent)
			)
		end
	end
	folder.Parent = root
	curtains[key] = { segments = segments, accent = accent, folder = folder } :: any
end

local function rebuildCurtains()
	for key, curtain in curtains do
		(curtain :: any).folder:Destroy()
		curtains[key] = nil
	end
	for key in locked do
		buildCurtain(key)
	end
end

-- The sea mist stands just off the coast on every side; it never depends on unlocks.
local function buildMist()
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SeaMist"
	local outline = EdgeMath.Outline(IslandEdge.Coast, Mist.Offset)
	for _, segment in Geometry.Segments(outline, Mist.SegmentLength) do
		table.insert(
			mistSegments,
			buildSegment(folder, segment.a, segment.b, segment.normal, hex(Mist.Rim), Mist)
		)
	end
	folder.Parent = root
end

-- Enable only the nearest segments (two Beams each; MaxVisibleSegments keeps Beams <= 40).
local function cullSegments()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local focus = camera.Focus.Position
	local candidates = {}
	for _, curtain in curtains do
		for _, segment in curtain.segments do
			local d = (Vector3.new(segment.mid.X, focus.Y, segment.mid.Z) - focus).Magnitude
			table.insert(candidates, { segment = segment, d = d })
		end
	end
	for _, segment in mistSegments do
		local d = (Vector3.new(segment.mid.X, focus.Y, segment.mid.Z) - focus).Magnitude
		table.insert(candidates, { segment = segment, d = d })
	end
	table.sort(candidates, function(l, r)
		return l.d < r.d
	end)
	for index, entry in candidates do
		local on = index <= Storm.MaxVisibleSegments and entry.d <= Storm.VisibleRadius
		if entry.segment.enabled ~= on and not entry.segment.collapsing then
			entry.segment.enabled = on
			entry.segment.body.Enabled = on
			entry.segment.rim.Enabled = on
		end
	end
end

local function ensureHud(): TextLabel
	if banner and banner.Parent then
		return banner
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "StormHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	local label = Instance.new("TextLabel")
	label.Name = "Banner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.16)
	label.Size = UDim2.fromScale(0.62, 0.09)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 16
	limit.MaxTextSize = 44
	limit.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	banner = label
	return label
end

local bannerToken = 0
local function showBanner(text: string, colour: Color3, seconds: number)
	local label = ensureHud()
	bannerToken += 1
	local token = bannerToken
	label.Text = text
	label.TextColor3 = colour
	label.Visible = true
	if not reducedMotion() then
		label.Size = UDim2.fromScale(0.5, 0.07)
		TweenService:Create(
			label,
			TweenInfo.new(0.25, Enum.EasingStyle.Back),
			{ Size = UDim2.fromScale(0.62, 0.09) }
		):Play()
	end
	task.delay(seconds, function()
		if bannerToken == token then
			label.Visible = false
		end
	end)
end
Controller.ShowBanner = showBanner

local function ensureTint(): ColorCorrectionEffect
	if tint and tint.Parent then
		return tint
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "StormApproachTint"
	effect.Parent = Lighting
	tint = effect
	return effect
end

local function setApproach(active: boolean, vignette: any?)
	local effect = ensureTint()
	local look = vignette or Storm.Vignette
	local goal = if active
		then { TintColor = hex(look.TintColor), Saturation = look.Saturation }
		else { TintColor = Color3.new(1, 1, 1), Saturation = 0 }
	TweenService:Create(effect, TweenInfo.new(0.4), goal):Play()
	if rumble then
		if active and not rumble.IsPlaying then
			rumble:Play()
		elseif not active then
			rumble:Stop()
		end
	end
	if guideBeam then
		guideBeam.Enabled = active and vignette == nil -- the mist has no gate to point at
	end
end

local function gateAnchor(key: string): BasePart?
	local map = workspace:FindFirstChild("MapBlockout")
	local gates = map and map:FindFirstChild("ProgressionGates")
	local gate = gates and gates:FindFirstChild(key)
	local anchor = gate and gate:FindFirstChild("InteractionAnchor", true)
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

local function characterRoot(): BasePart?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

local function ensureFeedbackRig()
	if rumbleHost and rumbleHost.Parent then
		return
	end
	local host = anchorPart("StormFeedback", Vector3.zero)
	host.Parent = root
	rumbleHost = Instance.new("Attachment")
	rumbleHost.Parent = host
	local r = sound(Storm.Sounds.Rumble, rumbleHost :: Attachment, 0.5)
	r.Looped = true
	r.PlaybackSpeed = 0.45
	r.RollOffMaxDistance = 80
	rumble = r
	sparkHost = Instance.new("Attachment")
	sparkHost.Parent = host
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(hex("#8A4DFF"), hex(Storm.Body))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.9, 0)
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(12, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = sparkHost
	sparks = emitter
	guideTarget = Instance.new("Attachment")
	guideTarget.Parent = host
	local beam = Instance.new("Beam")
	beam.Name = "GateGuide"
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 1.2, 0.4
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Texture = Storm.Texture
	beam.TextureSpeed = 1.5
	beam.TextureLength = 6
	beam.Transparency = NumberSequence.new(0.1, 0.5)
	beam.Enabled = false
	beam.Parent = host
	guideBeam = beam
end

-- 4 Hz: nearest locked edge distance -> approach feedback.
local function approachStep()
	local rootPart = characterRoot()
	if not rootPart or not rumbleHost then
		return
	end
	local p = rootPart.Position
	local nearestKey, nearestDistance, nearestPoint = nil, math.huge, nil
	for key in locked do
		local boundary = Boundaries[key]
		if boundary and not Geometry.Contains(boundary.points, p.X, p.Z) then
			local hit = Geometry.NearestEdge(boundary.points, p.X, p.Z)
			if hit.distance < nearestDistance then
				nearestKey, nearestDistance, nearestPoint = key, hit.distance, hit.point
			end
		end
	end
	local near = nearestKey ~= nil and nearestDistance <= Storm.ApproachDistance
	if not near and p.Y > Mist.WarnAboveY then
		local inside = EdgeMath.Nearest(IslandEdge.Playable, p.X, p.Z)
		if inside <= Mist.WarnDistance then
			if approachKey ~= "OutOfBounds" then
				approachKey = "OutOfBounds"
				setApproach(true, Mist.Vignette)
				showBanner(Mist.Banner, hex(Mist.Rim), 3)
			end
			return
		end
	end
	if approachKey == "OutOfBounds" then
		approachKey = nil
		setApproach(false)
	end
	if near and nearestPoint then
		(rumbleHost.Parent :: BasePart).CFrame = CFrame.new(nearestPoint.X, p.Y, nearestPoint.Y)
	end
	if near ~= (approachKey ~= nil) or (near and nearestKey ~= approachKey) then
		approachKey = if near then nearestKey else nil
		setApproach(near)
		if near and nearestKey then
			local definition = Progression.ByKey[nearestKey]
			showBanner(
				"🔒 " .. string.upper(definition.displayName) .. " — unlock at the gate",
				hex(Storm.Accents[nearestKey]),
				3
			)
			local anchor = gateAnchor(nearestKey)
			local playerAttachment = rootPart:FindFirstChild("RootAttachment")
			if
				anchor
				and guideBeam
				and guideTarget
				and playerAttachment
				and playerAttachment:IsA("Attachment")
			then
				(guideTarget.Parent :: BasePart).CFrame = CFrame.new(anchor.Position)
				guideTarget.WorldPosition = anchor.Position + Vector3.new(0, 3, 0)
				guideBeam.Attachment0 = playerAttachment
				guideBeam.Attachment1 = guideTarget
				guideBeam.Color = ColorSequence.new(hex(Storm.Accents[nearestKey]))
			end
		end
	end
end

local function shakeCamera()
	if reducedMotion() then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local deadline = os.clock() + Storm.ShakeSeconds
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() >= deadline or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.6
	end)
end

local function onPush(message: any)
	if
		type(message) ~= "table"
		or (message.kind ~= "Push" and message.kind ~= "Mist")
		or typeof(message.normal) ~= "Vector3"
	then
		return
	end
	local rootPart = characterRoot()
	if not rootPart then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local velocity =
		Rules.PushVelocity(message.normal, Storm.PushSpeed, Storm.PushLift, seat ~= nil)
	-- Push whatever assembly this client simulates (the character, or the driven cart). A Humanoid
	-- cancels a one-frame impulse (Play, 8 Nov: ~2 studs), and re-applying velocity per frame fails at
	-- low frame rates (Play, 9 Nov: no movement at ~3 fps). A planar LinearVelocity is enforced every
	-- physics substep, so the outward move is frame-rate independent; gravity keeps the vertical.
	local assemblyRoot = if seat then seat.AssemblyRootPart else rootPart.AssemblyRootPart
	if
		assemblyRoot
		and assemblyRoot:IsDescendantOf(workspace)
		and not assemblyRoot:FindFirstChild("StormPushAttachment") -- predicted push already running
	then
		local ok, owner = pcall(function()
			return assemblyRoot:GetNetworkOwner()
		end)
		if not ok or owner == nil or owner == player then
			assemblyRoot.AssemblyLinearVelocity = velocity
			local attachment = Instance.new("Attachment")
			attachment.Name = "StormPushAttachment"
			local push = Instance.new("LinearVelocity")
			push.Name = "StormPush"
			push.Attachment0 = attachment
			push.RelativeTo = Enum.ActuatorRelativeTo.World
			push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
			push.PrimaryTangentAxis = Vector3.xAxis
			push.SecondaryTangentAxis = Vector3.zAxis
			push.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
			push.MaxForce = assemblyRoot.AssemblyMass * 4000
			push.Parent = attachment
			attachment.Parent = assemblyRoot
			task.delay(
				if seat
					then Storm.PushHoldSecondsSeated or Storm.PushHoldSeconds
					else Storm.PushHoldSeconds,
				function()
					attachment:Destroy()
				end
			)
		end
	end
	local now = os.clock()
	if now - lastNoticeAt < Progression.UNAUTHORIZED_NOTICE_COOLDOWN_SECONDS then
		return
	end
	lastNoticeAt = now
	shakeCamera()
	if sparkHost and sparks and typeof(message.exit) == "Vector3" then
		(sparkHost.Parent :: BasePart).CFrame = CFrame.new(message.exit + Vector3.new(0, 3, 0))
		sparks:Emit(Storm.SparkCount)
	end
	playOnce(Storm.Sounds.Whoosh, 0.7)
	if message.kind == "Mist" then
		showBanner(Mist.Banner, hex(Mist.Rim), 2.5)
		return
	end
	local definition = Progression.ByKey[message.regionKey]
	if definition then
		showBanner(
			"🔒 " .. string.upper(definition.displayName) .. " — unlock at the gate",
			hex(Storm.Accents[message.regionKey] or "#FFFFFF"),
			2.5
		)
	end
end

local function landmarkPosition(key: string): Vector3?
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild(key)
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("HeroLandmark") then
				local frame, size = model:GetBoundingBox()
				return frame.Position + Vector3.new(0, size.Y * 0.25, 0)
			end
		end
	end
	local definition = Progression.ByKey[key]
	for _, marker in FirstSession.Skyline.Markers do
		if definition and marker.Region == definition.displayName then
			return Vector3.new(marker.X, marker.BaseY + 40, marker.Z)
		end
	end
	return nil
end

local function nudgeCamera(key: string)
	local target = landmarkPosition(key)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not target
		or not camera
		or not humanoid
		or humanoid.SeatPart
		or reducedMotion()
		or humanoid.MoveDirection.Magnitude > 0.1
	then
		return
	end
	local previousType = camera.CameraType
	local start = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local goal = CFrame.lookAt(start.Position, start.Position:Lerp(target, 0.35))
	TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = goal })
		:Play()
	task.delay(1, function()
		camera.CameraType = previousType
	end)
end

local function celebrate(key: string)
	local curtain = curtains[key]
	local definition = Progression.ByKey[key]
	if curtain then
		curtains[key] = nil
		local info =
			TweenInfo.new(Storm.CollapseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, segment in curtain.segments do
			segment.collapsing = true
			segment.body.Enabled, segment.rim.Enabled = true, true
			-- Top-down collapse: the top attachment drops to the ground while the curtain thins out.
			TweenService:Create(segment.top, info, { Position = Vector3.new(0, 0.5, 0) }):Play()
			local fade = Instance.new("NumberValue")
			fade.Value = Storm.TransparencyBase
			fade.Changed:Connect(function(value)
				segment.body.Transparency =
					NumberSequence.new(value, math.max(value, Storm.TransparencyTop))
				segment.rim.Transparency = NumberSequence.new(value, 1)
			end)
			TweenService:Create(fade, info, { Value = 1 }):Play()
			if not reducedMotion() then
				local burst = Instance.new("ParticleEmitter")
				burst.Color = ColorSequence.new(curtain.accent)
				burst.LightEmission = 1
				burst.Size = NumberSequence.new(1.6, 0)
				burst.Lifetime = NumberRange.new(0.6, 1.1)
				burst.Speed = NumberRange.new(18, 34)
				burst.SpreadAngle = Vector2.new(60, 60)
				burst.EmissionDirection = Enum.NormalId.Top
				burst.Enabled = false
				burst.Parent = segment.part
				burst:Emit(14)
			end
		end
		task.delay(Storm.CollapseSeconds + 1.2, function()
			(curtain :: any).folder:Destroy()
		end)
	end
	if definition then
		showBanner(
			string.upper(definition.displayName) .. " UNLOCKED!",
			hex(Storm.Accents[key] or "#FFD447"),
			3.5
		)
	end
	playOnce(Storm.Sounds.Fanfare, 0.8)
	nudgeCamera(key)
end

local function onSummary(summary: any)
	local nextLocked = Rules.LockedKeys(summary, Progression.Ordered)
	if type(summary) == "table" and type(summary.personalUnlocks) == "table" then
		summaryKnown = true
	end
	local changed = false
	for key in nextLocked do
		if not locked[key] then
			changed = true
		end
	end
	for key in locked do
		if not nextLocked[key] then
			changed = true
		end
	end
	if not changed then
		return
	end
	locked = nextLocked
	-- Rebuild (a celebrating curtain was already detached) so shared edges that now face open
	-- ground appear and unlocked regions lose their curtain.
	rebuildCurtains()
	cullSegments()
end

local function onAnnouncement(message: any)
	if type(message) ~= "table" or (message.kind ~= "RegionUnlocked" and message.kind ~= "MutationStorm") then
		return
	end
	local text = if message.kind == "MutationStorm"
		then string.format(
			"%s started a MUTATION STORM! %d× mutations for everyone for %d min.",
			tostring(message.playerName),
			tonumber(message.multiplier) or 3,
			math.floor((tonumber(message.addedSeconds) or 0) / 60 + 0.5)
		)
		else string.format("%s unlocked the %s!", tostring(message.playerName), tostring(message.displayName))
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(text)
		end
	end)
end

-- Every frame: if this client is already inside a region it has not unlocked, push now instead of
-- waiting for the server guard's tick (Play, 9 Nov: ~0.4 s detection made the exit 0.73 s against a
-- 0.6 s target). Presentation only: the guard still decides access, sends its own push (deduplicated
-- above) and owns the authoritative fallback move.
local function predictStep()
	if not summaryKnown then
		return
	end
	local rootPart = characterRoot()
	if not rootPart then
		return
	end
	local position = rootPart.Position
	local message = Rules.PredictPush(locked, Boundaries, Geometry, position)
	if
		not message
		and EdgeMath.IsOutside(
			IslandEdge.Playable,
			IslandEdge.OutsideMargin,
			position.X,
			position.Z
		)
	then
		local _, point, normal = EdgeMath.Nearest(IslandEdge.Playable, position.X, position.Z)
		message = {
			kind = "Mist",
			normal = Vector3.new(normal.X, 0, normal.Y),
			exit = Vector3.new(point.X, position.Y, point.Y),
			predicted = true,
		}
	end
	if message then
		onPush(message)
	end
end

function Controller.Start()
	if started then
		return
	end
	started = true
	local deadline = os.clock() + 15
	while workspace:GetAttribute("TerrainRedesignActive") ~= true and os.clock() < deadline do
		task.wait(0.25)
	end
	if workspace:GetAttribute("TerrainRedesignActive") ~= true then
		return -- V5 world failed to load on this server (the server warned).
	end
	local folder = Instance.new("Folder")
	folder.Name = "StormClient"
	folder:SetAttribute("GlobalNavigationFacade", true) -- never culled by RegionVisibilityController
	folder.Parent = workspace
	root = folder
	ensureFeedbackRig()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local update = remotes:WaitForChild(Names.WorldProgressionUpdate) :: RemoteEvent
	update.OnClientEvent:Connect(function(message)
		if type(message) ~= "table" then
			return
		end
		local result = message.result
		if
			message.kind == "Result"
			and type(result) == "table"
			and result.code == "Success"
			and type(result.key) == "string"
			and curtains[result.key]
		then
			celebrate(result.key) -- the green panel logic in WorldProgressionController still runs
		end
		if message.summary then
			onSummary(message.summary)
		end
	end)
	task.spawn(function()
		local push = remotes:WaitForChild(Names.StormPush, 30)
		if push and push:IsA("RemoteEvent") then
			push.OnClientEvent:Connect(onPush)
		end
	end)
	task.spawn(function()
		local announce = remotes:WaitForChild(Names.WorldAnnouncement, 60)
		if announce and announce:IsA("RemoteEvent") then
			announce.OnClientEvent:Connect(onAnnouncement)
		end
	end)
	-- Before the first summary arrives every gated region is treated as locked (the safe default).
	locked = Rules.LockedKeys(nil, Progression.Ordered)
	rebuildCurtains()
	buildMist()
	task.delay(2, function()
		update:FireServer() -- snapshot (server rate-limits; WorldProgressionController shares the reply)
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		predictStep()
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		cullSegments()
		approachStep()
	end)
end

-- Test seam.
Controller._celebrate = celebrate
Controller._onSummary = onSummary

return Controller
