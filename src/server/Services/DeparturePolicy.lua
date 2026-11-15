--!strict

-- Phase 7A-3 policy boundary. This table contains only outcomes explicitly
-- established by the current task. Observed legacy behaviour is deliberately
-- not promoted to an approved persistence rule.

local Phase10 = require(game:GetService("ReplicatedStorage").Shared.Config.Phase10)

local DeparturePolicy = {}

DeparturePolicy.Events = table.freeze({
	CharacterDeath = "CharacterDeath",
	CharacterReset = "CharacterReset",
	PlayerLogout = "PlayerLogout",
	ServerShutdown = "ServerShutdown",
	DeliberateWorldDrop = "DeliberateWorldDrop",
	OccupiedSlotReplacement = "OccupiedSlotReplacement",
	CartReplacement = "CartReplacement",
	RejoinUnassigned = "RejoinUnassigned",
	ReturnToSlot = "ReturnToSlot",
	BaseReassignment = "BaseReassignment",
	RuntimeTeardown = "RuntimeTeardown",
})

DeparturePolicy.AssetClasses = table.freeze({
	FreshUnbanked = "FreshUnbanked",
	Banked = "Banked",
	StoredDisplay = "StoredDisplay",
	ReleasedWorld = "ReleasedWorld",
	TemporaryEffect = "TemporaryEffect",
})

DeparturePolicy.Locations = table.freeze({
	Carried = "Carried",
	CartCargo = "CartCargo",
	World = "World",
	Stored = "Stored",
})

local APPROVED: { [string]: { [string]: string } } = {
	RejoinUnassigned = {
		Banked = "ReturnToAvailableSlotOrDestroy",
	},
	CharacterDeath = {
		FreshUnbanked = "DestroyFresh",
		Banked = "ReturnToAvailableSlotOrConfirmedRelease",
		StoredDisplay = "PreserveSavedState",
		TemporaryEffect = "RemoveRuntimeVisual",
		ReleasedWorld = "NoOwnershipChange",
	},
	CharacterReset = {
		FreshUnbanked = "DestroyFresh",
		Banked = "ReturnToAvailableSlotOrConfirmedRelease",
		StoredDisplay = "PreserveSavedState",
		TemporaryEffect = "RemoveRuntimeVisual",
		ReleasedWorld = "NoOwnershipChange",
	},
	DeliberateWorldDrop = {
		FreshUnbanked = "PublishExistingWorldDrop",
		Banked = "ConfirmedOwnershipRelinquishment",
		ReleasedWorld = "AlreadyReleased",
	},
	CartReplacement = {
		FreshUnbanked = "PreserveAuthoritativeCargo",
		Banked = "PreserveAuthoritativeCargo",
		TemporaryEffect = "RemoveRuntimeVisual",
	},
	BaseReassignment = {
		StoredDisplay = "RebindSavedState",
		TemporaryEffect = "RemoveRuntimeVisual",
	},
	RuntimeTeardown = {
		StoredDisplay = "RemoveRuntimeVisual",
		TemporaryEffect = "RemoveRuntimeVisual",
		ReleasedWorld = "NoOwnershipChange",
	},
}

local LOGOUT_BY_LOCATION: { [string]: { [string]: string } } = {
	Carried = {
		FreshUnbanked = "PublishExistingWorldDrop",
		Banked = "ReturnToAvailableSlotOrDestroy",
	},
	CartCargo = {
		FreshUnbanked = "PublishExistingWorldDrop",
		Banked = "DestroyOwned",
	},
}

