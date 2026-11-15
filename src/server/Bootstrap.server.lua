--!strict

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Trace = require(script.Parent.Utility.BrainrotDiagnostics)
Trace.Emit("BOOT", "trace_enabled", {
	module = script,
	environment = Environment.Name,
	placeId = game.PlaceId,
	result = "loading_dependencies",
})

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local BrainrotBehaviours = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotPopulation = require(ReplicatedStorage.Shared.Config.BrainrotPopulation)
local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Phase13Rules = require(ReplicatedStorage.Shared.Utility.Phase13Rules)
local Phase13Service = require(script.Parent.Services.Phase13Service)
local Phase13Runtime = require(script.Parent.Services.Phase13RuntimeService)
local Phase13Interest = require(script.Parent.Services.Phase13InterestService)
local Phase13Analytics = require(script.Parent.Services.Phase13AnalyticsService)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local WorldVisualRepair = require(script.Parent.Utility.WorldVisualRepair)

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local ConfigValidator = require(ReplicatedStorage.Shared.Validation.ConfigValidator)
local BrainrotCatalogValidator =
	require(ReplicatedStorage.Shared.Validation.BrainrotCatalogValidator)
local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)

local CartMovementProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)

local CartStabilityProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartStabilityProfileResolver)

local CartTerrainProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartTerrainProfileResolver)

local AssetValidationService = require(script.Parent.Services.AssetValidationService)
local PlayerDataService = require(script.Parent.Services.PlayerDataService)
local PlayerWorldLifecycle = require(script.Parent.Services.PlayerWorldLifecycle)
local BankedBrainrotService = require(script.Parent.Services.BankedBrainrotService)
local DeparturePolicy = require(script.Parent.Services.DeparturePolicy)
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local Phase12World = require(script.Parent.Services.Phase12WorldService)
local Phase12Escape = require(script.Parent.Services.Phase12EscapeService)
local Phase12Events = require(script.Parent.Services.Phase12EventService)
local PlayerCombatService = require(script.Parent.Services.PlayerCombatService)
local function phase10Feedback(player: Player, text: string)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("SleepRequest")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, nil, nil, { Phase10Message = text })
	end
end
-- Denied gate thresholds are deliberately nonqueryable. Resolve the same
-- authored semantic boxes before committing a shot, without changing map physics.
local function gateIntersection(origin: Vector3, endpoint: Vector3, part: BasePart): number?
	local from = part.CFrame:PointToObjectSpace(origin)
	local delta = part.CFrame:VectorToObjectSpace(endpoint - origin)
	local half = part.Size / 2
	local near, far = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		if math.abs(delta[axis]) < 1e-8 then
			if math.abs(from[axis]) > half[axis] then
				return nil
			end
		else
			local a, b =
				(-half[axis] - from[axis]) / delta[axis], (half[axis] - from[axis]) / delta[axis]
			if a > b then
				a, b = b, a
			end
			near, far = math.max(near, a), math.min(far, b)
			if near > far then
				return nil
			end
		end
	end
	return near
end

local UpgradeService = require(script.Parent.Services.UpgradeService)
local WorldProgressionRuntime = require(script.Parent.Services.WorldProgressionRuntime)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.Config.WorldProgression)
local ProgressionMetricsService = require(script.Parent.Services.ProgressionMetricsService)
local PlayerDataConfig = require(script.Parent.Config.PlayerDataConfig)

local CollisionService = require(script.Parent.Services.CollisionService)

local CartSpawnRegistry = require(script.Parent.Services.CartSpawnRegistry)

local CartAssemblyValidationService = require(script.Parent.Services.CartAssemblyValidationService)

local CartOccupantService = require(script.Parent.Services.CartOccupantService)

local CartTerrainService = require(script.Parent.Services.CartTerrainService)

local CartArcadeService = require(script.Parent.Services.CartArcadeService)

local CartStabilityService = require(script.Parent.Services.CartStabilityService)

Trace.Emit("BOOT", "require_enter", { module = script.Parent.Services.CartService })
local CartService = require(script.Parent.Services.CartService)
Trace.Emit(
	"BOOT",
	"require_exit",
	{ module = script.Parent.Services.CartService, result = "loaded" }
)

Trace.Emit("BOOT", "require_enter", { module = script.Parent.Services.CartCargoService })
local CartCargoService = require(script.Parent.Services.CartCargoService)
Trace.Emit(
	"BOOT",
	"require_exit",
	{ module = script.Parent.Services.CartCargoService, result = "loaded" }
)

local CartResetService = require(script.Parent.Services.CartResetService)

local CartResetRequestService = require(script.Parent.Services.CartResetRequestService)

local CartMovementValidationService = require(script.Parent.Services.CartMovementValidationService)

local CartAnalyticsService = require(script.Parent.Services.CartAnalyticsService)

local CartGreyboxValidationService = require(script.Parent.Services.CartGreyboxValidationService)

local CartPerformanceLoadService = require(script.Parent.Services.CartPerformanceLoadService)

local CartGreyboxRouteSystem = require(script.Parent.Systems.CartGreyboxRouteSystem)

local PlayerBaseSystem = require(script.Parent.Systems.PlayerBaseSystem)
local PlatformIncomeProfileStore = require(script.Parent.Systems.PlatformIncomeProfileStore)
local BaseSignSystem = require(script.Parent.Systems.BaseSignSystem)

