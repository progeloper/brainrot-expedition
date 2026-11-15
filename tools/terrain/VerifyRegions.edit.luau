-- Studio EDIT mode only, with the V5 world applied (BuildWorld.edit.luau with PREVIEW = true).
-- Section-9 checks per rebuilt region (the audit's section-C methods), written to the workspace
-- attribute "V5Verify" because a full pass outlasts one MCP call. Set REGION / CHECKS below.
--   W1 longest featureless run (pathfinding routes, 8-stud samples, beat = World model / burrow within a
--      40-stud +-35 deg forward cone, or terrain 2+ studs above the ground in that cone)
--   W2 hero tops visible from 6 hub eye points; W3 other heroes visible from 3 points inside the region
--   W6 glow parts with line of sight within 150 from 3 random points; W7 open walkable ground
--   W8 precise lane cells: flat (surface within 0.3 of -0.48, normal >= 0.98) and no collidable prop
--   W9 burrow -> region centre pathfinding; W10 burrow pads flat (12 studs) with no props
--   W11 wall dominance median over 20 random views (844x390 frustum, visible surfaces only); spawner
--   floor-probe share
-- Decor props are CanQuery = false, so sightline rays pass through foliage: W2/W3 measure terrain and
-- solid geometry (legacy walls, landmarks) only.
local REGION = "Beach" -- Beach | Swamp | Jungle | Forest | Arctic | Volcano | GlitchZone
local CHECKS = { W1 = true, W2 = true, W3 = true, W6 = true, W7 = true, W8 = true, W9 = true, W10 = true, W11 = true, W12 = true }

local SPEC = {
	Beach = {
		folder = "Beach",
		centre = Vector3.new(-628, 1, -200),
		burrows = { "Burrow_B01", "Burrow_B02", "Burrow_B03" },
		routes = {
			{ "gate->B01", Vector3.new(-520, 1, -384), "Burrow_B01" },
			{ "gate->B03", Vector3.new(-520, 1, -384), "Burrow_B03" },
			{ "B01->B02", "Burrow_B01", "Burrow_B02" },
			{ "B03->gate", "Burrow_B03", Vector3.new(-520, 1, -384) },
			{ "gate->Faro", Vector3.new(-520, 1, -384), Vector3.new(-640, 1, -560) },
		},
	},
	Swamp = {
		folder = "Swamp",
		centre = Vector3.new(-560, 1, 290),
		burrows = { "Burrow_S01", "Burrow_S02", "Burrow_S03" },
		routes = {
			{ "gate->S02", Vector3.new(-387, 1, 214), "Burrow_S02" },
			{ "S02->S01", "Burrow_S02", "Burrow_S01" },
			{ "S01->S03", "Burrow_S01", "Burrow_S03" },
			{ "gate->S03", Vector3.new(-387, 1, 214), "Burrow_S03" },
			{ "S03->Tree", "Burrow_S03", Vector3.new(-610, 1, 500) },
		},
	},
	Forest = { -- CP-A routes (gate threshold at the Camp/Forest edge, z -294)
		folder = "Forest",
		centre = Vector3.new(-120, 1, -440),
		burrows = { "Burrow_F01", "Burrow_F02", "Burrow_F03" },
		routes = {
			{ "gate->F01", Vector3.new(-12, 1, -306), "Burrow_F01" },
			{ "F01->F02", "Burrow_F01", "Burrow_F02" },
			{ "F02->F03", "Burrow_F02", "Burrow_F03" },
			{ "gate->F03", Vector3.new(-12, 1, -306), "Burrow_F03" },
			{ "F01->Hero", "Burrow_F01", Vector3.new(-214, 1, -570) },
		},
	},
	Jungle = {
		folder = "Jungle",
		centre = Vector3.new(-50, 1, 290),
		burrows = { "Burrow_J01", "Burrow_J02", "Burrow_J03" },
		routes = {
			{ "gate->J01", Vector3.new(-244, 1, 214), "Burrow_J01" },
			{ "J01->J02", "Burrow_J01", "Burrow_J02" },
			{ "J01->J03", "Burrow_J01", "Burrow_J03" },
			{ "gate->J03", Vector3.new(-244, 1, 214), "Burrow_J03" },
			{ "J02->Falls", "Burrow_J02", Vector3.new(150, 1, 466) },
		},
	},
	Arctic = { -- CP-C (gate thresholds on x 229; routes start just inside)
		folder = "Arctic",
		centre = Vector3.new(380, 1, -520),
		burrows = { "Burrow_A01", "Burrow_A02", "Burrow_A03" },
		routes = {
			{ "gate->A01", Vector3.new(241, 1, -564), "Burrow_A01" },
			{ "A01->A02", "Burrow_A01", "Burrow_A02" },
			{ "A01->A03", "Burrow_A01", "Burrow_A03" },
			{ "gate->A03", Vector3.new(241, 1, -564), "Burrow_A03" },
			{ "A02->Granita", "Burrow_A02", Vector3.new(640, 1, -570) },
			{ "A03->Spire", "Burrow_A03", Vector3.new(320, 1, -460) },
		},
	},
	Volcano = {
		folder = "Volcano",
		centre = Vector3.new(380, 1, -100),
		burrows = { "Burrow_V01", "Burrow_V02", "Burrow_V03" },
		routes = {
			{ "gate->V01", Vector3.new(241, 1, -280), "Burrow_V01" },
			{ "gate->V03", Vector3.new(241, 1, -280), "Burrow_V03" },
			{ "V03->V02", "Burrow_V03", "Burrow_V02" },
			{ "V01->V02", "Burrow_V01", "Burrow_V02" },
			{ "V03->Pyramid", "Burrow_V03", Vector3.new(420, 1, -196) },
		},
	},
	GlitchZone = {
		folder = "Glitch Zone",
		centre = Vector3.new(430, 1, 340),
		burrows = { "Burrow_G01", "Burrow_G02", "Burrow_G03" },
		routes = {
			{ "gate->G01", Vector3.new(241, 1, 292), "Burrow_G01" },
			{ "G01->G02", "Burrow_G01", "Burrow_G02" },
			{ "G02->G03", "Burrow_G02", "Burrow_G03" },
			{ "gate->G03", Vector3.new(241, 1, 292), "Burrow_G03" },
			{ "G03->Tower", "Burrow_G03", Vector3.new(320, 1, 430) },
		},
	},
}

local spec = SPEC[REGION]
local PFS = game:GetService("PathfindingService")
local AssetService = game:GetService("AssetService")
local out = { "== " .. REGION }
local function log(s)
	table.insert(out, s)
	workspace:SetAttribute("V5Verify", table.concat(out, "\n"))
end
local tp = RaycastParams.new()
tp.FilterType = Enum.RaycastFilterType.Include
tp.FilterDescendantsInstances = { workspace.Terrain }
local function surf(x, z)
	local h = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), tp)
	return h and h.Position.Y, h and h.Material, h and h.Normal
