--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CartCamera = require(ReplicatedStorage.Shared.Config.CartCamera)
local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)
local MountedAim = require(ReplicatedStorage.Shared.Config.MountedAim)
local MountedAimMath = require(ReplicatedStorage.Shared.Utility.MountedAimMath)
local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local CartCameraMath = require(ReplicatedStorage.Shared.Utility.CartCameraMath)
local CartCameraOcclusion = require(ReplicatedStorage.Shared.Utility.CartCameraOcclusion)
local CartCameraRuntimeState = require(ReplicatedStorage.Shared.Utility.CartCameraRuntimeState)
local CartCameraConfigValidator = require(ReplicatedStorage.Shared.Validation.CartCameraConfigValidator)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local Handling = require(ReplicatedStorage.Shared.Config.CartHandlingConfig)
local HandlingMath = require(ReplicatedStorage.Shared.Utility.CartHandlingMath)
local CameraVolume = require(ReplicatedStorage.Shared.Utility.CartCameraVolume)
local Geometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)
local CartInputController = require(script.Parent.CartInputController)
local LocalCartResetState = require(script.Parent.Parent.State.LocalCartResetState)
local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local MountedAimState = require(script.Parent.Parent.State.MountedAimState)
local Phase10InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)

type CameraSnapshot = CartCameraRuntimeState.Snapshot
type OcclusionResolver = CartCameraOcclusion.Resolver
type CameraSubject = Humanoid | BasePart

local log = Logger.new("CartCameraController")

local CartCameraController = {}

local RENDER_BINDING_NAME = "BrainrotExpedition.CartCamera"
local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local ROOT_NAME = "Root"
local TARGET_NAME = "CameraTarget"

local player = Players.LocalPlayer
local developmentTuning = CartCamera.Development

local controllerConnections: { RBXScriptConnection } = {}
local cartConnections: { RBXScriptConnection } = {}
local activeConnections: { RBXScriptConnection } = {}

local runtime: CameraSnapshot = CartCameraRuntimeState.Create()
local observedCart: Model? = nil
local activeCart: Model? = nil
local activeRoot: BasePart? = nil
local activeTarget: BasePart? = nil
local claimedCamera: Camera? = nil
local previousCameraType: Enum.CameraType? = nil
local previousCameraSubject: Instance? = nil
local smoothedCFrame: CFrame? = nil
local smoothedLookAhead: Vector3? = nil
local smoothedFitDistance: number? = nil
local occlusionResolver: OcclusionResolver? = nil
local structuralYaw = 0
local neutralInputAt = 0
local previousFov: number? = nil
local bodySize = Vector3.new(7, 3, 10)
local mountedMinimum, zoomDistance, pinchScale = 7, 18, 1
local priorMinimumZoom: number? = nil
local priorMaximumZoom: number? = nil
local yawOffset = 0
local pitch = developmentTuning.DefaultPitch
local lastManualInputAt = 0
local started = false
local configValid = false
local renderBound = false
local windowFocused = true
local textInputFocused = false
local systemMenuOpen = false
local characterInvalidated = false
local cartRevision = 0
local warnedReadinessRevision = -1
local occlusionDiagnosticActive = false
local occlusionQueryFailureWarned = false
local aiming = false
local aimYaw, aimPitch = 0, 0
local savedOrbitYaw, savedOrbitPitch = 0, developmentTuning.DefaultPitch
local previousMouseBehavior: Enum.MouseBehavior? = nil
local previousMouseIconEnabled: boolean? = nil
local reconciling = false
local reconcile: (string) -> ()
local lastMountedCart: Model? = nil
local lastAimRequested = false
local lastAimBlocked = false
local aimIntentDirty = false

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function getLiveCameraSubject(subject: Instance?): CameraSubject?
	if subject == nil or subject.Parent == nil then
		return nil
	end

	if subject:IsA("Humanoid") then
		return subject
	end

	if subject:IsA("BasePart") then
		return subject
	end

	return nil
end

local function resolveCharacterCameraSubject(): CameraSubject?
	if characterInvalidated then
		return nil
	end

	local character = player.Character

	if character == nil or character.Parent == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	return if humanoid ~= nil and humanoid.Parent ~= nil then humanoid else nil
end

local function isInputSuppressed(): boolean
	return not windowFocused or textInputFocused or systemMenuOpen
end

local function isCameraInputApplicable(): boolean
	return UserInputService.TouchEnabled
		or (UserInputService.KeyboardEnabled and UserInputService.MouseEnabled)
		or UserInputService.GamepadEnabled
end

local function restoreAimMouse()
	if previousMouseBehavior ~= nil then
		UserInputService.MouseBehavior = previousMouseBehavior
		previousMouseBehavior = nil
	end
	if previousMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = previousMouseIconEnabled
		previousMouseIconEnabled = nil
	end
end

local function updateAimMouse()
	if aiming and UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		if previousMouseBehavior == nil then
			previousMouseBehavior = UserInputService.MouseBehavior
			previousMouseIconEnabled = UserInputService.MouseIconEnabled
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		restoreAimMouse()
	end
end

