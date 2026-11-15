--!strict
local Policy = require(script.Parent.WorldStudPolicy)
return table.freeze({
	Apply = function(part, legacy)
		return Policy.Apply(part, legacy, "Building")
	end,
})
