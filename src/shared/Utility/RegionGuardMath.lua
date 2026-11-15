--!strict
local Guard = {}
function Guard.IsValidNormal(normal: any): boolean
	return typeof(normal)=="Vector3" and normal.X==normal.X and normal.Y==normal.Y and normal.Z==normal.Z
		and math.abs(normal.Magnitude-1)<1e-6 and math.abs(normal.Y)<1e-6
end
function Guard.RemoveInwardVelocity(velocity: Vector3, normal: Vector3): Vector3
	if not Guard.IsValidNormal(normal) then return velocity end
	return velocity-normal*math.max(0,velocity:Dot(normal))
end
function Guard.ProjectedHalfExtent(frame: CFrame, size: Vector3, normal: Vector3): number
	return math.abs(frame.RightVector:Dot(normal))*size.X/2
		+math.abs(frame.UpVector:Dot(normal))*size.Y/2
		+math.abs(frame.LookVector:Dot(normal))*size.Z/2
end
function Guard.WouldCross(position: Vector3, velocity: Vector3, plane: Vector3, normal: Vector3,
	footprint: number, interval: number, thresholdHalfDepth: number): boolean
	if not Guard.IsValidNormal(normal) or velocity:Dot(normal)<=0 then return false end
	return (position-plane):Dot(normal)+footprint+velocity:Dot(normal)*interval >= -thresholdHalfDepth
end
return table.freeze(Guard)
