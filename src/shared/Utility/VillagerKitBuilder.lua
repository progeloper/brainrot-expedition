--!strict
-- Builds a villager visual from a V4 box kit (boxes only). Shared by the native template
-- installer (Studio) and the client fallback, so both produce identical geometry.
-- Kit space: studs, y up, ground at y = 0, the villager faces -Z.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Config.VoxelCreaturePalette)

local Builder = {}

export type Box = {
	slot: string,
	min: { number },
	max: { number },
	role: string,
	relief: boolean?,
	emissive: boolean?,
	color: string?,
	group: string?,
}

local EYE_WHITE = "#FFFFFF"
local PUPIL = "#1A0B06"
local LASH = "#140A0A"

local function box(slot, x0, y0, z0, x1, y1, z1, role, extra: any?): Box
	local result: any = {
		slot = slot,
		min = { math.min(x0, x1), math.min(y0, y1), math.min(z0, z1) },
		max = { math.max(x0, x1), math.max(y0, y1), math.max(z0, z1) },
		role = role,
	}
	if extra then
		for key, value in extra do
			result[key] = value
		end
	end
	return result
end
Builder.Box = box

-- Mirror a list of boxes across x = 0, renaming L <-> R in slot and group names.
function Builder.Mirror(boxes: { Box }): { Box }
	local out = {}
	for _, item in boxes do
		local copy: any = table.clone(item)
		copy.min = { -item.max[1], item.min[2], item.min[3] }
		copy.max = { -item.min[1], item.max[2], item.max[3] }
		copy.slot = string.gsub(item.slot, "_L$", "_R")
		if item.group then
			copy.group = string.gsub(item.group, "L$", "R")
		end
		table.insert(out, copy)
	end
	return out
end

