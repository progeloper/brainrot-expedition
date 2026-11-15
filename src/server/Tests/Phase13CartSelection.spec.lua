--!nocheck
return function()
	local Players = game:GetService("Players")
	local Cart = require(script.Parent.Parent.Services.CartService)
	local Assets = require(script.Parent.Parent.Services.CartAssetService)
	local Assembly = require(script.Parent.Parent.Services.CartAssemblyValidationService)
	-- The arcade drive service owns the live movement profile (formerly CartLongitudinalStateService).
	local Arcade = require(script.Parent.Parent.Services.CartArcadeService)
	local Collision = require(script.Parent.Parent.Services.CollisionService)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local Bases = require(script.Parent.Parent.Systems.PlayerBaseSystem)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local function part(parent, name, frame)
		local p = Instance.new("Part")
		p.Name = name
		p.CFrame = frame
		p.Parent = parent
		return p
	end
	local function fixture(callback)
		local cart = Instance.new("Model")
		cart.Name = "Phase13SyntheticCart"
		cart.Parent = workspace
		local root = part(cart, "Root", CFrame.new(10000, 100, 10000))
		root.CanCollide = false
		root.RootPriority = 127
		cart.PrimaryPart = root
		local visual = Instance.new("Model")
		visual.Name = "Visual"
		visual.Parent = cart
		local chassis = part(visual, "Chassis", root.CFrame * CFrame.new(0, 0.75, 0))
		chassis.CanCollide = true
		chassis.Size = Vector3.new(8, 1.5, 11)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = chassis
		weld.Parent = root
		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriverSeat"
		seat.Parent = cart
		local folders = {}
		for _, name in { "CargoSlots", "FormationSlots" } do
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = cart
			folders[name] = folder
			for i = 1, 6 do
				part(folder, "Slot" .. i, root.CFrame * CFrame.new(i, 2, -2))
			end
		end
		local cargoVisual = Instance.new("Model")
		cargoVisual.Name = "PreservedFreshVisual"
		cargoVisual.Parent = cart
		local cargoBody = part(cargoVisual, "Body", root.CFrame * CFrame.new(2, 3, -2))
		local recordIdentity = { ItemId = "fresh:same", MutationId = "Astral", EscapeAttemptCount = 1 }
		local base = Instance.new("Model")
		part(base, "CartSpawn", root.CFrame)
		base.Parent = workspace
		local source = Instance.new("Model")
		local sourceRoot = part(source, "Root", CFrame.new(50, 10, 50))
		local sourceVisual = Instance.new("Model")
		sourceVisual.Name = "Visual"
		sourceVisual.Parent = source
		part(sourceVisual, "Chassis", sourceRoot.CFrame * CFrame.new(0, 0.75, 0))
		local art = part(sourceVisual, "ScoutArt", sourceRoot.CFrame * CFrame.new(3, 2, 0))
		art.Color = Color3.fromRGB(40, 180, 220)
		local sourceWeld = Instance.new("WeldConstraint")
		sourceWeld.Name = "ForeignArtWeld"
		sourceWeld.Part0 = sourceRoot
		sourceWeld.Part1 = art
		sourceWeld.Parent = art
		local data = Schema.CreateDefault()
		data.Phase13.OwnedCartIds.CRT_008 = true
		data.Phase13.SpeedLevel = 3
		local player = { UserId = 831309, Name = "SyntheticCartOwner", Parent = Players }
		local record = {
			OwnerUserId = player.UserId,
			CartId = "CRT_001",
			Model = cart,
			Generation = 7,
			PerformanceSignature = "",
			PerformanceRevision = 1,
		}
		cart:SetAttribute("OwnerUserId", player.UserId)
		cart:SetAttribute("CartId", "CRT_001")
		local originals = {
			Assets.GetAsset,
			Assembly.IsCartValid,
			Arcade.UpdateProfile,
			Collision.SetModelCollisionGroup,
			Cargo.CanSelectOwnedCart,
			Bases.GetBase,
		}
		local busy = false
		Assets.GetAsset = function()
			return source
		end
		Assembly.IsCartValid = function()
			return true
		end
		Arcade.UpdateProfile = function()
			return true
		end
		Collision.SetModelCollisionGroup = function() end
		Cargo.CanSelectOwnedCart = function()
			return not busy, "CARGO_BUSY"
		end
		Bases.GetBase = function()
			return base
		end
		local ok, why = xpcall(function()
			Cart:_TestWithOwnedSelectionRecord(player, record, function()
				return { status = "Ready", userId = player.UserId, phase13 = data.Phase13 }
			end, function()
				callback({
					Player = player,
					Data = data,
					Cart = cart,
					Root = root,
					Chassis = chassis,
					Weld = weld,
					Seat = seat,
					Visual = visual,
					Folders = folders,
					CargoVisual = cargoVisual,
					CargoBody = cargoBody,
					Record = record,
					Identity = recordIdentity,
					Busy = function(value)
						busy = value
					end,
				})
			end)
		end, debug.traceback)
		Assets.GetAsset, Assembly.IsCartValid, Arcade.UpdateProfile, Collision.SetModelCollisionGroup, Cargo.CanSelectOwnedCart, Bases.GetBase =
			table.unpack(originals)
		cart:Destroy()
		source:Destroy()
		base:Destroy()
		assert(ok, why)
	end
	describe("Phase13 same-model owned cart selection", function()
		it("prepares without exposing reward and preserves physical custody/chassis after durable selection", function()
			fixture(function(f)
				local handle = Cart:GetCartHandle(f.Player)
				local preparation = assert(Cart:PrepareOwnedCartSelection(f.Player, "CRT_008"))
				expect(f.Cart:GetAttribute("CartId")).to.equal("CRT_001")
				expect(f.Cart.Visual).to.equal(f.Visual)
				f.Data.Phase13.SelectedCartId = "CRT_008"
				expect(Cart:CommitOwnedCartSelection(f.Player, preparation, "CRT_008")).to.equal(true)
				expect(Cart:GetCart(f.Player)).to.equal(f.Cart)
				expect(Cart:IsCurrentCartHandle(handle)).to.equal(true)
				expect(f.Cart.Visual.Chassis).to.equal(f.Chassis)
				expect(f.Chassis.CanCollide).to.equal(true)
				expect(f.Chassis.Size).to.equal(Vector3.new(8, 1.5, 11))
				expect(f.Weld.Part1).to.equal(f.Chassis)
				expect(f.Cart.Root).to.equal(f.Root)
				expect(f.Cart.DriverSeat).to.equal(f.Seat)
				expect(f.Cart.CargoSlots).to.equal(f.Folders.CargoSlots)
				expect(f.Cart.FormationSlots).to.equal(f.Folders.FormationSlots)
				expect(f.CargoBody.Parent).to.equal(f.CargoVisual)
				expect(f.Identity.ItemId).to.equal("fresh:same")
				expect(f.Identity.EscapeAttemptCount).to.equal(1)
				expect(f.Identity.MutationId).to.equal("Astral")
				expect(f.Cart.Visual.ScoutArt.CanCollide).to.equal(false)
				for _, joint in f.Cart.Visual:GetDescendants() do
					if joint:IsA("WeldConstraint") then
						expect(joint.Part0 == f.Root or joint.Part1 == f.Root).to.equal(true)
					end
				end
				expect(
					(f.Cart.Visual.ScoutArt.Position - f.Root.CFrame:PointToWorldSpace(Vector3.new(3, 2, 0))).Magnitude
						< 0.001
				).to.equal(true)
				-- Starter 48 x Scout 1.10 x SpeedLevel 3 (1.30).
				expect(math.abs(f.Record.MovementProfile.MaxTravelSpeed - 68.64) < 1e-8).to.equal(true)
			end)
		end)
		it("rejects a transfer/reset or changed dock at preparation and atomic revalidation", function()
			fixture(function(f)
				f.Busy(true)
				expect(Cart:PrepareOwnedCartSelection(f.Player, "CRT_008")).to.equal(nil)
				f.Busy(false)
				local preparation = assert(Cart:PrepareOwnedCartSelection(f.Player, "CRT_008"))
				f.Cart:SetAttribute("Phase13CargoResetGeneration", 1)
				expect(preparation.Validate()).to.equal(false)
				expect(f.Cart.Visual).to.equal(f.Visual)
				expect(f.Cart:GetAttribute("CartId")).to.equal("CRT_001")
				f.Cart:SetAttribute("Phase13CargoResetGeneration", nil)
				f.Root.CFrame += Vector3.new(100, 0, 0)
				expect(preparation.Validate()).to.equal(false)
			end)
		end)
	end)
end