local function updateOrbitInputAvailability()
	local enabled = runtime.Active
		and not aiming
		and LocalCartState.IsAuthorizedDriver()
		and isCameraInputApplicable()
		and not runtime.ResetSuspended
		and not isInputSuppressed()

	CartInputController.SetCameraOrbitEnabled(enabled and UserInputService.TouchEnabled)
	CartInputController.SetPCCameraOrbitEnabled(
		enabled and UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
	)
	CartInputController.SetGamepadCameraOrbitEnabled(enabled and UserInputService.GamepadEnabled)

	if not enabled then
		runtime = CartCameraRuntimeState.ClearManualInput(runtime)
	end
end

local function restoreClaimedCamera()
	if priorMinimumZoom and priorMaximumZoom then
		player.CameraMinZoomDistance = priorMinimumZoom
		player.CameraMaxZoomDistance = priorMaximumZoom
	end
	priorMinimumZoom, priorMaximumZoom = nil, nil
	local camera = claimedCamera

	if camera == nil or camera.Parent == nil or camera.CameraType ~= Enum.CameraType.Scriptable then
		return
	end

	if characterInvalidated then
		camera.CameraSubject = nil :: any
	else
		local subject = getLiveCameraSubject(previousCameraSubject) or resolveCharacterCameraSubject()

		if subject ~= nil then
			camera.CameraSubject = subject
		end
	end

	if previousFov then
		camera.FieldOfView = previousFov
	end
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
end

local function resetOcclusionState(clearFilterContext: boolean)
	local resolver = occlusionResolver

	if resolver ~= nil then
		if clearFilterContext then
			resolver:SetFilterContext(nil, nil)
		end

		resolver:Reset()
	end

	occlusionDiagnosticActive = false
	occlusionQueryFailureWarned = false
end

local function getInstanceDiagnosticPath(instance: Instance?): string
	if instance == nil then
		return "unknown"
	end

	local succeeded, path = pcall(function()
		return instance:GetFullName()
	end)

	return if succeeded then path else instance.Name
end

local function releaseCamera(reason: string, preserveAimRequest: boolean?)
	local wasActive = runtime.Active
	aiming = false
	restoreAimMouse()
	MountedAimState.SetActive(nil, false)
	if not preserveAimRequest then
		MountedAimState.ClearRequested()
	end

	if renderBound then
		RunService:UnbindFromRenderStep(RENDER_BINDING_NAME)
		renderBound = false
	end
	disconnectAll(activeConnections)
	CartInputController.SetPCCameraOrbitEnabled(false)
	CartInputController.SetCameraOrbitEnabled(false)
	CartInputController.SetGamepadCameraOrbitEnabled(false)
	resetOcclusionState(true)
	restoreClaimedCamera()

	runtime = CartCameraRuntimeState.Deactivate(runtime)
	activeCart = nil
	activeRoot = nil
	activeTarget = nil
	claimedCamera = nil
	previousCameraType = nil
	previousCameraSubject = nil
	previousFov = nil
	smoothedCFrame = nil
	smoothedLookAhead = nil
	smoothedFitDistance = nil
	structuralYaw = 0
	yawOffset = 0
	pitch = developmentTuning.DefaultPitch
	lastManualInputAt = 0

	if wasActive then
		log:Debug("Cart camera deactivated Reason=%s", reason)
	end
end

-- Match the current mounted-fire role: a real occupied, authorized owned
-- DriverSeat. A local view request never grants firing or vehicle authority.
local function resolveMountedCart(): Model?
	if characterInvalidated or not LocalCartState.IsAuthorizedDriver() then
		return nil
	end
	local cart = LocalCartState.GetCart()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	if
		not cart
		or not cart.Parent
		or not character
		or not humanoid
		or humanoid.Health <= 0
		or not seat
		or not seat:IsA("VehicleSeat")
		or seat.Occupant ~= humanoid
		or seat ~= cart:FindFirstChild("DriverSeat", true)
	then
		return nil
	end
	return cart
end

local function aimBlocked(): boolean
	return isInputSuppressed() or Phase10InputPolicy.IsBlocked(player, GuiService, UserInputService)
end

local function stopAim()
	if not aiming then
		return
	end
	aiming = false
	yawOffset, pitch = savedOrbitYaw, savedOrbitPitch
	lastManualInputAt = os.clock()
	runtime = CartCameraRuntimeState.ClearManualInput(runtime)
	MountedAimState.SetActive(nil, false)
	MountedAimState.ClearLook()
	restoreAimMouse()
	updateOrbitInputAvailability()
end

local function startAim(camera: Camera)
	if aiming then
		return
	end
	savedOrbitYaw, savedOrbitPitch = yawOffset, pitch
	aimYaw, aimPitch =
		MountedAimMath.FromLookVector(camera.CFrame.LookVector, MountedAim.MinimumPitch, MountedAim.MaximumPitch)
	aiming = true
	-- Start the tighter frame from the actual displayed view, including any
	-- prior obstruction correction; never infer aim from the chassis yaw.
	smoothedCFrame = camera.CFrame
	runtime = CartCameraRuntimeState.ConsumeResync(runtime)
	MountedAimState.SetActive(activeCart, true)
	CartInputController.ConsumePCCameraOrbit()
	updateOrbitInputAvailability()
	updateAimMouse()