end
local floors = {}
for _, f in workspace.MapBlockout[spec.folder]:GetChildren() do
	if f:IsA("BasePart") then
		table.insert(floors, f)
	end
end
local function inRegion(x, z)
	for _, f in floors do
		local p = f.CFrame:PointToObjectSpace(Vector3.new(x, 0, z))
		if math.abs(p.X) <= f.Size.X / 2 and math.abs(p.Z) <= f.Size.Z / 2 then
			return true
		end
	end
	return false
end
local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
for _, f in floors do
	lo = Vector3.new(math.min(lo.X, f.Position.X - f.Size.X / 2), 0, math.min(lo.Z, f.Position.Z - f.Size.Z / 2))
	hi = Vector3.new(math.max(hi.X, f.Position.X + f.Size.X / 2), 0, math.max(hi.Z, f.Position.Z + f.Size.Z / 2))
end
local rng = Random.new(20261109)
local function walkPoint()
	for _ = 1, 400 do
		local x, z = rng:NextNumber(lo.X + 6, hi.X - 6), rng:NextNumber(lo.Z + 6, hi.Z - 6)
		if inRegion(x, z) then
			local y, m = surf(x, z)
			if y and math.abs(y + 0.48) < 0.6 and m ~= Enum.Material.Water then
				return Vector3.new(x, y + 5.5, z)
			end
		end
	end
	return nil
end
local world = workspace:FindFirstChild("World")
assert(world, "apply the V5 world first (BuildWorld PREVIEW = true)")
local root = world:FindFirstChild(REGION)
local parts = {}
for _, p in root:GetDescendants() do
	if p:IsA("BasePart") then
		table.insert(parts, p)
	end
end
local burrowPos = {}
for _, n in spec.burrows do
	burrowPos[n] = workspace.Phase12Burrows[n]:GetPivot().Position
end
local function point(v: any): Vector3
	if typeof(v) == "Vector3" then
		return v
	end
	local p = burrowPos[v] or workspace.Phase12Burrows[v]:GetPivot().Position
	return Vector3.new(p.X, 1, p.Z + 9)
end