if Phase10.Enabled then
	for _, event in { "CharacterDeath", "CharacterReset", "CartReplacement" } do
		APPROVED[event].FreshUnbanked = "PublishExistingWorldDrop"
	end
	APPROVED.DeliberateWorldDrop.Banked = "PublishSecuredOwnedDrop"
	APPROVED.CharacterDeath.Banked = "ReturnToAvailableSlotOrSecuredDrop"
	APPROVED.CharacterReset.Banked = "ReturnToAvailableSlotOrSecuredDrop"
	APPROVED.CartReplacement.Banked = "ReturnToAvailableSlotOrRetainOwned"
	APPROVED.RejoinUnassigned.Banked = "ReturnToAvailableSlotOrRetainOwned"
	LOGOUT_BY_LOCATION.Carried.Banked = "ReturnToAvailableSlotOrRetainOwned"
	LOGOUT_BY_LOCATION.CartCargo.Banked = "ReturnToAvailableSlotOrRetainOwned"
end

local function validEnum(enum: { [string]: string }, value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	for _, member in enum do
		if member == value then
			return true
		end
	end
	return false
end

function DeparturePolicy.Resolve(event: any, assetClass: any, location: any?): any
	if not validEnum(DeparturePolicy.Events, event) then
		return table.freeze({ ok = false, code = "INVALID_EVENT" })
	end
	if not validEnum(DeparturePolicy.AssetClasses, assetClass) then
		return table.freeze({ ok = false, code = "INVALID_ASSET_CLASS" })
	end
	local action = nil
	if
		event == DeparturePolicy.Events.PlayerLogout
		or event == DeparturePolicy.Events.ServerShutdown
	then
		local locationPolicy = if type(location) == "string"
			then LOGOUT_BY_LOCATION[location]
			else nil
		action = if locationPolicy then locationPolicy[assetClass] else nil
		if action == nil and (assetClass == "FreshUnbanked" or assetClass == "Banked") then
			return table.freeze({
				ok = false,
				code = if locationPolicy == nil
					then "POLICY_CONTEXT_REQUIRED"
					else "POLICY_REQUIRED",
				event = event,
				assetClass = assetClass,
				location = location,
			})
		end
	else
		action = if APPROVED[event] then APPROVED[event][assetClass] else nil
	end
	if action == nil then
		return table.freeze({
			ok = false,
			code = "POLICY_REQUIRED",
			event = event,
			assetClass = assetClass,
		})
	end
	return table.freeze({
		ok = true,
		code = "APPROVED",
		event = event,
		assetClass = assetClass,
		location = location,
		action = action,
	})
end

-- Pure validation helper used by the lifecycle coordinator and deterministic
-- tests. It never scans Models and never invents a default consequence.
function DeparturePolicy.BuildPlan(items: { any }): any
	if type(items) ~= "table" then
		return table.freeze({ ok = false, code = "INVALID_ITEMS" })
	end
	local seen: { [string]: any } = {}
	local actions = {}
	local unresolved = {}
	for _, item in items do
		local individualId = item and item.individualId
		if type(individualId) ~= "string" or individualId == "" then
			return table.freeze({ ok = false, code = "INVALID_INDIVIDUAL_ID" })
		end
		local decision = DeparturePolicy.Resolve(item.event, item.assetClass, item.location)
		local prior = seen[individualId]
		if prior ~= nil then
			if
				prior.event ~= item.event
				or prior.assetClass ~= item.assetClass
				or prior.location ~= item.location
			then
				return table.freeze({
					ok = false,
					code = "CONTRADICTORY_OUTCOMES",
					individualId = individualId,
				})
			end
			continue
		end
		seen[individualId] = item
		local record = table.freeze({
			individualId = individualId,
			event = item.event,
			assetClass = item.assetClass,
			location = item.location,
			action = decision.action,
			code = decision.code,
		})
		if decision.ok then
			table.insert(actions, record)
		else
			table.insert(unresolved, record)
		end
	end
	return table.freeze({
		ok = #unresolved == 0,
		code = if #unresolved == 0 then "APPROVED" else "POLICY_REQUIRED",
		actions = table.freeze(actions),
		unresolved = table.freeze(unresolved),
	})
end

return table.freeze(DeparturePolicy)
