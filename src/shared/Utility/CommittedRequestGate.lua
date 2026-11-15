--!strict
-- In-memory replay fencing around the existing mutation functions, never a writer.
local Gate={}
function Gate.new()
 local actors=setmetatable({},{__mode="k"})
 local api={}
 function api.Execute(actor,operationId,signature,commit)
  if operationId==nil then return commit()end -- retained legacy server callers
  local history=actors[actor];if not history then history={};actors[actor]=history end
  local old=history[operationId]
  if old then
   if #old.signature~=#signature then return false,"STALE_REQUEST"end
   for i,v in ipairs(signature)do if old.signature[i]~=v then return false,"STALE_REQUEST"end end
   if old.pending then return false,"REQUEST_PENDING"end
   return old.success,old.reason
  end
  local receipt={signature=table.clone(signature),pending=true};history[operationId]=receipt
  local called,success,reason=pcall(commit)
  receipt.pending=false;receipt.success=called and success==true
  receipt.reason=if called then reason else "REQUEST_FAILED"
  if not called then warn(success)end
  return receipt.success,receipt.reason
 end
 return api
end
return table.freeze(Gate)
