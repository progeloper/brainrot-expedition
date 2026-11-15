--!strict
-- Per-template dimensions only. Catalogue identity, capacities and movement tuning
-- remain in their existing owners. Legacy templates do not acquire a profile.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Profiles = require(ReplicatedStorage.Shared.Config.CartGeometry)
local Geometry = {}
local validProfiles: {[string]: any} = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function vector(v: any): boolean
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function size(v: any): boolean
	return vector(v) and v.X > 0 and v.Y > 0 and v.Z > 0 and v.Magnitude < 128
end
local function frame(v: any): boolean
	if typeof(v) ~= "CFrame" then return false end
	for _, n in {v:GetComponents()} do if not finite(n) then return false end end
	return v.Position.Magnitude < 128
end

function Geometry.Validate(profile: any): (boolean, string?)
	if type(profile) ~= "table" or type(profile.Id) ~= "string" or not finite(profile.Revision) then
		return false, "Missing geometry identity/revision"
	end
	if profile.Revision < 1 or profile.Revision % 1 ~= 0 or not size(profile.RootSize) or not size(profile.BodySize) then
		return false, "Invalid geometry dimensions/revision"
	end
	if not vector(profile.Forward) or not vector(profile.Up) or profile.Forward:Dot(Vector3.new(0,0,-1)) < 0.999 or profile.Up:Dot(Vector3.yAxis) < 0.999 then
		return false, "Geometry convention must match controller -Z forward/+Y up"
	end
	if type(profile.Colliders) ~= "table" or #profile.Colliders < 1 or #profile.Colliders > 6 then
		return false, "Expected one to six simple body/support colliders"
	end
	local names = {}
	for _, collider in profile.Colliders do
		if type(collider.Name) ~= "string" or names[collider.Name] or not size(collider.Size) or not frame(collider.Frame) then
			return false, "Invalid collider"
		end
		if collider.TargetMass and (not finite(collider.TargetMass)or collider.TargetMass<=0 or collider.Massless~=false or collider.Shape~=Enum.PartType.Cylinder)then return false,"Invalid authored contact mass"end
		names[collider.Name] = true
	end
	if not profile.DriverSeat or not frame(profile.DriverSeat.Frame) or not size(profile.DriverSeat.Size) or not frame(profile.CameraTarget) then
		return false, "Invalid rider/camera layout"
	end
	for _, slots in {profile.CargoSlots, profile.FormationSlots} do
		if type(slots) ~= "table" or #slots ~= 6 then return false, "Geometry must author all six semantic slots" end
		for _, cf in slots do if not frame(cf) then return false, "Invalid semantic slot frame" end end
	end
	local ground = profile.Ground
	if type(ground) ~= "table" or not finite(ground.BottomY) or type(ground.ContactSamples) ~= "table" or #ground.ContactSamples ~= 3 then
		return false, "Expected explicit ground bottom and three contact samples"
	end
	for _, p in ground.ContactSamples do if not vector(p) then return false, "Invalid contact sample" end end
	if ground.CylinderSamples then
		if type(ground.CylinderSamples)~="table" or #ground.CylinderSamples~=3 then return false,"Expected three authored cylinder probes" end
		for _,sample in ground.CylinderSamples do
			if type(sample.ColliderName)~="string" or not vector(sample.Hub) or not vector(sample.Axis) or math.abs(sample.Axis.Magnitude-1)>.001 or not finite(sample.Radius) or sample.Radius<=0 or not finite(sample.HalfThickness) or sample.HalfThickness<=0 or not finite(sample.AxialOffset) or math.abs(sample.AxialOffset)>sample.HalfThickness then return false,"Invalid cylinder support probe" end
			local collider=nil
			for _,c in profile.Colliders do if c.Name==sample.ColliderName then collider=c;break end end
			if not collider or collider.Shape~=Enum.PartType.Cylinder or (sample.Hub-collider.Frame.Position).Magnitude>.001 or math.abs(sample.Axis:Dot(collider.Frame.RightVector))<.999 or math.abs(sample.Radius-collider.Size.Y/2)>.001 or math.abs(collider.Size.Y-collider.Size.Z)>.001 or math.abs(sample.HalfThickness-collider.Size.X/2)>.001 then return false,"Cylinder probe differs from its authored physical support" end
		end
	end
	if type(profile.Wheels) ~= "table" then return false, "Wheels must be a list; an empty list is valid" end
	if profile.SteeringAlignType~=nil and profile.SteeringAlignType~=Enum.AlignType.AllAxes and profile.SteeringAlignType~=Enum.AlignType.PrimaryAxisParallel then return false,"Unsupported steering alignment type"end
	if profile.SteeringAlignType==Enum.AlignType.PrimaryAxisParallel and #profile.Wheels<2 then return false,"Axle alignment requires the authored wheeled rig"end
	if profile.BodyMesh and (not size(profile.BodyMesh.BindSize) or not frame(profile.BodyMesh.Frame) or not frame(profile.BodyMesh.PivotOffset))then return false,"Invalid body mesh bind"end
	local wheelNames = {}
	for _, wheel in profile.Wheels do
		if type(wheel.Name) ~= "string" or wheelNames[wheel.Name] or not size(wheel.BindSize) or not frame(wheel.Hub) or not vector(wheel.SpinAxis) or math.abs(wheel.SpinAxis.Magnitude-1) > 0.001 or not finite(wheel.Radius) or wheel.Radius <= 0 or not finite(wheel.Thickness) or wheel.Thickness <= 0 then
			return false, "Invalid authored wheel bind"
		end
		if math.abs(wheel.BindSize.Y-wheel.BindSize.Z)/math.max(wheel.BindSize.Y,wheel.BindSize.Z)>0.01 or math.abs(wheel.BindSize.X-wheel.Thickness)>math.max(0.01,wheel.Thickness*0.01)then return false,"Wheel rim/thickness is not authored independently"end
		wheelNames[wheel.Name] = true
	end
	return true, nil
