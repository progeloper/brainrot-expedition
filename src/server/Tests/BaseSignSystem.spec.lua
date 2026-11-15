--!nocheck
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Base = require(script.Parent.Parent.Systems.PlayerBaseSystem)
	local Signs = require(script.Parent.Parent.Systems.BaseSignSystem)
	local function run(callback)
		Signs:Destroy()
		local created, restore, owners, listeners, bases = {}, {}, {}, {}, {}
		local function folder(parent, name)
			local result = parent:FindFirstChild(name)
			if not result then
				result = Instance.new("Folder")
				result.Name, result.Parent = name, parent
				table.insert(created, result)
			end
			return result
		end
		local assets = folder(folder(ReplicatedStorage, "StudioAssets"), "BaseSigns")
		assert(
			not assets:FindFirstChild("Sell Sign"),
			"Isolated fixture must not replace an imported sign"
		)
		local template = Instance.new("Model")
		template.Name, template.Parent = "Sell Sign", assets
		table.insert(created, template)
		local board = Instance.new("Part")
		board.Size, board.CFrame, board.Parent =
			Vector3.new(9.5, 4.75, 1), CFrame.new(0, 8, 0), template
		local post = Instance.new("Part")
		post.Size, post.CFrame, post.Parent =
			Vector3.new(2, 10.5, 0.6), CFrame.new(0, 5.25, 0.7), template
		local gui = Instance.new("SurfaceGui")
		gui.Adornee, gui.Parent = board, board
		local label = Instance.new("TextLabel")
		label.Text, label.Parent = "Sell Brainrots", gui
		for i = 1, 12 do
			local base = Instance.new("Model")
			base.Name, base.Parent = "SignBase" .. i, workspace
			base:SetAttribute("BaseId", base.Name)
			local foundation = Instance.new("Part")
			foundation.Name, foundation.Size = "Foundation", Vector3.new(96, 1, 64)
			foundation.CFrame = CFrame.new(i * 200, 0.5, 0) * CFrame.Angles(0, i * math.pi / 2, 0)
			foundation.Anchored, foundation.Parent = true, base
			local deck = Instance.new("Part")
			deck.Name, deck.Size = "CartDisplay", Vector3.new(32, 1, 24)
			deck.CFrame = foundation.CFrame * CFrame.new(28, 0, -54)
			deck.Anchored, deck.Parent = true, base
			table.insert(bases, base)
			table.insert(created, base)
		end
		local function replace(key, value)
			restore[key] = Base[key]
			Base[key] = value
		end
		replace("GetRegisteredBases", function()
			return bases
		end)
		replace("IsOwner", function(_, player, base)
			return owners[base] == player
		end)
		replace("SubscribeAssignments", function(_, assigned, releasing)
			listeners.assigned, listeners.releasing = assigned, releasing
			return {
				Disconnect = function()
					listeners.disconnected = true
				end,
			}
		end)
		local ok, err = xpcall(function()
			callback(bases, owners, listeners, template, label)
		end, debug.traceback)
		Signs:Destroy()
		for key, value in restore do
			Base[key] = value
		end
		for i = #created, 1, -1 do
			created[i]:Destroy()
		end
		assert(ok, err)
	end
	describe("Base ownership sign presentation", function()
		it(
			"creates exactly one supported, correctly facing sign per rotated base and reuses it",
			function()
				run(function(bases, _, _, template, sourceLabel)
					expect(Signs:Start()).to.equal(true)
					Signs:Start()
					for _, base in bases do
						local sign, label = Signs:EnsureSign(base)
						expect(Signs:EnsureSign(base)).to.equal(sign)
						expect(#base:GetChildren()).to.equal(3)
						expect(label.Text).to.equal("Unclaimed")
						expect(label.Parent.Adornee).to.equal(label.Parent.Parent)
						expect(
							label.Parent.Parent.CFrame.LookVector:Dot(
								base.Foundation.CFrame.LookVector
							) > 0.999
						).to.equal(true)
						local cf, size = sign:GetBoundingBox()
						expect(math.abs(cf.Position.Y - size.Y / 2) < 0.001).to.equal(true)
						for _, p in sign:GetChildren() do
							if p:IsA("BasePart") then
								expect(p.Anchored and not p.CanCollide and not p.CanTouch).to.equal(
									true
								)
							end
						end
					end
					expect(sourceLabel.Text).to.equal("Sell Brainrots")
					expect(template:GetChildren()[1].Anchored).to.equal(false)
				end)
			end
		)
		it(
			"uses each authorised username, not DisplayName or a callback's unrelated player",
			function()
				run(function(bases, owners, listeners)
					Signs:Start()
					local first = { Name = "TwentyCharacterNameX", DisplayName = "NotTheUsername" }
					local second = { Name = "SecondOwner" }
					owners[bases[1]], owners[bases[2]] = first, second
					listeners.assigned(first, bases[1])
					listeners.assigned(second, bases[2])
					local _, label1 = Signs:EnsureSign(bases[1])
					local _, label2 = Signs:EnsureSign(bases[2])
					expect(label1.Text).to.equal(first.Name)
					expect(label2.Text).to.equal(second.Name)
					expect(label1.TextScaled and label1.TextWrapped).to.equal(true)
					owners[bases[1]] = nil
					Signs:SetOwnerText(bases[1], first)
					expect(label1.Text).to.equal("Unclaimed")
					owners[bases[1]] = second
					listeners.assigned(second, bases[1])
					expect(label1.Text).to.equal(second.Name)
					Signs:Destroy()
					expect(listeners.disconnected).to.equal(true)
					Signs:Start()
					expect(#bases[1]:GetChildren()).to.equal(3)
				end)
			end
		)
		it("reports a missing template without blocking startup or altering bases", function()
			run(function(bases, _, _, template)
				template.Parent = nil
				expect(Signs:Start()).to.equal(false)
				expect(#bases[1]:GetChildren()).to.equal(2)
			end)
		end)
	end)
end
