from pathlib import Path
import re,json
import argparse
parser=argparse.ArgumentParser(description="Build the existing focused TestEZ-style specs for an isolated native Luau source-only environment; this command never launches Studio or runs a game.")
parser.add_argument('--scope',choices=['focused','affected','safety'],default='focused')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
specs=['Phase13Commerce.spec','Phase13CommerceCapacity.spec','Phase13ReceiptDelivery.spec','PlayerProfileStore.spec','Phase13ReceiptArchive.spec']
paths={}
for folder,prefix in [('src/shared','ReplicatedStorage.Shared'),('src/server','ServerScriptService.Server')]:
 for p in (root/folder).rglob('*.lua'):
  parts=list(p.relative_to(root/folder).parts);parts[-1]=parts[-1][:-4]
  if parts[-1].endswith('.server') or parts[-1].endswith('.client'):continue
  paths[prefix+'.'+'.'.join(x.replace('.', '_DOT_') for x in parts)]=p
selected={};unresolved=set()
stubs={n:'return setmetatable({}, {__index=function(_, key) return function() error("Uninjected unrelated dependency: " .. key) end end})' for n in ['ServerScriptService.Server.Systems.BrainrotIncomeSystem','ServerScriptService.Server.Services.BankedBrainrotService','ServerScriptService.Server.Systems.DevelopmentBrainrotSpawner']}
def resolve(expr,node,aliases):
 expr=re.sub(r'game:GetService\([\"\']([^\"\']+)[\"\']\)',r'\1',expr).strip()
 if not re.fullmatch(r'[\w.]+',expr):return None
 bits=expr.split('.')
 if bits[0]=='script': base=node.split('.');bits=bits[1:]
 elif bits[0]=='game':base=[];bits=bits[1:]
 elif bits[0] in aliases:base=aliases[bits[0]].split('.');bits=bits[1:]
 else:base=[]
 for b in bits:
  if b=='Parent':base.pop()
  else:base.append(b)
 return '.'.join(base)
def collect(node):
 if node in selected:return
 if node not in paths:unresolved.add(node);return
 p=paths[node];text=stubs.get(node,p.read_text());selected[node]=text
 aliases={m[0]:m[1] for m in re.findall(r'local\s+(\w+)\s*=\s*game:GetService\([\"\']([^\"\']+)[\"\']\)',text)}
 for expr in re.findall(r'require\((.*)\)',text):
  # Greedy matching handles inline GetService but trims outer trailing syntax.
  expr=expr.split(') or ')[0]
  target=resolve(expr,node,aliases)
  if target and target in paths:collect(target)
  elif target:unresolved.add(target)
for name in specs:collect('ServerScriptService.Server.Tests.'+name.replace('.', '_DOT_'))
print(json.dumps({'modules':len(selected),'bytes':sum(len(s) for s in selected.values()),'unresolved':sorted(unresolved)}))
def lua(s):
 eq='===='
 while ']'+eq+']' in s:eq+='='
 return '['+eq+'['+s+']'+eq+']'