end

function Geometry.GetById(id: any): (any?, string?)
	local profile = if type(id) == "string" then Profiles[id] else nil
	if not profile then return nil, "Unknown geometry profile" end
	if profile.DevelopmentOnly and not RunService:IsStudio() then return nil, "Development geometry is Studio-only" end
	if validProfiles[id] == profile then return profile, nil end
	local ok, reason = Geometry.Validate(profile)
	if ok then validProfiles[id] = profile end
	return if ok then profile else nil, reason
end
function Geometry.Get(cart: Model): (any?, string?)
	local id = cart:GetAttribute("CartGeometryId")
	if id == nil then return nil, nil end
	local profile, reason = Geometry.GetById(id)
	if not profile then return nil, reason end
	if cart:GetAttribute("CartGeometryRevision") ~= profile.Revision then return nil, "Geometry revision mismatch" end
	return profile, nil
end
function Geometry.SpawnOffset(cart: Model): CFrame
	local profile = Geometry.Get(cart)
	return CFrame.new(0, if profile then -profile.Ground.BottomY + (profile.Ground.SpawnLift or 0.25) else 4, 0)
end

local function bindSize(record: any,part: BasePart): Vector3
	return if part:IsA("UnionOperation") then record.NativeCSGBindSize else record.BindSize
end
local function bindPivot(record: any,part: BasePart): CFrame
	return if part:IsA("UnionOperation") then record.NativeCSGPivotOffset else record.PivotOffset
end
local function bindFrame(record: any,part: BasePart): CFrame
	return if part:IsA("UnionOperation") then record.NativeCSGFrame else record.Frame
end
local function sameFrame(a: CFrame,b: CFrame): boolean
	return (a.Position-b.Position).Magnitude<0.01 and a.RightVector:Dot(b.RightVector)>0.9999 and a.UpVector:Dot(b.UpVector)>0.9999
