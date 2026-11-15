--!strict
-- Current driver's sole pre-physics writer. Input is applied locally, before
-- its bounded telemetry packet; there is no per-turn server acknowledgement.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Gui = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")
local Config = require(RS.Shared.Config.CartHandlingConfig)
local Rig = require(RS.Shared.Utility.CartArcadeRig)
local Profiles = require(RS.Shared.Utility.CartMovementProfileResolver)
local Names = require(RS.Shared.Constants.RemoteNames)
local Input = require(script.Parent.CartInputController)
local LocalCart = require(script.Parent.Parent.State.LocalCartState)
local Reset = require(script.Parent.Parent.State.LocalCartResetState)
local Policy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local player = Players.LocalPlayer
local Controller = {}
local cart: Model? = nil
local physics: any = nil
local parameters: any = nil
local remote: RemoteEvent? = nil
local connections: { RBXScriptConnection } = {}
local cartConnections: { RBXScriptConnection } = {}
local started = false
local session, sequence = 0, 0
-- Wall-clock pacing: PreSimulation dt is clamped, so summing it under-counts
-- real time at low frame rates and starves the server lease.
local lastPacketAt, lastResumeAt = 0, 0
local stalledSince: number? = nil
local lastStallReport = 0
local mode = "Parked"
local diagnosticElapsed = 0
local diagnostic = { State = "Parked", ActiveMovementWriters = 0 }
local function disconnect(list: { RBXScriptConnection })
	for _, c in ipairs(list) do
		c:Disconnect()
	end
	table.clear(list)
end
local function detach()
	-- Only suspend while this client is still approved. A late old-generation
	-- teardown cannot disable the next driver's server-owned motor.
	if
		physics
		and cart
		and cart.Parent
		and cart:GetAttribute("ActiveDriverUserId") == player.UserId
		and cart:GetAttribute("CartDriveSession") == session
	then
		Rig.Suspend(physics)
	end
	disconnect(cartConnections)
	physics, parameters, cart = nil, nil, nil
	session, sequence, lastPacketAt = 0, 0, 0
	mode = "Parked"
	Input.ClearMovementInput()
end
local function refresh()
	if not cart or not cart.Parent then
		return
	end
	local valid = cart:GetAttribute("AssemblyValidationState") == "Valid"
	local nextSession = cart:GetAttribute("CartDriveSession")
	if not valid or type(nextSession) ~= "number" then
		physics = nil
		return
	end
	local constraints = cart:FindFirstChild("Constraints")
	if not constraints or not constraints:FindFirstChild("ArcadeDrive") or not cart:FindFirstChild("ArcadeHull") then
		physics = nil
		return
	end
	local ok, profile = pcall(Profiles.ResolveForCart, cart)
	if not ok then
		physics = nil
		warn("Cart arcade profile unavailable: " .. tostring(profile))
		return
	end
	parameters = Rig.Parameters(profile)
	physics = Rig.CreateState(cart, player.Character)
	if nextSession ~= session then
		session, sequence = nextSession, 0
	end
	lastPacketAt = 0
	Input.ClearMovementInput()
	mode = "Entering"
end
local function bind(nextCart: Model?)
	if nextCart ~= cart then
		detach()
		cart = nextCart
		if not cart then
			return
		end
		local expected = cart
		for _, attribute in ipairs({ "CartDriveSession", "PerformanceRevision", "CartId", "AssemblyValidationState" }) do
			table.insert(
				cartConnections,
				cart:GetAttributeChangedSignal(attribute):Connect(function()
					if cart == expected then
						refresh()
					end
				end)
			)
		end
		table.insert(
			cartConnections,
			cart.DescendantAdded:Connect(function(x)
				if
					cart == expected
					and (x.Name == "ArcadeDrive" or x.Name == "ArcadeOrientation" or x.Name == "ArcadeHull")
				then
					refresh()
				end
			end)
		)
		table.insert(
			cartConnections,
			cart.Destroying:Connect(function()
				if cart == expected then
					detach()
				end
			end)
		)
	end
	refresh()
