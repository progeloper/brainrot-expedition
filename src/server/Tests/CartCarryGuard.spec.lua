--!nocheck
-- Isolated service/seat fixtures, NOT multiplayer driving tests. Players,
-- carry notifications, assembly readiness and ownership assignment are adapters.
-- Real Humanoids and SeatWelds exercise native boarding, deferred admission and
-- rejection. Only the Player lookup/physics/readiness boundaries are adapters.
-- A cloned-source lookup adapter maps only these fixture characters to table players.
return function()
	local Players = game:GetService("Players")
	local Services = script.Parent.Parent.Services
	local Authority = require(script.Parent.Parent.Utility.CartDriverAuthority)
	local Assembly = require(Services.CartAssemblyValidationService)

	local function awaitState(predicate, message)
		local deadline = os.clock() + 5
		local passed
		repeat
			task.wait()
			passed = predicate()
		until passed or os.clock() >= deadline
		if not passed then
			error(if type(message) == "function" then message() else message, 2)
		end
	end

	local function nativeState(f, owner, cart)
		local seat, humanoid = cart.DriverSeat, owner.Character.Humanoid
		local driver = f.service:GetDriver(cart)
		local function label(instance)
			return if instance then instance:GetFullName() else "nil"
		end
		return string.format(
			"DriverUserId=%s ActiveDriverUserId=%s Occupant=%s SeatPart=%s Sit=%s State=%s SeatWeld=%s ready=%s writable=%s running=%s wallElapsed=%.3f simulationElapsed=%.3f",
			tostring(driver and driver.UserId), tostring(cart:GetAttribute("ActiveDriverUserId")),
			label(seat.Occupant), label(humanoid.SeatPart), tostring(humanoid.Sit),
			tostring(humanoid:GetState()), label(seat:FindFirstChild("SeatWeld")),
			tostring(f.ready[owner] ~= false), tostring(f.writable[owner] ~= false),
			tostring(game:GetService("RunService"):IsRunning()),
			os.clock() - f.wallStarted, time() - f.simulationStarted
		)
	end

	local function finishNativeDismount(f, owner, cart)
		local seat, humanoid = cart.DriverSeat, owner.Character.Humanoid
		if seat.Occupant ~= nil then return end
		local exitedAt = f.nativeExits[humanoid]
		if exitedAt then
			-- The service must finish the native exit without a QA Jump,
			-- ChangeState, Move, SeatPart assignment or character pose recovery.
			-- Native Seat currently ignores same-character requests for three
			-- simulation seconds after exit. Wait once instead of flooding Sit
			-- every heartbeat while the native controller is still dismounting.
			awaitState(function() return f.simulationNow() - exitedAt >= 3.2 end, function()
				return string.format("Native seat cooldown did not advance: elapsed=%.3f exit=%.3f now=%.3f; %s",
					f.simulationNow() - exitedAt, exitedAt, f.simulationNow(), nativeState(f, owner, cart))
			end)
			awaitState(function() return humanoid.SeatPart == nil and not humanoid.Sit end, function()
				return "Rejected native seat exit did not clear SeatPart without controller assistance: " .. nativeState(f, owner, cart)
			end)
			f.nativeExits[humanoid] = nil
		end
	end

	local function awaitAdmission(f, owner, cart)
		finishNativeDismount(f, owner, cart)
		local seat, humanoid = cart.DriverSeat, owner.Character.Humanoid
		-- Native seats currently have a per-character/per-seat cooldown. A Sit
		-- request during it is discarded; retry real boarding while vacant instead
		-- of forcing authority or assuming one early request will be replayed.
		awaitState(function()
			if f.service:GetDriver(cart) == owner and seat.Occupant == humanoid and humanoid.SeatPart == seat then
				return true
			end
			if seat.Occupant == nil then
				seat:Sit(humanoid)
			end
			return false
		end, function()
			return "Native owner boarding did not reach exact accepted occupancy: " .. nativeState(f, owner, cart)
		end)
	end

	local function awaitRejection(f, cart)
		awaitState(function()
			return f.service:GetDriver(cart) == nil
				and cart.DriverSeat.Occupant == nil
				and cart.DriverSeat:FindFirstChild("SeatWeld") == nil
		end, "Native rejected occupant retained authority, occupancy or SeatWeld")
	end

	local function requestRejectedBoarding(f, owner, cart)
		finishNativeDismount(f, owner, cart)
		local seat, humanoid = cart.DriverSeat, owner.Character.Humanoid
		local observed = false
		local connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant == humanoid then observed = true end
		end)
		local ok, failure = xpcall(function()
			awaitState(function()
				if observed then return true end
				if seat.Occupant == nil then seat:Sit(humanoid) end
				return false
			end, function()
				return "Native invalid boarding request never entered the seat: " .. nativeState(f, owner, cart)
			end)
			awaitRejection(f, cart)
		end, debug.traceback)
		connection:Disconnect()
		if not ok then error(failure, 0) end
	end

	local function fixture(callback)
		local PhysicsService = game:GetService("PhysicsService")
		local characterGroup, cartGroup = "SPEC_CARRY_CHARACTER", "SPEC_CARRY_CART"
		assert(not PhysicsService:IsCollisionGroupRegistered(characterGroup), "Fixture character collision group leaked")
		assert(not PhysicsService:IsCollisionGroupRegistered(cartGroup), "Fixture cart collision group leaked")
		PhysicsService:RegisterCollisionGroup(characterGroup)
		PhysicsService:RegisterCollisionGroup(cartGroup)
		-- Native boarding still creates its real joint. Prevent the diagnostic
		-- avatars pushing a cart while the deferred callback rejects that joint;
		-- both groups retain ordinary collision with their local Default floor.
		PhysicsService:CollisionGroupSetCollidable(characterGroup, cartGroup, false)
		PhysicsService:CollisionGroupSetCollidable(characterGroup, characterGroup, false)
		local originalNew, originalValid, originalState =
			Authority.new, Assembly.IsCartValid, Assembly.GetState
		local service, privateAuthority
		local networkOwners = {}
		local clone = Services.CartOccupantService:Clone()
		clone.Name, clone.Parent = "CartOccupantCarrySpec", Services
		local fixtureLookup = Instance.new("ModuleScript")
		fixtureLookup.Name = "FixturePlayers"
		fixtureLookup.Source = "return { ByCharacter = {}, Defer = task.defer }"
		fixtureLookup.Parent = clone
		local lookup = require(fixtureLookup)
		local mappedPlayers = lookup.ByCharacter
		clone.Source = clone.Source:gsub(
			"Players:GetPlayerFromCharacter%(character%)",
			"require(script.FixturePlayers).ByCharacter[character]"
		)
		clone.Source = clone.Source:gsub("task%.defer%(", "require(script.FixturePlayers).Defer(")
		local world = Instance.new("Folder")
		world.Name, world.Parent = "SPEC_CARRY_DRIVER", workspace
		-- A running disposable simulation needs local support; no global gravity,
		-- production map or cart properties are changed by this fixture floor.
		local floor = Instance.new("Part")
		floor.Name, floor.Size, floor.Position = "FixtureFloor", Vector3.new(512, 2, 512), Vector3.new(16000, 98, 16000)
		floor.Anchored, floor.Parent = true, world
		local carryCallback
		local carryChanged = { Event = {} }
		function carryChanged.Event:Connect(listener)
			carryCallback = listener
			return {
				Disconnect = function()
					carryCallback = nil
				end,
			}
		end
		function carryChanged:Fire(p)
			if carryCallback then
				carryCallback(p)
			end
		end
		local carrying, ready, writable, removingEvents, nativeExits, seatSignals = {}, {}, {}, {}, {}, {}
		local simulationSeconds = 0
		table.insert(seatSignals, game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
			simulationSeconds += deltaTime
		end))
		local function part(parent, name, position, class)
			local p = Instance.new(class or "Part")
			p.Name, p.Size, p.Position, p.Parent = name, Vector3.new(2, 2, 2), position, parent
			p.Anchored = false
			p.CollisionGroup = if parent:IsA("Model") and parent.Name == "CarryGuardCart" then cartGroup else characterGroup
			return p
		end
		local function player(id, x)
			local removing = Instance.new("BindableEvent")
			table.insert(removingEvents, removing)
			local attributes, attributeEvents = {}, {}
			local p = {
				Name = "CarryGuard" .. tostring(id),
				UserId = id,
				Parent = Players,
				CharacterRemoving = removing.Event,
			}
			function p:GetAttribute(name) return attributes[name] end
			function p:GetAttributeChangedSignal(name)
				if not attributeEvents[name] then
					local event = Instance.new("BindableEvent")
					table.insert(removingEvents, event)
					attributeEvents[name] = event
				end
				return attributeEvents[name].Event
			end
			function p:SetAttribute(name, value)
				attributes[name] = value
				if attributeEvents[name] then attributeEvents[name]:Fire() end
			end
			local character = Instance.new("Model")
			character.Name, character.Parent = p.Name, world
			local root = part(character, "HumanoidRootPart", Vector3.new(x, 104, 16000))
			root.Size, root.CanCollide = Vector3.new(2, 2, 1), false
			local torso = part(character, "Torso", root.Position)
			torso.Size = Vector3.new(2, 2, 1)
			local function motor(name, first, second, c0, c1)
				local joint = Instance.new("Motor6D")
				joint.Name, joint.Part0, joint.Part1 = name, first, second
				joint.C0, joint.C1, joint.Parent = c0, c1, first
			end
			motor("RootJoint", root, torso, CFrame.identity, CFrame.identity)
			local head = part(character, "Head", root.Position + Vector3.new(0, 1.5, 0))
			head.Size, head.CanCollide = Vector3.new(2, 1, 1), false
			motor("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -.5, 0))
			for _, definition in {
				{ "Left Arm", "Left Shoulder", -1.5, 0, -1, .5, .5 },
				{ "Right Arm", "Right Shoulder", 1.5, 0, 1, .5, -.5 },
				{ "Left Leg", "Left Hip", -.5, -2, -.5, -1, 0 },
				{ "Right Leg", "Right Hip", .5, -2, .5, -1, 0 },
			} do
				local limb = part(character, definition[1], root.Position + Vector3.new(definition[3], definition[4], 0))
				limb.Size, limb.CanCollide = Vector3.new(1, 2, 1), false
				motor(definition[2], torso, limb,
					CFrame.new(definition[5], definition[6], 0),
					CFrame.new(definition[7], if definition[4] == -2 then 1 else .5, 0))
			end
			character.PrimaryPart = root
			local h = Instance.new("Humanoid")
			h.RigType, h.HipHeight = Enum.HumanoidRigType.R6, 0
			h.RequiresNeck, h.Parent = true, character
			p.Character = character
			mappedPlayers[character] = p
			-- Native actor initialization is separate from the owner's logical
			-- world/profile readiness. A real character has initialized RootPart
			-- and state machinery before reaching its cart.
			local runService = game:GetService("RunService")
			assert(runService:IsRunning(), "Native boarding fixtures require the running simulation runner")
			runService.Heartbeat:Wait()
			runService.Heartbeat:Wait()
			awaitState(function()
				return h.RootPart == root and h.Health > 0
			end, "Native R6 character did not initialize its living HumanoidRootPart")
			return p
		end
		local function cart(owner)
			local model = Instance.new("Model")
			model.Name, model.Parent = "CarryGuardCart", world
			model:SetAttribute("RuntimeCart", true)
			model:SetAttribute("CartId", "CRT_GUARD_SPEC")
			local root = part(model, "Root", Vector3.new(16000, 100, 16000))
			model.PrimaryPart = root
			for _, definition in { { "DriverSeat", "VehicleSeat", 0 } } do
				local seat = part(
					model,
					definition[1],
					root.Position + Vector3.new(definition[3], 2, 0),
					definition[2]
				)
				seat.CanTouch = false -- Explicit native Sit calls isolate admission from incidental contact.
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1, weld.Parent = root, seat, root
				local previousOccupant = seat.Occupant
				table.insert(seatSignals, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
					local nextOccupant = seat.Occupant
					if previousOccupant and nextOccupant ~= previousOccupant then
						nativeExits[previousOccupant] = simulationSeconds
					end
					previousOccupant = nextOccupant
				end))
			end
			assert(service:RegisterCart(model, owner.UserId))
			return model
		end
		local ok, failure = xpcall(function()
			Authority.new = function(adapter)
				adapter.SetNetworkOwner = function(record, owner)
					networkOwners[record.Cart] = owner
					return true
				end
				privateAuthority = originalNew(adapter)
				return privateAuthority
			end
			Assembly.IsCartValid = function()
				return true
			end
			Assembly.GetState = function()
				return "Valid"
			end
			service = require(clone)
			Authority.new = originalNew
			service:Start()
			service:SetDriverEligibilityPredicate(function(p)
				return ready[p] ~= false and writable[p] ~= false, "player is not ready"
			end)
			service:SetCarryingPredicate(function(p)
				return carrying[p] == true
			end, carryChanged.Event)
			callback({
				service = service,
				wallStarted = os.clock(),
				simulationStarted = time(),
				deferredAdapter = lookup,
				world = world,
				player = player,
				cart = cart,
				carrying = carrying,
				ready = ready,
				writable = writable,
				nativeExits = nativeExits,
				simulationNow = function() return simulationSeconds end,
				changed = carryChanged,
				networkOwners = networkOwners,
				authority = privateAuthority,
			})
		end, debug.traceback)
		if service then
			service:Stop()
			service:SetCarryingPredicate(nil)
			service:SetDriverEligibilityPredicate(nil)
		end
		Authority.new, Assembly.IsCartValid, Assembly.GetState =
			originalNew, originalValid, originalState
		for _, event in removingEvents do
			event:Destroy()
		end
		for _, connection in seatSignals do connection:Disconnect() end
		world:Destroy()
		clone:Destroy()
		PhysicsService:UnregisterCollisionGroup(characterGroup)
		PhysicsService:UnregisterCollisionGroup(cartGroup)
		if not ok then
			error(failure, 0)
		end
	end

	local function exitFenceFixture()
		local registration, token, cart, seat, humanoid, weld = {}, {}, {}, {}, {}, {}
		return {
			Registration = registration, CurrentRegistration = registration,
			Token = token, CurrentPending = token, Cart = cart, CurrentCart = cart,
			Seat = seat, CurrentSeat = seat, ExpectedOccupancySequence = 4, OccupancySequence = 4,
			ExpectedDriverRevision = 7, DriverRevision = 7, Humanoid = humanoid,
			SeatOccupant = humanoid, HumanoidSeat = seat, ExpectedNativeWeld = weld, NativeWeld = weld,
			CartAlive = true, CharacterCurrent = true,
		}
	end
	local ProductionService = require(Services.CartOccupantService)
	describe("Rejected native seat exit identity fences", function()
		it("permits only the original rejected physical entry", function()
			expect(ProductionService.IsCurrentRejectedSeatExit(exitFenceFixture())).to.equal(true)
		end)
		it("never unseats a newly accepted humanoid or a newer authority revision", function()
			local f = exitFenceFixture()
			f.ActiveHumanoid = f.Humanoid
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
			f.ActiveHumanoid, f.DriverRevision = nil, 9 -- a new authority can already be revoked again
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
		end)
		it("rejects a replacement weld and a humanoid now in another seat", function()
			local f = exitFenceFixture()
			f.NativeWeld = {}
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
			f.NativeWeld, f.HumanoidSeat = f.ExpectedNativeWeld, {}
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
		end)
		it("rejects another cart or a replacement registration for the same cart", function()
			local f = exitFenceFixture()
			f.CurrentCart = {}
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
			f.CurrentCart, f.CurrentRegistration = f.Cart, {}
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
		end)
		it("rejects a newer occupancy or pending token and retired character", function()
			local f = exitFenceFixture()
			f.OccupancySequence = 5
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
			f.OccupancySequence, f.CurrentPending = f.ExpectedOccupancySequence, {}
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
			f.CurrentPending, f.CharacterCurrent = f.Token, false
			expect(ProductionService.IsCurrentRejectedSeatExit(f)).to.equal(false)
		end)
	end)

	describe("Carrying guard at the occupant/control authority", function()
		it(
			"rejects real driver-seat occupancy, removes only its SeatWeld and clears native input",
			function()
				fixture(function(f)
					local p = f.player(-30101, 16000)
					local cart = f.cart(p)
					f.carrying[p] = true
					local seat = cart.DriverSeat
					seat:Sit(p.Character.Humanoid)
					seat.ThrottleFloat, seat.SteerFloat = 1, -1
					f.service:EnforceCarryRestriction(p)
					awaitRejection(f, cart)
					expect(f.service:GetDriver(cart)).to.equal(nil)
					expect(seat:FindFirstChild("SeatWeld")).to.equal(nil)
					expect(seat.Disabled).to.equal(false)
					expect(cart.Root.Anchored).to.equal(false)
					expect(seat.ThrottleFloat).to.equal(0)
					expect(seat.SteerFloat).to.equal(0)
					for _ = 1, 5 do
						expect(f.service:CanPlayerControlCart(p, cart)).to.equal(false)
						f.service:RestoreNetworkOwnership(cart) -- Vacant seat may successfully restore the server.
					end
					expect(f.networkOwners[cart]).to.equal(nil)
				end)
			end
		)

		it(
			"carry acquisition revokes an accepted driver and clears only their authority/input",
			function()
				fixture(function(f)
					local p = f.player(-30102, 16000)
					local cart = f.cart(p)
					cart.DriverSeat:Sit(p.Character.Humanoid)
					awaitAdmission(f, p, cart)
					expect(f.service:CanPlayerControlCart(p, cart)).to.equal(true)
					cart.DriverSeat.ThrottleFloat, cart.DriverSeat.SteerFloat = 1, 1
					f.carrying[p] = true
					f.changed:Fire(p)
					awaitRejection(f, cart)
					expect(f.service:GetDriver(cart)).to.equal(nil)
					expect(cart:GetAttribute("ActiveDriverUserId")).to.equal(0)
					expect(f.networkOwners[cart]).to.equal(nil)
					expect(cart.DriverSeat.ThrottleFloat).to.equal(0)
					expect(cart.DriverSeat.SteerFloat).to.equal(0)
					expect(f.service:GetDiagnostics().DriverConnectionCount).to.equal(0)
					f.carrying[p] = false -- Same predicate boundary used by successful Drop/load.
					f.changed:Fire(p)
					expect(f.service:CanEnterDriver(p)).to.equal(true)
				end)
			end
		)

		it(
			"a nearby carrying stranger cannot clear the owner's inputs or ownership",
			function()
				fixture(function(f)
					local driver = f.player(-30103, 16000)
					local stranger = f.player(-30104, 16005)
					local cart = f.cart(driver)
					cart.DriverSeat:Sit(driver.Character.Humanoid)
					awaitAdmission(f, driver, cart)
					cart.DriverSeat.ThrottleFloat, cart.DriverSeat.SteerFloat = 0.8, -0.6
					f.carrying[stranger] = true
					f.changed:Fire(stranger)
					expect(f.service:CanPlayerControlCart(stranger, cart)).to.equal(false)
					expect(f.service:ClearDriverInput(stranger, cart)).to.equal(false)
					expect(f.service:GetDriver(cart)).to.equal(driver)
					expect(f.service:CanPlayerControlCart(driver, cart)).to.equal(true)
					expect(f.networkOwners[cart]).to.equal(driver)
					expect(math.abs(cart.DriverSeat.ThrottleFloat - 0.8) < 0.001).to.equal(true)
					expect(math.abs(cart.DriverSeat.SteerFloat + 0.6) < 0.001).to.equal(true)
					expect(#f.service:GetOccupants(cart)).to.equal(1)
					expect(f.service:GetOccupants(cart)[1]).to.equal(driver)
					expect(stranger.Character.Humanoid.SeatPart).to.equal(nil)
					f.service:UnregisterCart(cart)
					expect(f.service:GetDiagnostics().CartConnectionCount).to.equal(0)
					expect(f.service:GetDiagnostics().DriverConnectionCount).to.equal(0)
					f.service:Stop()
					expect(f.service:GetDiagnostics().SharedConnectionCount).to.equal(0)
				end)
			end
		)
		it("clears rejected native SeatPart before unassisted ready owner re-entry", function()
			fixture(function(f)
				local owner = f.player(-30116, 16000)
				local cart = f.cart(owner)
				local seat, humanoid = cart.DriverSeat, owner.Character.Humanoid
				seat:Sit(humanoid)
				awaitAdmission(f, owner, cart)
				-- Same sequence as the connected human failure: accepted owner,
				-- writability revoke, another real native entry while denied, then
				-- recovery. Only native Seat:Sit establishes these fixture entries.
				f.writable[owner] = false
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(false)
				awaitRejection(f, cart)
				requestRejectedBoarding(f, owner, cart)
				awaitState(function()
					return humanoid.SeatPart == nil
						and not humanoid.Sit
						and seat.Occupant == nil
						and seat:FindFirstChild("SeatWeld") == nil
				end, function()
					return "Rejected native transaction left stale SeatPart: " .. nativeState(f, owner, cart)
				end)
				f.writable[owner] = true
				expect(f.service:CanEnterDriver(owner)).to.equal(true)
				awaitAdmission(f, owner, cart)
				expect(f.service:GetDriver(cart)).to.equal(owner)
				expect(seat.Occupant).to.equal(humanoid)
				expect(humanoid.SeatPart).to.equal(seat)
				expect(f.networkOwners[cart]).to.equal(owner)
				awaitState(function()
					return f.service:GetDiagnostics().PendingSeatExitCount == 0
				end, "Rejected-seat cleanup jobs did not settle")
			end)
		end)

		it("rejects owner boarding until world readiness and profile writability both recover", function()
			fixture(function(f)
				local owner = f.player(-30111, 16000)
				local cart = f.cart(owner)
				f.ready[owner] = false
				expect(select(2, f.service:CanEnterDriver(owner))).to.equal("player is not ready")
				requestRejectedBoarding(f, owner, cart)
				expect(f.service:GetDriver(cart)).to.equal(nil)
				expect(cart.DriverSeat:FindFirstChild("SeatWeld")).to.equal(nil)
				f.ready[owner], f.writable[owner] = true, false
				requestRejectedBoarding(f, owner, cart)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(false)
				expect(cart.DriverSeat:FindFirstChild("SeatWeld")).to.equal(nil)
				f.writable[owner] = true
				cart.DriverSeat:Sit(owner.Character.Humanoid)
				awaitAdmission(f, owner, cart)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
				expect(f.networkOwners[cart]).to.equal(owner)
			end)
		end)

		for _, eligibility in { "ready", "writable" } do
			it("revokes only the owner's current input and seat when " .. eligibility .. " eligibility expires", function()
				fixture(function(f)
					local owner = f.player(-30112, 16000)
					local stranger = f.player(-30113, 16005)
					local cart = f.cart(owner)
					cart.DriverSeat:Sit(owner.Character.Humanoid)
					awaitAdmission(f, owner, cart)
					expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
					cart.DriverSeat.ThrottleFloat, cart.DriverSeat.SteerFloat = 0.7, -0.5
					local revision = f.service:GetDriverRevision(cart)
					f[eligibility][stranger] = false
					f.service:EnforceDriverEligibility(stranger)
					expect(f.service:GetDriver(cart)).to.equal(owner)
					expect(f.service:GetDriverRevision(cart)).to.equal(revision)
					f[eligibility][owner] = false
					if eligibility == "ready" then
						owner:SetAttribute("PlayerWorldStatus", "Restoring")
						awaitRejection(f, cart)
					else
						expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(false)
					end
					awaitRejection(f, cart) -- Native Sit=false cleanup is asynchronous.
					expect(f.service:GetDriver(cart)).to.equal(nil)
					expect(cart:GetAttribute("ActiveDriverUserId")).to.equal(0)
					expect(cart.DriverSeat:FindFirstChild("SeatWeld")).to.equal(nil)
					expect(cart.DriverSeat.ThrottleFloat).to.equal(0)
					expect(cart.DriverSeat.SteerFloat).to.equal(0)
					expect(f.networkOwners[cart]).to.equal(nil)
					expect(f.service:GetDiagnostics().DriverConnectionCount).to.equal(0)
					f[eligibility][owner] = true
					cart.DriverSeat:Sit(owner.Character.Humanoid)
					awaitAdmission(f, owner, cart)
					expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
				end)
			end)
		end

		it("unseats a stranger, retains the owner record and permits normal owner reseating", function()
			fixture(function(f)
				local owner = f.player(-30105, 16000)
				local stranger = f.player(-30106, 16005)
				local cart = f.cart(owner)
				local seat, root = cart.DriverSeat, cart.Root
				local origin, strangerOrigin = root.CFrame, stranger.Character:GetPivot()
				local gravityControl = cart:Clone()
				gravityControl.Name, gravityControl.Parent = "UnregisteredGravityControl", f.world
				gravityControl:PivotTo(origin + Vector3.new(20, 0, 0))
				local controlOrigin = gravityControl.Root.CFrame
				seat:Sit(stranger.Character.Humanoid)
				local immediate = root.CFrame
				awaitRejection(f, cart)
				local physicsDiagnostic = string.format(
					"origin=%s immediateAfterSit=%s afterRejection=%s delta=%.6f headingDot=%.9f strangerOrigin=%s strangerNow=%s gravityControlOrigin=%s gravityControlNow=%s gravityDelta=%.6f",
					tostring(origin), tostring(immediate), tostring(root.CFrame), (root.Position-origin.Position).Magnitude,
					root.CFrame.LookVector:Dot(origin.LookVector), tostring(strangerOrigin), tostring(stranger.Character:GetPivot()),
					tostring(controlOrigin), tostring(gravityControl.Root.CFrame), (gravityControl.Root.Position-controlOrigin.Position).Magnitude
				)
				print("[NATIVE_BOARDING_PHYSICS] " .. physicsDiagnostic)
				expect(f.service:GetOwnerUserId(cart)).to.equal(owner.UserId)
				expect(f.service:GetDriver(cart)).to.equal(nil)
				expect(#f.service:GetOccupants(cart)).to.equal(0)
				expect(cart:GetAttribute("ActiveDriverUserId")).to.equal(0)
				expect(seat:FindFirstChild("SeatWeld")).to.equal(nil)
				expect(seat.Disabled).to.equal(false)
				expect(root.Anchored).to.equal(false)
				-- Native physics settles a supported root by about 0.003 studs.
				-- This still rejects relocation while allowing normal solver precision.
				assert((root.Position - origin.Position).Magnitude < 0.05, physicsDiagnostic)
				assert(root.CFrame.LookVector:Dot(origin.LookVector) > 0.99999, physicsDiagnostic)
				expect(f.networkOwners[cart]).to.equal(nil)
				seat:Sit(owner.Character.Humanoid)
				awaitAdmission(f, owner, cart)
				expect(f.service:GetDriver(cart)).to.equal(owner)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
				expect(f.service:GetOccupants(cart)[1]).to.equal(owner)
				expect(f.networkOwners[cart]).to.equal(owner)
				local revision = f.service:GetDriverRevision(cart)
				local candidate = {
					Player = stranger,
					Character = stranger.Character,
					Humanoid = stranger.Character.Humanoid,
				}
				expect(f.authority:Refresh(cart, candidate, "forged driver claim")).to.equal(false)
				expect(f.service:GetDriver(cart)).to.equal(owner)
				expect(f.service:GetDriverRevision(cart)).to.equal(revision)
				expect(f.networkOwners[cart]).to.equal(owner)
			end)
		end)

		it("a queued stranger callback cannot eject a later legitimate owner occupant", function()
			fixture(function(f)
				local owner = f.player(-30114, 16000)
				local stranger = f.player(-30115, 16005)
				local queued = {}
				f.deferredAdapter.Defer = function(callback) table.insert(queued, callback) end
				local cart = f.cart(owner)
				local seat = cart.DriverSeat
				seat:Sit(stranger.Character.Humanoid)
				awaitState(function()
					return seat.Occupant == stranger.Character.Humanoid and #queued >= 2
				end, "Native stranger boarding callback was not queued")
				expect(f.service:GetDriver(cart)).to.equal(nil)
				-- Native Sit cannot replace an occupied seat. Complete a real
				-- dismount, then board the owner while reconciliation remains held.
				stranger.Character.Humanoid.Sit = false
				local nativeWeld = seat:FindFirstChild("SeatWeld")
				if nativeWeld then nativeWeld:Destroy() end
				awaitState(function() return seat.Occupant == nil end, "Stranger native dismount did not finish")
				seat:Sit(owner.Character.Humanoid)
				awaitState(function()
					return seat.Occupant == owner.Character.Humanoid
						and owner.Character.Humanoid.SeatPart == seat
				end, "Later native owner boarding did not finish")
				f.deferredAdapter.Defer = task.defer
				-- Deliver the newest owner callback, followed by obsolete callbacks
				-- in reverse order. They must leave the owner's existing native weld.
				for index = #queued, 1, -1 do queued[index]() end
				awaitAdmission(f, owner, cart)
				expect(f.service:GetOccupants(cart)[1]).to.equal(owner)
				expect(cart.DriverSeat:FindFirstChild("SeatWeld") ~= nil).to.equal(true)
				expect(f.networkOwners[cart]).to.equal(owner)
			end)
		end)

		it("rejects stranger boarding even while the owner's cart control is suspended", function()
			fixture(function(f)
				local owner = f.player(-30109, 16000)
				local stranger = f.player(-30110, 16005)
				local cart = f.cart(owner)
				f.service:SuspendControl(cart, "suspended owner fixture")
				cart.DriverSeat:Sit(stranger.Character.Humanoid)
				awaitRejection(f, cart)
				expect(f.service:GetDriver(cart)).to.equal(nil)
				expect(#f.service:GetOccupants(cart)).to.equal(0)
				expect(cart.DriverSeat:FindFirstChild("SeatWeld")).to.equal(nil)
				expect(f.networkOwners[cart]).to.equal(nil)
				expect(f.service:GetOwnerUserId(cart)).to.equal(owner.UserId)
				expect(cart.DriverSeat.Disabled).to.equal(false)
				assert(f.service:ResumeControl(cart))
				cart.DriverSeat:Sit(owner.Character.Humanoid)
				awaitAdmission(f, owner, cart)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
			end)
		end)

		it("tracks physical owner occupancy during suspension and rejects obsolete character callbacks", function()
			fixture(function(f)
				local owner = f.player(-30107, 16000)
				local cart = f.cart(owner)
				cart.DriverSeat:Sit(owner.Character.Humanoid)
				awaitAdmission(f, owner, cart)
				expect(f.service:GetDriver(cart)).to.equal(owner)
				f.service:SuspendControl(cart, "correction fixture")
				expect(f.service:GetDriver(cart)).to.equal(nil)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(false)
				expect(f.service:GetOccupants(cart)[1]).to.equal(owner)
				expect(cart.DriverSeat.Occupant).to.equal(owner.Character.Humanoid)
				assert(f.service:ResumeControl(cart))
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(true)
				owner.Character = f.player(-30108, 16005).Character
				expect(#f.service:GetOccupants(cart)).to.equal(0)
				expect(f.service:CanPlayerControlCart(owner, cart)).to.equal(false)
				expect(f.networkOwners[cart]).to.equal(nil)
			end)
		end)

	end)
end
