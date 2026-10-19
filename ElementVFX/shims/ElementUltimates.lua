-- ElementUltimates (ModuleScript in ReplicatedStorage): replace the old module's code with this.
-- The game's existing calls keep working, but now play the new ElementVFX ultimates.
local VFX = require(game:GetService("ReplicatedStorage"):WaitForChild("Eternium"):WaitForChild("ElementVFX"))

local ElementUltimates = {}

-- a CFrame at the character's feet, facing where they look
function ElementUltimates.feet(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local down = humanoid and (humanoid.HipHeight + root.Size.Y / 2) or 3
	return root.CFrame * CFrame.new(0, -down, 0)
end

function ElementUltimates.play(element, at, options)
	if typeof(at) == "Instance" then -- a character was passed
		at = ElementUltimates.feet(at)
	end
	return VFX.ultimate(element, at, options)
end

function ElementUltimates.prepare() end -- the old Blender-model setup step is no longer needed

return ElementUltimates
