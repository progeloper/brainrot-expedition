--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local ApprovedEnvironment = require(ReplicatedStorage.Shared.Utility.ApprovedEnvironment)

local LocalCartState = require(script.Parent.State.LocalCartState)

local CartInputController = require(script.Parent.Controllers.CartInputController)

local CartPCInputController = require(script.Parent.Controllers.CartPCInputController)

local CartGamepadInputController = require(script.Parent.Controllers.CartGamepadInputController)

local CartMovementController = require(script.Parent.Controllers.CartMovementController)
local CartWheelPresentationController =
	require(script.Parent.Controllers.CartWheelPresentationController)

local CartCameraController = require(script.Parent.Controllers.CartCameraController)

local CartResetController = require(script.Parent.Controllers.CartResetController)
local CargoHudController = require(script.Parent.Controllers.CargoHudController)
local IncomePlaqueController = require(script.Parent.Controllers.IncomePlaqueController)
local BrainrotSaleController = require(script.Parent.Controllers.BrainrotSaleController)
local BrainrotNametagController = require(script.Parent.Controllers.BrainrotNametagController)
local Phase12PresentationController =
	require(script.Parent.Controllers.Phase12PresentationController)
local PlayerDataStatusController = require(script.Parent.Controllers.PlayerDataStatusController)
local WorldProgressionController = require(script.Parent.Controllers.WorldProgressionController)
local CartUpgradeController = require(script.Parent.Controllers.CartUpgradeController)

local player = Players.LocalPlayer
local log = Logger.new("ClientBootstrap")

