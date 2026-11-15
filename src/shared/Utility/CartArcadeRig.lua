--!strict
-- One fitted hidden hull and one server-known motor. Accepted art, wheel joints,
-- seat and semantic mounts are retained. Step is shared by the current local
-- driver and the server's parked fallback, never both for a driven mechanism.
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Shared.Config.CartHandlingConfig)
local Math = require(script.Parent.CartHandlingMath)
local Geometry = require(script.Parent.CartGeometry)
local Rig = {}
Rig.Version = 1
function Rig.Configure(cart: Model)
    local geometry = assert(Geometry.Get(cart), "Arcade cart requires fitted geometry")
    local root = cart:FindFirstChild("Root") :: BasePart
    local seat = cart:FindFirstChild("DriverSeat") :: VehicleSeat
    assert(root and seat, "Missing cart root/seat")
    local constraints = assert(cart:FindFirstChild("Constraints"))
    for _,x in ipairs(cart:GetDescendants()) do
        if x:IsA("BodyMover") or x:IsA("LinearVelocity") or x:IsA("AngularVelocity")
            or (x:IsA("AlignOrientation") and x.Name ~= "ArcadeOrientation")
            or (x:IsA("Torque") and x.Name == "CartStabilityTorque") then
            x:Destroy()
        elseif x:IsA("BasePart") and x:GetAttribute("CartGeometryCollider") == true then
            x.CanCollide, x.Massless = false, true
        end
    end
    seat.Torque, seat.MaxSpeed, seat.TurnSpeed = 0, 0, 0
    local size = geometry.RootSize
    root.CustomPhysicalProperties = PhysicalProperties.new(Config.RootMass / (size.X * size.Y * size.Z), Config.ContactFriction, 0, 100, 100)
    local hull = cart:FindFirstChild("ArcadeHull") :: Part?
    if not hull then hull = Instance.new("Part"); hull.Name = "ArcadeHull"; hull.Parent = cart end
    assert(hull:IsA("Part"), "Arcade hull class conflict")
    local weld = hull:FindFirstChild("ArcadeHullWeld") :: WeldConstraint?
    if not weld then weld = Instance.new("WeldConstraint"); weld.Name = "ArcadeHullWeld"; weld.Parent = hull end
    weld.Part0 = nil
    hull.Size = Vector3.new(size.X - Config.HullInset * 2, Config.HullHeight, size.Z - Config.HullInset * 2)
    hull.CFrame = root.CFrame * CFrame.new(0, geometry.Ground.BottomY + Config.HullHeight / 2, 0)
    hull.Transparency, hull.Anchored, hull.Massless = 1, false, true
    hull.CanCollide, hull.CanTouch, hull.CanQuery = true, false, true
    hull.CollisionGroup = root.CollisionGroup
    hull.CustomPhysicalProperties = PhysicalProperties.new(0.7, Config.ContactFriction, 0, 100, 100)
    weld.Part0, weld.Part1 = root, hull
    local attachment = root:FindFirstChild("ArcadeMotorAttachment") :: Attachment?
    if not attachment then attachment = Instance.new("Attachment"); attachment.Name = "ArcadeMotorAttachment"; attachment.Parent = root end
    local force = constraints:FindFirstChild("ArcadeDrive") :: VectorForce?
    if not force then force = Instance.new("VectorForce"); force.Name = "ArcadeDrive"; force.Parent = constraints end
    force.Attachment0, force.Attachment1 = attachment, nil
    force.ApplyAtCenterOfMass, force.RelativeTo = true, Enum.ActuatorRelativeTo.World
    force.Force, force.Enabled = Vector3.zero, true
    local orientation = constraints:FindFirstChild("ArcadeOrientation") :: AlignOrientation?
    if not orientation then orientation = Instance.new("AlignOrientation"); orientation.Name = "ArcadeOrientation"; orientation.Parent = constraints end
    orientation.Attachment0, orientation.Attachment1 = attachment, nil
    orientation.Mode, orientation.AlignType = Enum.OrientationAlignmentMode.OneAttachment, Enum.AlignType.AllAxes
    orientation.RigidityEnabled, orientation.ReactionTorqueEnabled = false, false
    orientation.Responsiveness = Config.OrientationResponsiveness
    orientation.MaxAngularVelocity = math.rad(Config.LowTurnDegrees)
    orientation.MaxTorque = Config.MaximumTorque
    orientation.CFrame, orientation.Enabled = root.CFrame.Rotation, true
    cart:SetAttribute("CartArcadeVersion", Config.Version)
