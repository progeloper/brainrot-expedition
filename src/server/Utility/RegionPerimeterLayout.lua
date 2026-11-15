--!strict
-- Pure union-perimeter layout for the Edit-time managed biome separator installer.
-- Rectangles come from the current authored floor geometry, never catalogue guesses.
local Layout = {}
local function finite(n: any): boolean
	return type(n)=="number" and n==n and math.abs(n)<math.huge
end
function Layout.Build(rectangles: {any}, entrance: any, sharedEntrances: {any}?): {any}
	assert(#rectangles>0,"Missing authored region floors")
	assert(finite(entrance.x) and finite(entrance.z) and finite(entrance.width) and entrance.width>=24,"Invalid entrance")
	assert(entrance.axis=="X" or entrance.axis=="Z","Entrance must match an axis-aligned floor edge")
	local xs,zs,xseen,zseen={},{},{},{}
	for _,r in rectangles do
		assert(finite(r.x0) and finite(r.x1) and finite(r.z0) and finite(r.z1) and r.x0<r.x1 and r.z0<r.z1,"Invalid floor bounds")
		for _,x in {r.x0,r.x1} do if not xseen[x] then xseen[x]=true table.insert(xs,x) end end
		for _,z in {r.z0,r.z1} do if not zseen[z] then zseen[z]=true table.insert(zs,z) end end
	end
	table.sort(xs) table.sort(zs)
	local cells={}
	for i=1,#xs-1 do
		cells[i]={}
		for j=1,#zs-1 do
			local x,z=(xs[i]+xs[i+1])/2,(zs[j]+zs[j+1])/2
			for _,r in rectangles do
				if x>r.x0 and x<r.x1 and z>r.z0 and z<r.z1 then cells[i][j]=true break end
			end
		end
	end
	local lines={}
	local function edge(axis,fixed,first,last,inward)
		local key=axis..":"..tostring(fixed)..":"..tostring(inward)
		if not lines[key] then lines[key]={axis=axis,fixed=fixed,inward=inward,spans={}} end
		table.insert(lines[key].spans,{first=first,last=last})
	end
	local function occupied(i,j) return cells[i] and cells[i][j]==true end
	for i=1,#xs-1 do for j=1,#zs-1 do
		if not occupied(i,j) then continue end
		if not occupied(i-1,j) then edge("Z",xs[i],zs[j],zs[j+1],1) end
		if not occupied(i+1,j) then edge("Z",xs[i+1],zs[j],zs[j+1],-1) end
		if not occupied(i,j-1) then edge("X",zs[j],xs[i],xs[i+1],1) end
		if not occupied(i,j+1) then edge("X",zs[j+1],xs[i],xs[i+1],-1) end
	end end
	local perimeter={}
	for _,line in lines do
		table.sort(line.spans,function(a,b) return a.first<b.first end)
		local merged={}
		for _,span in line.spans do
			local last=merged[#merged]
			if last and last.last==span.first then last.last=span.last else table.insert(merged,{first=span.first,last=span.last}) end
		end
		for _,span in merged do table.insert(perimeter,{axis=line.axis,fixed=line.fixed,inward=line.inward,first=span.first,last=span.last}) end
	end
	table.sort(perimeter,function(a,b)
		if a.axis~=b.axis then return a.axis<b.axis end
		if a.fixed~=b.fixed then return a.fixed<b.fixed end
		return a.first<b.first
	end)

	local walls,openingCount={},0
	local openings={entrance}
	for _,other in sharedEntrances or {} do
		if other.x~=entrance.x or other.z~=entrance.z or other.axis~=entrance.axis then
			assert(finite(other.x) and finite(other.z) and finite(other.width) and other.width>=24,"Invalid shared entrance")
			assert(other.axis=="X" or other.axis=="Z","Invalid shared entrance axis")
			table.insert(openings,other)
		end
	end
	for _,edgeSpan in perimeter do
		local cuts={}
		for _,opening in openings do
			local fixed=if opening.axis=="X" then opening.z else opening.x
			local along=if opening.axis=="X" then opening.x else opening.z
			if edgeSpan.axis~=opening.axis or math.abs(edgeSpan.fixed-fixed)>=0.001 or along<edgeSpan.first or along>edgeSpan.last then continue end
			local first,last=along-opening.width/2,along+opening.width/2
			assert(first>=edgeSpan.first+4 and last<=edgeSpan.last-4,"Gate opening must fit inside its real perimeter edge")
			if opening==entrance then openingCount+=1 end
			table.insert(cuts,{first=first,last=last})
		end
		table.sort(cuts,function(a,b) return a.first<b.first end)
		local cursor=edgeSpan.first
		for _,cut in cuts do
			if cut.first>cursor then table.insert(walls,{axis=edgeSpan.axis,fixed=edgeSpan.fixed,inward=edgeSpan.inward,first=cursor,last=cut.first}) end
			cursor=math.max(cursor,cut.last)
		end
		if cursor<edgeSpan.last then table.insert(walls,{axis=edgeSpan.axis,fixed=edgeSpan.fixed,inward=edgeSpan.inward,first=cursor,last=edgeSpan.last}) end
	end
	assert(openingCount==1,"Entrance does not bind exactly one region perimeter edge")
	return walls
end
return Layout
