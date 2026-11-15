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
 return {workspace.MapBlockout.PlayerBasePatches,workspace.MapBlockout.MapArt.BaseShells}
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

end)() local g=Guard.Capture() local PG=(function()

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

end)() local p=PG.Capture() local E=game:GetService("EncodingService") local function hash(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end local rows={} local S=game:GetService("ScriptEditorService") local same=true for _,n in game:GetDescendants() do if n:IsA("LuaSourceContainer") then table.insert(rows,n:GetFullName().."\0"..n.ClassName.."\0"..hash(n.Source)) local ok,editor=pcall(function()return S:GetEditorSource(n)end) if not ok or editor~=n.Source then same=false end end end table.sort(rows) local captured={baseDigest=g.digest,baseInstances=g.count,protectedDigest=p.digest,protectedInstances=p.count,sourceDigest=hash(table.concat(rows,"\n")),sourceCount=#rows,allEditorSame=same}
local expected=game.HttpService:JSONDecode("{\"baseInstances\":422,\"protectedDigest\":\"e44c2f47fdbcbcf0832567b46b89a0595d31d95fdfc0cb99180faf9500ebf23d\",\"protectedInstances\":1777,\"sourceCount\":420,\"baseDigest\":\"36b7b2b17b9690d1ca982683a384b0482cc2367926e24e1757540035aae3421c\",\"allEditorSame\":true,\"sourceDigest\":\"019adfd3b46337e1d1e8356bd268cd6efbfc1ab244877740c3b4d55207b38e06\"}") local failures={} for _,key in {"baseDigest","baseInstances","protectedDigest","protectedInstances","sourceDigest","sourceCount","allEditorSame"} do if captured[key]~=expected[key] then table.insert(failures,key.." mismatch") end end captured.PlaceId=game.PlaceId captured.GameId=game.GameId if game.PlaceId~=91958083796436 or game.GameId~=10548905405 then table.insert(failures,"wrong DEV identity") end captured.passed=#failures==0 captured.failures=failures return captured