--!nocheck
return function()
	local World=require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local Config=require(game.ReplicatedStorage.Shared.Config.BrainrotPopulation)
	local Mutations=require(game.ReplicatedStorage.Shared.Config.MutationCatalog)
	describe("Phase12 mutation follows the existing pending reservation",function()
		it("keeps species, mutation and counted identity across failed placement and commit",function()
			local blocked=true
			local attempts={}
			local config=table.clone(Config)
			config.TargetWildPopulation=1
			local ledger=World._TestCreatePopulationHarness(config,{
				GetRegion=function() return {kind="Hunting",naturalSpawnAllowed=true,populationCap=1} end,
				ChooseRegion=function(_,tried) return if not tried.REGION_FOREST then "REGION_FOREST" else nil end,
				SelectSpecies=function() return {status="Selected",speciesId="BRT_019"} end,
				GenerateReservationId=function() return "phase12-stable-pending" end,
				Schedule=function() end,
				SpawnReservation=function(reservation,commit)
					table.insert(attempts,reservation)
					if blocked then return false,"NO_SAFE_POSE" end
					return commit(reservation.ReservationId)
				end,
			})
			assert(ledger:Start())
			ledger:Run()
			local first=attempts[1]
			expect(Mutations.ById[first.MutationId]~=nil).to.equal(true)
			expect(ledger:Snapshot().Effective).to.equal(1)
			expect(ledger:Snapshot().Reserved).to.equal(1)
			ledger:Run()
			expect(attempts[2]).to.equal(first)
			expect(attempts[2].MutationId).to.equal(first.MutationId)
			blocked=false
			ledger:Run()
			local member=ledger:Snapshot().Members[1]
			expect(member.RuntimeId).to.equal(first.ReservationId)
			expect(member.Phase12.MutationId).to.equal(first.MutationId)
			expect(member.Phase12.OrdinaryReservationId).to.equal(first.ReservationId)
			expect(member.Phase12.RemainingHp).to.equal(2)
			expect(ledger:Snapshot().Reserved).to.equal(0)
			expect(ledger:Snapshot().Effective).to.equal(1)
			expect(ledger:Validate()).to.equal(true)
			ledger:Stop()
		end)
	end)
end
