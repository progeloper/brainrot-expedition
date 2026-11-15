#!/usr/bin/env python3
"""Compose exact-hash guarded new source proposals, never overwrite existing sources."""
from pathlib import Path
import difflib,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/map-compaction'
OUT=DOC/'source-patches'
BASE=DOC/'live-sources'
EXPECTED={
 'ReplicatedStorage/Shared/Config/BaseLayoutConfig.lua':'fec81ec990b6f2837150781feaef1f90055adf336b2987ae440a22e128cf332e',
 'ServerScriptService/Server/Systems/BaseIncomePlaqueSystem.lua':'36abfff76ed6d107ae63c7fe0b72882f2de09d1840b784f1fe04153f71320574',
 'ServerScriptService/Server/Systems/RegionSpawnCatalog.lua':'9d0952524437e03e5591f66d0fe7919a7c356a7537e95324b56c70dc585af598',
 'ServerScriptService/Server/Systems/BrainrotSaleSystem.lua':'559c2ffaeca7c871c792b37a5b341c7d5567459f6eeaaa7c1e1d474789dd1a48',
 'ServerScriptService/Server/Services/UpgradeService.lua':'87535911505d969f75ed22c30df8bb86439e4b1807f121e632ea965c08beea1b',
}
def sha(text):return hashlib.sha256(text.encode()).hexdigest()
def replace(source,old,new):
 assert source.count(old)==1,('unique exact source anchor required',old[:90],source.count(old))
 return source.replace(old,new,1)
def base_config(source):
 source=replace(source,'--!strict\n','--!strict\n\nlocal CompactMapGeometry = require(game:GetService("ReplicatedStorage").Shared.Utility.CompactMapGeometry)\n')
 return replace(source,'return table.freeze(BaseLayoutConfig)','-- Compact values are final evaluated locals; all original scale/economy constants remain unchanged.\nfunction BaseLayoutConfig.GetGeometry(base: Model): any?\n\treturn CompactMapGeometry.ResolveBase(base)\nend\n\nreturn table.freeze(BaseLayoutConfig)')
