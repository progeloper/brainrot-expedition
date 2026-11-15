assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"DEV identity")
local G=(function()

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
 return {workspace.MapBlockout,game.MaterialService.Environment_Saved_Studs_13719188279}
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

end)() local W=G.Capture()
local P=(function()

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

end)() local B=P.Capture()
local E=game.EncodingService local function hash(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local rows={} local editorSame=true for _,n in game:GetDescendants() do if n:IsA("LuaSourceContainer") then table.insert(rows,n:GetFullName().."\0"..n.ClassName.."\0"..hash(n.Source)) if game.ScriptEditorService:GetEditorSource(n)~=n.Source then editorSame=false end end end table.sort(rows)
local actual={worldDigest=W.digest,worldInstances=W.count,protectedDigest=B.digest,protectedInstances=B.count,sourceDigest=hash(table.concat(rows,"\n")),sourceCount=#rows,allEditorSame=editorSame,runtimeGeometryDigest=hash(workspace.MapBlockout.CompactMapRuntimeGeometry.Value),closures=#workspace.MapBlockout.GateApertureClosures:GetChildren(),bases=#workspace.MapBlockout.PlayerBasePatches:GetChildren(),gates=#workspace.MapBlockout.ProgressionGates:GetChildren()}
local expected=game.HttpService:JSONDecode("{\"worldDigest\":\"dcf94e3ee3571b38795f09ff42fb508df3a80d3654a51e2650d434a7554b1329\",\"bases\":12,\"sourceDigest\":\"019adfd3b46337e1d1e8356bd268cd6efbfc1ab244877740c3b4d55207b38e06\",\"worldInstances\":3339,\"gates\":6,\"runtimeGeometryDigest\":\"123661898d695ee7607f2ba487ca8a08238e32ccb56dcfaa858aac363d67a27f\",\"closures\":22,\"sourceCount\":420,\"protectedInstances\":1777,\"allEditorSame\":true,\"protectedDigest\":\"e44c2f47fdbcbcf0832567b46b89a0595d31d95fdfc0cb99180faf9500ebf23d\"}") local failures={} for k,v in expected do if actual[k]~=v then table.insert(failures,k.." mismatch") end end actual.passed=#failures==0 actual.failures=failures return actual