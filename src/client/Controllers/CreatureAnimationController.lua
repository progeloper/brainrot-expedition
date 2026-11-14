--!strict
-- Brainrot playback (rig + animation brief v5, D.1/D.3). A plain module called from
-- CreaturePresentationController's existing RenderStepped loop and LOD refresh: it makes no
-- connections of its own. Client-only and visual: hit proxies, the authoritative pose and every
-- server rule are untouched.
--
-- A view gets an Animator only when CharacterMotion.BrainrotsEnabled() is on, the species is
-- approved with every id uploaded (Config/CreatureAnimations.Ready), and the model is rigged
-- (Motor6D joints; the Voxel V4 templates). Anything else renders exactly as before.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterMotion = require(ReplicatedStorage.Shared.Config.CharacterMotion)
local CreatureAnimations = require(ReplicatedStorage.Shared.Config.CreatureAnimations)

local Anim = {}

-- LOD (brief D.3). Caps are halved at graphics quality <= 3.
Anim.MaxAnimators = 24
Anim.FullDistance = 80
Anim.MovementDistance = 150
Anim.OwnBaseDistance = 100
Anim.OtherBaseDistance = 80
Anim.OtherBaseCap = 12
Anim.LowQualityActionDistance = 40
-- Smoothing for wild rows (replaces the linear lerp while the flag is on).
Anim.SpringOmega = 10
Anim.TurnRateDegrees = 360

local PRIORITY: { [string]: Enum.AnimationPriority } = {
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
}

export type State = {
	animator: Animator,
	species: string,
	set: any,
	tracks: { [string]: AnimationTrack },
	loop: string?,
	oneShot: string?,
	oneShotKey: string?,
	seed: number,
	tier: string, -- "Full" | "Movement" | "Off"
	noAction: boolean,
	lastDamageAt: any,
	idleKey: string?,
	celebrate: boolean,
}

local animationObjects: { [number]: Animation } = {}

local function animationFor(id: number): Animation
	local existing = animationObjects[id]
	if existing then
		return existing
	end
	local object = Instance.new("Animation")
	object.AnimationId = "rbxassetid://" .. tostring(id)
	animationObjects[id] = object
	return object
end

function Anim.Available(): boolean
	return CharacterMotion.BrainrotsEnabled()
end

local function rigged(model: Model): boolean
	for _, node in model:GetDescendants() do
		if node:IsA("Motor6D") then
			return true
		end
	end
	return false
end

-- Called at the end of createView. Sets entry.anim when the view can be animated.
function Anim.Attach(entry: any)
	entry.anim = nil
	local model: Model? = entry.model
	local row = entry.row
	if not model or not row or not Anim.Available() then
		return
	end
	if not CreatureAnimations.Ready(row.speciesId) or not rigged(model) then
		return
	end
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = model
	end
	local animator = (controller :: AnimationController):FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local seed = row.attributes and row.attributes.MotionSeed
	entry.anim = {
		animator = animator :: Animator,
		species = row.speciesId,
		set = CreatureAnimations.Species[row.speciesId].animations,
		tracks = {},
		loop = nil,
		oneShot = nil,
		oneShotKey = nil,
		seed = if type(seed) == "number" then seed else CharacterMotion.SeedFor(row.id),
		tier = "Full",
		noAction = false,
		lastDamageAt = row.attributes and row.attributes.Phase13LastDamageAt,
		idleKey = nil,
		celebrate = entry.celebratePending == true,
	} :: State
	entry.celebratePending = nil
	-- The smoothed pose starts where the view was placed.
	entry.smoothPosition = model:GetPivot().Position
	entry.smoothVelocity = Vector3.zero
end

function Anim.Detach(entry: any)
	entry.anim = nil
end

local function track(state: State, name: string): AnimationTrack?
	local existing = state.tracks[name]
	if existing then
		return existing
	end
	local entry = state.set[name]
	if not entry or entry.id == 0 then
		return nil
	end
	local loaded = state.animator:LoadAnimation(animationFor(entry.id))
	loaded.Looped = entry.loop == true
	loaded.Priority = PRIORITY[entry.priority] or Enum.AnimationPriority.Core
	state.tracks[name] = loaded
	return loaded
end

local function stopAll(state: State)
	for _, playing in state.tracks do
		if playing.IsPlaying then
			playing:Stop(0.2)
		end
	end
	state.loop, state.oneShot, state.oneShotKey = nil, nil, nil
end

local FAST: { [string]: boolean } = { Run = true, Alert = true, Hit = true }

-- The looping base layer: crossfade 0.2 s (0.12 s into Run), desynced by seed.
local function playLoop(state: State, name: string)
	if state.loop == name then
		return
	end
	local fade = if FAST[name] then 0.12 else 0.2
	if state.loop then
		local old = state.tracks[state.loop]
		if old then
			old:Stop(fade)
		end
	end
	local nextTrack = track(state, name)
	state.loop = name
	if nextTrack then
		nextTrack:Play(fade)
		local length = state.set[name].length
		nextTrack.TimePosition = (state.seed * 0.137) % math.max(length, 0.01)
	end