-- W1
if CHECKS.W1 then
	local feats = {}
	for _, m in world:GetDescendants() do
		if m:IsA("Model") and m.Parent and m.Parent:IsA("Folder") then
			table.insert(feats, m:GetPivot().Position)
		end
	end
	for _, b in workspace.Phase12Burrows:GetChildren() do
		table.insert(feats, b:GetPivot().Position)
	end
	-- Hub routes (F02 -> F03 crosses the Camp) walk over the player base plots and service stalls:
	-- large areas, so a sample inside a footprint grown by 12 studs counts as a beat.
	local areas = {}
	for _, n in { "PlayerBasePatches", "ServiceStallPatches" } do
		for _, m in workspace.MapBlockout[n]:GetChildren() do
			local ok, cf, size = pcall(function()
				if m:IsA("Model") then
					return m:GetBoundingBox()
				end
				local part = m:FindFirstChildWhichIsA("BasePart", true) :: BasePart
				return part.CFrame, part.Size
			end)
			if ok then
				table.insert(areas, { cf = cf, half = size / 2 + Vector3.new(12, 0, 12) })
			end
		end
	end
	local cosA = math.cos(math.rad(35))
	local function hasBeat(pos, dir)
		for _, area in areas do
			local q = area.cf:PointToObjectSpace(pos)
			if math.abs(q.X) <= area.half.X and math.abs(q.Z) <= area.half.Z then
				return true
			end
		end
		for _, f in feats do
			local d = Vector3.new(f.X - pos.X, 0, f.Z - pos.Z)
			local m = d.Magnitude
			if m <= 40 and m > 0 and d.Unit:Dot(dir) >= cosA then
				return true
			end
		end
		for rr = 8, 40, 8 do
			for a = -35, 35, 17.5 do
				local v = CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(dir) * rr
				local h = workspace:Raycast(pos + v + Vector3.new(0, 60, 0), Vector3.new(0, -80, 0), tp)
				if h and h.Position.Y > 2 then
					return true
				end
			end
		end
		return false
	end
	local worst = 0
	for _, rt in spec.routes do
		local a, b = point(rt[2]), point(rt[3])
		local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(a, b)
		end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			log("W1 " .. rt[1] .. " path " .. tostring(path.Status))
			continue
		end
		local wps = path:GetWaypoints()
		local samples = {}
		for i = 1, #wps - 1 do
			local p, q = wps[i].Position, wps[i + 1].Position
			local n = math.max(1, math.floor((q - p).Magnitude / 8))
			local dir = Vector3.new(q.X - p.X, 0, q.Z - p.Z)
			dir = if dir.Magnitude > 0 then dir.Unit else Vector3.new(0, 0, -1)
			for k = 0, n - 1 do
				table.insert(samples, { p:Lerp(q, k / n), dir })
			end
		end
		local run, longest, total, at = 0, 0, 0, nil
		for i = 2, #samples do
			local seg = (samples[i][1] - samples[i - 1][1]).Magnitude
			total += seg
			if hasBeat(samples[i][1], samples[i][2]) then
				run = 0
			else
				run += seg
				if run > longest then
					longest, at = run, samples[i][1]
				end
			end
		end
		worst = math.max(worst, longest)
		log(string.format("W1 %s length=%.0f longest=%.0f%s", rt[1], total, longest,
			if at then string.format(" ending (%.0f,%.0f)", at.X, at.Z) else ""))
		task.wait()
	end
	log(string.format("W1 worst=%.0f", worst))
end

-- W2 / W3
local heroes = {}
for _, m in world:GetDescendants() do
	if m:IsA("Model") and m:GetAttribute("HeroLandmark") then
		local cf, size = m:GetBoundingBox()
		heroes[m:GetAttribute("HeroLandmark")] = { model = m, top = cf.Position + Vector3.new(0, size.Y / 2 - 3, 0) }
	end
end
local function visible(eye: Vector3, hero): boolean
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { hero.model }
	return workspace:Raycast(eye, hero.top - eye, rp) == nil
