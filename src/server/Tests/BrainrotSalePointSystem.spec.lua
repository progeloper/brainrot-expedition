--!nocheck
return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
	local Sale = require(script.Parent.Parent.Systems.BrainrotSaleSystem)
	local SalePoint = require(script.Parent.Parent.Systems.BrainrotSalePointSystem)

	-- Camp Rework: the legacy board/prompt text only exist in legacy mode; camp mode is pinned below.
	local function fixture(callback, campMode)
		SalePoint:Stop()
		local originalUsesCamp, originalPresent = SalePoint.UsesCampMenu, SalePoint.CampStallPresent
		SalePoint.UsesCampMenu = function()
			return campMode == true
		end
		SalePoint.CampStallPresent = function()
			return campMode == true
		end
		local created = {}
		local function own(instance)
			table.insert(created, instance)
			return instance
		end
		local function folder(parent, name)
			local result = parent:FindFirstChild(name)
			if not result then
				result = own(Instance.new("Folder"))
				result.Name = name
				result.Parent = parent
			end
			return result
		end

		-- A built place carries the real SellStall / Sell Sign; park them for the test and restore after.
		local parked = {}
		local function park(parent, name)
			local existing = parent:FindFirstChild(name)
			if existing then
				table.insert(parked, { instance = existing, parent = parent })
				existing.Parent = nil
			end
		end
		local patches = folder(folder(workspace, "MapBlockout"), "ServiceStallPatches")
		park(patches, "SellStall")
		assert(not patches:FindFirstChild("SellStall"), "Fixture must not replace a sale point")
		local stall = own(Instance.new("Part"))
		stall.Name = "SellStall"
		stall.Size = Vector3.new(56, 1, 32)
		stall.CFrame = CFrame.new(15000, 100, 15000) * CFrame.Angles(0, -math.pi / 2, 0)
		stall.Anchored = true
		stall.Parent = patches

		local signs = folder(folder(ReplicatedStorage, "StudioAssets"), "BaseSigns")
		park(signs, "Sell Sign")
		assert(not signs:FindFirstChild("Sell Sign"), "Fixture must not replace the sign source")
		local template = own(Instance.new("Model"))
		template.Name = "Sell Sign"
		template.Parent = signs
		local board = Instance.new("Part")
		board.Name = "Part"
		board.Size = Vector3.new(9.5, 4.75, 1)
		board.CFrame = CFrame.new(0, 8, 0)
		board.Color = Color3.fromRGB(247, 147, 30)
		board.Material = Enum.Material.Plastic
		board.Parent = template
		local post = Instance.new("Part")
		post.Name = "Part"
		post.Size = Vector3.new(2, 10.5, 0.6)
		post.CFrame = CFrame.new(0, 5.25, 0.7)
		post.Parent = template
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Adornee = board
		gui.Parent = board
		local sourceLabel = Instance.new("TextLabel")
		sourceLabel.Text = "Sell Brainrots"
		sourceLabel.Font = Enum.Font.FredokaOne
		sourceLabel.TextColor3 = Color3.new(1, 1, 1)
		sourceLabel.TextStrokeColor3 = Color3.new(0.05, 0.05, 0.05)
		sourceLabel.TextStrokeTransparency = 0
		sourceLabel.Visible = true
		sourceLabel.Parent = gui

		local originalCreatePreview = Sale.CreatePreview
		local calls = 0
		Sale.CreatePreview = function(_, player)
			calls += 1
			return if player then { SaleSessionId = "fixture" } else nil
		end
		local ok, problem = xpcall(function()
			callback({
				stall = stall,
				patches = patches,
				template = template,
				board = board,
				sourceLabel = sourceLabel,
				getCalls = function()
					return calls
				end,
			})
		end, debug.traceback)
		SalePoint:Stop()
		SalePoint.UsesCampMenu, SalePoint.CampStallPresent = originalUsesCamp, originalPresent
		Sale.CreatePreview = originalCreatePreview
		for index = #created, 1, -1 do
			if created[index].Parent then
				created[index]:Destroy()
			end
		end
		for _, entry in parked do
			entry.instance.Parent = entry.parent
		end
		assert(ok, problem)
	end

	local function managedChildren(parent, className, name)
		local result = {}
		for _, child in parent:GetChildren() do
			if
				child:IsA(className)
				and child.Name == name
				and child:GetAttribute("ManagedBy") == "BrainrotSalePointSystem"
			then
				table.insert(result, child)
			end
		end
		return result
	end

	describe("Phase 5F physical sale point", function()
		it(
			"clones the canonical sign once, preserves style, and places it from stall space",
			function()
				fixture(function(f)
					expect(SalePoint:Start()).to.equal(true)
					expect(SalePoint:Start()).to.equal(true)
					expect(SalePoint:EnsureSalePoint()).to.equal(true)
					local signs = managedChildren(f.patches, "Model", "SellBrainrotsSign")
					expect(#signs).to.equal(1)
					local sign = signs[1]
					local clonedLabel = sign:FindFirstChildWhichIsA("TextLabel", true)
					assert(clonedLabel, "Managed sign must retain the canonical text label")
					expect(clonedLabel.Text).to.equal("SELL BRAINROTS")
					expect(clonedLabel.Font).to.equal(f.sourceLabel.Font)
					expect(clonedLabel.TextColor3).to.equal(f.sourceLabel.TextColor3)
					expect(clonedLabel.TextStrokeColor3).to.equal(f.sourceLabel.TextStrokeColor3)
					expect(clonedLabel.TextStrokeTransparency).to.equal(
						f.sourceLabel.TextStrokeTransparency
					)
					expect(f.sourceLabel.Text).to.equal("Sell Brainrots")
					expect(f.board.Anchored).to.equal(false)
					local clonedBoard = clonedLabel:FindFirstAncestorWhichIsA("BasePart")
					assert(clonedBoard, "Managed sign label must remain on a display part")
					expect(clonedBoard.Color).to.equal(f.board.Color)
					expect(clonedBoard.Material).to.equal(f.board.Material)
					expect(clonedBoard.CFrame.LookVector:Dot(f.stall.CFrame.LookVector) > 0.999).to.equal(
						true
					)
					local bounds, size = sign:GetBoundingBox()
					local localGround = f.stall.CFrame:PointToObjectSpace(
						bounds.Position - Vector3.new(0, size.Y * 0.5, 0)
					)
					expect(
						(localGround - Vector3.new(-20, f.stall.Size.Y * 0.5, 20)).Magnitude < 0.01
					).to.equal(true)
					expect(localGround.Z > f.stall.Size.Z * 0.5).to.equal(true)
					for _, descendant in sign:GetDescendants() do
						expect(descendant:IsA("LuaSourceContainer")).to.equal(false)
						expect(descendant:IsA("ProximityPrompt")).to.equal(false)
						if descendant:IsA("BasePart") then
							expect(
								descendant.Anchored
									and not descendant.CanCollide
									and not descendant.CanTouch
									and not descendant.CanQuery
							).to.equal(true)
						end
					end
				end)
			end
		)

		it("owns one native prompt with the requested device and activation settings", function()
			fixture(function(f)
				SalePoint:Start()
				local prompts = managedChildren(f.stall, "ProximityPrompt", "SellBrainrotPrompt")
				expect(#prompts).to.equal(1)
				local prompt = prompts[1]
				expect(prompt.ActionText).to.equal("Sell Brainrot")
				expect(prompt.ObjectText).to.equal("SELL BRAINROTS")
				expect(prompt.KeyboardKeyCode).to.equal(Enum.KeyCode.E)
				expect(prompt.GamepadKeyCode).to.equal(Enum.KeyCode.ButtonX)
				expect(prompt.MaxActivationDistance).to.equal(
					InteractionConfig.SELL_INTERACTION_DISTANCE
				)
				expect(prompt.HoldDuration).to.equal(0)
				expect(prompt.RequiresLineOfSight).to.equal(false)
				expect(prompt.ClickablePrompt).to.equal(true)
				expect(prompt.Exclusivity).to.equal(Enum.ProximityPromptExclusivity.AlwaysShow)
				expect(prompt.Enabled).to.equal(true)
			end)
		end)

		it("camp mode: counter prompt reads Open / SELL and no legacy board is spawned", function()
			fixture(function(f)
				expect(SalePoint:Start()).to.equal(true)
				expect(#managedChildren(f.patches, "Model", "SellBrainrotsSign")).to.equal(0)
				local prompts = managedChildren(f.stall, "ProximityPrompt", "SellBrainrotPrompt")
				expect(#prompts).to.equal(1)
				expect(prompts[1].ActionText).to.equal("Open")
				expect(prompts[1].ObjectText).to.equal("SELL")
			end, true)
		end)

		it("camp mode removes a stale legacy board", function()
			fixture(function(f)
				SalePoint:Start()
				SalePoint:Stop()
				expect(#managedChildren(f.patches, "Model", "SellBrainrotsSign")).to.equal(1)
				SalePoint.UsesCampMenu = function()
					return true
				end
				expect(SalePoint:EnsureSalePoint()).to.equal(true)
				expect(#managedChildren(f.patches, "Model", "SellBrainrotsSign")).to.equal(0)
			end)
		end)

		it("routes only its exact prompt once and repairs only its own duplicates", function()
			fixture(function(f)
				SalePoint:Start()
				local sign = managedChildren(f.patches, "Model", "SellBrainrotsSign")[1]
				local prompt = managedChildren(f.stall, "ProximityPrompt", "SellBrainrotPrompt")[1]
				local duplicateSign = sign:Clone()
				duplicateSign.Parent = f.patches
				local duplicatePrompt = prompt:Clone()
				duplicatePrompt.Parent = f.stall
				local unrelatedPrompt = Instance.new("ProximityPrompt")
				unrelatedPrompt.Name = "OtherFeaturePrompt"
				unrelatedPrompt.Parent = f.stall
				expect(SalePoint:EnsureSalePoint()).to.equal(true)
				expect(#managedChildren(f.patches, "Model", "SellBrainrotsSign")).to.equal(1)
				expect(#managedChildren(f.stall, "ProximityPrompt", "SellBrainrotPrompt")).to.equal(
					1
				)
				expect(unrelatedPrompt.Parent).to.equal(f.stall)
				prompt = managedChildren(f.stall, "ProximityPrompt", "SellBrainrotPrompt")[1]
				expect(SalePoint:HandlePromptTriggered(unrelatedPrompt, Players)).to.equal(false)
				expect(f.getCalls()).to.equal(0)
				expect(SalePoint:HandlePromptTriggered(prompt, Players)).to.equal(true)
				expect(f.getCalls()).to.equal(1)
			end)
		end)
	end)
end
