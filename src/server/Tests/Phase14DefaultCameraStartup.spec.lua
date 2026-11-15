--!nocheck
-- Real engine camera/subject fixtures; no writes to Workspace.CurrentCamera.
return function()
	local Startup = require(game.StarterPlayer.StarterPlayerScripts.Client.Utility.DefaultCameraStartup)
	local function fixture(mode, subjectReady)
		local root = Instance.new("Folder")
		root.Parent = workspace
		local character = Instance.new("Model")
		character.Parent = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		local camera = Instance.new("Camera")
		camera.CameraType = mode
		camera.CFrame = CFrame.new(23, 7, -11) * CFrame.Angles(0.2, 0.6, 0)
		camera.Focus = CFrame.new(24, 5, -16)
		camera.FieldOfView = 73
		camera.Parent = root
		if subjectReady then
			camera.CameraSubject = humanoid
		end
		local attrs, now = {}, 0
		local player = { Parent = root, Character = character }
		function player:GetAttribute(key)
			return attrs[key]
		end
		local heartbeat = Instance.new("BindableEvent")
		local world = { CurrentCamera = camera }
		local state = Startup.Start(player, {
			Workspace = world,
			Players = root,
			Heartbeat = heartbeat.Event,
			Clock = function()
				return now
			end,
		})
		return {
			Root = root,
			Player = player,
			Attrs = attrs,
			World = world,
			Camera = camera,
			Humanoid = humanoid,
			State = state,
			Advance = function(amount)
				now += amount
				heartbeat:Fire()
				task.wait()
			end,
			Destroy = function()
				state.Cancel()
				heartbeat:Destroy()
				root:Destroy()
			end,
		}
	end
	describe("Phase14 bounded normal camera startup", function()
		it("waits for the actual self subject and changes only the observed Fixed type", function()
			local f = fixture(Enum.CameraType.Fixed, false)
			local frame, focus, fov = f.Camera.CFrame, f.Camera.Focus, f.Camera.FieldOfView
			f.Advance(0.2)
			expect(f.State.Status).to.equal("Waiting")
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			f.Camera.CameraSubject = f.Humanoid
			f.Advance(0.2)
			f.Advance(0.05)
			expect(f.State.Status).to.equal("Waiting")
			f.Advance(0.06)
			expect(f.State.Status).to.equal("Repaired")
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Custom)
			expect(f.Camera.CameraSubject).to.equal(f.Humanoid)
			expect(f.Camera.CFrame).to.equal(frame)
			expect(f.Camera.Focus).to.equal(focus)
			expect(f.Camera.FieldOfView).to.equal(fov)
			expect(f.State.IsConnected()).to.equal(false)
			f.Destroy()
		end)
		it("hands off an already Custom camera and never reasserts after completion", function()
			local f = fixture(Enum.CameraType.Custom, true)
			f.Advance(0.11)
			expect(f.State.Status).to.equal("Ready")
			expect(f.State.IsConnected()).to.equal(false)
			f.Camera.CameraType = Enum.CameraType.Fixed
			f.Advance(9)
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			f.Destroy()
		end)
		it("preserves every existing nondefault camera mode", function()
			for _, mode in
				{ Enum.CameraType.Scriptable, Enum.CameraType.Attach, Enum.CameraType.Watch, Enum.CameraType.Follow }
			do
				local f = fixture(mode, true)
				expect(f.State.Status).to.equal("Owned")
				f.Advance(1)
				expect(f.Camera.CameraType).to.equal(mode)
				expect(f.State.IsConnected()).to.equal(false)
				f.Destroy()
			end
		end)
		it("leaves cinematic, team-preview and seated ownership unchanged", function()
			for _, claim in { "Phase13CinematicActive", "ChariotTeamMenuOpen", "Seated" } do
				local f = fixture(Enum.CameraType.Fixed, true)
				if claim == "Seated" then
					f.Humanoid.Sit = true
				else
					f.Attrs[claim] = true
				end
				f.Advance(0.2)
				expect(f.State.Status).to.equal("Owned")
				expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
				expect(f.State.IsConnected()).to.equal(false)
				f.Destroy()
			end
		end)
		it("resets readiness for a replacement camera before the one-time handoff", function()
			local f = fixture(Enum.CameraType.Fixed, true)
			local nextCamera = Instance.new("Camera")
			nextCamera.CameraType, nextCamera.CameraSubject = Enum.CameraType.Fixed, f.Humanoid
			nextCamera.Parent = f.Root
			f.World.CurrentCamera = nextCamera
			f.Advance(0.2)
			expect(nextCamera.CameraType).to.equal(Enum.CameraType.Fixed)
			f.Advance(0.11)
			expect(nextCamera.CameraType).to.equal(Enum.CameraType.Custom)
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			expect(f.State.IsConnected()).to.equal(false)
			f.Destroy()
		end)
		it("times out a foreign subject without changing it or retaining a listener", function()
			local f = fixture(Enum.CameraType.Fixed, false)
			local foreign = Instance.new("Humanoid")
			foreign.Parent = f.Root
			f.Camera.CameraSubject = foreign
			f.Advance(8.01)
			expect(f.State.Status).to.equal("Unavailable")
			expect(f.State.Reason).to.equal("SELF_CAMERA_TIMEOUT")
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			expect(f.Camera.CameraSubject).to.equal(foreign)
			expect(f.State.IsConnected()).to.equal(false)
			f.Destroy()
		end)
		it("cancels or releases a removed local player without a later camera write", function()
			local f = fixture(Enum.CameraType.Fixed, true)
			f.State.Cancel()
			f.Advance(0.2)
			expect(f.State.Status).to.equal("Cancelled")
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			expect(f.State.IsConnected()).to.equal(false)
			f.Destroy()
			f = fixture(Enum.CameraType.Fixed, true)
			f.Player.Parent = nil
			f.Advance(0.2)
			expect(f.State.Reason).to.equal("PLAYER_REMOVED")
			expect(f.Camera.CameraType).to.equal(Enum.CameraType.Fixed)
			expect(f.State.IsConnected()).to.equal(false)
			f.Destroy()
		end)
	end)
end
