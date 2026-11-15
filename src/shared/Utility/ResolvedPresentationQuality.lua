--!strict
-- One local publisher owns the effective presentation tier. This pure module
-- creates no connections, jobs, Instances, settings writes or replication.
local function validTier(value: any): boolean
	return value == "Low" or value == "Medium" or value == "High"
end
local function create()
	local owner: any = nil
	local resolved = "Low"
	local revision = 0
	local api = {}
	function api.Begin(initialTier: any): any
		owner = {}
		resolved = if validTier(initialTier) then initialTier else "Low"
		revision += 1
		return owner
	end
	function api.Publish(token: any, tier: any): boolean
		if owner == nil or token ~= owner or not validTier(tier) then
			return false
		end
		if resolved ~= tier then
			resolved = tier
			revision += 1
		end
		return true
	end
	function api.Release(token: any): boolean
		if owner == nil or token ~= owner then
			return false
		end
		owner, resolved = nil, "Low"
		revision += 1
		return true
	end
	function api.GetTier(fallbackPreference: any): string
		if owner ~= nil then
			return resolved
		end
		-- Until/after the existing presenter runs, preserve explicit manual
		-- preference; Auto/unknown uses the policy's conservative Low default.
		return if validTier(fallbackPreference) then fallbackPreference else "Low"
	end
	function api.GetPlatformDetailCap(fallbackPreference: any): number
		return if api.GetTier(fallbackPreference) == "Low" then 24 else 48
	end
	function api.GetDiagnostics(fallbackPreference: any): any
		return {
			publisherActive = owner ~= nil,
			effectiveTier = api.GetTier(fallbackPreference),
			platformDetailCap = api.GetPlatformDetailCap(fallbackPreference),
			revision = revision,
			ownedConnections = 0,
			ownedJobs = 0,
		}
	end
	return api
end
local state = create()
state.new = create
return state