def base_owner(s):
 s=replace(s,'type StructuralStyle = {\n	Color: Color3,','type StructuralStyle = {\n	PostWidth: number?,\n	PostDepth: number?,\n	Color: Color3,')
 s=replace(s,'	pillar.Size = Vector3.new(PILLAR_WIDTH_STUDS, pillarHeight, PILLAR_DEPTH_STUDS)','	pillar.Size = Vector3.new(style.PostWidth or PILLAR_WIDTH_STUDS, pillarHeight, style.PostDepth or PILLAR_DEPTH_STUDS)')
 s=replace(s,'\tstyle: StructuralStyle\n)\n\tclearManagedPillars(container)','\tstyle: StructuralStyle,\n\tgeometry: any?\n)\n\tclearManagedPillars(container)')
 s=replace(s,'\tlocal halfWidth = (Config.BASE_FOOTPRINT_WIDTH_STUDS - PILLAR_ORIGINAL_WIDTH_STUDS) / 2\n\tlocal halfDepth = (Config.BASE_FOOTPRINT_DEPTH_STUDS - PILLAR_ORIGINAL_DEPTH_STUDS) / 2\n\tlocal frontZ = entranceSign(base, root) * halfDepth\n\tlocal backZ = -frontZ\n\tlocal frontLeft = Vector3.new(-halfWidth, 0, frontZ)\n\tlocal frontRight = Vector3.new(halfWidth, 0, frontZ)\n\tlocal backLeft = Vector3.new(-halfWidth, 0, backZ)\n\tlocal backRight = Vector3.new(halfWidth, 0, backZ)', '\tlocal perimeter = if geometry then geometry.perimeter else nil\n\tlocal width = if perimeter then perimeter.width else Config.BASE_FOOTPRINT_WIDTH_STUDS\n\tlocal depth = if perimeter then perimeter.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS\n\tlocal centreX = if perimeter then perimeter.centreX else 0\n\tlocal centreZ = if perimeter then perimeter.centreZ else 0\n\tlocal postWidth = if perimeter then perimeter.postWidth else PILLAR_WIDTH_STUDS\n\tlocal postDepth = if perimeter then perimeter.postDepth else PILLAR_DEPTH_STUDS\n\tstyle = table.clone(style)\n\tstyle.PostWidth = postWidth\n\tstyle.PostDepth = postDepth\n\tlocal halfWidth = (width - (if perimeter then postWidth * 2 else PILLAR_ORIGINAL_WIDTH_STUDS)) / 2\n\tlocal halfDepth = (depth - (if perimeter then postDepth * 2 else PILLAR_ORIGINAL_DEPTH_STUDS)) / 2\n\tlocal frontSign = if perimeter and perimeter.frontSign then perimeter.frontSign else entranceSign(base, root)\n\tlocal frontZ = centreZ + frontSign * halfDepth\n\tlocal backZ = centreZ - frontSign * halfDepth\n\tlocal frontLeft = Vector3.new(centreX - halfWidth, 0, frontZ)\n\tlocal frontRight = Vector3.new(centreX + halfWidth, 0, frontZ)\n\tlocal backLeft = Vector3.new(centreX - halfWidth, 0, backZ)\n\tlocal backRight = Vector3.new(centreX + halfWidth, 0, backZ)')
 s=replace(s,'return math.abs(localPosition.X) < ENTRANCE_CLEAR_WIDTH_STUDS / 2','return math.abs(localPosition.X - centreX) < ENTRANCE_CLEAR_WIDTH_STUDS / 2')
 s=replace(s,'local function ensureInterior(base: Model, root: CFrame, platformFloorY: number): number','local function ensureInterior(base: Model, root: CFrame, platformFloorY: number, geometry: any?): number')
 s=replace(s, '	local floor: BasePart? = nil\n	for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do\n		local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)\n		if candidate and candidate:IsA("BasePart") then\n			floor = candidate\n			break\n		end\n	end', '	local floor: BasePart? = nil\n	if geometry then\n		-- Compact support reuses the migrated authoritative Foundation. No coplanar runtime floor.\n		local foundation = base:FindFirstChild("Foundation")\n		assert(foundation and foundation:IsA("BasePart") and foundation:GetAttribute("LayoutRole") == "Foundation", "Compact base Foundation is missing or has changed identity")\n		floor = foundation :: BasePart\n	else\n		for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do\n			local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)\n			if candidate and candidate:IsA("BasePart") then\n				floor = candidate\n				break\n			end\n		end\n	end')
 s=replace(s,'\tresolvedFloor.Size = Vector3.new(\n\t\tConfig.BASE_FOOTPRINT_WIDTH_STUDS,\n\t\tfloorThickness,\n\t\tConfig.BASE_FOOTPRINT_DEPTH_STUDS\n\t)\n\tresolvedFloor.CFrame = root * CFrame.new(0, floorTopY - floorThickness / 2, 0)', '\tlocal support = if geometry then geometry.support else nil\n\tresolvedFloor.Size = Vector3.new(\n\t\tif support then support.width else Config.BASE_FOOTPRINT_WIDTH_STUDS,\n\t\tfloorThickness,\n\t\tif support then support.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS\n\t)\n\tresolvedFloor.CFrame = root * CFrame.new(\n\t\tif support then support.centreX else 0, floorTopY - floorThickness / 2,\n\t\tif support then support.centreZ else 0\n\t)')
 s=replace(s,'\tconfigureStructuralPart(resolvedFloor)', '\tif geometry then\n\t\t-- Retain the authoritative Foundation colour, flags and effective physics.\n\t\tStaticMaterial.Apply(resolvedFloor)\n\telse\n\t\tconfigureStructuralPart(resolvedFloor)\n\tend')
 s=replace(s,'createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle)','createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle, geometry)')
 s=replace(s,'local function positionPlatforms(root: CFrame, slots: { any }): (any, number)','local function positionPlatforms(root: CFrame, slots: { any }, geometry: any?): (any, number)')
 s=replace(s,'\t\tlocal x = side * Config.PLATFORM_ROW_OFFSET_X\n\t\tlocal z = Config.PLATFORM_Z_CENTERS[row]','\t\tlocal canonical = if geometry then geometry.slots[slot.Index] else nil\n\t\tassert(not canonical or (canonical.Index == slot.Index and canonical.Side == side), "Compact stable slot identity changed")\n\t\tlocal x = if canonical then canonical.X else side * Config.PLATFORM_ROW_OFFSET_X\n\t\tlocal z = if canonical then canonical.Z else Config.PLATFORM_Z_CENTERS[row]\n\t\tlocal normalSize = if canonical then canonical.PadNormalStuds else Config.PLATFORM_SIDE_STUDS\n\t\tlocal tangentSize = if canonical then canonical.PadTangentialStuds else Config.PLATFORM_SIDE_STUDS\n\t\tlocal aisleX = if geometry then geometry.formationCenterX else 0')
 s=replace(s,'Vector3.new(0, localPosition.Y, localPosition.Z),','Vector3.new(aisleX, localPosition.Y, localPosition.Z),')
 s=replace(s,'Vector3.new(Config.PLATFORM_SIDE_STUDS, platform.Size.Y, Config.PLATFORM_SIDE_STUDS)','Vector3.new(tangentSize, platform.Size.Y, normalSize)')
 s=replace(s,'\t\t\tSide = side,\n\t\t\tZCenter = z,','\t\t\tSide = side,\n\t\t\tXCenter = x,\n\t\t\tZCenter = z,\n\t\t\tPlatformNormalStuds = normalSize,')
 s=replace(s,'\tlocal inward = Config.PLATFORM_SIDE_STUDS / 2','\tlocal inward = placement.PlatformNormalStuds / 2')
 s=replace(s,'\tlocal plaqueX = placement.Side * (Config.PLATFORM_ROW_OFFSET_X - inward)','\tlocal plaqueX = placement.XCenter - placement.Side * inward')
 s=replace(s,'\tteardownBase(base, false)\n\tlocal root = baseRootCFrame(base)\n\tlocal placementById, platformFloorY = positionPlatforms(root, slots)\n\tlocal floorTopY = ensureInterior(base, root, platformFloorY)', '\t-- Resolve/validate before any teardown: marked compact data must never fall back.\n\tlocal geometry = Config.GetGeometry(base)\n\tteardownBase(base, false)\n\tlocal root = baseRootCFrame(base)\n\tlocal placementById, platformFloorY = positionPlatforms(root, slots, geometry)\n\tlocal floorTopY = ensureInterior(base, root, platformFloorY, geometry)')
 return s

