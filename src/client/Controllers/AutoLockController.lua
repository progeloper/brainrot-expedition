--!strict
-- Drive-and-Hunt auto-lock (Part C). The game picks the target; the player presses FIRE.
-- Client presentation and intent only: it scans wild awake brainrots at 10 Hz, asks the pure
-- HuntTargetSelector for the lock, shows one reticle, and hands SleepLauncherController a
-- camera ray through the lock. The server validates every shot exactly as before
-- (BrainrotSleepSystem ASSIST_LOCK: identity, range from the muzzle, line of sight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.DriveAndHunt).Lock
-- Core Loop V2 (B5): add a star term (Star 1.0, others 0.85, weight 1.0); every other term unchanged.
local selectorConfig: any = nil
if require(Shared.Config.CoreLoopFlags).Part("Stars") then
	selectorConfig = table.clone(Config)
	local weights = table.clone(Config.Weights)
	weights.star = 1.0
	selectorConfig.Weights = table.freeze(weights)
	table.freeze(selectorConfig)
end
local Flags = require(Shared.Config.DriveAndHuntFlags)
local BrainrotCatalog = require(Shared.Config.BrainrotCatalog)
local Rarities = require(Shared.Config.Rarities)
local Palette = require(Shared.Config.VoxelCreaturePalette)
local Weapons = require(Shared.Config.Weapons)
local WeaponStats = require(Shared.Utility.WeaponStats)
local Selector = require(Shared.Utility.HuntTargetSelector)

local LocalCartState = require(script.Parent.Parent.State.LocalCartState)
local InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)

local player = Players.LocalPlayer

export type Lock = { Model: Model, Id: string, Point: Vector3 }

type Entry = {
	candidate: Selector.Candidate,
	model: Model?,
	body: BasePart?,
}

local Controller = {}
local started = false
local enabled = false
local connections: { RBXScriptConnection } = {}
local changed = Instance.new("BindableEvent")
Controller.Changed = changed.Event

local state = Selector.NewState()
local context: Selector.Context = { range = 0, mounted = false, fireHeld = false, now = 0 }
local pool: { Entry } = {}
local active: { Selector.Candidate } = {}
local entryById: { [string]: Entry } = {}
local hitUntil: { [string]: number } = {}
local lockModel: Model? = nil
local lockBody: BasePart? = nil
local lockId: string? = nil
local elapsed = 0
local scanCount = 0
local lastScanCandidates = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
rayParams.RespectCanCollide = false

-- Optional collaborators, resolved lazily so a missing module never breaks firing.
local nametags: any = nil
local visibility: any = nil
local presentation: any = nil
local aimModule: any = nil
local function collaborator(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, value = pcall(require, module)
		if ok then
			return value
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Reticle (exactly one pooled BillboardGui)
--------------------------------------------------------------------------------

local reticle: BillboardGui? = nil
local reticleScale: UIScale? = nil
local reticleStrokes: { UIStroke } = {}
local reticleDot: Frame? = nil
local bounce: Tween? = nil

-- Aim line (stands in for a turret) and muzzle flash: one pooled part, two attachments, one Beam.
local aimPart: Part? = nil
local aimFrom: Attachment? = nil
local aimTo: Attachment? = nil
local aimBeam: Beam? = nil
local flashPart: Part? = nil
local shotCount = 0

local function buildAimLine()
	local part = Instance.new("Part")
	part.Name = "DriveAndHuntAimLine"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.identity
	local from, to = Instance.new("Attachment"), Instance.new("Attachment")
	from.Parent, to.Parent = part, part
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.Width0, beam.Width1 = Config.AimLineWidth, Config.AimLineWidth
	beam.Transparency = NumberSequence.new(Config.AimLineTransparency)
	beam.FaceCamera = true
	beam.LightEmission, beam.LightInfluence = 1, 0
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = part
	part.Parent = Workspace
	aimPart, aimFrom, aimTo, aimBeam = part, from, to, beam
end

local function buildReticle()
	local gui = Instance.new("BillboardGui")
	gui.Name = "DriveAndHuntLock"
	gui.Size = UDim2.fromOffset(84, 84)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Active = false
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.78, 0.78)
	ring.BackgroundTransparency = 1
	ring.Rotation = 45
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.28, 0)
	corner.Parent = ring
	local outline = Instance.new("UIStroke")
	outline.Thickness = 9
	outline.Color = Color3.fromRGB(29, 33, 51)
	outline.Parent = ring
	local inner = Instance.new("Frame")
	inner.Name = "Colour"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.Parent = ring
	local innerCorner = corner:Clone()
	innerCorner.Parent = inner
	local colour = Instance.new("UIStroke")
	colour.Thickness = 5
	colour.Parent = inner
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.16, 0.16)
	dot.BorderSizePixel = 0
	dot.Parent = gui
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Thickness = 3
	dotStroke.Color = Color3.fromRGB(29, 33, 51)
	dotStroke.Parent = dot
	local scale = Instance.new("UIScale")
	scale.Parent = ring
	gui.Parent = player:WaitForChild("PlayerGui")
	reticle, reticleScale, reticleDot = gui, scale, dot
	reticleStrokes = { colour }
