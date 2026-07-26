--!strict

local Workspace = game:GetService("Workspace")

local RuntimeFolders = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)

	if existing ~= nil then
		assert(
			existing:IsA("Folder"),
			string.format("%s.%s must be a Folder", parent:GetFullName(), name)
		)

		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	return folder
end

function RuntimeFolders.GetRuntimeFolder(): Folder
	return getOrCreateFolder(Workspace, "Runtime")
end

function RuntimeFolders.GetCartsFolder(): Folder
	local runtime = RuntimeFolders.GetRuntimeFolder()

	return getOrCreateFolder(runtime, "Carts")
end

return RuntimeFolders