def spawn_owner(s):
 s=replace(s,'local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)','local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)\nlocal CompactMapGeometry = require(ReplicatedStorage.Shared.Utility.CompactMapGeometry)')
 s=replace(s,'\tmapArtFootprintsValid: boolean,','\tmapArtFootprintsValid: boolean,\n\tstaticWallIndex: any,\n\tstaticWallObstaclesValid: boolean,')
 s=replace(s,'\tlocal mapArtFootprints, mapArtFootprintsError = readInstalledMapArtFootprints(map)','\tlocal mapArtFootprints, mapArtFootprintsError = readInstalledMapArtFootprints(map)\n\tlocal compact = CompactMapGeometry.Read(map)')
 s=replace(s,'\t\tMapArtFootprintsError = mapArtFootprintsError,','\t\tMapArtFootprintsError = mapArtFootprintsError,\n\t\tStaticWallObstacles = if compact then compact.staticWallObstacles else {},')
 s=replace(s,'\tlocal index: Index = {','\t-- Separate bounded geometry layer; never append walls to the 343-art-row contract.\n\tlocal wallsValid, wallIndex = pcall(CompactMapGeometry.BuildWallIndex, context.StaticWallObstacles or {})\n\tif not wallsValid then\n\t\taddIssue(report, "Error", "INVALID_STATIC_WALL_OBSTACLES", tostring(wallIndex))\n\t\twallIndex = CompactMapGeometry.BuildWallIndex({})\n\tend\n\tlocal index: Index = {')
 s=replace(s,'\t\tmapArtFootprintsValid = mapArtFootprintsError == nil,','\t\tmapArtFootprintsValid = mapArtFootprintsError == nil,\n\t\tstaticWallIndex = wallIndex,\n\t\tstaticWallObstaclesValid = wallsValid,')
 s=replace(s,'): (boolean, string?, string?)\n\tif ignoredRegionId ~= Regions.CampId then','): (boolean, string?, string?)\n\tif not index.staticWallObstaclesValid then return true, "INVALID_STATIC_WALL_OBSTACLES", nil end\n\tlocal wallId = CompactMapGeometry.WallHit(index.staticWallIndex, frame, size, 0)\n\tif wallId then return true, "STATIC_WALL_OBSTACLE_OVERLAP", wallId end\n\tif ignoredRegionId ~= Regions.CampId then')
 anchor='\tfor _, boundary in index.boundariesByRegion[normalizedRegion] do\n\t\tif boxFitsPart(envelopeFrame, envelopeSize, boundary, padding) then\n\t\t\treturn true, nil'
 s=replace(s,anchor,'\tif not index.staticWallObstaclesValid then return false, "INVALID_STATIC_WALL_OBSTACLES" end\n\tif CompactMapGeometry.WallHit(index.staticWallIndex, envelopeFrame, envelopeSize, 0) then\n\t\treturn false, "STATIC_WALL_OBSTACLE_OVERLAP"\n\tend\n'+anchor)
 s=replace(s,'\tif not index.mapArtFootprintsValid then\n\t\ttable.insert(reasons, "INVALID_MAP_ART_FOOTPRINTS")\n\tend','\tif not index.mapArtFootprintsValid then\n\t\ttable.insert(reasons, "INVALID_MAP_ART_FOOTPRINTS")\n\tend\n\tif not index.staticWallObstaclesValid then table.insert(reasons, "INVALID_STATIC_WALL_OBSTACLES") end')
 s=replace(s,'\tlocal clear, clearanceReason =\n\t\tvalidateClearance(index, envelopeFrame, envelopeSize, area, definition)','\tif #index.staticWallIndex.rows > 0 then\n\t\tlocal nativeFrame, nativeSize, nativeReason = getMapArtEnvelope(index, definition)\n\t\tif nativeFrame == nil or nativeSize == nil then\n\t\t\ttable.insert(reasons, nativeReason or "INVALID_MAP_ART_ENVELOPE")\n\t\telseif CompactMapGeometry.WallHit(index.staticWallIndex, placementPivot * nativeFrame, nativeSize, 2) then\n\t\t\ttable.insert(reasons, "STATIC_WALL_OBSTACLE_OVERLAP")\n\t\tend\n\tend\n\tlocal clear, clearanceReason =\n\t\tvalidateClearance(index, envelopeFrame, envelopeSize, area, definition)')
 return s

