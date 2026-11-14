--!strict
-- Guard playback on the one villager body (rig + animation brief v5, D.2/D.3). A plain module
-- called from VillagerPresentationController's existing RenderStepped loop: it makes no
-- connections of its own. Client-only and visual: the server's invisible root, the tag
-- distance and every state stay authoritative.
--
-- Used only while CharacterMotion.VillagersEnabled() is on, the animation set is approved and
-- uploaded, and the guard's skin is approved; otherwise the controller keeps the old template.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Shared.Config.VillagerAnimations)
local BodyBuilder = require(ReplicatedStorage.Shared.Utility.VillagerBodyBuilder)
local CharacterMotion = require(ReplicatedStorage.Shared.Config.CharacterMotion)
local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)

local player = Players.LocalPlayer
local Player = {}

-- Hard cap (brief D.3) and the LOD refresh period.
Player.MaxAnimators = 12
Player.LodSeconds = 0.25
Player.ReachDistance = 8

export type BodyView = {
	model: Model,
	root: BasePart,
	head: BasePart,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	under: AnimationTrack?, -- Core-priority Idle underlay
	base: string?, -- the looping or one-shot base track playing now
	reach: boolean,
	type: string,
	seed: number,
	height: number,
	active: boolean, -- LOD: allowed to play tracks
	full: boolean, -- LOD: Chat/Wave allowed (graphics quality)
	velocity: Vector3,
	lastPosition: Vector3?,
	motionKey: string?,
}

local animationObjects: { [string]: Animation } = {}
local skinsByVillager: { [string]: any }? = nil

local PRIORITY: { [string]: Enum.AnimationPriority } = {
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
}

-- True when the body may be used at all (flags, approval, every id uploaded).
function Player.Available(): boolean
	return CharacterMotion.VillagersEnabled() and Animations.approved == true and Animations.Ready()
end

-- The approved skin for a villager id, or nil (then the old template is used).
function Player.SkinFor(villagerId: string): any?
	if not skinsByVillager then
		local map = {}
		local folder = ReplicatedStorage.Shared.Config.VillagerSkins
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") and string.find(module.Name, "_", 1, true) then
				local ok, skin = pcall(require, module)
				if ok and type(skin) == "table" and skin.villagerId and skin.approved == true then
					map[skin.villagerId] = skin
				end
			end
		end
		skinsByVillager = map
	end
	return (skinsByVillager :: any)[villagerId]
end

local function animation(name: string): Animation?
	local existing = animationObjects[name]
	if existing then
		return existing
	end
	local entry = Animations.animations[name]
	if not entry or entry.id == 0 then
		return nil
	end
	local object = Instance.new("Animation")
	object.Name = name
	object.AnimationId = "rbxassetid://" .. tostring(entry.id)
	animationObjects[name] = object
	return object
end

-- The one set is shared by every guard: preload it once.
function Player.Preload()
	local list = {}
	for name in Animations.animations do
		local object = animation(name)
		if object then
			table.insert(list, object)
		end
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
end

function Player.Build(row: any, skin: any, parent: Instance): BodyView
	local model = BodyBuilder.Build(skin, skin.palette)
	model.Name = "VillagerVisual_" .. row.id
	local root = model.PrimaryPart :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local controller = model:FindFirstChildOfClass("AnimationController") :: AnimationController
	local animator = controller:FindFirstChildOfClass("Animator") :: Animator
	model.Parent = parent
	return {
		model = model,
		root = root,
		head = head,
		animator = animator,
		tracks = {},
		under = nil,
		base = nil,
		reach = false,
		type = row.type,
		seed = CharacterMotion.SeedFor(row.id),
		height = BodyBuilder.Height(skin),
		active = true,
		full = true,
		velocity = Vector3.zero,
		lastPosition = nil,
		motionKey = nil,
	}
end

local function track(view: BodyView, name: string): AnimationTrack?
	local existing = view.tracks[name]
	if existing then
		return existing
	end
	local object = animation(name)
	if not object then
		return nil
	end
	local loaded = view.animator:LoadAnimation(object)
	local entry = Animations.animations[name]
	loaded.Looped = entry.loop
	loaded.Priority = PRIORITY[entry.priority] or Enum.AnimationPriority.Core
	view.tracks[name] = loaded
	return loaded
