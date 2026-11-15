
assert(not game.RunService:IsRunning(),"Edit only")
local Guard=(function()

local Guard={}
local base={"Name","ClassName","Parent","Archivable"}
local extra={
BasePart={"CFrame","Size","Color","Transparency","Reflectance","Anchored","CanCollide","CanTouch","CanQuery","CastShadow","Massless","CollisionGroup","PivotOffset","Material","MaterialVariant","CustomPhysicalProperties"},
Model={"PrimaryPart","WorldPivot"},
Attachment={"CFrame","Axis","SecondaryAxis","Visible"},
MeshPart={"MeshId","TextureID","DoubleSided","CollisionFidelity","RenderFidelity"},
UnionOperation={"UsePartColor","CollisionFidelity","RenderFidelity"},
MaterialVariant={"BaseMaterial","ColorMap","NormalMap","RoughnessMap","MetalnessMap","MaterialPattern","StudsPerTile","CustomPhysicalProperties","AlphaMode"},
WeldConstraint={"Part0","Part1","Enabled"}
}
local E=game:GetService("EncodingService")
local function hash(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local function encode(v)
 local t=typeof(v)
 if t=="nil"then return {"nil"}elseif t=="Instance"then return {"Instance",v:GetFullName()}
 elseif t=="CFrame"then local a={"CFrame"};for _,x in {v:GetComponents()}do table.insert(a,x)end;return a
 elseif t=="Vector3"then return {t,v.X,v.Y,v.Z}
 elseif t=="Color3"then return {t,v.R,v.G,v.B}
 elseif t=="PhysicalProperties"then return {t,v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight}
 elseif t=="EnumItem"then return {t,tostring(v)}
 elseif t=="number"or t=="string"or t=="boolean"then return {t,v}
 else return {t,tostring(v)}end
end
local function roots()
 return {game.ReplicatedStorage.StudioAssets.Brainrots,game.ReplicatedStorage.StudioAssets.ChariotFormation,game.MaterialService.Bingus_Saved_Studs_13719188279,game.MaterialService:FindFirstChild("2022 Stud")}
end
function Guard.Capture()
 local B={nodes={},rows={}}
 for _,root in roots()do assert(root);local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,n in nodes do
   local props={}for _,p in base do props[p]=n[p]end
   for class,list in extra do if n:IsA(class)then for _,p in list do local ok,v=pcall(function()return n[p]end);if ok then props[p]=v end end end end
   local attrs=n:GetAttributes();local tags=game.CollectionService:GetTags(n);table.sort(tags)
   B.nodes[n]={props=props,attrs=attrs,tags=tags}
   local propRows={}for k,v in props do table.insert(propRows,{k,encode(v)})end;table.sort(propRows,function(a,b)return a[1]<b[1]end)
   local attrRows={}for k,v in attrs do table.insert(attrRows,{k,encode(v)})end;table.sort(attrRows,function(a,b)return a[1]<b[1]end)
   table.insert(B.rows,game.HttpService:JSONEncode({n:GetFullName(),n.ClassName,propRows,attrRows,tags}))
  end
 end
 table.sort(B.rows);B.digest=hash(table.concat(B.rows,"\n"));B.count=#B.rows;return B
end
function Guard.Verify(B)
 local checks=0 local failures={}
 for n,row in B.nodes do
  for key,value in row.props do checks+=1;if n[key]~=value then table.insert(failures,n:GetFullName().." property "..key)end end
  local attrs=n:GetAttributes();for k,v in row.attrs do checks+=1;if attrs[k]~=v then table.insert(failures,n:GetFullName().." attribute "..k)end end
  for k,v in attrs do checks+=1;if row.attrs[k]~=v then table.insert(failures,n:GetFullName().." extra attribute "..k)end end
  local tags=game.CollectionService:GetTags(n);table.sort(tags);checks+=1;if game.HttpService:JSONEncode(tags)~=game.HttpService:JSONEncode(row.tags)then table.insert(failures,n:GetFullName().." tags")end
 end
 local now=Guard.Capture();checks+=2;if now.count~=B.count or now.digest~=B.digest then table.insert(failures,"Protected model/material digest or instance count changed")end
 return {passed=#failures==0,checks=checks,failures=failures,digest=now.digest,instances=now.count}
end
return Guard

end)()
local B={old={},new={},functional={},art={},sourceRefs={},createdAt=os.date("!%Y-%m-%dT%H:%M:%SZ")}
local props={"Name","ClassName","CFrame","Size","Color","Transparency","Reflectance","Anchored","CanCollide","CanTouch","CanQuery","CastShadow","Massless","CollisionGroup","PivotOffset","Material","MaterialVariant","CustomPhysicalProperties"}
local function capture(n)
 local row={props={},attrs=n:GetAttributes(),tags=game.CollectionService:GetTags(n)}
 for _,p in props do row.props[p]=n[p]end
 if n:IsA("MeshPart")then row.props.MeshId=n.MeshId row.props.TextureID=n.TextureID row.props.CollisionFidelity=n.CollisionFidelity row.props.RenderFidelity=n.RenderFidelity end
 return row
end
for i=1,12 do
 local id=string.format("Base_%02d",i)
 local old=assert(workspace.MapBlockout.PlayerBasePatches:FindFirstChild(id),"Missing "..id)
 local art=assert(workspace.MapBlockout.MapArt.BaseShells:FindFirstChild("Showhouse_"..id),"Missing shell "..id)
 assert(old:IsA("Model")and art:IsA("Model")and not art.PrimaryPart,"Unexpected base model")
 assert(old:GetAttribute("BaseId")==id and not art:GetAttribute("BaseId"),"Ambiguous registration")
 B.old[id]={model=old,pivot=old:GetPivot(),attrs=old:GetAttributes()}
 B.new[id]={model=art,pivot=art:GetPivot(),attrs=art:GetAttributes()}
 local partCount=0 local markerCount=0
 for _,n in old:GetChildren()do
  assert(n:IsA("BasePart"),"Unexpected old direct child "..n:GetFullName())
  B.functional[n]=capture(n);B.functional[n].baseId=id;partCount+=1
  for _,a in n:GetChildren()do if a:IsA("Attachment")then markerCount+=1;B.functional[a]={baseId=id,parent=n,props={Name=a.Name,ClassName=a.ClassName,CFrame=a.CFrame,Axis=a.Axis,SecondaryAxis=a.SecondaryAxis,Visible=a.Visible},attrs=a:GetAttributes(),tags=game.CollectionService:GetTags(a)}else error("Unexpected logic child "..a:GetFullName())end end
 end
 assert(partCount==19 and markerCount==12,"Functional base contract differs")
 for _,p in art:GetChildren()do assert(p:IsA("MeshPart"),"Unexpected shell child");B.art[p]=capture(p);B.art[p].baseId=id end
end
local sourceRows=game.HttpService:JSONDecode(shared.DevBaseMigrationSources)
local indexed={}for _,row in sourceRows do indexed[row.path]=row end
local count=0 local concurrent={}
for _,n in game:GetDescendants()do if n:IsA("LuaSourceContainer")then count+=1;local row=indexed[n:GetFullName()];local editor=game.ScriptEditorService:GetEditorSource(n);if not row or editor~=row.source or n.Source~=row.source then table.insert(concurrent,n:GetFullName())end;B.sourceRefs[n]={source=n.Source,editor=editor}end end
assert(count==420 and #concurrent==0,"Source changed since fresh export: "..game.HttpService:JSONEncode(concurrent))
B.protected=Guard.Capture();B.guard=Guard
shared.DevBaseMigrationBaseline=B
return {bases=12,functionalParts=228,placementAttachments=144,artMeshParts=36,sources=count,protectedDigest=B.protected.digest,protectedInstances=B.protected.count,createdAt=B.createdAt}