end

local function isResetSuspended(cart: Model): boolean
	return LocalCartResetState.IsActiveFor(cart) or cart:GetAttribute(CartResetLifecycle.Attributes.Active) == true
end

local function refreshResetState(reason: string)
	local cart = activeCart

	if not runtime.Active or cart == nil then
		return
	end

	local nextSuspended = isResetSuspended(cart)

	if runtime.ResetSuspended == nextSuspended then
		return
	end

	runtime = CartCameraRuntimeState.SetResetSuspended(runtime, nextSuspended)
	resetOcclusionState(false)
	updateOrbitInputAvailability()
	log:Debug("Cart camera reset synchronisation changed Active=%s Reason=%s", tostring(nextSuspended), reason)
end

local function resolveCartParts(cart: Model?): (BasePart?, BasePart?)
	if cart == nil or cart.Parent == nil then
		return nil, nil
	end

	local root = cart:FindFirstChild(ROOT_NAME)
	local target = cart:FindFirstChild(TARGET_NAME)

	if
		root == nil
		or not root:IsA("BasePart")
		or root.Parent ~= cart
		or target == nil
		or not target:IsA("BasePart")
		or target.Parent ~= cart
	then
		return nil, nil
	end

	if not CartCameraMath.IsFiniteCFrame(root.CFrame) or not CartCameraMath.IsFiniteCFrame(target.CFrame) then
		return nil, nil
	end

	return root, target
end

local function buildActivationContext(
	cart: Model?,
	root: BasePart?,
	target: BasePart?,
	camera: Camera?
): CartCameraRuntimeState.ActivationContext
	local resetSuspended = cart ~= nil and isResetSuspended(cart)
	local cameraAlreadyActive = runtime.Active and activeCart == cart
	local assemblyState = if cart ~= nil then cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) else nil

	return {
		ControllerStarted = started and configValid,
		PlayerActive = player.Parent == Players,
		AuthorizedDriver = cart ~= nil and LocalCartState.GetCart() == cart and LocalCartState.IsAuthorizedDriver(),
		CartAvailable = cart ~= nil and cart.Parent ~= nil,
		CartReady = CartCameraRuntimeState.IsCartReady(assemblyState, cameraAlreadyActive, resetSuspended),
		TargetValid = root ~= nil and target ~= nil,
		CameraAvailable = camera ~= nil and camera.Parent ~= nil,
		CameraInputApplicable = isCameraInputApplicable(),
	}
end

