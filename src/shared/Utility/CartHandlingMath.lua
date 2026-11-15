--!strict
local Config = require(script.Parent.Parent.Config.CartHandlingConfig)
local Math = {}
function Math.Finite(n: any): boolean
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end
function Math.FiniteVector(v: any): boolean
    return typeof(v) == "Vector3" and Math.Finite(v.X) and Math.Finite(v.Y) and Math.Finite(v.Z)
end
function Math.Project(v: Vector3, n: Vector3): Vector3
    return v - n * v:Dot(n)
end
function Math.Unit(v: Vector3, fallback: Vector3): Vector3
    return if Math.FiniteVector(v) and v.Magnitude > 1e-5 then v.Unit else fallback
end
function Math.Shape(raw: Vector2): (Vector2, number)
    if not Math.Finite(raw.X) or not Math.Finite(raw.Y) then return Vector2.zero, 0 end
    local length = raw.Magnitude
    if length <= Config.Deadzone + 1e-6 then return Vector2.zero, 0 end
    return raw / length, math.clamp((length - Config.Deadzone) / (1 - Config.Deadzone), 0, 1)
end
function Math.GestureGate(raw: Vector2, needsFresh: boolean, blocked: boolean): (Vector2, boolean)
    if blocked then return Vector2.zero,true end
    if needsFresh then
        return Vector2.zero,raw.Magnitude>Config.Deadzone
    end
    return raw,false
end
function Math.ShouldRecenter(now: number, neutralAt: number, lastManualAt: number, moving: boolean, looking: boolean): boolean
    return not moving and not looking and now-neutralAt>=Config.NeutralCameraDelay
        and now-lastManualAt>=Config.ManualCameraGrace
end
-- raw axes: +X camera-right; +Y camera-forward. Output is WORLD space.
function Math.WorldIntent(raw: Vector2, cameraLook: Vector3, previousForward: Vector3): (Vector3, number, Vector3)
    local flat = Math.Unit(Math.Project(cameraLook, Vector3.yAxis), previousForward)
    local right = flat:Cross(Vector3.yAxis)
    local direction, magnitude = Math.Shape(raw)
    return Math.Unit(flat * direction.Y + right * direction.X, Vector3.zero), magnitude, flat
end
function Math.SignedAngle(a: Vector3, b: Vector3, normal: Vector3): number
    return math.atan2(normal:Dot(a:Cross(b)), math.clamp(a:Dot(b), -1, 1))
end
function Math.RemoveInward(v: Vector3, normal: Vector3): Vector3
    local amount = v:Dot(normal)
    return if amount < 0 then v - normal * amount else v
end
function Math.Walkable(normal: Vector3): boolean
    return Math.FiniteVector(normal) and normal.Y >= math.cos(math.rad(Config.MaximumSupportSlope))
end
function Math.VisibleDistance(speed: number, braking: number, halfLength: number, latency: number?): number
    local lead = math.max((latency or Config.ReadinessLatency) + 0.75, 2)
    return speed * lead + speed * speed / (2 * math.max(braking, 1)) + halfLength + 24
end
function Math.ValidPacket(packet: any, cart: any, session: number, lastSequence: number): boolean
    return type(packet) == "table" and packet.cart == cart and packet.session == session
        and Math.Finite(packet.sequence) and packet.sequence % 1 == 0
        and packet.sequence > lastSequence and packet.sequence <= 2147483647
        and Math.Finite(packet.magnitude) and packet.magnitude >= 0 and packet.magnitude <= 1
        and Math.FiniteVector(packet.direction) and packet.direction.Magnitude <= 1.001
        and type(packet.braking) == "boolean" and type(packet.paused) == "boolean"
end
function Math.AuthorityMatches(sender: number, owner: number?, driver: number?, session: number, approvedSession: number?, alive: boolean): boolean
    return alive and sender==owner and sender==driver and session>0 and session==approvedSession
end
function Math.Step(state: any, sample: any, parameters: any, dt: number): any
    local safeDt = if Math.Finite(dt) and dt > 0 then math.min(dt, Config.MaximumFrameGap) else 0
    local normal = Math.Unit(sample.normal, Vector3.yAxis)
    local forward = Math.Unit(Math.Project(sample.forward, normal), Vector3.new(0, 0, -1))
    local right = Math.Unit(forward:Cross(normal), Vector3.xAxis)
    local speed = math.max(parameters.speed, 0)
    local scale = speed / Config.StarterSpeed
    local acceleration = parameters.acceleration or Config.ForwardAcceleration * scale
    local braking = parameters.braking or Config.Braking * scale
    local velocity = sample.velocity
    local relative = velocity - (sample.supportVelocity or Vector3.zero)
    local vf, vs = relative:Dot(forward), relative:Dot(right)
    local lowTurn = parameters.lowTurn or Config.LowTurnDegrees
    local highTurn = parameters.highTurn or Config.CruiseTurnDegrees
    local turn = math.rad(lowTurn + (highTurn - lowTurn) * math.clamp(relative.Magnitude / math.max(speed, 1), 0, 1))
    local heading = Math.Unit(Math.Project(state.heading or forward, normal), forward)
    local magnitude = math.clamp(sample.magnitude or 0, 0, 1)
    local intent = Math.Project(sample.intent or Vector3.zero, normal)
    local angle = 0
    if magnitude > 0 and intent.Magnitude > 1e-5 then
        intent = intent.Unit
        angle = math.abs(Math.SignedAngle(forward, intent, normal))
        if angle > Config.ReversalEnter then state.reversing = true
        elseif angle < Config.ReversalLeave then state.reversing = false end
        local delta = Math.SignedAngle(heading, intent, normal)
        heading = CFrame.fromAxisAngle(normal, math.clamp(delta, -turn * safeDt, turn * safeDt)):VectorToWorldSpace(heading)
    else
        magnitude, state.reversing = 0, false
    end
    state.heading = heading
    local alignment = 1 - (1 - Config.AlignmentAtRightAngle) * math.clamp(angle / (math.pi / 2), 0, 1)
    local goal = if state.reversing then 0 else speed * magnitude ^ Config.SpeedExponent * alignment
    local goalVector = forward * goal
    if sample.wallNormal then goalVector = Math.RemoveInward(goalVector, sample.wallNormal) end
    goal = goalVector:Dot(forward)
    local shouldBrake = magnitude == 0 or state.reversing == true
    local af = math.clamp((goal - vf) / math.max(Config.LongitudinalTau, safeDt), -braking, if shouldBrake then braking else acceleration)
    local lateralLimit = math.clamp(math.max(Config.MinimumLateralAcceleration, speed * math.rad(lowTurn) * 1.25), Config.MinimumLateralAcceleration, Config.MaximumLateralAcceleration)
    local side = math.clamp((goalVector:Dot(right) - vs) / math.max(Config.LateralTau, safeDt), -lateralLimit, lateralLimit)
    local gravity = Vector3.new(0, -sample.gravity, 0)
    local force = (forward * af + right * side - Math.Project(gravity, normal)) * sample.mass
    if not sample.grounded or not Math.Finite(dt) or dt <= 0 or dt > Config.MaximumFrameGap then force = Vector3.zero end
    if sample.wallNormal then force = Math.RemoveInward(force, sample.wallNormal) end
    if not Math.FiniteVector(force) then force = Vector3.zero end
    return {force = force, heading = heading, normal = normal, goal = goal, braking = shouldBrake,
        turnRate = turn, forwardSpeed = vf, sideSpeed = vs, grounded = sample.grounded}
end
return table.freeze(Math)
