--!nocheck
-- Voxel V4: builder determinism, native template parity, role coverage, Protected
-- immunity, exact Normal -> mutation -> Normal restore, idempotent scaling, fit
-- envelope, Atomic streaming and Neon presence. Edit mode; no profiles or Play.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Builder = require(RS.Shared.Utility.VoxelCreatureBuilder)
	local Registry = require(RS.Shared.Utility.VoxelCreatureRegistry)
	local Palette = require(RS.Shared.Config.VoxelCreaturePalette)
	local Adapter = require(RS.Shared.Utility.MutationAppearanceAdapter)
	local Appearance = require(RS.Shared.Utility.BrainrotAppearance)
	local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
	local Rarities = {
		BRT_001 = "Common",
		BRT_002 = "Common",
		BRT_003 = "Common",
		BRT_004 = "Common",
		BRT_005 = "Common",
		BRT_006 = "Common",
		BRT_007 = "Common",
		BRT_008 = "Common",
		BRT_009 = "Common",
		BRT_010 = "Common",
		BRT_011 = "Uncommon",
		BRT_012 = "Uncommon",
		BRT_013 = "Uncommon",
		BRT_014 = "Uncommon",
		BRT_015 = "Uncommon",
		BRT_016 = "Uncommon",
		BRT_017 = "Uncommon",
		BRT_018 = "Uncommon",
		BRT_019 = "Rare",
		BRT_020 = "Rare",
		BRT_021 = "Rare",
		BRT_022 = "Rare",
		BRT_023 = "Rare",
		BRT_024 = "Rare",
		BRT_025 = "Rare",
		BRT_026 = "Epic",
		BRT_027 = "Epic",
		BRT_028 = "Epic",
		BRT_029 = "Epic",
		BRT_030 = "Epic",
		BRT_031 = "Legendary",
		BRT_032 = "Legendary",
		BRT_033 = "Legendary",
		BRT_034 = "Mythic",
		BRT_035 = "Secret",
	}

	local function snapshot(model)
		local rows = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				rows[part:GetFullName() .. "#" .. tostring(part:GetAttribute("VoxelIndex"))] =
					table.concat({
						part.Color:ToHex(),
						part.Material.Name,
						part.MaterialVariant,
						string.format("%.4f", part.Reflectance),
						string.format("%.4f", part.Transparency),
						tostring(part.Size),
						tostring(part.CFrame),
					}, "|")
			end
		end
		return rows
	end
	local function same(a, b)
		for key, value in a do
			if b[key] ~= value then
				return false, key
			end
		end
		for key in b do
			if a[key] == nil then
				return false, key
			end
		end
		return true, nil
	end
	local function geometry(model)
		local rows = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(
					rows,
					part.Name
						.. "|"
						.. tostring(part.Size)
						.. "|"
						.. tostring(part.CFrame)
						.. "|"
						.. part.Color:ToHex()
						.. "|"
						.. part.Material.Name
						.. "|"
						.. part.MaterialVariant
				)
			end
		end
		table.sort(rows)
		return table.concat(rows, "\n")
	end

	for _, id in Registry.ListSpecies() do
		local data = Registry.GetData(id)
		describe("Voxel V4 " .. id, function()
			it("builds deterministically", function()
				local a, b = Builder.Build(data), Builder.Build(data)
				expect(geometry(a)).to.equal(geometry(b))
				expect(a:GetAttribute("VoxelSignature")).to.equal(Builder.Signature(data))
				a:Destroy()
				b:Destroy()
			end)

			it("is installed natively and matches a fresh build", function()
				local template = Registry.GetTemplate(id)
				expect(template ~= nil).to.equal(true)
				local fresh = Builder.Build(data)
				expect(template:GetAttribute("VoxelSignature")).to.equal(
					fresh:GetAttribute("VoxelSignature")
				)
				expect(geometry(template)).to.equal(geometry(fresh))
				expect(template.PrimaryPart ~= nil and template.PrimaryPart.Name).to.equal("Root")
				fresh:Destroy()
			end)

			it("has Atomic streaming, full role coverage, a Body contract and Neon", function()
				local model = Registry.GetTemplate(id)
				expect(model.ModelStreamingMode).to.equal(Enum.ModelStreamingMode.Atomic)
				local allowed = { Protected = true }
				for _, role in Palette.Roles do
					allowed[role] = true
				end
				local neon, bad, bodies, plastic, studOnFace = 0, 0, 0, 0, 0
				for _, part in model:GetDescendants() do
					if
						part:IsA("BasePart")
						and part ~= model.PrimaryPart
						and part:GetAttribute("RigBone") == nil
					then
						if not allowed[part:GetAttribute("Role")] then
							bad += 1
						end
						if part.Material == Enum.Material.Neon then
							neon += 1
						end
						if part.Material == Enum.Material.Plastic then
							plastic += 1
						end
						if part.Name == "Body" then
							bodies += 1
							expect(part:FindFirstChild("CaptureAttachment") ~= nil).to.equal(true)
							expect(part:FindFirstChild("CargoAttachment") ~= nil).to.equal(true)
						end
						if
							part.MaterialVariant ~= ""
							and (
								part:GetAttribute("Relief") ~= true
								or part:GetAttribute("Protected") == true
							)
						then
							studOnFace += 1
						end
						expect(part.CanCollide or part.CanQuery or part.CanTouch).to.equal(false)
					end
				end
				expect(bad).to.equal(0)
				expect(bodies).to.equal(1)
				expect(plastic).to.equal(0)
				expect(studOnFace).to.equal(0)
				expect(neon > 0).to.equal(true)
				for _, anchor in
					{
						"HeadTop",
						"CarryGrip",
						"CargoSeat",
						"BankDisplay",
						"FrontTeamMount",
						"Mouth",
						"FxCore",
					}
				do
					expect(model.PrimaryPart:FindFirstChild(anchor) ~= nil).to.equal(true)
				end
			end)

			it("is rigged: Motor6D bone chain from Root, every box welded to its bone", function()
				local model = Registry.GetTemplate(id)
				expect(model:GetAttribute("VoxelRigged")).to.equal(true)
				local controller = model:FindFirstChildOfClass("AnimationController")
				expect(controller ~= nil and controller:FindFirstChildOfClass("Animator") ~= nil).to.equal(
					true
				)
				expect(model.PrimaryPart.Anchored).to.equal(true)
				local bones, names, loose, badWeld = {}, {}, 0, 0
				for _, part in model:GetChildren() do
					if part:IsA("BasePart") and part:GetAttribute("RigBone") then
						expect(names[part.Name]).to.equal(nil)
						names[part.Name] = true
						bones[part] = true
						expect(part.Transparency).to.equal(1)
						expect(part.Anchored).to.equal(false)
					end
				end
				expect(names[Builder.RigBonePrefix .. "Torso"]).to.equal(true)
				-- each bone has exactly one Motor6D (Part1 = bone) and its chain reaches Root
				for bone in bones do
					local motors = {}
					for _, child in bone:GetChildren() do
						if child:IsA("Motor6D") then
							table.insert(motors, child)
						end
					end
					expect(#motors).to.equal(1)
					expect(motors[1].Part1).to.equal(bone)
					local node, steps = bone, 0
					while node ~= model.PrimaryPart and steps < 10 do
						local motor = node:FindFirstChildOfClass("Motor6D")
						node = motor and motor.Part0
						steps += 1
					end
					expect(node).to.equal(model.PrimaryPart)
				end
				for _, part in model:GetChildren() do
					if part:IsA("BasePart") and part:GetAttribute("VoxelV4") then
						local weld = part:FindFirstChildOfClass("WeldConstraint")
						if part.Anchored then
							loose += 1
						end
						if
							not weld
							or weld.Part1 ~= part
							or not bones[weld.Part0]
							or weld.Part0.Name
								~= Builder.RigBonePrefix .. part:GetAttribute("Bone")
						then
							badWeld += 1
						end
					end
				end
				expect(loose).to.equal(0)
				expect(badWeld).to.equal(0)
			end)

			it("fits the gameplay envelope and box budget", function()
				local m = Builder.Measure(data)
				local giant = Builder.SizeMultiplier(data)
				expect(giant >= 1 and giant <= Palette.Fit.GiantSizeMultiplierMax).to.equal(true)
				expect(m.normalizedSize.Z <= Palette.Fit.MaxDepthStuds * giant).to.equal(true)
				expect(m.normalizedSize.X <= Palette.Fit.MaxWidthStuds * giant).to.equal(true)
				expect(math.abs(m.normalizedSize.Y - Builder.TargetHeight(data)) < 0.01).to.equal(
					true
				)
				local rarity = Rarities[id] or "Rare"
				local legendaryPlus = rarity == "Legendary"
					or rarity == "Mythic"
					or rarity == "Secret"
				local maxBoxes = if legendaryPlus
					then Palette.Fit.MaxBoxesLegendaryPlus
					else Palette.Fit.MaxBoxes
				local maxTriangles = if legendaryPlus
					then Palette.Fit.MaxTrianglesLegendaryPlus
					else Palette.Fit.MaxTrianglesCommonToEpic
				expect(#data.boxes >= Palette.Fit.MinBoxes and #data.boxes <= maxBoxes).to.equal(
					true
				)
				expect(#data.boxes * Palette.Fit.TrianglesPerBox <= maxTriangles).to.equal(true)
			end)

			it("keeps passive FX within budget and engine-bundled", function()
				local model = Registry.GetTemplate(id)
				local count = 0
				for _, item in model:GetDescendants() do
					if item:IsA("ParticleEmitter") and item:GetAttribute("V4PassiveFx") == true then
						count += 1
						expect(item.Rate <= Palette.PassiveFx.MaxRate).to.equal(true)
						expect(item.Lifetime.Max <= Palette.PassiveFx.MaxLifetime).to.equal(true)
						expect(string.sub(item.Texture, 1, 9)).to.equal("rbxasset:")
					end
				end
				expect(count <= Palette.PassiveFx.MaxEmitters).to.equal(true)
			end)

			it("scales idempotently to the canonical height", function()
				local model = Registry.GetTemplate(id):Clone()
				model:SetAttribute("BrainrotId", id)
				local ok1 = Scale.ApplyCanonicalScale(model, "V4Spec")
				local first = model:GetScale()
				local ok2 = Scale.ApplyCanonicalScale(model, "V4Spec")
				expect(ok1 and ok2).to.equal(true)
				expect(math.abs(model:GetScale() - first) < 1e-6).to.equal(true)
				local low, high = math.huge, -math.huge
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Transparency < 1 then
						low = math.min(low, part.Position.Y - part.Size.Y / 2)
						high = math.max(high, part.Position.Y + part.Size.Y / 2)
					end
				end
				expect(
					math.abs((high - low) - Builder.TargetHeight(data))
						< Palette.Fit.HeightToleranceStuds
				).to.equal(true)
				model:Destroy()
			end)

			for _, mutation in Palette.Mutations do
				it("applies " .. mutation .. ", keeps Protected/studs, restores exactly", function()
					local model = Registry.GetTemplate(id):Clone()
					model:SetAttribute("BrainrotId", id)
					Scale.ApplyCanonicalScale(model, "V4Spec")
					model.Parent = workspace
					local before = snapshot(model)
					local protected = {}
					for _, part in model:GetDescendants() do
						if part:IsA("BasePart") and part:GetAttribute("Protected") == true then
							protected[part] = part.Color:ToHex()
								.. part.Material.Name
								.. part.MaterialVariant
						end
					end
					local ok = Appearance.ApplyAppearance(
						model,
						Rarities[id] or "Rare",
						mutation,
						"Awake",
						"Detailed",
						{
							detailLevel = "High",
							glowAdmitted = true,
							isVisible = true,
							semanticOverlaysClear = true,
						}
					)
					expect(ok).to.equal(true)
					local roles = Palette.MutationPalettes[mutation]
					local overrides = data.mutationOverrides[mutation] or {}
					local wrong, touched, studsLost = 0, 0, 0
					for _, part in model:GetDescendants() do
						if part:IsA("BasePart") and part:GetAttribute("VoxelV4") then
							if protected[part] then
								if
									protected[part]
									~= part.Color:ToHex()
										.. part.Material.Name
										.. part.MaterialVariant
								then
									touched += 1
								end
							elseif
								mutation ~= "Radioactive"
								and not (mutation == "Glitched" and part:GetAttribute("Emissive"))
							then
								local expected = string.lower(
									string.sub(
										overrides[part:GetAttribute("Role")]
											or roles[part:GetAttribute("Role")],
										2
									)
								)
								if part.Color:ToHex() ~= expected then
									wrong += 1
								end
							end
							if
								part:GetAttribute("Relief") == true
								and part.MaterialVariant ~= Palette.Studs.MaterialVariant
							then
								studsLost += 1
							end
						end
					end
					expect(touched).to.equal(0)
					expect(wrong).to.equal(0)
					expect(studsLost).to.equal(0)
					expect(model:FindFirstChild("V4_MutationEffects") ~= nil).to.equal(true)
					expect(model:FindFirstChild("Phase12RarityGlow")).to.equal(nil)
					-- state change keeps the binding; Astral reveals when banked
					Appearance.UpdateAppearanceState(model, "Banked", {
						detailLevel = "High",
						glowAdmitted = true,
						isVisible = true,
						semanticOverlaysClear = true,
					})
					expect(Adapter.GetAppearanceState(model).state).to.equal("Banked")
					Appearance.ApplyAppearance(
						model,
						Rarities[id] or "Rare",
						"None",
						"Awake",
						"Detailed",
						{ detailLevel = "High" }
					)
					local ok2, key = same(before, snapshot(model))
					expect(ok2 and "restored" or key).to.equal("restored")
					expect(model:FindFirstChild("V4_MutationEffects")).to.equal(nil)
					Appearance.Restore(model)
					model:Destroy()
				end)
			end
		end)
	end
end
