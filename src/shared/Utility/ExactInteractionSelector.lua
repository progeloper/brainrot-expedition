--!strict
local C=require(script.Parent.Parent.Config.PlaytestExact).Interaction
local Selector={}
function Selector.Score(angle,distance)return C.AngleWeight*(angle/C.AcquireAngle)+C.DistanceWeight*(distance/C.Range)end
function Selector.new()
 local current,challenger,since=nil,nil,nil
 local api={}
 function api.Update(candidates,now)
  local retained,best=nil,nil
  for _,row in ipairs(candidates)do
   row.score=Selector.Score(row.angle,row.distance)
   if row.valid and row.distance<=math.min(C.Range,row.serverRange)then
    if current and row.id==current.id and row.revision==current.revision and row.angle<=C.RetainAngle then retained=row end
    if row.angle<=C.AcquireAngle and (not best or (row.drive~=true and best.drive==true)
     or row.drive==best.drive and (row.score<best.score or row.score==best.score and row.id<best.id))then best=row end
   end
  end
  if not retained then current=best;challenger,since=nil,nil;return current end
  if best and best.id~=retained.id and ((retained.drive==true and best.drive~=true)
   or retained.drive==best.drive and retained.score-best.score>=C.SwitchAdvantage)then
   if challenger~=best.id then challenger,since=best.id,now end
   if now-since>=C.SwitchDwell then current=best;challenger,since=nil,nil else current=retained end
  else current=retained;challenger,since=nil,nil end
  return current
 end
 function api.Clear()current,challenger,since=nil,nil,nil end
 return api
end
return table.freeze(Selector)
