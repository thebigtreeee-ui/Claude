-- ElementBeams (ModuleScript in ReplicatedStorage): aims and colours the Blender beam and blast models.
--
-- Expects ReplicatedStorage.ElementBeamModels (beams) and ReplicatedStorage.ElementBlastModels (blasts),
-- holding the imported models named after the element ("Fire") or the file ("FireBeam", "FireBlast").
-- Each model keeps the tiny Start/End marker parts from Blender; they tell this module which way the
-- model points, however the import was scaled or rotated.
--
--   local ElementBeams = require(game.ReplicatedStorage.ElementBeams)
--   ElementBeams.fire("Fire", handPosition, hitPosition)   -- beam
--   ElementBeams.blast("Fire", handPosition, hitPosition)  -- projectile
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local DESIGN_LENGTH = 24 -- beam: studs from Start to End after normalising; thickness is designed around this
local BLAST_LENGTH = 8 -- blast: studs from tail (Start) to nose (End) at size 1
local BLAST_CORE = 0.75 -- the blast's core sits this far along from Start to End

local ElementBeams = {}

local function style(r, g, b, material, transparency)
	return { Color = Color3.fromRGB(r, g, b), Material = material, Transparency = transparency or 0 }
end

local Neon = Enum.Material.Neon

-- Part name -> look. Spin is how fast (radians/sec) the whole beam rolls around its own axis.
ElementBeams.Styles = {
	Fire = {
		Spin = 9,
		Core = style(255, 240, 180, Neon),
		Flames = style(255, 120, 20, Neon, 0.05),
		Wisps = style(255, 60, 15, Neon, 0.15),
	},
	Ice = {
		Spin = 0,
		Core = style(225, 250, 255, Neon),
		Crystal = style(150, 215, 255, Enum.Material.Glass, 0.35),
		Shards = style(190, 235, 255, Enum.Material.Ice, 0.1),
	},
	Electric = {
		Spin = 0,
		Bolt = style(245, 230, 255, Neon), -- white-hot lilac
		Branches = style(130, 80, 255, Neon), -- violet
		Sheath = style(140, 60, 235, Enum.Material.ForceField, 0), -- deep purple plasma
	},
	Nature = {
		Spin = 3,
		Core = style(140, 255, 120, Neon),
		Vines = style(70, 95, 40, Enum.Material.Wood),
		Leaves = style(80, 175, 60, Enum.Material.Grass),
		Blossoms = style(255, 150, 205, Enum.Material.SmoothPlastic),
	},
	Void = {
		Spin = -6,
		Core = style(8, 4, 14, Enum.Material.SmoothPlastic),
		Horizon = style(140, 60, 255, Enum.Material.ForceField, 0),
		Tendrils = style(95, 20, 190, Neon),
		Rings = style(190, 120, 255, Neon),
		Debris = style(25, 15, 40, Enum.Material.Slate),
	},
	Rift = {
		Spin = 2,
		Core = style(220, 255, 255, Neon),
		Tear = style(170, 245, 250, Enum.Material.Glass, 0.15),
		EdgeMagenta = style(40, 220, 230, Neon), -- cyan now; the part keeps its original name
		EdgeCyan = style(40, 220, 230, Neon),
		Fragments = style(190, 245, 245, Enum.Material.Glass, 0.3),
		Gates = style(30, 200, 200, Neon),
	},
	Wind = {
		Spin = 12, -- the fastest roll of the lot: it's a cyclone
		Core = style(235, 255, 248, Neon, 0.1),
		Streams = style(160, 240, 215, Neon, 0.25),
		Rings = style(150, 235, 215, Enum.Material.ForceField, 0),
		Blades = style(215, 255, 240, Neon, 0.15),
	},
}

local function markers(model)
	local startPart = model:FindFirstChild("Start", true)
	local endPart = model:FindFirstChild("End", true)
	assert(startPart and endPart, model:GetFullName() .. " is missing its Start/End markers")
	return startPart, endPart
end

-- Colours a template and scales it so Start to End spans `length` studs. Safe to call more than once.
function ElementBeams.prepare(template, element, length)
	if template:GetAttribute("ElementBeamPrepared") then
		return template
	end
	local looks = ElementBeams.Styles[element]
	assert(looks, "No beam style for element " .. tostring(element))

	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			local look = looks[part.Name]
			if look then
				part.Color = look.Color
				part.Material = look.Material
				part.Transparency = look.Transparency
			elseif part.Name == "Start" or part.Name == "End" then
				part.Transparency = 1
			else
				warn("ElementBeams: no style for part " .. part:GetFullName())
			end
			part:SetAttribute("BaseTransparency", part.Transparency)
		end
	end

	local startPart, endPart = markers(template)
	local current = (endPart.Position - startPart.Position).Magnitude
	template:ScaleTo(template:GetScale() * (length or DESIGN_LENGTH) / current)
	template:SetAttribute("ElementBeamPrepared", true)
	return template
