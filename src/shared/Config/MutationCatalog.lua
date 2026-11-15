--!strict
-- Conditional shares within mutated NEW spawns; absolute odds derive from Phase12.MutationChance.
local entries={
 {id="None",displayName="Normal",multiplier=1,share=0,floor=0},
 {id="Shiny",displayName="Shiny",multiplier=1.5,share=.45,floor=1},
 {id="Golden",displayName="Golden",multiplier=2.5,share=.25,floor=2},
 {id="Glitched",displayName="Glitched",multiplier=4,share=.15,floor=4},
 {id="Radioactive",displayName="Radioactive",multiplier=7,share=.0875,floor=5},
 {id="Astral",displayName="Astral",multiplier=15,share=.0625,floor=6},
}
local byId={}
for _,row in entries do byId[row.id]=table.freeze(row)end
return table.freeze({Order=table.freeze(entries),ById=table.freeze(byId)})
