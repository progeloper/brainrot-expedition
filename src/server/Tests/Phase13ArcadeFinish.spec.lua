--!strict
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.Phase13AppearanceRules)
	local function expectPartColor(actual: Color3, expected: Color3)
		-- BasePart.Color stores channel values at 8-bit precision.
		local tolerance = 0.5 / 255 + 0.000001
		expect(math.abs(actual.R - expected.R) <= tolerance).to.equal(true)
		expect(math.abs(actual.G - expected.G) <= tolerance).to.equal(true)
		expect(math.abs(actual.B - expected.B) <= tolerance).to.equal(true)
	end
	local function fixture()
		local model = Instance.new("Model")
		for _, name in { "Body", "Wheel_L", "Wheel_R" } do
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Color = Color3.new(1, 1, 1)
			part:SetAttribute("ArcadeVisualRevision", 3)
			part:SetAttribute("Phase13FinishAlias", if name == "Body" then "Floor" else "CuboidWheel")
			local surface = Instance.new("SurfaceAppearance")
			surface.Color = Color3.fromRGB(240, 245, 250)
			surface.Parent = part
			part.Parent = model
		end
		return model
	end
	describe("Tagged arcade atlas finish integration", function()
		it("tints the atlas target idempotently and restores Default without changing map or mechanical bindings", function()
			local model = fixture()
			local before = {}
			for _, part in model:GetChildren() do
				local surface = part:FindFirstChildOfClass("SurfaceAppearance")
				before[part] = { Tint = surface.Color, Size = part.Size, Frame = part.CFrame, Color = part.Color, ColorMap = surface.ColorMap, NormalMap = surface.NormalMap, RoughnessMap = surface.RoughnessMap }
			end
			local ok, why = xpcall(function()
				local count = Rules.Apply(model, "Riftgold", "Cart", "CRT_001")
				expect(count).to.equal(3)
				for part, state in before do
					local surface = part:FindFirstChildOfClass("SurfaceAppearance")
					local tint = surface.Color
					expect(tint).to.equal(Rules.Color(state.Tint, "Riftgold", part.Name))
					Rules.Apply(model, "Riftgold", "Cart", "CRT_001")
					expect(surface.Color).to.equal(tint)
					expect(part.Size).to.equal(state.Size)
					expect(part.CFrame).to.equal(state.Frame)
					expect(part.Color).to.equal(state.Color)
					expect(surface.ColorMap).to.equal(state.ColorMap)
					expect(surface.NormalMap).to.equal(state.NormalMap)
					expect(surface.RoughnessMap).to.equal(state.RoughnessMap)
				end
				Rules.Apply(model, "Default", "Cart", "CRT_001")
				for part, state in before do
					expect(part:FindFirstChildOfClass("SurfaceAppearance").Color).to.equal(state.Tint)
				end
			end, debug.traceback)
			model:Destroy()
			assert(ok, why)
		end)
		it("keeps the existing Starter body and hardware aliases distinct", function()
			local model = fixture()
			local ok, why = xpcall(function()
				Rules.Apply(model, "Trailblazer", "Cart", "CRT_001")
				expect(model.Body.SurfaceAppearance.Color).to.equal(Color3.fromRGB(28, 153, 157))
				expect(model.Wheel_L.SurfaceAppearance.Color).to.equal(Color3.fromRGB(242, 129, 41))
				expect(model.Wheel_R.SurfaceAppearance.Color).to.equal(model.Wheel_L.SurfaceAppearance.Color)
			end, debug.traceback)
			model:Destroy()
			assert(ok, why)
		end)
		it("preserves native union face colors on Default after repeated required finishes", function()
			local model = Instance.new("Model")
			local part = Instance.new("UnionOperation")
			part.Name, part.Color, part.UsePartColor = "Body", Color3.fromRGB(180, 90, 25), false
			part.Size, part.CFrame = Vector3.new(6, 3, 8), CFrame.new(3, 4, 5)
			part:SetAttribute("ArcadeVisualRevision", 3)
			part:SetAttribute("NativeVehicleConstruction", "CSG")
			part:SetAttribute("Phase13FinishAlias", "Floor")
			part.Parent = model
			local original = part.Color
			local ok, why = xpcall(function()
				for _ = 1, 3 do
					Rules.Apply(model, "Riftgold", "Cart", "CRT_001")
					expect(part.UsePartColor).to.equal(true)
					expectPartColor(part.Color, Rules.Color(original, "Riftgold", "Floor"))
					Rules.Apply(model, "Default", "Cart", "CRT_001")
					expect(part.UsePartColor).to.equal(false)
					expect(part.Color).to.equal(original)
				end
				Rules.Apply(model, "Riftgold", "Cart", "CRT_001")
				Rules.Apply(model, "UNKNOWN_FINISH", "Cart", "CRT_001")
				expect(part.UsePartColor).to.equal(false)
				expect(part.Color).to.equal(original)
				expect(part.Size).to.equal(Vector3.new(6, 3, 8))
				expect(part.CFrame).to.equal(CFrame.new(3, 4, 5))
			end, debug.traceback)
			model:Destroy()
			assert(ok, why)
		end)
		it("supports the native union Starter role and leaves optional finishes rejected", function()
			local model = Instance.new("Model")
			for _, name in { "Body", "Wheel_L", "Wheel_R" } do
				local part = Instance.new("UnionOperation")
				part.Name, part.UsePartColor, part.Color = name, false, Color3.fromRGB(140, 80, 30)
				part:SetAttribute("ArcadeVisualRevision", 3)
				part:SetAttribute("NativeVehicleConstruction", "CSG")
				part:SetAttribute("Phase13FinishAlias", if name == "Body" then "Floor" else "CuboidWheel")
				part.Parent = model
			end
			local ok, why = xpcall(function()
				Rules.Apply(model, "Trailblazer", "Cart", "CRT_001")
				expect(model.Body.Color).to.equal(Color3.fromRGB(28, 153, 157))
				expect(model.Wheel_L.Color).to.equal(Color3.fromRGB(242, 129, 41))
				expect(model.Wheel_R.Color).to.equal(model.Wheel_L.Color)
				local count = Rules.Apply(model, "FIN_GLACIER", "Cart", "CRT_001")
				expect(count).to.equal(0)
				for _, part in model:GetChildren() do
					expect(part.UsePartColor).to.equal(false)
					expect(part.Color).to.equal(Color3.fromRGB(140, 80, 30))
				end
			end, debug.traceback)
			model:Destroy()
			assert(ok, why)
		end)
		it("retains optional atlas rejection and removes any former required-finish tint on rejection", function()
			local model = fixture()
			local original = model.Body.SurfaceAppearance.Color
			local ok, why = xpcall(function()
				Rules.Apply(model, "Riftgold", "Cart", "CRT_001")
				local count, diagnostics = Rules.Apply(model, "FIN_GLACIER", "Cart", "CRT_001")
				expect(count).to.equal(0)
				expect(diagnostics.protected > 0 or #diagnostics.atlasBlocked > 0).to.equal(true)
				expect(model.Body.SurfaceAppearance.Color).to.equal(original)
			end, debug.traceback)
			model:Destroy()
			assert(ok, why)
		end)
	end)
end
