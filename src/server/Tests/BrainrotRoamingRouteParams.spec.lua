--!nocheck
-- Native collision queries with inert, isolated fixture models; no profile bootstrap.
return function()
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	local Workspace = game:GetService("Workspace")

	local function fixture(callback)
		local created = {}
		local function folder(parent, name)
			local existing = parent:FindFirstChild(name)
			if existing then
				return existing
			end
			local value = Instance.new("Folder")
			value.Name, value.Parent = name, parent
			table.insert(created, value)
			return value
		end
		local world = folder(folder(Workspace, "Runtime"), "Brainrots")
		local geometry = Instance.new("Folder")
		geometry.Name, geometry.Parent = "SPEC_ROUTE_QUERY", Workspace
		local origin = Vector3.new(23500, 80, 23500)
		local model = Instance.new("Model")
		model.Name = "SPEC_ROUTE_QUERY_BRAINROT"
		model:SetAttribute("Captured", true) -- This test must not advance movement.
		local function part(parent, name, distance, collidable)
			local value = Instance.new("Part")
			value.Name, value.Size = name, Vector3.new(2, 2, 2)
			value.CFrame = CFrame.new(origin + Vector3.new(distance, 0, 0))
			value.Anchored, value.CanCollide, value.CanQuery = true, collidable, true
			value.Parent = parent
			return value
		end
		local body = part(model, "Body", 4, true)
		model.PrimaryPart, model.Parent = body, world
		local before = Roaming.GetDiagnostics().Registered
		local ok, failure = xpcall(function()
			callback(model, function(name, distance, collidable)
				return part(geometry, name, distance, collidable)
			end, origin)
		end, debug.traceback)
		Roaming.Unregister(model, "TestCleanup")
		model:Destroy()
		geometry:Destroy()
		for index = #created, 1, -1 do
			created[index]:Destroy()
		end
		expect(Roaming.GetDiagnostics().Registered).to.equal(before)
		if not ok then
			error(failure, 0)
		end
	end

	describe("Roaming route query lifecycle", function()
		it("keeps unregistered queries transient with the original collision filter", function()
			fixture(function(model)
				local first = Roaming._TestRouteParams(model)
				-- RaycastParams equality compares values; use a restored sentinel to
				-- distinguish a shared object from separately created equal filters.
				first.IgnoreWater = true
				local second = Roaming._TestRouteParams(model)
				expect(second.IgnoreWater).to.equal(false)
				first.IgnoreWater = false
				expect(first.FilterType).to.equal(Enum.RaycastFilterType.Exclude)
				expect(first.RespectCanCollide).to.equal(true)
				expect(#first.FilterDescendantsInstances).to.equal(1)
				expect(first.FilterDescendantsInstances[1]).to.equal(model)
			end)
		end)

		it("reuses the registered filter while ignoring current and newly added self parts", function()
			fixture(function(model, obstacle, origin)
				expect(Roaming.Register(model)).to.equal(true)
				local first = Roaming._TestRouteParams(model)
				first.IgnoreWater = true
				for _ = 1, 500 do
					expect(Roaming._TestRouteParams(model).IgnoreWater).to.equal(true)
				end
				first.IgnoreWater = false
				local blocker = obstacle("SolidBlocker", 10, true)
				obstacle("NonCollidableDecoration", 6, false)
				local newlyAddedSelfPart = obstacle("NewSelfPart", 2, true)
				newlyAddedSelfPart.Parent = model
				local hit = Workspace:Raycast(origin, Vector3.new(20, 0, 0), first)
				expect(hit and hit.Instance).to.equal(blocker)
				local cast = Workspace:Blockcast(CFrame.new(origin), Vector3.one, Vector3.new(20, 0, 0), first)
				expect(cast and cast.Instance).to.equal(blocker)
			end)
		end)

		it("drops the controller cache on unregister, removal and destruction", function()
			fixture(function(model)
				local before = Roaming.GetDiagnostics().Registered
				expect(Roaming.Register(model)).to.equal(true)
				local first = Roaming._TestRouteParams(model)
				first.IgnoreWater = true
				expect(Roaming.Register(model)).to.equal(true)
				expect(Roaming._TestRouteParams(model).IgnoreWater).to.equal(true)
				expect(Roaming.Unregister(model, "TestCleanup")).to.equal(true)
				expect(Roaming.GetDiagnostics().Registered).to.equal(before)
				expect(Roaming._TestRouteParams(model).IgnoreWater).to.equal(false)
				expect(Roaming.Register(model)).to.equal(true)
				local second = Roaming._TestRouteParams(model)
				expect(second.IgnoreWater).to.equal(false)
				first.IgnoreWater = false
				second.IgnoreWater = true
				local parent = model.Parent
				model.Parent = nil
				task.wait()
				expect(Roaming.GetDiagnostics().Registered).to.equal(before)
				model.Parent = parent
				expect(Roaming.Register(model)).to.equal(true)
				expect(Roaming._TestRouteParams(model).IgnoreWater).to.equal(false)
				second.IgnoreWater = false
				model:Destroy()
				task.wait()
				expect(Roaming.GetDiagnostics().Registered).to.equal(before)
			end)
		end)
	end)
end