end
function Geometry.ValidateTemplate(cart: Model): (boolean, string?)
	local profile, reason = Geometry.Get(cart)
	if not profile then return cart:GetAttribute("CartGeometryId") == nil, reason end
	local arcade = cart:GetAttribute("CartArcadeVersion") == 1
	local root, visual = cart:FindFirstChild("Root"), cart:FindFirstChild("Visual")
	if not root or not root:IsA("BasePart") or not visual or not visual:IsA("Model") then return false, "Missing geometry root/visual" end
	if (root.Size-profile.RootSize).Magnitude > 0.01 or root.Massless or root.CanCollide or (not arcade and math.abs(root.CurrentPhysicalProperties.Density-profile.RootPhysicalProperties.Density)>.001) then return false, "Root is not the authored noncolliding ballast" end
	local function positioned(parent: Instance,name: string,expected: CFrame,expectedSize: Vector3?): boolean
		local p=parent:FindFirstChild(name,true)
		return p~=nil and p:IsA("BasePart") and sameFrame(root.CFrame:ToObjectSpace(p.CFrame),expected) and (not expectedSize or (p.Size-expectedSize).Magnitude<0.01)
	end
	if not positioned(cart,"DriverSeat",profile.DriverSeat.Frame,profile.DriverSeat.Size) or not positioned(cart,"CameraTarget",profile.CameraTarget,nil) then return false,"Semantic marker mismatch" end
	local seat=cart:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") or seat.CanCollide then return false,"DriverSeat must be the noncolliding functional seat" end
	for _,pair in {{"CargoSlots",profile.CargoSlots},{"FormationSlots",profile.FormationSlots}} do
		local folder=cart:FindFirstChild(pair[1])
		if not folder then return false,"Missing semantic slot folder" end
		for index,cf in pair[2] do if not positioned(folder,"Slot"..index,cf,nil) then return false,"Semantic slot mismatch" end end
	end
	for _, c in profile.Colliders do
		local p = visual:FindFirstChild(c.Name, true)
		if not p or not p:IsA("BasePart") or (not arcade and (not p.CanCollide or p.Massless~=(c.Massless~=false))) or not positioned(visual,c.Name,c.Frame,c.Size) then return false, "Collider mismatch: "..c.Name end
		if not arcade and c.TargetMass and math.abs(p:GetMass()-c.TargetMass)>.01 then return false,"Authored contact mass mismatch: "..c.Name end
	end
    if arcade then
        local hull=cart:FindFirstChild("ArcadeHull")
        if not hull or not hull:IsA("BasePart") or not hull.CanCollide or not hull.Massless then return false,"Missing arcade collision hull" end
    end
	if profile.BodyMesh then
		local body=visual:FindFirstChild("Body",true)
		if not positioned(visual,"Body",if body and body:IsA("BasePart") then bindFrame(profile.BodyMesh,body) else profile.BodyMesh.Frame,if body and body:IsA("BasePart") then bindSize(profile.BodyMesh,body) else profile.BodyMesh.BindSize) or not body or not body:IsA("BasePart") or not sameFrame(body.PivotOffset,bindPivot(profile.BodyMesh,body)) then return false,"Body bind mismatch" end
	end
	for _, wheel in profile.Wheels do
		local p = visual:FindFirstChild(wheel.Name, true)
		local motor = cart:FindFirstChild("CartWheel_"..wheel.Name, true)
		if not p or not p:IsA("BasePart") or (p.Size-bindSize(wheel,p)).Magnitude > 0.01 or p.CanCollide or not p.Massless or p:GetAttribute("CartWheelName")~=wheel.Name or not motor or not motor:IsA("Motor6D") or motor.Part0 ~= root or motor.Part1 ~= p or not sameFrame(motor.C0,wheel.Hub) or not sameFrame(motor.C1,p.PivotOffset) or not sameFrame(p.PivotOffset,bindPivot(wheel,p)) then return false, "Wheel bind mismatch: "..wheel.Name end
	end
	return true, nil
end

