--!strict
-- Camp Rework, Part B: client-side stall presentation (CampReworkV1Enabled). Presentation only; every
-- number comes from the server snapshot or replicated attributes.
--   Weapons  hunting racks = your next upgrades (WeaponDisplays, side-on on the pegs), back wall = your
--            three best owned weapons, medal pedestals = the Won specials (greyed until earned).
--   Carts    windmill spins, turntable turns the featured cart (your next cart, 65% prop), boiler steams.
--   Sell     coin burst + ka-ching on every completed sale.
--   Training speedometer needle (225° − 270° × level/25, tweened), live "LV n", lamp blinks while you
--            train, rollers spin while you train (faster on better rollers), "Bay busy" for others.
-- All motion runs on the shared ≤10 Hz CampAnimationScheduler with off-screen/150-stud culling.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CampFlags = require(ReplicatedStorage.Shared.Config.CampReworkFlags)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local WeaponTiersV2 = require(ReplicatedStorage.Shared.Config.WeaponTiersV2)
local Phase13 = require(ReplicatedStorage.Shared.Config.Phase13)
local TrainingConfig = require(ReplicatedStorage.Shared.Config.Training)
local Scheduler = require(script.Parent.Parent.Utility.CampAnimationScheduler)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)

local Controller = {}
local player = Players.LocalPlayer
local started = false
local snapshot: any = nil
local stalls: { [string]: Model } = {}
local props: { [string]: Instance } = {}
local NEEDLE_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GREY = Color3.fromRGB(128, 128, 134)

-- Pure: speedometer needle angle for a Training level (prompt Part B).
function Controller.NeedleDegrees(level: number): number
	local clamped = math.clamp(level, 0, TrainingConfig.MaxLevel)
	return 225 - 270 * (clamped / TrainingConfig.MaxLevel)
end

