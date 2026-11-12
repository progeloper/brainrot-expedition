--!strict
-- Exact native template paths, inspected 2026-10-22. Unmapped mechanics/signals stay original.
local Maps = {}
Maps["BDS_001"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_002"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.LodgeEave"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_003"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.TideglassBlade"]="Accent1",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_004"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.BoglightTerrace"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_005"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.CanopyCrown"]="Accent1",["Phase13Architecture.SelectedDesign.CanopyTower"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_006"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.FrostBattlement"]="Accent1",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_007"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.MagmaBand"]="Accent1",["Phase13Architecture.SelectedDesign.MagmaButtress"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BDS_008"] = table.freeze({["Accent"]="Accent2",["CartRamp"]="Secondary",["Foundation"]="Primary",["HouseRamp"]="Secondary",["Phase13Architecture.EntryCrown"]="Accent1",["Phase13Architecture.EntryPillar"]="Primary",["Phase13Architecture.SelectedDesign.AstralDiamond"]="Accent1",["Phase13Architecture.SelectedDesign.AstralSpire"]="Primary",["Primary"]="Primary",["Support"]="Hardware"})
Maps["BastionWagon"] = table.freeze({["Visual.Phase13Appearance.CornerBattlement"]="EdgeBand",["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.ShieldedProw"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["CometSkimmer"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.LongCometNose"]="Primary",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.SweptWing"]="Secondary",["Visual.Phase13Appearance.TailWake"]="Accent1",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["DuneRunner"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.LowWindshield"]="Hardware",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.SlenderRunner"]="EdgeBand",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["IronHauler"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HaulerButtress"]="Secondary",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.ReinforcedBumper"]="Hardware",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["NeonCruiser"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.LongLightRail"]="Accent1",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.SplitNose"]="Secondary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["ObsidianFortress"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.FortressProw"]="Primary",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.ObsidianSpire"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand",["Visual.Phase13Appearance.VioletFault1"]="Accent1",["Visual.Phase13Appearance.VioletFault2"]="Accent2",["Visual.Phase13Appearance.VioletFault3"]="Accent1"})
Maps["ScrapChariot"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.PatchPlate1"]="Accent1",["Visual.Phase13Appearance.PatchPlate2"]="Hardware",["Visual.Phase13Appearance.PatchPlate3"]="Accent2",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.TimberRearBar"]="Secondary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["StarforgeChariot"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.ForgedWing"]="Primary",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.OctagonalCore"]="Accent2",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["VoltDasher"] = table.freeze({["Visual.Phase13Appearance.CuboidWheel"]="Hardware",["Visual.Phase13Appearance.HubPlate"]="Accent2",["Visual.Phase13Appearance.LightningStep1"]="Accent1",["Visual.Phase13Appearance.LightningStep2"]="Accent2",["Visual.Phase13Appearance.LightningStep3"]="Accent1",["Visual.Phase13Appearance.LightningStep4"]="Accent2",["Visual.Phase13Appearance.NosePlate"]="Secondary",["Visual.Phase13Appearance.OutriggerFin"]="Secondary",["Visual.Phase13Appearance.RearCargoDeck"]="Primary",["Visual.Phase13Appearance.SideRail"]="Primary",["Visual.Phase13Appearance.UpperEdge"]="EdgeBand"})
Maps["WPN_C01"] = table.freeze({["Phase13Appearance.BoltRail"]="Hardware",["Phase13Appearance.Bowstring"]="Hardware",["Phase13Appearance.Grip"]="Hardware",["Phase13Appearance.HorizontalProd"]="Primary",["Phase13Appearance.ScrapBrace"]="Hardware",["Phase13Appearance.Stock"]="Secondary"})
Maps["WPN_G01"] = table.freeze({["Phase13Appearance.Barrel"]="Primary",["Phase13Appearance.Grip"]="Hardware",["Phase13Appearance.MuzzleCollar"]="EdgeBand",["Phase13Appearance.Receiver"]="Secondary",["Phase13Appearance.TinPatch"]="EdgeBand"})
-- Camp Rework (12 Nov 2026): v2 weapon art (HRP_001, WPN_B/C/G 02-08 and WPN_SP_*) is mapped by part
-- name with the same rules the art converter used (tools/camp-rework/WeaponConverter.luau), so every
-- converted part keeps a finish role without a hand-written table per weapon.
local WEAPON_NAME_RULES = {
	{ "Hardware", { "Grip", "Wrap", "Handle", "Trigger", "Guard", "Latch", "Rivet", "Bolt", "Pin", "Cap", "Mount", "String", "Serving", "Nock", "Axle", "Hub" } },
	{ "EdgeBand", { "Stripe", "Edge", "Band", "Trim", "Rim", "Ring", "Seam", "Line", "Collar" } },
	{ "Accent1", { "Gem", "Glow", "Core", "Orb", "Crystal", "Neon", "Glint", "Lens", "Halo" } },
	{ "Primary", { "Limb", "Body", "Stock", "Barrel", "Rail", "Shell", "Horn", "Riser", "Hull", "Prod", "Lance", "Plate", "Armor", "Receiver", "Tank" } },
}
local function weaponRoleByName(name: string): string
	for _, rule in WEAPON_NAME_RULES do
		for _, key in rule[2] do
			if string.find(name, key, 1, true) then
				return rule[1]
			end
		end
	end
	return "Secondary"
end
local Roles = { Templates = table.freeze(Maps), WeaponRoleByName = weaponRoleByName }
local architecture = table.freeze({ ThemePrimary="Primary", ThemeAccent="Accent1", Slab="Secondary", Stair="Secondary", Tread="Secondary", Rail="EdgeBand" })
function Roles.Base(part: BasePart): string?
 local role=part:GetAttribute("Phase13Role")
 if type(role)=="string" then return architecture[role] end
 return ({Primary="Primary",Accent="Accent2",Support="Hardware",Foundation="Primary",HouseRamp="Secondary",CartRamp="Secondary"})[part.Name]
end
function Roles.Resolve(model: Instance, part: BasePart, category: string, templateId: string): string?
 local map=Maps[templateId]
 if not map then
  if category=="Weapon" and (model.Name=="Phase13Appearance" or model.Name=="Phase13WeaponArt") and part~=model then
   return weaponRoleByName(part.Name)
  end
  return nil
 end
 local path=if part==model then part.Name else part:GetFullName():sub(#model:GetFullName()+2)
 if category=="Cart" and model.Name=="Visual" then path="Visual."..path
 elseif category=="Cart" and model.Name=="Phase13Appearance" then path="Visual.Phase13Appearance."..path
 elseif category=="Weapon" and (model.Name=="Phase13Appearance" or model.Name=="Phase13WeaponArt") then path="Phase13Appearance."..path end
 return map[path]
end
return table.freeze(Roles)