def sale_owner(s):
 s=replace(s,'local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)','local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)\nlocal CompactMapGeometry = require(ReplicatedStorage.Shared.Utility.CompactMapGeometry)')
 return replace(s,'local halfSize = salePoint.Size * 0.5','local halfSize = CompactMapGeometry.ResolveInteractionSize(salePoint) * 0.5')
def upgrade_owner(s):
 s=replace(s,'local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)','local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)\nlocal CompactMapGeometry = require(ReplicatedStorage.Shared.Utility.CompactMapGeometry)')
 return replace(s,'local halfSize = shop.Size * 0.5','local halfSize = CompactMapGeometry.ResolveInteractionSize(shop) * 0.5')

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 baseline=json.loads((DOC/'BeforeManifest.json').read_text());manifest=[];payload=[]
 patchers=[base_config,base_owner,spawn_owner,sale_owner,upgrade_owner]
 assert len(patchers)==len(EXPECTED)
 for (file,expected),patch in zip(EXPECTED.items(),patchers):
  old=(BASE/file).read_text();assert sha(old)==expected,('fresh source hash drift',file)
  new=patch(old);dest=OUT/'proposals'/file;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(new)
  diff=''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='actual-before/'+file,tofile='proposal/'+file))
  diffpath=OUT/'diffs'/file;diffpath=diffpath.with_suffix('.diff');diffpath.parent.mkdir(parents=True,exist_ok=True);diffpath.write_text(diff)
  record={'path':file[:-4].replace('/','.'),'beforeSHA256':expected,'afterSHA256':sha(new),'beforeBytes':len(old.encode()),'afterBytes':len(new.encode()),'proposal':str(dest.relative_to(ROOT)),'diff':str(diffpath.relative_to(ROOT))}
  manifest.append(record);payload.append({**record,'beforeSource':old,'afterSource':new})
 geometry=(ROOT/'tools/map-compaction/source-templates/CompactMapGeometry.lua').read_text()
 dest=OUT/'proposals/ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua';dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(geometry)
 added={'path':'ReplicatedStorage.Shared.Utility.CompactMapGeometry','class':'ModuleScript','afterSHA256':sha(geometry),'afterBytes':len(geometry.encode()),'proposal':str(dest.relative_to(ROOT))}
 installers=[]
 for file in ['assets/InstallProgressionGate.luau','assets/InstallBeachGate.luau','assets/InstallProgressionBoundaries.luau','assets/VerifyProgressionBoundaries.luau','assets/map-art/InstallMapArtImportedMeshes.luau','assets/map-art/InstallMapArt.template.luau']:
  old=(ROOT/file).read_text()
  guard='-- Guard historical geometry before any write/readback claim.\ndo\n local map=workspace:FindFirstChild("MapBlockout")\n assert(not map or (map:GetAttribute("CompactMapMigrationId")==nil and map:GetAttribute("CompactMapStatus")==nil and map:GetAttribute("CompactMapDesiredHash")==nil and map:FindFirstChild("CompactMapRuntimeGeometry")==nil), "Historical installer is superseded by canonical CompactMap_V1; refusing old coordinates")\nend\n'
  new=old.replace('--!strict\n','--!strict\n\n'+guard,1) if old.startswith('--!strict\n') else guard+old
  target=OUT/'installers'/file;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(new)
  diff=''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile=file,tofile='guarded-proposal/'+file))
  dp=OUT/'diffs'/file;dp=dp.with_suffix('.diff');dp.parent.mkdir(parents=True,exist_ok=True);dp.write_text(diff)
  installers.append({'path':file,'beforeSHA256':sha(old),'afterSHA256':sha(new),'proposal':str(target.relative_to(ROOT)),'diff':str(dp.relative_to(ROOT)),'method':'Reject any marked compact layout before writes; canonical migration owns geometry.'})
 result={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'SourceProposalsOnly','baselineSourceBundleSHA256':baseline['sourceBundleSHA256'],'managedBaselineSHA256':baseline['baselineManagedContentSHA256'],'runtimeManifestMaximumBytes':200000,'patchedOwners':manifest,'newOwners':[added],'guardedInstallerProposals':installers,'unchanged':['Currency/profile/schema/key/version/economy','current35brainrotassets/catalog/scales/attachments','cartcontrols/cargodimensions','roamranges/strides/decisionrates','existingcaptureLOS and progressionrules','343artfootprintschema'],'notClaimed':['Native patched-owner runtime fit','Studio source installation','World application','Gameplay/performance acceptance']}
 (OUT/'SourcePatchManifest.json').write_text(json.dumps(result,indent=2)+'\n')
 transfer=json.dumps({'patches':payload,'newModule':{**added,'source':geometry}},separators=(',',':'))
 (OUT/'SourcePatchPayload.json').write_text(transfer+'\n')
 n=0
 while ']'+('='*n)+']' in transfer:n+=1
 quoted='['+'='*n+'['+transfer+']'+'='*n+']'
 apply=(ROOT/'tools/map-compaction/source-templates/ApplyCompactSourcePatches.template.luau').read_text().replace('__PAYLOAD_JSON_LUA__',quoted)
 (ROOT/'tools/map-compaction/ApplyCompactSourcePatches.luau').write_text(apply)
 result['applyHelper']={'path':'tools/map-compaction/ApplyCompactSourcePatches.luau','sha256':sha(apply),'bytes':len(apply.encode()),'execution':'PreparedOnly','scope':'Five exact original Source fields and one new Utility ModuleScript; rollback journal outside Workspace.'}
 (OUT/'SourcePatchManifest.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'owners':len(manifest),'newModules':1,'installerGuards':len(installers),'status':result['status']}))

if __name__=='__main__':main()
