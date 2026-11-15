--!strict
-- Shared preview/runtime finish contract. Only color changes; functional ownership is separate.
local Config = require(script.Parent.Parent.Config.Phase13)
local Commerce = require(script.Parent.Phase13CommerceRules)
local Definitions = require(script.Parent.Parent.Config.Phase13OptionalFinishes).Finishes
local Roles = require(script.Parent.Phase13FinishRoles)
local AttachmentCosmetics = require(script.Parent.Phase14CosmeticRules)
local Rules = {}
Rules.RequiredPerks = table.freeze({
	VIP = table.freeze({ "VIPChat", "VIPBadge", "VIPTitle", "BaseFinish", "CartFinish", "WeaponFinish", "RiftVariant" }),
	STARTER_PACK = table.freeze({ "StarterCashOnce", "TrailblazerCart", "TrailblazerWeapon" }),
})
local valid = {
	VIPBadge = { On = true, Off = true },
	VIPTitle = { On = true, Off = true },
	VIPChat = { On = true, Off = true },
	BaseFinish = { Default = true, Riftgold = true, FIN_AURORA = true },
	CartFinish = { Default = true, Riftgold = true, Trailblazer = true, FIN_GLACIER = true },
	WeaponFinish = { Default = true, Riftgold = true, Trailblazer = true, FIN_PRISM = true },
	RiftVariant = { Default = true, Riftgold = true, FIN_SINGULARITY = true },
}
function Rules.CanSelect(data: any, key: string, value: string): (boolean, string?)
	if AttachmentCosmetics.IsSlot(key) then return AttachmentCosmetics.CanSelect(data, key, value) end
	if not valid[key] or not valid[key][value] then
		return false, "INVALID_SELECTION"
	end
	if Definitions[value] then
		return Commerce.HasEntitlement(data, value), if Commerce.HasEntitlement(data, value) then nil else "NOT_OWNED"
	end
	if
		value ~= "Default"
		and value ~= "Off"
		and not Commerce.HasEntitlement(data, if value == "Trailblazer" then "STARTER_PACK" else "VIP")
	then
		return false, "NOT_OWNED"
	end
	return true, nil
end
function Rules.ResolveFinish(data: any, category: string, id: string): string
	local p = data and data.Phase13
	local map = if p
		then p[if category == "Weapon"
			then "OwnedWeaponIds"
			elseif category == "Cart" then "OwnedCartIds"
			else "OwnedBaseDesigns"]
		else nil
	if not map or map[id] ~= true then
		return "Default"
	end
	local finish = data.Commerce and data.Commerce.Appearance and data.Commerce.Appearance[category .. "Finish"]
	if Definitions[finish] and Definitions[finish].Category == category and Commerce.HasEntitlement(data, finish) then
		return finish
	end
	if finish == "Riftgold" and Commerce.HasEntitlement(data, "VIP") then
		return finish
	end
	if
		finish == "Trailblazer"
		and Commerce.HasEntitlement(data, "STARTER_PACK")
		and (
			(category == "Weapon" and id == Config.InitialWeaponId)
			or (category == "Cart" and id == Config.InitialCartId)
		)
	then
		return finish
	end
	return "Default"
end
function Rules.Color(original: Color3, finish: string, partName: string, role: string?): Color3
	if Definitions[finish] then
		return Definitions[finish].Palette[role or ""] or original
	end
	if finish == "Riftgold" then
		return original:Lerp(Color3.fromRGB(244, 189, 65), 0.55)
	end
	if finish == "Trailblazer" then
		local hash = 0
		for i = 1, #partName do
			hash += string.byte(partName, i)
		end
		return if partName == "Handle" or hash % 2 == 0
			then Color3.fromRGB(28, 153, 157)
			else Color3.fromRGB(242, 129, 41)
	end
	return original
