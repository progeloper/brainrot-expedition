--!strict
-- Explicit physical-world roots; construction/stream events, never frame scans.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Policy = require(RS.Shared.Utility.WorldStudPolicy)
local Binding = {}
local started = false
local watched = setmetatable({}, { __mode = "k" })
local function bind(root: Instance, family: string)
	if watched[root] then
		return
	end
	watched[root] = true
	Policy.ApplyModel(root, family)
	root.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			-- Finish the constructor's property writes before binding the surface once.
			task.defer(function()
				if part:IsDescendantOf(root) then
					Policy.Apply(part, nil, family)
				end
			end)
		end
	end)
end
function Binding.Start()
	if started then
		return
	end
	started = true
	local studs = require(RS.Shared.Config.AfternoonRepair).Studs
	local materials = game:GetService("MaterialService")
	for _, name in studs.TerrainMaterials do
		materials:SetBaseMaterialOverride(Enum.Material[name], "AF2_Building_" .. name)
	end
	local map = workspace:FindFirstChild("MapBlockout")
	if map then
		bind(map, "Building")
	end
	local burrows = workspace:FindFirstChild("Phase12Burrows")
	if burrows then
		bind(burrows, "Building")
	end
	local runtime = workspace:FindFirstChild("Runtime")
	if runtime then
		local carts = runtime:FindFirstChild("Carts")
		if carts then
			bind(carts, "Prop")
		end
		runtime.ChildAdded:Connect(function(child)
			if child.Name == "Carts" then
				bind(child, "Prop")
			end
		end)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Phase12Burrows" then
			bind(child, "Building")
		end
		if child.Name == "Runtime" then
			local carts = child:FindFirstChild("Carts")
			if carts then
				bind(carts, "Prop")
			end
			child.ChildAdded:Connect(function(x)
				if x.Name == "Carts" then
					bind(x, "Prop")
				end
			end)
		end
	end)
	local function playerAdded(player: Player)
		local function character(c: Model)
			for _, tool in c:GetChildren() do
				if tool:IsA("Tool") then
					bind(tool, "Creature")
				end
			end
			c.ChildAdded:Connect(function(tool)
				if tool:IsA("Tool") then
					bind(tool, "Creature")
				end
			end)
		end
		player.CharacterAdded:Connect(character)
		if player.Character then
			character(player.Character)
		end
	end
	Players.PlayerAdded:Connect(playerAdded)
	for _, p in Players:GetPlayers() do
		playerAdded(p)
	end
end
return Binding
