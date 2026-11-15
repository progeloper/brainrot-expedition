--!strict
-- Playtest Fixes 2 Part E: the resolved feature switches for this session, so a Studio play-test can
-- be compared with a live server. Every boolean FeatureFlag resolves the way its gate module does:
-- the flag, or (Studio only) its ReplicatedStorage "<Name>Preview" attribute set explicitly to true.
-- The server prints the table at start; Settings shows ReleaseId plus a short hash of it (E2).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Deployment = require(ReplicatedStorage.Shared.Config.Deployment)

local SwitchTable = {}

export type Row = { name: string, flag: boolean, preview: boolean, resolved: boolean }

-- Pure: one switch's resolution (opt-in Studio preview).
function SwitchTable.Resolve(flag: boolean, isStudio: boolean, previewAttribute: any): boolean
	return flag or (isStudio and previewAttribute == true)
end

function SwitchTable.Rows(): { Row }
	local rows: { Row } = {}
	local isStudio = RunService:IsStudio()
	for name, value in FeatureFlags :: any do
		if type(value) == "boolean" then
			local previewName = string.gsub(name, "Enabled$", "Preview")
			local preview = previewName ~= name
				and isStudio
				and ReplicatedStorage:GetAttribute(previewName) == true
			table.insert(rows, {
				name = name,
				flag = value,
				preview = preview == true,
				resolved = SwitchTable.Resolve(value, isStudio, if preview then true else nil),
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

-- Pure: a 6-hex-digit hash of the resolved values (djb2 over "name=0|1;").
function SwitchTable.HashRows(rows: { Row }): string
	local h = 5381
	for _, row in rows do
		local text = row.name .. "=" .. (if row.resolved then "1" else "0") .. ";"
		for i = 1, #text do
			h = (h * 33 + string.byte(text, i)) % 16777216
		end
	end
	return string.format("%06x", h)
end

function SwitchTable.Hash(): string
	return SwitchTable.HashRows(SwitchTable.Rows())
end

-- "P14_..._R1 · a1b2c3" for the Settings window.
function SwitchTable.Stamp(): string
	return string.format("%s · %s", Deployment.ReleaseId, SwitchTable.Hash())
end

function SwitchTable.Format(): string
	local lines = {
		string.format(
			"[Switches] %s studio=%s hash=%s",
			Deployment.ReleaseId,
			tostring(RunService:IsStudio()),
			SwitchTable.Hash()
		),
	}
	for _, row in SwitchTable.Rows() do
		table.insert(
			lines,
			string.format(
				"  %-28s %s%s",
				row.name,
				if row.resolved then "ON " else "off",
				if row.preview and not row.flag then "  (Studio preview)" else ""
			)
		)
	end
	return table.concat(lines, "\n")
end

return table.freeze(SwitchTable)