local PlayerSpawnSystem = require(script.Parent.Systems.PlayerSpawnSystem)
Trace.Emit("BOOT", "require_enter", { module = script.Parent.Systems.BaseStorageSystem })
local BaseStorageSystem = require(script.Parent.Systems.BaseStorageSystem)
Trace.Emit(
	"BOOT",
	"require_exit",
	{ module = script.Parent.Systems.BaseStorageSystem, result = "loaded" }
)
Trace.Emit("BOOT", "require_enter", { module = script.Parent.Systems.BrainrotIncomeSystem })
local BrainrotIncomeSystem = require(script.Parent.Systems.BrainrotIncomeSystem)
Trace.Emit(
	"BOOT",
	"require_exit",
	{ module = script.Parent.Systems.BrainrotIncomeSystem, result = "loaded" }
)
local BaseIncomePlaqueSystem = require(script.Parent.Systems.BaseIncomePlaqueSystem)

local DevelopmentBrainrotSpawner = require(script.Parent.Systems.DevelopmentBrainrotSpawner)

local DevelopmentBrainrotRoaming = require(script.Parent.Systems.DevelopmentBrainrotRoaming)
local RegionSpawnCatalog = require(script.Parent.Systems.RegionSpawnCatalog)

local BrainrotSleepSystem = require(script.Parent.Systems.BrainrotSleepSystem)
local BrainrotInteractionSystem = require(script.Parent.Systems.BrainrotInteractionSystem)
local BrainrotSaleSystem = require(script.Parent.Systems.BrainrotSaleSystem)
local BrainrotSalePointSystem = require(script.Parent.Systems.BrainrotSalePointSystem)
local CartUpgradePointSystem = require(script.Parent.Systems.CartUpgradePointSystem)
local CurrencySystem = require(script.Parent.Systems.CurrencySystem)

local CartGreyboxAnalyticsSink = require(script.Parent.Utility.CartGreyboxAnalyticsSink)

local log = Logger.new("ServerBootstrap")

local function upgradeOwnerSnapshot(player: Player, data: any): any
	local progression = if type(data) == "table" then data.Progression else nil
	local owned = if type(progression) == "table" and type(progression.Upgrades) == "table"
		then progression.Upgrades
		else {}
	return {
		status = "Ready",
		userId = player.UserId,
		balance = if type(data.Economy) == "table" then data.Economy.Balance else nil,
		ownedOfferIds = owned,
		ownedCarts = data.Phase13 and data.Phase13.OwnedCartIds or {},
		phase13 = data.Phase13,
		speedLevel = data.Phase13 and data.Phase13.SpeedLevel,
		cargoLevel = data.Phase13 and data.Phase13.CargoLevel,
	}
end

local function readUpgradeOwnerByUserId(ownerUserId: number): any?
	local player = Players:GetPlayerByUserId(ownerUserId)
	if player == nil then
		return nil
	end
	local data = PlayerDataService:GetReadableData(player)
	return if data then upgradeOwnerSnapshot(player, data) else nil
end

local function resolveUpgradeTarget(player: Player, _offer: any): (any?, string?)
	local cart = CartService:GetCart(player)
	if cart == nil then
		return nil, "Current cart is unavailable."
	end
	local cartId = cart:GetAttribute("CartId")
	local definition = if type(cartId) == "string" then Carts[cartId] else nil
	if definition == nil then
		return nil, "Current cart definition is unavailable."
	end
	return {
		cartId = cartId,
		ownerUserId = player.UserId,
		durableCartId = cart:GetAttribute("DurableCartId"),
		runtimeCart = cart,
		targetCartDisplayName = definition.DisplayName,
	},
		nil
end

local function applyPlayerWideUpgradeGrant(data: any, offer: any, _target: any): (boolean, string?)
	return Phase13Rules.GrantUpgrade(data, offer)
end

local upgradeReadiness = {
	effectReadyByOfferId = (function()
		local effects = {}
		for _, offer in Upgrades.GetReleased() do
			effects[offer.id] = if offer.grant.trackId == "Cargo"
				then function(_offer, _snapshot, target)
					local cart = target and target.runtimeCart
					return typeof(cart) == "Instance"
						and CartAssetValidator.ValidateCargoLayout(cart, 3 + offer.grant.level).status
							== "Ready"
				end
				else true
		end
		return effects
	end)(),
	persistenceReadyByScope = { PlayerWide = true },
	cartAcquisitionByTier = {},
	rankProviderOperational = false,
}

local function validateBrainrotCatalog()
	local ServerStorage = game:GetService("ServerStorage")
	local studioAssets = ServerStorage:FindFirstChild("Phase13CreatureAssets")
		or ReplicatedStorage:FindFirstChild("StudioAssets")
	local brainrotAssetFolder = if studioAssets
		then studioAssets:FindFirstChild("Brainrots")
		else nil
	local report = BrainrotCatalogValidator.ValidateCatalog(brainrotAssetFolder)
	local warningCounts: { [string]: number } = {}
	for _, validationIssue in report.warnings do
		warningCounts[validationIssue.code] = (warningCounts[validationIssue.code] or 0) + 1
	end
	local warningSummary = {}
	for code, count in warningCounts do
		table.insert(warningSummary, string.format("%s=%d", code, count))
	end
	table.sort(warningSummary)

	log:Info(
		"Brainrot catalogue validation complete: %d error(s), %d warning(s)",
		#report.errors,
		#report.warnings
	)
	for _, validationIssue in report.errors do
		log:Warn(
			"Brainrot catalogue error %s%s: %s",
			validationIssue.code,
			if validationIssue.speciesId then " (" .. validationIssue.speciesId .. ")" else "",
			validationIssue.message
		)
	end
	if #warningSummary > 0 then
		log:Info("Brainrot catalogue warning summary: %s", table.concat(warningSummary, ", "))
	end
	if RunService:IsStudio() or not Environment.IsProduction then
		log:Debug("%s", BrainrotCatalogValidator.FormatReport(report))
	end
end

