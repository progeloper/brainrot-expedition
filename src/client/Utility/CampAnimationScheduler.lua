--!strict
-- Camp Rework: the ONE client animation loop for weapon spinners, stall props and Training
-- feedback. It ticks at most 10 times a second (Heartbeat accumulator) and skips every entry that
-- is off-screen or farther than its radius (default 150 studs) from the camera. No per-model loops:
-- callers register an entry and receive step(now, dt) calls. Smoothness between ticks comes from a
-- short engine tween that each step may start (TweenService), never from a per-frame script.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Entry = {
	position: () -> Vector3?, -- world position used for culling; nil = skip this tick
	step: (now: number, dt: number) -> (),
	radius: number?, -- cull distance (studs); default 150
	always: boolean?, -- skip on-screen culling (still distance-culled)
	hidden: (() -> ())?, -- called once when a stepped entry becomes culled (Playtest Fixes C1)
}

local Scheduler = {}
Scheduler.Hz = 10
Scheduler.DefaultRadius = 150

local entries: { [any]: Entry } = {}
local shown: { [any]: boolean } = {}
local count = 0
local connection: RBXScriptConnection? = nil
local accumulator = 0
local lastTick = 0
local stats = { ticks = 0, stepped = 0, culled = 0 }

local function visible(entry: Entry, camera: Camera?): boolean
	local position = entry.position()
	if not position or not camera then
		return false
	end
	local radius = entry.radius or Scheduler.DefaultRadius
	if (camera.CFrame.Position - position).Magnitude > radius then
		return false
	end
	if entry.always then
		return true
	end
	local _, onScreen = camera:WorldToViewportPoint(position)
	return onScreen
end

local function tick()
	local now = os.clock()
	local dt = if lastTick > 0 then now - lastTick else 1 / Scheduler.Hz
	lastTick = now
	stats.ticks += 1
	local camera = Workspace.CurrentCamera
	for key, entry in entries do
		local ok, isVisible = pcall(visible, entry, camera)
		if ok and isVisible then
			shown[key] = true
			stats.stepped += 1
			local stepped, err = pcall(entry.step, now, dt)
			if not stepped then
				warn("[CampAnimationScheduler] entry failed and was removed:", err)
				Scheduler.Unregister(key)
			end
		else
			stats.culled += 1
			if shown[key] then
				shown[key] = nil
				if entry.hidden then
					pcall(entry.hidden)
				end
			end
		end
	end
end

local function ensureRunning()
	if connection or count == 0 then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		local period = 1 / Scheduler.Hz
		if accumulator < period then
			return
		end
		accumulator = math.min(accumulator - period, period)
		tick()
	end)
end

function Scheduler.Register(key: any, entry: Entry)
	if entries[key] == nil then
		count += 1
	end
	entries[key] = entry
	ensureRunning()
end

function Scheduler.Unregister(key: any)
	if entries[key] ~= nil then
		entries[key] = nil
		shown[key] = nil
		count -= 1
	end
	if count == 0 and connection then
		connection:Disconnect()
		connection = nil
		accumulator = 0
	end
end

function Scheduler.IsRegistered(key: any): boolean
	return entries[key] ~= nil
end

function Scheduler.Count(): number
	return count
end

function Scheduler.Stats(): { ticks: number, stepped: number, culled: number, entries: number }
	return { ticks = stats.ticks, stepped = stats.stepped, culled = stats.culled, entries = count }
end

-- Test hook: run one tick immediately (no culling camera required when entries use always).
function Scheduler._TickForTests()
	tick()
end

return Scheduler