end

-- Server state + motion -> the clip to play (brief C.5).
local TANTRUM = { Sprinter = "TantrumFlail", Plodder = "TantrumStomp", Shouter = "TantrumSquawk" }

function Player.ClipFor(view: BodyView, state: string, motion: string?): string
	if motion == "Run" then
		return if view.type == "Sprinter" then "RunSprint" else "RunTrot"
	elseif motion == "Tantrum" then
		return TANTRUM[view.type] or "TantrumStomp"
	elseif motion == "Walk" then
		return if state == "Return" then "WalkGrumble" else "Walk"
	elseif motion == "Chat" or motion == "Wave" then
		return if view.full then motion else "Idle"
	elseif motion and Animations.animations[motion] then
		return motion
	end
	-- No motion published (server flag off): fall back on the state.
	if state == "Suspicious" then
		return "Curious"
	elseif state == "WindUp" then
		return "Shout"
	elseif state == "Chase" then
		if view.type == "Shouter" then
			return "Alarm"
		end
		return if view.type == "Sprinter" then "RunSprint" else "RunTrot"
	elseif state == "GiveUp" then
		return TANTRUM[view.type] or "TantrumStomp"
	elseif state == "Return" then
		return "WalkGrumble"
	end
	return "Idle"
end

local FAST_FADE: { [string]: boolean } = {
	RunSprint = true,
	RunTrot = true,
	Shout = true,
	Tag = true,
	Alarm = true,
}

local function stopAll(view: BodyView)
	for _, playing in view.tracks do
		if playing.IsPlaying then
			playing:Stop(0.2)
		end
	end
	if view.under and view.under.IsPlaying then
		view.under:Stop(0.2)
	end
	view.base = nil
	view.reach = false
	view.motionKey = nil
end

-- Switch the base clip. One-shots (Shout, Tag, tantrums, Wave) are timed from MotionAt, so the
-- Shout lands exactly on the server's 0.75 s wind-up; loops start at a seeded offset.
local function play(view: BodyView, name: string, motionAt: number?, now: number)
	-- A permanent Idle underlay at Core priority: when a one-shot (Shout, Tag) ends a frame
	-- before the next state replicates, the body breathes instead of snapping to bind pose.
	if not view.under then
		local object = animation("Idle")
		if object then
			local under = view.animator:LoadAnimation(object)
			under.Looped = true
			under.Priority = Enum.AnimationPriority.Core
			view.under = under
		end
	end
	if view.under and not view.under.IsPlaying then
		view.under:Play(0.2)
		view.under.TimePosition = (view.seed * 0.291) % Animations.animations.Idle.length
	end
	local key = name .. ":" .. tostring(motionAt)
	if view.motionKey == key then
		return
	end
	local entry = Animations.animations[name]
	local nextTrack = track(view, name)
	if not nextTrack or not entry then
		return
	end
	local fade = if FAST_FADE[name] then 0.12 else 0.2
	if view.base and view.base ~= name then
		local old = view.tracks[view.base]
		if old then
			old:Stop(fade)
		end
	end
	view.motionKey = key
	if view.base == name and entry.loop and nextTrack.IsPlaying then
		return
	end
	view.base = name
	nextTrack:Play(fade)
	if entry.loop then
		nextTrack.TimePosition = (view.seed * 0.137) % entry.length
	else
		local into = if motionAt then math.clamp(now - motionAt, 0, entry.length) else 0
		nextTrack.TimePosition = into
	end
end

-- Walk and run cycles follow the measured ground speed (no foot sliding).
local function matchSpeed(view: BodyView)
	local name = view.base
	if not name then
		return
	end
	local entry = Animations.animations[name]
	local playing = view.tracks[name]
	if not entry or not playing or not entry.speed then
		return
	end
	local speed = Vector3.new(view.velocity.X, 0, view.velocity.Z).Magnitude
	playing:AdjustSpeed(math.clamp(speed / entry.speed, 0.6, 1.6))
end

