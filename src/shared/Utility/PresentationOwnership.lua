--!strict
-- Per-client-session counters survive replacement of an individual/model.
local Ownership={}
function Ownership.new()
 local counters,active={},{}
 local api={}
 function api.Revoke(id)
  counters[id]=(counters[id]or 0)+1
  local previous=active[id];active[id]=nil
  if previous then
   previous.valid=false
   for _,cancel in ipairs(previous.cleanup)do local ok,why=pcall(cancel);if not ok then warn(why)end end
   table.clear(previous.cleanup)
  end
  return counters[id]
 end
 function api.Bind(id,revision,state)
  api.Revoke(id)
  counters[id]+=1
  local handle={id=id,revision=revision,state=state,generation=counters[id],valid=true,cleanup={}}
  active[id]=handle
  return handle
 end
 function api.IsCurrent(handle,id,revision,state)
  return handle~=nil and handle.valid==true and active[id]==handle and counters[id]==handle.generation
   and handle.id==id and handle.revision==revision and handle.state==state
 end
 function api.Own(handle,cancel)
  if handle and handle.valid and active[handle.id]==handle then table.insert(handle.cleanup,cancel)else cancel()end
 end
 function api.Get(id)return active[id],counters[id]or 0 end
 return api
end
return table.freeze(Ownership)
