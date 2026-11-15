--!nocheck

return function()
	local Players = game:GetService("Players")
	local WorldLifecycle = require(script.Parent.Parent.Services.PlayerWorldLifecycle)

	local nextUserId = 30000
	local function player()
		nextUserId += 1
		local attributes = {}
		local value = {
			Name = "WorldLifecycleFixture",
			UserId = nextUserId,
			Parent = Players,
		}
		function value:SetAttribute(name, attribute)
			attributes[name] = attribute
		end
		function value:GetAttribute(name)
			return attributes[name]
		end
		function value:Kick(message)
			self.Kicked = message
		end
		return value
	end

	local function run(callback)
		WorldLifecycle:_ResetForTests()
		local readyEvent = Instance.new("BindableEvent")
		local cartSpawned = Instance.new("BindableEvent")
		local baseAssigned
		local baseReleasing
		local sessionGeneration = 1
		local profileStatus = {}
		local assignments = {}
		local bindings = {}
		local carts = {}
		local spawnCount = 0
		local bindCount = 0
		local delayed = {}
		local base = Instance.new("Model")
		base.Name = "WorldLifecycleBase"
		base:SetAttribute("BaseId", "SPEC_BASE")
		local cart = Instance.new("Model")
		cart.Name = "WorldLifecycleCart"
		local profile = {}
		local function sameAssignment(left, right)
			return left ~= nil
				and right ~= nil
				and left.Player == right.Player
				and left.Base == right.Base
				and left.BaseId == right.BaseId
				and left.Generation == right.Generation
		end
		local function assignmentSnapshot(handle)
			if handle == nil then
				return nil
			end
			return {
				Player = handle.Player,
				Base = handle.Base,
				BaseId = handle.BaseId,
				Generation = handle.Generation,
			}
		end
		function profile:GetStatus(subject)
			return profileStatus[subject] or "Loading"
		end
		function profile:GetSessionHandle(subject)
			if self:GetStatus(subject) ~= "Ready" then
				return nil
			end
			return {
				Player = subject,
				UserId = subject.UserId,
				Generation = sessionGeneration,
			}
		end
		function profile:IsCurrentSessionHandle(handle)
			return handle ~= nil
				and handle.Player.Parent == Players
				and profileStatus[handle.Player] == "Ready"
				and handle.Generation == sessionGeneration
		end
		function profile:SubscribeReady(callbackValue)
			local connection = readyEvent.Event:Connect(callbackValue)
			return connection
		end
		local baseSystem = {}
		function baseSystem:GetAssignment(subject)
			return assignmentSnapshot(assignments[subject])
		end
		function baseSystem:IsCurrentAssignment(handle)
			return handle ~= nil
				and sameAssignment(assignments[handle.Player], handle)
				and handle.Player.Parent == Players
		end
		function baseSystem:AssignBase(subject)
			if assignments[subject] then
				return assignments[subject].Base
			end
			local handle = {
				Player = subject,
				Base = base,
				BaseId = "SPEC_BASE",
				Generation = 1,
			}
			assignments[subject] = handle
			if baseAssigned then
				baseAssigned(subject, base, assignmentSnapshot(handle))
			end
			return base
		end
		function baseSystem:SubscribeAssignments(assigned, releasing)
			baseAssigned, baseReleasing = assigned, releasing
			return { Disconnect = function() end }
		end
		local storage = {}
		function storage:EnsureBound(subject, assignedBase, handle)
			if not sameAssignment(assignments[subject], handle) or assignedBase ~= handle.Base then
				return false, "STALE_ASSIGNMENT"
			end
			bindCount += 1
			bindings[subject] = handle
			return true
		end
		function storage:GetBindingHandle(subject)
			return bindings[subject]
		end
		local cartService = { CartSpawned = cartSpawned.Event }
		function cartService:GetCart(subject)
			return carts[subject]
		end
		function cartService:SpawnCart(subject)
			spawnCount += 1
			carts[subject] = cart
			return cart
		end
		WorldLifecycle:Start({
			Profile = profile,
			Base = baseSystem,
			Storage = storage,
			Cart = cartService,
			CartEnabled = true,
			Delay = function(_, callbackValue)
				table.insert(delayed, callbackValue)
			end,
		})
		local ok, failure = xpcall(function()
			callback({
				Ready = function(subject)
					profileStatus[subject] = "Ready"
				end,
				Restore = function(subject)
					return WorldLifecycle:TryRestoreWorld(subject)
				end,
				Assignments = assignments,
				Bindings = bindings,
				SameAssignment = sameAssignment,
				Carts = carts,
				Base = base,
				Cart = cart,
				BaseAssigned = function(subject, handle)
					baseAssigned(subject, handle.Base, handle)
				end,
				BaseReleasing = function(subject, handle)
					baseReleasing(subject, handle.Base, handle)
				end,
				SetSessionGeneration = function(value)
					sessionGeneration = value
				end,
				SetSpawn = function(callbackValue)
					cartService.SpawnCart = callbackValue
				end,
				SpawnCount = function()
					return spawnCount
				end,
				BindCount = function()
					return bindCount
				end,
				Delayed = delayed,
			})
		end, debug.traceback)
		WorldLifecycle:_ResetForTests()
		readyEvent:Destroy()
		cartSpawned:Destroy()
		base:Destroy()
		cart:Destroy()
		assert(ok, failure)
	end

	describe("Phase 7A-3 ordered world reconstruction", function()
		it("waits for a profile, then binds base, slots and cart once", function()
			run(function(f)
				local subject = player()
				expect(f.Restore(subject).code).to.equal("PROFILE_NOT_READY")
				f.Ready(subject)
				local restored = f.Restore(subject)
				expect(restored.ok).to.equal(true)
				expect(WorldLifecycle:IsReady(subject)).to.equal(true)
				expect(f.BindCount()).to.equal(1)
				expect(f.SpawnCount()).to.equal(1)
				expect(f.Restore(subject).code).to.equal("ALREADY_READY")
				expect(f.BindCount()).to.equal(1)
				expect(f.SpawnCount()).to.equal(1)
			end)
		end)

		it("rejects a late cart preparation from an old profile generation", function()
			run(function(f)
				local subject = player()
				f.Ready(subject)
				f.SetSpawn(function(_, currentPlayer)
					f.SetSessionGeneration(2)
					f.Carts[currentPlayer] = f.Cart
					return f.Cart
				end)
				local result = f.Restore(subject)
				expect(result.ok).to.equal(false)
				expect(result.code).to.equal("STALE_RESTORATION")
				expect(WorldLifecycle:IsReady(subject)).to.equal(false)
			end)
		end)

		it("rebinds a new assignment without accepting the old release callback", function()
			run(function(f)
				local subject = player()
				f.Ready(subject)
				expect(f.Restore(subject).ok).to.equal(true)
				local old = f.Assignments[subject]
				local replacement = {
					Player = subject,
					Base = f.Base,
					BaseId = "SPEC_BASE",
					Generation = old.Generation + 1,
				}
				f.Assignments[subject] = replacement
				f.BaseAssigned(subject, replacement)
				f.Bindings[subject] = replacement
				expect(f.Restore(subject).ok).to.equal(true)
				f.BaseReleasing(subject, old)
				expect(f.Assignments[subject]).to.equal(replacement)
				expect(f.SameAssignment(f.Bindings[subject], replacement)).to.equal(true)
			end)
		end)

		it("keeps one reconstruction per session across 100 controlled joins", function()
			run(function(f)
				for _ = 1, 100 do
					local subject = player()
					f.Ready(subject)
					expect(f.Restore(subject).ok).to.equal(true)
					expect(f.Restore(subject).code).to.equal("ALREADY_READY")
					WorldLifecycle:BeginClosing(subject, "Fixture")
					expect(WorldLifecycle:GetStatus(subject)).to.equal("Closing")
				end
				expect(f.BindCount()).to.equal(100)
				expect(f.SpawnCount()).to.equal(100)
			end)
		end)
	end)
end
