--!strict
-- One idempotent authoring/startup adapter. No frame loops or entitlement writes.
local RS=game:GetService("ReplicatedStorage")
local Theme=require(RS.Shared.Config.WorldVisualTheme)
local Surface=require(RS.Shared.Utility.PlaytestSurfacePolicy)
local FirstSession=require(RS.Shared.Config.FirstSessionVisuals)
local FirstSessionRules=require(RS.Shared.Utility.FirstSessionVisualRules)
local Repair={}
local regionFolders={"Camp","Forest","Beach","Swamp","Jungle","Arctic","Volcano","Glitch Zone"}
-- Region floor rectangles and the outer floor bounds, used only to choose facade
-- height (interior vs perimeter) and crest colour. Nothing here changes access.
local function floorLayout(map: Instance): any
    local rects,lo,hi={},nil,nil
    for _,name in ipairs(regionFolders)do
        local folder=map:FindFirstChild(name)
        if folder then for _,p in ipairs(folder:GetChildren())do
            if p:IsA("BasePart")and p.Name:match("^Floor_R%d+_C%d+$")then
                local a=p.Position-p.Size/2;local b=p.Position+p.Size/2
                table.insert(rects,{name=name,minX=a.X,maxX=b.X,minZ=a.Z,maxZ=b.Z,top=b.Y})
                lo=if lo then Vector3.new(math.min(lo.X,a.X),0,math.min(lo.Z,a.Z))else Vector3.new(a.X,0,a.Z)
                hi=if hi then Vector3.new(math.max(hi.X,b.X),0,math.max(hi.Z,b.Z))else Vector3.new(b.X,0,b.Z)
            end
        end end
    end
    local ground=map:GetAttribute("GroundSurfaceY")
    return {rects=rects,lo=lo,hi=hi,ground=if type(ground)=="number"then ground else 0}
end
local function regionAt(layout: any,point: Vector3): string?
    for _,r in ipairs(layout.rects)do
        if point.X>=r.minX and point.X<=r.maxX and point.Z>=r.minZ and point.Z<=r.maxZ then return r.name end
    end
    return nil
end
local function facadeTop(layout: any,frame: CFrame): number
    local f=FirstSession.Facade
    local p=frame.Position
    local perimeter=layout.lo~=nil and(
        p.X-layout.lo.X<=f.PerimeterBand or layout.hi.X-p.X<=f.PerimeterBand
        or p.Z-layout.lo.Z<=f.PerimeterBand or layout.hi.Z-p.Z<=f.PerimeterBand)
    return layout.ground+(if perimeter then f.PerimeterHeight else f.InteriorHeight)
end
local started=false
local connections={}
local function calm(part: BasePart,color: Color3)
    if part:GetAttribute("VisualRepairOriginalMaterial")==nil then
        part:SetAttribute("VisualRepairOriginalMaterial",part.Material.Name)
        part:SetAttribute("VisualRepairOriginalVariant",part.MaterialVariant)
    end
    local physical=part.CurrentPhysicalProperties
    part.Material,part.MaterialVariant,part.Color=Enum.Material.SmoothPlastic,"",color
    part.TopSurface,part.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    if not part.CustomPhysicalProperties then part.CustomPhysicalProperties=physical end
    part:SetAttribute("VisualRepairRevision",Theme.Version)
end
local function label(part: BasePart,name: string,text: string,face: Enum.NormalId)
    local gui=part:FindFirstChild(name) :: SurfaceGui?
    if not gui then gui=Instance.new("SurfaceGui");gui.Name=name;gui.Face=face;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=24;gui.LightInfluence=0;gui.MaxDistance=500;gui.Parent=part end
    gui.Adornee=part;gui.ZOffset=.1
    local textLabel=gui:FindFirstChild("Text") :: TextLabel?
    if not textLabel then textLabel=Instance.new("TextLabel");textLabel.Name="Text";textLabel.Size=UDim2.fromScale(1,1);textLabel.BackgroundTransparency=1;textLabel.TextScaled=true;textLabel.Font=Enum.Font.FredokaOne;textLabel.TextColor3=Color3.fromRGB(255,245,218);textLabel.TextStrokeTransparency=0.15;textLabel.Parent=gui end
    textLabel.Text=text
