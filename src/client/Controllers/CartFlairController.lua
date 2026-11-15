--!strict
-- Local-only presentation for baked cart flair (Visual.Flair, tag "CartFlair").
-- Never drives a cart and never writes server state. Every effect ships disabled in
-- the template; this controller turns effects on by motion state, distance and the
-- player's resolved VFX quality, and runs the tier-3 colour cycles.
-- Budget (design/Brainrot_Cart_Flair_Standard.md): own cart gets the player's tier,
-- other carts one step lower within 70 studs and two steps lower within 120, so a
-- Low-quality phone only animates its own trails and smoke.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")

local Styles = require(RS.Shared.Config.CartFlairStyles)
local Quality = require(RS.Shared.Utility.ResolvedPresentationQuality)
local cartsOk, Carts = pcall(require, RS.Shared.Config.Carts)
local visibilityOk, Visibility = pcall(require, script.Parent.RegionVisibilityController)

local Controller = {}
local R = Styles.Runtime
local RANK = { Low = 1, Medium = 2, High = 3 }
local STATE_INTERVAL = 0.1
local CYCLE_INTERVAL = 1 / 20
local RESCAN_INTERVAL = 1
local CYCLE_PERIOD = 3.2 -- seconds for one full palette loop

local player = Players.LocalPlayer
local started = false
local connections: { RBXScriptConnection } = {}
local records: { [Instance]: any } = {}
local stateClock, cycleClock, rescanClock = 0, 0, 0
local activeEffects, cyclingParts = 0, 0

local function rank(value: any): number
	return RANK[value] or 1
end

