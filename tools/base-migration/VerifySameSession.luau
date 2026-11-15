
local B=assert(shared.DevBaseMigrationBaseline)
local failures={}local checks=0
local function check(v,m)checks+=1;if not v then table.insert(failures,m)end end
local targets=workspace.MapBlockout.PlayerBasePatches
local ids={}local counts={bases=0,parts=0,markers=0,art=0}
for _,base in targets:GetChildren()do
 check(base:IsA("Model"),"Unexpected base child")
 local id=base:GetAttribute("BaseId")
 check(type(id)=="string"and not ids[id],"Duplicate/missing BaseId")
 ids[id]=true;counts.bases+=1
 check(B.new[id]and base==B.new[id].model,"Base is not accepted new shell "..tostring(id))
 check(base:GetAttribute("AuthoredBaseLayout")==true and base:GetAttribute("FunctionalBaseRevision")==1,"Authored layout flag "..tostring(id))
 check(base:GetPivot()==B.old[id].pivot and base:GetAttribute("BaseOrigin")==B.old[id].pivot and base:GetAttribute("Phase5DLayoutPivot")==B.old[id].pivot,"Functional origin changed "..tostring(id))
 check(not base:FindFirstChild("Phase5DInterior")and not base:FindFirstChild("BaseFloor"),"Legacy layer present "..tostring(id))
 for i=1,12 do local platform=base:FindFirstChild(string.format("Slot_%02d",i));check(platform and platform:IsA("BasePart")and platform:FindFirstChild("BrainrotPlacement"),"Missing direct platform "..tostring(id)..":"..i)end
 for _,name in {"Foundation","CartDisplay","CartRamp","HouseRamp","DepositReturnZone","CartSpawn","PlayerSpawn"}do check(base:FindFirstChild(name)~=nil,"Missing transferred "..tostring(id)..":"..name)end
 for _,n in base:GetDescendants()do if n:IsA("MeshPart")then counts.art+=1 elseif n:IsA("BasePart")then counts.parts+=1 elseif n:IsA("Attachment")then counts.markers+=1 end end
end
check(counts.bases==12 and counts.parts==228 and counts.markers==144 and counts.art==36,"Wrong live base/part counts")
check(#workspace.MapBlockout.MapArt.BaseShells:GetChildren()==0,"Separate decorative bases remain")
for p,row in B.functional do
 for key,value in row.props do check(p[key]==value,"Transferred functional property changed "..p:GetFullName()..":"..key)end
 local parent=if p:IsA("Attachment")then row.parent else B.new[row.baseId].model
 check(p.Parent==parent,"Transferred parent incorrect "..p.Name)
 for key,value in row.attrs do check(p:GetAttribute(key)==value,"Functional attribute changed "..p.Name..":"..key)end
 for key,value in p:GetAttributes()do check(row.attrs[key]==value,"Unexpected functional attribute "..p.Name..":"..key)end
 local tags=game.CollectionService:GetTags(p);table.sort(tags);table.sort(row.tags);check(game.HttpService:JSONEncode(tags)==game.HttpService:JSONEncode(row.tags),"Functional tags changed "..p.Name)
end
for p,row in B.art do
 for key,value in row.props do check(p[key]==value,"Accepted art changed "..p:GetFullName()..":"..key)end
 check(p.Parent==B.new[row.baseId].model,"Art parent incorrect")
 for key,value in row.attrs do check(p:GetAttribute(key)==value,"Art attribute changed "..p.Name..":"..key)end
end
local sourceCount=0
for n,row in B.sourceRefs do sourceCount+=1;local expected=if n==B.expectedSourceNode then B.expectedSource else row.source;check(n.Source==expected,"Unintended Source edit "..n:GetFullName());check(game.ScriptEditorService:GetEditorSource(n)==expected,"Unintended editor edit "..n:GetFullName())end
local actual=0;for _,n in game:GetDescendants()do if n:IsA("LuaSourceContainer")then actual+=1;check(B.sourceRefs[n]~=nil,"Added Source "..n:GetFullName())end end
check(sourceCount==420 and actual==420,"Source population changed")
local protected=B.guard.Verify(B.protected);check(protected.passed,"Brainrot preservation failed")
return {passed=#failures==0,checks=checks,failures=failures,counts=counts,sourcesVerified=actual,onlyChangedSource="BaseIncomePlaqueSystem",protected=protected}