end
local function visibleBox(model: Model): (CFrame?,Vector3?)
    local first: BasePart?=nil
    for _,x in ipairs(model:GetChildren())do if x:IsA("BasePart")and x:GetAttribute("ExportGroup")=="A" then first=x;break end end
    if not first then return nil end
    local base=first.CFrame
    local lo,hi=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
    for _,x in ipairs(model:GetChildren())do
        if x:IsA("BasePart")and x:GetAttribute("EnvironmentRole")=="Visible" then
            for _,sx in ipairs({-1,1})do for _,sy in ipairs({-1,1})do for _,sz in ipairs({-1,1})do
                local q=base:PointToObjectSpace(x.CFrame:PointToWorldSpace(x.Size*Vector3.new(sx,sy,sz)/2))
                lo=Vector3.new(math.min(lo.X,q.X),math.min(lo.Y,q.Y),math.min(lo.Z,q.Z))
                hi=Vector3.new(math.max(hi.X,q.X),math.max(hi.Y,q.Y),math.max(hi.Z,q.Z))
            end end end
        end
    end
    return base*CFrame.new((lo+hi)/2),hi-lo
end
local function corePart(frame: CFrame,size: Vector3): Part
    local p=Instance.new("Part");p.CFrame=frame;p.Size=size;p.Anchored=true
    p.CanCollide,p.CanTouch,p.CanQuery=false,false,true
    p:SetAttribute("PresentationClass","CriticalBoundary")
    calm(p,Theme.Wall)
    return p
end
local function persistent(parent: Instance,name: string): Model
    local model=parent:FindFirstChild(name) :: Model?
    if not model then model=Instance.new("Model");model.Name=name;model.Parent=parent end
    assert(model:IsA("Model"),"Visual shell model name conflict")
    model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
    model:SetAttribute("PresentationClass","CriticalBoundary")
    model:SetAttribute("GlobalNavigationFacade",true)
    model:SetAttribute("VisualRepairOwner",Theme.Version)
    return model
