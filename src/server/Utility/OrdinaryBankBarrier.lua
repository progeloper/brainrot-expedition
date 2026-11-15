--!strict
-- Reservation ownership ends only at the explicit covering-save callback.
local Barrier = {}
function Barrier.Begin(pending: any, members: any, record: any, operationId: string, revision: number?): (boolean,string?)
 if type(record)~="table" or type(record.ItemId)~="string" then return false,"INVALID_RECORD" end
 local member=members[record.ItemId]
 if not member then return false,"ALREADY_BANKED_OR_NONORDINARY" end
 if member.SpeciesId~=record.BrainrotId or operationId~="Bank:"..record.ItemId then return false,"IDENTITY_CONFLICT" end
 local existing=pending[record.ItemId]
 if existing then
  return existing.OperationId==operationId,if existing.OperationId==operationId then "ALREADY_PENDING" else "BANK_OPERATION_CONFLICT"
 end
 pending[record.ItemId]={OperationId=operationId,CoveringRevision=revision,Record=record}
 return true,nil
end
function Barrier.Confirm(pending: any,members: any,id: string,operationId: string,release: (string)->(boolean,string?)): (boolean,string?)
 if operationId~="Bank:"..id then return false,"INVALID_BANK_CONFIRMATION" end
 local operation=pending[id]
 if not operation then
  if members[id]==nil then return true,"ALREADY_CONFIRMED" end
  return false,"BANK_NOT_PENDING"
 end
 if operation.OperationId~=operationId then return false,"BANK_OPERATION_CONFLICT" end
 local released,reason=release(id)
 if not released then return false,reason end
 pending[id]=nil
 return true,nil
end
return Barrier