end
function Rig.CreateState(cart: Model, character: Model?): any
    local geometry = assert(Geometry.Get(cart))
    local root = cart:FindFirstChild("Root") :: BasePart
    local hull = cart:FindFirstChild("ArcadeHull") :: BasePart
    local folder = assert(cart:FindFirstChild("Constraints"))
    assert(root and hull and folder:FindFirstChild("ArcadeDrive") and folder:FindFirstChild("ArcadeOrientation"), "Server motor not replicated yet")
    local excluded: {Instance} = {cart}
    if character then table.insert(excluded, character) end
    local ray = RaycastParams.new()
    ray.FilterType, ray.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, excluded
    ray.RespectCanCollide, ray.CollisionGroup = true, root.CollisionGroup
    local overlap = OverlapParams.new()
    overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, excluded
    overlap.RespectCanCollide, overlap.CollisionGroup, overlap.MaxParts = true, root.CollisionGroup, 8
    local x, z = hull.Size.X * 0.42, hull.Size.Z * 0.42
    local y = geometry.Ground.BottomY + Config.SupportOriginLift
    return {cart=cart, root=root, hull=hull, size=hull.Size, geometry=geometry,
        force=folder.ArcadeDrive, orientation=folder.ArcadeOrientation,
        ray=ray, overlap=overlap,
        probes={Vector3.new(0,y,0),Vector3.new(x,y,z),Vector3.new(-x,y,z),Vector3.new(x,y,-z),Vector3.new(-x,y,-z)},
        heading=Math.Unit(Math.Project(root.CFrame.LookVector,Vector3.yAxis),Vector3.new(0,0,-1)),
        normal=Vector3.yAxis, grounded=false, support=nil, sampleElapsed=1, diagnosticElapsed=0, reversing=false}
end
local function sampleSupport(state: any, elapsed: number)
    local normal, weight = Vector3.zero, 0
    local nearest = math.huge
    state.grounded, state.support = false, nil
    for _,point in ipairs(state.probes) do
        local hit = Workspace:Raycast(state.root.CFrame:PointToWorldSpace(point), Vector3.new(0,-Config.SupportOriginLift-Config.SupportGap,0), state.ray)
        if hit and Math.Walkable(hit.Normal) then
            local w = 1 / math.max(0.1, hit.Distance)
            normal += hit.Normal * w; weight += w
            if hit.Distance < nearest then nearest=hit.Distance;state.support=hit.Instance end
        end
    end
    if weight > 0 then
        local nextNormal = normal.Unit
        state.normal = Math.Unit(state.normal:Lerp(nextNormal,1-math.exp(-elapsed/Config.NormalTau)),Vector3.yAxis)
        state.grounded = true
    else
        state.normal = Vector3.yAxis -- never retain propulsion across a gap
    end
end
local function overlapNormal(part: BasePart, point: Vector3): Vector3
    local p, h = part.CFrame:PointToObjectSpace(point), part.Size / 2
    local closest = Vector3.new(math.clamp(p.X,-h.X,h.X), math.clamp(p.Y,-h.Y,h.Y), math.clamp(p.Z,-h.Z,h.Z))
    local delta = p - closest
    if delta.Magnitude < 1e-4 then
        local dx,dy,dz=h.X-math.abs(p.X),h.Y-math.abs(p.Y),h.Z-math.abs(p.Z)
        if dx <= dy and dx <= dz then delta=Vector3.new(if p.X>=0 then 1 else -1,0,0)
        elseif dz <= dy then delta=Vector3.new(0,0,if p.Z>=0 then 1 else -1)
        else delta=Vector3.new(0,if p.Y>=0 then 1 else -1,0) end
    end
    return part.CFrame:VectorToWorldSpace(delta.Unit)
