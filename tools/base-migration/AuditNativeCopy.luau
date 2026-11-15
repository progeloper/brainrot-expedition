local fs=require('@lune/fs') local roblox=require('@lune/roblox') local serde=require('@lune/serde')
local path='/Users/noahodukoya/Documents/BrainrotExpedition_DEV_BaseMigration_Final_2026-10-13.rbxl'
local data=fs.readFile(path) local game=roblox.deserializePlace(data)
local expected=serde.decode('json',fs.readFile('/private/tmp/DevBaseMigrationProposals/Source_Manifest.json'))
local wanted={} for _,r in expected do table.insert(wanted,r.path..'\0'..r.class..'\0'..r.afterSHA256) end table.sort(wanted)
local actual={} for _,n in game:GetDescendants() do if n:IsA('LuaSourceContainer') then table.insert(actual,n:GetFullName()..'\0'..n.ClassName..'\0'..serde.hash('sha256',n.Source)) end end table.sort(actual)
assert(#actual==420 and serde.encode('json',actual)==serde.encode('json',wanted),'saved native source mismatch')
local ws=game:GetService('Workspace') local root=ws.MapBlockout.PlayerBasePatches local counts={bases=0,parts=0,markers=0,art=0}
for _,b in root:GetChildren() do counts.bases+=1 assert(b:IsA('Model') and b:GetAttribute('BaseId')==b.Name and b:GetAttribute('AuthoredBaseLayout')==true,'invalid sole authority') assert(b:FindFirstChild('BaseFloor',true)==nil and b:FindFirstChild('Phase5DInterior',true)==nil,'legacy interior persisted')
 for _,n in b:GetDescendants() do if n:IsA('BasePart') then counts.parts+=1 if n:IsA('MeshPart') then counts.art+=1 end end if n.Name=='BrainrotPlacement' then counts.markers+=1 end end
 for i=1,12 do local p=b:FindFirstChild(string.format('Slot_%02d',i)) assert(p and p:IsA('BasePart') and p:FindFirstChild('BrainrotPlacement'),'native platform schema lost') end
 for _,name in {'CartSpawn','PlayerSpawn','DepositReturnZone','Foundation','CartDisplay','CartRamp','HouseRamp','Primary','Support','Accent'} do assert(b:FindFirstChild(name),'native child lost '..name) end
end
assert(counts.bases==12 and counts.parts==264 and counts.markers==144 and counts.art==36,'native counts')
assert(#ws.MapBlockout.MapArt.BaseShells:GetChildren()==0,'duplicate shells persisted')
local rs=game:GetService('ReplicatedStorage') assert(#rs.StudioAssets.Brainrots:GetChildren()==35,'brainrot roster count')
local backup=game:GetService('ServerStorage'):FindFirstChild('AuthoredBaseMigration_Backup_v1') assert(backup and backup:GetAttribute('NoRuntimeUse')==true,'native backup missing')
local out={passed=true,path=path,bytes=#data,sha256=serde.hash('sha256',data),sourceCount=#actual,sourceDigest=serde.hash('sha256',table.concat(actual,'\n')),counts=counts,brainrots=35,backupPreserved=true,wholePlaceReserialized=false}
fs.writeFile('/private/tmp/DevBaseMigrationProposals/Native_Copy_Audit.json',serde.encode('json',out,true)) print(out)
