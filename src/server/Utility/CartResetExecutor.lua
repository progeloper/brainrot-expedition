--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CartAssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)
local CartLocalCorrection = require(ReplicatedStorage.Shared.Config.CartLocalCorrection)
local CartLocalPlacement = require(script.Parent.CartLocalPlacement)

local CartModelUtility = require(script.Parent.CartModelUtility)
local CartAssemblyValidationService = require(script.Parent.Parent.Services.CartAssemblyValidationService)
local CartOccupantService = require(script.Parent.Parent.Services.CartOccupantService)
local CartStabilityService = require(script.Parent.Parent.Services.CartStabilityService)
local CartTerrainService = require(script.Parent.Parent.Services.CartTerrainService)

export type ResetStage = "Suspension" | "Reposition" | "Recovery" | "Resume"
export type StageCallback = (stage: ResetStage) -> (boolean, string?)

local CartResetExecutor = {}

local function summarizeAssemblyFailure(cart: Model): string
	local result = CartAssemblyValidationService:GetResult(cart)

	if result == nil then
		return "assembly validation returned no result"
	end

	local issue = result.FatalErrors[1]

	return if issue ~= nil then CartAssemblyValidator.FormatIssue(issue) else "cart assembly is not valid"
end

local function isLiveCart(cart: Model, root: BasePart): boolean
	return cart.Parent ~= nil
		and root.Parent ~= nil
		and root:IsDescendantOf(cart)
		and cart:GetAttribute("RuntimeCart") == true
end

