--!nocheck
-- Playtest Fixes 2, Part D (14 Nov 2026): solid base walls. Run in Studio EDIT mode (command bar or
-- execute_luau). Idempotent: rebuilds Base_0#.WallColliders in all 8 PlayerBasePatches.
--
-- Primary / Accent / Support (the ground-floor house shell meshes) are CanCollide = false. The shell
-- is the same mesh in every base, so the colliders are authored once in the base pivot's frame
-- (measured with raycasts against the shell on 14 Nov 2026) and placed by each base's pivot:
--   side walls  x -36.56 .. -33.16 and 6.50 .. 9.90, z -57.5 .. 21.78
--   back wall   z 19.96 .. 21.78, x -36.56 .. 9.90
--   back corners: filleted inner faces from (-33.16, 13.1) to (-25.1, 19.96) (and mirrored)
--   height 23 (shell top), the front (local -Z) is the open doorway.
-- Boxes: invisible, CanCollide = true, CanQuery = false, CanTouch = false, group "BaseWalls".
-- Undo: scripts/RevertBaseWalls.server.lua.
local PhysicsService = game:GetService("PhysicsService")

local GROUP = "BaseWalls"
local HEIGHT = 23
local CENTRE_X = -13.33
local COLLIDERS = {
	{ name = "Wall_Left", cf = CFrame.new(-34.86, HEIGHT / 2, -17.86), size = Vector3.new(3.4, HEIGHT, 79.28) },
	{ name = "Wall_Right", cf = CFrame.new(8.2, HEIGHT / 2, -17.86), size = Vector3.new(3.4, HEIGHT, 79.28) },
	{ name = "Wall_Back", cf = CFrame.new(CENTRE_X, HEIGHT / 2, 20.87), size = Vector3.new(46.46, HEIGHT, 1.82) },
}
do
	-- back-left fillet: inner face line A -> B; the box sits behind it (toward the corner), 3 thick
	local a, bpt = Vector2.new(-33.16, 13.1), Vector2.new(-25.1, 19.96)
	local d = (bpt - a).Unit
	local n = Vector2.new(-d.Y, d.X) -- points toward the outer corner (-x, +z)
	local mid = (a + bpt) / 2 + n * 1.5
	local length = (bpt - a).Magnitude
	local function fillet(name, centre, normal)
		local c = Vector3.new(centre.X, HEIGHT / 2, centre.Y)
		table.insert(COLLIDERS, {
			name = name,
			cf = CFrame.lookAt(c, c + Vector3.new(normal.X, 0, normal.Y)),
			size = Vector3.new(length, HEIGHT, 3),
		})
	end
	fillet("Wall_CornerBackLeft", mid, n)
	-- mirror about the house centre line x = CENTRE_X
	fillet("Wall_CornerBackRight", Vector2.new(2 * CENTRE_X - mid.X, mid.Y), Vector2.new(-n.X, n.Y))
end

if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
	PhysicsService:RegisterCollisionGroup(GROUP)
end

local patches = workspace.MapBlockout.PlayerBasePatches
local report = {}
for _, base in patches:GetChildren() do
	if base:IsA("Model") and base:FindFirstChild("Primary") then
		local old = base:FindFirstChild("WallColliders")
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "WallColliders"
		folder:SetAttribute("PlaytestFixes2", "BaseWalls")
		local pivot = base:GetPivot()
		for _, spec in COLLIDERS do
			local p = Instance.new("Part")
			p.Name = spec.name
			p.Anchored = true
			p.CanCollide = true
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 1
			p.Material = Enum.Material.SmoothPlastic
			p.Size = spec.size
			p.CFrame = pivot * spec.cf
			p.CollisionGroup = GROUP
			p.Parent = folder
		end
		folder.Parent = base
		table.insert(report, base.Name .. "=" .. #folder:GetChildren())
	end
end

-- Clearance check (geometric): no collider may overlap the doorway, HouseRamp, CartRamp, the cart
-- entry/deposit zone, the stairs/landings, or a slot's approach (the 3 studs in front of each slot).
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
local problems = {}
for _, base in patches:GetChildren() do
	local folder = base:FindFirstChild("WallColliders")
	if folder then
		local pivot = base:GetPivot()
		local function blocked(cf, size)
			for _, c in folder:GetChildren() do
				-- oriented-box test via the separating-axis-free shortcut: sample the probe box corners
				-- and centre against each collider's local bounds
				local half = c.Size / 2 - Vector3.new(0.01, 0.01, 0.01)
				for _, sx in { -1, 0, 1 } do
					for _, sy in { -1, 0, 1 } do
						for _, sz in { -1, 0, 1 } do
							local pt = (cf * CFrame.new(size.X / 2 * sx, size.Y / 2 * sy, size.Z / 2 * sz)).Position
							local l = c.CFrame:PointToObjectSpace(pt)
							if math.abs(l.X) < half.X and math.abs(l.Y) < half.Y and math.abs(l.Z) < half.Z then
								return c.Name
							end
						end
					end
				end
			end
			return nil
		end
		local probes = {
			{ "Doorway", pivot * CFrame.new(CENTRE_X, 5, -56), Vector3.new(38, 8, 4) },
		}
		for _, name in { "HouseRamp", "CartRamp", "DepositReturnZone", "CartDisplay", "CartSpawn", "PlayerSpawn" } do
			local part = base:FindFirstChild(name)
			if part then
				table.insert(probes, { name, part.CFrame, part.Size })
			end
		end
		for _, d in base:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:match("^Stair") or d.Name:match("^HalfLanding")) then
				table.insert(probes, { d.Name, d.CFrame, d.Size })
			end
			if d:IsA("BasePart") and d.Name:match("^Slot_%d+$") then
				-- the approach strip: 3 studs deep, in front of the slot (local -Z of the base), standing height
				local lp = pivot:PointToObjectSpace(d.Position)
				local approach = pivot * CFrame.new(lp.X, lp.Y + 3, lp.Z - d.Size.Z / 2 - 1.5)
				table.insert(probes, { d.Name .. "Approach", approach, Vector3.new(d.Size.X - 1, 5, 3) })
			end
		end
		for _, probe in probes do
			local hit = blocked(probe[2], probe[3])
			if hit then
				table.insert(problems, base.Name .. ":" .. probe[1] .. " x " .. hit)
			end
		end
	end
end

return "colliders " .. table.concat(report, " ") .. "\nclearance problems: " .. #problems .. (if #problems > 0
	then "\n" .. table.concat(problems, "\n")
	else "")