-- Pure: which ladder weapons fill the hunting racks (cheapest unowned first, up to `count`).
function Controller.RackPicks(owned: { [string]: boolean }, count: number): { string }
	local rows = {}
	for _, row in Weapons.GetAll() do
		if owned[row.id] ~= true and row.price > 0 then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		return if a.price == b.price then a.id < b.id else a.price < b.price
	end)
	local out = {}
	for i = 1, math.min(count, #rows) do
		out[i] = rows[i].id
	end
	return out
end

-- Pure: the three best owned weapons for the back wall (power tier, then price).
function Controller.WallPicks(owned: { [string]: boolean }): { string }
	local rows = {}
	for id, isOwned in owned do
		local d = Weapons.Get(id)
		if isOwned and d then
			local tier = WeaponTiersV2.TierFromWeaponId(id)
			local special = WeaponTiersV2.Specials[id]
			table.insert(rows, { id = id, tier = if special then special.powerTier else (tier or 0), price = d.price })
		end
	end
	table.sort(rows, function(a, b)
		if a.tier ~= b.tier then
			return a.tier > b.tier
		end
		if a.price ~= b.price then
			return a.price > b.price
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(3, #rows) do
		out[i] = rows[i].id
	end
	return out
end

-- Pure: the featured cart is the next cart to buy (cheapest unowned); everything owned -> the best one.
function Controller.FeaturedCart(owned: { [string]: boolean }): string?
	local best, bestOwned = nil, nil
	for _, row in Phase13.CartRows do
		if owned[row.id] ~= true then
			if not best or row.price < best.price then
				best = row
			end
		elseif not bestOwned or row.price > bestOwned.price then
			bestOwned = row
		end
	end
	local pick = best or bestOwned
	return if pick then pick.assetName else nil
end

local function call(payload: any): any
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local request = remotes and remotes:FindFirstChild("Phase13Request")
	if not request then
		return nil
	end
	local ok, result = pcall(function()
		return (request :: RemoteFunction):InvokeServer(payload)
	end)
	return if ok then result else nil
end

local function clearProp(key: string)
	local old = props[key]
	if old then
		old:Destroy()
		props[key] = nil
	end
end

local function staticize(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Seat") or d:IsA("VehicleSeat")
			or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("ClickDetector") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
end

-- Place a WeaponDisplays copy on a slot: display forward (-Z) along the slot's long axis, side-on.
local function placeDisplay(key: string, slot: BasePart, weaponId: string, greyed: boolean)
	clearProp(key)
	local folder = ReplicatedStorage:FindFirstChild("CodeAssets")
	local displays = folder and folder:FindFirstChild("WeaponDisplays")
	local source = displays and displays:FindFirstChild(weaponId)
	if not source or not source:IsA("Model") then
		return
	end
	local model = source:Clone()
	staticize(model)
	-- Size in the display's own frame (X = side, Y = up, Z = forward). The length that lies on the
	-- pegs is the longer of up (bow limbs) and forward (stocks/barrels); the side stays facing out.
	local _, size = model:GetBoundingBox()
	local length = tonumber(slot:GetAttribute("SlotLength")) or 3
	local along = math.max(size.Y, size.Z)
	local turn = if size.Y > size.Z then CFrame.Angles(math.rad(90), 0, 0) else CFrame.new()
	if along > 0 then
		model:ScaleTo(model:GetScale() * (length / along))
	end
	model:PivotTo(slot.CFrame * turn)
	if greyed then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local h, s, v = d.Color:ToHSV()
				d.Color = Color3.fromHSV(h, s * 0.15, math.clamp(v * 0.75, 0.25, 0.75)):Lerp(GREY, 0.35)
				d.Material = Enum.Material.SmoothPlastic
			elseif d:IsA("Beam") or d:IsA("Light") then
				d.Enabled = false
			end
		end
	end
	model.Name = "CampDisplay_" .. weaponId
	model.Parent = slot
	props[key] = model
end

local function slots(stall: Model): { [string]: BasePart }
	local out = {}
	local folder = stall:FindFirstChild("CampSlots")
	if folder then
		for _, s in folder:GetChildren() do
			if s:IsA("BasePart") then
				out[s.Name] = s
			end
		end
	end
	return out
end

local function refreshWeapons()
	local stall = stalls.Weapon
	if not stall or not snapshot then
		return
	end
	local owned = snapshot.ownedWeapons or {}
	local s = slots(stall)
	local rack = Controller.RackPicks(owned, 6)
	for i = 1, 6 do
		local slot = s["RackSlot_" .. i]
		if slot and rack[i] then
			placeDisplay("Rack" .. i, slot, rack[i], false)
		else
			clearProp("Rack" .. i)
		end
	end
	local wall = Controller.WallPicks(owned)
	for i = 1, 3 do
		local slot = s["WallSlot_" .. i]
		if slot and wall[i] then
			placeDisplay("Wall" .. i, slot, wall[i], false)
		else
			clearProp("Wall" .. i)
		end
	end
	local medals = { "WPN_SP_COLLECTORSBOW", "WPN_SP_GETAWAY", "WPN_SP_SECRETHUNTER" }
	for i, id in medals do
		local slot = s["MedalSlot_" .. i]
		if slot then
			placeDisplay("Medal" .. i, slot, id, owned[id] ~= true)
		end
	end
end

-- Brainrots hitched to the featured cart (approved Carts stall design). Client props so they can
-- follow the per-player featured cart; they ride the turntable when they stand on it.
local function placeHitched(stall: Model)
	local folder = ReplicatedStorage:FindFirstChild("CodeAssets")
	folder = folder and folder:FindFirstChild("CampStallProps")
	local source = folder and folder:FindFirstChild("HitchedBrainrots")
	local rotor = stall:FindFirstChild("TurntableRotor")
	local turn = slots(stall).TurntableSlot
	if not source then
		return
	end
	for name, slot in slots(stall) do
		local index = string.match(name, "^HitchSlot_(%d+)$")
		local template = index and source:FindFirstChild("HitchedBrainrot_" .. index)
		local key = "Hitch" .. tostring(index)
		if template and template:IsA("Model") and not props[key] then
			local model = template:Clone()
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				end
			end
			if model.PrimaryPart then
				model.PrimaryPart.Anchored = true
			end
			model:PivotTo(slot.CFrame)
			local onTable = turn ~= nil and rotor ~= nil
				and (Vector3.new(slot.Position.X, 0, slot.Position.Z) - Vector3.new(turn.Position.X, 0, turn.Position.Z)).Magnitude < 6
			model.Parent = if onTable then rotor else slot
			props[key] = model
		end
	end
end

local function refreshCarts()
	local stall = stalls.Cart
	if not stall or not snapshot then
		return
	end
	placeHitched(stall)
	local slot = slots(stall).TurntableSlot
	local rotor = stall:FindFirstChild("TurntableRotor")
	local asset = Controller.FeaturedCart(snapshot.ownedCarts or {})
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local carts = assets and assets:FindFirstChild("Carts")
	local source = carts and asset and carts:FindFirstChild(asset)
	if not slot or not rotor or not source then
		return
	end
	local current = props.FeaturedCart
	if current and current:GetAttribute("AssetName") == asset then
		return
	end
	clearProp("FeaturedCart")
	local model = source:Clone()
	staticize(model)
	if model:IsA("Model") then
		model:ScaleTo(model:GetScale() * (tonumber(slot:GetAttribute("CartScale")) or 0.65))
		local offset = slot:GetAttribute("CartOffset")
		local rotorPivot = (rotor :: Model):GetPivot()
		local base = slot.CFrame * (if typeof(offset) == "CFrame" then offset else CFrame.new())
		-- keep the cart's wheels on the deck: drop it so its lowest point sits on the slot
		model:PivotTo(base)
		local cf, size = model:GetBoundingBox()
		local lift = slot.Position.Y - (cf.Position.Y - size.Y / 2)
		model:PivotTo(base + Vector3.new(0, lift, 0))
		model:SetAttribute("AssetName", asset)
		model:SetAttribute("RotorOffset", rotorPivot:ToObjectSpace(model:GetPivot()))
		model.Name = "CampFeaturedCart"
		model.Parent = rotor
		props.FeaturedCart = model
	end
end

local function refresh()
	snapshot = call({ action = "Snapshot" })
	if type(snapshot) ~= "table" or snapshot.ok ~= true then
		snapshot = nil
		return
	end
	refreshWeapons()
	refreshCarts()
end

-- Windmill / turntable: rotate the assembly about its Pivot's LookVector (stepped at ≤10 Hz).
local function bindSpinner(model: Model)
	local rate = tonumber(model:GetAttribute("CampAnimRate")) or 0
	local base = model:GetPivot()
	local angle = 0
	Scheduler.Register(model, {
		position = function()
			return if model.Parent then base.Position else nil
		end,
		step = function(_now, dt)
			angle = (angle + rate * math.min(dt, 0.25)) % 360
			model:PivotTo(base * CFrame.Angles(0, 0, math.rad(angle)))
		end,
	})
end

local function coinBurst(stall: Model)
	local slot = slots(stall).CoinBurst
	if not slot then
		return
	end
	local emitter = slot:FindFirstChild("CampCoinBurst") :: ParticleEmitter?
	if not emitter then
		local attachment = Instance.new("Attachment")
		attachment.Parent = slot
		local e = Instance.new("ParticleEmitter")
		e.Name = "CampCoinBurst"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 214, 64), Color3.fromRGB(255, 170, 30))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(8, 14)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, -30, 0)
		e.Rate = 0
		e.Enabled = false
		e.LightEmission = 0.4
		e.Parent = attachment
		emitter = e
	end
	local burst = emitter :: ParticleEmitter
	burst:Emit(24)
	AudioCue.Play("E5_crate", { bus = "Rewards", cooldown = 0.3 }) -- ka-ching
end

-- Training stall visuals (data from player attributes the server mirrors: TrainingLevel, TrainingActive,
-- TrainingRoller; prompt attribute BayOccupantUserId).
local function bindTraining(stall: Model)
	local needle = stall:FindFirstChild("SpeedNeedle") :: Model?
	local needleBase = if needle then needle:GetPivot() else nil
	-- The authored needle points at some level already: measure its tip angle in the viewer's frame
	-- (0° = right, counter-clockwise positive; the pivot's LookVector faces the viewer).
	local builtDegrees = 225
	if needle and needleBase then
		local tip, far = nil, -1
		for _, p in needle:GetDescendants() do
			if p:IsA("BasePart") and p ~= needle.PrimaryPart then
				local h = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						local corner = p.CFrame * Vector3.new(h.X * sx, h.Y * sy, 0)
						local d = (corner - needleBase.Position).Magnitude
						if d > far then
							tip, far = corner, d
						end
					end
				end
			end
		end
		if tip then
			local d = tip - needleBase.Position
			local x = d:Dot(-needleBase.RightVector)
			local y = d:Dot(needleBase.UpVector)
			builtDegrees = math.deg(math.atan2(y, x))
		end
	end
	local lamp = nil
	local rollers = {}
	for _, d in stall:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("CampLamp") then
			lamp = d
		elseif d:IsA("BasePart") and d:GetAttribute("CampRoller") then
			table.insert(rollers, { part = d, base = d.CFrame, axis = d:GetAttribute("CampRollerAxis") })
		end
	end
	local lampColor = if lamp then lamp.Color else Color3.new(1, 0, 0)
	local readout: TextLabel? = nil
	for _, d in stall:GetDescendants() do
		if d:IsA("TextLabel") and string.match(d.Text, "^LV") then
			readout = d
		end
	end
	local shownLevel = -1
	local rollerAngle = 0
	local blink = false
	local function applyLevel()
		local level = tonumber(player:GetAttribute("TrainingLevel")) or 0
		if level == shownLevel then
			return
		end
		shownLevel = level
		if readout then
			readout.Text = "LV " .. tostring(level)
		end
		if needle and needleBase then
			-- rotate counter-clockwise (for the viewer) from the authored angle to the level's angle
			local delta = Controller.NeedleDegrees(level) - builtDegrees
			local target = needleBase * CFrame.Angles(0, 0, math.rad(-delta))
			local value = Instance.new("CFrameValue")
			value.Value = needle:GetPivot()
			value.Changed:Connect(function(v)
				if needle.Parent then
					needle:PivotTo(v)
				end
			end)
			local tween = TweenService:Create(value, NEEDLE_TWEEN, { Value = target })
			tween.Completed:Once(function()
				value:Destroy()
			end)
			tween:Play()
		end
	end
	applyLevel()
	player:GetAttributeChangedSignal("TrainingLevel"):Connect(applyLevel)
	local center = stall:GetPivot().Position
	Scheduler.Register(stall, {
		position = function()
			return if stall.Parent then center else nil
		end,
		radius = 150,
		always = true,
		step = function(_now, dt)
			local active = player:GetAttribute("TrainingActive") == true
			if lamp then
				blink = active and not blink
				lamp.Color = if blink then Color3.fromRGB(255, 40, 40) else lampColor:Lerp(Color3.new(0.2, 0, 0), if active then 0.6 else 0)
				lamp.Material = if blink then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
			if active then
				local roller = tostring(player:GetAttribute("TrainingRoller") or "Wooden")
				local speed = TrainingConfig.RollerSpinDegrees[roller] or 360
				rollerAngle = (rollerAngle + speed * math.min(dt, 0.25)) % 360
				for _, r in rollers do
					local axis = if typeof(r.axis) == "Vector3" then r.axis else Vector3.xAxis
					local cf = CFrame.new(r.base.Position) * CFrame.fromAxisAngle(axis, math.rad(rollerAngle)) * r.base.Rotation
					TweenService:Create(r.part, TweenInfo.new(0.1, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
				end
			end
		end,
	})
	-- "Bay busy" for everyone except the trainer (client-local prompt text).
	local function bindPrompt(prompt: ProximityPrompt)
		local function apply()
			local occupant = tonumber(prompt:GetAttribute("BayOccupantUserId")) or 0
			prompt.ActionText = if occupant ~= 0 and occupant ~= player.UserId then "Bay busy" else "Open"
		end
		apply()
		prompt:GetAttributeChangedSignal("BayOccupantUserId"):Connect(apply)
	end
	for _, d in stall:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			bindPrompt(d)
		end
	end
	stall.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			bindPrompt(d)
		end
	end)
end

local function bindStall(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local key = model:GetAttribute("CampCategory")
	if type(key) ~= "string" or stalls[key] == model then
		return
	end
	stalls[key] = model
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("CampAnim") == "Spin" then
			bindSpinner(d)
		end
	end
	if key == "Training" then
		bindTraining(model)
	end
	task.defer(refresh)
end

-- "+1 SPEED LV" toast (UI only, never on the stall) + a small sound.
function Controller.ShowLevelToast(gained: number)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local screen = gui:FindFirstChild("CampTrainingToast") :: ScreenGui?
	if not screen then
		local s = Instance.new("ScreenGui")
		s.Name = "CampTrainingToast"
		s.ResetOnSpawn = false
		s.DisplayOrder = 40
		s.Parent = gui
		screen = s
	end
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.32)
	label.Size = UDim2.fromScale(0.36, 0.08)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 120)
	label.Text = string.format("+%d SPEED LV", gained)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 60, 20)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	label.Parent = screen
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	AudioCue.Play("U6", { bus = "UI", cooldown = 0.2 })
	task.delay(1.6, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.26) })
		fade:Play()
		fade.Completed:Once(function()
			label:Destroy()
		end)
	end)
