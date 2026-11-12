--!nocheck
-- Camp Rework, Parts B + C (owner-approved 11–12 Nov 2026). Studio Edit-mode builder ONLY.
-- Places the prepared stalls from Config/CampLayout (selected layout), moves the landmark and the
-- Announcements kiosk, removes the replaced kiosk art and coloured pads, and re-homes the invisible
-- SellStall sale anchor under the new Sell counter. Everything deleted is backed up first into
-- ServerStorage._Backups_CampRework_20261112 (idempotent: an existing backup is never overwritten).
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local P = {}
P.BackupName = "_Backups_CampRework_20261112"
P.GroundY = 0.05
P.FootprintMargin = 4

local function backupFolder()
	local f = SS:FindFirstChild(P.BackupName)
	if not f then
		f = Instance.new("Folder")
		f.Name = P.BackupName
		f.Parent = SS
	end
	return f
end

function P.Backup(instance, label)
	if not instance then
		return
	end
	local folder = backupFolder()
	local name = label or instance.Name
	if folder:FindFirstChild(name) then
		return
	end
	local copy = instance:Clone()
	copy.Name = name
	copy:SetAttribute("BackupSource", instance:GetFullName())
	copy.Parent = folder
end

local function dropToGround(model, cf)
	model:PivotTo(cf)
	local bcf, size = model:GetBoundingBox()
	local bottom = bcf.Position.Y - size.Y / 2
	model:PivotTo(cf + Vector3.new(0, P.GroundY - bottom, 0))
end

local function footprint(patches, name, cf, size)
	local old = patches:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(size.X + P.FootprintMargin, 0.6, size.Y + P.FootprintMargin)
	-- top 0.05 above the floor: overlap queries catch spawns, cart ground rays never ride on it
	p.CFrame = cf * CFrame.new(0, 0, 0) - Vector3.new(0, cf.Position.Y, 0) + Vector3.new(0, P.GroundY + 0.05 - 0.3, 0)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = false
	p:SetAttribute("CampStallFootprint", true)
	p.Parent = patches
	return p
end

function P.Run(layout)
	local map = workspace.MapBlockout
	local services = map.MapArt.Services
	local patches = map.ServiceStallPatches
	local env = map.EnvironmentArt_V2
	local build = SS._CampReworkBuild
	local report = {}
	-- 1) backups
	for _, name in { "Kiosk_WeaponHarpoonStall", "Kiosk_BuyCartStall", "Kiosk_KitStall", "Kiosk_SellStall", "Kiosk_AnnouncementStall" } do
		local m = services:FindFirstChild(name)
		if m and not m:GetAttribute("CampReworkStall") then
			P.Backup(m, "MapArt.Services." .. name)
		end
	end
	P.Backup(patches, "ServiceStallPatches")
	P.Backup(env:FindFirstChild("REGION_CAMP_Hero"), "EnvironmentArt_V2.REGION_CAMP_Hero")
	P.Backup(env:FindFirstChild("REGION_CAMP_Shrub_01"), "EnvironmentArt_V2.REGION_CAMP_Shrub_01")
	-- 2) remove replaced kiosk art (Announcements stays) and the coloured pads
	for _, name in { "Kiosk_WeaponHarpoonStall", "Kiosk_BuyCartStall", "Kiosk_KitStall", "Kiosk_SellStall" } do
		local m = services:FindFirstChild(name)
		if m then
			m:Destroy()
			table.insert(report, "deleted MapArt.Services." .. name)
		end
	end
	for _, name in { "BuyCartStall", "WeaponHarpoonStall", "AnnouncementStall", "SellSignSupport", "KitStall" } do
		local p = patches:FindFirstChild(name)
		if p then
			p:Destroy()
			table.insert(report, "deleted ServiceStallPatches." .. name)
		end
	end
	for _, child in patches:GetChildren() do
		if child.Name == "SellBrainrotsSign" then
			child:Destroy() -- the legacy runtime board; the new stall has its own SELL sign
		end
	end
	-- 3) stalls from the layout
	local names = { Weapons = "Kiosk_WeaponHarpoonStall", Carts = "Kiosk_BuyCartStall", Sell = "Kiosk_SellStall", Training = "Kiosk_TrainingStall" }
	local placed = {}
	for key, name in names do
		local row = layout.stalls[key]
		local template = build:FindFirstChild(name)
		assert(template, "missing built stall " .. name)
		local m = template:Clone()
		local cf = CFrame.new(row.x, P.GroundY, row.z) * CFrame.Angles(0, math.rad(row.yawDegrees), 0)
		m:PivotTo(cf)
		m.Parent = services
		placed[key] = m
		local fp = m:GetAttribute("FootprintSize")
		local off = m:GetAttribute("FootprintOffset")
		footprint(patches, "StallFootprint_" .. key, cf * CFrame.new(off.X, 0, off.Z), Vector2.new(fp.X, fp.Z))
		table.insert(report, string.format("placed %s at (%.1f, %.1f) yaw %.1f", name, row.x, row.z, row.yawDegrees))
	end
	-- 4) sale anchor under the new Sell counter (same size or smaller, invisible, non-colliding)
	local sale = patches:FindFirstChild("SellStall")
	local counter = placed.Sell:FindFirstChild("Counter")
	if sale and counter then
		sale.Size = Vector3.new(math.min(sale.Size.X, counter.Size.X - 0.2), math.min(sale.Size.Y, 1), math.min(sale.Size.Z, counter.Size.Z - 0.2))
		sale.CFrame = counter.CFrame
		sale.Transparency = 1
		sale.CanCollide = false
		sale.CanTouch = false
		sale.CanQuery = true
		sale.CastShadow = false
		table.insert(report, "moved ServiceStallPatches.SellStall under the Sell counter")
	end
	-- 5) landmark (keep its shrub) to the camp centre
	local hero = env:FindFirstChild("REGION_CAMP_Hero")
	local shrub = env:FindFirstChild("REGION_CAMP_Shrub_01")
	if hero then
		local old = hero:GetPivot()
		local target = CFrame.new(layout.center.X, old.Position.Y, layout.center.Z) * old.Rotation
		local delta = target * old:Inverse()
		hero:PivotTo(target)
		if shrub then
			shrub:PivotTo(delta * shrub:GetPivot())
		end
		footprint(patches, "StallFootprint_Landmark", CFrame.new(layout.center.X, 0, layout.center.Z), Vector2.new(12, 10))
		table.insert(report, "moved REGION_CAMP_Hero (+ shrub) to the camp centre")
	end
	-- 6) Announcements kiosk beside the landmark, facing the larger group of base entrances
	local kiosk = services:FindFirstChild("Kiosk_AnnouncementStall")
	if kiosk then
		local row = layout.announcements
		dropToGround(kiosk, CFrame.new(row.x, P.GroundY, row.z) * CFrame.Angles(0, math.rad(row.yawDegrees), 0))
		local _, size = kiosk:GetBoundingBox()
		footprint(patches, "StallFootprint_Announcements", CFrame.new(row.x, 0, row.z) * CFrame.Angles(0, math.rad(row.yawDegrees), 0),
			Vector2.new(size.X, size.Z))
		table.insert(report, "moved Kiosk_AnnouncementStall")
	end
	return report
end

return P
