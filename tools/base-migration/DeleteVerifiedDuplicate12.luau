assert(game.PlaceId==91958083796436 and game.GameId==10548905405 and not game.RunService:IsRunning(),"DEV Edit only")
local folder=workspace.MapBlockout.PlayerBasePatches local twins={}
for _,n in folder:GetChildren() do if n.Name=="Base_12" then table.insert(twins,n) end end
if #twins==1 and #folder:GetChildren()==12 then return {alreadyUnique=true,changes=0} end
assert(#twins==2 and #folder:GetChildren()==13,"Unexpected duplicate structure")
local info={}
for _,target in twins do
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
 return {target}
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

end)() local c=G.Capture()
 local refs=0 for _,n in game:GetDescendants() do if n:IsA("ObjectValue") and n.Value and (n.Value==target or n.Value:IsDescendantOf(target)) then refs+=1 end end
 table.insert(info,{target=target,digest=c.digest,count=c.count,refs=refs})
end
assert(info[1].digest==info[2].digest and info[1].count==35 and info[2].count==35,"Twins must have exactly identical native properties")
local retained,discarded
for _,r in info do if r.refs>0 then assert(not retained,"Both twins externally referenced");retained=r else assert(not discarded);discarded=r end end
assert(retained and discarded and discarded.refs==0,"Retain the historical reference graph")
local CH=game.ChangeHistoryService local token=CH:TryBeginRecording("RemoveVerifiedUnreferencedDuplicateBase12")
discarded.target:Destroy()
if token then CH:FinishRecording(token,Enum.FinishRecordingOperation.Commit) end
assert(#folder:GetChildren()==12 and retained.target.Parent==folder,"Duplicate removal failed")
return {passed=true,removedExactlyIdenticalUnreferencedBase12=true,retainedHistoricalObjectReferences=retained.refs,identicalPerBaseDigest=retained.digest,remainingBases=#folder:GetChildren()}
