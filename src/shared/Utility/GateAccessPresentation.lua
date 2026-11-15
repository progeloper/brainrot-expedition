--!strict
-- The existing server summary is the only entitlement input. No physics writes.
local Policy={}
function Policy.Apply(model: Model,allowed: boolean,name: string)
    local door=model:FindFirstChild("DoorPresentation")
    if not door or not door:IsA("BasePart")then return end
    door.LocalTransparencyModifier=if allowed then 1 else 0
    for _,x in ipairs(door:GetDescendants())do
        if x:IsA("SurfaceGui")then x.Enabled=not allowed
        elseif x:IsA("TextLabel")then x.Text="LOCKED\n"..name:upper()end
    end
end
return table.freeze(Policy)
