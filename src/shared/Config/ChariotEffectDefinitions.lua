--!strict
-- Four stable effect identifiers. Species assignments and runtime reserves are
-- separate data; adding a species does not add an ability type or change saves.
local ordered = {
 table.freeze({Id='Speed',DisplayName='Speed',Unit='speed bonus',Stat='speedBonus',Cap=.10,Neutral=0,UsesCPS=true,UsesDuplicateFactors=true,DisplayScale=100,Prefix='+',Suffix='%',Icon='»',Description='Raises your chariot\'s normal top speed.'}),
 table.freeze({Id='Hit',DisplayName='Hit Multiplier',Unit='hit multiplier',Stat='hitMultiplier',Cap=5,Neutral=1,UsesCPS=true,UsesDuplicateFactors=true,DisplayScale=1,Prefix='×',Suffix='',Icon='✦',Description='Scales accepted shot damage using the current sleep threshold.'}),
 table.freeze({Id='Burst',DisplayName='Burst',Unit='boost seconds',Stat='burstCapacity',Cap=8,Neutral=0,UsesCPS=true,UsesDuplicateFactors=true,DisplayScale=1,Prefix='',Suffix=' seconds',Icon='»',Description='Supplies the driver\'s rechargeable Burst reserve.'}),
 table.freeze({Id='Shield',DisplayName='Shield',Unit='charges',Stat='shieldCapacity',Cap=3,Neutral=0,UsesCPS=false,UsesDuplicateFactors=false,DisplayScale=1,Prefix='',Suffix=' charges',Icon='◇',Description='Blocks a cargo hit and protects your cargo for 5 seconds. Refills at your base.'}),
}
local byId = {} local ids = {}
for _,definition in ordered do byId[definition.Id]=definition table.insert(ids,definition.Id) end
table.freeze(ordered) table.freeze(byId) table.freeze(ids)
local Effects={Ordered=ordered,OrderedIds=ids,ById=byId}
for id,definition in byId do Effects[id]=definition end
function Effects.Get(id:any):any? return byId[id] end
local function integer(value:any):boolean
 return type(value)=='number' and value==value and math.abs(value)<math.huge and value%1==0
end
-- Return structured configuration issues rather than throwing through profile
-- loading. Invalid static entries become unavailable; their saved IDs remain.
function Effects.ValidateSpeciesEffectReport(spec:any,speciesId:string?):any
 local report={errors={},warnings={}}
 local function issue(code,message) table.insert(report.errors,{severity='Error',code=code,speciesId=speciesId,message=message}) end
 if type(spec)~='table' then issue('EFFECT_DEFINITION_INVALID','equipped effect must be a table') return report end
 local definition=byId[spec.effect]
 if not definition then issue('EFFECT_IDENTIFIER_INVALID','primary effect must be Speed, Hit, Burst or Shield') end
 if spec.effect=='Shield' then
  if spec.contribution~=1 or not integer(spec.contribution) then issue('SHIELD_CONTRIBUTION_INVALID','Shield contribution must be exactly one whole charge') end
 elseif spec.contribution~=nil then
  issue('NUMERICAL_CONTRIBUTION_OVERRIDE','Speed, Hit and Burst contributions use the existing rarity/CPS rules')
 end
 local grant=if spec.contributors==nil then 1 else spec.contributors
 if not integer(grant) or grant<1 or grant>3 then issue('CONTRIBUTOR_LIMIT_INVALID','contributor limit must be an integer from one through three') end
 local target=spec.amplifierTarget
 if target~=nil and not byId[target] then issue('AMPLIFIER_TARGET_INVALID','amplifier target must be one of the four defined effects') end
 if target~=nil and grant==1 then issue('AMPLIFIER_WITHOUT_GRANT','an explicit amplifier target requires a Top 2 or Top 3 grant') end
 return report
end
function Effects.ValidateSpeciesEffect(spec:any,speciesId:string?):(boolean,string?,any)
 local report=Effects.ValidateSpeciesEffectReport(spec,speciesId)
 return #report.errors==0,if report.errors[1] then report.errors[1].code else nil,report
end
function Effects.ValidateDefinitions(species:any):any
 local report={errors={},warnings={}}
 if type(species)~='table' then
  table.insert(report.errors,{severity='Error',code='EFFECT_DEFINITIONS_INVALID',message='species effect definitions must be a table'}) return report
 end
 for id,spec in species do
  local individual=Effects.ValidateSpeciesEffectReport(spec,tostring(id))
  for _,issue in individual.errors do table.insert(report.errors,issue) end
 end
 table.sort(report.errors,function(a,b)return (a.speciesId or '')..a.code<(b.speciesId or '')..b.code end)
 return report
end
return table.freeze(Effects)