end

-- One-shots on top (Action): timed from when they began so every client agrees.
local function playOneShot(state: State, name: string, key: string, startedAt: number?, now: number)
	if state.oneShotKey == key or (state.noAction and name ~= "Celebrate") then
		return
	end
	local entry = state.set[name]
	local nextTrack = track(state, name)
	if not entry or not nextTrack then
		return
	end
	local into = if startedAt then now - startedAt else 0
	if into > entry.length then
		state.oneShotKey = key -- already over: never replay a stale one-shot
		return
	end
	if state.oneShot and state.oneShot ~= name then
		local old = state.tracks[state.oneShot]
		if old then
			old:Stop(0.12)
		end
	end
	state.oneShot, state.oneShotKey = name, key
	nextTrack.Priority = Enum.AnimationPriority.Action
	nextTrack:Play(if FAST[name] then 0.08 else 0.12)
	nextTrack.TimePosition = math.max(into, 0)
end

local function matchSpeed(state: State, speed: number)
	local name = state.loop
	local entry = name and state.set[name]
	local playing = name and state.tracks[name]
	if entry and playing and entry.speed then
		playing:AdjustSpeed(math.clamp(speed / entry.speed, 0.6, 1.6))
	end
end

-- Per frame: pick the clips for this row (brief D.1 state -> track).
function Anim.Update(entry: any, now: number)
	local state: State? = entry.anim
	if not state or state.tier == "Off" then
		return
	end
	local row = entry.row
	local attributes = row.attributes or {}
	local motion = attributes.Motion
	local motionAt = attributes.MotionAt
	local speed = entry.groundSpeed or 0

	-- Base loop.
	local loop: string
	if row.state == "Deposited" then
		loop = "IdleDisplay"
	elseif row.state == "Carried" or row.state == "Cart" then
		loop = "Carried"
	elseif row.state == "Sleeping" then
		loop = "Sleep"
	elseif motion == "Walk" or motion == "Run" then
		loop = motion
	elseif motion == nil then
		loop = if speed > CharacterMotion.Brainrot.MovingSpeed then "Walk" else "IdleWild"
	else
		loop = "IdleWild" -- Idle, Alert and Signature stand on the idle loop
	end
	if state.tier == "Movement" and state.set[loop] and state.set[loop].priority ~= "Movement" then
		-- 80-150 studs: Movement tracks only; idle poses rest.
		if state.loop then
			local old = state.tracks[state.loop]
			if old then
				old:Stop(0.2)
			end
			state.loop = nil
		end
	else
		playLoop(state, loop)
		matchSpeed(state, speed)
	end
	if state.tier ~= "Full" then
		return
	end

	-- One-shots.
	if state.celebrate then
		state.celebrate = false
		playOneShot(state, "Celebrate", "Celebrate:" .. tostring(now), nil, now)
	end
	local damageAt = attributes.Phase13LastDamageAt
	if damageAt ~= state.lastDamageAt then
		state.lastDamageAt = damageAt
		if damageAt ~= nil and (row.state == "Awake" or row.state == "Sleeping") then
			playOneShot(state, "Hit", "Hit:" .. tostring(damageAt), nil, now)
		end
	end
	if row.state == "Awake" and type(motionAt) == "number" then
		if motion == "Alert" or motion == "Signature" then
			playOneShot(state, motion, motion .. ":" .. tostring(motionAt), motionAt, now)
		elseif motion == "Idle" then
			-- Every third pause (seeded) shows the second idle instead of standing still.
			local key = "Idle:" .. tostring(motionAt)
			if state.idleKey ~= key then
				state.idleKey = key
				if (state.seed + math.floor(motionAt)) % 3 == 0 then
					playOneShot(
						state,
						"IdleWild2",
						"IdleWild2:" .. tostring(motionAt),
						motionAt,
						now
					)
				end
			end
		end
	end
end