end
local function step(dt: number)
	local model = cart
	if not model or not physics or not parameters or model.Parent == nil then
		return
	end
	if
		not LocalCart.IsAuthorizedDriver()
		or model:GetAttribute("CartDriveSession") ~= session
		or model:GetAttribute("ActiveDriverUserId") ~= player.UserId
	then
		diagnostic = { State = "Parked", ActiveMovementWriters = 0 }
		-- Still seated in our own cart with no driver: the server dropped the
		-- lease (a long frame hitch). Ask it to re-check the seat; it validates
		-- ownership and eligibility itself before granting anything.
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		local now = os.clock()
		if
			remote
			and seat
			and seat == model:FindFirstChild("DriverSeat")
			and model:GetAttribute("ActiveDriverUserId") == 0
			and now - lastResumeAt >= 1
		then
			lastResumeAt = now
			remote:FireServer({ cart = model, resume = true })
		end
		return
	end
	local tool = player.Character and player.Character:FindFirstChildWhichIsA("Tool")
	-- Owner decision (10 Nov 2026): the mounted aim view no longer pauses
	-- driving. Only an equipped launcher tool does, matching the server.
	local hunting = tool
		and (
			tool.Name == "Hunting"
			or tool.Name == "SleepLauncher"
			or tool:GetAttribute("BrainrotSleepLauncher") == true
		)
	local reset = Reset.IsActiveFor(model) or model:GetAttribute("ResetActive") == true
	local dazed = Policy.IsDazed(player)
	local paused = reset
		or dazed
		or hunting == true
		or Policy.IsBlocked(player, Gui, UIS)
		or not Input.IsWindowFocused()
	local nextMode = if reset
		then "Reset"
		elseif dazed then "Dazed"
		elseif hunting then "MountedHunting"
		elseif paused then "Paused"
		else "Driving"
	if nextMode ~= mode and not (mode == "Entering" and nextMode == "Driving") then
		-- Always visible: a paused drive is otherwise indistinguishable from a fault.
		print(
			("[CartDrive] %s -> %s reset=%s dazed=%s tool=%s menu=%s focused=%s"):format(
				mode,
				nextMode,
				tostring(reset),
				tostring(dazed),
				tostring(tool),
				tostring(Policy.IsMenuOpen(player, Gui, UIS)),
				tostring(Input.IsWindowFocused())
			)
		)
	end
	if nextMode ~= mode or dt > Config.MaximumFrameGap then
		Input.ClearMovementInput()
		lastPacketAt = 0
	end
	mode = nextMode
	local direction, magnitude = Input.GetWorldIntent()
	if paused or dt > Config.MaximumFrameGap then
		direction, magnitude = Vector3.zero, 0
	end
	local result = nil
	if reset or dazed then
		Rig.Suspend(physics)
	else
		-- Villager tag (server-decided): a short top-speed cap. Attributes are only ever
		-- written while FeatureFlags.VillagerGuardsEnabled is on.
		local stepParameters = parameters
		local slowUntil = model:GetAttribute("VillagerSlowUntil")
		if type(slowUntil) == "number" and workspace:GetServerTimeNow() < slowUntil then
			local factor = model:GetAttribute("VillagerSlowFactor")
			if type(factor) == "number" and factor > 0 and factor < 1 then
				stepParameters = table.clone(parameters)
				stepParameters.speed *= factor
			end
		end
		result = Rig.Step(physics, stepParameters, direction, magnitude, dt)
	end
	local now = os.clock()
	if remote and now - lastPacketAt >= 1 / Config.IntentHz then
		lastPacketAt = now
		sequence += 1
		remote:FireServer({
			cart = model,
			session = session,
			sequence = sequence,
			direction = direction,
			magnitude = magnitude,
			braking = not result or result.braking,
			paused = paused,
		})
	end
	-- Report a held throttle that produces no motion, at most every 3 s.
	local keyHeld = UIS:IsKeyDown(Enum.KeyCode.W)
		or UIS:IsKeyDown(Enum.KeyCode.A)
		or UIS:IsKeyDown(Enum.KeyCode.S)
		or UIS:IsKeyDown(Enum.KeyCode.D)
	if (magnitude > 0.5 or keyHeld) and not paused and physics.root.AssemblyLinearVelocity.Magnitude < 2 then
		stalledSince = stalledSince or now
		if now - stalledSince > 1 and now - lastStallReport > 3 then
			lastStallReport = now
			local wall = physics.wall
			print(
				("[CartDrive] Throttle held but not moving: input=%.2f keyHeld=%s grounded=%s wall=%s reversing=%s goal=%.0f force=%.0f support=%s pos=%s"):format(
					magnitude,
					tostring(keyHeld),
					tostring(result and result.grounded),
					if wall then tostring(wall) else "none",
					tostring(physics.reversing),
					result and result.goal or 0,
					result and result.force.Magnitude or 0,
					if physics.support then physics.support:GetFullName() else "none",
					tostring(physics.root.Position)
				)
			)
		end
	else
		stalledSince = nil
	end
	diagnosticElapsed += dt
	if diagnosticElapsed < 0.2 then
		return
	end
	diagnosticElapsed = 0
	diagnostic = {
		State = if result and not result.grounded then "Airborne" else mode,
		Session = session,
		DesiredSpeed = result and result.goal or 0,
		ActualSpeed = physics.root.AssemblyLinearVelocity.Magnitude,
		Grounded = result and result.grounded or false,
		Contact = physics.wall ~= nil,
		Mass = physics.mass or 0,
		FrameInterval = dt,
		ActiveMovementWriters = if reset or dazed then 0 else 1,
		InputMagnitude = magnitude,
		Force = result and result.force.Magnitude or 0,
	}
end
function Controller.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		-- The server creates this remote late in boot, after world and terrain
		-- setup. Giving up here leaves the driver with no lease packets, so the
		-- server revokes control one second after every seat entry.
		while started and not remote do
			local folder = RS:WaitForChild("Remotes", 5)
			local value = folder and folder:WaitForChild(Names.CartDriveIntent, 5)
			if started and value and value:IsA("RemoteEvent") then
				remote = value
			elseif value then
				task.wait(5) -- wrong class: keep the retry paced
			end
		end
	end)
	table.insert(
		connections,
		LocalCart.Changed:Connect(function(nextCart)
			bind(nextCart)
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			Input.ClearMovementInput()
		end)
	)
	table.insert(connections, Run.PreSimulation:Connect(step))
	bind(LocalCart.GetCart())
end
function Controller.Stop()
	started = false
	detach()
	disconnect(connections)
	remote = nil
end
function Controller.GetDiagnostics(): any
	return table.clone(diagnostic)
end
-- Read-only presentation access; no controller parameter or force is changed.
function Controller.GetPresentationSupport(model)
	if cart ~= model or not physics then
		return nil, nil
	end
	return physics.grounded, physics.normal
end
return Controller
