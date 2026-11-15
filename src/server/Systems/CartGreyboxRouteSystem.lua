--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartGreyboxConfigValidator =
	require(ReplicatedStorage.Shared.Validation.CartGreyboxConfigValidator)

local CartGreyboxRouteBuilder = require(script.Parent.Parent.Utility.CartGreyboxRouteBuilder)
local RuntimeFolders = require(script.Parent.Parent.Utility.RuntimeFolders)
local CartSpawnRegistry = require(script.Parent.Parent.Services.CartSpawnRegistry)

type BuildResult = CartGreyboxRouteBuilder.BuildResult

local log = Logger.new("CartGreyboxRouteSystem")
local CartGreyboxRouteSystem = {}

local result: BuildResult? = nil
local createdDevelopmentFolder: Folder? = nil
local started = false

local function isAvailable(): boolean
	return Environment.Name == "Development"
		and Environment.EnableDebugTools
		and RunService:IsStudio()
end

local function resolveSpawnFolder(): (Folder?, string?)
	local instance = Workspace:FindFirstChild("CartSpawns")

	if instance == nil or not instance:IsA("Folder") then
		return nil, "Workspace.CartSpawns must exist before the greybox route starts"
	end

	return instance, nil
end

local function resolveCanonicalSpawn(spawnFolder: Folder): (BasePart?, string?)
	local resolved: BasePart? = nil

	for _, child in spawnFolder:GetChildren() do
		if child:GetAttribute("SpawnId") ~= CartGreybox.CanonicalSpawnId then
			continue
		end

		if not child:IsA("BasePart") then
			return nil,
				string.format("canonical spawn %s must be a BasePart", CartGreybox.CanonicalSpawnId)
		end

		if resolved ~= nil then
			return nil,
				string.format("canonical spawn %s is duplicated", CartGreybox.CanonicalSpawnId)
		end

		resolved = child
	end

	if resolved == nil then
		return nil, string.format("canonical spawn %s was not found", CartGreybox.CanonicalSpawnId)
	end

	return resolved, nil
end

local function resolveDevelopmentFolder(): (Folder?, boolean, string?)
	local runtime = RuntimeFolders.GetRuntimeFolder()
	local existing = runtime:FindFirstChild(CartGreybox.RuntimeDevelopmentFolderName)

	if existing ~= nil then
		if not existing:IsA("Folder") then
			return nil,
				false,
				string.format(
					"Workspace.Runtime.%s must be a Folder",
					CartGreybox.RuntimeDevelopmentFolderName
				)
		end

		return existing, false, nil
	end

	local folder = Instance.new("Folder")

	folder.Name = CartGreybox.RuntimeDevelopmentFolderName
	folder.Parent = runtime

	return folder, true, nil
end

function CartGreyboxRouteSystem:Start(): (boolean, string?)
	if started then
		return true, nil
	end

	if not isAvailable() then
		return false, "greybox route is available only in Development Studio"
	end

	local validation = CartGreyboxConfigValidator.Validate(CartGreybox)

	if not validation.IsValid then
		local errorMessage = table.concat(validation.Errors, "; ")

		log:Warn("Greybox route configuration is invalid: %s", errorMessage)

		return false, errorMessage
	end

	local spawnFolder, spawnFolderError = resolveSpawnFolder()

	if spawnFolder == nil then
		log:Warn("Greybox route did not start: %s", spawnFolderError or "missing spawn folder")

		return false, spawnFolderError
	end

	local canonicalSpawn, canonicalError = resolveCanonicalSpawn(spawnFolder)

	if canonicalSpawn == nil then
		log:Warn("Greybox route did not start: %s", canonicalError or "missing canonical spawn")

		return false, canonicalError
	end

	local developmentFolder, folderWasCreated, developmentError = resolveDevelopmentFolder()

	if developmentFolder == nil then
		log:Warn("Greybox route did not start: %s", developmentError or "invalid runtime folder")

		return false, developmentError
	end

	local built, buildError = CartGreyboxRouteBuilder.Build(
		CartGreybox,
		canonicalSpawn.CFrame,
		developmentFolder,
		spawnFolder
	)

	if built == nil then
		if folderWasCreated and #developmentFolder:GetChildren() == 0 then
			developmentFolder:Destroy()
		end

		log:Warn("Greybox route did not start: %s", buildError or "route build failed")

		return false, buildError
	end

	if CartSpawnRegistry:IsStarted() then
		local registrationSucceeded, registrationError = pcall(function()
			CartSpawnRegistry:RegisterSpawns(built.SpawnMarkers)
		end)

		if not registrationSucceeded then
			CartSpawnRegistry:UnregisterSpawns(built.SpawnMarkers)
			CartGreyboxRouteBuilder.Destroy(built)

			if folderWasCreated and #developmentFolder:GetChildren() == 0 then
				developmentFolder:Destroy()
			end

			return false, string.format("route spawn registration failed: %s", registrationError)
		end
	end

	result = built
	createdDevelopmentFolder = if folderWasCreated then developmentFolder else nil
	started = true

	log:Info(
		"Greybox route ready Sections=%d CanonicalSpawn=%s Folder=%s",
		#CartGreybox.Sections,
		CartGreybox.CanonicalSpawnId,
		built.RouteFolder:GetFullName()
	)

	return true, nil
end

function CartGreyboxRouteSystem:GetRouteFolder(): Folder?
	local current = result

	return if current ~= nil then current.RouteFolder else nil
end

function CartGreyboxRouteSystem:GetSectionSpawnId(sectionId: string): string?
	local current = result
	local spawnIds = if current ~= nil then current.SpawnIdsBySection[sectionId] else nil

	return if spawnIds ~= nil then spawnIds[1] else nil
end

function CartGreyboxRouteSystem:GetSectionSpawnIds(sectionId: string): { string }
	local current = result
	local spawnIds = if current ~= nil then current.SpawnIdsBySection[sectionId] else nil

	return if spawnIds ~= nil then table.clone(spawnIds) else {}
end

function CartGreyboxRouteSystem:GetSectionStartCFrame(sectionId: string): CFrame?
	local current = result

	return if current ~= nil then current.StartCFramesBySection[sectionId] else nil
end

function CartGreyboxRouteSystem:Stop()
	if not started then
		return
	end

	started = false

	if result ~= nil then
		CartSpawnRegistry:UnregisterSpawns((result :: BuildResult).SpawnMarkers)
		CartGreyboxRouteBuilder.Destroy(result :: BuildResult)
		result = nil
	end

	if createdDevelopmentFolder ~= nil and #createdDevelopmentFolder:GetChildren() == 0 then
		createdDevelopmentFolder:Destroy()
	end

	createdDevelopmentFolder = nil
	log:Info("Greybox route stopped")
end

return CartGreyboxRouteSystem
