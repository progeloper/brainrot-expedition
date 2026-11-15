--!strict
-- Client observations are bounded diagnostics, never gameplay authority.
local Rules = { MaximumSamples = 600, WindowSeconds = 60, MinimumReportInterval = 55 }
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value: any, maximum: number): boolean
	return finite(value) and value >= 0 and value % 1 == 0 and value <= maximum
end
local pickupCategories = {}
for category, reasons in
	{
		PickupOutOfRange = { "OUT_OF_REACH", "OBSTRUCTED" },
		PickupNotSleeping = { "NOT_SLEEPING_WORLD" },
		PickupBusy = { "ALREADY_CARRYING", "DRIVING", "BUSY", "BANK_SAVE_PENDING", "DAZED", "NOT_READY", "Saving" },
		PickupProtected = {
			"BANKED_PROTECTED",
			"RegionAccessRequired",
			"ProtectedTarget",
			"NewbieProtected",
			"ProtectionOptOutRequired",
		},
		PickupStale = { "STALE_ID", "OWNERSHIP_CHANGED", "INVALID_TARGET" },
	}
do
	for _, reason in reasons do
		pickupCategories[reason] = category
	end
end
function Rules.PickupCategory(reason: any): string
	return pickupCategories[reason] or "PickupOther"
end
local assetFailureCategories = table.freeze({
	RIFT_NOT_RESIDENT = true,
	RIFT_FETCH_FAILED = true,
	RIFT_REFERENCE_INVALID = true,
	RIFT_PRELOAD_TIMEOUT = true,
})
function Rules.ValidateAssetFailure(report: any): string?
	if type(report) ~= "table" or report.kind ~= "CinematicAsset" or not assetFailureCategories[report.category] then
		return nil
	end
	local count = 0
	for key in report do
		count += 1
		if count > 2 or (key ~= "kind" and key ~= "category") then
			return nil
		end
	end
	return report.category
end
function Rules.Summarize(samples: { number }): any?
	if #samples == 0 or #samples > Rules.MaximumSamples then
		return nil
	end
	local sorted = {}
	local bands = { 0, 0, 0, 0 }
	for _, sample in samples do
		if not finite(sample) or sample <= 0 or sample > 2000 then
			return nil
		end
		table.insert(sorted, sample)
		local index = if sample <= 16.667 then 1 elseif sample <= 33.334 then 2 elseif sample <= 50 then 3 else 4
		bands[index] += 1
	end
	table.sort(sorted)
	return {
		sampleCount = #sorted,
		p50Ms = sorted[math.max(1, math.ceil(#sorted * 0.5))],
		p90Ms = sorted[math.max(1, math.ceil(#sorted * 0.9))],
		bands = bands,
	}
end
function Rules.Validate(report: any): (any?, string?)
	if type(report) ~= "table" then
		return nil, "INVALID_REPORT"
	end
	local allowed = {
		windowSeconds = true,
		sampleCount = true,
		p50Ms = true,
		p90Ms = true,
		bands = true,
		memoryMB = true,
		streamPauseSeconds = true,
		graphicsTier = true,
		visibility = true,
		focusKnown = true,
		focused = true,
	}
	for key in report do
		if not allowed[key] then
			return nil, "UNKNOWN_FIELD"
		end
	end
	if
		not finite(report.windowSeconds)
		or report.windowSeconds < 55
		or report.windowSeconds > 120
		or not integer(report.sampleCount, 600)
		or report.sampleCount < 1
		or not finite(report.p50Ms)
		or report.p50Ms <= 0
		or report.p50Ms > 2000
		or not finite(report.p90Ms)
		or report.p90Ms < report.p50Ms
		or report.p90Ms > 2000
		or (report.graphicsTier ~= nil and not integer(report.graphicsTier, 10))
	then
		return nil, "INVALID_WINDOW"
	end
	if
		(report.focusKnown ~= nil and type(report.focusKnown) ~= "boolean")
		or (report.focused ~= nil and type(report.focused) ~= "boolean")
		or (report.focusKnown == true and report.focused == nil)
		or (report.focusKnown ~= true and report.focused ~= nil)
	then
		return nil, "INVALID_FOCUS"
	end
	if report.memoryMB ~= nil and (not finite(report.memoryMB) or report.memoryMB <= 0 or report.memoryMB > 100000) then
		return nil, "INVALID_MEMORY"
	end
	if
		report.streamPauseSeconds ~= nil
		and (
			not finite(report.streamPauseSeconds)
			or report.streamPauseSeconds < 0
			or report.streamPauseSeconds > report.windowSeconds
		)
	then
		return nil, "INVALID_PAUSE"
	end
	if type(report.bands) ~= "table" then
		return nil, "INVALID_BANDS"
	end
	local sum = 0
	local bandCount = 0
	for key, value in report.bands do
		if not integer(key, 4) or key < 1 or not integer(value, 600) then
			return nil, "INVALID_BANDS"
		end
		sum += value
		bandCount += 1
	end
	if bandCount ~= 4 or sum ~= report.sampleCount then
		return nil, "INVALID_BANDS"
	end
	local visibility = report.visibility
	if type(visibility) ~= "table" then
		return nil, "INVALID_VISIBILITY"
	end
	local caps = {
		visible = 4096,
		detailed = 4096,
		reduced = 4096,
		hidden = 4096,
		interestSubscriptions = 8,
		renderDistance = 1000,
	}
	local optionalCaps = {
		interestEntries = 1000000,
		interestExits = 1000000,
		authorityProxies = 4096,
		localFullModels = 4096,
		localReducedModels = 4096,
		cacheParts = 65536,
	}
	local cleanVisibility = {}
	for key, value in visibility do
		if not (caps[key] or optionalCaps[key]) or not integer(value, caps[key] or optionalCaps[key]) then
			return nil, "INVALID_VISIBILITY"
		end
		cleanVisibility[key] = value
	end
	for key in caps do
		if cleanVisibility[key] == nil then
			return nil, "INVALID_VISIBILITY"
		end
	end
	if cleanVisibility.detailed + cleanVisibility.reduced ~= cleanVisibility.visible then
		return nil, "INVALID_VISIBILITY"
	end
	return {
		windowSeconds = report.windowSeconds,
		sampleCount = report.sampleCount,
		p50Ms = report.p50Ms,
		p90Ms = report.p90Ms,
		memoryMB = report.memoryMB,
		streamPauseSeconds = report.streamPauseSeconds,
		graphicsTier = report.graphicsTier,
		bands = table.clone(report.bands),
		visibility = cleanVisibility,
		focusKnown = report.focusKnown == true,
		focused = report.focused,
	},
		nil
end
return table.freeze(Rules)
