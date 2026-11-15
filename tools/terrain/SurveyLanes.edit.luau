-- Studio EDIT mode only. Rasterises the precise cart-lane carpets (MapBlockout.Paths.StyledSurfaces
-- MeshParts, read through EditableMesh triangles) onto a 4-stud XZ grid and returns run-length rows of lane cells.
-- Box-collision raycasts over-reserve the lanes (the whole mesh bounding box hits),
-- so this is the lane mask the author scripts use. Bounds are passed in X0/X1/Z0/Z1 below.
local X0, X1, Z0, Z1, CELL = -748, 232, -656, 564, 4
local AssetService = game:GetService("AssetService")
local nx, nz = math.floor((X1 - X0) / CELL), math.floor((Z1 - Z0) / CELL)
local grid = table.create(nx * nz, false)
for _, part in workspace.MapBlockout.Paths.StyledSurfaces:GetChildren() do
	if part:IsA("MeshPart") then
		local ok, em = pcall(function()
			return AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
		end)
		if ok and em then
			-- Mesh space -> part space: scale by Size / MeshSize (MeshSize.Y is 0 for flat carpets).
			local ms = part.MeshSize
			local sx, sz = part.Size.X / ms.X, part.Size.Z / ms.Z
			local cf = part.CFrame
			for _, tri in em:GetFaces() do
				local v = em:GetFaceVertices(tri)
				local p = {}
				for i = 1, 3 do
					local m = em:GetPosition(v[i])
					local w = cf:PointToWorldSpace(Vector3.new(m.X * sx, 0, m.Z * sz))
					p[i] = Vector2.new(w.X, w.Z)
				end
				local a, b, c = p[1], p[2], p[3]
				local area = (b - a):Cross(c - a)
				if math.abs(area) > 1e-3 then
					local minx, maxx = math.min(a.X, b.X, c.X), math.max(a.X, b.X, c.X)
					local minz, maxz = math.min(a.Y, b.Y, c.Y), math.max(a.Y, b.Y, c.Y)
					for ix = math.max(0, math.floor((minx - X0) / CELL)), math.min(nx - 1, math.floor((maxx - X0) / CELL)) do
						for iz = math.max(0, math.floor((minz - Z0) / CELL)), math.min(nz - 1, math.floor((maxz - Z0) / CELL)) do
							local q = Vector2.new(X0 + (ix + 0.5) * CELL, Z0 + (iz + 0.5) * CELL)
							local d1, d2, d3 = (b - a):Cross(q - a), (c - b):Cross(q - b), (a - c):Cross(q - c)
							local neg = d1 < 0 or d2 < 0 or d3 < 0
							local pos = d1 > 0 or d2 > 0 or d3 > 0
							if not (neg and pos) then
								grid[iz * nx + ix + 1] = true
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
-- Run-length rows keep the result small: "iz:a-b,c-d" lists the lane cell index runs of row iz.
local rows = {}
for iz = 0, nz - 1 do
	local runs, start = {}, nil
	for ix = 0, nx do
		local on = ix < nx and grid[iz * nx + ix + 1]
		if on and not start then
			start = ix
		elseif not on and start then
			table.insert(runs, start .. "-" .. (ix - 1))
			start = nil
		end
	end
	if #runs > 0 then
		table.insert(rows, iz .. ":" .. table.concat(runs, ","))
	end
end
return string.format("%d %d %d %d %d\n", X0, Z0, CELL, nx, nz) .. table.concat(rows, "\n")