end
local function wallContact(state: any, intent: Vector3, dt: number, parameters: any): Vector3?
    local actual = Math.Project(state.root.AssemblyLinearVelocity, Vector3.yAxis)
    local direction = Math.Unit(if actual.Magnitude>0.5 then actual else intent,Vector3.zero)
    if direction == Vector3.zero then return nil end
    local skin = Config.CollisionSkin
    local checkSize = Vector3.new(math.max(0.2,state.size.X-skin*2), math.max(0.2,state.size.Y-skin), math.max(0.2,state.size.Z-skin*2))
    for _,part in ipairs(Workspace:GetPartBoundsInBox(state.hull.CFrame,checkSize,state.overlap)) do
        local normal = overlapNormal(part,state.hull.Position)
        if math.abs(normal.Y)<Config.MinimumWallUpDot and direction:Dot(normal)<0 then return normal end
    end
    local reach=math.clamp(actual.Magnitude*dt+0.5*parameters.acceleration*dt*dt+skin,skin,Config.MaximumSweepDistance)
    local hit=Workspace:Blockcast(state.hull.CFrame,checkSize,direction*reach,state.ray)
    return if hit and math.abs(hit.Normal.Y)<Config.MinimumWallUpDot then hit.Normal else nil
end
function Rig.Parameters(profile: any): any
    return {speed=profile.MaxTravelSpeed,acceleration=profile.ForwardAcceleration,braking=profile.Braking,
        lowTurn=profile.TurnRate,highTurn=Config.CruiseTurnDegrees*(profile.TurnRate/Config.LowTurnDegrees)}
end
function Rig.Step(state: any, parameters: any, intent: Vector3, magnitude: number, dt: number, supportHz: number?): any
    local root=state.root
    if not root.Parent or root.Anchored or not Math.FiniteVector(root.AssemblyLinearVelocity) then
        state.force.Force=Vector3.zero;return nil
    end
    state.sampleElapsed+=dt
    if state.sampleElapsed>=1/(supportHz or Config.SupportHz) then
        sampleSupport(state,state.sampleElapsed);state.sampleElapsed=0
    end
    local mass=root.AssemblyMass
    if not Math.Finite(mass) or mass<=0 then state.force.Force=Vector3.zero;return nil end
    local supportVelocity=Vector3.zero
    if state.support and state.support.Parent and state.support:IsA("BasePart") then supportVelocity=state.support:GetVelocityAtPosition(root.Position) end
    local wall=wallContact(state,intent,math.min(dt,Config.MaximumFrameGap),parameters)
    local denied=state.cart:GetAttribute("WorldGateDeniedNormal")
    if not wall and Math.FiniteVector(denied) then wall=denied end
    local result=Math.Step(state,{normal=state.normal,forward=root.CFrame.LookVector,
        velocity=root.AssemblyLinearVelocity,supportVelocity=supportVelocity,mass=mass,gravity=Workspace.Gravity,
        intent=intent,magnitude=magnitude,grounded=state.grounded,wallNormal=wall},parameters,dt)
    if Math.FiniteVector(denied) then result.force=Math.RemoveInward(result.force,denied) end
    state.force.Enabled=true;state.force.Force=result.force
    local inertia=mass*(state.size.X^2+state.size.Z^2)/12
    state.orientation.MaxTorque=math.clamp(inertia*Config.AngularAcceleration,1000,Config.MaximumTorque)
    state.orientation.MaxAngularVelocity=math.rad(parameters.lowTurn)
    state.orientation.Responsiveness=if state.grounded then Config.OrientationResponsiveness else 8
    if not state.grounded then state.orientation.MaxTorque*=0.10 end
    state.orientation.Enabled=true
    state.orientation.CFrame=CFrame.lookAt(Vector3.zero,result.heading,state.normal)
    state.last=result;state.wall=wall;state.mass=mass
    return result
end
function Rig.Suspend(state: any)
    state.force.Force=Vector3.zero;state.force.Enabled=false;state.orientation.Enabled=false
end
return table.freeze(Rig)
