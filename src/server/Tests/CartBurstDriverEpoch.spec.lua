--!strict

return function()
	local Authority = require(script.Parent.Parent.Utility.CartDriverAuthority)
	local Burst = require(script.Parent.Parent.Utility.CartBurstRuntime)
	local Performance = require(game:GetService("ReplicatedStorage").Shared.Utility.CartTeamPerformance)

	describe("Burst authority revisions with deferred observers", function()
		it("stops for same-owner revoke/restore and ignores delayed old notifications after a fresh press", function()
			local cart = Instance.new("Model")
			local root = Instance.new("Part") root.Parent = cart
			local seat = Instance.new("VehicleSeat") seat.Parent = cart
			local character = Instance.new("Model")
			local humanoid = Instance.new("Humanoid") humanoid.Parent = character
			local player = { UserId = 91234, Name = "BurstAuthorityFixture" } :: any
			local candidate = { Player = player, Character = character, Humanoid = humanoid }
			local deferred = {}
			local authority = Authority.new({
				ValidateCandidate = function() return true, "allowed" end,
				SetNetworkOwner = function() return true end,
				SetActiveDriverUserId = function() return true end,
				OnDriverChanged = function(_cart, _previous, _next, _reason, revision)
					table.insert(deferred, revision)
				end,
				Warn = function(message) error(message) end,
			})
			assert(authority:Register({ Cart = cart, Root = root, DriverSeat = seat, OwnerUserId = player.UserId }))
			assert(authority:Refresh(cart, candidate, "initial driver"))
			local initial = authority:GetStateSnapshot(cart)
			assert(initial, "Initial driver authority snapshot missing")
			local ownerState = { Runtime = Burst.Create(100), Cart = cart, Driver = player, DriverRevision = initial.Revision }
			Burst.Step(ownerState.Runtime, 100, 8, true, false)
			Burst.Step(ownerState.Runtime, 106, 8, true, false)
			assert(Burst.Toggle(ownerState.Runtime, 106, 8, true, false))
			table.clear(deferred)

			-- Authority transitions are real. Observer delivery is deliberately held,
			-- matching the same-player ABA window of deferred BindableEvent signals.
			assert(authority:RevokeControl(cart, "dismount"))
			assert(authority:Refresh(cart, candidate, "same owner reseated"))
			local current = authority:GetStateSnapshot(cart)
			assert(current, "Restored driver authority snapshot missing")
			expect(authority:GetDriver(cart)).to.equal(player)
			expect(current.Revision > initial.Revision).to.equal(true)
			expect(#deferred).to.equal(2)
			-- This is the same guard used by the authoritative performance reader.
			expect(Burst.IsBound(ownerState, cart, player, current.Revision)).to.equal(false)
			local stalePerformance = Performance.Resolve(
				{ status = "Ready", baseSpeed = 36, resolvedSpeed = 36 },
				{ speedMultiplier = 1, burstCapacity = 8 },
				ownerState.Runtime.Active and Burst.IsBound(ownerState, cart, player, current.Revision)
			)
			expect(stalePerformance.resolvedSpeed).to.equal(36)
			Burst.Bind(ownerState, cart, player, current.Revision, 106)
			expect(ownerState.Runtime.Active).to.equal(false)
			expect(ownerState.Runtime.Energy).to.equal(3)
			expect(ownerState.Runtime.RechargeEligibleAt).to.equal(107)

			assert(Burst.Toggle(ownerState.Runtime, 106, 8, true, false))
			for _ in deferred do
				local authoritative = authority:GetStateSnapshot(cart)
				assert(authoritative, "Deferred driver authority snapshot missing")
				Burst.Bind(ownerState, cart, authority:GetDriver(cart), authoritative.Revision, 106)
			end
			expect(ownerState.Runtime.Active).to.equal(true)
			expect(ownerState.Runtime.Energy).to.equal(3)
			expect(Burst.IsBound(ownerState, cart, player, current.Revision)).to.equal(true)
			authority:Unregister(cart, "fixture cleanup")
			cart:Destroy()
			character:Destroy()
		end)
	end)
end
