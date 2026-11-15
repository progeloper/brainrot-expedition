--!strict
-- A cart has one direct authored human seat. Equipped brainrot formation slots
-- are unrelated to this contract and never confer human occupancy authority.
local Contract = {}

function Contract.GetDriverSeat(cart: Model): VehicleSeat?
	local driver: VehicleSeat? = nil
	local count = 0
	for _, child in cart:GetChildren() do
		if child.Name == "DriverSeat" then
			count += 1
			if child:IsA("VehicleSeat") then
				driver = child
			end
		end
	end
	return if count == 1 then driver else nil
end

function Contract.IsSeat(cart: Model, instance: Instance?): boolean
	return instance ~= nil and Contract.GetDriverSeat(cart) == instance
end

function Contract.SeatForJoint(cart: Model, joint: Instance): VehicleSeat?
	local seat = joint.Parent
	return if Contract.IsSeat(cart, seat) then seat :: VehicleSeat else nil
end

function Contract.IsCurrentJoint(cart: Model, instance: Instance): boolean
	if not instance:IsA("JointInstance") then
		return false
	end
	local seat = Contract.SeatForJoint(cart, instance)
	if seat == nil then
		return false
	end
	local occupant = seat.Occupant
	local character = occupant and occupant.Parent
	if not character or not character:IsA("Model") then
		return false
	end
	local first, second = instance.Part0, instance.Part1
	return (first == seat and second ~= nil and second:IsDescendantOf(character))
		or (second == seat and first ~= nil and first:IsDescendantOf(character))
end

return table.freeze(Contract)
