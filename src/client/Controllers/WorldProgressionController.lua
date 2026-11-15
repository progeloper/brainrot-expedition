--!strict
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CollectionService=game:GetService("CollectionService")
local HttpService=game:GetService("HttpService")
local Config=require(ReplicatedStorage.Shared.Config.WorldProgression)
local Names=require(ReplicatedStorage.Shared.Constants.RemoteNames)
local GateAccess=require(ReplicatedStorage.Shared.Utility.GateAccessPresentation)
local View=require(ReplicatedStorage.Shared.Utility.WorldProgressionPresentation)
-- Plate view (MenusV2 window "Gate"); this controller keeps the state and the remote call.
local GateScreen=require(script.Parent.Parent.UI.Screens.GateScreen)
local Controller={}
local started=false
local connections={}
local bindings={}
local summary: any,key: string?,pending: any,notice: string?=nil,nil,nil,nil
local confirming=false
local request,update
local function connect(signal,callback)
	local connection=signal:Connect(callback) table.insert(connections,connection) return connection
end
local function presentation()
	for model in bindings do
		local definition=Config.ByKey[model:GetAttribute("LogicalRegionKey")]
		local door=model:FindFirstChild("DoorPresentation")
		if not definition or not door or not door:IsA("BasePart") then continue end
		local allowed=summary and summary.personalUnlocks[definition.key]
		GateAccess.Apply(model,allowed==true,definition.displayName or model.Name)
	end
end
-- What the Plate window shows: title/body/action/enabled exactly from the shared view model.
local function viewModel(): any
	local view=View.Build(key :: string,summary,confirming)
	local gate=if summary and summary.ready and type(summary.gates)=="table" then summary.gates[key] else nil
	local code=if gate then gate.code else nil
	return {
		title=view.title,body=view.body,
		action=if pending then View.PendingLabel(pending.at,os.clock()) else view.action,
		enabled=not pending and view.enabled==true,
		confirming=confirming and view.enabled==true,
		pending=pending~=nil,
		unlocked=code=="AlreadyUnlocked" or code=="FreeStarterRegion",
		notice=notice,
	}
end
local function render()
	if not key or not GateScreen.isOpen() then return end
	GateScreen.update(viewModel())
end
local function hide(instant: boolean?)
	key=nil confirming=false notice=nil
	GateScreen.close(instant)
end
local function showNotice(text,kind: string?)
	if type(text)~="string" then return end
	GateScreen.toast(text,kind or "alert",Config.ACCESS_NOTICE_SECONDS)
end
-- The gate prompt the player just used (the server's Open message does not name it): the nearest
-- UnlockPrompt within reach. MenusV2 closes the window when the player walks away from it.
local function nearestGatePrompt(): ProximityPrompt?
	local character=Players.LocalPlayer.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end
	local best: ProximityPrompt?,bestDistance=nil,math.huge
	for model in bindings do
		local prompt=model:FindFirstChild("UnlockPrompt",true)
		if not prompt or not prompt:IsA("ProximityPrompt") then continue end
		local parent=prompt.Parent
		local position=if parent and parent:IsA("BasePart") then parent.Position
			elseif parent and parent:IsA("Attachment") then parent.WorldPosition else nil
		if not position then continue end
		local distance=(root.Position-position).Magnitude
		if distance<bestDistance and distance<=prompt.MaxActivationDistance+4 then best,bestDistance=prompt,distance end
	end
	return best
end
local function submit()
	if pending or not key then return end
	local view=View.Build(key,summary,confirming)
	if not view.enabled then render() return end
	if not confirming then confirming=true render() return end
	pending={key=key,id=HttpService:GenerateGUID(false),at=os.clock()}
	request:FireServer({regionKey=key,requestId=pending.id}) render()
	local operation=pending
	task.delay(Config.CLIENT_PENDING_NOTICE_SECONDS,function() if started and pending==operation then render() end end)
end
local function show(regionKey)
	key=regionKey confirming=false notice=nil
	GateScreen.open(viewModel(),{onPrimary=submit,onClose=hide},nearestGatePrompt())
end
function Controller.Start(): boolean
	if started then return false end
	local remotes=ReplicatedStorage:WaitForChild("Remotes",10)
	if not remotes then return false end
	request=remotes:WaitForChild(Names.WorldProgressionRequest,10)
	update=remotes:WaitForChild(Names.WorldProgressionUpdate,10)
	if not request or not update then return false end
	started=true
	connect(update.OnClientEvent,function(message)
		if type(message)~="table" then return end
		if message.summary then summary=message.summary presentation() render() end
		if message.kind=="Open" and Config.ByKey[message.key] then show(message.key)
		elseif message.kind=="Result" then
			local result=message.result
			if not result then return end
			if result.code=="Success" or result.code=="AlreadyUnlocked" then
				pending=nil confirming=false
				notice=if result.code=="Success" then Config.ByKey[result.key].displayName.." unlocked permanently!" else "Permanently unlocked"
				if result.code=="Success" then
					showNotice(notice,"good")
					GateScreen.celebrate()
				end
			elseif result.code~="PurchasePending" then pending=nil confirming=false notice=message.text or View.ResultMessage(result.code) end
			render()
		elseif message.kind=="Notice" then notice=message.text showNotice(message.text) if key then render() end end
	end)
	local function bind(model)
		if not model:IsA("Model") or bindings[model] then return end
		bindings[model]=model.DescendantAdded:Connect(presentation) presentation()
	end
	local function unbind(model)
		local connection=bindings[model] if connection then connection:Disconnect() bindings[model]=nil end
	end
	connect(CollectionService:GetInstanceAddedSignal("WorldProgressionGate"),bind)
	connect(CollectionService:GetInstanceRemovedSignal("WorldProgressionGate"),unbind)
	for _,model in CollectionService:GetTagged("WorldProgressionGate") do bind(model) end
	update:FireServer()
	return true
end
function Controller.Stop()
	if not started then return end
	started=false
	hide(true)
	for _,connection in connections do connection:Disconnect() end table.clear(connections)
	for model,connection in bindings do connection:Disconnect() bindings[model]=nil end
	summary,key,pending,notice=nil,nil,nil,nil
end
return Controller
