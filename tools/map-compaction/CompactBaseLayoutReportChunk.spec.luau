local fs=require('@lune/fs')
local Roblox=require('@lune/roblox')
local source=fs.readFile('/Users/noahodukoya/development/Roblox/BrainrotExpedition/tools/map-compaction/CompactBaseLayoutPlayReadOnly.server.luau')
local begin=assert(string.find(source,' local cursor,count=1,0',1,true))
local finish=assert(string.find(source,' output:SetAttribute("ChecksPassed"',begin,true))
local actual=string.sub(source,begin,finish-1)
local runner=assert(loadstring('return function(encoded,output,Instance)\n'..actual..'\nreturn output\nend'))()
local cases={string.rep('a',500161),string.rep('é',35001)..string.rep('x',60000),string.rep('😀',30003)..'終',string.rep('a',59999)..'😀'..string.rep('b',61000)}
for i,text in cases do
 local folder=Roblox.Instance.new('Folder');runner(text,folder,Roblox.Instance)
 local list={}
 for n=1,folder:GetAttribute('ChunkCount') do
  local v=folder:FindFirstChild(string.format('Chunk_%04d',n));assert(v and #v.Value<=60000)
  assert(utf8.len(v.Value)~=nil,'split UTF8 at '..i..':'..n);list[n]=v.Value
 end
 assert(table.concat(list)==text and folder:GetAttribute('JSONBytes')==#text)
 folder:Destroy()
end
print('4/4 actual-source chunk loop cases passed; UTF8 valid and exact bytes, native output limit NOT simulated')