end

local function lockColour(model: Model): Color3
	local mutation = model:GetAttribute("MutationId")
	local hex = if type(mutation) == "string" then (Palette.MutationTag :: any)[mutation] else nil
	if not hex then
		local rarity = BrainrotCatalog.GetRarity(model:GetAttribute("BrainrotId"))
		local tier = if rarity then (Palette.RarityTiers :: any)[rarity] else nil
		hex = if tier then (tier.glow or tier.primary) else nil
	end
	local ok, colour = pcall(Color3.fromHex, if type(hex) == "string" then hex else "#FFFFFF")
	return if ok then colour else Color3.new(1, 1, 1)
end

local function showReticle(model: Model?, body: BasePart?, snapped: boolean)
	local gui, scale, dot = reticle, reticleScale, reticleDot
	if not gui or not scale or not dot then
		return
	end
	if not model or not body then
		gui.Enabled, gui.Adornee = false, nil
		return
	end
	local colour = lockColour(model)
	if aimBeam then
		aimBeam.Color = ColorSequence.new(colour)
	end
	for _, stroke in reticleStrokes do
		stroke.Color = colour
	end
	dot.BackgroundColor3 = colour
	gui.Adornee = body
	gui.Enabled = true
	if snapped then
		if bounce then
			bounce:Cancel()
		end
		scale.Scale = 1.7
		local snap = TweenService:Create(
			scale,
			TweenInfo.new(Config.SnapSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		snap.Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and gui.Enabled then
				local loop = TweenService:Create(
					scale,
					TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.14 }
				)
				bounce = loop
				loop:Play()
			end
		end)
		snap:Play()
	end
end

--------------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------------

local function weaponRange(): number
	local profile =
		WeaponStats.Resolve(player:GetAttribute("SelectedWeaponId") or Weapons.StarterWeaponId)
	return if WeaponStats.IsReady(profile) then profile.rangeStuds else 0
end

local function mountedCart(): Model?
	local cart = LocalCartState.GetCart()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not cart or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local seat = cart:FindFirstChild("DriverSeat")
	return if seat
			and humanoid.SeatPart == seat
			and LocalCartState.IsAuthorizedDriver()
		then cart
		else nil
end

-- Where the shot leaves from, the heading used for "facing", and whether the player is mounted.
local function firingFrame(): (Vector3?, Vector3?, boolean, Model?)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera or not character or player:GetAttribute("CarriedItemId") ~= nil then
		return nil, nil, false, nil
	end
	local cart = mountedCart()
	if cart then
		local muzzle = cart:FindFirstChild("HarpoonOrigin", true)
		local origin = if muzzle and muzzle:IsA("Attachment")
			then muzzle.WorldPosition
			elseif muzzle and muzzle:IsA("BasePart") then muzzle.Position
			else nil
		return origin, cart:GetPivot().LookVector, true, cart
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return nil, nil, false, nil
	end
	-- On foot the server only accepts a shot from the held launcher's muzzle.
	local tool = if aimModule and type(aimModule.GetHeldLauncher) == "function"
		then aimModule.GetHeldLauncher(character)
		else nil
	local muzzle = if tool then tool:FindFirstChild("Muzzle", true) else nil
	if not muzzle or not muzzle:IsA("Attachment") then
		return nil, nil, false, nil
	end
	return muzzle.WorldPosition, camera.CFrame.LookVector, false, nil