-- Only staged templates/isolated fixtures may be fitted. Live safe swaps copy
-- one already-validated template as a unit; no avatar or live assembly ScaleTo.
function Geometry.ApplyDetached(cart: Model, profile: any): (boolean, string?)
	local valid, reason = Geometry.Validate(profile)
	if not valid then return false, reason end
	if cart:GetAttribute("RuntimeCart") == true then return false, "Apply geometry before publishing a runtime cart" end
	local root, visual = cart:FindFirstChild("Root"), cart:FindFirstChild("Visual")
	if not root or not root:IsA("BasePart") or not visual or not visual:IsA("Model") then return false, "Missing root/visual" end
	local targets = {}
	local function target(parent: Instance, name: string, cf: CFrame, dimensions: Vector3?)
		local p = parent:FindFirstChild(name)
		if not p or not p:IsA("BasePart") then error("Missing semantic part "..name) end
		table.insert(targets, {Part=p, Frame=cf, Size=dimensions})
	end
	local ok, failure = pcall(function()
		target(cart,"DriverSeat",profile.DriverSeat.Frame,profile.DriverSeat.Size)
		-- Preserve an existing fitted marker as inert geometry; it is not required.
		if cart:FindFirstChild("HarpoonOrigin") and frame(profile.HarpoonOrigin) then
			target(cart,"HarpoonOrigin",profile.HarpoonOrigin,nil)
		end
		target(cart,"CameraTarget",profile.CameraTarget,nil)
		for _, tuple in {{"CargoSlots",profile.CargoSlots},{"FormationSlots",profile.FormationSlots}} do
			local folder=assert(cart:FindFirstChild(tuple[1]),"Missing slot folder")
			for i,cf in tuple[2] do target(folder,"Slot"..i,cf,nil) end
		end
		if profile.BodyMesh then local body=visual:FindFirstChild("Body",true);assert(body and body:IsA("BasePart"),"Missing authored body");if body:IsA("UnionOperation")then assert(frame(profile.BodyMesh.NativeCSGFrame)and frame(profile.BodyMesh.NativeCSGPivotOffset)and size(profile.BodyMesh.NativeCSGBindSize)and(body.Size-profile.BodyMesh.NativeCSGBindSize).Magnitude<0.01,"Native body CSG seed bind mismatch")end end
		for _, w in profile.Wheels do
			local p=visual:FindFirstChild(w.Name,true)
			assert(p and p:IsA("BasePart"),"Missing authored wheel "..w.Name)
			if p:IsA("UnionOperation")then assert(frame(w.NativeCSGPivotOffset)and size(w.NativeCSGBindSize)and(p.Size-w.NativeCSGBindSize).Magnitude<0.01,"Native wheel CSG seed bind mismatch")end
		end
	end)
	if not ok then return false,tostring(failure) end
	local moved = {}
	for _, t in targets do moved[t.Part]=true end
	for _, p in visual:GetDescendants() do if p:IsA("BasePart") then moved[p]=true end end
	for _, joint in cart:GetDescendants() do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			if joint.Part0==nil or joint.Part1==nil or moved[joint.Part0] or moved[joint.Part1] then joint:Destroy() end
		end
	end
	local colliderNames,wheelNames={},{}
	for _,c in profile.Colliders do colliderNames[c.Name]=true end
	for _,w in profile.Wheels do wheelNames[w.Name]=true end
	for _,p in visual:GetDescendants()do
		if p:IsA("BasePart")and ((p:GetAttribute("CartGeometryCollider")==true and not colliderNames[p.Name])or(type(p:GetAttribute("CartWheelName"))=="string"and not wheelNames[p.Name]))then p:Destroy()end
	end
	root.Size=profile.RootSize;root.Transparency=1;root.CanCollide=false;root.Massless=false;root.RootPriority=127
	if profile.RootPhysicalProperties then root.CustomPhysicalProperties=profile.RootPhysicalProperties end
	local function weld(p: BasePart)
		local w=Instance.new("WeldConstraint");w.Name="CartGeometryWeld";w.Part0=root;w.Part1=p;w.Parent=p
	end
	for _, t in targets do
		if t.Size then t.Part.Size=t.Size end
		t.Part.CFrame=root.CFrame*t.Frame;t.Part.Anchored=false;t.Part.Massless=true
		if t.Part.Name=="DriverSeat"then t.Part.Transparency=1;t.Part.CanCollide=false end
		weld(t.Part)
	end
	for _, c in profile.Colliders do
		local p=visual:FindFirstChild(c.Name,true)
		if not p then p=Instance.new("Part");p.Name=c.Name;p.Parent=visual end
		assert(p:IsA("BasePart"));p.Size=c.Size;p.CFrame=root.CFrame*c.Frame
		if p:IsA("Part") and c.Shape then p.Shape=c.Shape end
		p.Anchored=false;p.Massless=c.Massless~=false;p.CanCollide=true;p.CanTouch=false;p.CanQuery=true;p.Transparency=1
		if profile.ColliderPhysicalProperties then p.CustomPhysicalProperties=profile.ColliderPhysicalProperties end
		if c.TargetMass then
			local properties=profile.ColliderPhysicalProperties
			p.CustomPhysicalProperties=PhysicalProperties.new(1,properties.Friction,properties.Elasticity,properties.FrictionWeight,properties.ElasticityWeight)
			local unitMass=p:GetMass()
			assert(finite(unitMass)and unitMass>0,"Cannot calibrate authored native cylinder mass")
			local density=c.TargetMass/unitMass
			assert(density>=.01 and density<=100,"Authored contact density is outside physical limits")
			p.CustomPhysicalProperties=PhysicalProperties.new(density,properties.Friction,properties.Elasticity,properties.FrictionWeight,properties.ElasticityWeight)
		end
		p:SetAttribute("CartGeometryCollider",true);weld(p)
	end
	if profile.BodyMesh then
		local p=visual:FindFirstChild("Body",true) :: BasePart
		if not p:IsA("UnionOperation")then p.Size=profile.BodyMesh.BindSize end
		p.PivotOffset=bindPivot(profile.BodyMesh,p);p.CFrame=root.CFrame*bindFrame(profile.BodyMesh,p)
	end
	local wheelParts={}
	for _, w in profile.Wheels do
		local p=visual:FindFirstChild(w.Name,true) :: BasePart
		if not p:IsA("UnionOperation")then p.Size=w.BindSize end
		p.PivotOffset=bindPivot(w,p);p.CFrame=root.CFrame*w.Hub*p.PivotOffset:Inverse()
		p.Anchored=false;p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
		p:SetAttribute("CartWheelName",w.Name);wheelParts[p]=true
		local motor=Instance.new("Motor6D");motor.Name="CartWheel_"..w.Name;motor.Part0=root;motor.Part1=p;motor.C0=w.Hub;motor.C1=p.PivotOffset;motor.Parent=p
	end
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") and not wheelParts[p] and p:GetAttribute("CartGeometryCollider") ~= true then
			p.Anchored=false;p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;weld(p)
		end
	end
	cart:SetAttribute("CartGeometryId",profile.Id);cart:SetAttribute("CartGeometryRevision",profile.Revision)
	return Geometry.ValidateTemplate(cart)
end
return table.freeze(Geometry)
