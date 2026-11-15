--!nocheck

return function()
	local Workspace = game:GetService("Workspace")
	local source = script.Parent.Parent.Services.CartSpawnRegistry

	local function withRegistry(callback)
		-- This suite runs in the isolated test place, never against the editable map.
		assert(
			Workspace:FindFirstChild("CartSpawns") == nil,
			"Test requires no shared spawn folder"
		)
		local folder = Instance.new("Folder")
		folder.Name = "CartSpawns"
		folder.Parent = Workspace
		local module = source:Clone()
		module.Name = "CartSpawnRegistryTest"
		module.Parent = source.Parent
		local registry = require(module)
		local ok, err = xpcall(function()
			callback(registry, folder)
		end, debug.traceback)
		registry:Stop()
		module:Destroy()
		folder:Destroy()
		assert(ok, err)
	end

	local function makeSpawn(folder, id)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part:SetAttribute("SpawnId", id)
		part:SetAttribute("CartId", "CRT_001")
		part:SetAttribute("Enabled", true)
		part:SetAttribute("Priority", 0)
		part.Parent = folder
		return part
	end

	describe("CartSpawnRegistry without legacy pads", function()
		it("starts with an empty shared folder without inventing fallback spawns", function()
			withRegistry(function(registry, folder)
				registry:Start()
				registry:Start()
				expect(registry:IsStarted()).to.equal(true)
				expect(#registry:GetAll()).to.equal(0)
				expect(registry:GetById("CSP_001")).to.equal(nil)
				expect(registry:GetDefaultForCart("CRT_001")).to.equal(nil)
				expect(#folder:GetChildren()).to.equal(0)
				registry:Stop()
				registry:Start()
				expect(registry:IsStarted()).to.equal(true)
			end)
		end)

		it("still accepts explicitly registered pads after an empty start", function()
			withRegistry(function(registry, folder)
				registry:Start()
				local part = makeSpawn(folder, "CSP_REGISTRY_TEST")
				registry:RegisterSpawns({ part })
				expect(registry:GetById("CSP_REGISTRY_TEST").Part).to.equal(part)
				expect(registry:GetDefaultForCart("CRT_001").Part).to.equal(part)
				registry:UnregisterSpawns({ part })
				expect(#registry:GetAll()).to.equal(0)
				expect(registry:IsStarted()).to.equal(true)
			end)
		end)

		it("still discovers authored shared pads and rejects duplicate registrations", function()
			withRegistry(function(registry, folder)
				local part = makeSpawn(folder, "CSP_REGISTRY_TEST")
				registry:Start()
				expect(registry:GetById("CSP_REGISTRY_TEST").Part).to.equal(part)
				local duplicate = makeSpawn(folder, "CSP_REGISTRY_TEST")
				local accepted = pcall(function()
					registry:RegisterSpawns({ duplicate })
				end)
				expect(accepted).to.equal(false)
				expect(registry:GetById("CSP_REGISTRY_TEST").Part).to.equal(part)
			end)
		end)

		it("does not relax validation for malformed or unknown-cart pads", function()
			withRegistry(function(registry, folder)
				local part = makeSpawn(folder, "CSP_REGISTRY_TEST")
				part:SetAttribute("SpawnId", nil)
				expect(pcall(function()
					registry:Start()
				end)).to.equal(false)
				expect(registry:IsStarted()).to.equal(false)
				part:SetAttribute("SpawnId", "CSP_REGISTRY_TEST")
				part:SetAttribute("CartId", "CRT_UNKNOWN")
				expect(pcall(function()
					registry:Start()
				end)).to.equal(false)
				expect(#registry:GetAll()).to.equal(0)
			end)
		end)
	end)
end