end

-- The cart muzzle while the local player is driving, else nil.
local function mountedMuzzle(): Vector3?
	local cart = mountedCart()
	local muzzle = if cart then cart:FindFirstChild("HarpoonOrigin", true) else nil
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	elseif muzzle and muzzle:IsA("BasePart") then
		return muzzle.Position
	end
	return nil
end

-- Every frame while locked and driving: two attachment moves, nothing allocated.
local function updateAimLine()
	local beam, from, to = aimBeam, aimFrom, aimTo
	if not beam or not from or not to then
		return
	end
	local body = lockBody
	local muzzle = if body and body.Parent then mountedMuzzle() else nil
	if not body or not muzzle then
		if beam.Enabled then
			beam.Enabled = false
		end
		return
	end
	from.WorldPosition, to.WorldPosition = muzzle, body.Position
	if not beam.Enabled then
		beam.Enabled = true
	end
end

local function flatAngle(heading: Vector3, offset: Vector3): number
	local a = Vector3.new(heading.X, 0, heading.Z)
	local b = Vector3.new(offset.X, 0, offset.Z)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return 0
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

local function entryAt(index: number): Entry
	local entry = pool[index]
	if not entry then
		entry = {
			candidate = {
				id = "",
				distance = 0,
				facingAngle = 0,
				alreadyHit = false,
				rarityRank = 1,
				lineOfSight = false,
				screen = nil,
				pointerAngle = nil,
			},
			model = nil,
			body = nil,
		}
		pool[index] = entry
	end
	return entry
end

local function clearLock()
	if lockModel ~= nil then
		lockModel, lockBody, lockId = nil, nil, nil
		Selector.Clear(state)
		showReticle(nil, nil, false)
		changed:Fire()
	end
end

