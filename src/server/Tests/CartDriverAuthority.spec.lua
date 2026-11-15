--!strict

return function()
	local CartDriverAuthority = require(script.Parent.Parent.Utility.CartDriverAuthority)

	type Adapter = CartDriverAuthority.Adapter
	type Authority = CartDriverAuthority.Authority
	type DriverCandidate = CartDriverAuthority.DriverCandidate
	type DriverRecord = CartDriverAuthority.DriverRecord
	type DriverRegistration = CartDriverAuthority.DriverRegistration

	type DriverEvent = {
		Cart: Model,
		PreviousDriver: Player?,
		NextDriver: Player?,
		Reason: string,
		Revision: number,
	}

	type HarnessState = {
		AllowedPlayers: { [Player]: boolean },
		AttributeByCart: { [Model]: number },
		Events: { DriverEvent },
		FailAttributeUserId: number?,
		FailNetworkPlayer: Player?,
		FailServerOwnership: boolean,
		Operations: { string },
		Warnings: { string },
	}

	type RegistrationFixture = {
		Cart: Model,
		Registration: DriverRegistration,
	}

	local function createPlayer(userId: number, name: string): Player
		return {
			UserId = userId,
			Name = name,
		} :: any
	end

	local function playerLabel(player: Player?): string
		return if player == nil then "server" else tostring(player.UserId)
	end

	local function createCandidate(player: Player): DriverCandidate
		local character = Instance.new("Model")
		local humanoid = Instance.new("Humanoid")

		character.Name = string.format("Character_%d", player.UserId)
		humanoid.Parent = character

		return {
			Player = player,
			Character = character,
			Humanoid = humanoid,
		}
	end

	local function destroyCandidate(candidate: DriverCandidate)
		candidate.Character:Destroy()
	end

	local function createRegistration(name: string, ownerUserId: number): RegistrationFixture
		local cart = Instance.new("Model")
		local root = Instance.new("Part")
		local driverSeat = Instance.new("VehicleSeat")

		cart.Name = name
		root.Name = "Root"
		root.Parent = cart
		driverSeat.Name = "DriverSeat"
		driverSeat.Parent = cart

		return {
			Cart = cart,
			Registration = {
				Cart = cart,
				Root = root,
				DriverSeat = driverSeat,
				OwnerUserId = ownerUserId,
			},
		}
	end

	local function createHarness(): (Authority, HarnessState)
		local state: HarnessState = {
			AllowedPlayers = {},
			AttributeByCart = {},
			Events = {},
			FailAttributeUserId = nil,
			FailNetworkPlayer = nil,
			FailServerOwnership = false,
			Operations = {},
			Warnings = {},
		}

		local adapter: Adapter = {
			ValidateCandidate = function(
				record: DriverRecord,
				candidate: DriverCandidate
			): (boolean, string)
				if record.ControlSuspended then
					return false, "control suspended"
				end

				if state.AllowedPlayers[candidate.Player] == false then
					return false, "candidate rejected"
				end

				return true, "allowed"
			end,
			SetNetworkOwner = function(record: DriverRecord, player: Player?): (boolean, string?)
				table.insert(
					state.Operations,
					string.format("network:%s:%s", record.Cart.Name, playerLabel(player))
				)

				if player ~= nil and state.FailNetworkPlayer == player then
					return false, "network assignment denied"
				end

				if player == nil and state.FailServerOwnership then
					return false, "server ownership denied"
				end

				return true
			end,
			SetActiveDriverUserId = function(
				record: DriverRecord,
				userId: number
			): (boolean, string?)
				table.insert(
					state.Operations,
					string.format("attribute:%s:%d", record.Cart.Name, userId)
				)

				if state.FailAttributeUserId == userId then
					return false, "attribute replication denied"
				end

				state.AttributeByCart[record.Cart] = userId

				return true
			end,
			OnDriverChanged = function(
				cart: Model,
				previousDriver: Player?,
				nextDriver: Player?,
				reason: string,
				revision: number
			)
				table.insert(state.Events, {
					Cart = cart,
					PreviousDriver = previousDriver,
					NextDriver = nextDriver,
					Reason = reason,
					Revision = revision,
				})
				table.insert(
					state.Operations,
					string.format(
						"event:%s:%s>%s",
						cart.Name,
						playerLabel(previousDriver),
						playerLabel(nextDriver)
					)
				)
			end,
			Warn = function(message: string)
				table.insert(state.Warnings, message)
			end,
		}

		return CartDriverAuthority.new(adapter), state
	end

	local function clearObservations(state: HarnessState)
		table.clear(state.Events)
		table.clear(state.Operations)
		table.clear(state.Warnings)
	end

	local function expectOperations(state: HarnessState, expectedOperations: { string })
		expect(#state.Operations).to.equal(#expectedOperations)

		for index, expectedOperation in expectedOperations do
			expect(state.Operations[index]).to.equal(expectedOperation)
		end
	end

	local function registerSuccessfully(authority: Authority, registration: DriverRegistration)
		local registered = authority:Register(registration)

		expect(registered).to.equal(true)
	end

	local function refreshSuccessfully(
		authority: Authority,
		cart: Model,
		candidate: DriverCandidate?,
		reason: string
	)
		local refreshed = authority:Refresh(cart, candidate, reason)

		expect(refreshed).to.equal(true)
	end

	local function getRegisteredRecord(authority: Authority, cart: Model): DriverRecord
		local record = authority:GetStateSnapshot(cart)

		assert(record ~= nil, "Expected cart to remain registered")

		return record
	end

	describe("CartDriverAuthority", function()
		it("accepts ten same-cart reentries and rejects late prior-entry revocations", function()
			local authority = createHarness()
			local player = createPlayer(101, "Reentry")
			local candidate = createCandidate(player)
			local fixture = createRegistration("SameCart", player.UserId)
			registerSuccessfully(authority, fixture.Registration)
			local oldRevision = nil
			for _ = 1, 10 do
				refreshSuccessfully(authority, fixture.Cart, candidate, "current occupant")
				expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(true)
				if oldRevision then
					expect(
						authority:RevokeControlIfCurrent(
							fixture.Cart,
							candidate,
							oldRevision,
							"late exit"
						)
					).to.equal(false)
				end
				oldRevision = getRegisteredRecord(authority, fixture.Cart).Revision
				refreshSuccessfully(authority, fixture.Cart, nil, "actual seat exit")
				expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			end
			authority:Unregister(fixture.Cart, "test cleanup")
			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)
		it("rejects a carrying candidate before any driver ownership or role grant", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "Carrier")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CarryGuardCart", player.UserId)
			registerSuccessfully(authority, fixture.Registration)
			state.AllowedPlayers[player] = false -- Adapter represents server carry predicate.
			clearObservations(state)
			for _ = 1, 5 do
				expect(authority:Refresh(fixture.Cart, candidate, "seat/role entry", true)).to.equal(
					false
				)
				expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			end
			expectOperations(state, {})
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it(
			"revokes a newly ineligible driver's ownership once on input and permits empty-hand re-entry",
			function()
				local authority, state = createHarness()
				local player = createPlayer(101, "Carrier")
				local candidate = createCandidate(player)
				local fixture = createRegistration("CarryGuardCart", player.UserId)
				registerSuccessfully(authority, fixture.Registration)
				refreshSuccessfully(authority, fixture.Cart, candidate, "empty-hand entry")
				state.AllowedPlayers[player] = false
				clearObservations(state)
				for _ = 1, 8 do
					expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
				end
				expectOperations(state, {
					"attribute:CarryGuardCart:0",
					"network:CarryGuardCart:server",
					"event:CarryGuardCart:101>server",
				})
				expect(authority:GetCartDrivenBy(player)).to.equal(nil)
				expect(getRegisteredRecord(authority, fixture.Cart).ControlEnabled).to.equal(false)
				state.AllowedPlayers[player] = true
				refreshSuccessfully(authority, fixture.Cart, candidate, "hands empty again")
				expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(true)
				destroyCandidate(candidate)
				fixture.Cart:Destroy()
			end
		)

		it(
			"a carrying passenger's rejected role switch or input cannot evict a legitimate driver",
			function()
				local authority, state = createHarness()
				local driver = createPlayer(101, "Driver")
				local carrier = createPlayer(202, "Passenger")
				local driving, passenger = createCandidate(driver), createCandidate(carrier)
				local fixture = createRegistration("SharedCart", driver.UserId)
				registerSuccessfully(authority, fixture.Registration)
				refreshSuccessfully(authority, fixture.Cart, driving, "driver seated")
				state.AllowedPlayers[carrier] = false
				clearObservations(state)
				for _ = 1, 4 do
					expect(
						authority:Refresh(fixture.Cart, passenger, "rejected role request", true)
					).to.equal(false)
					expect(authority:CanPlayerControlCart(carrier, fixture.Cart)).to.equal(false)
				end
				expectOperations(state, {})
				expect(authority:GetDriver(fixture.Cart)).to.equal(driver)
				expect(authority:CanPlayerControlCart(driver, fixture.Cart)).to.equal(true)
				destroyCandidate(driving)
				destroyCandidate(passenger)
				fixture.Cart:Destroy()
			end
		)

		it(
			"forced ownership restoration never regrants to an ineligible accepted driver",
			function()
				local authority, state = createHarness()
				local player = createPlayer(101, "Carrier")
				local candidate = createCandidate(player)
				local fixture = createRegistration("CarryGuardCart", player.UserId)
				registerSuccessfully(authority, fixture.Registration)
				refreshSuccessfully(authority, fixture.Cart, candidate, "driver seated")
				state.AllowedPlayers[player] = false
				clearObservations(state)
				expect(authority:Refresh(fixture.Cart, candidate, "ownership restore", true)).to.equal(
					false
				)
				expectOperations(state, {
					"attribute:CarryGuardCart:0",
					"network:CarryGuardCart:server",
					"event:CarryGuardCart:101>server",
				})
				destroyCandidate(candidate)
				fixture.Cart:Destroy()
			end
		)

		it("registers with no driver, disabled control, and server ownership", function()
			local authority, state = createHarness()
			local fixture = createRegistration("CartA", 101)

			local registered, warning = authority:Register(fixture.Registration)
			local record = authority:GetStateSnapshot(fixture.Cart)

			expect(registered).to.equal(true)
			expect(warning).to.equal(nil)
			expect(authority:IsRegistered(fixture.Cart)).to.equal(true)
			expect(record).never.to.equal(nil)
			expect((record :: DriverRecord).ActivePlayer).to.equal(nil)
			expect((record :: DriverRecord).ControlEnabled).to.equal(false)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
			})

			fixture.Cart:Destroy()
		end)

		it("rejects registration when server ownership cannot be confirmed", function()
			local authority, state = createHarness()
			local fixture = createRegistration("CartA", 101)

			state.FailServerOwnership = true

			local registered, warning = authority:Register(fixture.Registration)

			expect(registered).to.equal(false)
			expect(warning).to.equal("failed to confirm server ownership")
			expect(authority:IsRegistered(fixture.Cart)).to.equal(false)
			expect(authority:GetStateSnapshot(fixture.Cart)).to.equal(nil)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Warnings).to.equal(1)
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
			})

			fixture.Cart:Destroy()
		end)

		it("assigns a valid driver only after requesting network ownership", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, candidate, "seat occupied")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(player)
			expect(authority:GetCartDrivenBy(player)).to.equal(fixture.Cart)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(true)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(player.UserId)
			expect(#state.Events).to.equal(1)
			expect(state.Events[1].PreviousDriver).to.equal(nil)
			expect(state.Events[1].NextDriver).to.equal(player)
			expect(state.Events[1].Reason).to.equal("seat occupied")
			expect(state.Events[1].Revision).to.equal(1)
			expectOperations(state, {
				"network:CartA:101",
				"attribute:CartA:101",
				"event:CartA:server>101",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("keeps an empty cart unassigned and server-owned", function()
			local authority, state = createHarness()
			local fixture = createRegistration("CartA", 101)

			registerSuccessfully(authority, fixture.Registration)
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, nil, "seat vacant")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(getRegisteredRecord(authority, fixture.Cart).ControlEnabled).to.equal(false)
			expect(#state.Events).to.equal(0)
			expect(#state.Operations).to.equal(0)

			fixture.Cart:Destroy()
		end)

		it("repairs vacant cart ownership only when the refresh is forced", function()
			local authority, state = createHarness()
			local fixture = createRegistration("CartA", 101)

			registerSuccessfully(authority, fixture.Registration)
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, nil, "ownership repair", true)

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(getRegisteredRecord(authority, fixture.Cart).ControlEnabled).to.equal(false)
			expect(#state.Events).to.equal(0)
			expectOperations(state, {
				"network:CartA:server",
			})

			fixture.Cart:Destroy()
		end)

		it("reports a failed forced ownership repair without publishing a transition", function()
			local authority, state = createHarness()
			local fixture = createRegistration("CartA", 101)

			registerSuccessfully(authority, fixture.Registration)
			clearObservations(state)
			state.FailServerOwnership = true

			local refreshed, reason = authority:Refresh(fixture.Cart, nil, "ownership repair", true)

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("server ownership refresh failed")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(getRegisteredRecord(authority, fixture.Cart).ControlEnabled).to.equal(false)
			expect(#state.Events).to.equal(0)
			expect(#state.Warnings).to.equal(1)
			expectOperations(state, {
				"network:CartA:server",
			})

			fixture.Cart:Destroy()
		end)

		it("does not report a forced stale-driver ownership repair as successful", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			clearObservations(state)
			state.FailServerOwnership = true

			local refreshed, reason =
				authority:Refresh(fixture.Cart, nil, "forced ownership correction", true)

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("server ownership refresh failed")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Events).to.equal(1)
			expect(state.Events[1].PreviousDriver).to.equal(player)
			expect(state.Events[1].NextDriver).to.equal(nil)
			expect(#state.Warnings).to.equal(1)
			expectOperations(state, {
				"attribute:CartA:0",
				"event:CartA:101>server",
				"network:CartA:server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("rejects an invalid or NPC-equivalent candidate without granting authority", function()
			local authority, state = createHarness()
			local npcPlayer = createPlayer(101, "RejectedCandidate")
			local candidate = createCandidate(npcPlayer)
			local fixture = createRegistration("CartA", npcPlayer.UserId)

			state.AllowedPlayers[npcPlayer] = false
			registerSuccessfully(authority, fixture.Registration)
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, candidate, "seat occupied")

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("candidate rejected")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(npcPlayer)).to.equal(nil)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Events).to.equal(0)
			expect(#state.Operations).to.equal(0)

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("does not publish authority when network assignment fails", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			state.FailNetworkPlayer = player
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, candidate, "seat occupied")

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("network assignment denied")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Events).to.equal(0)
			expectOperations(state, {
				"network:CartA:101",
				"network:CartA:server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("rolls back ownership when active-driver replication fails", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			state.FailAttributeUserId = player.UserId
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, candidate, "seat occupied")

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("failed to replicate active driver")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			expect(#state.Events).to.equal(0)
			expect(#state.Warnings).to.equal(1)
			expectOperations(state, {
				"network:CartA:101",
				"attribute:CartA:101",
				"network:CartA:server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("does not duplicate transitions for the same valid occupant", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			clearObservations(state)

			local refreshed, reason =
				authority:Refresh(fixture.Cart, candidate, "duplicate occupant signal")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(player)
			expect(#state.Events).to.equal(0)
			expect(#state.Operations).to.equal(0)

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("can refresh network ownership without duplicating the driver transition", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			clearObservations(state)

			local refreshed, reason =
				authority:Refresh(fixture.Cart, candidate, "ownership repair", true)

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(player)
			expect(#state.Events).to.equal(0)
			expectOperations(state, {
				"network:CartA:101",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("revokes authority if a forced ownership refresh fails", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			state.FailNetworkPlayer = player
			clearObservations(state)

			local refreshed, reason =
				authority:Refresh(fixture.Cart, candidate, "ownership repair", true)

			expect(refreshed).to.equal(false)
			expect(reason).to.equal("network assignment denied")
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Events).to.equal(1)
			expectOperations(state, {
				"network:CartA:101",
				"attribute:CartA:0",
				"network:CartA:server",
				"event:CartA:101>server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("clears replicated authority before server ownership and the exit event", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			clearObservations(state)

			local refreshed, reason = authority:Refresh(fixture.Cart, nil, "seat vacant")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			expect(state.AttributeByCart[fixture.Cart]).to.equal(0)
			expect(#state.Events).to.equal(1)
			expect(state.Events[1].PreviousDriver).to.equal(player)
			expect(state.Events[1].NextDriver).to.equal(nil)
			expect(state.Events[1].Reason).to.equal("seat vacant")
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
				"event:CartA:101>server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("emits an exit before an enter during direct driver replacement", function()
			local authority, state = createHarness()
			local firstPlayer = createPlayer(101, "DriverA")
			local secondPlayer = createPlayer(202, "DriverB")
			local firstCandidate = createCandidate(firstPlayer)
			local secondCandidate = createCandidate(secondPlayer)
			local fixture = createRegistration("CartA", firstPlayer.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, firstCandidate, "first occupied")
			clearObservations(state)

			local refreshed, reason =
				authority:Refresh(fixture.Cart, secondCandidate, "occupant changed")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(secondPlayer)
			expect(authority:GetCartDrivenBy(firstPlayer)).to.equal(nil)
			expect(authority:GetCartDrivenBy(secondPlayer)).to.equal(fixture.Cart)
			expect(#state.Events).to.equal(2)
			expect(state.Events[1].PreviousDriver).to.equal(firstPlayer)
			expect(state.Events[1].NextDriver).to.equal(nil)
			expect(state.Events[1].Reason).to.equal("driver replaced")
			expect(state.Events[1].Revision).to.equal(2)
			expect(state.Events[2].PreviousDriver).to.equal(nil)
			expect(state.Events[2].NextDriver).to.equal(secondPlayer)
			expect(state.Events[2].Reason).to.equal("occupant changed")
			expect(state.Events[2].Revision).to.equal(3)
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
				"event:CartA:101>server",
				"network:CartA:202",
				"attribute:CartA:202",
				"event:CartA:server>202",
			})

			destroyCandidate(firstCandidate)
			destroyCandidate(secondCandidate)
			fixture.Cart:Destroy()
		end)

		it("ignores a stale lifecycle callback after direct driver replacement", function()
			local authority, state = createHarness()
			local firstPlayer = createPlayer(101, "DriverA")
			local secondPlayer = createPlayer(202, "DriverB")
			local firstCandidate = createCandidate(firstPlayer)
			local secondCandidate = createCandidate(secondPlayer)
			local fixture = createRegistration("CartA", firstPlayer.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, firstCandidate, "first occupied")
			local staleRevision = getRegisteredRecord(authority, fixture.Cart).Revision

			refreshSuccessfully(authority, fixture.Cart, secondCandidate, "occupant changed")
			clearObservations(state)

			local revoked = authority:RevokeControlIfCurrent(
				fixture.Cart,
				firstCandidate,
				staleRevision,
				"stale first-driver callback"
			)

			expect(revoked).to.equal(false)
			expect(authority:GetDriver(fixture.Cart)).to.equal(secondPlayer)
			expect(authority:GetCartDrivenBy(secondPlayer)).to.equal(fixture.Cart)
			expect(#state.Events).to.equal(0)
			expect(#state.Operations).to.equal(0)

			destroyCandidate(firstCandidate)
			destroyCandidate(secondCandidate)
			fixture.Cart:Destroy()
		end)

		it("revokes a Player's previous cart before assigning a second cart", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local firstFixture = createRegistration("CartA", player.UserId)
			local secondFixture = createRegistration("CartB", player.UserId)

			registerSuccessfully(authority, firstFixture.Registration)
			registerSuccessfully(authority, secondFixture.Registration)
			refreshSuccessfully(authority, firstFixture.Cart, candidate, "first occupied")
			clearObservations(state)

			local refreshed, reason =
				authority:Refresh(secondFixture.Cart, candidate, "second occupied")

			expect(refreshed).to.equal(true)
			expect(reason).to.equal(nil)
			expect(authority:GetDriver(firstFixture.Cart)).to.equal(nil)
			expect(authority:GetDriver(secondFixture.Cart)).to.equal(player)
			expect(authority:GetCartDrivenBy(player)).to.equal(secondFixture.Cart)
			expect(authority:CanPlayerControlCart(player, firstFixture.Cart)).to.equal(false)
			expect(authority:CanPlayerControlCart(player, secondFixture.Cart)).to.equal(true)
			expect(#state.Events).to.equal(2)
			expect(state.Events[1].Cart).to.equal(firstFixture.Cart)
			expect(state.Events[1].PreviousDriver).to.equal(player)
			expect(state.Events[1].NextDriver).to.equal(nil)
			expect(state.Events[2].Cart).to.equal(secondFixture.Cart)
			expect(state.Events[2].PreviousDriver).to.equal(nil)
			expect(state.Events[2].NextDriver).to.equal(player)
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
				"event:CartA:101>server",
				"network:CartB:101",
				"attribute:CartB:101",
				"event:CartB:server>101",
			})

			destroyCandidate(candidate)
			firstFixture.Cart:Destroy()
			secondFixture.Cart:Destroy()
		end)

		it(
			"suspends authority, rejects refreshes, and resumes without restoring stale control",
			function()
				local authority, state = createHarness()
				local player = createPlayer(101, "DriverA")
				local candidate = createCandidate(player)
				local fixture = createRegistration("CartA", player.UserId)

				registerSuccessfully(authority, fixture.Registration)
				refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
				clearObservations(state)

				expect(authority:SuspendControl(fixture.Cart, "server transition")).to.equal(true)
				expect(getRegisteredRecord(authority, fixture.Cart).ControlSuspended).to.equal(true)
				expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
				expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)

				clearObservations(state)

				local refreshed, reason =
					authority:Refresh(fixture.Cart, candidate, "signal while suspended")

				expect(refreshed).to.equal(false)
				expect(reason).to.equal("control suspended")
				expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
				expect(#state.Events).to.equal(0)
				expect(#state.Operations).to.equal(0)

				expect(authority:ResumeControl(fixture.Cart)).to.equal(true)
				expect(getRegisteredRecord(authority, fixture.Cart).ControlSuspended).to.equal(
					false
				)
				expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
				refreshSuccessfully(authority, fixture.Cart, candidate, "seat revalidated")
				expect(authority:GetDriver(fixture.Cart)).to.equal(player)

				destroyCandidate(candidate)
				fixture.Cart:Destroy()
			end
		)

		it("unregisters an active cart and clears both authority lookups", function()
			local authority, state = createHarness()
			local player = createPlayer(101, "DriverA")
			local candidate = createCandidate(player)
			local fixture = createRegistration("CartA", player.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")
			clearObservations(state)

			expect(authority:Unregister(fixture.Cart, "cart destroyed")).to.equal(true)
			expect(authority:IsRegistered(fixture.Cart)).to.equal(false)
			expect(authority:GetStateSnapshot(fixture.Cart)).to.equal(nil)
			expect(authority:GetDriver(fixture.Cart)).to.equal(nil)
			expect(authority:GetCartDrivenBy(player)).to.equal(nil)
			expect(authority:CanPlayerControlCart(player, fixture.Cart)).to.equal(false)
			expect(authority:Unregister(fixture.Cart, "duplicate cleanup")).to.equal(false)
			expectOperations(state, {
				"attribute:CartA:0",
				"network:CartA:server",
				"event:CartA:101>server",
			})

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)

		it("rejects duplicate registration without replacing the original record", function()
			local authority, state = createHarness()
			local original = createRegistration("CartA", 101)
			local duplicateRoot = Instance.new("Part")
			local duplicateSeat = Instance.new("VehicleSeat")

			registerSuccessfully(authority, original.Registration)
			clearObservations(state)

			local registered, reason = authority:Register({
				Cart = original.Cart,
				Root = duplicateRoot,
				DriverSeat = duplicateSeat,
				OwnerUserId = 202,
			})
			local record = authority:GetStateSnapshot(original.Cart)

			expect(registered).to.equal(false)
			expect(reason).to.equal("cart is already registered")
			expect(record).never.to.equal(nil)
			expect((record :: DriverRecord).Root).to.equal(original.Registration.Root)
			expect((record :: DriverRecord).DriverSeat).to.equal(original.Registration.DriverSeat)
			expect((record :: DriverRecord).OwnerUserId).to.equal(101)
			expect(#state.Operations).to.equal(0)

			duplicateRoot:Destroy()
			duplicateSeat:Destroy()
			original.Cart:Destroy()
		end)

		it("answers authority queries without granting another Player control", function()
			local authority, _state = createHarness()
			local driver = createPlayer(101, "DriverA")
			local otherPlayer = createPlayer(202, "DriverB")
			local candidate = createCandidate(driver)
			local fixture = createRegistration("CartA", driver.UserId)

			registerSuccessfully(authority, fixture.Registration)
			refreshSuccessfully(authority, fixture.Cart, candidate, "seat occupied")

			expect(authority:GetDriver(fixture.Cart)).to.equal(driver)
			expect(authority:GetCartDrivenBy(driver)).to.equal(fixture.Cart)
			expect(authority:GetCartDrivenBy(otherPlayer)).to.equal(nil)
			expect(authority:IsDriver(driver, fixture.Cart)).to.equal(true)
			expect(authority:IsDriver(otherPlayer, fixture.Cart)).to.equal(false)
			expect(authority:CanPlayerControlCart(driver, fixture.Cart)).to.equal(true)
			expect(authority:CanPlayerControlCart(otherPlayer, fixture.Cart)).to.equal(false)
			expect(authority:IsRegistered(fixture.Cart)).to.equal(true)
			expect(getRegisteredRecord(authority, fixture.Cart).ControlEnabled).to.equal(true)
			expect(table.isfrozen(getRegisteredRecord(authority, fixture.Cart))).to.equal(true)

			destroyCandidate(candidate)
			fixture.Cart:Destroy()
		end)
	end)
end
