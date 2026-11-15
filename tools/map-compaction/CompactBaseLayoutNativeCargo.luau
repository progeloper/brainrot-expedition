--!nocheck
-- Native isolated maximum current released cargo projection. No vehicle/profile/service startup.
local A={}
local function box(model,reference,visibleScale)
 local low,high=Vector3.one*math.huge,Vector3.one*-math.huge;local parts,native=0,0
 for _,part in model:GetDescendants()do
  if part:IsA("BasePart")and(not visibleScale or visibleScale.IsVisualPart(part,model))then
   local cf,size=part.CFrame,part.Size
   if part:IsA("PartOperation")then cf,size=part.ExtentsCFrame,part.ExtentsSize;native+=1 end
   local frame=reference:ToObjectSpace(cf);local half=size/2
   for _,x in {-1,1}do for _,y in {-1,1}do for _,z in {-1,1}do local point=frame*(half*Vector3.new(x,y,z));low=low:Min(point);high=high:Max(point)end end end
   parts+=1
  end
 end
 assert(parts>0,"No measured native parts")
 return low,high,parts,native
end
local function plain(low,high)return{min={low.X,low.Y,low.Z},max={high.X,high.Y,high.Z},size={high.X-low.X,high.Y-low.Y,high.Z-low.Z},centre={(high.X+low.X)/2,(high.Y+low.Y)/2,(high.Z+low.Z)/2}}end
local function strip(clone)
 local nodes=clone:GetDescendants();table.insert(nodes,clone)
 for _,node in nodes do
  for _,tag in game:GetService("CollectionService"):GetTags(node)do game:GetService("CollectionService"):RemoveTag(node,tag)end
  if node:IsA("LuaSourceContainer")then node:Destroy()end
  if node:IsA("BasePart")then node.Anchored=true;node.CanCollide=false;node.CanTouch=false;node.CanQuery=false end
 end
end
function A.Measure(stage,deps)
 local cart=assert(game.ReplicatedStorage.StudioAssets.Carts:FindFirstChild("ScrapChariot")):Clone();cart.Parent=stage;strip(cart)
 local root=cart:GetPivot();local cartLow,cartHigh,cartParts=box(cart,root,nil)
 local allLow,allHigh=cartLow,cartHigh
 local report={scope="Native source-exact factory + current four authored cargo attachment poses",mode="IsolatedEditProjection",cartSource="ReplicatedStorage.StudioAssets.Carts.ScrapChariot",canonicalCartScale=cart:GetScale(),canonicalCartPivot={root:GetComponents()},cartAllBaseParts=cartParts,cartAllPartBounds=plain(cartLow,cartHigh),eligibility="Current captured catalog Live and spawnEnabled=true",capacityScope="Four current authored slots; Cargo1 released maximum, Cargo2 deferred excluded",species={},nativeFactoryCalls=0,nativeMountPoseCalls=0,originalSourceWrites=0,originalObjectWrites=0,gameplayAcceptance=false}
 local definitions=deps.Catalog.GetAll();table.sort(definitions,function(a,b)return a.id<b.id end)
 for _,definition in definitions do
  if definition.launchStatus=="Live"and definition.spawnEnabled==true then
   local visual=assert(deps.Factory:CreateItemVisual(definition.id),"Factory failed "..definition.id);visual.Parent=stage;strip(visual)
   local entry={id=definition.id,scale=visual:GetScale(),visibleHeight=deps.Scale.GetVisualHeight(visual),slots={}}
   local pivotBoundsLow,pivotBoundsHigh=box(visual,visual:GetPivot(),deps.Scale)
   entry.canonicalNativeGroundPivotBounds=plain(pivotBoundsLow,pivotBoundsHigh)
   report.nativeFactoryCalls+=1
   for index=1,4 do
    local slot=assert(cart.CargoSlots:FindFirstChild("Slot"..index));local attachment=assert(slot:FindFirstChild("CargoAttachment"))
    assert(attachment:IsA("Attachment"),"Expected actual cargo attachment")
    -- Exact current mountCargoVisual geometry expression; no additional height/facing/scale.
    local frame=attachment.WorldCFrame
    visual:PivotTo(frame)
    local low,high,count,native=box(visual,root,deps.Scale)
    allLow=allLow:Min(low);allHigh=allHigh:Max(high)
    local loadedLow,loadedHigh=cartLow:Min(low),cartHigh:Max(high)
    table.insert(entry.slots,{index=index,frame={frame:GetComponents()},nativeVisibleBounds=plain(low,high),loadedBounds=plain(loadedLow,loadedHigh),visibleParts=count,nativePartOperations=native})
    report.nativeMountPoseCalls+=1
   end
   table.insert(report.species,entry);visual:Destroy();task.wait()
  end
 end
 report.releasedSpeciesCount=#report.species
 report.maximumLoadedEnvelope=plain(allLow,allHigh)
 report.centredCartPadRequired={width=2*(math.max(math.abs(allLow.X),math.abs(allHigh.X))+2),depth=2*(math.max(math.abs(allLow.Z),math.abs(allHigh.Z))+2),marginEachSide=2,poseOrigin="Unchanged actual cart ground/root pivot in its spawn facing frame"}
 report.poseOnlyProjection=true;report.drivingTurningAcceptance=false
 cart:Destroy()
 return report
end
return A
