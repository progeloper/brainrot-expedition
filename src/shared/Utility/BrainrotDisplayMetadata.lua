--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)

local BrainrotDisplayMetadata = {}

local function resolveMutationId(record: any): any?
	if type(record) ~= "table" then
		return nil
	end
	local mutationId = record.MutationId
	local metadata = record.Metadata
	if mutationId == nil and type(metadata) == "table" then
		mutationId = metadata.MutationId
		if mutationId == nil and type(metadata.Mutation) == "table" then
			mutationId = metadata.Mutation.Id or metadata.Mutation.MutationId
		end
	end
	if typeof(mutationId) == "string" or typeof(mutationId) == "number" then
		return mutationId
	end
	return nil
end

function BrainrotDisplayMetadata.SetIdentity(model: Model, record: any)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId, record.BrainrotId)
	local mutationId = resolveMutationId(record)
	-- Core Loop V2 (K2): while the server marks a wild individual's mutation hidden, clients get "None"
	-- plus a shimmer flag; the real id is published at the KO. The attribute exists only with the flag on.
	if model:GetAttribute("CoreLoopMutationHidden") == true and mutationId ~= nil and mutationId ~= "None" then
		model:SetAttribute("CoreLoopShimmer", true)
		mutationId = "None"
	end
	model:SetAttribute(BrainrotDisplayConfig.Attributes.MutationId, mutationId)
end

function BrainrotDisplayMetadata.Apply(
	model: Model,
	record: any,
	displayState: string,
	carrierUserId: number?
)
	BrainrotDisplayMetadata.SetIdentity(model, record)
	model:SetAttribute(
		BrainrotDisplayConfig.Attributes.CarrierUserId,
		if carrierUserId and carrierUserId > 0 then carrierUserId else nil
	)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.DisplayState, displayState)
	CollectionService:AddTag(model, BrainrotDisplayConfig.CollectionTag)
end

function BrainrotDisplayMetadata.Clear(model: Model)
	CollectionService:RemoveTag(model, BrainrotDisplayConfig.CollectionTag)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.DisplayState, nil)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.CarrierUserId, nil)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.CamouflageSnapshot, nil)
	model:SetAttribute(BrainrotDisplayConfig.Attributes.DecoySplitSnapshot, nil)
end

return table.freeze(BrainrotDisplayMetadata)
