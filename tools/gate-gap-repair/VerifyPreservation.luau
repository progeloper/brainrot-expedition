local B=assert(shared.GateGapRepairBaseline) local failures={} local checks=0
local function check(ok,msg) checks+=1 if not ok then table.insert(failures,msg) end end
for n,row in B.world.nodes do
 for key,value in row.props do check(n[key]==value,n:GetFullName().." property "..key) end
 local attrs=n:GetAttributes() for k,v in row.attrs do check(attrs[k]==v,n:GetFullName().." attr "..k) end for k,v in attrs do check(row.attrs[k]==v,n:GetFullName().." extra attr "..k) end
 local tags=game.CollectionService:GetTags(n) table.sort(tags) check(game.HttpService:JSONEncode(tags)==game.HttpService:JSONEncode(row.tags),n:GetFullName().." tags")
end
local actual=0 for _,n in game:GetDescendants() do if n:IsA("LuaSourceContainer") then actual+=1 local before=B.sources[n] check(before~=nil,"Added source "..n:GetFullName()) if before then check(n.Source==before.source and game.ScriptEditorService:GetEditorSource(n)==before.editor,"Source changed "..n:GetFullName()) end end end check(actual==B.sourceCount,"Source count changed")
check(workspace.MapBlockout.CompactMapRuntimeGeometry.Value==B.runtimeValue,"Runtime metadata changed")
local count={models=0,cores=0,bricks=0} local root=workspace.MapBlockout.GateApertureClosures
for _,group in root:GetChildren() do check(group:IsA("Model"),"Closure Model type") count.models+=1
 for _,part in group:GetChildren() do if part.Name=="CollisionCore" then count.cores+=1 check(part.Anchored and part.CanCollide and part.CanQuery and not part.CanTouch and part.Transparency==1,"Collider flags") else count.bricks+=1 check(part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Transparency==0,"Brick flags") check(part.MaterialVariant=="Environment_Saved_Studs_13719188279" and part:GetAttribute("StudsPerTile")==4,"Saved studs missing") check(part.Size.X<=8.001 and part.Size.Y<=4.001 and part.Size.Z<=8.001,"Brick exceeds authored maximum") end end
end
check(count.models==22 and count.cores==22 and count.bricks==1850,"Closure counts")
local protected=B.guard.Verify(B.protected) check(protected.passed,"Protected brainrot changes")
local groups={} for _,g in game.PhysicsService:GetRegisteredCollisionGroups() do table.insert(groups,{name=g.name,collidesWithClosures=game.PhysicsService:CollisionGroupsAreCollidable("Default",g.name)}) end
return {passed=#failures==0,checks=checks,failures=failures,originalWorldInstancesPreserved=B.world.count,sourceCount=actual,counts=count,protected=protected,collisionGroups=groups}