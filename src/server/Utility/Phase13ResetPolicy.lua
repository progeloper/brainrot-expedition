--!strict
-- Pure boundary policy. Cargo survival never promotes fresh identity to ownership.
local Policy = {}
function Policy.Classify(playerInCamp: boolean, cartPresent: boolean, cartInCamp: boolean, worldReady: boolean): any
	if not worldReady then
		return { Policy = "H", ForfeitHeld = false, ForfeitCargo = false, KillCharacter = false, ReturnCart = false }
	end
	return {
		Policy = if not playerInCamp
			then (if cartInCamp then "D" else "A")
			elseif cartPresent and not cartInCamp then "C"
			else "B",
		ForfeitHeld = true,
		ForfeitCargo = false,
		KillCharacter = not playerInCamp,
		ReturnCart = cartPresent and (not playerInCamp or not cartInCamp),
	}
end
return table.freeze(Policy)