local function applyCameraFrame(deltaTime: number)
	local camera = claimedCamera
	local cart = activeCart
	local root = activeRoot
	local target = activeTarget

	if
		not runtime.Active
		or camera == nil
		or cart == nil
		or root == nil
		or target == nil
		or Workspace.CurrentCamera ~= camera
		or cart.Parent == nil
		or root.Parent ~= cart
		or target.Parent ~= cart
		or not CartCameraMath.IsFiniteCFrame(root.CFrame)
		or not CartCameraMath.IsFiniteCFrame(target.CFrame)
	then
		releaseCamera("active camera context became invalid")
		return
	end

	local mountedCart = resolveMountedCart()
	local blocked = aimBlocked()
	local shouldAim = mountedCart == cart
		and MountedAimState.GetCart() == cart
		and MountedAimState.IsRequested()
		and not blocked
		and not runtime.ResetSuspended
	if blocked or runtime.ResetSuspended or mountedCart ~= cart then
		MountedAimState.ClearRequested()
	end
	if shouldAim then
		startAim(camera)
	elseif aiming then
		stopAim()
	end
	if not aiming and (not LocalCartState.IsAuthorizedDriver() or not isCameraInputApplicable()) then
		releaseCamera("mounted aiming view released")
		return
	end

	if aiming then
		-- Consume the legacy RMB orbit so the same gesture cannot apply twice.
		CartInputController.ConsumePCCameraOrbit()
		aimYaw, aimPitch = MountedAimMath.ApplyLook(
			aimYaw,
			aimPitch,
			MountedAimState.ConsumePointerDelta(),
			MountedAimState.GetGamepadLook(),
			deltaTime,
			MountedAim.MouseRadiansPerPixel,
			MountedAim.GamepadRadiansPerSecond,
			MountedAim.MinimumPitch,
			MountedAim.MaximumPitch
		)
		updateAimMouse()
		runtime = CartCameraRuntimeState.SetManualInputActive(runtime, true)
	elseif not runtime.ResetSuspended and not isInputSuppressed() then
		local inputDevice = CartInputController.GetInputDevice()
		local pcOrbit = CartInputController.ConsumePCCameraOrbit()
		local gamepadOrbit = CartInputController.GetGamepadCameraIntent()
		local manualInputApplied = false

		if inputDevice == "Gamepad" and gamepadOrbit.Magnitude > developmentTuning.ManualInputThreshold then
			yawOffset, pitch = CartCameraMath.ApplyGamepadOrbit(
				yawOffset,
				pitch,
				gamepadOrbit,
				CartCamera.GamepadSensitivity,
				CartGamepad.Development.CameraRadiansPerSecond,
				deltaTime,
				developmentTuning.MinimumPitch,
				developmentTuning.MaximumPitch
			)
			manualInputApplied = true
		elseif
			(inputDevice == "KeyboardMouse" or inputDevice == "Touch")
			and pcOrbit.Magnitude > developmentTuning.ManualInputThreshold
		then
			yawOffset, pitch = CartCameraMath.ApplyManualOrbit(
				yawOffset,
				pitch,
				pcOrbit,
				if inputDevice == "Touch" then 1 else CartCamera.PCSensitivity,
				if inputDevice == "Touch" then CartCamera.TouchSensitivity else developmentTuning.MouseRadiansPerPixel,
				developmentTuning.MinimumPitch,
				developmentTuning.MaximumPitch
			)
			manualInputApplied = true
		end

		if manualInputApplied then
			lastManualInputAt = os.clock()
			runtime = CartCameraRuntimeState.SetManualInputActive(runtime, true)
		elseif runtime.ManualInputActive then
			runtime = CartCameraRuntimeState.ClearManualInput(runtime)
		end
	else
		CartInputController.ConsumePCCameraOrbit()
	end

	local moving = CartInputController.IsMovementIntentActive()
	if moving then
		neutralInputAt = os.clock()
	end
	if
		not aiming
		and not runtime.ResetSuspended
		and HandlingMath.ShouldRecenter(
			os.clock(),
			neutralInputAt,
			lastManualInputAt,
			moving,
			runtime.ManualInputActive
		)
	then
		local absolute = CartCameraMath.WrapAngle(structuralYaw + yawOffset)
		local desired = CartCameraMath.GetStructuralYaw(root.CFrame, structuralYaw)
		structuralYaw = CartCameraMath.WrapAngle(
			absolute + CartCameraMath.WrapAngle(desired - absolute) * (1 - math.exp(-deltaTime / Handling.CameraYawTau))
		)
		yawOffset = 0
	end

	local desiredCFrame: CFrame
	local focus: Vector3
	if aiming then
		desiredCFrame, focus = MountedAimMath.GetDesiredCFrame(
			target.Position,
			aimYaw,
			aimPitch,
			MountedAim.Distance,
			MountedAim.ShoulderOffset,
			MountedAim.HeightOffset
		)
	else
		local speed = math.max(0, root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector))
		local lookAhead = math.clamp(
			speed * Handling.CameraLookAheadSeconds,
			Handling.CameraMinimumLookAhead,
			Handling.CameraMaximumLookAhead
		)
		local forward =
			HandlingMath.Unit(HandlingMath.Project(root.CFrame.LookVector, Vector3.yAxis), Vector3.new(0, 0, -1))
		-- Ease the look-ahead instead of pinning it to the chassis heading: a
		-- sharp turn otherwise drags the focus around the cart on a 3-10 stud arm.
		local snap = runtime.ResyncRequired or runtime.ResetSuspended or smoothedCFrame == nil
		local lead = smoothedLookAhead
		if snap or lead == nil then
			lead = forward * lookAhead
		else
			lead = lead:Lerp(forward * lookAhead, 1 - math.exp(-deltaTime / Handling.CameraLookAheadTau))
		end
		smoothedLookAhead = lead
		desiredCFrame, focus = CartCameraMath.GetDesiredCFrame(
			CFrame.new(target.Position + lead),
			CFrame.Angles(0, structuralYaw, 0),
			yawOffset,
			pitch,
			zoomDistance,
			math.clamp(
				bodySize.Y * 0.5 + Handling.CameraHeightAdd,
				Handling.CameraMinimumHeight,
				Handling.CameraMaximumHeight
			),
			structuralYaw
		)
		-- The existing camera owner frames the complete measured presentation.
		local lo, hi = cart:GetAttribute("FrontPresentationBoundsMin"), cart:GetAttribute("FrontPresentationBoundsMax")
		local cargoLo, cargoHi =
			cart:GetAttribute("CargoPresentationBoundsMin"), cart:GetAttribute("CargoPresentationBoundsMax")
		if typeof(lo) == "Vector3" or typeof(cargoLo) == "Vector3" then
			local profile = require(ReplicatedStorage.Shared.Config.CartGeometry)[cart:GetAttribute("CartId")]
			if profile then
				local low = profile.VisualBounds.Frame.Position - profile.VisualBounds.Size / 2
				local high = profile.VisualBounds.Frame.Position + profile.VisualBounds.Size / 2
				if typeof(lo) == "Vector3" then
					low = low:Min(lo)
					high = high:Max(hi)
				end
				if typeof(cargoLo) == "Vector3" then
					low = low:Min(cargoLo)
					high = high:Max(cargoHi)
				end
				local rider = profile.RiderClearance
				low = low:Min(rider.Frame.Position - rider.Size / 2)
				high = high:Max(rider.Frame.Position + rider.Size / 2)
				local cf = CFrame.lookAt(focus, focus + desiredCFrame.LookVector)
				local corners = {}
				for _, x in { low.X, high.X } do
					for _, y in { low.Y, high.Y } do
						for _, z in { low.Z, high.Z } do
							local q = cf:PointToObjectSpace(root.CFrame * Vector3.new(x, y, z))
							table.insert(corners, Vector3.new(q.X, q.Y, -q.Z))
						end
					end
				end
				local aspect = camera.ViewportSize.X / camera.ViewportSize.Y
				local fov = camera.FieldOfView
				if camera.FieldOfViewMode == Enum.FieldOfViewMode.Diagonal then
					fov = math.deg(
						2
							* math.atan(
								math.tan(math.rad(camera.DiagonalFieldOfView) / 2) / math.sqrt(1 + aspect * aspect)
							)
					)
				elseif camera.FieldOfViewMode == Enum.FieldOfViewMode.MaxAxis and aspect > 1 then
					fov = math.deg(2 * math.atan(math.tan(math.rad(camera.MaxAxisFieldOfView) / 2) / aspect))
				end
				local distance = require(ReplicatedStorage.Shared.Utility.ExactBodyPlacement).CameraDistance(
					corners,
					fov,
					aspect,
					zoomDistance
				)
				-- The fitted distance depends on how the cart is turned to the
				-- view (side-on needs more room than end-on); ease it so turning
				-- does not pump the zoom.
				local fit = smoothedFitDistance
				if snap or fit == nil then
					fit = distance
				else
					fit += (distance - fit) * (1 - math.exp(-deltaTime / Handling.CameraFitDistanceTau))
				end
				smoothedFitDistance = fit
				desiredCFrame, focus = CartCameraMath.GetDesiredCFrame(
					CFrame.new(target.Position + lead),
					CFrame.Angles(0, structuralYaw, 0),
					yawOffset,
					pitch,
					fit,
					math.clamp(
						bodySize.Y * 0.5 + Handling.CameraHeightAdd,
						Handling.CameraMinimumHeight,
						Handling.CameraMaximumHeight
					),
					structuralYaw
				)
			end
		end
		if previousFov then
			local legal = cart:GetAttribute("ResolvedMaxTravelSpeed") or Handling.StarterSpeed
			local optional = player:GetAttribute("ReducedMotion") ~= true
			local amount = if optional
				then math.clamp(speed / math.max(legal, 1), 0, 1) * Handling.CameraFovAddition
				else 0
			if optional and cart:GetAttribute("BurstActive") == true then
				amount += Handling.BurstFovAddition
			end
			-- "ESCAPED!" punch from EscapeRingController (villager guards only).
			local punch = player:GetAttribute("EscapeFovPunch")
			if optional and type(punch) == "number" and punch > 0 and punch <= 12 then
				amount += punch
			end
			camera.FieldOfView += (previousFov + amount - camera.FieldOfView) * (1 - math.exp(
				-deltaTime / Handling.CameraYawTau
			))
		end
	end

	if not CartCameraMath.IsFiniteCFrame(desiredCFrame) then
		releaseCamera("camera transform became non-finite")
		return
	end

	local resynchronizeCamera = runtime.ResyncRequired or runtime.ResetSuspended or smoothedCFrame == nil

	if resynchronizeCamera then
		smoothedCFrame = desiredCFrame
		runtime = CartCameraRuntimeState.ConsumeResync(runtime)
	else
		smoothedCFrame = CartCameraMath.SmoothCFrame(
			smoothedCFrame,
			desiredCFrame,
			if aiming then MountedAim.PositionResponsiveness else 1 / Handling.CameraPositionTau,
			if aiming then MountedAim.RotationResponsiveness else 1000,
			deltaTime
		)
	end

	if smoothedCFrame == nil or not CartCameraMath.IsFiniteCFrame(smoothedCFrame) then
		releaseCamera("smoothed camera transform became non-finite")
		return
	end

	local resolver = occlusionResolver

	if resolver == nil then
		releaseCamera("camera occlusion resolver unavailable")
		return
	end

	local occlusionResult, occlusionError =
		resolver:Resolve(focus, smoothedCFrame.Position, deltaTime, resynchronizeCamera)

	if occlusionResult == nil then
		log:Warn("Cart camera obstruction correction failed: %s", occlusionError or "unknown")
		releaseCamera("camera obstruction correction failure")
		return
	end

	if occlusionResult.QueryFailed then
		if not occlusionQueryFailureWarned then
			occlusionQueryFailureWarned = true
			log:Warn(
				"Cart camera obstruction query failed Cart=%s Detail=%s",
				cart.Name,
				occlusionResult.Failure or "unknown"
			)
		end
	elseif occlusionQueryFailureWarned then
		occlusionQueryFailureWarned = false
		log:Debug("Cart camera obstruction query recovered Cart=%s", cart.Name)
	end

	if occlusionResult.Obstructed and not occlusionDiagnosticActive then
		occlusionDiagnosticActive = true
		local hit = occlusionResult.HitInstance

		log:Debug(
			"Cart camera obstruction active Cart=%s Hit=%s HitDistance=%.2f CorrectedDistance=%.2f InitialOverlap=%s MinimumCompromised=%s FilterRevision=%d",
			cart.Name,
			getInstanceDiagnosticPath(hit),
			occlusionResult.HitDistance or 0,
			occlusionResult.CorrectedDistance,
			tostring(occlusionResult.InitialOverlap),
			tostring(occlusionResult.MinimumCompromised),
			occlusionResult.FilterRevision
		)
	elseif
		occlusionDiagnosticActive
		and not occlusionResult.Obstructed
		and math.abs(occlusionResult.DesiredDistance - occlusionResult.CorrectedDistance)
			<= CartCamera.Obstruction.DistanceTolerance
	then
		occlusionDiagnosticActive = false
		log:Debug("Cart camera obstruction cleared Cart=%s", cart.Name)
	end

	local finalCFrame = CartCameraOcclusion.ApplyCorrectedPosition(smoothedCFrame, occlusionResult.CorrectedPosition)

	if finalCFrame == nil or not CartCameraMath.IsFiniteCFrame(finalCFrame) then
		releaseCamera("camera obstruction produced a non-finite frame")
		return
	end

	camera.CFrame = finalCFrame
	camera.Focus =
		CFrame.new(if aiming then finalCFrame.Position + finalCFrame.LookVector * MountedAim.FocusDistance else focus)
