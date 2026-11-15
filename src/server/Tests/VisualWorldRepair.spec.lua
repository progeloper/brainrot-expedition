--!nocheck
-- Six bounded behaviors, no profile/reward/entitlement writes.
return function()
    local Q=script.Parent
    local Policy=require(game.ReplicatedStorage.Shared.Utility.RegionPresentationPolicy)
    local Volume=require(game.ReplicatedStorage.Shared.Utility.CartCameraVolume)
    local Shell=require(game.ServerScriptService.Server.Utility.WorldVisualRepair)
    local Base=require(game.ServerScriptService.Server.Utility.Phase13BaseGeometry)
    local Gates=require(game.ReplicatedStorage.Shared.Utility.GateAccessPresentation)
    local Wheel=require(game.ReplicatedStorage.Shared.Utility.CartWheelMath)
    local function near(a,b,t)assert(math.abs(a-b)<(t or .001),tostring(a).." differs from "..tostring(b))end
    it("critical classification overrides locked-region distance without changing authored opacity",function()
        local map=Instance.new("Folder");map.Name="MapBlockout"
        local group=Instance.new("Model");group:SetAttribute("PresentationClass","CriticalBoundary");group.Parent=map
        local skin=Instance.new("Part");skin.CanCollide=false;skin.Transparency=.4;skin.Parent=group
        local inside,mandatory,class=Policy.Classify(skin)
        assert(inside and mandatory,"Visible noncolliding core must be critical")
        assert(Policy.StaticVisible("LOCKED","CAMP",{},mandatory,10000,350,class),"Critical shell cannot distance/access hide")
        near(skin.Transparency,.4)
        group:SetAttribute("PresentationClass","RegionDetail")
        inside,mandatory,class=Policy.Classify(skin)
        assert(not mandatory and not Policy.StaticVisible("LOCKED","CAMP",{},mandatory,1,350,class),"Optional locked detail remains culled")
        map:Destroy()
    end)
    it("uses closest oriented bounds and a wider, delayed detail release envelope",function()
        local frame=CFrame.new(100,0,0)*CFrame.Angles(0,math.pi/2,0)
        local point=frame:PointToWorldSpace(Vector3.new(99,0,0))
        near(Policy.DistanceToBounds(point,frame,Vector3.new(200,20,20)),0)
        local visible,deadline=Policy.OptionalVisible(true,nil,420,350,0)
        assert(visible and deadline==nil,"Quick turn margin must exceed 25 percent")
        visible,deadline=Policy.OptionalVisible(visible,deadline,450,350,0)
        assert(visible and deadline,"Outside geometry must wait before hiding")
        visible=Policy.OptionalVisible(visible,deadline,450,350,deadline+.01)
        assert(not visible,"Old optional detail should eventually release")
    end)
    it("keeps a camera volume clear of noncolliding walls and handles an initial overlap",function()
        local world=Instance.new("WorldModel");world.Name="IsolatedCameraWorld";world.Parent=Q
        local map=Instance.new("Folder");map.Name="MapBlockout";map.Parent=world
        local wall=Instance.new("Part");wall.Anchored=true;wall.CanCollide=false;wall.CanQuery=true
        wall.Size=Vector3.new(20,20,1);wall.CFrame=CFrame.new(0,6,3);wall.Parent=map
        local resolver=Volume.new({QueryRadius=.5,SurfaceBuffer=.25},world)
        local ok,why=xpcall(function()
            local r,e=resolver:Resolve(Vector3.new(0,6,0),Vector3.new(0,6,10),1/60,true,nil,nil)
            assert(r,e);assert(r.Obstructed and not resolver:Blocked(r.CorrectedPosition),"Noncolliding opaque wall must constrain camera")
            assert(#Volume.Candidates(Vector3.zero,Vector3.zAxis*20)==4,"Fallback search is bounded")
            local nextResult,err=resolver:Resolve(Vector3.new(0,6,3),Vector3.new(0,6,10),1/60,false,nil,nil)
            assert(nextResult,err);assert(nextResult.InitialOverlap and not resolver:Blocked(nextResult.CorrectedPosition),"Embedded origin must resolve to a clear volume")
            near(Volume.MinimumZoom(20),12)
        end,debug.traceback)
        resolver:Destroy();world:Destroy();assert(ok,why)
    end)
    it("builds one stable shell for a stepped source run and remains idempotent",function()
        local map=Instance.new("Folder");map.Name="MapBlockout";map.Parent=Q
        local art=Instance.new("Folder");art.Name="EnvironmentArt_V2";art.Parent=map
        for i=1,2 do
            local model=Instance.new("Model");model.Name="EV2_Run_01_Cliff_0"..i;model:SetAttribute("PrototypeId","CliffRun")
            local p=Instance.new("Part");p.Name="CliffRun_A";p:SetAttribute("ExportGroup","A");p:SetAttribute("EnvironmentRole","Visible")
            p.Size=Vector3.new(8,8+i*2,2);p.CFrame=CFrame.new((i-1)*8,5,0);p.Anchored=true;p.CanCollide=false;p.Parent=model;model.Parent=art
        end
        local ok,why=xpcall(function()
            local first=Shell.Apply(map);local core=map.NavigationShells.EV2_Run_01.Core
            assert(first.shellParts==1 and first.created==1,"Stepped modules must share one geometric shell")
            local again=Shell.Apply(map)
            assert(again.created==0 and core==map.NavigationShells.EV2_Run_01.Core,"Rebuild must not duplicate or replace unchanged core")
            assert(not core.CanCollide and core.CanQuery,"Original collision/access remains separate")
        end,debug.traceback)
        map:Destroy();assert(ok,why)
    end)
    it("repairs all eight shared base panel joins once while preserving support and gameplay anchors",function()
        local count=0
        for _,template in ipairs(game.ReplicatedStorage.CodeAssets.BaseDesigns:GetChildren())do if template:IsA("Model")then
            local clone=template:Clone();local panel=clone.Primary;local source=panel:GetAttribute("PanelJoinAuthoredSize")or panel.Size
            local supportFrame,supportSize=clone.Support.CFrame,clone.Support.Size
            local foundation,slot=clone.Foundation.CFrame,clone.Slot_01.CFrame
            Base.RepairPanelJoin(clone);local once=panel.Size;Base.RepairPanelJoin(clone)
            near((panel.Size-once).Magnitude,0);near(source.X-panel.Size.X,.24);near(source.Z-panel.Size.Z,.24)
            assert(clone.Support.CFrame==supportFrame and clone.Support.Size==supportSize,"Pillar/support geometry must be preserved")
            assert(clone.Foundation.CFrame==foundation and clone.Slot_01.CFrame==slot,"Plot/platform markers must not move")
            clone:Destroy();count+=1
        end end
        assert(count==8,"Eight actual design templates must be inspected")
    end)
    it("keeps gate views client-specific and accepts legitimate high-speed wheel travel",function()
        local function view()
            local m=Instance.new("Model");local p=Instance.new("Part");p.Name="DoorPresentation";p.CanCollide=false;p.Parent=m
            local gui=Instance.new("SurfaceGui");gui.Parent=p;local text=Instance.new("TextLabel");text.Parent=gui
            return m,p,gui
        end
        local a,closed,lock=view();local b,open,other=view()
        Gates.Apply(a,false,"Arctic");Gates.Apply(b,true,"Arctic")
        assert(closed.LocalTransparencyModifier==0 and lock.Enabled,"Locked view remains clear")
        assert(open.LocalTransparencyModifier==1 and not other.Enabled,"Unlocked view clears fully")
        assert(not closed.CanCollide and not open.CanCollide,"Local access presentation cannot change enforcement")
        Gates.Apply(b,false,"Arctic");assert(open.LocalTransparencyModifier==0,"Rebind uses current access state")
        local delta,reset=Wheel.Delta(CFrame.identity,CFrame.new(0,0,-108.9/30),CFrame.identity,Vector3.xAxis,2,1/30)
        assert(not reset and math.abs(delta)>1,"Legal Burst at 30 Hz must animate rather than teleport-reset wheels")
        a:Destroy();b:Destroy()
    end)
end