-- V4 anime eye (Palette.Eye proportions) on a face plane facing -Z, with a grumpy
-- tilted lash (inner end drooping, outer wing flicked up). No blush on villagers.
-- Pupils stay centred in each iris, so the eyes never cross.
function Builder.Eye(
	cx: number,
	cy: number,
	faceZ: number,
	w: number,
	h: number,
	family: string
): { Box }
	local E = Palette.Eye
	local iris = Palette.IrisFamilies[family] or Palette.IrisFamilies.Amber
	local out: { Box } = {}
	local tag = if cx < 0 then "_L" else "_R"
	local function layer(z0: number, z1: number): (number, number)
		return faceZ - z0, faceZ - z1
	end
	-- White: core (full height) + wide (inset top/bottom).
	local coreW = w * (E.WhiteCore.L / E.WhiteWide.L)
	local za, zb = layer(0, E.Proud.white)
	table.insert(
		out,
		box(
			"EyeWhiteCore" .. tag,
			cx - coreW / 2,
			cy - h / 2,
			za,
			cx + coreW / 2,
			cy + h / 2,
			zb,
			"Protected",
			{ color = EYE_WHITE }
		)
	)
	table.insert(
		out,
		box(
			"EyeWhiteWide" .. tag,
			cx - w / 2,
			cy - h / 2 + h * E.WhiteWide.HInset,
			za,
			cx + w / 2,
			cy + h / 2 - h * E.WhiteWide.HInset,
			zb,
			"Protected",
			{ color = EYE_WHITE }
		)
	)
	-- Iris: three horizontal bands, bottom to top bright/mid/dark.
	local iw, ih = w * E.Iris.W, h * E.Iris.H
	local ibottom = cy - h / 2 + h * 0.04
	local itop = ibottom + ih
	local z0, z1 = layer(E.Proud.white, E.Proud.white + E.Proud.iris)
	local y = ibottom
	for _, band in
		{
			{ "bright", E.Iris.Bands.bright },
			{ "mid", E.Iris.Bands.mid },
			{ "dark", E.Iris.Bands.dark },
		}
	do
		local bandH = ih * band[2]
		table.insert(
			out,
			box(
				"Iris_" .. band[1] .. tag,
				cx - iw / 2,
				y,
				z0,
				cx + iw / 2,
				y + bandH,
				z1,
				"Protected",
				{ color = iris[band[1]] }
			)
		)
		y += bandH
	end
	-- Pupil, centred horizontally (aligned pupils, never crossed).
	local pw, ph = iw * E.Pupil.W, ih * E.Pupil.H
	local ptop = itop - h * 0.12
	local p0, p1 = layer(E.Proud.white + E.Proud.iris, E.Proud.white + E.Proud.iris + 0.03)
	table.insert(
		out,
		box(
			"Pupil" .. tag,
			cx - pw / 2,
			ptop - ph,
			p0,
			cx + pw / 2,
			ptop,
			p1,
			"Protected",
			{ color = PUPIL }
		)
	)
	-- Catchlights (emissive): big upper-outer, small lower-inner, sparkle upper-inner.
	local c0, c1 = layer(0.10, 0.12)
	-- Outer = away from the face centre line (x = 0).
	local outer = if cx < 0 then -1 else 1
	local bw, bh = iw * E.BigCatchlight.W, ih * E.BigCatchlight.H
	local bx = cx + outer * (pw / 2)
	table.insert(
		out,
		box(
			"CatchBig" .. tag,
			bx - bw / 2,
			ptop - bh * 0.6,
			c0,
			bx + bw / 2,
			ptop + bh * 0.4,
			c1,
			"Protected",
			{ color = EYE_WHITE, emissive = true }
		)
	)
	local sw, sh = iw * E.SmallCatchlight.W, ih * E.SmallCatchlight.H
	local sx = cx - outer * (pw * 0.35)
	table.insert(
		out,
		box(
			"CatchSmall" .. tag,
			sx - sw / 2,
			ptop - ph + sh * 0.2,
			c0,
			sx + sw / 2,
			ptop - ph + sh * 1.2,
			c1,
			"Protected",
			{ color = EYE_WHITE, emissive = true }
		)
	)
	local kw, kh = math.max(iw * E.Sparkle.W, 0.05), math.max(ih * E.Sparkle.H, 0.05)
	local kx = cx - outer * (pw * 0.2)
	table.insert(
		out,
		box(
			"Sparkle" .. tag,
			kx - kw / 2,
			ptop - kh * 1.6,
			c0,
			kx + kw / 2,
			ptop - kh * 0.6,
			c1,
			"Protected",
			{ color = EYE_WHITE, emissive = true }
		)
	)
	-- Lash: outer two thirds sits on the white top; inner third drops (grumpy tilt);
	-- outer wing flicks upward.
	local l0, l1 = layer(0, 0.14)
	local lashH = h * E.Lash.H + 0.04
	local top = cy + h / 2
	local innerEdge = cx - outer * (w / 2 + 0.04)
	local outerEdge = cx + outer * (w / 2 + 0.08)
	local split = cx - outer * (w / 6)
	table.insert(
		out,
		box(
			"LashOuter" .. tag,
			outerEdge,
			top - lashH * 0.4,
			l0,
			split,
			top + lashH * 0.6,
			l1,
			"Protected",
			{ color = LASH }
		)
	)
	table.insert(
		out,
		box(
			"LashInner" .. tag,
			split,
			top - lashH * 0.9,
			l0,
			innerEdge,
			top + lashH * 0.1,
			l1,
			"Protected",
			{ color = LASH }
		)
	)
	local wingW = w * E.Lash.Wing + 0.06
	table.insert(
		out,
		box(
			"LashWing" .. tag,
			outerEdge,
			top + lashH * 0.4,
			l0,
			outerEdge + outer * wingW,
			top + lashH * 1.5,
			l1,
			"Protected",
			{ color = LASH }
		)
	)
	return out
end

local function toColor(hex: string?): Color3
	if type(hex) ~= "string" then
		return Color3.new(1, 0, 1)
	end
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else Color3.new(1, 0, 1)
end

