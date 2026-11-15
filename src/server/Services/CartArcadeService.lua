--!strict
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Config=require(RS.Shared.Config.CartHandlingConfig)
local Math=require(RS.Shared.Utility.CartHandlingMath)
local Rig=require(RS.Shared.Utility.CartArcadeRig)
local Names=require(RS.Shared.Constants.RemoteNames)
local Occupants=require(script.Parent.CartOccupantService)
local Service={}
local records: {[Model]: any}={}
local connections: {RBXScriptConnection}={}
local started=false
local function handoff(cart: Model, old: Player?, driver: Player?, reason: string, revision: number)
    local r=records[cart] if not r then return end
    -- Always visible: a seated driver losing control is otherwise silent in Production.
    if old and not driver then print(("[CartArcade] Driver released Cart=%s User=%d Reason=%s SinceLastPacket=%.2fs"):format(cart.Name,old.UserId,tostring(reason),os.clock()-r.lastAt)) end
    r.driver,r.session,r.sequence,r.lastAt,r.elapsed=driver,revision,0,os.clock(),0
    r.rateAt,r.rateCount=r.lastAt,0
    if driver then r.leaseLost=nil end
    r.physics.force.Force=Vector3.zero
    r.physics.orientation.Enabled=false
    r.physics.heading=Math.Unit(Math.Project(r.physics.root.CFrame.LookVector,Vector3.yAxis),Vector3.new(0,0,-1))
    r.physics.reversing=false
    cart:SetAttribute("CartDriveBraking",true)
    cart:SetAttribute("CartDrivePaused",false)
    cart:SetAttribute("CartDriveSession",revision) -- after actuator handoff
end
function Service:RegisterCart(cart: Model, profile: any): (boolean,string?)
    if records[cart] then return false,"cart already registered" end
    local physics=Rig.CreateState(cart,nil)
    records[cart]={physics=physics,parameters=Rig.Parameters(profile),profile=profile,driver=nil,session=0,sequence=0,lastAt=os.clock(),elapsed=0,rateAt=0,rateCount=0}
    cart:SetAttribute("CartDriveSession",Occupants:GetDriverRevision(cart) or 0)
    handoff(cart,nil,Occupants:GetDriver(cart),"initial",Occupants:GetDriverRevision(cart) or 0)
    return true,nil
end
function Service:UpdateProfile(cart: Model, profile: any): (boolean,string?)
    local r=records[cart] if not r then return false,"cart motor not registered" end
    r.profile,r.parameters=profile,Rig.Parameters(profile)
    r.physics=Rig.CreateState(cart,r.driver and r.driver.Character)
    return true,nil
end
function Service:UnregisterCart(cart: Model, _reason: string?): boolean
    local r=records[cart] if not r then return false end
    records[cart]=nil
    if cart.Parent then Rig.Suspend(r.physics) end
    return true
end
function Service:AcceptIntent(player: Player, packet: any): boolean
    local cart=type(packet)=="table" and packet.cart
    local r=cart and records[cart]
    if r and r.driver==nil and r.leaseLost==player and packet.resume==true then
        -- The seated owner outlived a lease expiry (client hitch). Re-run the
        -- ordinary seat validation; at most once a second.
        local now=os.clock()
        if now-(r.resumeAt or 0)>=1 then r.resumeAt=now;print(("[CartArcade] Driver lease resume requested Cart=%s User=%d"):format(cart.Name,player.UserId));Occupants:RefreshOccupancy(cart,"arcade drive lease resumed") end
        return false
    end
    if not r or r.driver~=player or not Occupants:IsDriver(player,cart)
        or not Math.AuthorityMatches(player.UserId,Occupants:GetOwnerUserId(cart),r.driver.UserId,r.session,Occupants:GetDriverRevision(cart),cart.Parent~=nil)
        or not Math.ValidPacket(packet,cart,r.session,r.sequence) then return false end
    local now=os.clock()
    if now-r.rateAt>=1 then r.rateAt,r.rateCount=now,0 end
    r.rateCount+=1 if r.rateCount>25 then return false end
    r.sequence,r.lastAt=packet.sequence,now
    local allowed=Occupants:CanPlayerControlCart(player,cart)
    local character=player.Character
    local tool=character and character:FindFirstChildWhichIsA("Tool")
    local hunting=tool and (tool.Name=="Hunting" or tool.Name=="SleepLauncher" or tool:GetAttribute("BrainrotSleepLauncher")==true)
    local paused=not allowed or hunting==true or packet.paused
    cart:SetAttribute("CartDrivePaused",paused)
    cart:SetAttribute("CartDriveBraking",paused or packet.braking)
    return true
end
function Service:Start()
    if started then return end started=true
    local folder=RS:WaitForChild("Remotes",10) assert(folder,"Missing remotes")
    local remote=folder:FindFirstChild(Names.CartDriveIntent)
    if not remote then remote=Instance.new("RemoteEvent");remote.Name=Names.CartDriveIntent;remote.Parent=folder end
    assert(remote:IsA("RemoteEvent"),"CartDriveIntent type conflict")
    table.insert(connections,remote.OnServerEvent:Connect(function(player,packet) self:AcceptIntent(player,packet) end))
    table.insert(connections,Occupants.DriverChanged:Connect(handoff))
    table.insert(connections,Run.PreSimulation:Connect(function(dt)
        local now=os.clock()
        for cart,r in pairs(records) do
            if not cart.Parent then records[cart]=nil;continue end
            if r.driver then
                -- The server observes the driver lease; it never drives the
                -- same actuator targets while that player owns the mechanism.
                local reset=cart:GetAttribute("ResetActive")==true
                local dazed=(r.driver:GetAttribute("Phase10DazeEnd") or 0)>workspace:GetServerTimeNow()
                if reset or dazed then r.lastAt=now
                elseif now-r.lastAt>Config.LeaseSeconds then r.leaseLost=r.driver;Occupants:RevokeControl(cart,"stale arcade drive session") end
            else
                r.elapsed+=dt
                if r.elapsed>=0.1 and cart:GetAttribute("ResetActive")~=true then
                    Rig.Step(r.physics,r.parameters,Vector3.zero,0,math.min(r.elapsed,Config.MaximumFrameGap),5)
                    r.elapsed=0
                end
            end
        end
    end))
end
function Service:GetDiagnostics(): any
    local count=0 for _ in pairs(records) do count+=1 end
    return {Registered=count,Connections=#connections,ClientWriterDuringDriving=true,LegacyLongitudinalGate=false}
end
return Service