end

local function renderUpdate(deltaTime: number)
	local succeeded, failure = pcall(applyCameraFrame, deltaTime)

	if succeeded then
		return
	end

	log:Warn("Cart camera render callback failed: %s", tostring(failure))
	releaseCamera("render callback failure")
end

local function bindActiveLifecycle(cart: Model, root: BasePart, target: BasePart, expectedContextRevision: number)
	disconnectAll(activeConnections)

	local function invalidate(reason: string)
		if
			runtime.Active
			and activeCart == cart
			and CartCameraRuntimeState.IsCurrent(runtime, expectedContextRevision)
		then
			warnedReadinessRevision = cartRevision
			log:Warn(
				"Cart camera target context invalidated Cart=%s CartId=%s Reason=%s",
				cart.Name,
				tostring(cart:GetAttribute("CartId")),
				reason
			)
			releaseCamera(reason)
		end
	end

	table.insert(
		activeConnections,
		root.Destroying:Connect(function()
			invalidate("Root destroyed")
		end)
	)
	table.insert(
		activeConnections,
		target.Destroying:Connect(function()
			invalidate("CameraTarget destroyed")
		end)
	)
	table.insert(
		activeConnections,
		root.AncestryChanged:Connect(function()
			if root.Parent ~= cart then
				invalidate("Root left active cart")
			end
		end)
	)
	table.insert(
		activeConnections,
		target.AncestryChanged:Connect(function()
			if target.Parent ~= cart then
				invalidate("CameraTarget left active cart")
			end
		end)
	)