end

function Controller.Start()
	if started or not CampFlags.CampRework() then
		return
	end
	started = true
	local function watch(services: Instance)
		for _, child in services:GetChildren() do
			bindStall(child)
		end
		services.ChildAdded:Connect(bindStall)
	end
	task.spawn(function()
		local map = Workspace:WaitForChild("MapBlockout", 60)
		local art = map and map:WaitForChild("MapArt", 60)
		local services = art and art:WaitForChild("Services", 60)
		if services then
			watch(services)
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local update = remotes and remotes:WaitForChild("Phase13Update", 30)
	if update and update:IsA("RemoteEvent") then
		update.OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.kind == "Confirmed" then
				task.delay(0.5, refresh)
			end
		end)
	end
	local campEvent = remotes and remotes:WaitForChild("CampReworkEvent", 30)
	if campEvent and campEvent:IsA("RemoteEvent") then
		campEvent.OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.kind == "SaleBurst" and stalls.Sell then
				coinBurst(stalls.Sell)
			end
		end)
	end
	if CampFlags.Training() then
		-- AFK detection: ping the server at most every 20 s while the player is actually giving input.
		local UserInputService = game:GetService("UserInputService")
		local trainingInput = remotes and remotes:WaitForChild("TrainingInput", 30)
		local lastPing = 0
		UserInputService.InputBegan:Connect(function()
			local now = os.clock()
			if trainingInput and now - lastPing >= 20 then
				lastPing = now
				local remote = trainingInput :: RemoteEvent
				remote:FireServer()
			end
		end)
		if campEvent and campEvent:IsA("RemoteEvent") then
			campEvent.OnClientEvent:Connect(function(payload)
				if type(payload) == "table" and payload.kind == "TrainingLevelUp" then
					Controller.ShowLevelToast(tonumber(payload.gained) or 1)
				end
			end)
		end
	end
	-- Balance changes move the rack picks (affordability); refresh at most every few seconds.
	local pending = false
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if pending then
			return
		end
		pending = true
		task.delay(4, function()
			pending = false
			refresh()
		end)
	end)
end

return Controller
