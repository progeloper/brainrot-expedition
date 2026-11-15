--!strict

-- An adapter for PlayerModule, NOT another camera/movement controller. The
-- default camera still computes orbit, sensitivity and obstruction pull-in.
local ThirdPersonAimController = {}
local CreaturePresentation = require(script.Parent.CreaturePresentationController)
local Visibility = require(script.Parent.RegionVisibilityController)
local DefaultNametagController = require(script.Parent.BrainrotNametagController)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeatState = require(ReplicatedStorage.Shared.Utility.HumanoidSeatState)
local InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)
local DEFAULT_WEAPON_PROFILE = WeaponStats.Resolve(Weapons.StarterWeaponId)
assert(WeaponStats.IsReady(DEFAULT_WEAPON_PROFILE), "Starter weapon profile must be valid")
local BINDING = "BrainrotOnFootHunting"
local DISTANCE = 11
local SHOULDER = Vector3.new(1.75, 0.5, 0)
local DWELL, IDLE_GRACE, TRACK_TIME = 0.12, 0.25, 0.30
local MAX_SPEED, MAX_DT, SCAN_INTERVAL = math.rad(40), 1 / 15, 0.1

-- Shared equipped predicate for facing, tracking and HUD. A seat/backpack or
-- arbitrary Tool is not a held hunting weapon. Server authorization is separate.
function ThirdPersonAimController.GetHeldLauncher(character: Model?): Tool?
	if not character then
		return nil
	end
	local held: Tool? = nil
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			if
				(child.Name ~= "SleepLauncher" and child.Name ~= "Hunting")
				or child:GetAttribute("BrainrotSleepLauncher") ~= true
				or not child.Enabled
			then
				return nil
			end
			if held then
				return nil
			end
			held = child
		end
	end
	local handle = if held then held:FindFirstChild("Handle") else nil
	local muzzle = if handle then handle:FindFirstChild("Muzzle") else nil
	if not handle or not handle:IsA("BasePart") or not muzzle or not muzzle:IsA("Attachment") then
		return nil
	end
	return held
end

