--!strict
-- Bounded world-volume resolution, called only by the existing camera owner.
local Workspace=game:GetService("Workspace")
local Geometry=require(script.Parent.CartGeometry)
local Volume={}
function Volume.MinimumZoom(bodyLength: number): number return math.max(6,bodyLength/2+2)end
function Volume.Contains(frame: CFrame,size: Vector3,point: Vector3,padding: number): boolean
    local q=frame:PointToObjectSpace(point);local h=size/2+Vector3.one*padding
    return math.abs(q.X)<=h.X and math.abs(q.Y)<=h.Y and math.abs(q.Z)<=h.Z
end
function Volume.Candidates(focus: Vector3,desired: Vector3): {any}
    local rear=desired-focus
    local flat=Vector3.new(rear.X,0,rear.Z)
    local right=if flat.Magnitude>.001 then flat.Unit:Cross(Vector3.yAxis)else Vector3.xAxis
    return {{origin=focus,point=desired},{origin=focus+Vector3.yAxis*3,point=desired+Vector3.yAxis*5},
        {origin=focus+right*3+Vector3.yAxis*2,point=desired+right*4+Vector3.yAxis*2},
        {origin=focus-right*3+Vector3.yAxis*2,point=desired-right*4+Vector3.yAxis*2}}
end
local Methods={};Methods.__index=Methods
function Volume.new(config: any, worldRoot: WorldRoot?): any
    local world=worldRoot or Workspace
    local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.RespectCanCollide=false;ray.IgnoreWater=true
    local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.RespectCanCollide=false;overlap.MaxParts=8
    local probe=Instance.new("Part");probe.Name="CartCameraQueryVolume";probe.Shape=Enum.PartType.Ball
    probe.Size=Vector3.one*config.QueryRadius*2;probe.Transparency=1;probe.Anchored=true;probe.CanCollide=false;probe.CanQuery=false;probe.CanTouch=false;probe.CastShadow=false;probe.Parent=world
    local self=setmetatable({world=world,config=config,ray=ray,overlap=overlap,probe=probe,parts={},dirty=true,connections={},own={},faded={},cart=nil,character=nil,lastDistance=nil,lastKey=nil,limited=false},Methods)
    local map=world:FindFirstChild("MapBlockout")
    local function eligible(p)
        return p:IsA("BasePart")and p.Anchored and (p.CanCollide or p.Transparency<.95 or (p:GetAttribute("BaseAuthored_Transparency")or 1)<.95)
    end
    if map then
        for _,p in ipairs(map:GetDescendants())do if eligible(p)then self.parts[p]=true end end
        table.insert(self.connections,map.DescendantAdded:Connect(function(p)if eligible(p)then self.parts[p]=true;self.dirty=true end end))
        table.insert(self.connections,map.DescendantRemoving:Connect(function(p)if self.parts[p]then self.parts[p]=nil;self.dirty=true end end))
    end
    for _,p in ipairs(world:GetChildren())do if eligible(p)then self.parts[p]=true end end
    return self
end
function Methods:RestoreFade()
    for p,original in pairs(self.faded)do if p.Parent and p.LocalTransparencyModifier==.85 then p.LocalTransparencyModifier=original end end
    table.clear(self.faded)
end
function Methods:SetContext(cart: Model?,character: Model?)
    if self.cart==cart and self.character==character then return end
    self:RestoreFade();table.clear(self.own);self.cart,self.character=cart,character
    for _,model in ipairs({cart,character})do if model then for _,p in ipairs(model:GetDescendants())do
        if p:IsA("BasePart")and p.Transparency<.95 and not p:FindFirstAncestorWhichIsA("Tool")then table.insert(self.own,p)end
    end end end
end
function Methods:UpdateFilter()
    if not self.dirty then return end
    local list={}
    local terrain=self.world:FindFirstChildWhichIsA("Terrain")
    if terrain then table.insert(list,terrain)end
    for p in pairs(self.parts)do if p.Parent then table.insert(list,p)else self.parts[p]=nil end end
    self.ray.FilterDescendantsInstances=list;self.overlap.FilterDescendantsInstances=list;self.dirty=false
end
function Methods:Blocked(point: Vector3): boolean
    self.probe.CFrame=CFrame.new(point)
    -- Exact collision-volume overlap after broad phase; irregular mesh boxes
    -- alone never classify a camera as embedded in geometry.
    return #self.world:GetPartsInPart(self.probe,self.overlap)>0
