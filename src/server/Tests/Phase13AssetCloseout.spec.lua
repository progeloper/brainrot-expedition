--!nocheck
-- Source-only native instances, fake profiles, no game boot or DataStore access.
return function()
 local RS=game:GetService("ReplicatedStorage")
 local Rules=require(RS.Shared.Utility.Phase13AppearanceRules)
 local Roles=require(RS.Shared.Utility.Phase13FinishRoles)
 local Definitions=require(RS.Shared.Config.Phase13OptionalFinishes).Finishes
 local Commerce=require(RS.Shared.Utility.Phase13CommerceRules)
 local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
 local Geometry=require(script.Parent.Parent.Utility.Phase13BaseGeometry)
 local Config=require(RS.Shared.Config.Phase13)
 local Renderer=require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Utility.SpaceRiftRenderer)
 local defaultAsset=require(RS.Shared.Config.SpaceRift)
 -- Test-owned native adapter, local to this spec. Accepted sources are read/cloned only.
 local Weapons=require(RS.Shared.Config.Weapons)
 local CartAssets=require(script.Parent.Parent.Services.CartAssetService)
 local fixtureContext={OwnerUserId=8105,AssignmentRevision=1,ProfileReady=true}
 local owned={}
 local function own(instance)
  assert(typeof(instance)=="Instance","Actual native fixture clone required")
  table.insert(owned,instance)
  return instance
 end
 -- Engine BasePart.Color stores RGB8. Quantize only the calculated required
 -- tint through an independent owned Part; protected/default values stay exact.
 local colorStorage
 local function nativeRGB8(value)
  if not colorStorage then colorStorage=own(Instance.new("Part")) end
  colorStorage.Color=value
  return colorStorage.Color
 end
 local registerCase=it
 local function it(name,callback)
  registerCase(name,function()
   assert(#owned==0,"Prior asset fixture was not cleaned")
   local ok,reason=xpcall(callback,debug.traceback)
   for _,instance in owned do instance:Destroy() end
   table.clear(owned)
   colorStorage=nil
   assert(ok,reason)
  end)
 end
 local function AssetCloseoutFixtures()
  local rows={}
  local weaponFolder=assert(RS:FindFirstChild("CodeAssets") and RS.CodeAssets:FindFirstChild("Weapons"),"Actual mapped weapon sources required")
  local weaponRows=Weapons.GetAll()
  assert(#weaponRows==24 and #Config.CartRows==9 and #Config.DesignRows==8,"Current exact catalogues required")
  for _,row in weaponRows do
   local source=assert(weaponFolder:FindFirstChild(row.assetName),"Missing current weapon: "..row.id)
   assert(source:IsA("Model") or source:IsA("Tool"),"Weapon art must retain native container")
   local handle=source:FindFirstChild("Handle")
   assert(handle and handle:IsA("BasePart"),"Current weapon Handle required")
   -- Obsolete capture/reel markers are not startup/fixture requirements.
   table.insert(rows,{category="Weapon",id=row.id,catalogId=row.id,clone=own(source:Clone())})
  end
  task.wait() -- Completed native weapon category; detached sources only.
  for _,row in Config.CartRows do
   -- Reuse all current root/seat/cargo/formation/geometry validators unchanged.
   table.insert(rows,{category="Cart",id=row.assetName,catalogId=row.id,clone=own(CartAssets:CloneAsset(row.id))})
  end
  task.wait() -- Completed native cart category.
  local map=assert(workspace:FindFirstChild("MapBlockout"),"Mapped accepted world required")
  local patches=assert(map:FindFirstChild("PlayerBasePatches"),"Accepted base patches required")
  local source=assert(patches:FindFirstChild("Base_01"),"Accepted Base_01 source required")
  assert(source:IsA("Model") and source:FindFirstChild("Foundation"),"Native grouped base source required")
  for _,row in Config.DesignRows do
   local base=own(source:Clone())
   base:SetAttribute("OwnerUserId",fixtureContext.OwnerUserId)
   base:SetAttribute("BaseOwnershipRevision",fixtureContext.AssignmentRevision)
   Geometry.Build(base)
   assert(Geometry.Apply(base,12,row.id,false,fixtureContext),"Actual design adapter failed: "..row.id)
   table.insert(rows,{category="Base",id=row.id,catalogId=row.id,clone=base})
   task.wait() -- Bound one native design build at a time.
  end
  return rows
 end
 local function mechanics(model)
  local result={}
  for _,p in {model,table.unpack(model:GetDescendants())} do
   if p:IsA("BasePart") then result[p]={p.Size,p.CFrame,p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery,p.Massless,p.Material,p.MaterialVariant,p.Transparency,p.CustomPhysicalProperties,if p:IsA("UnionOperation") then p.UsePartColor else false,if p:IsA("MeshPart") then p.MeshId else "",if p:IsA("MeshPart") then p.TextureID else "",if p:IsA("MeshPart") then p.DoubleSided else false}
   elseif p:IsA("Attachment") then result[p]={p.CFrame}
   elseif p:IsA("SurfaceAppearance") then result[p]={p.Color,p.ColorMap,p.NormalMap,p.MetalnessMap,p.RoughnessMap,p.AlphaMode}
   elseif p:IsA("WeldConstraint") then result[p]={p.Part0,p.Part1,p.Enabled} end
  end
  return result
 end
 local function unchanged(before)
  for p,values in before do
   local actual=if p:IsA("BasePart") then {p.Size,p.CFrame,p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery,p.Massless,p.Material,p.MaterialVariant,p.Transparency,p.CustomPhysicalProperties,if p:IsA("UnionOperation") then p.UsePartColor else false,if p:IsA("MeshPart") then p.MeshId else "",if p:IsA("MeshPart") then p.TextureID else "",if p:IsA("MeshPart") then p.DoubleSided else false} elseif p:IsA("Attachment")then {p.CFrame}elseif p:IsA("SurfaceAppearance")then {p.Color,p.ColorMap,p.NormalMap,p.MetalnessMap,p.RoughnessMap,p.AlphaMode}else {p.Part0,p.Part1,p.Enabled}
   for i,v in values do assert(actual[i]==v,p.Name.." mechanics changed at "..i)end
  end
 end
 describe("Phase13 disabled optional finish integration",function()
  it("keeps all four exact supplied palettes/prices static and paid-disabled",function()
   local expected={FIN_PRISM={"Weapon",79,Color3.fromRGB(48,39,84)},FIN_GLACIER={"Cart",149,Color3.fromRGB(169,214,232)},FIN_AURORA={"Base",199,Color3.fromRGB(32,48,71)},FIN_SINGULARITY={"Rift",199}}
   for id,wanted in expected do local d=Definitions[id];expect(d.Category).to.equal(wanted[1]);expect(d.TargetRobux).to.equal(wanted[2]);expect(d.PaidEnabled).to.equal(false);expect(d.DefaultSelected).to.equal(false);if wanted[3]then expect(d.Palette.Primary).to.equal(wanted[3])end end
  end)
  it("rejects every forged FIN selection and keeps optional grants out of GrantPass",function()
   local d=Schema.CreateDefault();local balance=d.Economy.Balance
   for key,id in {WeaponFinish="FIN_PRISM",CartFinish="FIN_GLACIER",BaseFinish="FIN_AURORA",RiftVariant="FIN_SINGULARITY"}do
    expect(Rules.CanSelect(d,key,id)).to.equal(false);expect(Commerce.GrantPass(d,id,1000)).to.equal(false)
    d.Commerce.Entitlements[id]=true;expect(Rules.CanSelect(d,key,id)).to.equal(true)
   end
   expect(Commerce.Validate(d)).to.equal(true);expect(d.Economy.Balance).to.equal(balance);expect(d.Commerce.StarterPackClaimed).to.equal(false)
   expect(Rules.CanSelect(d,"CartFinish","FIN_PRISM")).to.equal(false)
  end)
  it("preserves functional ownership and validates old profiles without new fields",function()
   local d=Schema.CreateDefault();expect(Commerce.Validate(d)).to.equal(true)
   d.Commerce.Entitlements.FIN_PRISM=true;d.Commerce.Appearance.WeaponFinish="FIN_PRISM"
   expect(Rules.ResolveFinish(d,"Weapon","WPN_G08")).to.equal("Default")
   d.Phase13.OwnedWeaponIds.WPN_G08=true;expect(Rules.ResolveFinish(d,"Weapon","WPN_G08")).to.equal("FIN_PRISM")
   expect(d.Phase13.ExpansionLevel).to.equal(0)
  end)
  it("maps actual 24 weapons/nine carts/eight bases and restores originals over20 switches",function()
   local seen={Weapon=0,Cart=0,Base=0}
   for _,fixture in AssetCloseoutFixtures() do
    local model=fixture.clone;local before=mechanics(model);local original={};for p in before do if p:IsA("BasePart")then original[p]=p.Color end end
    local finish=({Weapon="FIN_PRISM",Cart="FIN_GLACIER",Base="FIN_AURORA"})[fixture.category]
    local eligible,blocked,native=0,0,0
    local expectedColor={}
    for p,c in original do
     if p.Transparency<1 then
      local role=Roles.Resolve(model,p,fixture.category,fixture.id)
      local protectedCSG=p:IsA("UnionOperation") and p:GetAttribute("ArcadeVisualRevision")==3 and p:GetAttribute("NativeVehicleConstruction")=="CSG"
      local atlas=p:IsA("MeshPart") and (p.TextureID~="" or p:FindFirstChildOfClass("SurfaceAppearance")~=nil)
      if protectedCSG then native+=1 end
      if role and (protectedCSG or atlas) then blocked+=1
      elseif role then eligible+=1;expectedColor[p]=Definitions[finish].Palette[role] end
     end
     expectedColor[p]=expectedColor[p] or c
    end
    if fixture.category=="Cart" then
     local known=false;for _,row in Config.CartRows do if row.id==fixture.catalogId and row.assetName==fixture.id then known=true end end
     assert(known and native>0,fixture.id.." must be one of the nine accepted native CSG carts")
     -- Required owned finishes still tint accepted fitted bodies. Optional paid
     -- palettes may never flatten their authored face colors or atlas detail.
     for _,required in {"Riftgold","Trailblazer"} do
      assert(Rules.Apply(model,required,"Cart",fixture.id)>0,fixture.id.." required finish lost")
      for p,c in original do
       if p.Transparency<1 and p:IsA("UnionOperation") and p:GetAttribute("ArcadeVisualRevision")==3 and p:GetAttribute("NativeVehicleConstruction")=="CSG" then
        local alias=p:GetAttribute("Phase13FinishAlias")
        expect(p.UsePartColor).to.equal(true)
        expect(p.Color).to.equal(nativeRGB8(Rules.Color(c,required,if type(alias)=="string" then alias else p.Name)))
       end
      end
      Rules.Apply(model,"Default","Cart",fixture.id);unchanged(before)
      for p,c in original do expect(p.Color).to.equal(c)end
     end
    else
     assert(eligible>0 and blocked==0,fixture.id.." current weapon/base coverage required")
    end
    for _=1,20 do
     local count,diagnostics=Rules.Apply(model,finish,fixture.category,fixture.id)
     expect(count).to.equal(eligible)
     expect(#diagnostics.atlasBlocked).to.equal(math.min(64,blocked))
     for p,color in expectedColor do expect(p.Color).to.equal(color)end
     unchanged(before);Rules.Apply(model,"Default",fixture.category,fixture.id);unchanged(before)
     for p,c in original do expect(p.Color).to.equal(c)end
    end
    seen[fixture.category]+=1;model:Destroy()
   end
   expect(seen.Weapon).to.equal(24);expect(seen.Cart).to.equal(9);expect(seen.Base).to.equal(8)
  end)
  it("restores protected surfaces when switching directly from Riftgold to an optional finish",function()
   local fixtures=AssetCloseoutFixtures();local chosen
   for _,f in fixtures do if f.category=="Cart" and not chosen then chosen=f else f.clone:Destroy()end end
   local model=chosen.clone;local original={};for _,p in model:GetDescendants()do if p:IsA("BasePart")then original[p]=p.Color end end
   Rules.Apply(model,"Riftgold");Rules.Apply(model,"FIN_GLACIER","Cart",chosen.id)
   for p,c in original do if not Roles.Resolve(model,p,"Cart",chosen.id)then expect(p.Color).to.equal(c)end end
   Rules.Apply(model,"Default");for p,c in original do expect(p.Color).to.equal(c)end;model:Destroy()
  end)
  it("maps the actual flattened equipped-weapon adapter with the same explicit roles",function()
   local fixtures=AssetCloseoutFixtures();local seen=0
   for _,f in fixtures do
    if f.category=="Weapon"then
     local art=Instance.new("Model");art.Name="Phase13WeaponArt"
     for _,p in f.clone:GetDescendants()do if p:IsA("BasePart") and p.Name~="Handle"then local c=p:Clone();c.Parent=art end end
     local count,_=Rules.Apply(art,"FIN_PRISM","Weapon",f.id);assert(count>0,f.id.." flattened adapter unmapped")
     for _,p in art:GetChildren()do local role=Roles.Resolve(art,p,"Weapon",f.id);if role and p.Transparency<1 then expect(p.Color).to.equal(Definitions.FIN_PRISM.Palette[role])end end
     art:Destroy();seen+=1
    end
    f.clone:Destroy()
   end
   expect(seen).to.equal(24)
  end)
  it("leaves unexpected or atlas-bearing surfaces untouched with bounded diagnostics",function()
   local m=Instance.new("Model");m.Name="HRP_001";local folder=Instance.new("Folder");folder.Name="Phase13Appearance";folder.Parent=m
   local p=Instance.new("MeshPart");p.Name="InnerLimb";p.TextureID="rbxassetid://1";p.Parent=folder;local original=p.Color
   local count,d=Rules.Apply(m,"FIN_PRISM","Weapon","HRP_001");expect(count).to.equal(0);expect(#d.atlasBlocked).to.equal(1);expect(p.Color).to.equal(original);m:Destroy()
  end)
  it("applies Aurora at all56 design/capacity combinations while keeping locked slots/protected plaques",function()
   local fixtures=AssetCloseoutFixtures();local base
   for _,f in fixtures do if f.category=="Base" and not base then base=f.clone else f.clone:Destroy()end end
   Geometry.Build(base)
   for _,design in Config.DesignRows do for capacity=12,48,6 do
    Geometry.Apply(base,capacity,design.id,false);local before=mechanics(base);local colors={};for p in before do if p:IsA("BasePart")then colors[p]=p.Color end end
    Geometry.Apply(base,capacity,design.id,"FIN_AURORA");unchanged(before)
    for p,color in colors do if p:GetAttribute("SlotIndex")then expect(p.Color).to.equal(color)end end
    expect(base:GetAttribute("Phase13Capacity")).to.equal(capacity)
    Geometry.Apply(base,capacity,design.id,false);for p,color in colors do expect(p.Color).to.equal(color)end
   end end;base:Destroy()
  end)
  it("retains missing optional selection/ownership and falls back without touching approved default",function()
   local d=Schema.CreateDefault();d.Commerce.Entitlements.FIN_SINGULARITY=true;d.Commerce.Appearance.RiftVariant="FIN_SINGULARITY"
   local asset,variant,reason=Rules.ResolveRift(d,defaultAsset);expect(asset).to.equal(defaultAsset);expect(variant).to.equal("Default");expect(reason).to.equal("OPTIONAL_RIFT_UNAVAILABLE");expect(d.Commerce.Appearance.RiftVariant).to.equal("FIN_SINGULARITY");expect(defaultAsset.PrimaryImage).to.equal("rbxassetid://123465248728183")
  end)
  it("uses one renderer slot and falls back from an unavailable optional texture without renewing the event",function()
   local parent=Instance.new("Folder");local owner=Instance.new("Folder");owner.Parent=parent;local anchor=Instance.new("Part");anchor.Parent=owner
   local api=Renderer.Create(owner,defaultAsset,anchor)
   local variant={Installed=true,PrimaryImage="rbxassetid://1",Width=1024,Height=1024,VerticalLongAxis=true,AngleDegrees=0}
   assert(api.Start({eventId="FAKE_OPTIONAL",mode="Spawn",startTime=0,deadline=7,position=Vector3.zero,requestedRifts=1,variantAsset=variant},0,"Low",true))
   api.Step(1,Vector3.zero,"Low",true);local image=owner:FindFirstChildWhichIsA("ImageLabel",true);expect(image.Image).to.equal(variant.PrimaryImage)
   api.Step(3,Vector3.zero,"Low",true);expect(image.Image).to.equal(defaultAsset.PrimaryImage);expect(api.GetDiagnostics().poolSlots).to.equal(1);expect(api.GetDiagnostics().connections).to.equal(0);api.Step(7,Vector3.zero,"Low",true);expect(api.GetDiagnostics().activeRifts).to.equal(0);api.Destroy();parent:Destroy()
  end)
 end)
end
