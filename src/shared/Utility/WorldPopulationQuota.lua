--!strict
local Config=require(script.Parent.Parent.Config.WorldProgression)
local Quota={}
-- Players are ready-profile summaries from the server; no client seat claims.
function Quota.Allocate(players: {any},operational: {[string]:boolean},budget: number?): any
	local target=budget or 42
	assert(target>=0 and target%1==0,"Population target must be a nonnegative integer")
	local weights,eligible,focus,seen={}, {}, {}, {}
	for _,player in players do
		if not player.ready or type(player.highestIndex)~="number" or player.highestIndex%1~=0
			or player.highestIndex<1 or player.highestIndex>7 then continue end
		local identity=player.userId or player
		if seen[identity] then continue end seen[identity]=true
		for _,definition in Config.Ordered do
			if definition.index>=1 and definition.index<=player.highestIndex and operational[definition.regionId] then eligible[definition.regionId]=true end
		end
		local highest=Config.Ordered[player.highestIndex+1]
		if highest and operational[highest.regionId] then focus[highest.regionId]=(focus[highest.regionId] or 0)+1 end

	end
	local regions,total={},0
	for _,definition in Config.Ordered do
		if definition.index>=1 and eligible[definition.regionId] then
			local weight=1+(focus[definition.regionId] or 0)
			weights[definition.regionId]=weight total+=weight table.insert(regions,definition)
		end
	end
	local quotas,remainder={},{}
	if #regions==0 then return {quotas=quotas,weights=weights,total=0} end
	local reserved=math.min(target,#regions)
	local remaining=target-reserved
	local assigned=0
	for index,definition in regions do
		local proportion=remaining*weights[definition.regionId]/total
		local count=math.floor(proportion)+(if index<=reserved then 1 else 0)
		quotas[definition.regionId]=count assigned+=count
		table.insert(remainder,{id=definition.regionId,index=definition.index,fraction=proportion-math.floor(proportion)})
	end
	table.sort(remainder,function(a,b) return if a.fraction==b.fraction then a.index<b.index else a.fraction>b.fraction end)
	for index=1,target-assigned do quotas[remainder[index].id]+=1 end
	return {quotas=quotas,weights=weights,total=target}
end
return Quota
