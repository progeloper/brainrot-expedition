--!strict
return function()
 local RS=game:GetService("ReplicatedStorage")
 local Rules=require(RS.Shared.Utility.Phase13CombatUiRules)
 local View=require(RS.Shared.UI.BrainrotNametagView)
 local Config=require(RS.Shared.Config.BrainrotDisplayConfig)
 local function snapshot(changes: any?): any
  local value={visible=true,banked=false,interactionReady=true,itemId="long-range-catch",resetToken="reset1:source1",focused=true,displayState="Awake",now=10,profileRange=125,maximumLockRange=125}
  for key,item in changes or {} do value[key]=item end
  return value
 end
 local function readability(context: any, changes: any?): any
  local value={context=context,profileRange=125,ordinaryRange=100,maximumLockRange=125,physicalDistance=125,cameraDistance=136,cameraOffset=11,adorneeOffset=1}
  for key,item in changes or {} do value[key]=item end
  return Rules.Readability(value)
 end
 describe("Physical combat range and offset-camera readouts",function()
  it("keeps a valid125-stud lock visible from a camera11studs behind without increasing physical range",function()
   local context=Rules.UpdateReadabilityContext(nil,snapshot())
   local result=readability(context)
   expect(result.eligible).to.equal(true)
   expect(result.physicalRangeStuds).to.equal(125)
   expect(result.billboardRangeStuds>=136).to.equal(true)
   expect(readability(context,{physicalDistance=125.01}).eligible).to.equal(false)
  end)
  it("retains the same lock for its actual ground-sleep deadline and clears wake/transport/visibility/identity changes",function()
   local context=Rules.UpdateReadabilityContext(nil,snapshot())
   local sleeping=snapshot({focused=false,displayState="Sleeping",sleepUntil=22})
   context=Rules.UpdateReadabilityContext(context,sleeping)
   expect(context~=nil).to.equal(true)
   expect(readability(context).eligible).to.equal(true)
   for _,state in {"Awake","Carried","Cart","Deposited"} do
    expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState=state,sleepUntil=22}))).to.equal(nil)
   end
   expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState="Sleeping",sleepUntil=22,now=22}))).to.equal(nil)
   expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState="Sleeping",sleepUntil=22,visible=false}))).to.equal(nil)
   expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState="Sleeping",sleepUntil=22,itemId="other"}))).to.equal(nil)
   expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState="Sleeping",sleepUntil=22,resetToken="reset2:source1"}))).to.equal(nil)
   expect(Rules.UpdateReadabilityContext(context,snapshot({focused=false,displayState="Sleeping",sleepUntil=23}))).to.equal(nil)
  end)
  it("does not invent a distant sleep context and retains only a bounded attribute-arrival grace",function()
   local sleep=snapshot({focused=false,displayState="Sleeping",sleepUntil=22})
   expect(Rules.UpdateReadabilityContext(nil,sleep)).to.equal(nil)
   local context=Rules.UpdateReadabilityContext(nil,snapshot())
   local pending=snapshot({focused=false,displayState="Sleeping",now=10.3})
   expect(Rules.UpdateReadabilityContext(context,pending)~=nil).to.equal(true)
   pending.now=10.6
   expect(Rules.UpdateReadabilityContext(context,pending)).to.equal(nil)
  end)
  it("preserves ordinary100-stud camera culling and bounds extended camera allowance",function()
   expect(readability(nil,{cameraDistance=100}).eligible).to.equal(true)
   expect(readability(nil,{cameraDistance=100.01}).eligible).to.equal(false)
   local context=Rules.UpdateReadabilityContext(nil,snapshot())
   local far=readability(context,{cameraOffset=500,cameraDistance=500})
   expect(far.eligible).to.equal(false)
   expect(far.billboardRangeStuds<160).to.equal(true)
   expect(readability(context,{physicalDistance=math.huge}).eligible).to.equal(false)
   expect(readability(context,{profileRange=55,physicalDistance=56,cameraDistance=60}).eligible).to.equal(false)
  end)
  it("keeps fractional native HP geometry and world-occluded GUI configuration at the extended camera distance",function()
   local holder=Instance.new("Folder")
   local model=Instance.new("Model")
   local body=Instance.new("Part")
   body.Name,body.Anchored,body.CFrame="Body",true,CFrame.new(125,0,0)
   body.Parent=model;model.PrimaryPart=body
   local view=View.create(holder :: any,model,body,{displayName="Range fixture",rarity="Legendary",cashPerSecond=1},Config.States.Awake)
   local context=Rules.UpdateReadabilityContext(nil,snapshot())
   local result=readability(context)
   view.Gui.MaxDistance=result.billboardRangeStuds
   View.updateCombat(view,Rules.Sample(0.75,4,nil,10),true,true)
   expect(view.Gui.AlwaysOnTop).to.equal(false)
   expect(view.Gui.MaxDistance>=136).to.equal(true)
   expect(view.HealthFill.Size.X.Scale).to.equal(0.1875)
   expect(view.HealthLabel.Text).to.equal("0.75 / 4")
   View.updateState(view,Config.States.Sleeping,nil)
   view.Gui.MaxDistance=result.billboardRangeStuds
   View.updateCombat(view,Rules.Sample(0,4,22,21.1),true,true)
   expect(view.Gui.MaxDistance>=136).to.equal(true)
   expect(view.HealthLabel.Visible).to.equal(true)
   expect(view.HealthBar.Visible).to.equal(false)
   expect(string.find(view.HealthLabel.Text,"WAKING",1,true)~=nil).to.equal(true)
   View.destroy(view);model:Destroy();holder:Destroy()
  end)
 end)
end