local function close(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.013 and math.abs(a.G - b.G) < 0.013 and math.abs(a.B - b.B) < 0.013
end

local function scan(flair: Model, cart: Model): any
	local rec = {
		Flair = flair, Cart = cart, Fx = {}, Cycle = {}, Count = 0,
		Moving = false, Budget = 0, Cycling = false, MaxSpeed = 30,
		Palette = Styles.Cycles[flair:GetAttribute("FlairCycle") :: any],
	}
	for _, d in flair:GetDescendants() do
		rec.Count += 1
		if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Light") then
			local mode = d:GetAttribute("FlairMode")
			if type(mode) == "string" then
				(d :: any).Enabled = false
				local rate = d:GetAttribute("FlairRate")
				table.insert(rec.Fx, {
					I = d, Mode = mode, Q = rank(d:GetAttribute("FlairQuality")),
					Rate = if type(rate) == "number" then rate else nil, On = false,
					Emitter = d:IsA("ParticleEmitter"),
				})
			end
		elseif d:IsA("BasePart") and d:GetAttribute("FlairCycle") == true then
			local base = d:GetAttribute("FlairBaseColor")
			local phase = d:GetAttribute("FlairPhase")
			-- A selected finish (Riftgold, Trailblazer, ...) recolours on the server;
			-- such parts are left alone so the paid finish always wins.
			local off = typeof(base) ~= "Color3" or not close(d.Color, base :: Color3)
			table.insert(rec.Cycle, {
				P = d, Base = base, Phase = if type(phase) == "number" then phase else 0, Last = nil, Off = off,
			})
		end
	end
	local id = cart:GetAttribute("CartId")
	if cartsOk and type(id) == "string" and Carts[id] and type(Carts[id].MaxTravelSpeed) == "number" then
		rec.MaxSpeed = Carts[id].MaxTravelSpeed
	end
	return rec
end

local function disableAll(rec: any)
	for _, fx in rec.Fx do
		if fx.On and fx.I.Parent then
			fx.I.Enabled = false
		end
		fx.On = false
	end
	if rec.Cycling then
		for _, c in rec.Cycle do
			if not c.Off and c.P.Parent and c.Last and close(c.P.Color, c.Last) then
				c.P.Color = c.Base
			end
			c.Last = nil
		end
		rec.Cycling = false
	end
	rec.Budget = 0
end

local function cartOf(flair: Instance): Model?
	local visual = flair.Parent
	local cart = visual and visual.Parent
	return if cart and cart:IsA("Model") then cart else nil
end

local function register(flair: Instance)
	if records[flair] or not flair:IsA("Model") or not flair:IsDescendantOf(Workspace) then
		return
	end
	local cart = cartOf(flair)
	if not cart then
		return
	end
	records[flair] = scan(flair, cart)
end

local function release(flair: Instance)
	local rec = records[flair]
	if rec then
		disableAll(rec)
		records[flair] = nil
	end
end

local function isOwn(cart: Model): boolean
	if not player then
		return false
	end
	local uid = player.UserId
	return cart:GetAttribute("OwnerUserId") == uid or cart:GetAttribute("ActiveDriverUserId") == uid
end

local function updateState(rec: any, q: number, scale: number, camPos: Vector3)
	local cart = rec.Cart
	local root = cart.PrimaryPart
	if not root or (visibilityOk and Visibility.IsVisible and not Visibility.IsVisible(cart)) then
		disableAll(rec)
		return
	end
	local dist = (root.Position - camPos).Magnitude
	local budget = 0
	if dist <= R.MaxDistance then
		if isOwn(cart) then
			budget = q
		elseif dist <= R.OthersMediumDistance then
			budget = q - 1
		elseif dist <= R.OthersHighDistance then
			budget = q - 2
		end
	end
	rec.Budget, rec.Distance = budget, dist
	if budget <= 0 then
		disableAll(rec)
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	rec.Moving = if rec.Moving then speed > R.MovingSpeed * 0.6 else speed > R.MovingSpeed
	local fast = speed > rec.MaxSpeed * R.FastFraction
	local boost = cart:GetAttribute("BurstActive") == true or speed > rec.MaxSpeed * R.BoostFraction
	local driver = cart:GetAttribute("ActiveDriverUserId")
	local driving = type(driver) == "number" and driver ~= 0
	for _, fx in rec.Fx do
		local mode = fx.Mode
		local want = fx.Q <= budget
			and (mode == "Always"
				or (mode == "Moving" and rec.Moving)
				or (mode == "Fast" and fast)
				or (mode == "Boost" and boost)
				or (mode == "Driving" and driving))
		if want ~= fx.On then
			fx.On = want
			fx.I.Enabled = want
		end
		if want then
			activeEffects += 1
			if fx.Emitter and fx.Rate then
				-- Boost pushes exhaust output up; quality scales everything.
				local r = fx.Rate * scale * (if boost and mode == "Moving" then 1.6 else 1)
				if math.abs(fx.I.Rate - r) > 0.01 then
					fx.I.Rate = r
				end
			end
		end
	end
end

local function updateCycle(rec: any, now: number, allowed: boolean)
	local palette = rec.Palette
	if not palette or #rec.Cycle == 0 then
		return
	end
	if not allowed or rec.Budget <= 0 or (rec.Distance or math.huge) > R.CycleDistance then
		if rec.Cycling then
			for _, c in rec.Cycle do
				if not c.Off and c.Last and close(c.P.Color, c.Last) then
					c.P.Color = c.Base
				end
				c.Last = nil
			end
			rec.Cycling = false
		end
		return
	end
	rec.Cycling = true
	local n = #palette
	local t = now / CYCLE_PERIOD
	for _, c in rec.Cycle do
		if c.Off then
			continue
		end
		local part = c.P
		if c.Last and not close(part.Color, c.Last) then
			c.Off = true -- the server applied a finish after we started; it wins
			continue
		end
		local u = ((t + c.Phase) % 1) * n
		local i = math.floor(u)
		local color = palette[i + 1]:Lerp(palette[(i + 1) % n + 1], u - i)
		part.Color = color
		c.Last = part.Color
		cyclingParts += 1
	end
end

local function step(dt: number)
	stateClock += dt
	cycleClock += dt
	rescanClock += dt
	local camera = Workspace.CurrentCamera
	if not camera or not player then
		return
	end
	if rescanClock >= RESCAN_INTERVAL then
		rescanClock = 0
		for flair, rec in records do
			if not flair.Parent or not flair:IsDescendantOf(Workspace) or cartOf(flair) ~= rec.Cart then
				release(flair)
			elseif #flair:GetDescendants() ~= rec.Count then
				-- Streaming delivered more of the model: rebuild the record.
				disableAll(rec)
				records[flair] = scan(flair :: Model, rec.Cart)
			end
		end
	end
	if stateClock >= STATE_INTERVAL then
		stateClock = 0
		activeEffects = 0
		local tier = Quality.GetTier(player:GetAttribute("VFXQuality"))
		local reduced = player:GetAttribute("ReducedMotion") == true
		local scale = (R.RateScale[tier] or 1) * (if reduced then 0.5 else 1)
		local q = rank(tier)
		local camPos = camera.CFrame.Position
		for _, rec in records do
			updateState(rec, q, scale, camPos)
		end
	end
	if cycleClock >= CYCLE_INTERVAL then
		cycleClock = 0
		cyclingParts = 0
		local allowed = player:GetAttribute("ReducedMotion") ~= true
		local now = os.clock()
		for _, rec in records do
			updateCycle(rec, now, allowed)
		end
	end
end

function Controller.Start(): boolean
	if started then
		return false
	end
	started = true
	table.insert(connections, CollectionService:GetInstanceAddedSignal(Styles.Tag):Connect(function(flair)
		task.defer(register, flair)
	end))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(Styles.Tag):Connect(release))
	for _, flair in CollectionService:GetTagged(Styles.Tag) do
		register(flair)
	end
	table.insert(connections, RunService.Heartbeat:Connect(step))
	return true
end

function Controller.Stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for flair in records do
		release(flair)
	end
	started = false
end

-- Studio verification hook: one synchronous state + cycle pass with a given
-- camera position and tier, over every tagged flair in Workspace.
function Controller._TestPass(camPos: Vector3, tierName: string, now: number?): any
	for _, flair in CollectionService:GetTagged(Styles.Tag) do
		register(flair)
	end
	activeEffects, cyclingParts = 0, 0
	local q = rank(tierName)
	for _, rec in records do
		updateState(rec, q, R.RateScale[tierName] or 1, camPos)
		updateCycle(rec, now or os.clock(), true)
	end
	return Controller.GetDiagnostics()
end

function Controller._TestReset()
	for flair in records do
		release(flair)
	end
end

function Controller.GetDiagnostics(): any
	local count = 0
	for _ in records do
		count += 1
	end
	return { Started = started, RegisteredCarts = count, ActiveEffects = activeEffects, CyclingParts = cyclingParts }
end

return Controller