end

local function engageCamera(cart: Model, root: BasePart, target: BasePart, camera: Camera)
	releaseCamera("camera context replaced", true)

	activeCart = cart
	activeRoot = root
	activeTarget = target
	claimedCamera = camera
	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousFov = camera.FieldOfView
	local geometry = Geometry.Get(cart)
	bodySize = if geometry then geometry.BodySize else root.Size
	mountedMinimum = CameraVolume.MinimumZoom(bodySize.Z)
	zoomDistance = math.clamp(
		bodySize.Z + Handling.CameraDistanceAdd,
		Handling.CameraMinimumDistance,
		Handling.CameraMaximumDistance
	)
	priorMinimumZoom, priorMaximumZoom = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
	player.CameraMaxZoomDistance = math.max(24, mountedMinimum, player.CameraMaxZoomDistance)
	player.CameraMinZoomDistance = mountedMinimum
	neutralInputAt = os.clock()

	local resolver = occlusionResolver

	if resolver == nil then
		log:Warn("Cart camera could not activate because obstruction resolver is unavailable")
		releaseCamera("camera obstruction resolver unavailable")
		return
	end

	resolver:SetFilterContext(cart, player.Character)
	resolver:Reset()
	occlusionDiagnosticActive = false
	occlusionQueryFailureWarned = false
	yawOffset = 0
	pitch = developmentTuning.DefaultPitch
	structuralYaw = CartCameraMath.GetStructuralYaw(root.CFrame, 0)
	lastManualInputAt = os.clock()
	smoothedCFrame = nil
	runtime = CartCameraRuntimeState.Activate(runtime)
	runtime = CartCameraRuntimeState.SetResetSuspended(runtime, isResetSuspended(cart))
	local expectedContextRevision = runtime.ContextRevision

	camera.CameraType = Enum.CameraType.Scriptable
	bindActiveLifecycle(cart, root, target, expectedContextRevision)
	updateOrbitInputAvailability()

	local bindSucceeded, bindFailure = pcall(function()
		RunService:BindToRenderStep(RENDER_BINDING_NAME, Enum.RenderPriority.Camera.Value + 1, renderUpdate)
	end)

	if not bindSucceeded then
		log:Warn("Cart camera render binding failed: %s", tostring(bindFailure))
		releaseCamera("render binding failure")
		return
	end

	renderBound = true
	renderUpdate(0)

	if not runtime.Active then
		return
	end

	log:Debug(
		"Cart camera activated Cart=%s CartId=%s Target=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		target:GetFullName()
	)
end