local function scan()
	scanCount += 1
	local origin, heading, mounted, cart = firingFrame()
	local camera = Workspace.CurrentCamera
	local range = weaponRange()
	local runtime = Workspace:FindFirstChild("Runtime")
	local brainrots = if runtime then runtime:FindFirstChild("Brainrots") else nil
	if not origin or not heading or not camera or not brainrots or range <= 0 then
		lastScanCandidates = 0
		clearLock()
		return
	end
	local now = os.clock()
	local cameraPosition = camera.CFrame.Position
	local usePointer = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
		and UserInputService.MouseBehavior == Enum.MouseBehavior.Default
	local pointerDirection: Vector3? = nil
	if usePointer then
		local mouse = UserInputService:GetMouseLocation()
		pointerDirection = camera:ViewportPointToRay(mouse.X, mouse.Y).Direction
	end

	-- Pass 1: the nearest MaxCandidates awake, visible, in-range brainrots (no raycasts yet).
	table.clear(active)
	table.clear(entryById)
	local count = 0
	local farthestIndex, farthestDistance = 0, -1
	for _, model in brainrots:GetChildren() do
		if not model:IsA("Model") or model:GetAttribute("Captured") ~= false then
			continue -- sleeping ones are for the scoop, never a lock
		end
		local id = model:GetAttribute("ItemId")
		local body = model:FindFirstChild("Body", true)
		if type(id) ~= "string" or not body or not body:IsA("BasePart") or not body.CanQuery then
			continue
		end
		local distance = (body.Position - origin).Magnitude
		if distance > range or distance < 0.5 then
			continue
		end
		if
			visibility
			and type(visibility.IsVisible) == "function"
			and not visibility.IsVisible(model)
		then
			continue
		end
		if
			nametags
			and type(nametags.isAimAssistEligible) == "function"
			and not nametags.isAimAssistEligible(model)
		then
			continue -- camouflaged: the server refuses the lock too
		end
		local index: number
		if count < Config.MaxCandidates then
			count += 1
			index = count
		elseif distance < farthestDistance then
			index = farthestIndex
		else
			continue
		end
		local entry = entryAt(index)
		entry.model, entry.body = model, body
		entry.candidate.id, entry.candidate.distance = id, distance
		farthestIndex, farthestDistance = 0, -1
		for slot = 1, count do
			local slotDistance = pool[slot].candidate.distance
			if slotDistance > farthestDistance then
				farthestIndex, farthestDistance = slot, slotDistance
			end
		end
	end
	lastScanCandidates = count

	-- Pass 2: line of sight and scoring inputs for those few.
	local exclusions: { Instance } = {}
	if player.Character then
		table.insert(exclusions, player.Character)
	end
	local ownCart = cart or LocalCartState.GetCart()
	if ownCart then
		table.insert(exclusions, ownCart)
	end
	local effects = Workspace:FindFirstChild("SleepBoltEffects")
	if effects then
		table.insert(exclusions, effects)
	end
	rayParams.FilterDescendantsInstances = exclusions
	for index = 1, count do
		local entry = pool[index]
		local model, body = entry.model :: Model, entry.body :: BasePart
		local candidate = entry.candidate
		local point = body.Position
		local fromMuzzle = point - origin
		local fromCamera = point - cameraPosition
		candidate.facingAngle = flatAngle(heading, fromMuzzle)
		local expiry = hitUntil[candidate.id]
		candidate.alreadyHit = expiry ~= nil and expiry > now
		local rarity = BrainrotCatalog.GetRarity(model:GetAttribute("BrainrotId"))
		candidate.rarityRank = (if rarity then Rarities.GetDisplayRank(rarity) else nil) or 1
		candidate.star = model:GetAttribute("CoreLoopStar") == true
		local sight = fromCamera.Magnitude > 0.01
			and fromMuzzle.Unit:Dot(fromCamera.Unit) >= Config.MinimumParallaxDot
		if sight then
			local hit = Workspace:Raycast(
				origin,
				fromMuzzle.Unit * (fromMuzzle.Magnitude + 0.01),
				rayParams
			)
			if
				hit
				and not hit.Instance:IsDescendantOf(model)
				and not (
					presentation
					and type(presentation.ResolveAuthority) == "function"
					and presentation.ResolveAuthority(hit.Instance) == model
				)
			then
				sight = false
			end
		end
		candidate.lineOfSight = sight
		local screen, onScreen = camera:WorldToViewportPoint(point)
		candidate.screen = if onScreen then Vector2.new(screen.X, screen.Y) else nil
		candidate.pointerAngle = if pointerDirection
			then math.acos(math.clamp(pointerDirection.Unit:Dot(fromCamera.Unit), -1, 1))
			else nil
		active[index] = candidate
		entryById[candidate.id] = entry
	end

	context.range, context.mounted, context.now = range, mounted, now
	if usePointer and state.manualId == nil then
		local pointed = Selector.PickByPointer(active, Config.PointerConeDegrees)
		if pointed then
			state.manualId = pointed.id
		end
	end
	local chosen = Selector.Select(active, state, context, (selectorConfig or Config) :: any)
	local entry = if chosen then entryById[chosen.id] else nil
	local nextModel = if entry then entry.model else nil
	if nextModel ~= lockModel then
		lockModel, lockBody, lockId =
			nextModel, if entry then entry.body else nil, if chosen then chosen.id else nil
		showReticle(lockModel, lockBody, true)
		changed:Fire()
	end
	for id, expiry in hitUntil do
		if expiry <= now then
			hitUntil[id] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Tap to switch (touch). A drag still turns the camera and never switches.
--------------------------------------------------------------------------------

local taps: { [InputObject]: { at: number, position: Vector2 } } = {}

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	taps[input] = { at = os.clock(), position = Vector2.new(input.Position.X, input.Position.Y) }
end

local function onInputEnded(input: InputObject)
	local tap = taps[input]
	taps[input] = nil
	if not tap or not enabled then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if
		os.clock() - tap.at > Config.TapMaxSeconds
		or (position - tap.position).Magnitude > Config.TapMaxDragPixels
		or InputPolicy.IsPointerInteraction(player, position)
	then
		return
	end
	local picked = Selector.PickByScreen(active, position, Config.TapRadiusPixels)
	if picked then
		state.manualId = picked.id
		scan()
	end
