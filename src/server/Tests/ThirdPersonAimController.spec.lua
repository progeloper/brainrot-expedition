--!nocheck
-- Isolated lifecycle/facing tests. Fake input, menu and render signals; real
-- Humanoid/root/Camera instances. These are NOT device or driving playtests.
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)
	local Aim =
		require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.ThirdPersonAimController)
	local function fixture(callback)
		local signals = {}
		local function signal()
			local listeners = {}
			local s = {}
			function s:Connect(fn)
				listeners[fn] = true
				return {
					Disconnect = function()
						listeners[fn] = nil
					end,
				}
			end
			function s:Fire(...)
				for fn in listeners do
					fn(...)
				end
			end
			function s:Count()
				local n = 0
				for _ in listeners do
					n += 1
				end
				return n
			end
			table.insert(signals, s)
			return s
		end
		local function observable(object)
			object.Signals = {}
			function object:GetPropertyChangedSignal(key)
				if not self.Signals[key] then
					self.Signals[key] = signal()
				end
				return self.Signals[key]
			end
			return object
		end
		local character = Instance.new("Model")
		character.Name, character.Parent = "SPEC_HUNTING_CHARACTER", workspace
		local root = Instance.new("Part")
		root.Name, root.Position, root.Parent = "HumanoidRootPart", Vector3.new(10000, 30, 10000), character
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck, humanoid.Parent = false, character
		local tool = Instance.new("Tool")
		tool.Name, tool.Parent = "SleepLauncher", character
		tool:SetAttribute("BrainrotSleepLauncher", true)
		local handle = Instance.new("Part")
		handle.Name, handle.Position, handle.Anchored, handle.CanQuery, handle.Parent =
			"Handle", root.Position, true, false, tool
		local muzzle = Instance.new("Attachment")
		muzzle.Name, muzzle.Parent = "Muzzle", handle
		local camera = Instance.new("Camera")
		camera.CameraType, camera.CameraSubject = Enum.CameraType.Custom, humanoid
		camera.CFrame = CFrame.lookAt(Vector3.new(10000, 35, 10012), root.Position)
		local player = {
			UserId = -8751,
			Character = character,
			CameraMode = Enum.CameraMode.Classic,
			CameraMinZoomDistance = 0.5,
			CameraMaxZoomDistance = 128,
		}
		function player:GetAttribute(key)
			return self[key]
		end
		local input = observable({
			PreferredInput = Enum.PreferredInput.KeyboardAndMouse,
			MouseBehavior = Enum.MouseBehavior.Default,
			MouseIconEnabled = true,
			TextBoxFocused = signal(),
			TextBoxFocusReleased = signal(),
			WindowFocused = signal(),
			WindowFocusReleased = signal(),
		})
		function input:GetFocusedTextBox()
			return self.TextBox
		end
		local gui = observable({ MenuIsOpen = false })
		local world = observable({ CurrentCamera = camera })
		local runtime = Instance.new("Folder")
		runtime.Name, runtime.Parent = "SPEC_TRACKING_RUNTIME", workspace
		local models = Instance.new("Folder")
		models.Name, models.Parent = "Brainrots", runtime
		local decoys = Instance.new("Folder")
		decoys.Name, decoys.Parent = "Decoys", runtime
		function world:FindFirstChild(name)
			return if name == "Runtime" then runtime else nil
		end
		function world:Raycast(...)
			return workspace:Raycast(...)
		end
		local clock = 0
		local focusCalls = {}
		local assistEligibility = {}
		local aimResetTokens = {}
		local nametags = {}
		function nametags.setFocusedBrainrot(model)
			table.insert(focusCalls, model or false)
		end
		function nametags.isAimAssistEligible(model)
			return assistEligibility[model] ~= false
		end
		function nametags.getAimResetToken(model)
			return aimResetTokens[model] or ""
		end
		local run = { Bindings = {}, Peak = 0 }
		function run:BindToRenderStep(name, priority, fn)
			assert(self.Bindings[name] == nil, "duplicate hunting render binding")
			self.Bindings[name] = fn
			self.Priority = priority
			self.Peak = math.max(self.Peak, 1)
		end
		function run:UnbindFromRenderStep(name)
			self.Bindings[name] = nil
		end
		local controller = Aim.new(player, {
			Input = input,
			Gui = gui,
			Run = run,
			World = world,
			Clock = function()
				return clock
			end,
			Nametags = nametags,
			OwnCartReader = function()
				return player.OwnCart
			end,
		})
		local manual = Vector2.zero
		local originalRotation = function()
			return manual
		end
		local adapter = { getRotation = originalRotation }
		assert(controller:SetCameraInput(adapter))
		local f = {
			Controller = controller,
			Player = player,
			Input = input,
			Gui = gui,
			Run = run,
			World = world,
			Camera = camera,
			Character = character,
			Humanoid = humanoid,
			Root = root,
			Tool = tool,
			Muzzle = muzzle,
			Models = models,
			Decoys = decoys,
			Adapter = adapter,
			OriginalRotation = originalRotation,
			FocusCalls = focusCalls,
			SetAssistEligible = function(model, eligible)
				assistEligibility[model] = eligible
			end,
			SetAimResetToken = function(model, token)
				aimResetTokens[model] = token
			end,
		}
		function f.Tick(dt, rotation, apply)
			clock += dt
			manual = rotation or Vector2.zero
			local delta = adapter.getRotation(dt)
			if apply then
				-- Same BaseCamera angular convention; simulated framing is not a Play test.
				local frame = CFrame.lookAt(Vector3.zero, camera.CFrame.LookVector)
				camera.CFrame = CFrame.new(camera.CFrame.Position)
					* CFrame.Angles(0, -delta.X, 0)
					* frame
					* CFrame.Angles(-delta.Y, 0, 0)
			end
			return delta
		end
		function f.Target(id, offset)
			local model = Instance.new("Model")
			model.Name, model.Parent = id, models
			model:SetAttribute("ItemId", id)
			model:SetAttribute("BrainrotId", "SPEC")
			model:SetAttribute("Captured", false)
			local body = Instance.new("Part")
			body.Name, body.Size, body.Anchored = "Body", Vector3.new(2, 4, 2), true
			body.Position, body.Parent = camera.CFrame.Position + offset, model
			return model
		end
		function f.Decoy(id, offset)
			local encounter = decoys:FindFirstChild("Encounter")
			if not encounter then
				encounter = Instance.new("Folder")
				encounter.Name, encounter.Parent = "Encounter", decoys
			end
			local model = Instance.new("Model")
			model.Name, model.Parent = id, encounter
			model:SetAttribute("EffectKind", "Decoy")
			model:SetAttribute("DecoyId", id)
			local proxy = Instance.new("Part")
			proxy.Name, proxy.Size, proxy.Anchored = "HitProxy", Vector3.new(2, 4, 2), true
			proxy.Position, proxy.Parent = camera.CFrame.Position + offset, model
			return model
		end
		local ok, err = xpcall(function()
			callback(f)
		end, debug.traceback)
		controller:Destroy()
		assert(adapter.getRotation == originalRotation, "camera input hook leaked")
		runtime:Destroy()
		character:Destroy()
		camera:Destroy()
		for _, s in signals do
			assert(s:Count() == 0, "leaked lifecycle listener")
		end
		assert(next(run.Bindings) == nil, "leaked hunting render binding")
		if not ok then
			error(err)
		end
	end

	describe("B2 default-camera input integration", function()
		local function prepare(f)
			local p = f.Root.Position + Vector3.new(0, 0, 12)
			f.Camera.CFrame = CFrame.lookAt(p, p - Vector3.zAxis)
			f.Controller:SetCharacter(f.Character)
		end
		local function acquire(f)
			for _ = 1, 4 do
				f.Tick(0.1)
			end
		end
		it("excludes actual owned cart geometry on foot while retaining another cart and real walls", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("beyond-own-cart", Vector3.new(3, 0, -30))
				local ownCart = Instance.new("Model")
				ownCart.Parent = f.Models
				ownCart:SetAttribute("OwnerUserId", f.Player.UserId)
				local ownBody = Instance.new("Part")
				ownBody.Size, ownBody.Anchored = Vector3.new(10, 8, 2), true
				ownBody.Position, ownBody.Parent = f.Camera.CFrame.Position + Vector3.new(1.5, 0, -15), ownCart
				f.Player.OwnCart = ownCart
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("beyond-own-cart")
				local paramsSeen
				local realRaycast = f.World.Raycast
				f.World.Raycast = function(world, origin, direction, params)
					paramsSeen = params
					return realRaycast(world, origin, direction, params)
				end
				expect(f.Controller:GetCrosshairTarget(nil)).to.equal(nil)
				expect(table.find(paramsSeen.FilterDescendantsInstances, ownCart) ~= nil).to.equal(true)
				local otherCart = Instance.new("Model")
				otherCart.Parent = f.Models
				otherCart:SetAttribute("OwnerUserId", f.Player.UserId + 1)
				otherCart:SetAttribute("Phase10TargetKind", "Cargo")
				otherCart:SetAttribute("ItemId", "other-cart-catch")
				local otherBody = ownBody:Clone()
				otherBody.Parent = otherCart
				local selected = f.Controller:GetCrosshairTarget(nil)
				expect(selected.ItemId).to.equal("other-cart-catch")
				expect(table.find(paramsSeen.FilterDescendantsInstances, otherCart)).to.equal(nil)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				otherCart:Destroy()
				local wall = Instance.new("Part")
				wall.Size, wall.Anchored, wall.Position, wall.Parent =
					Vector3.new(20, 10, 2), true, f.Camera.CFrame.Position - Vector3.zAxis * 20, f.Models
				for _ = 1, 8 do
					f.Tick(0.1)
				end
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				expect(target:GetAttribute("Captured")).to.equal(false)
			end)
		end)
		it("blocks shot snapshots and facing while the authoritative daze mirror is active", function()
			fixture(function(f)
				prepare(f)
				local before = f.Root.CFrame
				f.Player.Phase10DazeEnd = workspace:GetServerTimeNow() + 3
				expect(f.Controller:GetShotSnapshot(false)).to.equal(nil)
				expect(f.Controller:GetShotSnapshot(true)).to.equal(nil)
				expect(f.Root.CFrame).to.equal(before)
				f.Player.Phase10DazeEnd = nil
				f.Controller:Refresh()
				expect(f.Controller:IsActive()).to.equal(true)
			end)
		end)
		it("reads exact cargo intent from the current first crosshair hit without an assist pull", function()
			fixture(function(f)
				prepare(f)
				f.Target("nearby-wild", Vector3.new(3, 0, -30))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("nearby-wild")
				local cargo = Instance.new("Model")
				cargo.Parent = f.Models
				cargo:SetAttribute("Phase10TargetKind", "Cargo")
				cargo:SetAttribute("ItemId", "fresh-A")
				cargo:SetAttribute("Phase10CartId", "cart-B")
				cargo:SetAttribute("OwnerUserId", 321)
				local body = Instance.new("Part")
				body.Name, body.Parent = "Body", cargo
				local ownCart = Instance.new("Model")
				ownCart.Parent = f.Models
				local seenParams
				f.World.Raycast = function(_, _, _, params)
					seenParams = params
					return { Instance = body }
				end
				local target = f.Controller:GetCrosshairTarget(ownCart)
				expect(target.ItemId).to.equal("fresh-A")
				expect(target.CartId).to.equal("cart-B")
				expect(target.PlayerUserId).to.equal(321)
				expect(table.find(seenParams.FilterDescendantsInstances, ownCart) ~= nil).to.equal(true)
				expect(table.find(seenParams.FilterDescendantsInstances, f.Character) ~= nil).to.equal(true)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				expect(f.Tick(0.1)).to.equal(Vector2.zero)
				cargo:SetAttribute("ItemId", "fresh-replacement")
				expect(f.Controller:GetCrosshairTarget(ownCart).ItemId).to.equal("fresh-replacement")
				f.World.Raycast = function()
					return { Instance = f.Root }
				end
				expect(f.Controller:GetCrosshairTarget(ownCart)).to.equal(nil)
			end)
		end)
		it("requires a live muzzle before the held-weapon predicate becomes ready", function()
			fixture(function(f)
				f.Muzzle.Parent = nil
				expect(Aim.GetHeldLauncher(f.Character)).to.equal(nil)
				f.Muzzle.Parent = f.Tool.Handle
				expect(Aim.GetHeldLauncher(f.Character)).to.equal(f.Tool)
			end)
		end)
		it("tracks an unobstructed hollow body centre but still rejects foreign cover", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("hollow-centre", Vector3.new(3, 0, -30))
				f.World.Raycast = function()
					return nil
				end -- Mesh opening at the actual centre.
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("hollow-centre")
				expect(f.Tick(1 / 60).Magnitude > 0).to.equal(true)
				f.World.Raycast = function()
					return { Instance = f.Root }
				end
				expect(f.Tick(1 / 60).Magnitude).to.equal(0)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				expect(target.Parent).to.equal(f.Models)
			end)
		end)
		it("requires real held launcher, not a backpack weapon or arbitrary tool", function()
			fixture(function(f)
				f.Tool.Parent = f.Models
				prepare(f)
				expect(f.Controller:IsActive()).to.equal(false)
				f.Tool.Parent = f.Character
				f.Controller:Refresh()
				expect(f.Controller:IsActive()).to.equal(true)
				f.Tool:SetAttribute("BrainrotSleepLauncher", false)
				f.Controller:Update()
				expect(f.Controller:IsActive()).to.equal(false)
			end)
		end)
		it("waits for concurrent dwell/idle grace then follows with lag, not a snap", function()
			fixture(function(f)
				prepare(f)
				f.Target("awake", Vector3.new(4, 0, -40))
				expect(f.Tick(0.1)).to.equal(Vector2.zero)
				expect(f.Tick(0.1)).to.equal(Vector2.zero)
				local before = f.Camera.CFrame
				local delta = f.Tick(0.1, nil, true)
				expect(delta.X > 0).to.equal(true)
				expect(delta.Magnitude < math.rad(5.7)).to.equal(true)
				expect(f.Camera.CFrame.Position).to.equal(before.Position)
				local ray = f.Controller:GetAimRay(false)
				assert(
					ray and ray.Direction:Dot(f.Camera.CFrame.LookVector) > 0.99999,
					"Shot must use the partially tracked rendered view"
				)
				expect(f.Root.CFrame.LookVector:Dot(Vector3.new(ray.Direction.X, 0, ray.Direction.Z).Unit) > 0.99999).to.equal(
					true
				)
			end)
		end)
		it("snapshots the visible farther lock instead of a nearer non-locked target", function()
			fixture(function(f)
				prepare(f)
				local locked = f.Target("locked-farther", Vector3.new(1.5, 0, -30))
				f.Target("nearest-not-locked", Vector3.new(2.5, 0, -8))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("locked-farther")
				local snapshot = assert(f.Controller:GetShotSnapshot(false))
				expect(snapshot.Mode).to.equal("ASSIST_LOCK")
				expect(snapshot.TargetId).to.equal("locked-farther")
				expect(snapshot.TargetKind).to.equal("Brainrot")
				local intended = (locked.Body.Position - snapshot.ShotRay.Origin).Unit
				expect(snapshot.ShotRay.Direction:Dot(intended) > 0.99999).to.equal(true)
			end)
		end)
		it("uses the unassisted centre ray when no visible lock exists", function()
			fixture(function(f)
				prepare(f)
				f.Target("left", Vector3.new(-20, 0, -30))
				f.Target("right", Vector3.new(20, 0, -30))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				local snapshot = assert(f.Controller:GetShotSnapshot(false))
				expect(snapshot.Mode).to.equal("CROSSHAIR_FREE")
				expect(snapshot.TargetId).to.equal(nil)
				expect(snapshot.ShotRay.Direction:Dot(snapshot.CrosshairRay.Direction) > 0.99999).to.equal(true)
			end)
		end)
		it("falls back to the current crosshair when the displayed lock becomes stale", function()
			fixture(function(f)
				prepare(f)
				local stale = f.Target("stale-lock", Vector3.new(2, 0, -30))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("stale-lock")
				stale.Parent = nil
				local snapshot = assert(f.Controller:GetShotSnapshot(false))
				expect(snapshot.Mode).to.equal("CROSSHAIR_FREE")
				expect(snapshot.TargetId).to.equal(nil)
			end)
		end)
		it("uses the newly displayed target after an assist-lock switch", function()
			fixture(function(f)
				prepare(f)
				local first = f.Target("first-lock", Vector3.new(2, 0, -30))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("first-lock")
				first:SetAttribute("Captured", true)
				first:SetAttribute("BrainrotSleepUntil", nil)
				f.Target("second-lock", Vector3.new(-2, 0, -30))
				f.Tick(1 / 60)
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("second-lock")
				local snapshot = assert(f.Controller:GetShotSnapshot(false))
				expect(snapshot.Mode).to.equal("ASSIST_LOCK")
				expect(snapshot.TargetId).to.equal("second-lock")
			end)
		end)
		it("publishes only the selected target and clears focus when it becomes ineligible", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("focus-target", Vector3.new(4, 0, -40))
				acquire(f)
				expect(f.FocusCalls[#f.FocusCalls]).to.equal(target)
				local callCount = #f.FocusCalls
				f.Tick(1 / 60)
				expect(#f.FocusCalls).to.equal(callCount)
				target:SetAttribute("Captured", true)
				f.Tick(1 / 60)
				expect(f.FocusCalls[#f.FocusCalls]).to.equal(false)
			end)
		end)
		it("drops concealed assistance immediately and reacquires only after reveal", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("camouflage-target", Vector3.new(4, 0, -40))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("camouflage-target")

				f.SetAssistEligible(target, false)
				expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				expect(f.FocusCalls[#f.FocusCalls]).to.equal(false)
				for _ = 1, 5 do
					expect(f.Tick(0.1)).to.equal(Vector2.zero)
				end

				f.SetAssistEligible(target, true)
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("camouflage-target")
			end)
		end)
		it("scores temporary decoys as distinct candidates without focusing a brainrot tag", function()
			fixture(function(f)
				prepare(f)
				f.Target("real-owner", Vector3.new(6, 0, -40))
				local decoy = f.Decoy("D:encounter:1", Vector3.new(2, 0, -40))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("D:encounter:1")
				expect(f.Tick(1 / 60).X > 0).to.equal(true)
				expect(f.FocusCalls[#f.FocusCalls]).never.to.equal(decoy)
			end)
		end)
		it("releases an existing real lock once when a split encounter starts", function()
			fixture(function(f)
				prepare(f)
				local real = f.Target("split-owner", Vector3.new(4, 0, -40))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("split-owner")
				f.SetAimResetToken(real, "encounter-1")
				expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				expect(f.FocusCalls[#f.FocusCalls]).to.equal(false)
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("split-owner")
			end)
		end)
		it("clears a removed decoy lock without silently retargeting its owner", function()
			fixture(function(f)
				prepare(f)
				f.Target("owner-behind", Vector3.new(6, 0, -40))
				local decoy = f.Decoy("D:encounter:2", Vector3.new(2, 0, -40))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("D:encounter:2")
				decoy:Destroy()
				expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
			end)
		end)
		it("small manual look takes over unchanged; looking away never restores the old heading", function()
			fixture(function(f)
				prepare(f)
				f.Target("awake", Vector3.new(4, 0, -40))
				acquire(f)
				local manual = Vector2.new(0.00001, -0.00002)
				expect(f.Tick(1 / 60, manual, true)).to.equal(manual)
				expect(f.Tick(0.1)).to.equal(Vector2.zero)
				f.Camera.CFrame *= CFrame.Angles(0, math.pi / 2, 0)
				local before = f.Camera.CFrame
				expect(f.Tick(0.4, nil, true)).to.equal(Vector2.zero)
				expect((f.Camera.CFrame.LookVector - before.LookVector).Magnitude < 1e-6).to.equal(true)
				expect(f.Camera.CFrame.Position).to.equal(before.Position)
			end)
		end)
		it("held stick rotation wins every frame while movement alone does not cancel", function()
			fixture(function(f)
				prepare(f)
				f.Target("awake", Vector3.new(4, 0, -40))
				for _ = 1, 60 do
					local held = Vector2.new(0.005, 0)
					expect(f.Tick(1 / 60, held)).to.equal(held)
				end
				acquire(f)
				f.Root.Position += Vector3.xAxis
				f.Camera.CFrame += Vector3.xAxis
				expect(f.Tick(1 / 60).X > 0).to.equal(true)
			end)
		end)
		it("retains a target over a crossing neighbour and releases outside 16 degrees", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("first", Vector3.new(4, 0, -40))
				local neighbour = f.Target("second", Vector3.new(-6, 0, -40))
				acquire(f)
				neighbour.Body.Position = f.Camera.CFrame.Position + Vector3.new(-1, 0, -40)
				target.Body.Position = f.Camera.CFrame.Position + Vector3.new(10, 0, -40)
				expect(f.Tick(0.1).X > 0).to.equal(true)
				target.Body.Position = f.Camera.CFrame.Position + Vector3.new(20, 0, -40)
				expect(f.Tick(0.1)).to.equal(Vector2.zero)
			end)
		end)
		it("releases and reevaluates assistance when the resolved weapon cone narrows", function()
			fixture(function(f)
				prepare(f)
				f.Target("between-cones", Vector3.new(5.6, 0, -40))
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal("between-cones")
				local current = f.Controller:GetWeaponProfile()
				local narrow = table.clone(current)
				narrow.weaponId = "TEST_NARROW"
				narrow.definitionRevision = 1
				narrow.assistAcquireHalfAngleRadians = math.rad(7)
				narrow.assistRetainHalfAngleRadians = math.rad(12)
				expect(WeaponStats.IsReady(narrow)).to.equal(true)
				expect(f.Controller:SetWeaponProfile(narrow)).to.equal(true)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
				acquire(f)
				expect(f.Controller:GetTrackingId()).to.equal(nil)
			end)
		end)
		for _, reason in { "sleep", "removed", "range", "wall" } do
			it("immediately releases for " .. reason, function()
				fixture(function(f)
					prepare(f)
					local target = f.Target("awake", Vector3.new(4, 0, -40))
					acquire(f)
					if reason == "sleep" then
						target:SetAttribute("Captured", true)
					elseif reason == "removed" then
						target.Parent = f.Models.Parent
					elseif reason == "range" then
						target.Body.Position -= Vector3.zAxis * 80
					else
						local wall = Instance.new("Part")
						wall.Size, wall.Anchored, wall.Position, wall.Parent =
							Vector3.new(30, 20, 2), true, f.Camera.CFrame.Position - Vector3.zAxis * 20, f.Models
					end
					expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				end)
			end)
		end
		it("clamps an abnormal hitch independently of manual speed", function()
			fixture(function(f)
				prepare(f)
				local target = f.Target("awake", Vector3.new(4, 0, -40))
				acquire(f)
				target.Body.Position = f.Camera.CFrame.Position + Vector3.new(10, 0, -40)
				expect(f.Tick(2).Magnitude <= math.rad(40) / 15 + 1e-6).to.equal(true)
				local manual = Vector2.new(1, 0.2)
				expect(f.Tick(2, manual)).to.equal(manual)
			end)
		end)
		it("muzzle-side cover prevents acquisition even when the camera sees the body", function()
			fixture(function(f)
				prepare(f)
				f.Target("awake", Vector3.new(4, 0, -40))
				local wall = Instance.new("Part")
				wall.Size, wall.Anchored = Vector3.new(0.5, 4, 0.5), true
				wall.Position = f.Root.Position + Vector3.new(0.714, 0, -5)
				wall.Parent = f.Models
				acquire(f)
				expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				wall:Destroy()
				acquire(f)
				expect(f.Tick(1 / 60).X > 0).to.equal(true)
			end)
		end)
		it("starts outside the 10-degree acquisition cone without pulling and preserves a later input owner", function()
			fixture(function(f)
				prepare(f)
				f.Target("outside", Vector3.new(9, 0, -40))
				acquire(f)
				expect(f.Tick(1 / 60)).to.equal(Vector2.zero)
				local later = function()
					return Vector2.zero
				end
				f.Adapter.getRotation = later
				f.Controller:Update()
				expect(f.Controller:IsActive()).to.equal(false)
				expect(f.Adapter.getRotation).to.equal(later)
				-- Restore the fixture's own adapter so its teardown can verify ownership.
				f.Adapter.getRotation = f.OriginalRotation
			end)
		end)
		it("has comparable following at 30, 60 and 120 Hz", function()
			local angles = {}
			for _, hz in { 30, 60, 120 } do
				fixture(function(f)
					prepare(f)
					f.Target("awake", Vector3.new(4, 0, -40))
					for _ = 1, hz do
						f.Tick(1 / hz, nil, true)
					end
					table.insert(angles, math.acos(math.clamp(f.Camera.CFrame.LookVector:Dot(-Vector3.zAxis), -1, 1)))
				end)
			end
			for _, angle in angles do
				expect(math.abs(angle - angles[1]) < math.rad(0.4)).to.equal(true)
			end
		end)
	end)

	describe("A2 one current aim snapshot", function()
		it("immediate turns face the exact outgoing pitched centre ray without changing position", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				for _, heading in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
					for _, pitch in { -0.6, 0.6 } do
						local position = f.Root.Position
						f.Camera.CFrame = CFrame.new(position + Vector3.new(1.75, 2, 11))
							* CFrame.Angles(0, heading, 0)
							* CFrame.Angles(pitch, 0, 0)
						local ray = f.Controller:GetAimRay(false)
						assert(ray, "Eligible on-foot shot must have a current ray")
						local horizontal = Vector3.new(ray.Direction.X, 0, ray.Direction.Z).Unit
						expect(f.Root.CFrame.LookVector:Dot(horizontal) > 0.9999).to.equal(true)
						expect(ray.Direction:Dot(f.Camera.CFrame.LookVector) > 0.9999).to.equal(true)
						expect(math.abs(ray.Direction.Magnitude - 1) < 0.0001).to.equal(true)
						expect(ray.Direction.Y * pitch > 0).to.equal(true)
						expect(f.Root.Position).to.equal(position)
						expect(f.Root.CFrame.UpVector).to.equal(Vector3.yAxis)
					end
				end
			end)
		end)
		it("returns mounted aim without writing the seated root or claiming the cart camera", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				f.Humanoid.Sit = true
				f.Camera.CameraType = Enum.CameraType.Scriptable
				f.Camera.CFrame = CFrame.Angles(0.4, 1.5, 0)
				local before = f.Root.CFrame
				local ray = f.Controller:GetAimRay(true)
				assert(ray, "Mounted context must use current cart camera aim")
				expect(f.Controller:IsActive()).to.equal(false)
				expect(f.Root.CFrame).to.equal(before)
				expect(f.Camera.CameraType).to.equal(Enum.CameraType.Scriptable)
				expect(ray.Direction:Dot(f.Camera.CFrame.LookVector) > 0.9999).to.equal(true)
			end)
		end)
		it("does not reuse aim after carry, unequip or UI suspension", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				assert(f.Controller:GetAimRay(false))
				f.Player.CarriedItemId = "same-item"
				expect(f.Controller:GetAimRay(false)).to.equal(nil)
				f.Player.CarriedItemId = nil
				f.Controller:Refresh()
				assert(f.Controller:GetAimRay(false))
				f.Controller:SetCharacter(nil)
				expect(f.Controller:GetAimRay(false)).to.equal(nil)
				f.Gui.MenuIsOpen = true
				expect(f.Controller:GetAimRay(true)).to.equal(nil)
			end)
		end)
	end)

	describe("on-foot hunting adapter", function()
		it("uses default camera, shoulder framing and one post-camera binding", function()
			fixture(function(f)
				local before = f.Camera.CFrame
				f.Controller:SetCharacter(f.Character)
				expect(f.Controller:IsActive()).to.equal(true)
				expect(f.Humanoid.AutoRotate).to.equal(false)
				expect(f.Humanoid.CameraOffset).to.equal(Vector3.new(1.75, 0.5, 0))
				expect(f.Player.CameraMinZoomDistance).to.equal(11)
				expect(f.Player.CameraMaxZoomDistance).to.equal(11)
				expect(f.Camera.CameraType).to.equal(Enum.CameraType.Custom)
				expect(f.Camera.CFrame).to.equal(before)
				expect(f.Run.Priority).to.equal(Enum.RenderPriority.Camera.Value + 1)
				expect(f.Input.MouseBehavior).to.equal(Enum.MouseBehavior.LockCenter)
			end)
		end)
		it("follows current camera yaw only, preserving position and movement settings", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				local position, speed, jump, anchored =
					f.Root.Position, f.Humanoid.WalkSpeed, f.Humanoid.JumpPower, f.Root.Anchored
				f.Camera.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0.8, 0))
				f.Controller:Update()
				expect((f.Root.CFrame.LookVector - Vector3.xAxis).Magnitude < 0.0001).to.equal(true)
				expect(f.Root.Position).to.equal(position)
				expect(f.Root.CFrame.UpVector).to.equal(Vector3.yAxis)
				expect(f.Humanoid.WalkSpeed).to.equal(speed)
				expect(f.Humanoid.JumpPower).to.equal(jump)
				expect(f.Root.Anchored).to.equal(anchored)
				expect(f.Humanoid.PlatformStand).to.equal(false)
			end)
		end)
		it("keeps the last yaw for near-vertical aim", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				f.Controller:Update()
				local before = f.Root.CFrame
				f.Camera.CFrame = CFrame.Angles(math.pi / 2, 0, 0)
				f.Controller:Update()
				expect(f.Root.CFrame).to.equal(before)
			end)
		end)
		for _, reason in { "Sit", "Carry", "Death", "Replacement", "CartCamera" } do
			it("rechecks " .. reason .. " before writing the root", function()
				fixture(function(f)
					f.Controller:SetCharacter(f.Character)
					local before = f.Root.CFrame
					f.Camera.CFrame = CFrame.Angles(0, 1.3, 0)
					if reason == "Sit" then
						f.Humanoid.Sit = true
					elseif reason == "Carry" then
						f.Player.CarriedItemId = "same-individual"
					elseif reason == "Death" then
						f.Humanoid.Health = 0
					elseif reason == "Replacement" then
						f.Player.Character = nil
					else
						f.Camera.CameraType = Enum.CameraType.Scriptable
					end
					f.Controller:Update()
					expect(f.Controller:IsActive()).to.equal(false)
					expect(f.Root.CFrame).to.equal(before)
				end)
			end)
		end
		for _, reason in { "Menu", "Text", "Focus", "Selection" } do
			it("suspends and resumes for " .. reason, function()
				fixture(function(f)
					f.Controller:SetCharacter(f.Character)
					local function set(on)
						if reason == "Menu" then
							f.Gui.MenuIsOpen = on
							f.Gui.Signals.MenuIsOpen:Fire()
						elseif reason == "Text" then
							f.Input.TextBox = if on then {} else nil
							(if on then f.Input.TextBoxFocused else f.Input.TextBoxFocusReleased):Fire()
						elseif reason == "Focus" then
							(if on then f.Input.WindowFocusReleased else f.Input.WindowFocused):Fire()
						else
							f.Gui.SelectedObject = if on then {} else nil
							f.Gui.Signals.SelectedObject:Fire()
						end
					end
					set(true)
					expect(f.Controller:IsInputSuspended()).to.equal(true)
					expect(f.Controller:IsActive()).to.equal(false)
					expect(f.Input.MouseBehavior).to.equal(Enum.MouseBehavior.Default)
					set(false)
					expect(f.Controller:IsActive()).to.equal(true)
				end)
			end)
		end
		it("restores actual saved settings across repeated toggles", function()
			fixture(function(f)
				f.Player.CameraMinZoomDistance, f.Player.CameraMaxZoomDistance = 20, 90
				f.Humanoid.CameraOffset = Vector3.new(0, 1, 0)
				f.Input.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				for _ = 1, 20 do
					f.Controller:SetCharacter(f.Character)
					f.Controller:SetCharacter(f.Character)
					f.Controller:SetCharacter(nil)
					expect(f.Humanoid.AutoRotate).to.equal(true)
					expect(f.Humanoid.CameraOffset).to.equal(Vector3.new(0, 1, 0))
					expect(f.Player.CameraMinZoomDistance).to.equal(20)
					expect(f.Player.CameraMaxZoomDistance).to.equal(90)
					expect(f.Input.MouseBehavior).to.equal(Enum.MouseBehavior.LockCurrentPosition)
					expect(f.Input.MouseIconEnabled).to.equal(true)
				end
			end)
		end)
		it("does not overwrite a later camera/facing owner", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				f.Humanoid.CameraOffset = Vector3.new(9, 2, 1)
				f.Player.CameraMaxZoomDistance = 35
				f.Controller:Update()
				f.Controller:Refresh()
				expect(f.Controller:IsActive()).to.equal(false)
				expect(f.Humanoid.CameraOffset).to.equal(Vector3.new(9, 2, 1))
				expect(f.Player.CameraMaxZoomDistance).to.equal(35)
			end)
		end)
		it("hands a replaced camera back to its owner and resumes only a valid subject", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				local replacement = Instance.new("Camera")
				replacement.CameraType = Enum.CameraType.Scriptable
				f.World.CurrentCamera = replacement
				f.World.Signals.CurrentCamera:Fire()
				expect(f.Controller:IsActive()).to.equal(false)
				expect(replacement.CameraType).to.equal(Enum.CameraType.Scriptable)
				f.World.CurrentCamera = f.Camera
				f.World.Signals.CurrentCamera:Fire()
				expect(f.Controller:IsActive()).to.equal(true)
				replacement:Destroy()
			end)
		end)
		it("supports clearing carry and dismounting without another equip toggle", function()
			fixture(function(f)
				f.Controller:SetCharacter(f.Character)
				f.Humanoid.Sit = true
				f.Controller:Update()
				f.Humanoid.Sit = false
				f.Controller:Refresh()
				expect(f.Controller:IsActive()).to.equal(true)
				f.Player.CarriedItemId = "unchanged-record"
				f.Controller:Update()
				expect(f.Player.CarriedItemId).to.equal("unchanged-record")
				f.Player.CarriedItemId = nil
				f.Controller:Refresh()
				expect(f.Controller:IsActive()).to.equal(true)
			end)
		end)
		for _, device in { Enum.PreferredInput.Touch, Enum.PreferredInput.Gamepad } do
			it("does not require mouse lock for " .. device.Name, function()
				fixture(function(f)
					f.Input.PreferredInput = device
					f.Controller:SetCharacter(f.Character)
					f.Controller:Update()
					expect(f.Controller:IsActive()).to.equal(true)
					expect(f.Input.MouseBehavior).to.equal(Enum.MouseBehavior.Default)
					expect(f.Input.MouseIconEnabled).to.equal(true)
				end)
			end)
		end
	end)
end