local function validateEnvironment()
	validateBrainrotCatalog()
	ConfigValidator.AssertBrainrotPopulation("BrainrotPopulation", BrainrotPopulation)
	ConfigValidator.AssertBrainrotTerritory("BrainrotTerritory", BrainrotTerritory)
	ConfigValidator.AssertSprinterProfile(
		"BrainrotBehaviours.Sprinter",
		BrainrotBehaviours.Sprinter
	)
	ConfigValidator.AssertZigzagProfile("BrainrotBehaviours.Zigzag", BrainrotBehaviours.Zigzag)
	ConfigValidator.AssertCamouflageProfile(
		"BrainrotBehaviours.Camouflage",
		BrainrotBehaviours.Camouflage
	)
	ConfigValidator.AssertDecoySplitProfile(
		"BrainrotBehaviours.DecoySplit",
		BrainrotBehaviours.DecoySplit
	)
	ConfigValidator.AssertLegendaryPursuitProfile(
		"BrainrotBehaviours.LegendaryPursuit",
		BrainrotBehaviours.LegendaryPursuit,
		BrainrotBehaviours.Sprinter,
		BrainrotBehaviours.Zigzag
	)
	assert(
		Environment.Name == "Development"
			or Environment.Name == "Sandbox"
			or Environment.Name == "Production",
		"Invalid environment name."
	)

	if Environment.IsProduction then
		assert(Environment.EnableDebugTools == false, "Debug tools must be disabled in production.")
	end

	ConfigValidator.AssertUniqueIds("Brainrots", Ids.Brainrots)

	ConfigValidator.AssertUniqueIds("Carts", Ids.Carts)

	ConfigValidator.AssertUniqueIds("Harpoons", Ids.Harpoons)

	local weaponErrors = Weapons.Validate()
	assert(#weaponErrors == 0, "Invalid weapon configuration: " .. table.concat(weaponErrors, ", "))

	ConfigValidator.AssertUniqueIds("Gadgets", Ids.Gadgets)

	ConfigValidator.AssertUniqueIds("Regions", Ids.Regions)

	ConfigValidator.AssertUniqueIds("CartSpawns", Ids.CartSpawns)

	CartMovementProfileResolver.ValidateAll()

	CartStabilityProfileResolver.ValidateAll()

	CartTerrainProfileResolver.ValidateAll()
end

local function start()
	-- Server-authored release identity, reused by the existing Settings surface.
	ReplicatedStorage:SetAttribute("ReleaseBuildId", Environment.BuildId)
	ReplicatedStorage:SetAttribute("ReleasePlaceVersion", game.PlaceVersion)
	ReplicatedStorage:SetAttribute("ReleasePlaceId", game.PlaceId)
	local creatureAssets = require(script.Parent.Utility.CreatureAssetService)
	local privateReady, privateReason = creatureAssets.Prepare()
	assert(privateReady, "Private creature assets unavailable: " .. tostring(privateReason))
	ReplicatedStorage:SetAttribute("Phase13CreatureProtocolEnabled", creatureAssets.IsEnabled())
	local bankedPersistenceEnabled = PlayerDataConfig.EnableBankedBasePersistence
	Trace.Emit("BOOT", "bootstrap_enter", { cartEnabled = FeatureFlags.CartEnabled })
	validateEnvironment()
	CartOccupantService:SetDriverEligibilityPredicate(function(player)
		if not PlayerWorldLifecycle:IsReady(player) or not PlayerDataService:IsWritable(player) then
			return false, "player is not ready"
		end
		return true, nil
	end)
	CurrencySystem:Init(PlayerDataService)
	BankedBrainrotService:Init({ Profile = PlayerDataService, Currency = CurrencySystem })
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.PlayerDataService })
	-- Audio A/B variant attribute (presentation only, does not yield); set before players spawn.
	require(script.Parent.Services.AudioVariantService).Start()
	PlayerDataService:Start()
	BankedBrainrotService:Start()
	CartService:ConfigurePerformance({ OwnerStateReader = readUpgradeOwnerByUserId })
	CartCargoService:ConfigureCapacity({ OwnerStateReader = readUpgradeOwnerByUserId })
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Services.PlayerDataService, result = "returned" }
	)
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.PlayerBaseSystem })
	-- Yield once before the V5 world step: everything above runs in one resumption, and on a slow
	-- machine it has used up the script-timeout allowance by the time the terrain modules load.
	task.wait()
	local TerrainRedesignSwitch = require(script.Parent.Utility.TerrainRedesignSwitch)
	do
		-- V5 world: archive legacy walls before WorldVisualRepair would rebuild their shells.
		local ok, applied, why =
			pcall(TerrainRedesignSwitch.Apply, workspace:WaitForChild("MapBlockout"))
		if not ok or not applied then
			warn("TerrainRedesign failed to load the V5 world: " .. tostring(if ok then why else applied))
		elseif workspace:GetAttribute("TerrainRedesignActive") == true then
			-- Created up front: clients wait a bounded time for it, and the first unlock can be much later.
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if not remotes then
				remotes = Instance.new("Folder")
				remotes.Name = "Remotes"
				remotes.Parent = ReplicatedStorage
			end
			if not remotes:FindFirstChild(RemoteNames.WorldAnnouncement) then
				local announcement = Instance.new("RemoteEvent")
				announcement.Name = RemoteNames.WorldAnnouncement
				announcement.Parent = remotes
			end
		end
	end
	WorldVisualRepair.Start(workspace:WaitForChild("MapBlockout"))
	do
		local ok, why =
			pcall(require(script.Parent.Utility.FirstSessionWorldArt).Apply, workspace.MapBlockout)
		if not ok then
			warn("First-session world art failed: " .. tostring(why))
		end
	end
	pcall(TerrainRedesignSwitch.ApplyAfterFirstSessionArt, workspace.MapBlockout)
	require(script.Parent.Utility.WorldStudBinding).Start()
	PlayerBaseSystem:Start()
	Phase13Runtime:Start()
	-- Playtest Fixes 2 Part G: Legs treadmill, Legs levels -> WalkSpeed, trails (flag-gated; with the
	-- flag off it only moves the treadmill out of the world). Isolated so it can never stop the boot.
	do
		local ok, err = pcall(require(script.Parent.Services.LegsTrainingService).Start)
		if not ok then
			log:Warn("LegsTrainingService failed to start: %s", tostring(err))
		end
	end
	-- Keep committed retention recovery running when new daily offers are disabled.
	-- RetentionConfig.Enabled still gates new progress/grants inside RetentionRules.
	if Environment.MainGameplayEnabled or not Environment.IsProduction then
		require(script.Parent.Services.RetentionService):Start()
	end
	require(script.Parent.Services.Phase13MetricsService):Start()
	require(script.Parent.Services.Phase13ClientTelemetryService):Start()
	PlayerCombatService:ConfigurePhase13Service(Phase13Service)
	UpgradeService:Start({
		WorldReady = function(player)
			return PlayerDataService:IsWritable(player)
				and PlayerBaseSystem:GetAssignment(player) ~= nil
		end,
		Readiness = upgradeReadiness,
		ResolveTarget = resolveUpgradeTarget,
		BuildPlayerSnapshot = function(player, data, _target)
			return upgradeOwnerSnapshot(player, data)
		end,
		ApplyGrant = applyPlayerWideUpgradeGrant,
	})
	ProgressionMetricsService:Start()
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.PlayerBaseSystem, result = "returned" }
	)
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BaseSignSystem })
	BaseSignSystem:Start()
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.BaseSignSystem, result = "returned" }
	)

	log:Info("Starting server in %s. PlaceId=%d", Environment.Name, game.PlaceId)
	-- Playtest Fixes 2 Part E1: the resolved switch table, to compare a Studio Play with a live server.
	print(require(ReplicatedStorage.Shared.Utility.SwitchTable).Format())

	log:Debug("Feature flags loaded: Cart=%s", tostring(FeatureFlags.CartEnabled))
	-- Read-only regional indexing starts only after edit-time map/base objects have
	-- had their existing registration pass. It does not start a natural spawner.
	RegionSpawnCatalog.Start()

	if FeatureFlags.CartEnabled then
		do
			-- Bake the cart flair layer into the templates before anything validates,
			-- caches or clones them. Each cart rolls back to plain on any failure.
			local ok, report = pcall(function()
				local folder = ReplicatedStorage:WaitForChild("StudioAssets"):WaitForChild("Carts")
				return require(script.Parent.Utility.CartFlairBuilder).BakeTemplates(folder)
			end)
			if ok then
				for cartName, result in report do
					log:Info("CartFlair %s: %s", cartName, result)
				end
			else
				log:Warn("CartFlair bake skipped: %s", tostring(report))
			end
		end
		Trace.Emit(
			"BOOT",
			"start_enter",
			{ module = script.Parent.Services.AssetValidationService }
		)
		AssetValidationService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.AssetValidationService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CollisionService })
		CollisionService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CollisionService, result = "returned" }
		)

		if
			Environment.Name == "Development"
			and Environment.EnableGreyboxValidation
			and RunService:IsStudio()
		then
			local routeStarted, routeError = CartGreyboxRouteSystem:Start()

			if not routeStarted then
				log:Warn("Phase 1S greybox route unavailable: %s", routeError or "unknown error")
			end
		end

		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartSpawnRegistry })
		CartSpawnRegistry:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartSpawnRegistry, result = "returned" }
		)
		Trace.Emit(
			"BOOT",
			"start_enter",
			{ module = script.Parent.Services.CartAssemblyValidationService }
		)
		CartAssemblyValidationService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartAssemblyValidationService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartOccupantService })
		CartOccupantService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartOccupantService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartTerrainService })
		CartTerrainService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartTerrainService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartArcadeService })
		CartArcadeService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartArcadeService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartStabilityService })
		CartStabilityService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartStabilityService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartService })
		CartService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartCargoService })
		CartCargoService:ConfigureProvenance(function(record, ownerId)
			local owner = if type(ownerId) == "number"
				then Players:GetPlayerByUserId(ownerId)
				else nil
			if owner then
				return BankedBrainrotService:ClassifyRecord(owner, record)
			end
			return if BankedBrainrotService:IsBankedRecord(record)
				then "Banked"
				else "FreshUnbanked"
		end)
		CartCargoService:Start()
		UpgradeService:SubscribePurchaseCommitted(function(player, offer)
			if offer.category == "Cargo" then
				local ok, failure = pcall(function()
					CartCargoService:ReconcileOwnerCapacity(
						player.UserId,
						"UpgradePurchase:" .. offer.id
					)
				end)
				if not ok then
					log:Warn(
						"UpgradeEffectApplicationFailed userId=%d offerId=%s error=%s",
						player.UserId,
						offer.id,
						tostring(failure)
					)
				end
			elseif offer.category == "CartPerformance" then
				local ok, failure = pcall(function()
					CartService:ReconcileOwnerPerformance(
						player.UserId,
						"UpgradePurchase:" .. offer.id
					)
				end)
				if not ok then
					log:Warn(
						"UpgradeEffectApplicationFailed userId=%d offerId=%s error=%s",
						player.UserId,
						offer.id,
						tostring(failure)
					)
				end
			end
		end)
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartCargoService, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BaseStorageSystem })
		BaseStorageSystem:Start({
			Profile = if bankedPersistenceEnabled then PlayerDataService else false,
		})
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Systems.BaseStorageSystem, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BrainrotIncomeSystem })
		BrainrotIncomeSystem:Start({
			Profile = if bankedPersistenceEnabled
				then PlayerDataService
				else PlatformIncomeProfileStore,
			ProfileReadySignal = function(callback)
				return PlayerDataService:SubscribeReady(callback)
			end,
		})
		PlayerDataService:RegisterCloseFinalizer(function(player)
			BrainrotIncomeSystem:UntrackPlayer(player)
		end)
		if bankedPersistenceEnabled then
			PlayerDataService:RegisterSnapshotPreparer(function(player, _at)
				-- PlayerDataService's lease clock is DateTime-based while live income uses
				-- Workspace:GetServerTimeNow(). Let the income owner sample its own clock
				-- so harmless clock skew cannot reject an otherwise coherent snapshot.
				return BrainrotIncomeSystem:PrepareForSave(player)
			end)
		end
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Systems.BrainrotIncomeSystem, result = "returned" }
		)
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BaseIncomePlaqueSystem })
		BaseIncomePlaqueSystem:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Systems.BaseIncomePlaqueSystem, result = "returned" }
		)
		-- BaseReturnSystem existed solely for automatic cargo unloading. Arrival
		-- no longer starts a scanner; deposits require an explicit platform action.
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartResetService })
		CartResetService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartResetService, result = "returned" }
		)
		Trace.Emit(
			"BOOT",
			"start_enter",
			{ module = script.Parent.Services.CartMovementValidationService }
		)
		CartMovementValidationService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartMovementValidationService, result = "returned" }
		)

		if
			Environment.Name == "Development"
			and Environment.EnableGreyboxValidation
			and RunService:IsStudio()
		then
			CartGreyboxAnalyticsSink.Clear()
			CartAnalyticsService:SetProvider(CartGreyboxAnalyticsSink.GetProvider())
		end

		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Services.CartAnalyticsService })
		CartAnalyticsService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartAnalyticsService, result = "returned" }
		)
		Trace.Emit(
			"BOOT",
			"start_enter",
			{ module = script.Parent.Services.CartResetRequestService }
		)
		CartResetRequestService:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Services.CartResetRequestService, result = "returned" }
		)

		if
			Environment.Name == "Development"
			and Environment.EnableGreyboxValidation
			and RunService:IsStudio()
		then
			local harnessStarted, harnessError = CartGreyboxValidationService:Start()

			if not harnessStarted then
				log:Warn(
					"Phase 1S greybox validation harness unavailable: %s",
					harnessError or "unknown error"
				)
			end

			local performanceHarnessStarted, performanceHarnessError = Trace.Emit(
				"BOOT",
				"start_enter",
				{ module = script.Parent.Services.CartPerformanceLoadService }
			)
			CartPerformanceLoadService:Start()
			Trace.Emit(
				"BOOT",
				"start_exit",
				{ module = script.Parent.Services.CartPerformanceLoadService, result = "returned" }
			)

			if not performanceHarnessStarted then
				log:Warn(
					"Phase 1T performance harness unavailable: %s",
					performanceHarnessError or "unknown error"
				)
			end
		end
	else
		log:Info("Cart subsystem disabled")
	end

	-- Villager guards read region locks through the progression runtime when it exists.
	local villagerAccessReader: ((Player, string) -> boolean)? = nil
	if
		FeatureFlags.WorldProgressionEnabled
		and (Environment.MainGameplayEnabled or not Environment.IsProduction)
	then
		local progressionRuntime = WorldProgressionRuntime.new({
			Map = workspace:WaitForChild("MapBlockout", 10),
			Profile = PlayerDataService,
			Carts = CartService,
			Occupants = CartOccupantService,
			Currency = CurrencySystem,
			Storage = BaseStorageSystem,
			Spawner = DevelopmentBrainrotSpawner,
			BindInteractions = true,
			PurchasesEnabled = true,
			-- Storm response whenever the V5 world loaded (it always should; the store ships in the place).
			StormEnabled = workspace:GetAttribute("TerrainRedesignActive") == true,
			OnResult = function(player, result)
				if result.code ~= "Success" or type(result.key) ~= "string" then
					return
				end
				local definition = WorldProgressionConfig.ByKey[result.key]
				if not definition then
					return
				end
				local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
				local remote = remotes and remotes:FindFirstChild(RemoteNames.WorldAnnouncement)
				if not remote and remotes then
					remote = Instance.new("RemoteEvent")
					remote.Name = RemoteNames.WorldAnnouncement
					remote.Parent = remotes
				end
				if remote and remote:IsA("RemoteEvent") then
					remote:FireAllClients({
						kind = "RegionUnlocked",
						userId = player.UserId,
						playerName = player.DisplayName,
						regionKey = result.key,
						displayName = definition.displayName,
					})
				end
			end,
			OnQuotaChanged = function(allocation)
				log:Info(
					"World progression natural quota total=%d quotas=%s",
					allocation.total,
					game:GetService("HttpService"):JSONEncode(allocation.quotas)
				)
			end,
			OnEvent = function(name, data, player)
				log:Info(
					"WorldProgression %s user=%s region=%s code=%s",
					name,
					tostring(player and player.UserId),
					tostring(data.key or data.regionId),
					tostring(data.code)
				)
				if player then
					ProgressionMetricsService:ObserveWorldProgression(player, name, data)
					if name == "GatePurchaseConfirmed" then
						if
							type(data.price) == "number"
							and data.price > 0
							and type(data.wallet) == "number"
						then
							Phase13Analytics:Economy(
								player,
								"Sink",
								data.price,
								data.wallet,
								data.key or "Session",
								"REGION_GATE"
							)
						end
						local order = {
							Forest = 1,
							Beach = 2,
							Swamp = 3,
							Jungle = 4,
							Arctic = 5,
							Volcano = 6,
							Glitch = 7,
						}
						if order[data.key] then
							Phase13Analytics:Funnel(player, "RegionProgression", order[data.key])
						end
						Phase13Analytics:Record(
							player,
							"RegionUnlock",
							1,
							{ category = data.key or "Session", result = "Success" }
						)
					end
				end
			end,
		})
		assert(
			progressionRuntime:Start(WorldProgressionConfig.OperationalKeys),
			"Phase 8 gate setup failed"
		)
		Phase13Interest:Start({ Access = progressionRuntime.access })
		villagerAccessReader = function(player: Player, regionId: string): boolean
			-- Starter regions are always open; others need confirmed personal access.
			local definition = WorldProgressionConfig.ById[regionId]
			if definition and definition.index <= 1 then
				return true
			end
			return progressionRuntime.access:GetPersonalAccess(player, regionId)
		end
		require(script.Parent.Services.CreatureReplicationService):Start({
			Interest = Phase13Interest,
		})
		BrainrotSleepSystem.SetInterestService(Phase13Interest)
		DevelopmentBrainrotRoaming.ConfigureInterest(function(regionId, position)
			return Phase13Interest:IsObserved(regionId, position)
		end)
		CartResetService:ConfigurePlacement({
			Descriptors = progressionRuntime.descriptors,
			Access = progressionRuntime.access,
			CampContains = function(position)
				return RegionSpawnCatalog.ContainsPosition("REGION_CAMP", position, math.huge)
			end,
			GetAssignedBase = function(player)
				return PlayerBaseSystem:GetBase(player)
			end,
		})
		if Phase10.Enabled then
			BrainrotSleepSystem.SetSemanticObstructionResolver(function(player, origin, endpoint)
				local nearest, barrier = math.huge, nil
				for _, definition in WorldProgressionConfig.Ordered do
					local gate = progressionRuntime.descriptors:GetGate(definition.regionId)
					if
						gate
						and not progressionRuntime.access:GetEffectiveAccess(
							player,
							definition.regionId
						)
					then
						local t = gateIntersection(origin, endpoint, gate.crossing)
						if t and t < nearest then
							nearest, barrier = t, gate.crossing
						end
					end
				end
				return if barrier
					then { Instance = barrier, Position = origin + (endpoint - origin) * nearest }
					else nil
			end)
		end
		if FeatureFlags.EquippedTeamsEnabled then
			require(script.Parent.Services.ChariotTeamService):ConfigureGateAccess(function(cart)
				local allowed = {}
				for _, definition in WorldProgressionConfig.Ordered do
					if definition.index > 1 then
						allowed[definition.regionId] = progressionRuntime.access:GetCartEntryAccess(
							cart,
							definition.regionId
						).allowed == true
					end
				end
				return allowed
			end)
		end
		BrainrotSleepSystem.SetRegionAccessValidator(function(player, target)
			return progressionRuntime:ValidateWildAction(player, target)
		end)
		BrainrotInteractionSystem.SetRegionAccessValidator(function(player, target)
			return progressionRuntime:ValidateWildAction(player, target)
		end)
		game:BindToClose(function()
			progressionRuntime:Destroy()
		end)
		log:Info("World progression access and gate services ready")
		log:Info("WorldProgression PoolValidated huntingRegions=7 liveSpecies=32 target=42")
	end

	DevelopmentBrainrotSpawner.Start()
	DevelopmentBrainrotRoaming.Start()
	-- Core Loop V2 (Part A): the herd spawn director. Starts only when CoreLoopFlags.Part("Herds") is on;
	-- with the flag off this is a no-op and natural spawning is unchanged.
	do
		local Economy = require(ReplicatedStorage.Shared.Config.Economy)
		local stormAttribute = Economy.MutationStorm.Attribute
		local HuntDirector = require(script.Parent.Systems.HuntDirector)
		local directorRunning = false
		if
			HuntDirector.Start({
				Spawner = DevelopmentBrainrotSpawner,
				WorldService = Phase12World,
				SleepSystem = BrainrotSleepSystem,
				AccessReader = villagerAccessReader,
				Analytics = Phase13Analytics,
				-- A7 Saved: the owner's driven cart position and whether its cargo is full.
				GetCartInfo = function(userId: number)
					local record = CartService:GetCartRecordByOwnerUserId(userId)
					local cart = record and record.Model
					if not cart or not cart.Parent then
						return nil
					end
					return { Position = cart:GetPivot().Position, Full = not CartCargoService:CanAcceptCargo(cart) }
				end,
				-- Paid Mutation Storm multiplies before the 30% clamp (K1); the gameplay multiplier only.
				StormMultiplier = function()
					local until_ = workspace:GetAttribute(stormAttribute)
					return if type(until_) == "number" and until_ > workspace:GetServerTimeNow()
						then Economy.MutationStorm.ChanceMultiplier
						else 1
				end,
			})
		then
			log:Info("Core Loop V2 HuntDirector running (herds, Stars, loners)")
			directorRunning = true
			-- Parts C, D, K: Lucky Meter + pity, combo + magnet, mutation reveal (server-authoritative).
			local GemSources = require(ReplicatedStorage.Shared.Config.Economy).GemSources
			require(script.Parent.Services.CoreLoopProgress).Start({
				Director = HuntDirector,
				Spawner = DevelopmentBrainrotSpawner,
				Interaction = BrainrotInteractionSystem,
				SleepSystem = BrainrotSleepSystem,
				Analytics = Phase13Analytics,
				Villagers = require(script.Parent.Services.VillagerGuardService),
				RushKind = HuntDirector.RushKind,
				GetDrivenCart = function(player: Player)
					local record = CartService:GetCartRecord(player)
					local cart = record and record.Model
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local seat = humanoid and humanoid.SeatPart
					return if cart and seat and cart:IsAncestorOf(seat) then cart else nil
				end,
				-- "NEW MUTATION! +N GEMS on bank": read-only preview of the existing first-bank Gem rule.
				MutationGemPreview = function(player: Player, mutationId: string): number?
					local data = PlayerDataService:GetReadableData(player)
					local gemState = data and data.Economy and data.Economy.GemState
					local seen = gemState and gemState.Mutations
					local amount = GemSources and GemSources.FirstMutation and GemSources.FirstMutation[mutationId]
					if type(amount) ~= "number" or (type(seen) == "table" and seen[mutationId]) then
						return nil
					end
					return amount
				end,
			})
		end
		-- K4 Mutation Rain: MEGA RUSH strikes on present players' displayed brainrots (sub-flag MutationRain).
		if directorRunning then
			require(script.Parent.Services.CoreLoopMutationRain).Start({
				WorldService = Phase12World,
				BaseStorageSystem = BaseStorageSystem,
				Phase13Service = Phase13Service,
				Profile = PlayerDataService,
				Analytics = Phase13Analytics,
			})
		end
		-- Trip measurement (A-4 / CL_Trip): flag on, or Studio QA with the flag off for comparisons.
		require(script.Parent.Services.CoreLoopTripTracker).Start({
			CartService = CartService,
			SleepSystem = BrainrotSleepSystem,
			Banked = BankedBrainrotService,
			Analytics = Phase13Analytics,
		})
		-- Studio QA hook (ServerStorage.CoreLoopQA = true only); also runs with the flag off for F-0.
		require(script.Parent.Services.CoreLoopQAService).Start({
			Director = if directorRunning then HuntDirector else nil,
			WorldService = Phase12World,
			Spawner = DevelopmentBrainrotSpawner,
		})
	end
	-- Studio-only draft animation review pen (Config/AnimationReview); off by default.
	require(script.Parent.Services.AnimationReviewService).Start()
	require(script.Parent.Services.Phase13MovementAnalyticsService):Start({
		World = DevelopmentBrainrotSpawner,
		Analytics = Phase13Analytics,
	})
	BrainrotInteractionSystem.Start({
		Feedback = phase10Feedback,
		World = DevelopmentBrainrotSpawner,
		CreateItemVisual = function(brainrotId)
			return CartCargoService:CreateItemVisual(brainrotId)
		end,
		IsDriving = function(player)
			return CartOccupantService:IsDriving(player)
		end,
		Banked = if bankedPersistenceEnabled then BankedBrainrotService else nil,
		DeparturePolicy = DeparturePolicy,
	})
	PlayerDataService:RegisterDeparturePreparer(function(player, reason)
		return BrainrotInteractionSystem.HandlePlayerDeparture(player, reason)
	end)
	-- Drive-by haul (owner decision, 10 Nov 2026): scoop beside the driven cart,
	-- bank on arrival at the owner's base.
	require(script.Parent.Systems.DriveByHaulSystem).Start({
		World = DevelopmentBrainrotSpawner,
		Interaction = BrainrotInteractionSystem,
		Cargo = CartCargoService,
		Feedback = phase10Feedback,
		GetDrivenCart = function(player)
			if not CartOccupantService:IsDriving(player) then
				return nil
			end
			return CartService:GetCart(player)
		end,
		GetBase = function(player)
			return PlayerBaseSystem:GetBase(player)
		end,
	})
	BrainrotSaleSystem:Init({
		Feedback = phase10Feedback,
		ActionValidator = function(player)
			return PlayerCombatService:CanAct(player)
		end,
		Carry = BrainrotInteractionSystem,
		Currency = CurrencySystem,
		Banked = if bankedPersistenceEnabled then BankedBrainrotService else nil,
		-- Bulk sale at the Sell stall sells banked brainrots straight from their platforms.
		Storage = BaseStorageSystem,
		Catalog = BrainrotCatalog,
		SessionClosingSignal = function(callback)
			return PlayerBaseSystem:SubscribeSessionClosing(callback)
		end,
		BaseReleasingSignal = function(callback)
			return PlayerBaseSystem:SubscribeAssignments(function(_player, _base) end, callback)
		end,
	})
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BrainrotSaleSystem })
	BrainrotSaleSystem:Start()
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.BrainrotSaleSystem, result = "returned" }
	)
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BrainrotSalePointSystem })
	BrainrotSalePointSystem:Start()
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.BrainrotSalePointSystem, result = "returned" }
	)
	if FeatureFlags.CartEnabled then
		Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.CartUpgradePointSystem })
		CartUpgradePointSystem:Start()
		Trace.Emit(
			"BOOT",
			"start_exit",
			{ module = script.Parent.Systems.CartUpgradePointSystem, result = "returned" }
		)
	end
	BrainrotSleepSystem.SetCarryingPredicate(BrainrotInteractionSystem.IsCarrying)
	CartOccupantService:SetCarryingPredicate(
		BrainrotInteractionSystem.IsCarrying,
		BrainrotInteractionSystem.CarryChanged
	)
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.BrainrotSleepSystem })
	BrainrotSleepSystem:Start()
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.BrainrotSleepSystem, result = "returned" }
	)
	Trace.Emit("BOOT", "start_enter", { module = script.Parent.Systems.PlayerSpawnSystem })
	if FeatureFlags.EquippedTeamsEnabled then
		local team = require(script.Parent.Services.ChariotTeamService)
		team:Start()
		BrainrotSleepSystem.SetCartHitMultiplierResolver(function(cart)
			local owner = cart:GetAttribute("OwnerUserId")
			local stats = type(owner) == "number" and team:GetStats(owner)
			return stats and stats.hitMultiplier or 1
		end)
		require(script.Parent.Services.CartBurstService):Start()
	end
	-- Keep the non-production handoff available when effects are disabled;
	-- Shield then passes valid attacks through to their existing normal commit.
	if Environment.MainGameplayEnabled or not Environment.IsProduction then
		require(script.Parent.Services.CartShieldService):Start()
	end
	PlayerWorldLifecycle:Start()
	if Phase10.Enabled then
		PlayerCombatService:ConfigureTransactions({
			Cargo = CartCargoService,
			Carry = BrainrotInteractionSystem,
			World = DevelopmentBrainrotSpawner,
			Banked = BankedBrainrotService,
			Shield = require(script.Parent.Services.CartShieldService),
			ValidateContext = BrainrotSleepSystem.ValidateFiringContext,
			Name = function(id)
				local definition = BrainrotCatalog.Get(id)
				return definition and definition.displayName or id
			end,
			Feedback = phase10Feedback,
		})
		PlayerCombatService:Start()
		BrainrotInteractionSystem.SetActionValidator(function(player)
			return PlayerCombatService:CanAct(player)
		end)
		BrainrotSleepSystem.SetActionValidator(function(player)
			if
				not PlayerWorldLifecycle:IsReady(player) or not PlayerDataService:IsWritable(player)
			then
				return false, "Player is not ready."
			end
			return PlayerCombatService:CanAct(player)
		end)
		BrainrotSleepSystem.SetImpactHandler(function(...)
			return PlayerCombatService:ResolveImpact(...)
		end)
	end
	if Phase12.Enabled then
		Phase12Events:Start({
			World = DevelopmentBrainrotSpawner,
			Cargo = CartCargoService,
			Interaction = BrainrotInteractionSystem,
			Banked = BankedBrainrotService,
			Upgrade = UpgradeService,
			PlayerData = PlayerDataService,
			WorldService = Phase12World,
			Interest = Phase13Interest,
		})
		Phase12World:Start({
			Spawner = DevelopmentBrainrotSpawner,
			InteractionService = BrainrotInteractionSystem,
			CargoService = CartCargoService,
			CartService = CartService,
			PlayerDataService = PlayerDataService,
			WorldReady = function(player)
				return PlayerWorldLifecycle:IsReady(player) and PlayerDataService:IsWritable(player)
			end,
			ObserveCampState = function(player, inCamp)
				BankedBrainrotService:ObserveCampState(player, inCamp)
			end,
			ReturnCart = function(player, cart, cycle)
				return CartService:ReturnCartForTimedWipe(player, cart, cycle)
			end,
			RestoreBanked = function(player)
				-- Ordinary death already restores protected held originals. Cargo
				-- remains on the same returned cart; current durable records never
				-- enter the ordinary population or receive first-bank credit.
				local restored = BankedBrainrotService:RestoreSecuredWorldForReset(
					player,
					DevelopmentBrainrotSpawner
				)
				if not restored then
					return false
				end
				local base = PlayerBaseSystem:GetBase(player)
				return base ~= nil and BaseStorageSystem:RefreshPlatformDisplays(base)
			end,
			PublishEvent = function(kind, payload)
				Phase12Events:Broadcast(kind, nil, nil, payload)
			end,
			CreateBurrowShortfall = false,
		})
		Phase12Escape:Start({
			World = DevelopmentBrainrotSpawner,
			Interaction = BrainrotInteractionSystem,
			Cargo = CartCargoService,
			Cart = CartService,
			Events = Phase12Events,
			WorldService = Phase12World,
		})
		local existingAction = function(player)
			if
				not PlayerWorldLifecycle:IsReady(player) or not PlayerDataService:IsWritable(player)
			then
				return false, "Player is not ready."
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then
				return false, "Character unavailable."
			end
			local allowed, reason = Phase12World:CanCommit(nil, root.Position, player)
			if not allowed then
				return false, reason
			end
			return PlayerCombatService:CanAct(player)
		end
		BrainrotInteractionSystem.SetActionValidator(existingAction)
		BrainrotSleepSystem.SetActionValidator(existingAction)
	end
	if FeatureFlags.VillagerGuardsEnabled then
		-- Villager guards + Escape Ring: NPC/presentation only, never touches cargo or carry.
		require(script.Parent.Services.VillagerGuardRuntime).Start({
			CartService = CartService,
			CartCargoService = CartCargoService,
			Interaction = BrainrotInteractionSystem,
			SleepSystem = BrainrotSleepSystem,
			PlayerBaseSystem = PlayerBaseSystem,
			Analytics = Phase13Analytics,
			AccessReader = villagerAccessReader,
		})
	end
	-- Drive-and-Hunt (12 Nov 2026): gate launch + HOP OUT / CART / LOAD & GO. Starts nothing
	-- and creates no remotes unless DriveAndHuntV1Enabled (or the Studio preview) is on.
	require(script.Parent.Services.DriveAndHuntService).Start({
		CartService = CartService,
		Occupants = CartOccupantService,
		Cargo = CartCargoService,
		Interaction = BrainrotInteractionSystem,
		Combat = PlayerCombatService,
		World = DevelopmentBrainrotSpawner,
		Placement = require(script.Parent.Utility.CartLocalPlacement),
		GetBase = function(player)
			return PlayerBaseSystem:GetBase(player)
		end,
		AccessReader = villagerAccessReader,
		Feedback = phase10Feedback,
	})
	PlayerSpawnSystem:Start({ Readiness = PlayerWorldLifecycle })
	Trace.Emit(
		"BOOT",
		"start_exit",
		{ module = script.Parent.Systems.PlayerSpawnSystem, result = "returned" }
	)

	Trace.Emit(
		"BOOT",
		"bootstrap_complete",
		{ result = "ready", cartEnabled = FeatureFlags.CartEnabled }
	)
	-- Clients hold their controllers until every server remote exists (see client Bootstrap).
	ReplicatedStorage:SetAttribute("ServerBootstrapReady", true)
	log:Info("Server bootstrap complete")
end

start()
