--!nocheck

return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Upgrade = require(script.Parent.Parent.Services.UpgradeService)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Catalogue = require(RS.Shared.Config.Upgrades)
	local Eligibility = require(RS.Shared.Utility.UpgradeEligibility)
	local Capacity = require(RS.Shared.Utility.CargoCapacityResolver)
	local Validator = require(RS.Shared.Validation.CartAssetValidator)

	local function player()
		local subject = { UserId = 89601, Name = "CargoPersistenceFixture", Parent = Players }
		function subject:SetAttribute() end
		function subject:Kick(reason)
			error(reason)
		end
		return subject
	end

	local function snapshot(subject, data)
		return {
			status = "Ready",
			userId = subject.UserId,
			balance = data.Economy.Balance,
			ownedOfferIds = data.Progression.Upgrades,
			ownedCarts = {},
            phase13 = data.Phase13,
		}
	end

	describe("Released Cargo I purchase and restoration", function()
		it(
			"requires real Slot4 readiness, charges once, and derives four from a fresh saved session",
			function()
				local now, operation = 1000, 0
				local backend = FakeBackend.new({
					Now = function()
						return now
					end,
				})
				local cart = Instance.new("Model")
				cart.Name = "SPEC_CARGO_UPGRADE_CART"
				cart:SetAttribute("CartId", "CRT_001")
				local slots = Instance.new("Folder")
				slots.Name, slots.Parent = "CargoSlots", cart
				local function authorSlot(index)
					local part = Instance.new("Part")
					part.Name, part.Position = "Slot" .. index, Vector3.new(index * 2, 0, 0)
					part.Anchored, part.Parent = true, slots
					local attachment = Instance.new("Attachment")
					attachment.Name, attachment.Parent = "CargoAttachment", part
				end
				for index = 1, 3 do
					authorSlot(index)
				end
				local shop = Instance.new("Part")
				shop.Name, shop.Anchored, shop.Parent = "SPEC_CARGO_UPGRADE_STALL", true, workspace
				local function initProfile()
					Profile:_ResetForTests()
					Profile:Init({
						Backend = backend,
						UnixNow = function()
							return now
						end,
						MonotonicNow = function()
							return now
						end,
						Wait = function(seconds)
							now += seconds
						end,
						Random = function()
							return 0
						end,
						GenerateOperationId = function(prefix)
							operation += 1
							return prefix .. ":cargo:" .. operation
						end,
						KickOnFailure = false,
					})
					Currency:_ResetForTests(Profile)
				end
				local ok, failure = xpcall(function()
					initProfile()
					local first = player()
					expect(Profile:LoadPlayerAsync(first).ok).to.equal(true)
					expect(Currency:TryCredit(first, 1500000000.5, "SyntheticFixture").ok).to.equal(true)
					local target =
						{ cartId = "CRT_001", ownerUserId = first.UserId, runtimeCart = cart }
					Upgrade:Stop()
					Upgrade:Init({
						Profile = Profile,
						Currency = Currency,
						Catalogue = Catalogue,
						Eligibility = Eligibility,
						Readiness = {
							effectReadyByOfferId = {
								CARGO_1 = function(_, _, currentTarget)
									return Validator.ValidateCargoLayout(
										currentTarget.runtimeCart,
										4
									).status == "Ready"
								end,
							},
							persistenceReadyByScope = { PlayerWide = true },
						},
						WorldReady = function()
							return true
						end,
						WithinShopRange = function()
							return true
						end,
						ResolveTarget = function()
							return target
						end,
						BuildPlayerSnapshot = snapshot,
						-- The production bootstrap grant adapter writes this source field;
						-- debit, revision, request cache and serialization remain real services.
                        ApplyGrant = function(data,offer)
                            return require(RS.Shared.Utility.Phase13Rules).GrantUpgrade(data,offer)
                        end,
						Now = function()
							return now
						end,
						GenerateId = function()
							operation += 1
							return "cargo-context:" .. operation
						end,
					})
					local blockedContext = Upgrade:OpenShop(first, shop)
					expect(blockedContext.ok).to.equal(true)
					local blocked = Upgrade:Purchase(first, {
						contextId = blockedContext.payload.contextId,
						requestId = "missing-slot4",
						offerId = "CARGO_1",
					})
					expect(blocked.code).to.equal("EFFECT_NOT_READY")
					expect(Currency:GetBalance(first)).to.equal(1500000000.5)
					authorSlot(4)
					expect(Validator.ValidateCargoLayout(cart, 4).status).to.equal("Ready")
					local before = Profile:GetReadableData(first)
					expect(Capacity.Resolve(snapshot(first, before), target).effectiveCapacity).to.equal(
						3
					)
					expect(before.Progression.Upgrades.CART_SPEED_1).to.equal(nil)
					local context = Upgrade:OpenShop(first, shop)
					local request = {
						contextId = context.payload.contextId,
						requestId = "cargo-one",
						offerId = "CARGO_1",
					}
					local purchased = Upgrade:Purchase(first, request)
					expect(purchased.outcome).to.equal("Accepted")
					expect(purchased.chargedAmount).to.equal(1500000000)
					expect(purchased.balance).to.equal(0.5)
					expect(Upgrade:Purchase(first, request).duplicate).to.equal(true)
					expect(Currency:GetBalance(first)).to.equal(0.5)
					local live = Profile:GetReadableData(first)
					expect(live.Phase13.CargoLevel).to.equal(1)
					expect(live.Progression.Upgrades.CART_SPEED_1).to.equal(nil)
					expect(Capacity.Resolve(snapshot(first, live), target).effectiveCapacity).to.equal(
						4
					)
					expect(Profile:ClosePlayerAsync(first, "CargoFixtureClose").ok).to.equal(true)
					local durable = backend:GetRecord("player_89601")
					expect(durable.Data.Economy.Balance).to.equal(0.5)
					expect(durable.Data.Phase13.CargoLevel).to.equal(1)
					expect(durable.Data.CargoCapacity).to.equal(nil)
					expect(durable.Data.Progression.CargoCapacity).to.equal(nil)
					Upgrade:Stop()
					first.Parent = nil
					initProfile()
					local returning = player()
					expect(Profile:LoadPlayerAsync(returning).isNew).to.equal(false)
					local restored = Profile:GetReadableData(returning)
					expect(restored == live).to.equal(false)
					expect(restored.Progression.Upgrades == live.Progression.Upgrades).to.equal(
						false
					)
					expect(restored.Economy.Balance).to.equal(0.5)
					for _ = 1, 100 do
						local resolved = Capacity.Resolve(snapshot(returning, restored), target)
						expect(resolved.effectiveCapacity).to.equal(4)
						expect(resolved.upgradeBonus).to.equal(1)
					end
					expect(Profile:ClosePlayerAsync(returning, "CargoFixtureCleanup").ok).to.equal(
						true
					)
				end, debug.traceback)
				Upgrade:Stop()
				Profile:_ResetForTests()
				Currency:_ResetForTests()
				cart:Destroy()
				shop:Destroy()
				assert(ok, failure)
			end
		)
	end)
end
