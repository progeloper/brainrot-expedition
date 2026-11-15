--!nocheck
-- Real native view instances with an injected authoritative clock. These are
-- lifecycle/presentation tests, not a physical-device or independent-client run.
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Presentation = require(ReplicatedStorage.Shared.Utility.DazePresentation)
	local Style = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
	local Controller =
		require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.PlayerDazeController)
	local function fixture(callback)
		local gui = Instance.new("Folder") -- Isolated GUI parent; no live player UI.
		local character = Instance.new("Model")
		character.Name, character.Parent = "SPEC_DAZE_CHARACTER", workspace
		character:SetAttribute("Phase10CharacterGeneration", 1)
		local head = Instance.new("Part")
		head.Name, head.Anchored, head.Parent = "Head", true, character
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck, humanoid.Parent = false, character
		local unrelated = Instance.new("Highlight")
		unrelated.Name, unrelated.Parent = "OtherSystemEffect", character
		local attributes = {
			Phase10DazeEnd = 103,
			Phase10ProtectionEnd = 108,
			Phase10DazeRevision = 1,
			Phase10DazeCharacterGeneration = 1,
		}
		local player = { Character = character }
		function player:GetAttribute(key)
			return attributes[key]
		end
		local clock = 100
		local view = Controller.CreateView(player, gui, function()
			return clock
		end)
		local f = {
			Gui = gui,
			Character = character,
			Head = head,
			Humanoid = humanoid,
			Player = player,
			Attributes = attributes,
			View = view,
		}
		function f.At(time)
			clock = time
			return view:Update()
		end
		function f.Label()
			local billboard = gui:FindFirstChild("Phase10DazeCountdown")
			return if billboard then billboard.Countdown else nil
		end
		local ok, err = xpcall(function()
			callback(f)
		end, debug.traceback)
		view:Destroy()
		assert(unrelated.Parent == character, "Daze cleanup deleted another effect")
		gui:Destroy()
		character:Destroy()
		if not ok then
			error(err)
		end
	end

	describe("Phase10 authoritative countdown and protection presentation", function()
		it("uses exact endpoints and never prints zero while daze remains active", function()
			expect(Presentation.Text(103, 100)).to.equal("3.00")
			expect(Presentation.Text(103, 102.9999)).to.equal("0.01")
			expect(Presentation.Text(103, 103)).to.equal("0.00")
			expect(Presentation.Text(103, 104)).to.equal("0.00")
			expect(Presentation.Color(103, 100)).to.equal(Color3.fromRGB(255, 64, 64))
			expect(Presentation.Color(103, 101.5)).to.equal(Color3.fromRGB(64, 160, 255))
			expect(Presentation.Color(103, 103)).to.equal(Color3.fromRGB(80, 255, 100))
		end)
		it("reuses one occluded label with the current main name font and 110% constraints", function()
			fixture(function(f)
				expect(f.At(100)).to.equal(true)
				local label = f.Label()
				expect(label.Font).to.equal(Style.Typography.Font)
				expect(label.UIStroke.Color).to.equal(Style.Colors.TextStroke)
				expect(label.UIStroke.Thickness).to.equal(Style.Typography.NameStrokeThickness)
				expect(label.UITextSizeConstraint.MinTextSize).to.equal(
					math.round(Style.Typography.NameMinTextSize * 1.1)
				)
				expect(label.UITextSizeConstraint.MaxTextSize).to.equal(
					math.round(Style.Typography.NameMaxTextSize * 1.1)
				)
				expect(label.Parent.AlwaysOnTop).to.equal(false)
				expect(label.Parent.MaxDistance).to.equal(55)
				f.At(101.5)
				expect(f.Label()).to.equal(label)
				expect(label.Text).to.equal("1.50")
				expect(label.TextColor3).to.equal(Presentation.Blue)
				expect(f.Character:FindFirstChild("Phase10ProtectionFilm")).to.equal(nil)
			end)
		end)
		it("restores at three, holds/fades green separately, and removes film at eight", function()
			fixture(function(f)
				f.At(100)
				expect(f.At(103)).to.equal(false)
				expect(f.Label().Text).to.equal("0.00")
				expect(f.Label().TextColor3).to.equal(Presentation.Green)
				local film = f.Character:FindFirstChild("Phase10ProtectionFilm")
				expect(film.FillColor).to.equal(Color3.fromRGB(150, 220, 255))
				expect(math.abs(film.FillTransparency - 0.72) < 1e-6).to.equal(true)
				expect(film.OutlineTransparency).to.equal(1)
				expect(film.DepthMode).to.equal(Enum.HighlightDepthMode.Occluded)
				f.At(103.25)
				expect(f.Label().TextTransparency).to.equal(0)
				f.At(103.325)
				expect(f.Label().TextTransparency > 0.49).to.equal(true)
				f.At(103.401)
				expect(f.Label()).to.equal(nil)
				f.At(107.99)
				expect(f.Character.Phase10ProtectionFilm).to.equal(film)
				f.At(108)
				expect(f.Character:FindFirstChild("Phase10ProtectionFilm")).to.equal(nil)
			end)
		end)
		it("handles late replication and Camp early completion without extending deadlines", function()
			fixture(function(f)
				f.At(101.5)
				expect(f.Label().Text).to.equal("1.50")
				expect(f.Label().TextColor3).to.equal(Presentation.Blue)
				f.Attributes.Phase10DazeEnd = 102
				f.Attributes.Phase10ProtectionEnd = 107
				expect(f.At(102)).to.equal(false)
				expect(f.Label().Text).to.equal("0.00")
				f.At(102.41)
				expect(f.Label()).to.equal(nil)
				f.At(107)
				expect(f.Character:FindFirstChild("Phase10ProtectionFilm")).to.equal(nil)
			end)
		end)
		it("does not restart green hold when recovery replication clears the active deadline", function()
			fixture(function(f)
				f.At(102.9)
				f.Attributes.Phase10DazeEnd = 0
				f.Attributes.Phase10ProtectionEnd = 108
				f.At(103.3)
				expect(f.Label().Text).to.equal("0.00")
				expect(f.Label().TextTransparency > 0.32).to.equal(true)
				f.At(103.401)
				expect(f.Label()).to.equal(nil)
			end)
		end)
		it("ignores old-character daze and cleans only owned effects on death", function()
			fixture(function(f)
				f.Character:SetAttribute("Phase10CharacterGeneration", 2)
				expect(f.At(100)).to.equal(false)
				expect(f.Label()).to.equal(nil)
				f.Attributes.Phase10DazeCharacterGeneration = 2
				f.At(100)
				expect(f.Label() ~= nil).to.equal(true)
				f.Humanoid.Health = 0
				f.At(101)
				expect(f.Label()).to.equal(nil)
				expect(f.Character:FindFirstChild("Phase10ProtectionFilm")).to.equal(nil)
			end)
		end)
		it("a new revision replaces completion without an old callback clearing it", function()
			fixture(function(f)
				f.At(100)
				f.At(103)
				f.Attributes.Phase10DazeRevision = 2
				f.Attributes.Phase10DazeEnd = 107
				f.Attributes.Phase10ProtectionEnd = 112
				expect(f.At(104)).to.equal(true)
				local label = f.Label()
				expect(label.Text).to.equal("3.00")
				f.At(104.4)
				expect(f.Label()).to.equal(label)
				expect(f.Character:FindFirstChild("Phase10ProtectionFilm")).to.equal(nil)
			end)
		end)
	end)
end