end
if CHECKS.W2 and heroes[REGION] then
	local eyes = { Vector3.new(-19, 18, -46) }
	for _, p in { { -19, -46 }, { -140, -160 }, { 100, -160 }, { -140, 80 }, { 100, 80 } } do
		table.insert(eyes, Vector3.new(p[1], 6, p[2]))
	end
	local n = 0
	for _, e in eyes do
		if visible(e, heroes[REGION]) then
			n += 1
		end
	end
	log(string.format("W2 %s hero top y=%.0f visible from %d/%d hub eye points", REGION, heroes[REGION].top.Y + 3, n, #eyes))
end
if CHECKS.W3 then
	local res = {}
	for i = 1, 3 do
		local e = walkPoint()
		local seen = {}
		for key, hero in heroes do
			if key ~= REGION and visible(e, hero) then
				table.insert(seen, key)
			end
		end
		table.sort(seen)
		table.insert(res, string.format("(%.0f,%.0f):%d[%s]", e.X, e.Z, #seen, table.concat(seen, ",")))
	end
	log("W3 other heroes visible from 3 inside points: " .. table.concat(res, "  "))
end

-- W6
if CHECKS.W6 then
	local neon = {}
	for _, p in world:GetDescendants() do
		if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
			table.insert(neon, p)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local res = {}
	for i = 1, 3 do
		local e = walkPoint()
		local seen = 0
		for _, n in neon do
			local d = n.Position - e
			if d.Magnitude <= 150 then
				rp.FilterDescendantsInstances = { n.Parent }
				if not workspace:Raycast(e, d, rp) then
					seen += 1
				end
			end
		end
		table.insert(res, string.format("(%.0f,%.0f):%d", e.X, e.Z, seen))
	end
	log("W6 glow parts in sight <=150: " .. table.concat(res, "  "))
end

-- W7
if CHECKS.W7 then
	local function covered(x, z)
		for _, p in parts do
			if
				math.abs(p.Position.X - x) < p.Size.X / 2 + 1
				and math.abs(p.Position.Z - z) < p.Size.Z / 2 + 1
				and p.Position.Y - p.Size.Y / 2 < 10
				and p.Size.Y > 0.5
				and p.Transparency < 1
			then
				return true
			end
		end
		return false
	end
	local total, open = 0, 0
	for x = lo.X + 4, hi.X - 4, 8 do
		for z = lo.Z + 4, hi.Z - 4, 8 do
			if inRegion(x, z) then
				total += 1
				local y, m = surf(x, z)
				if y and math.abs(y + 0.48) < 0.6 and m ~= Enum.Material.Water and not covered(x, z) then
					open += 1
				end
			end
		end
		task.wait()
	end
	log(string.format("W7 open ground-level walkable %.1f%% (%d/%d)", 100 * open / total, open, total))
end

-- W8: precise lane cells inside the region.
if CHECKS.W8 then
	local CELL = 4
	local cells = {}
	for _, part in workspace.MapBlockout.Paths.StyledSurfaces:GetChildren() do
		if part:IsA("MeshPart") then
			local ok, em = pcall(function()
				return AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
			end)
			if ok and em then
				local ms = part.MeshSize
				local sx, sz = part.Size.X / ms.X, part.Size.Z / ms.Z
				for _, tri in em:GetFaces() do
					local v = em:GetFaceVertices(tri)
					local p = {}
					for i = 1, 3 do
						local m = em:GetPosition(v[i])
						local w = part.CFrame:PointToWorldSpace(Vector3.new(m.X * sx, 0, m.Z * sz))
						p[i] = Vector2.new(w.X, w.Z)
					end
					local a, b, c = p[1], p[2], p[3]
					if math.abs((b - a):Cross(c - a)) > 1e-3 then
						for x = math.floor(math.min(a.X, b.X, c.X) / CELL) * CELL, math.max(a.X, b.X, c.X), CELL do
							for z = math.floor(math.min(a.Y, b.Y, c.Y) / CELL) * CELL, math.max(a.Y, b.Y, c.Y), CELL do
								local q = Vector2.new(x + CELL / 2, z + CELL / 2)
								local d1, d2, d3 = (b - a):Cross(q - a), (c - b):Cross(q - b), (a - c):Cross(q - c)
								if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)) and inRegion(q.X, q.Y) then
									cells[q.X .. "," .. q.Y] = q
								end
							end
						end
					end
				end
				em:Destroy()
			end
			task.wait()
		end
	end
	local cp = RaycastParams.new()
	cp.FilterType = Enum.RaycastFilterType.Include
	cp.FilterDescendantsInstances = { world }
	cp.RespectCanCollide = true
	local n, bumps, steep, blocked, near = 0, 0, 0, 0, 0
	for _, q in cells do
		n += 1
		local y, _, normal = surf(q.X, q.Y)
		if not y or math.abs(y + 0.48) > 0.3 then
			bumps += 1
		elseif normal.Y < 0.98 then
			steep += 1
		end
		if workspace:Raycast(Vector3.new(q.X, 30, q.Y), Vector3.new(0, -31, 0), cp) then
			blocked += 1
		end
		if n % 400 == 0 then
			task.wait()
		end
	end
	log(string.format("W8 lane cells=%d bumps=%d steep=%d blocked=%d", n, bumps, steep, blocked))
end

-- W9 / W10
if CHECKS.W9 then
	for _, name in spec.burrows do
		local p = burrowPos[name]
		local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		pcall(function()
			path:ComputeAsync(Vector3.new(p.X, 1, p.Z + 9), spec.centre)
		end)
		log("W9 " .. name .. " -> centre " .. path.Status.Name)
	end
end
if CHECKS.W10 then
	local bad = 0
	for _, name in spec.burrows do
		local p = burrowPos[name]
		local maxd = 0
		for i = 0, 7 do
			local a = i * math.pi / 4
			local y = surf(p.X + 12 * math.cos(a), p.Z + 12 * math.sin(a))
			maxd = math.max(maxd, math.abs((y or -99) + 0.48))
		end
		local props = 0
		for _, b in parts do
			local dx = math.max(0, math.abs(b.Position.X - p.X) - b.Size.X / 2)
			local dz = math.max(0, math.abs(b.Position.Z - p.Z) - b.Size.Z / 2)
			if math.sqrt(dx * dx + dz * dz) < 12 and b.Position.Y - b.Size.Y / 2 < 20 and b.Transparency < 1 then
				props += 1
			end
		end
		if maxd > 0.3 or props > 0 then
			bad += 1
		end
		log(string.format("W10 %s pad maxDelta=%.2f props=%d pos=(%.1f,%.1f,%.1f)", name, maxd, props, p.X, p.Y, p.Z))
	end
	log("W10 pad failures=" .. bad)
end

-- W11 + spawner probe
if CHECKS.W11 then
	local wallModels = {}
	for _, n in { "NavigationShells", "GateApertureClosures" } do
		local f = workspace.MapBlockout:FindFirstChild(n)
		if f then
			table.insert(wallModels, f)
		end
	end
	for _, m in workspace.MapBlockout.EnvironmentArt_V2:GetChildren() do
		local k = m:GetAttribute("PrototypeId")
		if k == "CliffRun" or k == "GateLintel" then
			table.insert(wallModels, m)
		end
	end
	local fr = {}
	local vf = math.rad(70)
	local hf = 2 * math.atan(math.tan(vf / 2) * 844 / 390)
	local p2 = RaycastParams.new()
	p2.FilterType = Enum.RaycastFilterType.Exclude
	-- Only visible surfaces count: rays pass through invisible colliders (the perimeter CliffRun
	-- colliders and rim-hidden shells stand behind the island rim, Transparency 1).
	local invisible = {}
	for _, d in workspace.MapBlockout:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency >= 0.98 then
			table.insert(invisible, d)
		end
	end
	p2.FilterDescendantsInstances = invisible
	for i = 1, 20 do
		local e = walkPoint()
		local cf = CFrame.new(e) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(math.rad(-8), 0, 0)
		local hits, wallHits = 0, 0
		for gx = 0, 15 do
			for gy = 0, 8 do
				local dir = (cf * CFrame.Angles((0.5 - gy / 8) * vf, -(gx / 15 - 0.5) * hf, 0)).LookVector * 1500
				local h = workspace:Raycast(e, dir, p2)
				hits += 1
				if h then
					for _, w in wallModels do
						if h.Instance:IsDescendantOf(w) then
							wallHits += 1
							break
						end
					end
				end
			end
		end
		table.insert(fr, wallHits / hits)
	end
	table.sort(fr)
	log(string.format("W11 wall dominance median %.1f%%", (fr[10] + fr[11]) / 2 * 100))
	local okc, tot = 0, 0
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.RespectCanCollide = true
	for x = lo.X + 8, hi.X - 8, 16 do
		for z = lo.Z + 8, hi.Z - 8, 16 do
			if inRegion(x, z) then
				tot += 1
				local h = workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -80, 0), rp)
				if h and math.abs(h.Position.Y - 0.05) <= 2 and h.Normal.Y >= 0.98 then
					okc += 1
				end
			end
		end
	end
	log(string.format("Spawner probe ok %d/%d (%.0f%%)", okc, tot, 100 * okc / tot))
end

-- W12
if CHECKS.W12 then
	local kitsUsed, nk = {}, 0
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Kit") and not kitsUsed[m:GetAttribute("Kit")] then
			kitsUsed[m:GetAttribute("Kit")] = true
			nk += 1
		end
	end
	local heroParts = 0
	if heroes[REGION] then
		for _, d in heroes[REGION].model:GetDescendants() do
			if d:IsA("BasePart") then
				heroParts += 1
			end
		end
	end
	local all = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			all += 1
		end
	end
	log(string.format("W12 %s parts=%d (World %d) kits=%d hero parts=%d", REGION, #parts, all, nk, heroParts))
end
log("done")
return table.concat(out, "\n")
