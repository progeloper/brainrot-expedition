--!strict
-- SeatPart can retain a former seat after its occupant/weld has cleared.
-- Actual sitting state or current physical occupancy still blocks on-foot actions.
local SeatState = {}
function SeatState.IsSeated(humanoid: Humanoid): boolean
 local seat = humanoid.SeatPart
 return humanoid.Sit or humanoid:GetState() == Enum.HumanoidStateType.Seated
  or (seat ~= nil and seat.Occupant == humanoid)
end
return table.freeze(SeatState)