local function validateDriverContext(
	cart: Model,
	root: BasePart,
	driver: Player?,
	requireValidAssembly: boolean,
	allowDriverless: boolean?,
	assignedContext: any?
): (boolean, string?)
	if assignedContext and not assignedContext.Validate() then return false,"Retired assigned return context" end
	if not isLiveCart(cart, root) then
		return false, "cart was destroyed or replaced"
	end

	if requireValidAssembly and not CartAssemblyValidationService:IsCartValid(cart) then
		return false, summarizeAssemblyFailure(cart)
	end

	if CartOccupantService:GetDriver(cart) ~= driver then
		return false, "active driver changed during reset"
	end

	if driver == nil then
		if
			allowDriverless ~= true
			or not CartOccupantService:IsCartRegistered(cart)
			or (#CartOccupantService:GetOccupants(cart) == 0 and assignedContext == nil)
		then
			return false, "registered occupied cart required for driverless access correction"
		end
		return true, nil
	end

	if not CartOccupantService:CanPlayerControlCart(driver, cart) then
		return false, "active driver is no longer authorised"
	end

	return true, nil
end

local function runStage(callback: StageCallback?, stage: ResetStage): (boolean, string?)
	if callback == nil then
		return true, nil
	end

	local callSucceeded, accepted, reason = pcall(callback, stage)

	if not callSucceeded then
		return false, string.format("%s stage callback failed: %s", stage, tostring(accepted))
	end

	if not accepted then
		return false, reason or string.format("%s stage was rejected", stage)
	end

	return true, nil
end

local function execute(
	cart: Model,
	spawnCFrame: CFrame,
	driver: Player?,
	stageCallback: StageCallback?,
	allowDriverless: boolean?,
	localPlan: any?,
	assignedContext: any?
): (boolean, string?, boolean)
	local rootSuccess, rootOrError = pcall(function()
		return CartModelUtility.GetRoot(cart)
	end)

	if not rootSuccess then
		return false, string.format("cart root is unavailable: %s", tostring(rootOrError)), true
	end

	local root = rootOrError :: BasePart
	local contextValid, contextError = validateDriverContext(cart, root, driver, true, allowDriverless, assignedContext)

	if not contextValid then
		return false, contextError, true
	end

	local targetCFrame = spawnCFrame
	local stabilitySuspended = false
	local terrainSuspended = false
	local suspensionIntegrityCompromised = false
	local mutationRevision: number? = nil
	local mutationCompleted = false

	local function recoverAcquiredState(): boolean
		if not isLiveCart(cart, root) then
			return false
		end

		local recoverySucceeded = pcall(function()
			CartModelUtility.SetRootAnchoredOnly(cart, false)
			CartModelUtility.ZeroVelocities(cart)
		end)

		if
			mutationRevision ~= nil
			and not mutationCompleted
			and CartAssemblyValidationService:GetState(cart) == "Preparing"
		then
			local mutationCallSucceeded, mutationValid = pcall(function()
				return CartAssemblyValidationService:CompleteMutation(
					cart,
					mutationRevision :: number,
					"PostReset",
					"reset failure recovery",
					true
				)
			end)

			mutationCompleted = mutationCallSucceeded
			recoverySucceeded = recoverySucceeded and mutationCallSucceeded and mutationValid == true
		end

		if terrainSuspended and CartAssemblyValidationService:IsCartValid(cart) then
			local resumeCallSucceeded, resumed = pcall(function()
				return CartTerrainService:ResumeCart(cart, "reset failure recovery")
			end)

			if resumeCallSucceeded and resumed then
				terrainSuspended = false
			else
				recoverySucceeded = false
			end
		elseif terrainSuspended then
			recoverySucceeded = false
		end

		if stabilitySuspended and CartAssemblyValidationService:IsCartValid(cart) then
			local resumeCallSucceeded, resumed = pcall(function()
				return CartStabilityService:ResumeCart(cart, "reset failure recovery")
			end)

			if resumeCallSucceeded and resumed then
				stabilitySuspended = false
			else
				recoverySucceeded = false
			end
		elseif stabilitySuspended then
			recoverySucceeded = false
		end

		if not CartAssemblyValidationService:IsCartValid(cart) then
			recoverySucceeded = false
		else
			local activeDriver = CartOccupantService:GetDriver(cart)

			if activeDriver ~= nil and activeDriver ~= driver then
				recoverySucceeded = false
			else
				local ownershipCallSucceeded, ownershipRestored = pcall(function()
					return CartOccupantService:RestoreNetworkOwnership(cart, "reset failure recovery")
				end)

				recoverySucceeded = recoverySucceeded and ownershipCallSucceeded and ownershipRestored == true

				local ownerCallSucceeded, networkOwner = pcall(function()
					return root:GetNetworkOwner()
				end)

				recoverySucceeded = recoverySucceeded and ownerCallSucceeded and networkOwner == activeDriver
			end
		end

		return recoverySucceeded and not suspensionIntegrityCompromised
	end

	local function fail(reason: string): (boolean, string?, boolean)
		return false, reason, recoverAcquiredState()
	end

	local function executeTransaction(): (boolean, string?, boolean)
		local stageAccepted, stageError = runStage(stageCallback, "Suspension")

		if not stageAccepted then
			return fail(stageError or "reset suspension stage failed")
		end

		-- This existing movement synchronization hook clears the authoritative
		-- longitudinal snapshot and invalidates any queued pre-reset client intent.
		cart:SetAttribute("LastServerMovementUpdate", Workspace:GetServerTimeNow())

		local stabilityAccepted, stabilityError = CartStabilityService:SuspendCart(cart, "cart reset suspension")

		if not stabilityAccepted then
			-- A failed suspension means the subsystem cannot prove its runtime
			-- health. Even if assembly and ownership recovery succeed, movement
			-- must remain fail-closed instead of resuming around an unhealthy
			-- stability record.
			suspensionIntegrityCompromised = true
			return fail(stabilityError or "stability suspension failed")
		end

		stabilitySuspended = true

		local terrainAccepted, terrainError = CartTerrainService:SuspendCart(cart, "cart reset suspension")

		if not terrainAccepted then
			-- The same conservative policy applies when terrain suspension cannot
			-- be confirmed. Recovery resumes every successfully acquired subsystem,
			-- but this reset is not declared safe for driving.
			suspensionIntegrityCompromised = true
			return fail(terrainError or "terrain suspension failed")
		end

		terrainSuspended = true

		local mutationAccepted, revision, mutationError =
			CartAssemblyValidationService:BeginMutation(cart, "cart reset reposition")

		if not mutationAccepted or revision == nil then
			return fail(mutationError or "assembly mutation could not begin")
		end

		mutationRevision = revision

		stageAccepted, stageError = runStage(stageCallback, "Reposition")

		if not stageAccepted then
			return fail(stageError or "reset reposition stage failed")
		end

		if assignedContext then
            if not assignedContext.Validate() then return fail("Assigned return authority changed") end
            local clear,reason=CartLocalPlacement.ValidateAssignedSpawn(cart,targetCFrame,assignedContext.Assignment)
            if not clear then return fail(reason or "Assigned return blocked") end
        end
		if localPlan then
			local clear, reason = CartLocalPlacement.Revalidate(localPlan)
			if not clear then
				return fail(reason or "local pose no longer clear")
			end
		end

		local mutationSucceeded, physicalError = pcall(function()
			CartModelUtility.SetAnchored(cart, true)
			CartModelUtility.ZeroVelocities(cart)
			cart:PivotTo(targetCFrame)
			CartModelUtility.ZeroVelocities(cart)
			CartModelUtility.SetRootAnchoredOnly(cart, false)
			CartModelUtility.ZeroVelocities(cart)
		end)

		if not mutationSucceeded then
			return fail(string.format("physical reposition failed: %s", tostring(physicalError)))
		end

		stageAccepted, stageError = runStage(stageCallback, "Recovery")

		if not stageAccepted then
			return fail(stageError or "reset recovery stage failed")
		end

		local validationCallSucceeded, assemblyValid, _result, validationError = pcall(function()
			return CartAssemblyValidationService:CompleteMutation(
				cart,
				mutationRevision :: number,
				"PostReset",
				"cart reset recovery",
				true
			)
		end)

		mutationCompleted = validationCallSucceeded

		if not validationCallSucceeded then
			return fail(string.format("post-reset validation errored: %s", tostring(assemblyValid)))
		end

		if not assemblyValid then
			return fail(validationError or summarizeAssemblyFailure(cart))
		end

		contextValid, contextError = validateDriverContext(cart, root, driver, true, allowDriverless, assignedContext)

		if not contextValid then
			return fail(contextError or "driver context changed during recovery")
		end

		if localPlan then
			-- Keep propulsion suspended while gravity settles the same assembly.
			-- The existing Burst service stops through ResetActive without refilling.
			local settleStart = Workspace:GetServerTimeNow()
			repeat
				task.wait(0.1)
				if not isLiveCart(cart, root) then
					return fail("cart disappeared while settling")
				end
				if CartLocalPlacement.IsSupported(cart) and math.abs(root.AssemblyLinearVelocity.Y) < 2 then
					break
				end
			until Workspace:GetServerTimeNow() - settleStart >= CartLocalCorrection.MaximumSettleSeconds
		end

		local terrainResumed, terrainResumeError = CartTerrainService:ResumeCart(cart, "cart reset recovery")

		if not terrainResumed then
			return fail(terrainResumeError or "terrain resume failed")
		end

		terrainSuspended = false

		local stabilityResumed, stabilityResumeError = CartStabilityService:ResumeCart(cart, "cart reset recovery")

		if not stabilityResumed then
			return fail(stabilityResumeError or "stability resume failed")
		end

		stabilitySuspended = false

		if not CartOccupantService:RestoreNetworkOwnership(cart, "cart reset recovery") then
			return fail("driver network ownership could not be restored")
		end

		contextValid, contextError = validateDriverContext(cart, root, driver, true, allowDriverless, assignedContext)

		if not contextValid then
			return fail(contextError or "driver context changed before resume")
		end

		local ownerCallSucceeded, networkOwner = pcall(function()
			return root:GetNetworkOwner()
		end)

		if not ownerCallSucceeded or networkOwner ~= driver then
			return fail("cart network ownership does not match the retained driver")
		end

		stageAccepted, stageError = runStage(stageCallback, "Resume")

		if not stageAccepted then
			return fail(stageError or "reset resume stage failed")
		end

		if not localPlan then
			CartModelUtility.ZeroVelocities(cart)
		end
		if allowDriverless or localPlan then
			-- Regional returns are committed server repositioning. The movement
			-- validator must clear an earlier pending position correction only
			-- after assembly, ownership and all resume checks have succeeded.
			cart:SetAttribute("LastServerReset", Workspace:GetServerTimeNow())
		end

		return true, nil, true
	end

	local callSucceeded, transactionSucceeded, transactionError, safeToResume = pcall(executeTransaction)

	if not callSucceeded then
		return fail(string.format("reset transaction errored: %s", tostring(transactionSucceeded)))
	end

	return transactionSucceeded, transactionError, safeToResume
end

-- Legacy entry point rejects all registered-spawn requests.
function CartResetExecutor.Execute(
	_cart: Model,
	_spawn: CFrame,
	_driver: Player,
	_callback: StageCallback?
): (boolean, string?, boolean)
	return false, "Manual reset removed", true
end

function CartResetExecutor.ExecuteLocal(
	cart: Model,
	plan: any,
	driver: Player,
	callback: StageCallback?
): (boolean, string?, boolean)
	if plan.cart ~= cart or plan.driver ~= driver then
		return false, "local plan context mismatch", true
	end
	return execute(cart, plan.frame, driver, callback, false, plan)
end

-- Server-only access corrections use actual registry occupancy and an exact
-- validated exterior frame. No owner claim, death/drop policy or cargo change.
function CartResetExecutor.CorrectRegionEntry(
	cart: Model,
	exterior: CFrame,
	stageCallback: StageCallback?
): (boolean, string?, boolean)
	return execute(cart, exterior, CartOccupantService:GetDriver(cart), stageCallback, true)
end

-- The timed wipe supplies an exact private generation/assignment proof. No
-- player remote, legacy ResetCart request or local correction can create it.
function CartResetExecutor.ReturnAssignedForWipe(cart: Model, frame: CFrame, context: any): (boolean,string?,boolean)
    if type(context)~="table" or type(context.Validate)~="function" or not context.Validate() then
        return false,"Invalid timed return authority",true
    end
    return execute(cart,frame,CartOccupantService:GetDriver(cart),nil,true,nil,context)
end

-- Drive-and-Hunt (12 Nov 2026): the server moves an owner's parked, empty cart to an
-- exact frame it has already chosen (gate launch lane or call-cart spot). Same
-- suspension, assembly-mutation and clearance proof as the timed return; no player
-- remote supplies the frame, and an occupied cart is refused.
function CartResetExecutor.RelocateParked(cart: Model, frame: CFrame, context: any): (boolean, string?, boolean)
	if type(context) ~= "table" or type(context.Validate) ~= "function" or not context.Validate() then
		return false, "Invalid relocation authority", true
	end
	if CartOccupantService:GetDriver(cart) ~= nil or #CartOccupantService:GetOccupants(cart) > 0 then
		return false, "Cart is occupied", true
	end
	return execute(cart, frame, nil, nil, true, nil, { Validate = context.Validate, Assignment = nil })
end

return CartResetExecutor