-- Wild rows: critically damped position and a turn rate of at most 360 deg/s, instead of the
-- linear lerp between 10 Hz poses. Returns true when it placed the model.
function Anim.Smooth(entry: any, dt: number): boolean
	local model: Model? = entry.model
	if not model or not Anim.Available() then
		return false
	end
	local state = entry.row.state
	if state ~= "Awake" and state ~= "Sleeping" then
		return false
	end
	local target: CFrame = entry.target
	-- Ground speed for cycle matching comes from the replicated poses themselves (the spring's
	-- velocity spikes on every packet): low-passed, and it decays when updates stop.
	local clock = os.clock()
	if entry.speedTarget ~= target then
		local previous: CFrame? = entry.speedTarget
		local previousAt: number? = entry.speedTargetAt
		if previous and previousAt then
			local gap = math.max(clock - previousAt, 0.05)
			local delta = target.Position - previous.Position
			local instant = Vector3.new(delta.X, 0, delta.Z).Magnitude / gap
			if instant < 40 then -- ignore teleports
				entry.groundSpeed = (entry.groundSpeed or instant) * 0.5 + instant * 0.5
			end
		end
		entry.speedTarget, entry.speedTargetAt = target, clock
	elseif entry.speedTargetAt and clock - entry.speedTargetAt > 0.4 then
		entry.groundSpeed = 0
	end
	local position: Vector3 = entry.smoothPosition or target.Position
	local velocity: Vector3 = entry.smoothVelocity or Vector3.zero
	local omega = Anim.SpringOmega
	local step = math.min(dt, 0.1)
	velocity += ((target.Position - position) * omega * omega - velocity * 2 * omega) * step
	position += velocity * step
	-- Snap after a teleport (route jump, respawn).
	if (target.Position - position).Magnitude > 20 then
		position, velocity = target.Position, Vector3.zero
	end
	entry.smoothPosition, entry.smoothVelocity = position, velocity
	local current = model:GetPivot()
	local look = current.LookVector
	local want = target.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatWant = Vector3.new(want.X, 0, want.Z)
	local rotation = target.Rotation
	if flatLook.Magnitude > 1e-3 and flatWant.Magnitude > 1e-3 then
		local angle =
			math.atan2(flatLook.Unit:Cross(flatWant.Unit).Y, flatLook.Unit:Dot(flatWant.Unit))
		local maxTurn = math.rad(Anim.TurnRateDegrees) * step
		if math.abs(angle) > maxTurn then
			rotation = CFrame.Angles(0, math.sign(angle) * maxTurn, 0) * current.Rotation
		end
	end
	model:PivotTo(CFrame.new(position) * rotation)
	return true
end

local function qualityLevel(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" and level > 0 then level else 10
end

-- LOD refresh (every 0.25 s, from the existing refresh): decide each animated view's tier.
function Anim.RefreshLod(entries: { [any]: any }, camera: Camera?)
	if not camera or not Anim.Available() then
		return
	end
	local low = qualityLevel() <= 3
	local cap = if low then Anim.MaxAnimators // 2 else Anim.MaxAnimators
	local otherCap = if low then Anim.OtherBaseCap // 2 else Anim.OtherBaseCap
	local me = Players.LocalPlayer and Players.LocalPlayer.UserId
	local eye = camera.CFrame.Position
	local candidates = {}
	for _, entry in entries do
		local state: State? = entry.anim
		if state and entry.model then
			local row = entry.row
			local position = entry.model:GetPivot().Position
			local distance = (position - eye).Magnitude
			local _, onScreen = camera:WorldToViewportPoint(position)
			local attributes = row.attributes or {}
			local mine = attributes.OwnerUserId == me
				or attributes.Phase10OwnerUserId == me
				or attributes.CarrierUserId == me
			local tier, rank = "Off", math.huge
			if row.state == "Deposited" then
				if mine and distance <= Anim.OwnBaseDistance then
					tier, rank = "Full", distance
				elseif not mine and distance <= Anim.OtherBaseDistance then
					tier, rank = "OtherBase", distance + 1000
				end
			elseif (row.state == "Carried" or row.state == "Cart") and mine then
				tier, rank = "Full", -1 -- your own catch always animates
			elseif onScreen and distance <= Anim.FullDistance then
				tier, rank = "Full", distance
			elseif onScreen and distance <= Anim.MovementDistance then
				tier, rank = "Movement", distance + 500
			end
			table.insert(
				candidates,
				{ entry = entry, tier = tier, rank = rank, distance = distance }
			)
		end
	end
	table.sort(candidates, function(a, b)
		return a.rank < b.rank
	end)
	local count, others = 0, 0
	for _, candidate in candidates do
		local tier = candidate.tier
		if tier == "OtherBase" then
			others += 1
			tier = if others <= otherCap then "Full" else "Off"
		end
		if tier ~= "Off" then
			if count >= cap then
				tier = "Off"
			else
				count += 1
			end
		end
		local state: State = candidate.entry.anim
		state.noAction = low and candidate.distance > Anim.LowQualityActionDistance
		if tier ~= state.tier then
			state.tier = tier
			if tier == "Off" then
				stopAll(state)
			end
		end
	end
end

-- Diagnostics for QA (Studio Play checks).
function Anim.Count(entries: { [any]: any }): (number, number)
	local animated, playing = 0, 0
	for _, entry in entries do
		local state: State? = entry.anim
		if state then
			animated += 1
			if state.tier ~= "Off" then
				playing += 1
			end
		end
	end
	return animated, playing
end

return Anim