end

--------------------------------------------------------------------------------
-- API used by SleepLauncherController and DriveAndHuntController
--------------------------------------------------------------------------------

function Controller.IsEnabled(): boolean
	return enabled
end

-- The current lock, re-read at call time so a stale 10 Hz sample never names a target that
-- has since fallen asleep or left.
function Controller.GetLock(): Lock?
	local model, body, id = lockModel, lockBody, lockId
	if
		not enabled
		or not model
		or not body
		or not id
		or model.Parent == nil
		or body.Parent == nil
		or model:GetAttribute("Captured") ~= false
	then
		return nil
	end
	return { Model = model, Id = id, Point = body.Position }
end

function Controller.HasLock(): boolean
	return Controller.GetLock() ~= nil
end

function Controller.GetLockModel(): Model?
	local lock = Controller.GetLock()
	return if lock then lock.Model else nil
end

-- A fire-time snapshot in the shape ThirdPersonAimController:GetShotSnapshot returns: the
-- REAL camera origin and the unit direction through the lock's aim point.
function Controller.GetShotSnapshot(): any?
	local lock = Controller.GetLock()
	local camera = Workspace.CurrentCamera
	if not lock or not camera then
		return nil
	end
	local origin = camera.CFrame.Position
	local offset = lock.Point - origin
	if offset.Magnitude < 0.01 then
		return nil
	end
	local ray = Ray.new(origin, offset.Unit)
	return table.freeze({
		Mode = "ASSIST_LOCK",
		TargetId = lock.Id,
		TargetKind = "Brainrot",
		CrosshairRay = ray,
		ShotRay = ray,
	})
end

function Controller.NoteShot()
	local now = os.clock()
	shotCount += 1
	local muzzle = mountedMuzzle()
	if muzzle then
		local flash = flashPart
		if not flash then
			flash = Instance.new("Part")
			flash.Name = "DriveAndHuntMuzzleFlash"
			flash.Shape = Enum.PartType.Ball
			flash.Material = Enum.Material.Neon
			flash.Color = Color3.fromRGB(255, 244, 190)
			flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch =
				true, false, false, false
			flash.CastShadow = false
			flash.Size = Vector3.one * Config.MuzzleFlashSize
			flashPart = flash
		end
		flash.Position = muzzle
		flash.Parent = Workspace
		local serial = shotCount
		task.delay(Config.MuzzleFlashSeconds, function()
			if serial == shotCount then
				flash.Parent = nil
			end
		end)
	end
	Selector.NoteShot(state, now)
	if lockId then
		hitUntil[lockId] = now + Config.HitMemorySeconds
	end
end

function Controller.SetFireHeld(held: boolean)
	context.fireHeld = held
end

function Controller.GetDiagnostics(): any
	return {
		Enabled = enabled,
		Scans = scanCount,
		Candidates = lastScanCandidates,
		LockId = lockId,
		PoolSize = #pool,
		Reticles = if reticle then 1 else 0,
	}
end

-- Test hook: forces the next sample to prefer a target (same path as a tap).
function Controller.RequestTarget(id: string)
	state.manualId = id
	scan()
end

function Controller.Start()
	if started then
		return
	end
	started = true
	if not Flags.Part("AutoLock") then
		return
	end
	enabled = true
	nametags = collaborator("BrainrotNametagController")
	visibility = collaborator("RegionVisibilityController")
	presentation = collaborator("CreaturePresentationController")
	aimModule = collaborator("ThirdPersonAimController")
	buildReticle()
	buildAimLine()
	table.insert(connections, RunService.RenderStepped:Connect(updateAimLine))
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= 1 / Config.ScanHz then
				elapsed = 0
				scan()
			end
		end)
	)
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	enabled = false
	clearLock()
	if aimPart then
		aimPart:Destroy()
		aimPart, aimFrom, aimTo, aimBeam = nil, nil, nil, nil
	end
	if flashPart then
		flashPart:Destroy()
		flashPart = nil
	end
end

return Controller
