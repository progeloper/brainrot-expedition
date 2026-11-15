-- Edit-only extraction of unchanged actual current source bodies.
-- Synthetic fixture amounts are presentation/guard inputs, never live cash evidence.
-- Real payment, custody commits, profile persistence, raycast LOS and multiplayer races are not exercised.
local function Run(options)
 local check=function(v,m)assert(v,m or "Detached migration guard assertion failed")end
 check(not game:GetService("RunService"):IsRunning(),"Run detached guards in Edit")
 local owned=Instance.new("Folder");owned.Name="DevBaseMigration_DetachedCounterGuards";owned.Parent=game:GetService("ServerStorage")
 local made={owned};local results={};local writeAttempts=0;local claimDispatches=0;local now=100
 local function make(class,parent,name)local v=Instance.new(class);v.Name=name or class;v.Parent=parent;made[#made+1]=v;return v end
 local function slice(source,first,last)
  local a=assert(source:find(first,1,true),first);local b=assert(source:find(last,a+#first,true),last)
  return source:sub(a,b-1)
 end
 local function compile(code,...)
  local fn,err=loadstring(code);check(fn,err);return fn(...)
 end
 local players=game:GetService("Players")
 local base=make("Model",owned,"NewFunctionalBase");base:SetAttribute("BaseId","Base_03")
 local oldBase=make("Model",owned,"DeletedBaseIdentityFixture");oldBase:SetAttribute("BaseId","Base_03")
 local platform=make("Part",base,"Slot_12");platform.Anchored=true;platform.CanCollide=true;platform.CanQuery=true;platform:SetAttribute("SlotIndex",12)
 platform.CFrame=CFrame.new(35,1.425,45)*CFrame.Angles(0,math.pi/2,0);platform.Size=Vector3.new(10.16,.75,13.92)
 local marker=make("Attachment",platform,"BrainrotPlacement");marker.CFrame=CFrame.new(0,.4,0)
 local character=make("Model",owned,"FixtureCharacter");local humanoid=make("Humanoid",character,"Humanoid");humanoid.Health=100
 local foot=make("Part",character,"Foot");local hrp=make("Part",character,"HumanoidRootPart")
 local otherCharacter=make("Model",owned,"OtherFixtureCharacter");make("Humanoid",otherCharacter,"Humanoid");local otherFoot=make("Part",otherCharacter,"Foot")
 local owner={Parent=players,Character=character,UserId=100001,Name="DetachedOwner"}
 local other={Parent=players,Character=otherCharacter,UserId=100002,Name="DetachedOther"}
 local control={ready=true,writable=true,active=true,busy=false,driving=false,reachable=true,reachReason=nil,ledger=123.875,record=nil,ownerBase=base}
 local ownerByCharacter={[character]=owner,[otherCharacter]=other}
 local slot={Index=12,Platform=platform,Marker=marker}
 local storage={Base=base,BaseId="Base_03",OwnerUserId=owner.UserId}
 function storage:IsActive()return control.active end
 function storage:IsProfileBacked()return true end
 function storage:IsValidPlatformId(i)return i==12 end
 function storage:GetPlatformRecord(i)check(i==12);return control.record end
 function storage:GetUnclaimedCashExact(i)check(i==12);return control.ledger end
 function storage:TryBeginPlatformMutation(i)check(i==12);return if control.busy then nil else "read-only-fixture-token" end
 function storage:EndPlatformMutation(i,token)check(i==12 and token=="read-only-fixture-token")end
 function storage:SetUnclaimedCashExact()writeAttempts+=1;error("Detached guards must never mutate a ledger")end
 local storageByPlayer={[owner]=storage}
 local baseSystem={}
 function baseSystem:GetBase(player)return if player==owner then control.ownerBase else nil end
 function baseSystem:IsOwner(player,candidate)return player==owner and candidate==control.ownerBase end
 local profileOwner={IsWritable=function(_,player)return control.writable and player==owner end}
 local wallet={IsReady=function()return control.ready end,CanCredit=function()return false end}
 wallet.AddCash=function()writeAttempts+=1;error("Detached guards must never award money")end
 wallet.TryCreditWithSource=wallet.AddCash
 local incomeCode=[[
local Players,wallet,baseSystem,storageSystem,control=...
local MAX_SAFE_INTEGER=9007199254740991
local platformContexts,claimsInFlight={},{}
local platformClock=function()return 100 end
local log={Warn=function(_,...)error("Unexpected extracted claim failure")end}
local syncOnePlatform=function()error("Detached guard reached financial commit")end
local Income={AccruePlatformsTo=function()return true end}
]]
 incomeCode..=slice(options.incomeSource,'local function finiteNonNegative(','local function validPlatformTime(')
 incomeCode..=slice(options.incomeSource,'local function platformContextCurrent(','local function syncOnePlatform(')
 incomeCode..=slice(options.incomeSource,'function Income:TryClaimPlatform(','local function diagnose(')
 incomeCode..=[[return {Owner=Income,Contexts=platformContexts,Claims=claimsInFlight}]]
 local storageOwner={GetStorageForPlayer=function(_,player)return storageByPlayer[player]end}
 local income=compile(incomeCode,players,wallet,baseSystem,storageOwner,control)
 local context={BaseId="Base_03",Base=base,Player=owner,OwnerUserId=owner.UserId,Storage=storage};income.Contexts.Base_03=context
 local snapshot={Occupied=true,RatePerSecond=1.25,UnclaimedCashSnapshot=123.875,SnapshotServerTime=100,Revision=4}
 local receiptFixture=false
 local incomeBridge={}
 function incomeBridge:TryClaimPlatform(player,bid,index)
  claimDispatches+=1;check(bid=="Base_03"and index==12,"Migrated counter forwarded a wrong stable identity")
  if receiptFixture then return {ok=true,paid=7.5,remainingExact=.125}end
  return income.Owner:TryClaimPlatform(player,bid,index)
 end
 function incomeBridge:GetPlatformIncomeSnapshot(bid,index)
  check(bid=="Base_03"and index==12)
  if receiptFixture then return {Occupied=true,RatePerSecond=1.25,UnclaimedCashSnapshot=.125,SnapshotServerTime=now,Revision=5}end
  return snapshot
 end
 local counterCode=slice(options.plaqueSource,'local PLAQUE_TAG =','local BaseIncomePlaqueSystem =')..[[
local Players,Config,CurrencyFormatter,incomeSystem,lookup,clock=...
local states,plaqueBindings={},{}
local touchAttempts=setmetatable({}, {__mode="k"})
local started=true
local getPlayerFromCharacter=lookup
local BaseIncomePlaqueSystem={}
]]
 counterCode..=slice(options.plaqueSource,'local function ensureAmountView(','local function candidatePlaques(')
 counterCode..=slice(options.plaqueSource,'local function characterFromTouchedPart(','local function bindPlaqueTouch(')
 counterCode..=[[return {Owner=BaseIncomePlaqueSystem,States=states,Bindings=plaqueBindings,Attempts=touchAttempts,Snapshot=applyIncomeSnapshotToPlaque}]]
 local counters=compile(counterCode,players,options.baseLayoutConfig,options.formatter,incomeBridge,function(char)return ownerByCharacter[char]end,function()return now end)
 local plaque=make("Part",base,"IncomePlaque_12")
 local state={Base=base,BaseId="Base_03",OwnerUserId=owner.UserId}
 counters.States[base]=state;counters.Bindings[plaque]={State=state,Base=base,BaseId="Base_03",PlatformId=12,OwnerUserId=owner.UserId}
 local storageCode=[[
local Workspace,platformSlots,storageByPlayer,profileOwner=...
local BaseStorageSystem={GetStorageForPlayer=function(_,player)return storageByPlayer[player]end}
]]
 storageCode..=slice(options.storageSource,'local function validSlot(','local function collectSlots(')
 storageCode..=slice(options.storageSource,'function BaseStorageSystem:ResolvePlatform(','function BaseStorageSystem:GetPlatformRecord(')
 storageCode..=[[return BaseStorageSystem]]
 local registry={[platform]={Base=base,Slot=slot}}
 local resolver=compile(storageCode,owned,registry,storageByPlayer,profileOwner)
 local carry={}
 local reachCall=nil
 local interactionCode=[[
local Players,BaseStorageSystem,InteractionConfig,control,carriedByUserId,livingCharacter,readReach=...
local dependencies={IsDriving=function()return control.driving end}
local canAct=function()return true end
local canReach=readReach
]]
 interactionCode..=slice(options.interactionSource,'local function validateCarriedSource(','-- Consumes the exact carried individual')
 interactionCode..=slice(options.interactionSource,'local function validatePlatformPickup(','-- Deposited pickup reuses')
 interactionCode..=[[return {Place=validatePlacement,Pickup=validatePlatformPickup}]]
 local interaction=compile(interactionCode,players,resolver,options.interactionConfig,control,carry,
  function(player)if player==owner and humanoid.Health>0 then return character,humanoid,hrp end return nil,nil,nil end,
  function(player,pos,target,distance)reachCall={player=player,pos=pos,target=target,distance=distance};return control.reachable,control.reachReason end)
 local emptyVisual=make("Model",character,"EmptyCustodyIdentityFixture")
 local carried={Player=owner,Record={ItemId="detached-exact-individual"},Character=character,Root=hrp,Visual={Model=emptyVisual,Weld={Enabled=true}}}
 local clientCode='local Config=...\nlocal State={}\n'..slice(options.clientStateSource,'function State:PlatformPromptReady(','-- Only base-platform prompts')..'return State'
 local client=compile(clientCode,options.interactionConfig)
 local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);results[#results+1]={name=name,passed=ok,error=if ok then nil else tostring(err)}end
 test("Actual snapshot publication retains migrated BaseId/PlatformId, authoritative amount and GUI binding",function()
  counters.Snapshot(plaque,"Base_03",12,owner.UserId,snapshot)
  local gui=plaque.AmountSurfaceGui;local label=gui.AmountLabel
  check(gui.Adornee==plaque and gui.Face==Enum.NormalId.Top and gui.Enabled)
  check(label.Text==options.formatter.FormatCompactCash(math.floor(snapshot.UnclaimedCashSnapshot)))
  check(plaque:GetAttribute("BaseId")=="Base_03"and plaque:GetAttribute("PlatformId")==12 and plaque:GetAttribute("BaseOwnerUserId")==owner.UserId)
  check(plaque:GetAttribute("IncomeRatePerSecond")==1.25 and plaque:GetAttribute("UnclaimedCashSnapshot")==123.875 and plaque:GetAttribute("IncomeRevision")==4)
  counters.Snapshot(plaque,"Base_03",12,owner.UserId,nil);check(not gui.Enabled and label.Text==""and plaque:GetAttribute("IncomeSnapshotReady")==false)
 end)
 test("Counter dispatch preserves exact IDs, receipt fields, ClaimRevision and duplicate-limb cooldown",function()
  receiptFixture=true;local before=claimDispatches;plaque:SetAttribute("ClaimRevision",2)
  counters.Snapshot(plaque,"Base_03",12,owner.UserId,{Occupied=true,RatePerSecond=1.25,UnclaimedCashSnapshot=7.625,SnapshotServerTime=now,Revision=4})
  local result=counters.Owner:HandlePlaqueTouch(plaque,foot);check(result and result.ok)
  check(claimDispatches==before+1 and plaque:GetAttribute("LastClaimUserId")==owner.UserId and plaque:GetAttribute("LastClaimAmount")==7.5 and plaque:GetAttribute("ClaimResetAmount")==.125 and plaque:GetAttribute("ClaimRevision")==3)
  check(plaque:GetAttribute("UnclaimedCashSnapshot")==.125 and plaque.AmountSurfaceGui.AmountLabel.Text==options.formatter.FormatCompactCash(0),"Counter receipt/snapshot amount incoherent")
  now=100.25;result=counters.Owner:HandlePlaqueTouch(plaque,foot);check(result.code=="Busy"and claimDispatches==before+1)
  now=100.6;check(counters.Owner:HandlePlaqueTouch(plaque,foot).ok and plaque:GetAttribute("ClaimRevision")==4)
  receiptFixture=false
 end)
 test("Invalid touch hierarchies, dead characters and stale migrated binding states cannot dispatch a claim",function()
  local before=claimDispatches;local accessory=make("Accessory",character,"FixtureAccessory");local handle=make("Part",accessory,"Handle")
  check(counters.Owner:HandlePlaqueTouch(plaque,handle)==nil)
  local tool=make("Tool",character,"FixtureTool");check(counters.Owner:HandlePlaqueTouch(plaque,make("Part",tool,"Handle"))==nil)
  humanoid.Health=0;check(counters.Owner:HandlePlaqueTouch(plaque,foot)==nil);humanoid.Health=100
  counters.States[base]={};check(counters.Owner:HandlePlaqueTouch(plaque,foot)==nil);counters.States[base]=state
  local saved=owner.Parent;owner.Parent=nil;check(counters.Owner:HandlePlaqueTouch(plaque,foot)==nil);owner.Parent=saved
  check(claimDispatches==before)
 end)
 test("Actual income owner rejects unreadable profiles, another owner, stale old-model contexts and invalid platform IDs",function()
  control.ready=false;check(income.Owner:TryClaimPlatform(owner,"Base_03",12).code=="ProfileNotReady");control.ready=true
  check(income.Owner:TryClaimPlatform(other,"Base_03",12).code=="NotOwner")
  local denied=counters.Owner:HandlePlaqueTouch(plaque,otherFoot);check(denied and denied.code=="NotOwner"and plaque:GetAttribute("ClaimRevision")==4)
  context.Base=oldBase;check(income.Owner:TryClaimPlatform(owner,"Base_03",12).code=="NotOwner");context.Base=base
  check(income.Owner:TryClaimPlatform(owner,"Base_99",12).code=="NotOwner")
  check(income.Owner:TryClaimPlatform(owner,"Base_03",11).code=="InvalidPlatform")
 end)
 test("Actual cash claim preserves the exact ledger when credit is refused, returns zero balance honestly and releases mutation locks",function()
  control.ledger=123.875;local result=income.Owner:TryClaimPlatform(owner,"Base_03",12)
  check(result.code=="AwardFailed"and result.paid==0 and result.remainingExact==123.875 and control.ledger==123.875)
  check(next(income.Claims)==nil and writeAttempts==0)
  control.ledger=0;result=income.Owner:TryClaimPlatform(owner,"Base_03",12);check(result.code=="NothingToCollect"and result.paid==0)
  control.busy=true;check(income.Owner:TryClaimPlatform(owner,"Base_03",12).code=="Busy");control.busy=false;control.ledger=123.875
 end)
 test("Actual platform resolver accepts the new direct slot and rejects old/nested/unregistered/unwritable targets",function()
  local found,store,reason=resolver:ResolvePlatform(owner,platform);check(found==slot and store==storage and reason==nil)
  local raw=make("Part",base,"UnregisteredSlab");local _,_,code=resolver:ResolvePlatform(owner,raw);check(code=="INVALID_PLATFORM")
  _,_,code=resolver:ResolvePlatform(other,platform);check(code=="NOT_OWNER")
  control.writable=false;_,_,code=resolver:ResolvePlatform(owner,platform);check(code=="PROFILE_NOT_READY");control.writable=true
  platform.Parent=oldBase;_,_,code=resolver:ResolvePlatform(owner,platform);check(code=="INVALID_PLATFORM");platform.Parent=base
  marker.Parent=oldBase;_,_,code=resolver:ResolvePlatform(owner,platform);check(code=="INVALID_PLATFORM");marker.Parent=platform
 end)
 test("Actual manual placement validation forwards the migrated marker and enforces custody ID, driving, occupied and reach guards",function()
  carry[owner.UserId]=nil;local _,reason=interaction.Place(owner,platform,carried.Record.ItemId);check(reason=="EMPTY_HANDS")
  carry[owner.UserId]=carried;_,reason=interaction.Place(owner,platform,"stale-id");check(reason=="STALE_ID")
  control.driving=true;_,reason=interaction.Place(owner,platform,carried.Record.ItemId);check(reason=="DRIVING");control.driving=false
  control.record={ItemId="deposited-individual"};_,reason=interaction.Place(owner,platform,carried.Record.ItemId);check(reason=="OCCUPIED");control.record=nil
  control.reachable=false;control.reachReason="OUT_OF_REACH";_,reason=interaction.Place(owner,platform,carried.Record.ItemId);check(reason=="OUT_OF_REACH");control.reachable=true
  local found;found,reason=interaction.Place(owner,platform,carried.Record.ItemId);check(found==carried and reason==nil)
  check(reachCall.target==platform and reachCall.pos==marker.WorldPosition and reachCall.distance==options.interactionConfig.PLACEMENT_INTERACT_RADIUS+options.interactionConfig.PLACEMENT_SERVER_TOLERANCE)
 end)
 test("Actual deposited pickup validation retains exact individual and rejects stale IDs/occupied hands/driving",function()
  carry[owner.UserId]=nil;control.record={ItemId="deposited-individual"}
  local record,found,_,_,_,reason=interaction.Pickup(owner,platform,"deposited-individual");check(record==control.record and found==slot and reason==nil)
  _,_,_,_,_,reason=interaction.Pickup(owner,platform,"stale-id");check(reason=="STALE_ID")
  carry[owner.UserId]=carried;_,_,_,_,_,reason=interaction.Pickup(owner,platform,"deposited-individual");check(reason=="ALREADY_CARRYING");carry[owner.UserId]=nil
  control.driving=true;_,_,_,_,_,reason=interaction.Pickup(owner,platform,"deposited-individual");check(reason=="DRIVING");control.driving=false
 end)
 test("Actual client front-half-plane and dwell policy follow the new platform frame and reset on changed target/eligibility",function()
  check(client.IsPlatformFront(platform.CFrame,platform.Position+platform.CFrame.LookVector*4))
  check(not client.IsPlatformFront(platform.CFrame,platform.Position-platform.CFrame.LookVector*4))
  local stateFixture=setmetatable({}, {__index=client});local dwell=options.interactionConfig.PLATFORM_PROMPT_DWELL_SECONDS
  check(not stateFixture:PlatformPromptReady(platform,character,true,10))
  check(not stateFixture:PlatformPromptReady(platform,character,true,10+dwell-.01))
  check(stateFixture:PlatformPromptReady(platform,character,true,10+dwell))
  check(not stateFixture:PlatformPromptReady(marker,character,true,10+dwell+.1))
  check(not stateFixture:PlatformPromptReady(marker,character,false,10+dwell+.2))
 end)
 local passed=0;for _,v in results do if v.passed then passed+=1 end end
 for i=#made,1,-1 do pcall(function()made[i]:Destroy()end)end
 return {status=if passed==#results then "Passed"else"Failed",passed=passed,total=#results,results=results,
  actualSourceBodiesExtracted=true,syntheticPresentationAmount=123.875,syntheticReceiptAmount=7.5,
  syntheticAmountsAreLiveMoney=false,realWalletOwnersInitialized=0,walletOrLedgerWriteAttempts=writeAttempts,
  liveCashOrProfileWrites=0,brainrotAssetsOrModelsTouched=0,workspaceWrites=0,allDetachedFixturesDestroyed=owned.Parent==nil,
  unexercised={"successful real wallet credit","full custody commit/rollback","real spatial raycast LOS","natural touch replication","multiplayer races","persistent release/rejoin"}}
end
return {Run=Run}
