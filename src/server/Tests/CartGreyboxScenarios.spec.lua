--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartGreyboxScenarios = require(ReplicatedStorage.Shared.Config.CartGreyboxScenarios)
	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxScenarioIds)
	local SectionIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxSectionIds)

	describe("CartGreyboxScenarios", function()
		it("defines each of the twenty-five required scenarios exactly once", function()
			local expectedIds: { [string]: boolean } = {}
			local seenIds: { [string]: boolean } = {}
			local sectionIds: { [string]: boolean } = {}
			local reachableSectionIds: { [string]: boolean } = {}

			for _, id in ScenarioIds do
				expect(expectedIds[id]).to.equal(nil)
				expectedIds[id] = true
			end

			for _, id in SectionIds do
				sectionIds[id] = true
			end

			for _, definition in CartGreyboxScenarios.All do
				expect(expectedIds[definition.Id]).to.equal(true)
				expect(seenIds[definition.Id]).to.equal(nil)
				expect(CartGreyboxScenarios.ById[definition.Id]).to.equal(definition)
				expect(sectionIds[definition.SectionId]).to.equal(true)
				expect(table.isfrozen(definition)).to.equal(true)
				expect(table.isfrozen(definition.AllowedSectionIds)).to.equal(true)

				local defaultIsAllowed = false

				for _, allowedSectionId in definition.AllowedSectionIds do
					expect(sectionIds[allowedSectionId]).to.equal(true)
					reachableSectionIds[allowedSectionId] = true

					if allowedSectionId == definition.SectionId then
						defaultIsAllowed = true
					end
				end

				expect(defaultIsAllowed).to.equal(true)
				seenIds[definition.Id] = true
			end

			expect(#CartGreyboxScenarios.All).to.equal(25)

			for id in expectedIds do
				expect(seenIds[id]).to.equal(true)
			end

			for id in sectionIds do
				expect(reachableSectionIds[id]).to.equal(true)
			end
		end)

		it("resolves only predefined sections allowed by each scenario", function()
			local defaultSection = CartGreyboxScenarios.ResolveSectionId(ScenarioIds.Steering, nil)
			local lowSpeedSection = CartGreyboxScenarios.ResolveSectionId(
				ScenarioIds.Steering,
				SectionIds.SteeringLowSpeed
			)
			local rejectedSection, rejection = CartGreyboxScenarios.ResolveSectionId(
				ScenarioIds.Steering,
				SectionIds.CartLifecycle
			)

			expect(defaultSection).to.equal(SectionIds.SteeringModerateSpeed)
			expect(lowSpeedSection).to.equal(SectionIds.SteeringLowSpeed)
			expect(rejectedSection).to.equal(nil)
			expect(type(rejection)).to.equal("string")
		end)

		it("keeps the catalogue and lookup immutable", function()
			expect(table.isfrozen(CartGreyboxScenarios)).to.equal(true)
			expect(table.isfrozen(CartGreyboxScenarios.All)).to.equal(true)
			expect(table.isfrozen(CartGreyboxScenarios.ById)).to.equal(true)
		end)
	end)
end