-- The chased player's cart (Runtime.Carts.Cart_<userId>), else their character.
local function targetPosition(targetUserId: number): Vector3?
	local runtime = workspace:FindFirstChild("Runtime")
	local carts = runtime and runtime:FindFirstChild("Carts")
	local cart = carts and carts:FindFirstChild("Cart_" .. tostring(targetUserId))
	if cart and cart:IsA("Model") then
		return cart:GetPivot().Position
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local character = target and target.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if rootPart then rootPart.Position else nil
end

-- Reach overlays the run when the chased player's cart is within 8 studs (flat distance).
local function updateReach(view: BodyView, state: string, targetUserId: any, position: Vector3)
	local want = false
	if state == "Chase" and view.type ~= "Shouter" and type(targetUserId) == "number" then
		local cartPosition = targetPosition(targetUserId)
		if cartPosition then
			local gap = Vector3.new(cartPosition.X - position.X, 0, cartPosition.Z - position.Z)
			want = gap.Magnitude <= Player.ReachDistance
		end
	end
	if want == view.reach then
		return
	end
	view.reach = want
	local reach = track(view, "Reach")
	if reach then
		if want then
			reach:Play(0.12)
		else
			reach:Stop(0.2)
		end
	end
end

-- Per frame: place the body on the smoothed pose and keep the right clip playing.
function Player.Update(view: BodyView, pose: CFrame, dt: number, now: number, serverRoot: Model)
	local position = pose.Position
	if view.lastPosition and dt > 0 then
		local raw = (position - view.lastPosition) / dt
		view.velocity = view.velocity:Lerp(raw, 1 - math.exp(-10 * dt))
	end
	view.lastPosition = position
	view.root.CFrame = pose * CFrame.new(0, 0.1, 0)
	if not view.active then
		return
	end
	local state = serverRoot:GetAttribute("State")
	local motion = serverRoot:GetAttribute("Motion")
	local motionAt = serverRoot:GetAttribute("MotionAt")
	local stateText = if type(state) == "string" then state else "Idle"
	local clip = Player.ClipFor(view, stateText, if type(motion) == "string" then motion else nil)
	local startedAt = if type(motionAt) == "number"
		then motionAt
		else serverRoot:GetAttribute("StateAt") :: number?
	play(view, clip, startedAt, now)
	matchSpeed(view)
	updateReach(view, stateText, serverRoot:GetAttribute("TargetUserId"), position)
end

local function qualityLevel(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	-- 0 is Automatic: treat as high.
	return if ok and type(level) == "number" and level > 0 then level else 10
end

-- LOD (brief D.3), every LodSeconds: a guard chasing you always animates; idle guards animate
-- on screen within IdleAnimationDistance; at most MaxAnimators (halved at quality <= 3), idle
-- guards culled first. Culled guards hold their last pose.
function Player.RefreshLod(
	entries: { { view: BodyView, root: Model, position: Vector3 } },
	camera: Camera
)
	local low = qualityLevel() <= 3
	local cap = if low then math.floor(Player.MaxAnimators / 2) else Player.MaxAnimators
	local ranked = {}
	for _, entry in entries do
		local state = entry.root:GetAttribute("State")
		local mine = entry.root:GetAttribute("TargetUserId") == player.UserId
			and state ~= "Idle"
			and state ~= "Return"
		local distance = (entry.position - camera.CFrame.Position).Magnitude
		local _, onScreen = camera:WorldToViewportPoint(entry.position + Vector3.new(0, 2.5, 0))
		local eligible = mine or (onScreen and distance <= Config.IdleAnimationDistance)
		entry.view.full = not low
		table.insert(ranked, {
			view = entry.view,
			mine = mine,
			eligible = eligible,
			score = if mine then -1 elseif state ~= "Idle" then distance * 0.5 else distance,
		})
	end
	table.sort(ranked, function(a, b)
		return a.score < b.score
	end)
	local count = 0
	for _, item in ranked do
		-- A guard chasing you is never culled, even over the cap.
		local allow = item.mine or (item.eligible and count < cap)
		if allow then
			count += 1
		end
		if allow ~= item.view.active then
			item.view.active = allow
			if not allow then
				stopAll(item.view)
			end
		end
	end
end

function Player.Destroy(view: BodyView)
	stopAll(view)
	view.model:Destroy()
end

return Player