reconcile = function(reason: string)
	if reconciling then
		return
	end
	reconciling = true
	local cart = observedCart
	local root, target = resolveCartParts(cart)
	local camera = Workspace.CurrentCamera
	local context = buildActivationContext(cart, root, target, camera)
	local mountedCart = resolveMountedCart()
	local mountedAvailable = started
		and configValid
		and not characterInvalidated
		and mountedCart ~= nil
		and mountedCart == cart
		and context.CartAvailable
		and context.CartReady
		and context.TargetValid
		and context.CameraAvailable
		and not isResetSuspended(mountedCart :: Model)
	MountedAimState.SetContext(if mountedAvailable then mountedCart else nil)
	if aimBlocked() then
		MountedAimState.ClearRequested()
	end
	local wantsAim = mountedAvailable and MountedAimState.IsRequested() and not aimBlocked()

	if not CartCameraRuntimeState.CanActivate(context) and not wantsAim then
		releaseCamera(reason)

		if
			cart ~= nil
			and LocalCartState.IsAuthorizedDriver()
			and context.CameraInputApplicable
			and warnedReadinessRevision ~= cartRevision
		then
			warnedReadinessRevision = cartRevision
			log:Warn(
				"Cart camera unavailable Cart=%s AssemblyState=%s RootValid=%s TargetValid=%s CameraAvailable=%s CameraInputApplicable=%s",
				cart.Name,
				tostring(cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE)),
				tostring(root ~= nil),
				tostring(target ~= nil),
				tostring(camera ~= nil),
				tostring(isCameraInputApplicable())
			)
		end

		reconciling = false
		return
	end

	warnedReadinessRevision = -1

	if
		runtime.Active
		and activeCart == cart
		and activeRoot == root
		and activeTarget == target
		and claimedCamera == camera
	then
		refreshResetState(reason)
		updateOrbitInputAvailability()
		reconciling = false
		return
	end

	engageCamera(cart :: Model, root :: BasePart, target :: BasePart, camera :: Camera)
	reconciling = false
end

local function bindObservedCart(cart: Model?)
	if observedCart == cart then
		return
	end

	disconnectAll(cartConnections)
	cartRevision += 1
	warnedReadinessRevision = -1
	observedCart = cart

	if cart == nil then
		return
	end

	local expectedRevision = cartRevision

	local function refresh(reason: string)
		if started and observedCart == cart and cartRevision == expectedRevision then
			reconcile(reason)
		end
	end

	table.insert(
		cartConnections,
		cart:GetAttributeChangedSignal(ASSEMBLY_STATE_ATTRIBUTE):Connect(function()
			refresh("assembly readiness changed")
		end)
	)
	table.insert(
		cartConnections,
		cart:GetAttributeChangedSignal(CartResetLifecycle.Attributes.Active):Connect(function()
			refreshResetState("replicated reset state changed")
			refresh("replicated reset state changed")
		end)
	)
	table.insert(
		cartConnections,
		cart.ChildAdded:Connect(function(child)
			if child.Name == ROOT_NAME or child.Name == TARGET_NAME then
				refresh("camera contract child added")
			end
		end)
	)
	table.insert(
		cartConnections,
		cart.ChildRemoved:Connect(function(child)
			if child.Name == ROOT_NAME or child.Name == TARGET_NAME then
				refresh("camera contract child removed")
			end
		end)
	)
	table.insert(
		cartConnections,
		cart.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				refresh("cart removed from hierarchy")
			end
		end)
	)
	table.insert(
		cartConnections,
		cart.Destroying:Connect(function()
			if observedCart == cart and cartRevision == expectedRevision then
				releaseCamera("cart destroyed")
			end
		end)
	)
end

local function updateSuppression(reason: string)
	if aimBlocked() then
		MountedAimState.ClearRequested()
		stopAim()
	end
	if runtime.Active then
		updateOrbitInputAvailability()
		log:Debug("Cart camera input context changed Suppressed=%s Reason=%s", tostring(isInputSuppressed()), reason)
	end
end