end
function Methods:InsideRider(point: Vector3): boolean
    local cart=self.cart;local root=cart and cart:FindFirstChild("Root")
    if not root or not root:IsA("BasePart")then return false end
    local g=Geometry.Get(cart);local size=if g then g.BodySize else root.Size
    local body=if g then g.BodyFrame else CFrame.identity
    local top=math.max(body.Y+size.Y/2,7.8)
    local bottom=if g then g.Ground.BottomY else -2
    return Volume.Contains(root.CFrame*CFrame.new(body.X,(top+bottom)/2,body.Z),Vector3.new(size.X,top-bottom,size.Z),point,.65)
end
function Methods:Fade(point: Vector3,needed: boolean)
    self:RestoreFade()
    if not needed then return end
    for _,p in ipairs(self.own)do
        if p.Parent and Volume.Contains(p.CFrame,p.Size,point,1.25)then
            self.faded[p]=p.LocalTransparencyModifier;p.LocalTransparencyModifier=.85
        end
    end
end
function Methods:Resolve(origin: Vector3,desired: Vector3,dt: number,resync: boolean,cart: Model?,character: Model?): (any?,string?)
    self:SetContext(cart,character);self:UpdateFilter()
    local distance=(desired-origin).Magnitude
    if distance<.001 or distance~=distance then return nil,"Invalid camera segment"end
    local minimum=6
    local g=cart and Geometry.Get(cart)
    if g then minimum=Volume.MinimumZoom(g.BodySize.Z)end
    local choices=Volume.Candidates(origin,desired)
    local selected,compressed=nil,nil
    local hitPart,hitDistance=nil,nil
    local initialOverlap=false
    for key,candidate in ipairs(choices)do
        local start=candidate.origin;local delta=candidate.point-start;local length=delta.Magnitude
        local embedded=self:Blocked(start)
        if key==1 then initialOverlap=embedded end
        if embedded or length<.001 then continue end
        local hit=self.world:Spherecast(start,self.config.QueryRadius,delta,self.ray)
        local safe=if hit then math.max(0,hit.Distance-self.config.SurfaceBuffer)else length
        local point=start+delta.Unit*safe
        if self:Blocked(point)then continue end
        local row={key=key,origin=start,direction=delta.Unit,distance=safe,length=length,point=point,hit=hit}
        if not compressed or safe>compressed.distance then compressed=row end
        if safe>=minimum and not self:InsideRider(point)then selected=row;break end
    end
    selected=selected or compressed
    if not selected then
        -- All four sweep origins are obstructed. Keep a previously verified
        -- nearby point if possible; otherwise the tested clear focus is preferred.
        local point=self.lastPoint
        if not point or (point-origin).Magnitude>32 or self:Blocked(point)then point=origin+Vector3.yAxis*6 end
        if self:Blocked(point)then return nil,"No bounded clear camera volume"end
        selected={key=5,origin=point,direction=Vector3.yAxis,distance=0,length=0,point=point,hit=nil}
    end
    local safe=selected.distance
    -- Ease outward only while recovering from an obstruction. Growth of the
    -- desired distance itself is already eased by the camera owner; easing it
    -- again here made the view lag and pump whenever speed changed the framing.
    if not resync and self.limited and self.lastKey==selected.key and self.lastDistance and safe>self.lastDistance then
        safe=self.lastDistance+(safe-self.lastDistance)*(1-math.exp(-math.max(dt,0)/.15))
        if selected.distance-safe<=(self.config.DistanceTolerance or .05) then safe=selected.distance end
    end
    local point=selected.origin+selected.direction*safe
    -- Scalar recovery stays inside this frame's freshly swept clear prefix.
    -- One final containment check also covers a starting/streaming overlap.
    if self:Blocked(point)then point=selected.point;safe=selected.distance end
    if self:Blocked(point)then return nil,"Final camera volume obstructed"end
    self.lastDistance,self.lastKey,self.lastPoint=safe,selected.key,point
    self.limited=selected.hit~=nil or safe<selected.length
    local compromised=safe<minimum or self:InsideRider(point)
    self:Fade(point,compromised)
    if selected.hit then hitPart,hitDistance=selected.hit.Instance,selected.hit.Distance end
    return {CorrectedPosition=point,DesiredDistance=distance,CorrectedDistance=(point-origin).Magnitude,
        Obstructed=selected.hit~=nil or selected.key~=1,HitInstance=hitPart,HitDistance=hitDistance,
        MinimumCompromised=compromised,Recovering=safe<selected.distance,InitialOverlap=initialOverlap,
        QueryPerformed=true,QueryFailed=false,Failure=nil,FilterRevision=0,Candidate=selected.key},nil
end
function Methods:Reset()self:RestoreFade();self.lastDistance,self.lastKey,self.lastPoint,self.limited=nil,nil,nil,false end
function Methods:Destroy()
    self:Reset();for _,c in ipairs(self.connections)do c:Disconnect()end;table.clear(self.connections);self.probe:Destroy();table.clear(self.parts)
end
return Volume