-- Resolve every box of a kit (+ optional per-villager variant boxes).
-- Regional variant: { add = { Box }, hide = { slot } }. The shared kit stays one shape per
-- type; a variant swaps the regional props/hat/head details on top of it.
-- Outfit: { add = { Box }, hide = { slot } } applied after the variant. Outfit boxes carry
-- `outfit = "headwear" | "top" | "bottom" | "footwear" | "accessory"` (v1.1 section 3.4).
local function applyLayer(boxes: { Box }, layer: any): { Box }
	if not layer then
		return boxes
	end
	local hidden: { [string]: boolean } = {}
	for _, slot in layer.hide or {} do
		hidden[slot] = true
	end
	local out = {}
	for _, item in boxes do
		if not hidden[item.slot] then
			table.insert(out, item)
		end
	end
	for _, item in layer.add or {} do
		table.insert(out, item)
	end
	return out
end

function Builder.Boxes(kit: any, variant: string?, outfit: any?): { Box }
	local spec = if variant and kit.variants then kit.variants[variant] else nil
	if variant and not spec then
		error(string.format("Villager kit %s has no variant %s", tostring(kit.id), variant))
	end
	return applyLayer(applyLayer(table.clone(kit.boxes), spec), outfit)
end

-- Outfit slots present on a resolved box list (for the V15 full-body check).
function Builder.OutfitSlots(boxes: { Box }): { [string]: boolean }
	local slots = {}
	for _, item in boxes do
		local slot = (item :: any).outfit
		if slot then
			slots[slot] = true
		end
	end
	return slots
end

-- Template name for a kit + variant (+ outfit set), e.g. "Sprinter", "Sprinter_Frog",
-- "Sprinter@Forest" or "Sprinter_Frog@Swamp".
function Builder.TemplateName(kitId: string, variant: string?, outfitSet: string?): string
	local name = if variant then kitId .. "_" .. variant else kitId
	return if outfitSet then name .. "@" .. outfitSet else name
end

-- Build a Model. palette maps role -> hex; Protected boxes keep their own colour.
function Builder.Build(
	kit: any,
	palette: { [string]: string },
	variant: string?,
	outfit: any?
): Model
	local model = Instance.new("Model")
	model.Name = kit.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new(0, 0.5, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	for index, item in Builder.Boxes(kit, variant, outfit) do
		local size = Vector3.new(
			item.max[1] - item.min[1],
			item.max[2] - item.min[2],
			item.max[3] - item.min[3]
		)
		local center = Vector3.new(
			item.max[1] + item.min[1],
			item.max[2] + item.min[2],
			item.max[3] + item.min[3]
		) / 2
		local part = Instance.new("Part")
		part.Name = item.slot
		part.Size =
			Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
		part.CFrame = CFrame.new(center)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = item.role ~= "Protected"
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local role = item.role
		part.Color = if role == "Protected"
			then toColor(item.color)
			else toColor(palette[role] or palette.cloth)
		if item.emissive or role == "glow" then
			part.Material = Enum.Material.Neon
		else
			part.Material = Enum.Material.SmoothPlastic
			if item.relief then
				part.MaterialVariant = Palette.Studs.MaterialVariant
			end
		end
		part:SetAttribute("Role", role)
		part:SetAttribute("Slot", item.slot)
		part:SetAttribute("VillagerIndex", index)
		if item.group then
			part:SetAttribute("Group", item.group)
		end
		if (item :: any).outfit then
			part:SetAttribute("OutfitSlot", (item :: any).outfit)
		end
		part.Parent = model
	end
	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("VillagerKit", kit.id)
	model:SetAttribute("VillagerVariant", variant)
	model:SetAttribute("VillagerKitVersion", kit.version)
	return model
end

-- Recolour an already-built kit model (template clone) with a villager palette.
function Builder.ApplyPalette(model: Model, palette: { [string]: string })
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Role")
			if type(role) == "string" and role ~= "Protected" then
				part.Color = toColor(palette[role] or palette.cloth)
			end
		end
	end
end

function Builder.CountBoxes(kit: any, variant: string?, outfit: any?): number
	return #Builder.Boxes(kit, variant, outfit)
end

-- Character height (held props such as a raised umbrella don't count).
function Builder.Height(kit: any, variant: string?, outfit: any?): number
	local top = 0
	for _, item in Builder.Boxes(kit, variant, outfit) do
		if item.group ~= "Prop" then
			top = math.max(top, item.max[2])
		end
	end
	return top
end

return table.freeze(Builder)