end
function Repair.Apply(map: Instance): any
    local art=map:FindFirstChild("EnvironmentArt_V2")
    assert(art,"Missing authored environment")
    local shells=map:FindFirstChild("NavigationShells")
    if not shells then shells=Instance.new("Folder");shells.Name="NavigationShells";shells.Parent=map end
    local groups: {[string]: {Model}}={}
    for _,model in ipairs(art:GetChildren())do
        local kind=model:GetAttribute("PrototypeId")
        if model:IsA("Model")and(kind=="CliffRun"or kind=="GateLintel")then
            local key=if kind=="CliffRun"then model.Name:match("^(EV2_Run_%d+)")or model.Name else model.Name
            groups[key]=groups[key]or {};table.insert(groups[key],model)
        end
    end
    local count,created=0,0
    local layout=floorLayout(map)
    local facade=FirstSession.Facade
    local keys={} for key in pairs(groups)do table.insert(keys,key)end table.sort(keys)
    for _,key in ipairs(keys)do
        local group=groups[key]
        local owner=persistent(shells,key)
        table.sort(group,function(a,b)return a.Name<b.Name end)
        local sourceKeys={}
        for _,model in ipairs(group)do local frame,size=visibleBox(model);table.insert(sourceKeys,model.Name..":"..tostring(frame)..":"..tostring(size))end
        -- Facade heights are part of the shell identity so a height change rebuilds once.
        table.insert(sourceKeys,FirstSession.Version..":"..facade.InteriorHeight..":"..facade.PerimeterHeight)
        local fingerprint=table.concat(sourceKeys,"|")
        local core=owner:FindFirstChild("Core") :: BasePart?
        local oldCore=core
        if not core or owner:GetAttribute("SourceGeometryKey")~=fingerprint then
            local pieces,boxes={},{}
            for _,model in ipairs(group)do
                local frame,size=visibleBox(model)
                assert(frame and size,"Missing authored boundary bounds: "..model.Name)
                local clippedFrame,clippedSize=FirstSessionRules.ClipBoxTop(frame,size,facadeTop(layout,frame))
                if clippedFrame and clippedSize then
                    table.insert(pieces,corePart(clippedFrame,clippedSize))
                    table.insert(boxes,{frame=clippedFrame,size=clippedSize})
                end
            end
            for _,old in ipairs(owner:GetChildren())do if old.Name=="FacadeCrest"then old:Destroy()end end
            -- Region-themed crest on each lowered facade piece.
            for _,box in ipairs(boxes)do
                local crest=Instance.new("Part");crest.Name="FacadeCrest";crest.Anchored=true
                crest.CanCollide,crest.CanTouch,crest.CanQuery=false,false,true;crest.CastShadow=false
                crest.Size=Vector3.new(box.size.X+facade.CrestOverhang*2,facade.CrestThickness,box.size.Z+facade.CrestOverhang*2)
                crest.CFrame=box.frame*CFrame.new(0,box.size.Y/2+facade.CrestThickness/2-0.4,0)
                local region=regionAt(layout,box.frame.Position)
                crest.Color=if region then facade.CrestColours[region]or facade.NeutralCrest else facade.NeutralCrest
                crest.Material=Enum.Material.SmoothPlastic
                crest.TopSurface,crest.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
                crest:SetAttribute("PresentationClass","CriticalBoundary");crest:SetAttribute("FirstSessionVisuals",FirstSession.Version)
                crest.Parent=owner
            end
            local first=table.remove(pieces,1)
            assert(first,"Empty boundary group")
            if #pieces>0 then
                local staging=Instance.new("Folder");staging.Name="VisualRepairCSGInputs";staging.Parent=game:GetService("ServerStorage")
                first.Parent=staging;for _,p in ipairs(pieces)do p.Parent=staging end
                local ok,result=pcall(function()return first:UnionAsync(pieces,Enum.CollisionFidelity.Box,Enum.RenderFidelity.Performance)end)
                if not ok then staging:Destroy();error("Boundary shell union failed: "..key..":"..tostring(result))end
                core=result :: BasePart;staging:Destroy()
            else core=first end
            core.Name="Core";core.Anchored=true;core.CanCollide=false;core.CanTouch=false;core.CanQuery=true
            core:SetAttribute("BoundaryId",key);core:SetAttribute("PresentationClass","CriticalBoundary")
            calm(core,Theme.Wall)
            if core:IsA("UnionOperation")then core.UsePartColor=true end
            core.Parent=owner;if oldCore then oldCore:Destroy()end;owner:SetAttribute("SourceGeometryKey",fingerprint);created+=1
        end
        count+=1
        -- Replace the visible skin only after a complete geometric shell exists.
        for _,model in ipairs(group)do for _,x in ipairs(model:GetDescendants())do
            if x:IsA("BasePart")and x:GetAttribute("EnvironmentRole")=="Visible"then
                if x:GetAttribute("VisualRepairAuthoredTransparency")==nil then x:SetAttribute("VisualRepairAuthoredTransparency",x.Transparency)end
                x.Transparency=1;x:SetAttribute("PresentationClass","RegionDetail")
            end
        end end
        task.wait() -- one bounded group, never one unyielding map mutation
    end
    for _,old in ipairs(shells:GetChildren())do
        if old:GetAttribute("VisualRepairOwner")==Theme.Version and not groups[old.Name]then old:Destroy()end
    end
    -- Gate aperture closure bricks above the interior facade height are hidden so the
    -- lowered walls stay level; the authored transparency is recorded and restorable.
    local closures=map:FindFirstChild("GateApertureClosures")
    local hiddenClosures=0
    if closures then
        local capY=layout.ground+facade.InteriorHeight
        for _,p in ipairs(closures:GetDescendants())do
            if p:IsA("BasePart")then
                local authored=p:GetAttribute("FirstSessionAuthoredTransparency")
                local bottom=p.Position.Y-p.Size.Y/2
                if bottom>=capY-0.5 then
                    if authored==nil then p:SetAttribute("FirstSessionAuthoredTransparency",p.Transparency)end
                    p.Transparency=1;hiddenClosures+=1
                elseif type(authored)=="number"then
                    p.Transparency=authored;p:SetAttribute("FirstSessionAuthoredTransparency",nil)
                end
            end
        end
    end
    local gates=map:FindFirstChild("ProgressionGates")
    local lights=0
    if gates then for _,gate in ipairs(gates:GetChildren())do
        if not gate:IsA("Model")then continue end
        local color=Theme.GateColors[gate.Name]
        if not color then continue end
        local owner=persistent(gate,"NavigationCore")
        for _,name in ipairs({"SupportLeft","SupportRight","Lintel"})do
            local p=gate:FindFirstChild(name)or owner:FindFirstChild(name)
            if p and p:IsA("BasePart")then calm(p,color);p:SetAttribute("PresentationClass","CriticalBoundary");p.Parent=owner;count+=1 end
        end
        local lintel=owner:FindFirstChild("Lintel") :: BasePart?
        if lintel then
            label(lintel,"RegionFront",gate.Name:upper(),Enum.NormalId.Front)
            label(lintel,"RegionBack",gate.Name:upper(),Enum.NormalId.Back)
            local light=lintel:FindFirstChild("EntranceFill") :: PointLight?
            if not light then light=Instance.new("PointLight");light.Name="EntranceFill";light.Parent=lintel end
            light.Range,light.Brightness,light.Shadows=20,0.35,false;light.Color=Color3.fromRGB(225,218,245);lights+=1
        end
        local landmarks=gate:FindFirstChild("RouteLandmarks")
        if not landmarks then
            landmarks=Instance.new("Folder");landmarks.Name="RouteLandmarks"
            local prototypes={Jungle="Broadleaf",Swamp="SwampTree",Arctic="ArcticIgloo",Volcano="VolcanoMassif",Beach="Palm",GlitchZone="GlitchTemple"}
            local source: BasePart?=nil
            for _,model in ipairs(art:GetChildren())do
                if model:GetAttribute("PrototypeId")==prototypes[gate.Name]then
                    for _,p in ipairs(model:GetChildren())do if p:IsA("MeshPart")and p:GetAttribute("ExportGroup")=="A"then source=p;break end end
                end
                if source then break end
            end
            if source and lintel then for i=1,3 do
                local p=source:Clone();p.Name="BiomeMotif_"..i;p.Size=source.Size*(4.5/math.max(source.Size.X,source.Size.Y,source.Size.Z))
                p.CFrame=lintel.CFrame*CFrame.new((i-2)*8,lintel.Size.Y/2+p.Size.Y/2,0)
                p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
                p:SetAttribute("PresentationClass","CriticalBoundary");p.Parent=landmarks
            end end
            landmarks.Parent=gate
        end
        -- Route-facing gate identity remains readable while locked interiors cull.
        for _,p in ipairs(landmarks:GetDescendants())do if p:IsA("BasePart")then p:SetAttribute("PresentationClass","CriticalBoundary")end end
        local door=gate:FindFirstChild("DoorPresentation") :: BasePart?
        if door then
            calm(door,color:Lerp(Color3.fromRGB(35,27,43),0.4));door.Transparency=0.08
            door:SetAttribute("VisibilityOwner","GateAccess")
            label(door,"LockFront","LOCKED\n"..gate.Name:upper(),Enum.NormalId.Front)
            label(door,"LockBack","LOCKED\n"..gate.Name:upper(),Enum.NormalId.Back)
        end
    end end
    assert(count<=Theme.ShellLimit,"Persistent boundary budget exceeded: "..tostring(count))
    assert(lights<=6,"Entrance fill budget exceeded")
    local paths=map:FindFirstChild("Paths")
    local calmCount=0
    for _,p in ipairs(map:GetDescendants())do
        if p:IsA("BasePart")then
            local role=p:GetAttribute("LayoutRole")
            if role=="Floor"and p:GetAttribute("GeneratedBy")=="CreateBasicMap_v1"then
                calm(p,Theme.Grass);p:SetAttribute("PresentationClass","CriticalRoute");calmCount+=1
            elseif paths and p:IsDescendantOf(paths)then
                calm(p,Theme.Path);p:SetAttribute("PresentationClass","CriticalRoute");calmCount+=1
            end
        end
    end
    Surface.ApplyMap()
    map:SetAttribute("VisualRepairVersion",Theme.Version)
    map:SetAttribute("PersistentShellParts",count)
    return {shellParts=count,created=created,entranceLights=lights,calmSurfaces=calmCount,hiddenClosures=hiddenClosures}
