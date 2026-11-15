--!nocheck
-- Native assigned pad geometry + actual reset executor, assembly, occupancy,
-- terrain and stability owners. No real player or save is used.
return function()
 local Workspace=game:GetService("Workspace")
 local Physics=game:GetService("PhysicsService")
 local RS=game:GetService("ReplicatedStorage")
 local server=script.Parent.Parent
 local Placement=require(server.Utility.CartLocalPlacement)
 local Executor=require(server.Utility.CartResetExecutor)
 local Assembly=require(server.Services.CartAssemblyValidationService)
 local Occupants=require(server.Services.CartOccupantService)
 local Stability=require(server.Services.CartStabilityService)
 local Terrain=require(server.Services.CartTerrainService)
 local Validator=require(RS.Shared.Validation.CartAssemblyValidator)
 if not Physics:IsCollisionGroupRegistered("Carts")then Physics:RegisterCollisionGroup("Carts")end
 local sequence=0
 local function fixture(callback)
  sequence+=1 Placement.ResetQueryBudgetForTesting()
  local folder=Instance.new("Folder")folder.Name="Phase12AssignedReturnNative"folder.Parent=Workspace
  local origin=Vector3.new(40000+sequence*100,6000,40000)
  local base=Instance.new("Model")base.Name="NativeAssignedBase"base:SetAttribute("BaseId","NATIVE_ASSIGNMENT")base.Parent=folder
  local nativeMarker=Vector3.new(-132.399994,1.50000095,-204.732208)local offset=origin-nativeMarker
  local function surface(name,pos,size)
   local p=Instance.new("Part")p.Name=name p.Anchored=true p.Size=size p.CFrame=CFrame.new(pos+offset)
   p:SetAttribute("LayoutRole",name)p.Parent=base return p
  end
  surface("CartDisplay",Vector3.new(-132.4,.55,-204.732208),Vector3.new(27.2,1,36))
  surface("CartRamp",Vector3.new(-132.4,.55,-180.93),Vector3.new(24,1,12))
  surface("Foundation",Vector3.new(-95.27,.55,-226.46),Vector3.new(46.66,1,79.46))
  surface("HouseRamp",Vector3.new(-95.27,.55,-180.93),Vector3.new(20,1,12))
  local marker=surface("CartSpawn",nativeMarker,Vector3.one)
  marker.CanCollide,marker.CanQuery,marker.CanTouch=false,false,false
  marker:SetAttribute("Enabled",true)marker:SetAttribute("SpawnId","NATIVE_ASSIGNMENT_CART")marker:SetAttribute("CartId","CRT_001")
  local cart=Instance.new("Model")cart.Name="NativeEmptyCart"cart.Parent=folder
  cart:SetAttribute("RuntimeCart",true)cart:SetAttribute("CartId","CRT_001")
  cart:SetAttribute("SpawnId","NATIVE_ASSIGNMENT_CART")cart:SetAttribute("OwnerUserId",920001)
  local root=Instance.new("Part")root.Name="Root"root.Size=Vector3.new(4,2,6)
  root.CFrame=CFrame.new(origin+Vector3.new(60,10,0))root.RootPriority=127 root.CollisionGroup="Carts"root.Parent=cart cart.PrimaryPart=root
  for _,name in {"MovementAttachment","OrientationAttachment"}do local a=Instance.new("Attachment")a.Name=name a.Parent=root end
  local function mounted(name,parent,seat)
   local part=Instance.new(if seat then "VehicleSeat"else "Part")part.Name=name part.Size=Vector3.one
   part.Massless=true part.CanCollide=false part.CollisionGroup="Carts"part.CFrame=root.CFrame part.Parent=parent
   local weld=Instance.new("WeldConstraint")weld.Part0=root weld.Part1=part weld.Parent=part return part
  end
  mounted("DriverSeat",cart,true)mounted("CameraTarget",cart)
  local gun=mounted("HarpoonOrigin",cart)local muzzle=Instance.new("Attachment")muzzle.Name="MuzzleAttachment"muzzle.Parent=gun
  for _,kind in {"Cargo","Formation"}do local slots=Instance.new("Folder")slots.Name=kind.."Slots"slots.Parent=cart
   for i=1,if kind=="Cargo"then 3 else 6 do local slot=mounted("Slot"..i,slots)
    local a=Instance.new("Attachment")a.Name=kind.."Attachment"a.Parent=slot
   end
  end
  local visual=Instance.new("Model")visual.Name="Visual"visual.Parent=cart mounted("VisualBody",visual)
  local constraints=Instance.new("Folder")constraints.Name="Constraints"constraints.Parent=cart
  local player={UserId=920001,Character=nil}
  local currentBase=base
  local previous=Placement.Configure({Descriptors={GetRegionAtPosition=function()return nil end,GetGate=function()return nil end},
   Access={GetEffectiveAccess=function()return false end},CampContains=function()return true end,
   GetAssignedBase=function(p)return if p==player then currentBase else nil end})
  local identity={Base=base,Marker=marker,Player=player,CurrentBase=function()return currentBase end}
  local frame=marker.CFrame*CFrame.new(0,4,0)
  local ok,reason=xpcall(function()
   local valid,result,failure=Assembly:RegisterCart(cart)
   if not valid then local messages={}for _,issue in result.FatalErrors do table.insert(messages,Validator.FormatIssue(issue))end error(table.concat(messages,"; ")..tostring(failure))end
   pcall(function()Stability:SetFatalHandler(function(_cart,message)error(message)end)end)
   Stability:Start()Terrain:Start()
   local terrain,terrainReason=Terrain:RegisterCart(cart)assert(terrain,terrainReason)
   local stable,stableReason=Stability:RegisterCart(cart)assert(stable,stableReason)
   assert(Occupants:RegisterCart(cart,player.UserId))
   assert(Occupants:GetDriver(cart)==nil and #Occupants:GetOccupants(cart)==0,"Actual registered empty cart required")
   callback({cart=cart,root=root,base=base,marker=marker,frame=frame,identity=identity,folder=folder,
    setBase=function(value)currentBase=value end})
  end,debug.traceback)
  Occupants:UnregisterCart(cart,"native assigned QA")Assembly:ForgetCart(cart,"native assigned QA")
  Stability:UnregisterCart(cart,"native assigned QA")Terrain:UnregisterCart(cart,"native assigned QA")
  Placement.Configure(previous)folder:Destroy()assert(ok,reason)
 end
 describe("Phase 12 actual assigned empty-cart executor",function()
  it("returns a registered empty cart through real native support, recovery and server network ownership",function()
   fixture(function(f)
    local context={Assignment=f.identity,Validate=function()return true end}
    local accepted,reason,safe=Executor.ReturnAssignedForWipe(f.cart,f.frame,context)
    expect(reason).to.equal(nil)expect(accepted).to.equal(true)expect(safe).to.equal(true)
    expect(f.root.CFrame).to.equal(f.frame)expect(f.root.Anchored).to.equal(false)
    expect(f.root:GetNetworkOwner()).to.equal(nil)
    expect(Assembly:IsCartValid(f.cart)).to.equal(true)
    expect(type(f.cart:GetAttribute("LastServerReset"))).to.equal("number")
   end)
  end)
  it("blocked assigned support keeps exact cart pose and previous movement marker",function()
   fixture(function(f)
    local before=f.root.CFrame f.cart:SetAttribute("LastServerReset",123)
    local blocker=Instance.new("Part")blocker.Size=Vector3.new(6,4,8)blocker.CFrame=f.frame blocker.Anchored=true blocker.Parent=f.folder
    local accepted=Executor.ReturnAssignedForWipe(f.cart,f.frame,{Assignment=f.identity,Validate=function()return true end})
    expect(accepted).to.equal(false)expect(f.root.CFrame).to.equal(before)
    expect(f.cart:GetAttribute("LastServerReset")).to.equal(123)expect(f.root:GetNetworkOwner()).to.equal(nil)
   end)
  end)
  it("retired authority during suspension rolls back without publishing an assigned return",function()
   fixture(function(f)
    local before=f.root.CFrame f.cart:SetAttribute("LastServerReset",123)local calls=0
    local accepted=Executor.ReturnAssignedForWipe(f.cart,f.frame,{Assignment=f.identity,Validate=function()calls+=1 return calls<3 end})
    expect(accepted).to.equal(false)expect(f.root.CFrame).to.equal(before)
    expect(f.cart:GetAttribute("LastServerReset")).to.equal(123)expect(f.root:GetNetworkOwner()).to.equal(nil)
   end)
  end)
  it("unregistered empty-cart ownership rejects private return context without moving",function()
   fixture(function(f)
    local before=f.root.CFrame assert(Occupants:UnregisterCart(f.cart,"native context loss"))
    expect(Executor.ReturnAssignedForWipe(f.cart,f.frame,{Assignment=f.identity,Validate=function()return true end})).to.equal(false)
    expect(f.root.CFrame).to.equal(before)expect(f.cart:GetAttribute("LastServerReset")).to.equal(nil)
   end)
  end)
  it("changed base assignment rejects the exact pad without reopening manual reset",function()
   fixture(function(f)
    local before=f.root.CFrame f.setBase(nil)
    expect(Executor.ReturnAssignedForWipe(f.cart,f.frame,{Assignment=f.identity,Validate=function()return true end})).to.equal(false)
    expect(f.root.CFrame).to.equal(before)
    expect(Executor.Execute(f.cart,f.frame,nil)).to.equal(false)
    expect(f.root.CFrame).to.equal(before)
   end)
  end)
 end)
end
