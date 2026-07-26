--!strict

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
	Warnings: { string },
}

local CartSpawnValidator = {}

function CartSpawnValidator.Validate(spawnPart: BasePart): ValidationResult
	local errors: { string } = {}
	local warnings: { string } = {}

	local spawnId = spawnPart:GetAttribute("SpawnId")
	local cartId = spawnPart:GetAttribute("CartId")
	local enabled = spawnPart:GetAttribute("Enabled")
	local priority = spawnPart:GetAttribute("Priority")
	local debugOnly = spawnPart:GetAttribute("DebugOnly")

	if type(spawnId) ~= "string" or spawnId == "" then
		table.insert(errors, "SpawnId must be a non-empty string")
	end

	if type(cartId) ~= "string" or cartId == "" then
		table.insert(errors, "CartId must be a non-empty string")
	end

	if type(enabled) ~= "boolean" then
		table.insert(errors, "Enabled must be a boolean")
	end

	if type(priority) ~= "number" then
		table.insert(errors, "Priority must be a number")
	elseif priority < 0 then
		table.insert(errors, "Priority must not be negative")
	end

	if debugOnly ~= nil and type(debugOnly) ~= "boolean" then
		table.insert(errors, "DebugOnly must be a boolean when provided")
	end

	if not spawnPart.Anchored then
		table.insert(errors, "Cart spawn parts must be anchored")
	end

	if spawnPart.CanCollide then
		table.insert(warnings, "Cart spawn part should normally have CanCollide disabled")
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
		Warnings = warnings,
	}
end

function CartSpawnValidator.AssertValid(spawnPart: BasePart)
	local result = CartSpawnValidator.Validate(spawnPart)

	for _, warningMessage in result.Warnings do
		warn(string.format("[CartSpawnValidator][%s] %s", spawnPart.Name, warningMessage))
	end

	if not result.IsValid then
		error(
			string.format(
				"Invalid cart spawn %s:\n- %s",
				spawnPart:GetFullName(),
				table.concat(result.Errors, "\n- ")
			),
			2
		)
	end
end

return CartSpawnValidator
