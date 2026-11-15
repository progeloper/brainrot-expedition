--!strict

local Effects = require(script.Parent.Parent.Config.ChariotEffectDefinitions)
local Text = {}

local function number(value: number?, precision: number?): string
	return (string.format("%." .. tostring(precision or 4) .. "f", value or 0):gsub("0+$", ""):gsub("%.$", ""))
end

function Text.Value(effect: string?, value: number?): string
	local definition = Effects.Get(effect)
	if not definition then return "Unavailable" end
	if effect == "Speed" then return "+" .. number((value or 0) * 100) .. "%" end
	if effect == "Hit" then return "×" .. number(1 + (value or 0)) end
	if effect == "Shield" then return tostring(value or 0) .. (if value == 1 then " charge" else " charges") end
	return number(value) .. " seconds"
end

function Text.Trait(row: any): string
	if (row.grant or 1) <= 1 then return "No rare trait" end
	local target = row.amplifierTarget or row.effect
	local definition = Effects.Get(target)
	return "Top " .. tostring(row.grant) .. " " .. (if definition then definition.DisplayName else "Unavailable") .. " trait"
end

function Text.Description(row: any): string
	local definition = Effects.Get(row.effect)
	local result = if definition then definition.Description else "This effect is unavailable."
	local target = row.amplifierTarget or row.effect
	if (row.grant or 1) > 1 then
		local amplified = Effects.Get(target)
		result ..= "\nAllows the best " .. tostring(row.grant) .. " equipped "
			.. (if amplified then amplified.DisplayName else "Unavailable") .. " providers to contribute."
		if target == "Shield" and row.effect ~= "Shield" then
			result ..= " This member's primary effect supplies no Shield charge."
		end
	end
	return result
end

function Text.Member(detail: any, stats: any): string?
	if detail and detail.effect == "Shield" and detail.status == "below_limit" then
		local limit = stats and stats.limits and stats.limits.Shield or 1
		return if limit <= 1 then "A Shield amplifier is needed" else "Shield contribution limit reached"
	end
	return nil
end

function Text.Totals(stats: any, effective: any): string
	local limits = stats.limits or {}
	local lines = {}
	for _, definition in Effects.Ordered do
		local id = definition.Id
		local limit = limits[id] or 1
		local line
		if id == "Speed" then
			line = definition.DisplayName .. " +" .. number(effective.percent.speed, 2) .. "% ("
				.. number(effective.speed, 2) .. " studs/s) · best " .. limit .. " · cap +10%"
				.. (if effective.clipped.speed then " · physical limit" else "")
		elseif id == "Hit" then
			line = definition.DisplayName .. " ×" .. number(stats[definition.Stat]) .. " · best " .. limit .. " · cap ×5"
		elseif id == "Shield" then
			line = definition.DisplayName .. " capacity " .. tostring(stats[definition.Stat] or 0)
				.. " charges · best " .. limit .. " · cap " .. definition.Cap
		else
			line = definition.DisplayName .. " " .. number(stats[definition.Stat]) .. " s · best " .. limit .. " · cap " .. definition.Cap .. " s"
		end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

function Text.Reserve(shield: any, now: number): string
	if type(shield) ~= "table" then return "Current Shield reserve unavailable." end
	local result = "Current Shield reserve " .. tostring(shield.remaining or 0) .. "/" .. tostring(shield.capacity or 0) .. "."
	if (shield.protectedUntil or 0) > now then result ..= " Cargo protection finishes at its original deadline." end
	return result .. " Capacity previews do not promise a refill; Shield refills at your own base."
end

return table.freeze(Text)
