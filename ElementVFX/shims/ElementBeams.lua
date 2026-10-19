-- ElementBeams (ModuleScript in ReplicatedStorage): replace the old module's code with this.
-- The game's existing calls keep working, but now play the new ElementVFX effects.
local VFX = require(game:GetService("ReplicatedStorage"):WaitForChild("Eternium"):WaitForChild("ElementVFX"))

local ElementBeams = {}

function ElementBeams.fire(element, origin, target, options)
	return VFX.beam(element, origin, target, options)
end

function ElementBeams.blast(element, origin, target, options)
	return VFX.blast(element, origin, target, options)
end

function ElementBeams.prepare() end -- the old Blender-model setup step is no longer needed

return ElementBeams
