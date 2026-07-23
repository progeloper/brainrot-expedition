--!strict

local ConfigValidator = {}

function ConfigValidator.AssertUniqueIds(categoryName: string, entries: { [string]: string })
	local seen: { [string]: string } = {}

	for key, id in entries do
		assert(
			type(id) == "string" and id ~= "",
			string.format("%s.%s has an invalid ID", categoryName, key)
		)

		local previousKey = seen[id]

		assert(
			previousKey == nil,
			string.format(
				"%s contains duplicate ID %s for %s and %s",
				categoryName,
				id,
				previousKey or "?",
				key
			)
		)

		seen[id] = key
	end
end

return ConfigValidator
