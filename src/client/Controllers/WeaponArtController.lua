--!strict
-- Camp Rework, Part A: client feedback for the v2 weapon art (presentation only).
--   * SPINS/MOVES rotors (tag CampAnimRotor) animate on the shared ≤10 Hz scheduler while the tool is
--     equipped and on screen, and stop (culled) when unequipped or far away.
--   * Each shot: Prism Repeater's drum snaps one slot (60°, 0.08 s Back) with a click; petal/piston
--     FirePump groups kick; EmitOnFire emitters burst. No ammo, no counts: feedback only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Scheduler = require(script.Parent.Parent.Utility.CampAnimationScheduler)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local PlaytestFlags = require(ReplicatedStorage.Shared.Config.PlaytestFixesFlags)
local PresentationQuality = require(ReplicatedStorage.Shared.Utility.ResolvedPresentationQuality)
local IDLE_TAG = "PlaytestIdleFx"

local Controller = {}
local TICK = 1 / Scheduler.Hz
local DRUM_STEP_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KICK_TWEEN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)

type Rig = {
	rotor: BasePart,
	motor: Weld,
	base: CFrame,
	kind: string,
	rate: number,
	distance: number,
	step: number,
	phase: number,
	angle: number,
	tween: Tween?,
}

local rigs: { [BasePart]: Rig } = {}
local started = false

local function play(rig: Rig, target: CFrame, info: TweenInfo)
	if rig.tween then
		rig.tween:Cancel()
	end
	local tween = TweenService:Create(rig.motor, info, { C0 = target })
	rig.tween = tween
	tween:Play()
end

local function equipped(rotor: BasePart): boolean
	local tool = rotor:FindFirstAncestorOfClass("Tool")
	return tool ~= nil
		and tool.Parent ~= nil
		and tool.Parent:FindFirstChildOfClass("Humanoid") ~= nil
		and rotor:IsDescendantOf(Workspace)
end

-- Pure: the motor offset for a continuous rig at time `now` (tests use this).
function Controller.ContinuousOffset(
	kind: string,
	rate: number,
	distance: number,
	phase: number,
	angle: number,
	now: number
): (CFrame, number)
	if kind == "Spin" then
		return CFrame.Angles(0, 0, math.rad(angle)), angle
	elseif kind == "Pump" then
		local wave = 0.5 + 0.5 * math.sin((now * rate + phase) * math.pi * 2)
		return CFrame.new(0, 0, -distance * wave), angle
	end
	return CFrame.new(), angle
end

-- Pure: Prism Repeater drum. Each fire event advances exactly one 60° slot.
function Controller.NextDrumAngle(angle: number, step: number?): number
	return (angle + (step or 60)) % 360
end

local function bind(rotor: Instance)
	if not rotor:IsA("BasePart") or rigs[rotor] then
		return
	end
	local motor = rotor:FindFirstChild("ArtMotor")
	if not motor or not motor:IsA("Weld") then
		return
	end
	local rig: Rig = {
		rotor = rotor,
		motor = motor,
		base = motor.C0,
		kind = tostring(rotor:GetAttribute("CampAnim") or "Spin"),
		rate = tonumber(rotor:GetAttribute("CampAnimRate")) or 0,
		distance = tonumber(rotor:GetAttribute("CampAnimDistance")) or 0,
		step = tonumber(rotor:GetAttribute("CampAnimStep")) or 60,
		phase = tonumber(rotor:GetAttribute("CampAnimPhase")) or 0,
		angle = 0,
		tween = nil,
	}
	rigs[rotor] = rig
	if rig.kind == "Spin" or rig.kind == "Pump" then
		Scheduler.Register(rotor, {
			position = function()
				return if equipped(rotor) then rotor.Position else nil
			end,
			step = function(now, dt)
				if rig.kind == "Spin" then
					rig.angle = (rig.angle + rig.rate * math.min(dt, 0.25)) % 360
				end
				local offset = Controller.ContinuousOffset(
					rig.kind,
					rig.rate,
					rig.distance,
					rig.phase,
					rig.angle,
					now + TICK
				)
				play(rig, rig.base * offset, TweenInfo.new(TICK, Enum.EasingStyle.Linear))
			end,
		})
	end
end

local function unbind(rotor: Instance)
	local rig = rigs[rotor :: BasePart]
	if rig then
		if rig.tween then
			rig.tween:Cancel()
		end
		rigs[rotor :: BasePart] = nil
	end
	Scheduler.Unregister(rotor)
end

local function clickSound()
	if not (FeatureFlags :: any).GameAudioEnabled then
		return
	end
	local ok, Audio = pcall(require, script.Parent.AudioController)
	if ok and Audio and Audio.Play then
		pcall(Audio.Play, "U1_1", { bus = "UI", volume = 0.6, cooldown = 0.04 })
	end
end

-- Fire feedback for a specific equipped tool (local shots and replicated shots both route here).
function Controller.OnToolFired(tool: Instance)
	local art = tool:FindFirstChild("Phase13WeaponArt")
	if not art then
		return
	end
	local isLocal = tool.Parent == (Players.LocalPlayer and Players.LocalPlayer.Character)
	for _, d in art:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local n = d:GetAttribute("EmitOnFire")
			if type(n) == "number" and n > 0 then
				d:Emit(n)
			end
		elseif d:IsA("BasePart") then
			local rig = rigs[d]
			if rig and rig.kind == "FireStep" then
				rig.angle = Controller.NextDrumAngle(rig.angle, rig.step)
				play(rig, rig.base * CFrame.Angles(0, 0, math.rad(rig.angle)), DRUM_STEP_TWEEN)
				if isLocal then
					clickSound()
				end
			elseif rig and rig.kind == "FirePump" then
				play(rig, rig.base * CFrame.new(0, 0, rig.distance), KICK_TWEEN)
			end
		end
	end
end

-- A replicated shot only carries its origin: pick the equipped launcher whose muzzle is nearest.
function Controller.OnShot(origin: Vector3)
	local best, bestDistance = nil, 8
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local handle = tool and tool:FindFirstChild("Handle")
		local muzzle = handle and handle:FindFirstChild("Muzzle")
		if tool and muzzle and muzzle:IsA("Attachment") then
			local distance = (muzzle.WorldPosition - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = tool, distance
			end
		end
	end
	if best then
		Controller.OnToolFired(best)
	end
end

function Controller.Start()
	if started then
		return
	end
	started = true
	for _, rotor in CollectionService:GetTagged("CampAnimRotor") do
		bind(rotor)
	end
	CollectionService:GetInstanceAddedSignal("CampAnimRotor"):Connect(bind)
	CollectionService:GetInstanceRemovedSignal("CampAnimRotor"):Connect(unbind)
	if PlaytestFlags.Part("WeaponFx") then
		-- Playtest Fixes C5: idle emitters on held weapons are off on Low quality (bursts still play).
		local player = Players.LocalPlayer
		local function apply(e: Instance)
			if e:IsA("ParticleEmitter") and e:FindFirstAncestorOfClass("Tool") then
				e.Enabled = PresentationQuality.GetTier(player:GetAttribute("VFXQuality")) ~= "Low"
			end
		end
		for _, e in CollectionService:GetTagged(IDLE_TAG) do
			apply(e)
		end
		CollectionService:GetInstanceAddedSignal(IDLE_TAG):Connect(apply)
		player:GetAttributeChangedSignal("VFXQuality"):Connect(function()
			for _, e in CollectionService:GetTagged(IDLE_TAG) do
				apply(e)
			end
		end)
	end
end

return Controller
