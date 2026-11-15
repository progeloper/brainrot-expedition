--!nocheck
return function()
 local SeatState = require(game.ReplicatedStorage.Shared.Utility.HumanoidSeatState)
 describe("actual seating after dismount", function()
  local function fixture(sit, state, occupied)
   local h = {Sit=sit,GetState=function() return state end}
   h.SeatPart={Occupant=if occupied then h else nil}
   return h
  end
  it("ignores an empty former SeatPart for a running character", function()
   expect(SeatState.IsSeated(fixture(false,Enum.HumanoidStateType.Running,false))).to.equal(false)
  end)
  it("rejects actual occupied seats even before Sit changes", function()
   expect(SeatState.IsSeated(fixture(false,Enum.HumanoidStateType.Running,true))).to.equal(true)
  end)
  it("retains sitting and seated transition restrictions", function()
   expect(SeatState.IsSeated(fixture(true,Enum.HumanoidStateType.Running,false))).to.equal(true)
   expect(SeatState.IsSeated(fixture(false,Enum.HumanoidStateType.Seated,false))).to.equal(true)
  end)
 end)
 describe("team presentation after native seat rejection", function()
  local controllers=game.StarterPlayer.StarterPlayerScripts.Client.Controllers
  local Team=require(controllers.ChariotTeamController)
  local Formation=require(controllers.ChariotFormationController)
  local function context(sit,state,occupantKind,sameCart)
   local cart={}
   local h={Sit=sit,Health=100,GetState=function()return state end}
   h.SeatPart={Occupant=if occupantKind=="Self" then h elseif occupantKind=="Other" then {} else nil,
    IsDescendantOf=function(_,candidate)return sameCart and candidate==cart end}
   return h,cart
  end
  it("shows management and releases occupied priority for the observed stale Running mirror",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"None",true)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(true)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(false)
  end)
  it("keeps actual occupied contact protected before Sit changes",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"Self",true)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(false)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(true)
  end)
  it("keeps a Seated native transition protected even with no current occupant",function()
   local h,cart=context(false,Enum.HumanoidStateType.Seated,"None",true)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(false)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(true)
  end)
  it("keeps Sit true protected while the native state is still Running",function()
   local h,cart=context(true,Enum.HumanoidStateType.Running,"None",true)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(false)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(true)
  end)
  it("does not assign this cart occupied priority for another actual seat",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"Self",false)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(false)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(false)
  end)
  it("ignores somebody else's occupancy on the former seat",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"Other",true)
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(true)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(false)
  end)
  it("retains management menu ownership carry health and missing-character gates",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"None",true)
   expect(Team.CanShowManagementPrompt(true,true,h,false)).to.equal(false)
   expect(Team.CanShowManagementPrompt(false,false,h,false)).to.equal(false)
   expect(Team.CanShowManagementPrompt(false,true,h,true)).to.equal(false)
   h.Health=0
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(false)
   expect(Team.CanShowManagementPrompt(false,true,nil,false)).to.equal(false)
   expect(Formation.IsLocallyOccupied(nil,cart)).to.equal(false)
  end)
  it("keeps an ordinary running character with no SeatPart on foot",function()
   local h,cart=context(false,Enum.HumanoidStateType.Running,"None",true)
   h.SeatPart=nil
   expect(Team.CanShowManagementPrompt(false,true,h,false)).to.equal(true)
   expect(Formation.IsLocallyOccupied(h,cart)).to.equal(false)
  end)
 end)
end