function ThirdPersonAimController.new(player: any, services: any?)
	local input = if services then services.Input else game:GetService("UserInputService")
	local gui = if services then services.Gui else game:GetService("GuiService")
	local run = if services then services.Run else game:GetService("RunService")
	local world = if services then services.World else workspace
	local ownCartReader = if services and services.OwnCartReader then services.OwnCartReader else LocalCartState.GetCart
	local now = if services and services.Clock then services.Clock else os.clock
	local nametags = if services and services.Nametags then services.Nametags else DefaultNametagController
	local replicated = ReplicatedStorage
	local requestedProfile = if services then services.WeaponProfile else nil
	local weaponProfile = if WeaponStats.IsReady(requestedProfile)
		then assert(WeaponStats.CaptureShotProfile(requestedProfile, 0))
		else DEFAULT_WEAPON_PROFILE
	local cameraInput: any = nil
	local inputOriginal: any = nil
	local inputWrapper: any = nil
	local tracked: any = nil
	local focusedTrackingModel: Model? = nil
	local candidate: any = nil
	local candidateSince, lastManual = 0, now()
	local lastDeliberate = -math.huge
	local nextScan = 0
	local candidates = {}
	local traceKey = ""
	local desired: Model? = nil
	local active: any = nil
	local focused = true
	local destroyed = false
	local blocked = false
	local connections = {}
	local cameraConnection: any = nil
	local controller: any = {}
	local function excludeOwnedCart(exclusions: { Instance })
		local ownCart = ownCartReader()
		if
			ownCart
			and ownCart:IsA("Model")
			and ownCart:GetAttribute("OwnerUserId") == player.UserId
			and not table.find(exclusions, ownCart)
		then
			table.insert(exclusions, ownCart)
		end
	end
	local function notify()
		if controller.OnContextChanged then
			controller.OnContextChanged()
		end
	end
	local function setFocusedTrackingModel(modelOrNil: Model?)
		if focusedTrackingModel == modelOrNil then
			return
		end
		focusedTrackingModel = modelOrNil
		nametags.setFocusedBrainrot(modelOrNil)
	end

	function controller:IsInputSuspended(): boolean
		return destroyed
			or not focused
			or player:GetAttribute("Phase13CinematicActive") == true
			or player:GetAttribute("Phase13ConsentDialogOpen") == true
			or player:GetAttribute("Phase13CompareDialogOpen") == true
			or InputPolicy.IsBlocked(player, gui, input)
	end

	local function eligible(): (Humanoid?, BasePart?)
		local character = desired
		if not character or player.Character ~= character or not character.Parent then
			return nil, nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if
			not humanoid
			or humanoid.Health <= 0
			or SeatState.IsSeated(humanoid)
			or player:GetAttribute("CarriedItemId") ~= nil
			or ThirdPersonAimController.GetHeldLauncher(character) == nil
			or not root
			or not root:IsA("BasePart")
		then
			return nil, nil
		end
		-- Also reject a root already joined to a vehicle before seat callbacks run.
		local assembly = root.AssemblyRootPart
		if assembly and not assembly:IsDescendantOf(character) then
			return nil, nil
		end
		return humanoid, root
	end

	local function traceTracking(reason: string)
		if not game:GetService("RunService"):IsStudio() or replicated:GetAttribute("HuntingAimTrace") ~= true then
			return
		end
		local info = tracked or candidate
		local key = reason .. ":" .. tostring(info and info.Id)
		if key == traceKey then
			return
		end
		traceKey = key
		print(
			string.format(
				"[HuntingTracking] state=%s eligible=%s target=%s angle=%.2f lastManual=%.3f",
				reason,
				tostring(active ~= nil),
				tostring(info and info.Id),
				math.deg(if info then info.Angle else 0),
				lastManual
			)
		)
	end

	function controller:ReleaseTracking(reason: string, resetGrace: boolean?)
		setFocusedTrackingModel(nil)
		tracked, candidate, candidateSince = nil, nil, 0
		candidates, nextScan = {}, 0
		if resetGrace then
			lastManual = now()
		end
		traceTracking(reason)
	end

	local function muzzlePosition(): Vector3?
		local tool = ThirdPersonAimController.GetHeldLauncher(desired)
		local muzzle = if tool then tool:FindFirstChild("Muzzle", true) else nil
		if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
			return muzzle.WorldPosition
		end
		return nil
	end

	local function trackingCandidate(model: Model, cone: number, allowSleeping: boolean?): (any?, string?)
		local runtime = world:FindFirstChild("Runtime")
		local brainrots = if runtime then runtime:FindFirstChild("Brainrots") else nil
		local decoys = if runtime then runtime:FindFirstChild("Decoys") else nil
		local isBrainrot = brainrots ~= nil and model.Parent == brainrots
		local isDecoy = decoys ~= nil and model:IsDescendantOf(decoys) and model:GetAttribute("EffectKind") == "Decoy"
		local kind = if isBrainrot then "Brainrot" elseif isDecoy then "Decoy" else nil
		local id = if isBrainrot then model:GetAttribute("ItemId") else model:GetAttribute("DecoyId")
		local body = if isBrainrot then model:FindFirstChild("Body", true) else model:FindFirstChild("HitProxy", true)
		local camera = world.CurrentCamera
		local muzzle = muzzlePosition()
		local sleeping = isBrainrot
			and model:GetAttribute("Captured") == true
			and type(model:GetAttribute("BrainrotSleepUntil")) == "number"
		if
			kind == nil
			or not Visibility.IsVisible(model)
			or type(id) ~= "string"
			or (isBrainrot and model:GetAttribute("Captured") ~= false and not (allowSleeping and sleeping))
			or (isBrainrot and type(model:GetAttribute("BrainrotId")) ~= "string")
			or not body
			or not body:IsA("BasePart")
			or not body.CanQuery
			or not camera
			or not muzzle
		then
			return nil, "lifecycle_or_muzzle"
		end
		if
			isBrainrot
			and (type(nametags.isAimAssistEligible) == "function" and not nametags.isAimAssistEligible(model))
		then
			return nil, "camouflaged"
		end
		local point = body.Position
		local distance = (point - muzzle).Magnitude
		local offset = point - camera.CFrame.Position
		if distance > weaponProfile.rangeStuds or distance < 0.001 or offset.Magnitude < 0.001 then
			return nil, "range"
		end
		local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(offset.Unit), -1, 1))
		local screen, visible = camera:WorldToViewportPoint(point)
		if angle > cone or not visible or screen.Z <= 0 then
			return nil, "cone_or_screen"
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclusions: { Instance } = { desired :: Model }
		excludeOwnedCart(exclusions)
		local effects = world:FindFirstChild("SleepBoltEffects")
		if effects then
			table.insert(exclusions, effects)
		end
		params.FilterDescendantsInstances = exclusions
		params.IgnoreWater, params.RespectCanCollide = false, false
		for _, origin in { camera.CFrame.Position, muzzle } do
			local ray = point - origin
			local hit = world:Raycast(origin, ray.Unit * (ray.Magnitude + 0.01), params)
			-- A MeshPart's centre may lie in an opening. No obstruction before
			-- that stable aim point is clear LOS, not an invisible target.
			if
				hit
				and not hit.Instance:IsDescendantOf(model)
				and CreaturePresentation.ResolveAuthority(hit.Instance) ~= model
			then
				return nil,
					(if origin == camera.CFrame.Position then "camera_cover:" else "muzzle_cover:") .. (if hit
						then hit.Instance:GetFullName()
						else "no_body_hit")
			end
		end
		local resetToken = if isBrainrot and type(nametags.getAimResetToken) == "function"
			then nametags.getAimResetToken(model)
			else ""
		return {
			Model = model,
			Id = id,
			Kind = kind,
			Point = point,
			Angle = angle,
			Distance = distance,
			ResetToken = resetToken,
		},
			nil
	end

	local function collectAimCandidates(): { Model }
		local found = {}
		local runtime = world:FindFirstChild("Runtime")
		local brainrots = if runtime then runtime:FindFirstChild("Brainrots") else nil
		if brainrots then
			for _, child in brainrots:GetChildren() do
				if child:IsA("Model") then
					table.insert(found, child)
				end
			end
		end
		local decoys = if runtime then runtime:FindFirstChild("Decoys") else nil
		if decoys then
			for _, encounter in decoys:GetChildren() do
				for _, child in encounter:GetChildren() do
					if child:IsA("Model") and child:GetAttribute("EffectKind") == "Decoy" then
						table.insert(found, child)
					end
				end
			end
		end
		return found
	end

	function controller:GetTrackingId(): string?
		return if tracked then tracked.Id else nil
	end

	function controller:GetWeaponProfile(): any
		return weaponProfile
	end

	function controller:SetWeaponProfile(profile: any): boolean
		if not WeaponStats.IsReady(profile) then
			return false
		end
		local captured = WeaponStats.CaptureShotProfile(profile, 0)
		if not captured then
			return false
		end
		if
			captured.weaponId == weaponProfile.weaponId
			and captured.definitionRevision == weaponProfile.definitionRevision
			and captured.rangeStuds == weaponProfile.rangeStuds
			and captured.assistAcquireHalfAngleRadians == weaponProfile.assistAcquireHalfAngleRadians
			and captured.assistRetainHalfAngleRadians == weaponProfile.assistRetainHalfAngleRadians
		then
			return true
		end
		weaponProfile = captured
		self:ReleaseTracking("weapon_profile_changed", true)
		notify()
		return true
	end

	function controller:UpdateSoftTracking(dt: number, manual: Vector2): Vector2
		local clock = now()
		local humanoid = eligible()
		local camera = world.CurrentCamera
		if
			not active
			or humanoid ~= active.Humanoid
			or self:IsInputSuspended()
			or camera ~= active.Camera
			or camera.CameraType ~= Enum.CameraType.Custom
			or camera.CameraSubject ~= humanoid
		then
			self:ReleaseTracking("ineligible", true)
			return manual
		end
		-- This is the default CameraInput's REAL processed rotation, before our
		-- addition: it already filters stick drift and separates look-touch from
		-- the movement joystick. Held sticks are read every camera update.
		if manual.Magnitude > 1e-7 then
			lastManual = clock
			self:ReleaseTracking("manual")
			return manual -- No damping/consumption, hidden heading or residual spring.
		end
		if clock - lastDeliberate < SCAN_INTERVAL + 0.05 then
			return manual -- Current exact PvP selection suppresses wild assistance.
		end
		if tracked then
			local valid, reason = trackingCandidate(tracked.Model, weaponProfile.assistRetainHalfAngleRadians)
			if
				not valid
				or valid.Id ~= tracked.Id
				or valid.Kind ~= tracked.Kind
				or valid.ResetToken ~= tracked.ResetToken
			then
				self:ReleaseTracking("lost:" .. tostring(reason), true)
				return manual
			end
			tracked = valid
		else
			if clock >= nextScan then
				nextScan = clock + SCAN_INTERVAL
				candidates = collectAimCandidates()
				local best = nil
				for _, model in candidates do
					if not model:IsA("Model") then
						continue
					end
					local info = trackingCandidate(model, weaponProfile.assistAcquireHalfAngleRadians)
					if
						info
						and (
							not best
							or info.Angle < best.Angle
							or (
								info.Angle == best.Angle
								and (
									info.Distance < best.Distance
									or (info.Distance == best.Distance and info.Id < best.Id)
								)
							)
						)
					then
						best = info
					end
				end
				if not best or not candidate or candidate.Model ~= best.Model or candidate.Id ~= best.Id then
					candidateSince = clock
				end
				candidate = best
				traceTracking(if best then "dwell" else "searching")
			end
			if candidate then
				local valid = trackingCandidate(candidate.Model, weaponProfile.assistAcquireHalfAngleRadians)
				if
					not valid
					or valid.Id ~= candidate.Id
					or valid.Kind ~= candidate.Kind
					or valid.ResetToken ~= candidate.ResetToken
				then
					candidate, candidateSince = nil, clock
				elseif clock - candidateSince >= DWELL and clock - lastManual >= IDLE_GRACE then
					tracked, candidate = valid, nil
					setFocusedTrackingModel(if tracked.Kind == "Brainrot" then tracked.Model else nil)
					traceTracking("tracking")
				end
			end
		end
		if not tracked then
			return manual
		end
		local look = camera.CFrame.LookVector
		local target = (tracked.Point - camera.CFrame.Position).Unit
		local yaw = math.atan2(-look.X, -look.Z)
		local targetYaw = math.atan2(-target.X, -target.Z)
		local yawError = math.atan2(math.sin(targetYaw - yaw), math.cos(targetYaw - yaw))
		local pitchError = math.clamp(math.asin(target.Y), math.rad(-80), math.rad(80))
			- math.asin(math.clamp(look.Y, -1, 1))
		local step = math.clamp(dt, 0, MAX_DT)
		local correction = Vector2.new(-yawError, -pitchError) * (1 - math.exp(-step / TRACK_TIME))
		local limit = MAX_SPEED * step
		if correction.Magnitude > limit then
			correction = correction.Unit * limit
		end
		return manual + correction
	end

	local function detachCameraInput()
		if cameraInput and inputWrapper and cameraInput.getRotation == inputWrapper then
			cameraInput.getRotation = inputOriginal
		end
		inputOriginal, inputWrapper = nil, nil
	end

	local function attachCameraInput()
		if not cameraInput or inputWrapper or not active then
			return
		end
		inputOriginal = cameraInput.getRotation
		local original = inputOriginal
		inputWrapper = function(dt: number, ...: any): Vector2
			local manual = original(dt, ...)
			return controller:UpdateSoftTracking(dt, manual)
		end
		cameraInput.getRotation = inputWrapper
	end

	function controller:SetCameraInput(adapter: any): boolean
		if
			destroyed
			or type(adapter) ~= "table"
			or type(adapter.getRotation) ~= "function"
			or table.isfrozen(adapter)
		then
			return false
		end
		detachCameraInput()
		cameraInput = adapter
		attachCameraInput()
		return true
	end

	local function claim(owner: any, object: any, property: string, value: any)
		table.insert(owner.Saved, { Object = object, Property = property, Previous = object[property], Value = value })
		object[property] = value
	end

	local function release()
		controller:ReleaseTracking("released", true)
		detachCameraInput()
		if not active then
			return
		end
		local previous = active
		active = nil
		run:UnbindFromRenderStep(BINDING)
		for index = #previous.Saved, 1, -1 do
			local entry = previous.Saved[index]
			-- A later owner wins. Never restore stale state onto a different character.
			if entry.Object[entry.Property] == entry.Value then
				entry.Object[entry.Property] = entry.Previous
			end
		end
		notify()
	end

	function controller:IsActive(): boolean
		return active ~= nil
	end

	local function centreRay(camera: Camera?): Ray?
		if not camera then
			return nil
		end
		local viewport = camera.ViewportSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return nil
		end
		-- Same DeviceSafeInsets coordinates as SleepAimReticle; no pointer or
		-- CoreUI-inset subtraction and no cached direction from a previous frame.
		return camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5, 0)
	end

	function controller:Update(): Ray?
		if not active then
			return nil
		end
		local humanoid, root = eligible()
		local camera = world.CurrentCamera
		if
			self:IsInputSuspended()
			or humanoid ~= active.Humanoid
			or not root
			or camera ~= active.Camera
			or camera.CameraType ~= Enum.CameraType.Custom
			or camera.CameraSubject ~= humanoid
		then
			release()
			return nil
		end
		if
			humanoid.AutoRotate ~= false
			or humanoid.CameraOffset ~= active.Offset
			or player.CameraMinZoomDistance ~= DISTANCE
			or player.CameraMaxZoomDistance ~= DISTANCE
			or player.CameraMode ~= Enum.CameraMode.Classic
			or (cameraInput and inputWrapper and cameraInput.getRotation ~= inputWrapper)
		then
			blocked = true -- Another owner changed framing/facing; do not fight it.
			release()
			return nil
		end
		if active.Mouse then
			-- PlayerModule may set mouse mode during its camera update (e.g. RMB).
			-- Lock after that update; its ordinary mouse delta already drives orbit.
			input.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		local ray = centreRay(camera)
		if not ray then
			return nil
		end
		local look = ray.Direction
		local horizontal = Vector3.new(look.X, 0, look.Z)
		if horizontal.Magnitude > 0.001 then
			-- No yielding between the seat/assembly guard and this yaw-only write.
			root.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit)
		end
		return ray
	end

	function controller:GetAimRay(mounted: boolean?): Ray?
		if self:IsInputSuspended() then
			return nil
		end
		if mounted then
			-- The caller resolves the actual mounted role. Never turn the avatar
			-- (and its seated assembly) to follow a mounted shot.
			self:SetCharacter(nil)
			return centreRay(world.CurrentCamera)
		end
		-- Input can arrive between camera and facing callbacks. Update facing
		-- and return that SAME centre ray atomically before sending this shot.
		return self:Update()
	end

	-- One immutable fire-time view of both the visible assist lock and the
	-- unassisted crosshair. The server receives both directions so a lock that
	-- becomes stale in transit can fall back to the real crosshair without ever
	-- selecting a different nearby target.
	function controller:GetShotSnapshot(mounted: boolean?): any?
		local crosshairRay = self:GetAimRay(mounted)
		if not crosshairRay then
			return nil
		end
		if not mounted and tracked then
			local valid = trackingCandidate(tracked.Model, weaponProfile.assistRetainHalfAngleRadians, true)
			if
				valid
				and valid.Id == tracked.Id
				and valid.Kind == tracked.Kind
				and valid.ResetToken == tracked.ResetToken
			then
				tracked = valid
				local offset = valid.Point - crosshairRay.Origin
				if offset.Magnitude > 0.001 then
					return table.freeze({
						Mode = "ASSIST_LOCK",
						TargetId = valid.Id,
						TargetKind = valid.Kind,
						CrosshairRay = crosshairRay,
						ShotRay = Ray.new(crosshairRay.Origin, offset.Unit),
					})
				end
			end
			self:ReleaseTracking("fire_snapshot_stale", true)
		end
		return table.freeze({
			Mode = "CROSSHAIR_FREE",
			TargetId = nil,
			TargetKind = nil,
			CrosshairRay = crosshairRay,
			ShotRay = crosshairRay,
		})
	end

	-- A first-hit camera ray is the only deliberate PvP selection. Assistance
	-- remains limited to the existing wild/decoy candidate list. No cached slot
	-- can silently select its replacement occupant.
	function controller:GetCrosshairTarget(mountedCart: Model?): any?
		if self:IsInputSuspended() then
			return nil
		end
		local ray = centreRay(world.CurrentCamera)
		if not ray then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclusions: { Instance } = {}
		if player.Character then
			table.insert(exclusions, player.Character)
		end
		if mountedCart then
			table.insert(exclusions, mountedCart)
		end
		excludeOwnedCart(exclusions)
		local effects = world:FindFirstChild("SleepBoltEffects")
		if effects then
			table.insert(exclusions, effects)
		end
		params.FilterDescendantsInstances = exclusions
		params.IgnoreWater, params.RespectCanCollide = false, false
		local hit = world:Raycast(ray.Origin, ray.Direction * weaponProfile.rangeStuds, params)
		if not hit then
			return nil
		end
		local ancestor: Instance? = hit.Instance
		while ancestor and ancestor ~= world do
			if not Visibility.IsVisible(ancestor) then
				return nil
			end
			local kind = ancestor:GetAttribute("Phase10TargetKind")
			if kind == "Cargo" or kind == "Held" then
				local id = ancestor:GetAttribute("ItemId")
				local owner = ancestor:GetAttribute("OwnerUserId")
				if type(id) ~= "string" or type(owner) ~= "number" then
					return nil
				end
				lastDeliberate = now()
				self:ReleaseTracking("deliberate_target", true)
				return {
					Model = ancestor,
					Kind = kind,
					ItemId = id,
					CartId = ancestor:GetAttribute("Phase10CartId"),
					PlayerUserId = owner,
					Banked = ancestor:GetAttribute("Phase10Banked") == true,
					Hit = hit,
				}
			end
			if ancestor:IsA("Model") then
				local targetPlayer = game:GetService("Players"):GetPlayerFromCharacter(ancestor)
				if targetPlayer and targetPlayer ~= player then
					lastDeliberate = now()
					self:ReleaseTracking("deliberate_target", true)
					return {
						Model = ancestor,
						Kind = "Player",
						PlayerUserId = targetPlayer.UserId,
						Player = targetPlayer,
						Hit = hit,
					}
				end
			end
			ancestor = ancestor.Parent
		end
		return nil
	end

	function controller:Refresh()
		if destroyed then
			return
		end
		local humanoid = eligible()
		local camera = world.CurrentCamera
		if
			self:IsInputSuspended()
			or not humanoid
			or not camera
			or camera.CameraType ~= Enum.CameraType.Custom
			or camera.CameraSubject ~= humanoid
		then
			release()
			return
		end
		if active and (active.Humanoid ~= humanoid or active.Camera ~= camera) then
			release()
		end
		if active or blocked then
			return
		end
		active = {
			Humanoid = humanoid,
			Camera = camera,
			Saved = {},
			Offset = humanoid.CameraOffset + SHOULDER,
			Mouse = input.PreferredInput == Enum.PreferredInput.KeyboardAndMouse,
		}
		self:ReleaseTracking("entered", true)
		nextScan = 0
		claim(active, humanoid, "AutoRotate", false)
		claim(active, humanoid, "CameraOffset", active.Offset)
		claim(active, player, "CameraMode", Enum.CameraMode.Classic)
		-- Widen the existing interval before narrowing it, including unusual saved bounds.
		if player.CameraMinZoomDistance > DISTANCE then
			claim(active, player, "CameraMinZoomDistance", DISTANCE)
			claim(active, player, "CameraMaxZoomDistance", DISTANCE)
		else
			claim(active, player, "CameraMaxZoomDistance", DISTANCE)
			claim(active, player, "CameraMinZoomDistance", DISTANCE)
		end
		if active.Mouse then
			claim(active, input, "MouseBehavior", Enum.MouseBehavior.LockCenter)
			claim(active, input, "MouseIconEnabled", false)
		end
		-- CameraInput correction enters ClassicCamera before its framing and
		-- Poppercam collision. The default owner commits once and adopts that
		-- heading; this binding only reads the final view for character yaw.
		attachCameraInput()
		run:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 1, function()
			self:Update()
		end)
		notify()
	end

	function controller:SetCharacter(character: Model?)
		if desired ~= character then
			release()
			desired, blocked = character, false
		end
		self:Refresh()
	end

	local function refresh()
		controller:Refresh()
		notify()
	end
	local function observe(signal: any, callback: any)
		table.insert(connections, signal:Connect(callback))
	end
	local function observeCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		local camera = world.CurrentCamera
		cameraConnection = if camera
			then camera.Changed:Connect(function(property: string)
				if property == "CameraType" or property == "CameraSubject" then
					refresh()
				end
			end)
			else nil
		refresh()
	end
	observe(world:GetPropertyChangedSignal("CurrentCamera"), observeCamera)
	observe(gui:GetPropertyChangedSignal("MenuIsOpen"), refresh)
	observe(gui:GetPropertyChangedSignal("SelectedObject"), refresh)
	observe(input.TextBoxFocused, refresh)
	observe(input.TextBoxFocusReleased, refresh)
	observe(input.WindowFocusReleased, function()
		focused = false
		refresh()
	end)
	observe(input.WindowFocused, function()
		focused = true
		refresh()
	end)
	observe(input:GetPropertyChangedSignal("PreferredInput"), function()
		release()
		refresh()
	end)
	observeCamera()

	function controller:Destroy()
		destroyed = true
		release()
		desired = nil
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
	end
	return controller
end

return ThirdPersonAimController