end
function Rules.Apply(model: Instance, finish: string, category: string?, templateId: string?): (number, any)
	local count = 0
	local diagnostics = { unmapped = {}, atlasBlocked = {}, protected = 0 }
	local definition = Definitions[finish]
	local function arcadeSurface(part)
		return if part:IsA("MeshPart") and part:GetAttribute("ArcadeVisualRevision") == 3
			then part:FindFirstChildOfClass("SurfaceAppearance")
			else nil
	end
	local function nativeCSG(part)
		return part:IsA("UnionOperation") and part:GetAttribute("ArcadeVisualRevision") == 3
			and part:GetAttribute("NativeVehicleConstruction") == "CSG"
	end
	local function restoreArcadeTint(part)
		local surface = arcadeSurface(part)
		local original = surface and surface:GetAttribute("Phase13FinishOriginalTint")
		if surface and typeof(original) == "Color3" then surface.Color = original end
		if nativeCSG(part) then
			local color = part:GetAttribute("Phase13CSGOriginalColor")
			local usePartColor = part:GetAttribute("Phase13CSGOriginalUsePartColor")
			if typeof(color) == "Color3" then part.Color = color end
			if type(usePartColor) == "boolean" then part.UsePartColor = usePartColor end
		end
	end
	local function apply(part)
		if not part:IsA("BasePart") or part.Transparency >= 1 then
			return
		end
		local role = if definition and category and templateId then Roles.Resolve(model, part, category, templateId) else nil
		if definition then
			if definition.Category ~= category or not role then
				diagnostics.protected += 1
				local original = part:GetAttribute("Phase13FinishOriginalColor")
				if typeof(original) == "Color3" then part.Color = original end
				restoreArcadeTint(part)
				if #diagnostics.unmapped < 64 then table.insert(diagnostics.unmapped, part.Name) end
				return
			end
			if nativeCSG(part) or (part:IsA("MeshPart") and (part.TextureID ~= "" or part:FindFirstChildOfClass("SurfaceAppearance"))) then
				local original = part:GetAttribute("Phase13FinishOriginalColor")
				if typeof(original) == "Color3" then part.Color = original end
				restoreArcadeTint(part)
				if #diagnostics.atlasBlocked < 64 then table.insert(diagnostics.atlasBlocked, part.Name) end
				return -- A flat tint is not a matching-UV atlas variant.
			end
		end
		-- Native unions preserve their authored face colors for Default. Existing
		-- required finishes intentionally tint each combined body/wheel as one role.
		if nativeCSG(part) then
			local originalColor = part:GetAttribute("Phase13CSGOriginalColor")
			local originalUse = part:GetAttribute("Phase13CSGOriginalUsePartColor")
			if typeof(originalColor) ~= "Color3" then
				originalColor = part.Color
				part:SetAttribute("Phase13CSGOriginalColor", originalColor)
			end
			if type(originalUse) ~= "boolean" then
				originalUse = part.UsePartColor
				part:SetAttribute("Phase13CSGOriginalUsePartColor", originalUse)
			end
			if finish ~= "Riftgold" and finish ~= "Trailblazer" then
				part.Color = originalColor
				part.UsePartColor = originalUse
			else
				local alias = part:GetAttribute("Phase13FinishAlias")
				part.UsePartColor = true
				part.Color = Rules.Color(originalColor, finish, if type(alias) == "string" then alias else part.Name, role)
			end
			count += 1
			return
		end
		-- Atlas colors/material maps remain authored. Existing VIP/Starter finishes
		-- target SurfaceAppearance.Color, leaving mesh color, bind size and physics alone.
		local surface = arcadeSurface(part)
		if surface then
			local originalTint = surface:GetAttribute("Phase13FinishOriginalTint")
			if typeof(originalTint) ~= "Color3" then
				originalTint = surface.Color
				surface:SetAttribute("Phase13FinishOriginalTint", originalTint)
			end
			local alias = part:GetAttribute("Phase13FinishAlias")
			surface.Color = Rules.Color(originalTint, finish, if type(alias) == "string" then alias else part.Name, role)
			count += 1
			return
		end
		local original = part:GetAttribute("Phase13FinishOriginalColor")
		if typeof(original) ~= "Color3" then
			original = part.Color
			part:SetAttribute("Phase13FinishOriginalColor", original)
		end
		part.Color = Rules.Color(original, finish, part.Name, role)
		count += 1
	end
	apply(model)
	for _, part in model:GetDescendants() do
		apply(part)
	end
	return count, diagnostics
end
function Rules.ResolveRift(data: any, defaultAsset: any): (any, string, string?)
	local selected = data and data.Commerce and data.Commerce.Appearance and data.Commerce.Appearance.RiftVariant
	if selected == "FIN_SINGULARITY" and Commerce.HasEntitlement(data, selected) then
		local definition = Definitions.FIN_SINGULARITY
		if definition.ReadyForRuntime == true and definition.ImportedDimensionsVerified == true and type(definition.TextureWidth) == "number" and type(definition.TextureHeight) == "number" and type(definition.TextureAssetId) == "string" and definition.TextureAssetId:match("^rbxassetid://%d+$") then
			return { Installed = true, PrimaryImage = definition.TextureAssetId, Width = definition.TextureWidth, Height = definition.TextureHeight, VerticalLongAxis = true, AngleDegrees = 0 }, selected, nil
		end
		return defaultAsset, "Default", "OPTIONAL_RIFT_UNAVAILABLE"
	end
	if (selected == nil or selected == "Riftgold") and Commerce.HasEntitlement(data, "VIP") then
		return defaultAsset, "Riftgold", nil
	end
	return defaultAsset, "Default", nil
end
return table.freeze(Rules)