end

local function findTemplate(element, folderName, suffix, length)
	local folder = ReplicatedStorage:WaitForChild(folderName)
	local template = folder:FindFirstChild(element) or folder:FindFirstChild(element .. suffix)
	assert(template, "ReplicatedStorage." .. folderName .. " has no model for " .. element)
	return ElementBeams.prepare(template, element, length)
end

-- Returns a copy of the element's beam running from origin to target. `width` scales thickness (default 1).
-- Only the length is stretched, so the detail (flames, shards, leaves) keeps its shape across the beam's width.
function ElementBeams.place(element, origin, target, width)
	width = width or 1
	local model = findTemplate(element, "ElementBeamModels", "Beam", DESIGN_LENGTH):Clone()
	local startPart, endPart = markers(model)
	local from = CFrame.lookAt(startPart.Position, endPart.Position)
	local to = CFrame.lookAt(origin, target)
	local stretch = (target - origin).Magnitude / (endPart.Position - startPart.Position).Magnitude

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local relative = from:ToObjectSpace(part.CFrame)
			local p = relative.Position
			relative = relative.Rotation + Vector3.new(p.X * width, p.Y * width, p.Z * stretch)

			-- Stretch whichever of the part's own axes runs along the beam.
			local along = part.CFrame:VectorToObjectSpace(from.LookVector)
			local ax, ay, az = math.abs(along.X), math.abs(along.Y), math.abs(along.Z)
			part.Size = part.Size
				* Vector3.new(
					(ax >= ay and ax >= az) and stretch or width,
					(ay > ax and ay >= az) and stretch or width,
					(az > ax and az > ay) and stretch or width
				)
			part.CFrame = to * relative
		end
	end
	model.WorldPivot = to
	return model
end

local function fadeAll(model, time, toBase)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in model:GetDescendants() do
		local base = part:GetAttribute("BaseTransparency")
		if base and base < 1 then
			TweenService:Create(part, info, { Transparency = toBase and base or 1 }):Play()
		end
	end
end

-- Shows a beam from origin to target for `hold` seconds, then fades it out. Returns the model.
function ElementBeams.fire(element, origin, target, options)
	options = options or {}
	local fadeIn = options.fadeIn or 0.08
	local hold = options.hold or 0.35
	local fadeOut = options.fadeOut or 0.25

	local model = ElementBeams.place(element, origin, target, options.width)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	model.Parent = options.parent or workspace
	fadeAll(model, fadeIn, true)

	local spin = ElementBeams.Styles[element].Spin or 0
	if spin ~= 0 then
		local pivot, angle = model.WorldPivot, 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not model.Parent then
				connection:Disconnect()
				return
			end
			angle += spin * dt
			model:PivotTo(pivot * CFrame.Angles(0, 0, angle))
		end)
	end

	task.delay(fadeIn + hold, fadeAll, model, fadeOut, false)
	Debris:AddItem(model, fadeIn + hold + fadeOut + 0.1)
	return model
end

-- Launches the element's blast from origin and flies it to target, rolling as it goes. Calls
-- options.onArrive(target) when it gets there, then removes it. Options: speed (studs/sec, default 90),
-- size (default 1), parent. Returns the model. Purely visual: do your hit detection as you do now.
function ElementBeams.blast(element, origin, target, options)
	options = options or {}
	local speed = options.speed or 90
	local model = findTemplate(element, "ElementBlastModels", "Blast", BLAST_LENGTH):Clone()
	if options.size and options.size ~= 1 then
		model:ScaleTo(model:GetScale() * options.size)
	end

	local startPart, endPart = markers(model)
	local tail, nose = startPart.Position, endPart.Position
	model.WorldPivot = CFrame.lookAt(tail:Lerp(nose, BLAST_CORE), nose)

	local offset = target - origin
	local distance = offset.Magnitude
	local direction = distance > 0 and offset.Unit or Vector3.zAxis
	local spin = (ElementBeams.Styles[element].Spin or 0) * 1.5
	local travelled, angle = 0, 0
	model:PivotTo(CFrame.lookAt(origin, origin + direction))
	model.Parent = options.parent or workspace

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then
			connection:Disconnect()
			return
		end
		travelled = math.min(travelled + speed * dt, distance)
		angle += spin * dt
		local position = origin + direction * travelled
		model:PivotTo(CFrame.lookAt(position, position + direction) * CFrame.Angles(0, 0, angle))
		if travelled >= distance then
			connection:Disconnect()
			model:Destroy()
			if options.onArrive then
				options.onArrive(target)
			end
		end
	end)
	Debris:AddItem(model, distance / speed + 5) -- safety net if Heartbeat stops reaching it
	return model
end

return ElementBeams