local function start()
	assert(player ~= nil, "LocalPlayer was unavailable")

	log:Info("Starting client for %s in %s", player.Name, Environment.Name)
	require(script.Parent.Utility.DefaultCameraStartup).Start(player)
	ApprovedEnvironment.ApplyBaseline()
	-- The server creates its remotes during a long boot (terrain, world art). Controllers
	-- that started first gave up on timed waits and stayed dead for the session: no wild
	-- creatures to hunt, no shop, no progression. Start them only once the server is ready.
	local waitedFrom = os.clock()
	local warnedAt = waitedFrom
	while ReplicatedStorage:GetAttribute("ServerBootstrapReady") ~= true do
		task.wait(0.25)
		if os.clock() - warnedAt >= 15 then
			warnedAt = os.clock()
			log:Warn("Still waiting for server bootstrap after %d seconds", math.floor(os.clock() - waitedFrom))
		end
	end
	PlayerDataStatusController.Start()
	-- Playtest Fixes 2 Part A: DEV input trace (Studio) + flag-gated unstick watchdog. Isolated.
	task.spawn(function()
		local ok, err = pcall(require(script.Parent.Controllers.InputUnstickController).Start)
		if not ok then
			log:Warn("InputUnstickController failed to start: %s", tostring(err))
		end
		-- Part E3: DEV stall audit (Studio only, read-only).
		pcall(require(script.Parent.Utility.StallAudit).Start)
	end)
	if (FeatureFlags :: any).GameAudioEnabled then
		task.spawn(require(script.Parent.Controllers.AudioController).Start)
	end
	task.spawn(require(script.Parent.Controllers.CreaturePresentationController).Start)
	-- Core Loop V2 (flag-gated; returns immediately when CoreLoopV2Enabled/Preview is off).
	task.spawn(function()
		local ok, err = pcall(require(script.Parent.Controllers.CoreLoopHudController).Start)
		if not ok then
			log:Warn("CoreLoopHudController failed to start: %s", tostring(err))
		end
		local okFx, fxErr = pcall(require(script.Parent.Controllers.CoreLoopFxController).Start)
		if not okFx then
			log:Warn("CoreLoopFxController failed to start: %s", tostring(fxErr))
		end
		pcall(require(script.Parent.Controllers.CoreLoopFxPen).Start) -- Studio-only review pen (L6)
		pcall(require(script.Parent.Controllers.CoreLoopTripBot).Start) -- Studio-only trip bot (A-4)
	end)
	require(script.Parent.Controllers.Phase13AppearanceController).Start()
	-- Camp Rework weapon art feedback (spinners/drum on the shared <=10 Hz scheduler).
	-- Camp Rework presentation is isolated: an error here must never stop the rest of the client.
	local okArt, artError = pcall(function()
		require(script.Parent.Controllers.WeaponArtController).Start()
	end)
	if not okArt then
		log:Warn("WeaponArtController failed to start: %s", tostring(artError))
	end
	-- Camp Rework stalls (racks, featured cart, windmill/turntable, sale burst, speedometer).
	task.spawn(function()
		local ok, err = pcall(function()
			require(script.Parent.Controllers.CampStallController).Start()
		end)
		if not ok then
			log:Warn("CampStallController failed to start: %s", tostring(err))
		end
	end)
	require(script.Parent.Controllers.Phase14CosmeticController).Start()
	task.spawn(require(script.Parent.Controllers.RegionVisibilityController).Start)
	task.spawn(require(script.Parent.Controllers.Phase13ShopController).Start)
	if require(ReplicatedStorage.Shared.Config.RetentionConfig).Enabled then
		task.spawn(require(script.Parent.Controllers.RetentionController).Start)
	end
	task.spawn(require(script.Parent.Controllers.Phase13TelemetryController).Start)
	do
		-- HUD + menus (Stud Pop Plate). The HUD has two menu buttons (Brainrots, Inventory; B / I);
		-- shops open only at their camp stalls, Rebirth at the base entrance, Passes & Gems at the
		-- Announcements kiosk, the daily gift opens contextually. Controllers keep every remote call.
		local Shop = require(script.Parent.Controllers.Phase13ShopController)
		local retentionOn = require(ReplicatedStorage.Shared.Config.RetentionConfig).Enabled
		local Retention = if retentionOn then require(script.Parent.Controllers.RetentionController) else nil
		local MenusV2 = require(script.Parent.UI.MenusV2)
		local deps = { shop = Shop, retention = Retention }
		local function hudWindow(name)
			return function()
				require(script.Parent.UI.Screens[name]).toggle(deps)
			end
		end
		MenusV2.Start()
		MenusV2.bindKey(Enum.KeyCode.B, hudWindow("BrainrotsScreen"))
		MenusV2.bindKey(Enum.KeyCode.I, hudWindow("InventoryScreen"))
		if require(script.Parent.Utility.InputUnstick).Enabled() then
			-- Playtest Fixes 2 A3: HUD buttons are not pad-selectable; the D-pad opens their windows.
			local Registry = require(ReplicatedStorage.Shared.Config.CartInputRegistry)
			MenusV2.bindKey(Registry.HudBrainrots.Gamepad, hudWindow("BrainrotsScreen"))
			MenusV2.bindKey(Registry.HudInventory.Gamepad, hudWindow("InventoryScreen"))
		end
		task.spawn(require(script.Parent.UI.Screens.PassesKiosk).Start, Shop)
		if Retention then
			task.spawn(require(script.Parent.UI.Screens.DailyGiftScreen).Start, Retention, deps)
		end
		task.spawn(require(script.Parent.UI.Screens.HudScreen).Start, {
			openBrainrots = hudWindow("BrainrotsScreen"),
			openInventory = hudWindow("InventoryScreen"),
		})
	end
	if require(ReplicatedStorage.Shared.Config.Phase10).Enabled then
		require(script.Parent.Controllers.PlayerDazeController).Start()
	end
	BrainrotNametagController.Start()
	task.spawn(Phase12PresentationController.Start)
	task.spawn(require(script.Parent.Controllers.CatchRevealController).Start)
	task.spawn(require(script.Parent.Controllers.FirstSessionGuideController).Start)
	IncomePlaqueController.Start()
	-- Playtest Fixes 2 Part G: Legs treadmill presentation + trails (flag-gated). Isolated.
	task.spawn(function()
		local ok, err = pcall(require(script.Parent.Controllers.LegsTrainingController).Start)
		if not ok then
			log:Warn("LegsTrainingController failed to start: %s", tostring(err))
		end
	end)
	-- Playtest Fixes 2 Part C: cash stacks + claim coins (flag-gated, presentation only). Isolated.
	task.spawn(function()
		local ok, err = pcall(require(script.Parent.Controllers.CashPadController).Start)
		if not ok then
			log:Warn("CashPadController failed to start: %s", tostring(err))
		end
	end)
	BrainrotSaleController.Start()
	do
		-- V5 world: Storm listens to the same progression summary, so it starts first.
		local StormController = require(script.Parent.Controllers.StormController)
		task.spawn(StormController.Start)
		task.spawn(require(script.Parent.Controllers.WorldDetailController).Start, {
			ShowBanner = StormController.ShowBanner,
		})
	end
	if FeatureFlags.WorldProgressionEnabled then
		task.spawn(WorldProgressionController.Start)
	end

	if not FeatureFlags.CartEnabled then
		log:Info("Cart subsystem disabled")
		return
	end

	if FeatureFlags.EquippedTeamsEnabled then
		require(script.Parent.Controllers.ChariotTeamController).Start()
		require(script.Parent.Controllers.ChariotFormationController).Start()
	end
	CartUpgradeController.Start()

	CartInputController.Start()
	CartMovementController.Start()
	CartWheelPresentationController.Start()
	do
		-- Cart flair VFX (presentation only). Isolated so a failure never blocks driving.
		local ok, err = pcall(function()
			require(script.Parent.Controllers.CartFlairController).Start()
		end)
		if not ok then
			log:Warn("CartFlairController failed to start: %s", tostring(err))
		end
	end
	CartCameraController.Start()
	CartResetController.Start()
	CargoHudController.Start()
	LocalCartState.Start()
	CartPCInputController.Start()
	CartGamepadInputController.Start()
	if FeatureFlags.EquippedTeamsEnabled then
		require(script.Parent.Controllers.CartBurstController).Start()
	end
	if FeatureFlags.EquippedTeamsEnabled then
		require(script.Parent.Controllers.CartShieldController).Start()
	end

	require(script.Parent.Controllers.ExactHudController).Start()
	-- Drive-and-Hunt switch button and launch effects; a no-op unless its flag (or Studio preview) is on.
	task.spawn(require(script.Parent.Controllers.DriveAndHuntController).Start)
	if FeatureFlags.VillagerGuardsEnabled then
		-- Villager guards + Escape Ring (presentation only; the server owns every state).
		require(script.Parent.Controllers.VillagerPresentationController).Start()
		local EscapeRing = require(script.Parent.Controllers.EscapeRingController)
		EscapeRing.Start()
		require(script.Parent.Controllers.VillagerBankFxController).Start(EscapeRing.EscapeCompleted)
	end
	-- Studio-only draft animation review pen (Config/AnimationReview); off by default.
	if require(ReplicatedStorage.Shared.Config.AnimationReview).IsOn() then
		task.spawn(require(script.Parent.Controllers.AnimationReviewPen).Start)
	end
	require(script.Parent.Controllers.ContactShadowController).Start()
	log:Info("Client bootstrap complete")
end

start()