function CartCameraController.Start()
	if started then
		return
	end

	started = true
	windowFocused = true
	textInputFocused = UserInputService:GetFocusedTextBox() ~= nil
	systemMenuOpen = false
	characterInvalidated = false

	local validation = CartCameraConfigValidator.Validate(CartCamera)

	configValid = validation.IsValid

	if not configValid then
		log:Warn("Cart camera configuration invalid: %s", table.concat(validation.Errors, "; "))
		return
	end

	local resolverCreated, resolverOrError = pcall(CartCameraOcclusion.new, CartCamera.Obstruction)

	if not resolverCreated then
		configValid = false
		log:Warn("Cart camera obstruction resolver failed to initialise: %s", tostring(resolverOrError))
		return
	end

	occlusionResolver = resolverOrError :: OcclusionResolver
	table.insert(
		controllerConnections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if
				runtime.Active
				and not aiming
				and not processed
				and not isInputSuppressed()
				and input.UserInputType == Enum.UserInputType.MouseWheel
			then
				zoomDistance =
					math.clamp(zoomDistance - input.Position.Z * 2, mountedMinimum, Handling.CameraMaximumDistance)
			end
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService.TouchPinch:Connect(function(_points, scale, _velocity, state, processed)
			if state == Enum.UserInputState.Begin then
				pinchScale = scale
				return
			end
			if
				runtime.Active
				and not aiming
				and not processed
				and not isInputSuppressed()
				and state == Enum.UserInputState.Change
				and scale > 0
			then
				zoomDistance =
					math.clamp(zoomDistance * pinchScale / scale, mountedMinimum, Handling.CameraMaximumDistance)
			end
			pinchScale = scale
		end)
	)

	bindObservedCart(resolveMountedCart() or LocalCartState.GetCart())

	table.insert(
		controllerConnections,
		LocalCartState.Changed:Connect(function(cart)
			bindObservedCart(resolveMountedCart() or cart)
			reconcile("authoritative driver state changed")
		end)
	)
	table.insert(
		controllerConnections,
		LocalCartResetState.Changed:Connect(function(cart)
			if cart == nil or cart == observedCart then
				refreshResetState("local reset state changed")
				reconcile("local reset state changed")
			end
		end)
	)
	table.insert(
		controllerConnections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			if claimedCamera ~= nil and claimedCamera ~= Workspace.CurrentCamera then
				releaseCamera("CurrentCamera replaced")
			end

			reconcile("CurrentCamera changed")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(function()
			reconcile("keyboard availability changed")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(function()
			reconcile("mouse availability changed")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
			reconcile("touch availability changed")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService:GetPropertyChangedSignal("GamepadEnabled"):Connect(function()
			reconcile("gamepad availability changed")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService.WindowFocusReleased:Connect(function()
			windowFocused = false
			updateSuppression("application focus lost")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService.WindowFocused:Connect(function()
			windowFocused = true
			updateSuppression("application focus restored")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService.TextBoxFocused:Connect(function()
			textInputFocused = true
			updateSuppression("text input focused")
		end)
	)
	table.insert(
		controllerConnections,
		UserInputService.TextBoxFocusReleased:Connect(function()
			textInputFocused = false
			updateSuppression("text input released")
		end)
	)
	table.insert(
		controllerConnections,
		GuiService.MenuOpened:Connect(function()
			systemMenuOpen = true
			updateSuppression("system menu opened")
		end)
	)
	table.insert(
		controllerConnections,
		GuiService.MenuClosed:Connect(function()
			systemMenuOpen = false
			updateSuppression("system menu closed")
		end)
	)
	table.insert(
		controllerConnections,
		player.CharacterRemoving:Connect(function()
			characterInvalidated = true
			releaseCamera("local character removing")
		end)
	)
	table.insert(
		controllerConnections,
		player.CharacterAdded:Connect(function()
			characterInvalidated = false

			local camera = Workspace.CurrentCamera
			local subject = resolveCharacterCameraSubject()

			if
				not runtime.Active
				and camera ~= nil
				and camera.Parent ~= nil
				and camera.CameraType ~= Enum.CameraType.Scriptable
				and getLiveCameraSubject(camera.CameraSubject) == nil
				and subject ~= nil
			then
				camera.CameraSubject = subject
			end

			reconcile("local character added")
		end)
	)
	table.insert(
		controllerConnections,
		player.AncestryChanged:Connect(function(_, parent)
			if parent ~= Players then
				releaseCamera("local player removed")
			end
		end)
	)

	table.insert(
		controllerConnections,
		MountedAimState.Changed:Connect(function()
			aimIntentDirty = true
		end)
	)
	-- Observe occupancy and menu changes for the held view. Camera transforms
	-- stay in the existing Camera+1 owner, never in this heartbeat/input layer.
	table.insert(
		controllerConnections,
		RunService.Heartbeat:Connect(function()
			local mountedCart = resolveMountedCart()
			local requested = MountedAimState.IsRequested()
			local blocked = aimBlocked()
			local watchedCart = mountedCart or LocalCartState.GetCart()
			if
				aimIntentDirty
				or mountedCart ~= lastMountedCart
				or requested ~= lastAimRequested
				or blocked ~= lastAimBlocked
				or observedCart ~= watchedCart
			then
				aimIntentDirty = false
				lastMountedCart, lastAimRequested, lastAimBlocked = mountedCart, requested, blocked
				bindObservedCart(watchedCart)
				reconcile("mounted seat context changed")
			end
		end)
	)
	reconcile("camera controller started")
	log:Debug("Camera controller started")
end

function CartCameraController.Stop()
	if not started then
		return
	end

	started = false
	cartRevision += 1
	disconnectAll(controllerConnections)
	disconnectAll(cartConnections)
	observedCart = nil
	lastMountedCart = nil
	lastAimRequested, lastAimBlocked = false, false
	releaseCamera("camera controller stopped")
	MountedAimState.SetContext(nil)

	if occlusionResolver ~= nil then
		occlusionResolver:Destroy()
		occlusionResolver = nil
	end

	runtime = CartCameraRuntimeState.Create()
	configValid = false
	windowFocused = true
	textInputFocused = false
	systemMenuOpen = false
	characterInvalidated = false
	warnedReadinessRevision = -1
	log:Debug("Camera controller stopped")
end

return CartCameraController
