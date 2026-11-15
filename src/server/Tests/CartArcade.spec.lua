--!nocheck
return function()
    local RS=game:GetService("ReplicatedStorage")
    local M=require(RS.Shared.Utility.CartHandlingMath)
    local C=require(RS.Shared.Config.CartHandlingConfig)
    local Profiles=require(RS.Shared.Utility.CartMovementProfileResolver)
    local Performance=require(RS.Shared.Utility.CartPerformanceResolver)
    local Team=require(RS.Shared.Utility.CartTeamPerformance)
    local Validation=require(RS.Shared.Utility.CartMovementValidationMath)
    local Visibility=require(RS.Shared.Utility.RegionPresentationPolicy)
    local function near(a,b,t) assert(math.abs(a-b)<(t or 1e-5),tostring(a).." differs from "..tostring(b)) end
    local function parameters() return {speed=C.StarterSpeed,acceleration=C.ForwardAcceleration,braking=C.Braking} end
    local function sample(velocity,intent,magnitude,grounded)
        return {normal=Vector3.yAxis,forward=Vector3.new(0,0,-1),velocity=velocity,supportVelocity=Vector3.zero,
            mass=42,gravity=196.2,intent=intent,magnitude=magnitude,grounded=grounded}
    end
    it("normalizes radial intent once, maps camera-local axes, and suspends automatic yaw during a gesture",function()
        local d,m=M.Shape(Vector2.new(.1,0));assert(d==Vector2.zero and m==0,"Arcade behavior assertion at source line 18")
        d,m=M.Shape(Vector2.new(1,1));near(d.Magnitude,1);near(m,1)
        local u,a=M.WorldIntent(Vector2.new(0,1),Vector3.new(1,0,0),Vector3.new(0,0,-1));near((u-Vector3.xAxis).Magnitude,0);near(a,1)
        u=M.WorldIntent(Vector2.new(1,0),Vector3.yAxis,Vector3.new(0,0,-1));near((u-Vector3.xAxis).Magnitude,0)
        assert(not M.ShouldRecenter(10,0,0,true,false),"Arcade behavior assertion at source line 22");assert(not M.ShouldRecenter(10,9.8,0,false,false),"Arcade behavior assertion at source line 22")
        assert(M.ShouldRecenter(10,9,8,false,false),"Arcade behavior assertion at source line 23");assert(not M.ShouldRecenter(10,9,9.5,false,false),"Arcade behavior assertion at source line 23")
    end)
    it("resolves real class, purchased and team/Burst modifiers once without a cargo penalty",function()
        local base=Profiles.Resolve("CRT_001");near(base.MaxTravelSpeed,math.max(48,C.OrdinaryWalkSpeed*2.5))
        local p=Performance.Resolve({status="Ready",userId=42,phase13={SpeedLevel=5}}, {cartId="CRT_008",ownerUserId=42})
        local result=Team.Resolve(p,{speedMultiplier=1.1,burstCapacity=8},true)
        near(result.resolvedSpeed,C.StarterSpeed*1.1*1.5*1.1*1.25)
        local effective=Profiles.Resolve("CRT_008",result)
        near(effective.ForwardAcceleration,100*result.resolvedSpeed/C.StarterSpeed)
        local loaded=table.clone(p);loaded.cargoCount=6
        near(Team.Resolve(loaded,{speedMultiplier=1.1,burstCapacity=8},true).resolvedSpeed,result.resolvedSpeed)
    end)
    it("has consistent time-based acceleration at 30/60/120 Hz and finite bounded stall recovery",function()
        local speeds={}
        for _,hz in ipairs({30,60,120}) do
            local v=Vector3.zero;local s={}
            for _=1,hz do local r=M.Step(s,sample(v,Vector3.new(0,0,-1),1,true),parameters(),1/hz);v+=r.force/42/hz end
            table.insert(speeds,v.Magnitude);assert(v.Magnitude>C.StarterSpeed*.97 and v.Magnitude<=C.StarterSpeed+.1,"Arcade behavior assertion at source line 40")
        end
        near(speeds[1],speeds[3],.5)
        local r=M.Step({},sample(Vector3.zero,Vector3.xAxis,1,true),parameters(),.35)
        assert(r.force==Vector3.zero and M.FiniteVector(r.heading),"Arcade behavior assertion at source line 44")
    end)
    it("brakes promptly, bounds yaw, and uses hysteresis for a genuine turnaround",function()
        local v=Vector3.new(0,0,-C.StarterSpeed);local s={};local elapsed,distance=0,0
        while v.Magnitude>=2 and elapsed<1 do
            local r=M.Step(s,sample(v,Vector3.zero,0,true),parameters(),1/120)
            v+=r.force/42/120;distance+=v.Magnitude/120;elapsed+=1/120
        end
        assert(elapsed<=.45 and distance<=12,"Arcade behavior assertion at source line 52")
        s={};local r=M.Step(s,sample(Vector3.new(0,0,-48),Vector3.zAxis,1,true),parameters(),1/60)
        assert(s.reversing and r.goal==0 and r.braking,"Arcade behavior assertion at source line 54")
        assert(math.abs(M.SignedAngle(Vector3.new(0,0,-1),r.heading,Vector3.yAxis))<=math.rad(300)/60+.001,"Arcade behavior assertion at source line 55")
        local function heading(angle) return CFrame.Angles(0,math.rad(angle),0).LookVector end
        M.Step(s,sample(Vector3.zero,heading(80),1,true),parameters(),1/60);assert(s.reversing,"Arcade behavior assertion at source line 57")
        M.Step(s,sample(Vector3.zero,heading(70),1,true),parameters(),1/60);assert(not s.reversing,"Arcade behavior assertion at source line 58")
    end)
    it("projects onto ramps without lift, removes inward wall force, and cannot propel in air",function()
        local n=Vector3.new(0,math.cos(math.rad(30)),math.sin(math.rad(30)))
        local a=sample(Vector3.zero,Vector3.new(0,0,-1),1,true);a.normal=n
        local r=M.Step({},a,parameters(),1/60);near(r.force:Dot(n),0,.001)
        assert(M.Walkable(n) and not M.Walkable(Vector3.xAxis),"Arcade behavior assertion at source line 64")
        a=sample(Vector3.zero,Vector3.new(0,0,-1),1,true);a.wallNormal=Vector3.zAxis
        r=M.Step({},a,parameters(),1/60);assert(r.force:Dot(a.wallNormal)>=-.001,"Arcade behavior assertion at source line 66")
        a.grounded=false;r=M.Step({},a,parameters(),1/60);assert(r.force==Vector3.zero,"Arcade behavior assertion at source line 67")
    end)
    it("clears pause/seat intent and requires a new gesture while rejecting stale packets",function()
        local raw,fresh=M.GestureGate(Vector2.yAxis,false,true);assert(raw==Vector2.zero and fresh,"Arcade behavior assertion at source line 70")
        raw,fresh=M.GestureGate(Vector2.yAxis,fresh,false);assert(raw==Vector2.zero and fresh,"Arcade behavior assertion at source line 71")
        raw,fresh=M.GestureGate(Vector2.zero,fresh,false);assert(not fresh,"Arcade behavior assertion at source line 72")
        raw,fresh=M.GestureGate(Vector2.yAxis,fresh,false);assert(raw==Vector2.yAxis,"Arcade behavior assertion at source line 73")
        local cart={};local packet={cart=cart,session=3,sequence=2,direction=Vector3.zAxis,magnitude=1,braking=false,paused=false}
        assert(M.ValidPacket(packet,cart,3,1),"Arcade behavior assertion at source line 75");assert(not M.ValidPacket(packet,cart,4,1),"Arcade behavior assertion at source line 75");assert(not M.ValidPacket(packet,cart,3,2),"Arcade behavior assertion at source line 75")
        packet.direction=Vector3.new(0/0,0,0);assert(not M.ValidPacket(packet,cart,3,1),"Arcade behavior assertion at source line 76")
    end)
    it("keeps authoritative driver/session checks and permits legal reversal/transverse inertia",function()
        assert(M.AuthorityMatches(42,42,42,7,7,true),"Arcade behavior assertion at source line 79")
        assert(not M.AuthorityMatches(7,42,42,7,7,true),"Arcade behavior assertion at source line 80");assert(not M.AuthorityMatches(42,42,7,7,7,true),"Arcade behavior assertion at source line 80")
        assert(not M.AuthorityMatches(42,42,42,7,8,true),"Arcade behavior assertion at source line 81");assert(not M.AuthorityMatches(42,42,42,7,7,false),"Arcade behavior assertion at source line 81")
        local profile=Profiles.Resolve("CRT_008")
        local limits=Validation.BuildThresholds(profile,require(RS.Shared.Config.CartMovementValidation))
        assert(limits.ForwardObservation>profile.MaxTravelSpeed and limits.ReverseObservation>profile.MaxTravelSpeed,"Arcade behavior assertion at source line 84")
        assert(limits.HorizontalSevere>profile.MaxTravelSpeed,"Arcade behavior assertion at source line 85")
        local Rig=require(RS.Shared.Utility.CartArcadeRig)
        local Geometry=require(RS.Shared.Utility.CartGeometry)
        local Validator=require(RS.Shared.Validation.CartAssemblyValidator)
        local count=0
        for _,template in ipairs(game.ReplicatedStorage.StudioAssets.Carts:GetChildren())do
            if template:IsA("Model")then
                local clone=template:Clone()
                local ok,err=xpcall(function()
                    Rig.Configure(clone)
                    local valid,reason=Geometry.ValidateTemplate(clone)
                    assert(valid,template.Name..":"..tostring(reason))
                    local result=Validator.Validate(clone,{Stage="Static"})
                    local codes={} for _,issue in ipairs(result.FatalErrors)do table.insert(codes,issue.Code..":"..issue.Message)end
                    assert(result.IsValid,template.Name..":"..table.concat(codes,","))
                end,debug.traceback)
                clone:Destroy();assert(ok,err);count+=1;task.wait()
            end
        end
        assert(count==9,"All nine real native templates must pass the adapter")
    end)
    it("reveals structural bounds before travel/braking distance with hysteresis and no region grant",function()
        near(Visibility.DistanceToBounds(Vector3.new(1,0,0),CFrame.new(100,0,0),Vector3.new(200,20,20)),0)
        local baseline=M.VisibleDistance(48,140,5)
        local top=M.VisibleDistance(108.9,140*108.9/48*.9,5.6)
        assert(top>baseline and baseline>48*2+48*48/(2*140)+5+24,"Arcade behavior assertion at source line 91")
        assert(Visibility.StaticVisible("LOCKED","CAMP",{},true,top-1,top),"Arcade behavior assertion at source line 92")
        assert(not Visibility.StaticVisible("LOCKED","CAMP",{},false,1,top),"Arcade behavior assertion at source line 93")
        -- The release band is the wider of ReleaseMarginStuds and 25% of the radius.
        local beyond=top+math.max(Visibility.ReleaseMarginStuds,top*0.25)+1
        local visible,deadline=Visibility.OptionalVisible(true,nil,beyond,top,0)
        assert(visible and deadline,"Arcade behavior assertion at source line 95")
        visible=Visibility.OptionalVisible(visible,deadline,beyond,top,deadline+.01);assert(not visible,"Arcade behavior assertion at source line 96")
    end)
end