loader=r'''
local nativeGame=game
local lines={}
local function record(...) local a={...};for k,v in a do a[k]=tostring(v) end;table.insert(lines,table.concat(a," ")) end
local sources={__SOURCES__}
local nodes={};local function node(path)
 if nodes[path] then return nodes[path] end
 local parent,name=path:match("^(.*)%.([^%.]+)$")
 local v={Name=name or path,_path=path,ClassName=if sources[path] then "ModuleScript" else "Folder"}
 nodes[path]=v
 if parent then v.Parent=node(parent);v.Parent[v.Name]=v end
 function v:GetFullName()return self._path end
 function v:GetAttribute(k)return self._attrs and self._attrs[k] end
 function v:SetAttribute(k,value)self._attrs=self._attrs or {};self._attrs[k]=value end
 function v:GetAttributes()return table.clone(self._attrs or {}) end
 function v:GetDebugId()return self._path end
 function v:IsDescendantOf(parent)local p=self.Parent;while p do if p==parent then return true end;p=p.Parent end;return false end
 function v:FindFirstChild(n)return rawget(self,n) end
 function v:WaitForChild(n) local c=rawget(self,n);assert(c,"Missing virtual module "..self._path.."."..n);return c end
 function v:GetChildren()local a={};for _,c in nodes do if c.Parent==self then table.insert(a,c) end end;return a end
 function v:GetDescendants()local a={};for p,c in nodes do if p:sub(1,#self._path+1)==self._path.."." then table.insert(a,c) end end;return a end
 function v:IsA(kind)return self.ClassName==kind or kind=="Instance" end
 return v
end
for p in sources do node(p) end
local function signal()local s={};function s:Connect(_)return {Disconnect=function()end} end;return s end
local attrs={BrainrotTestDiagnosticsDisabled=true}
local gameProxy={PlaceId=91958083796436,GameId=10548905405,PlaceVersion=822,JobId="SOURCE_ONLY_FAKE_BACKEND"}
local denied=0
local function forbid()denied+=1;error("SOURCE-ONLY GUARD: real network API blocked",2)end
local players={PlayerAdded=signal(),PlayerRemoving=signal()}
function players:GetPlayers()return {} end
function players:GetPlayerByUserId()return nil end
local run={Heartbeat=signal(),RenderStepped=signal()}
function run:IsStudio()return true end
function run:IsServer()return true end
function run:IsClient()return false end
function run:IsRunning()return false end
local workspaceProxy={}
function workspaceProxy:GetServerTimeNow()return 1000 end
function workspaceProxy:GetAttribute(k)return attrs[k] end
function workspaceProxy:FindFirstChild()return nil end
local services={ServerStorage=node('ServerStorage'),ReplicatedStorage=node('ReplicatedStorage'),ServerScriptService=node('ServerScriptService'),Players=players,RunService=run,Workspace=workspaceProxy,
 DataStoreService=setmetatable({},{__index=function()return forbid end}),MarketplaceService=setmetatable({},{__index=function(_,k)if k:match('Finished$') then return signal() end;return forbid end}),AnalyticsService=setmetatable({},{__index=function()return forbid end})}
function gameProxy:GetService(n)
 if not services[n] then
  if n=='HttpService' or n=='EncodingService' then services[n]=nativeGame:GetService(n)
  else services[n]=setmetatable({},{__index=function(_,k) if k=='FindFirstChild' then return function()return nil end end; if k=='GetChildren' or k=='GetDescendants' then return function()return {} end end;return forbid end}) end
 end
 return services[n]
end
function gameProxy:GetAttribute(k)return attrs[k] end
function gameProxy:SetAttribute(k,v)attrs[k]=v end
function gameProxy:BindToClose()error('No boot allowed in a source-only fixture')end
gameProxy.ReplicatedStorage=services.ReplicatedStorage;gameProxy.Workspace=workspaceProxy
local cache={};local loading={};local sourceEnvironment=getfenv()
local function req(module)
 assert(type(module)=='table' and module._path,'Unexpected external require')
 local p=module._path
 if cache[p]~=nil then return cache[p] end
 assert(not loading[p],'Circular require '..p)
 assert(sources[p],'Missing bundled source '..p)
 loading[p]=true
 local fn,err=loadstring(sources[p],'@'..p);assert(fn,err)
 setfenv(fn,setmetatable({game=gameProxy,workspace=workspaceProxy,script=module,require=req,print=record,warn=record},{__index=sourceEnvironment}))
 local value=fn();cache[p]=value;loading[p]=nil;return value
end
local function print(...)record(...)end
local function warn(...)record(...)end
local function typeof(v)return sourceEnvironment.typeof(v)end
__DSL__
for _,name in __SPECS__ do
 local specModule=node('ServerScriptService.Server.Tests.'..name:gsub('%.','_DOT_'))
 totals.Files+=1;currentSpecName=name;table.clear(suiteStack)
 local before={totals.Tests,totals.Passed,totals.Failed}
 local ok,why=xpcall(function()
  local factory=req(specModule);local env=getfenv(factory)
  setfenv(factory,setmetatable({describe=describe,it=it,expect=expectValue},{__index=env}));factory()
 end,debug.traceback)
 if not ok then totals.FileErrors+=1;record('[FILE_ERROR]',name,why) end
 record('[FILE]',name,totals.Tests-before[1],totals.Passed-before[2],totals.Failed-before[3]);task.wait()
end
return {kind='SOURCE_ONLY_NATIVE_LUAU_FAKE_BACKEND',placeId=nativeGame.PlaceId,universeId=nativeGame.GameId,editVersion=nativeGame.PlaceVersion,totals=totals,networkGuardCalls=denied,lines=lines,nativeSourceWrites=0,serverLaunches=0}
'''
runner=(root/'scripts/studio-test-runner.luau').read_text()
dsl=runner[runner.index('local suiteStack = {}'):runner.index('local specModules = {}')]
if args.scope=='affected':
 dsl=dsl.replace('\ttotals.Tests += 1','\tif currentSpecName ~= "Phase13CommerceCapacity.spec" and currentSpecName ~= "PlayerProfileStore.spec" and currentSpecName ~= "Phase13ReceiptArchive.spec" then return end\n\ttotals.Tests += 1')
elif args.scope=='safety':
 dsl=dsl.replace('\ttotals.Tests += 1','\tlocal wanted=currentSpecName=="Phase13ReceiptArchive.spec" and (name:find("makes real room",1,true) or name:find("three full",1,true) or name:find("actual encoded maximum",1,true) or name:find("delivers a pending",1,true))\n\tif not wanted then return end\n\ttotals.Tests += 1')
loader=loader.replace('__SOURCES__',','.join('['+json.dumps(p)+']='+lua(s) for p,s in selected.items()))
loader=loader.replace('__DSL__',dsl).replace('__SPECS__','{'+','.join(json.dumps(s) for s in specs)+'}')
Path('/private/tmp/p13_receipt_bundle.luau').write_text(loader)
Path('/private/tmp/p13_receipt_bundle_manifest.json').write_text(json.dumps({'modules':{k:str(paths[k].relative_to(root)) for k in selected},'unresolved':sorted(unresolved),'mockedUnrelatedDefaults':sorted(stubs),'bytes':len(loader)}))