end
function Repair.Start(map: Instance)
    if started then return end
    Repair.Apply(map)
    local cartTemplates=RS:FindFirstChild("StudioAssets")and RS.StudioAssets:FindFirstChild("Carts")
    if cartTemplates then for _,cart in ipairs(cartTemplates:GetChildren())do Surface.ApplyCart(cart)end end
    local BaseGeometry=require(script.Parent.Phase13BaseGeometry)
    local templates=RS:FindFirstChild("CodeAssets")and RS.CodeAssets:FindFirstChild("BaseDesigns")
    if templates then for _,base in ipairs(templates:GetChildren())do if base:IsA("Model")then BaseGeometry.RepairPanelJoin(base)end end end
    local bases=map:FindFirstChild("PlayerBasePatches")
    if bases then for _,base in ipairs(bases:GetChildren())do if base:IsA("Model")then BaseGeometry.RepairPanelJoin(base)end end end
    local pending=false
    local function changed(x)
        if not x:IsA("Model")then return end
        local prototype=x:GetAttribute("PrototypeId")
        if prototype~="CliffRun"and prototype~="GateLintel"and x.Parent~=map:FindFirstChild("ProgressionGates")then return end
        if prototype=="CliffRun"or prototype=="GateLintel"then x:SetAttribute("PresentationClass","CriticalBoundary")end
        if pending then return end
        pending=true
        task.defer(function()
            if not started then pending=false;return end
            local ok,why=pcall(Repair.Apply,map);pending=false
            if not ok then warn("World visual rebuild failed: "..tostring(why))end
        end)
    end
    table.insert(connections,map.DescendantAdded:Connect(changed))
    table.insert(connections,map.DescendantRemoving:Connect(changed))
    if templates then table.insert(connections,templates.ChildAdded:Connect(function(base)
        if base:IsA("Model")then BaseGeometry.RepairPanelJoin(base)end
    end))end
    started=true
end
function Repair.Stop()
    started=false
    for _,connection in ipairs(connections)do connection:Disconnect()end
    table.clear(connections)
end
return Repair
