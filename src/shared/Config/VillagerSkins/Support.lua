--!strict
-- Helpers for villager skins (Config/VillagerSkins). A skin is data: boxes in kit space
-- (studs, y up, ground y = 0, faces -Z, left is -X), each attached to one body bone and
-- tagged with its slot: face, headwear, top, bottom, footwear, accessory, props, back, tail.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)

local Support = {}

function Support.Box(
	bone: string,
	outfit: string,
	slot: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	role: string,
	extra: any?
): any
	local item: any = K.Box(slot, x0, y0, z0, x1, y1, z1, role, extra)
	item.bone = bone
	item.outfit = outfit
	return item
end

-- Two V4 anime eyes on the head's front face (rigid with the Head bone).
function Support.Eyes(
	cy: number,
	faceZ: number,
	spacing: number,
	w: number,
	h: number,
	family: string
): { any }
	local out = {}
	for _, cx in { -spacing, spacing } do
		for _, item: any in K.Eye(cx, cy, faceZ, w, h, family) do
			item.bone = "Head"
			item.outfit = "face"
			table.insert(out, item)
		end
	end
	return out
end

function Support.Join(...: { any }): { any }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

return table.freeze(Support)
