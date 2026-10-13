-- ElementUltimates (ModuleScript in ReplicatedStorage): plays the animated ultimate-move models.
--
-- Expects ReplicatedStorage.ElementUltimateModels holding the imported models, named after the
-- element ("Rift") or the file ("RiftUltimate"). Each model keeps three tiny marker parts from
-- Blender: Start (the user's feet), End (10 studs forward) and Top (10 studs up). This module reads
-- them to find which way the model faces, however the import was scaled or rotated, then animates
-- every other part frame by frame.
--
--   local ElementUltimates = require(game.ReplicatedStorage.ElementUltimates)
--   ElementUltimates.play("Void", ElementUltimates.feet(character))
--   ElementUltimates.play("Nature", ElementUltimates.feet(character), { color = Color3.fromRGB(255, 120, 220) })
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UNIT = 10 -- studs from Start to End (and Start to Top) at size 1

local ElementUltimates = {}

local function style(r, g, b, material, transparency)
	return { Color = Color3.fromRGB(r, g, b), Material = material, Transparency = transparency or 0 }
end

local Neon = Enum.Material.Neon
local Glass = Enum.Material.Glass
local ForceField = Enum.Material.ForceField

-- Part name -> look. Numbered parts (Wall_03, Trunk_05...) use the style of their base name.
ElementUltimates.Styles = {
	Rift = {
		Frame = style(150, 240, 250, Glass, 0.2),
		Swirl = style(40, 220, 230, Neon, 0.35),
		Tunnel = style(30, 200, 200, Neon, 0.45),
		Core = style(230, 255, 255, Neon),
		Cracks = style(40, 220, 230, Neon),
		Fragments = style(190, 245, 245, Glass, 0.3),
	},
	Electric = {
		Cloud = style(35, 32, 45, Enum.Material.SmoothPlastic),
		CloudGlow = style(140, 60, 235, Neon, 0.5),
		Rain = style(190, 170, 255, Neon, 0.6),
		Bolt = style(245, 230, 255, Neon),
	},
	Fire = {
		Core = style(255, 240, 180, Neon),
		Flames = style(255, 120, 20, Neon, 0.05),
		Wisps = style(255, 60, 15, Neon, 0.15),
		Embers = style(255, 180, 60, Neon),
	},
	Ice = {
		Shockwave = style(200, 240, 255, Neon, 0.3),
		Frost = style(220, 245, 255, Enum.Material.Ice, 0.3),
		Spike = style(190, 235, 255, Glass, 0.2),
		Wall = style(150, 215, 255, Enum.Material.Ice, 0.15),
	},
	Nature = {
		Roots = style(90, 230, 130, Neon, 0.2),
		Trunk = style(70, 55, 40, Enum.Material.Wood),
		Canopy = style(110, 255, 160, Neon, 0.25),
		Glow = style(220, 255, 180, Neon),
		Petals = style(150, 255, 190, Neon, 0.2),
	},
	Wind = {
		Hand = style(170, 255, 230, ForceField, 0),
		Shockwave = style(200, 255, 240, Neon, 0.4),
		Streams = style(160, 240, 215, Neon, 0.3),
		Blades = style(215, 255, 240, Neon, 0.2),
	},
	Void = {
		Core = style(8, 4, 14, Enum.Material.SmoothPlastic),
		Horizon = style(140, 60, 255, ForceField, 0),
		Ring = style(205, 185, 255, Neon),
		Disk = style(130, 60, 255, Neon, 0.2),
		DiskOuter = style(90, 30, 200, Neon, 0.45),
		Jets = style(165, 140, 255, Neon, 0.3),
		Debris = style(25, 15, 40, Enum.Material.Slate),
	},
}

-- Which parts `options.color` repaints for each element (the glowing, "energy" parts).
ElementUltimates.Recolorable = {
	Rift = { "Swirl", "Cracks", "Tunnel" },
	Electric = { "CloudGlow", "Rain" },
	Fire = { "Flames", "Wisps", "Embers" },
	Ice = { "Shockwave", "Spike" },
	Nature = { "Canopy", "Glow", "Roots", "Petals" },
	Wind = { "Hand", "Streams", "Blades", "Shockwave" },
	Void = { "Disk", "DiskOuter", "Jets", "Ring", "Horizon" },
}

-- ---------------------------------------------------------------- easing

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

-- 0 before a, 1 after b, linear in between
local function phase(t, a, b)
	return clamp01((t - a) / (b - a))
end

local function outQuad(x)
	return 1 - (1 - x) * (1 - x)
end

local function inQuad(x)
	return x * x
end

local function outBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function flat(s)
	return Vector3.new(math.max(s, 0.01), 1, math.max(s, 0.01))
end

-- ---------------------------------------------------------------- animations
--
-- Model space: X = the user's right, Y = up, -Z = forward, origin = the user's feet.
-- c.v(x, y, z) builds a model-space point already scaled to the ultimate's size.
-- Each part() returns how to show one part at time t:
--   scale (number or Vector3, model axes), pivot (scale about this point), rot (CFrame rotation),
--   rotPivot, offset (Vector3), alpha (0 = invisible, 1 = its normal transparency).

local Animations = {}

Animations.Rift = {
	duration = 5,
	part = function(r, t, c)
		local C = c.v(0, 6.2, -10)
		local outro = phase(t, 4.3, 4.9)
		local shrink = 1 - inQuad(outro)
		local p = r.prefix
		if p == "Cracks" then
			return { scale = math.max(outQuad(phase(t, 0, 0.35)), 0.01), pivot = C, alpha = 1 - phase(t, 4.0, 4.6) }
		elseif p == "Frame" then
			local e = outBack(phase(t, 0.15, 0.75))
			return { scale = math.max(e * shrink, 0.01), pivot = C, rot = CFrame.Angles(0, 0, (1 - e) * -2 + outro * 3), rotPivot = C }
		elseif p == "Swirl" then
			return {
				scale = math.max(outQuad(phase(t, 0.3, 0.9)) * shrink, 0.01),
				pivot = C,
				rot = CFrame.Angles(0, 0, t * 3),
				rotPivot = C,
				alpha = phase(t, 0.3, 0.6),
			}
		elseif p == "Tunnel" then
			return {
				scale = math.max(outQuad(phase(t, 0.5, 1.1)) * shrink, 0.01),
				pivot = C,
				rot = CFrame.Angles(0, 0, -t * 1.5),
				rotPivot = C,
				alpha = phase(t, 0.5, 0.8),
			}
		elseif p == "Core" then
			local flash = phase(t, 4.6, 5)
			local s = outBack(phase(t, 0.5, 0.9)) * (1 + 0.12 * math.sin(t * 12)) * shrink + flash * 3
			return { scale = math.max(s, 0.01), pivot = C, alpha = 1 - flash }
		else -- Fragments
			return {
				scale = math.max(outQuad(phase(t, 0.4, 1.0)) * shrink, 0.01),
				pivot = C,
				rot = CFrame.Angles(0, 0, -t * 0.8),
				rotPivot = C,
			}
		end
	end,
}

Animations.Electric = {
	duration = 7,
	setup = function(c)
		-- each bolt strikes a few times at random moments, from a random angle round the storm
		c.strikes = {}
		for i = 1, 6 do
			local list = {}
			local time = 1.2 + c.random:NextNumber(0, 0.8)
			while time < 6.0 do
				table.insert(list, { time = time, yaw = c.random:NextNumber(0, math.pi * 2) })
				time += c.random:NextNumber(0.5, 1.4)
			end
			c.strikes[i] = list
		end
	end,
	frame = function(t, c)
		c.flash = 0
		for _, list in c.strikes do
			for _, strike in list do
				if t >= strike.time and t < strike.time + 0.14 then
					c.flash = 1
				end
			end
		end
	end,
	part = function(r, t, c)
		local CC = c.v(0, 26, -14)
		local ground = c.v(0, 0, -14)
		local appear = outQuad(phase(t, 0, 1.2))
		local fade = phase(t, 6.2, 7)
		local p = r.prefix
		if p == "Cloud" or p == "CloudGlow" then
			local alpha = appear * (1 - fade)
			if p == "CloudGlow" then
				alpha *= 0.35 + 0.65 * c.flash
			end
			return {
				scale = 0.25 + 0.75 * appear + 0.1 * fade,
				pivot = CC,
				rot = CFrame.Angles(0, t * 0.08, 0),
				rotPivot = CC,
				alpha = alpha,
			}
		elseif p == "Rain" then
			local period = 4 * c.size
			return { offset = Vector3.new(0, -((t * 45 * c.size) % period), 0), alpha = phase(t, 1, 1.5) * (1 - phase(t, 6, 6.6)) }
		else -- Bolt_NN
			for _, strike in c.strikes[r.index] or {} do
				local since = t - strike.time
				if since >= 0 and since < 0.14 then
					local flicker = (since < 0.05 or since > 0.09) and 1 or 0.25
					return { rot = CFrame.Angles(0, strike.yaw, 0), rotPivot = ground, alpha = flicker }
				end
			end
			return { alpha = 0 }
		end
	end,
}

Animations.Fire = {
	duration = 4,
	part = function(r, t, c)
		local axis = c.v(0, 3.2, -1.5) -- the hands; the flames pour forwards (-Z) from here
		local grow = outQuad(phase(t, 0, 0.35))
		local fade = phase(t, 3.3, 4)
		local width = 1 - 0.5 * fade
		local stretch = Vector3.new(width, width, math.max(grow, 0.02))
		local p = r.prefix
		if p == "Core" then
			stretch *= Vector3.new(1 + 0.06 * math.sin(t * 31), 1 + 0.06 * math.sin(t * 27), 1)
			return { scale = stretch, pivot = axis, alpha = 1 - fade }
		elseif p == "Flames" then
			return { scale = stretch, pivot = axis, rot = CFrame.Angles(0, 0, t * 7), rotPivot = axis, alpha = 1 - fade }
		elseif p == "Wisps" then
			return { scale = stretch, pivot = axis, rot = CFrame.Angles(0, 0, -t * 5), rotPivot = axis, alpha = 1 - fade }
		else -- Embers drift upwards and forwards
			return {
				scale = stretch,
				pivot = axis,
				rot = CFrame.Angles(0, 0, t * 1.5),
				rotPivot = axis,
				offset = Vector3.new(0, ((t * 2) % 2) * c.size, 0),
				alpha = (1 - fade) * phase(t, 0.2, 0.5),
			}
		end
	end,
}

Animations.Ice = {
	duration = 6,
	part = function(r, t, c)
		local p = r.prefix
		if p == "Shockwave" then
			local e = outQuad(phase(t, 0, 0.6))
			return { scale = flat(0.1 + 1.5 * e), pivot = Vector3.zero, alpha = 1 - phase(t, 0.2, 0.7) }
		elseif p == "Frost" then
			return { scale = flat(outQuad(phase(t, 0, 0.9))), pivot = Vector3.zero, alpha = 1 - phase(t, 5.2, 6) }
		end
		-- Spike_NN / Wall_NN: burst out of the ground in a wave travelling away from the stomp,
		-- then sink back in the same order
		local delay = 0.05 + r.distance / (40 * c.size)
		local rise = phase(t, delay, delay + 0.3)
		if rise <= 0 then
			return { alpha = 0 }
		end
		local e = outBack(rise)
		local sink = inQuad(phase(t, 4.6 + r.distance / (60 * c.size), 5.4 + r.distance / (60 * c.size)))
		local ground = Vector3.new(r.pos.X, 0, r.pos.Z)
		return {
			scale = Vector3.new(0.5 + 0.5 * e, math.max(e, 0.01), 0.5 + 0.5 * e),
			pivot = ground,
			offset = Vector3.new(0, -sink * r.height, 0),
			alpha = 1 - sink,
		}
	end,
}

Animations.Nature = {
	duration = 8,
	part = function(r, t, c)
		local fade = phase(t, 7, 8)
		local wither = inQuad(fade)
		local p = r.prefix
		local index = r.index or 1
		local base = Vector3.new(r.pos.X, 0, r.pos.Z)
		local sway = CFrame.Angles(math.sin(t * 1.3 + index) * 0.03, 0, math.cos(t * 1.1 + index) * 0.03)
		if p == "Roots" then
			return { scale = flat(outQuad(phase(t, 0, 0.9))), pivot = Vector3.zero, alpha = 1 - fade }
		elseif p == "Trunk" then
			local start = 0.25 + (index - 1) * 0.12
			local grow = phase(t, start, start + 0.7)
			if grow <= 0 then
				return { alpha = 0 }
			end
			return {
				scale = math.max(outBack(grow), 0.01),
				pivot = base,
				rot = sway,
				rotPivot = base,
				offset = Vector3.new(0, -wither * r.height, 0),
				alpha = 1 - wither,
			}
		elseif p == "Canopy" or p == "Glow" then
			local start = 0.8 + (index - 1) * 0.12
			local bloom = phase(t, start, start + 0.5)
			if bloom <= 0 then
				return { alpha = 0 }
			end
			local s = outBack(bloom) * (1 + 0.03 * math.sin(t * 2 + index)) * (1 - wither)
			local alpha = 1 - fade
			if p == "Glow" then
				alpha *= 0.55 + 0.45 * math.sin(t * 3 + index)
			end
			return { scale = math.max(s, 0.01), pivot = r.pos, rot = sway, rotPivot = base, alpha = alpha }
		else -- Petals drift round the grove
			return {
				rot = CFrame.Angles(0, t * 0.35, 0),
				rotPivot = Vector3.zero,
				offset = Vector3.new(0, 0.4 * c.size * math.sin(t * 1.5), 0),
				alpha = phase(t, 1, 1.8) * (1 - fade),
			}
		end
	end,
}

Animations.Wind = {
	duration = 2.2,
	part = function(r, t, c)
		local W = c.v(0, 7, -7) -- where the hands meet
		local clap = 0.45
		local p = r.prefix
		if p == "Hand" then
			-- the hands start wide open at the sides and slam together, speeding up as they close
			local side = r.pos.X > 0 and 1 or -1
			local open = 1 - inQuad(phase(t, 0.1, clap))
			return {
				scale = 1 + 0.15 * phase(t, clap, 1.1),
				pivot = W,
				rot = CFrame.Angles(0, -side * 0.7 * open, 0),
				rotPivot = W,
				offset = Vector3.new(side * 9 * c.size * open, 0, 0),
				alpha = phase(t, 0, 0.15) * (1 - phase(t, 0.7, 1.1)),
			}
		end
		if t < clap then
			return { alpha = 0 }
		end
		if p == "Shockwave" then
			local e = outQuad(phase(t, clap, clap + 0.7))
			return {
				scale = 0.2 + 1.3 * e,
				pivot = W,
				offset = Vector3.new(0, 0, -28 * c.size * e),
				alpha = 1 - phase(t, clap + 0.3, clap + 1.0),
			}
		elseif p == "Streams" then
			local e = outQuad(phase(t, clap, clap + 0.35))
			return { scale = Vector3.new(1, 1, math.max(e, 0.01)), pivot = W, alpha = 1 - phase(t, clap + 0.6, clap + 1.2) }
		else -- Blades fly out with the shockwave, spinning
			local e = outQuad(phase(t, clap, clap + 1.0))
			return {
				rot = CFrame.Angles(0, 0, t * 6),
				rotPivot = W,
				offset = Vector3.new(0, 0, -35 * c.size * e),
				alpha = 1 - phase(t, clap + 0.6, clap + 1.1),
			}
		end
	end,
}

local DISK_NORMAL = Vector3.new(0, math.cos(math.rad(20)), math.sin(math.rad(20))) -- matches the Blender tilt

Animations.Void = {
	duration = 8,
	part = function(r, t, c)
		local V = c.v(0, 9, -16)
		local intro = outBack(phase(t, 0, 0.7))
		local collapse = 1 - inQuad(phase(t, 7.1, 7.6))
		local flash = phase(t, 7.6, 8)
		local p = r.prefix
		if p == "Core" or p == "Horizon" then
			return { scale = math.max(intro * collapse * (1 + 0.04 * math.sin(t * 4)), 0.01), pivot = V }
		elseif p == "Ring" then
			-- squeezed with the core, then flashes outwards as the black hole snaps shut
			return {
				scale = math.max(intro * collapse + flash * 4, 0.01),
				pivot = V,
				rot = CFrame.fromAxisAngle(DISK_NORMAL, t),
				rotPivot = V,
				alpha = 1 - flash,
			}
		elseif p == "Disk" or p == "DiskOuter" then
			local outer = p == "DiskOuter"
			local e = outQuad(phase(t, outer and 0.5 or 0.3, outer and 1.6 or 1.3))
			return {
				scale = math.max((0.3 + 0.7 * e) * collapse, 0.01),
				pivot = V,
				rot = CFrame.fromAxisAngle(DISK_NORMAL, t * (outer and 1.2 or 2.5)),
				rotPivot = V,
				alpha = phase(t, 0.3, 0.7),
			}
		elseif p == "Jets" then
			local e = outQuad(phase(t, 0.9, 1.6))
			if e <= 0 then
				return { alpha = 0 }
			end
			return { scale = Vector3.new(collapse, math.max(e * collapse, 0.01), collapse), pivot = V }
		else -- Debris spirals in and gets crushed
			local pull = 1 - 0.45 * phase(t, 1, 7)
			return {
				scale = math.max(pull * collapse * outQuad(phase(t, 0.4, 1.2)), 0.01),
				pivot = V,
				rot = CFrame.fromAxisAngle(DISK_NORMAL, t * 1.8),
				rotPivot = V,
			}
		end
	end,
}

ElementUltimates.Animations = Animations

-- ---------------------------------------------------------------- plumbing

local function lookFor(model, name)
	local part = model:FindFirstChild(name, true)
	assert(part, model:GetFullName() .. " is missing its " .. name .. " marker")
	return part
end

-- The frame the model was built in: its origin at the user's feet, LookVector forward, UpVector up.
local function markerFrame(model)
	local start = lookFor(model, "Start").Position
	local forward = lookFor(model, "End").Position - start
	local up = lookFor(model, "Top").Position - start
	local f, u = forward.Unit, up.Unit
	return CFrame.fromMatrix(start, f:Cross(u), u, -f), forward.Magnitude
end

local function isMarker(part)
	return part.Name == "Start" or part.Name == "End" or part.Name == "Top"
end

local function baseName(name)
	local prefix, index = string.match(name, "^(.-)_(%d+)$")
	if prefix then
		return prefix, tonumber(index)
	end
	return name, nil
end

-- Colours a template and scales it so its markers are UNIT studs apart. Safe to call more than once.
function ElementUltimates.prepare(template, element)
	if template:GetAttribute("ElementUltimatePrepared") then
		return template
	end
	local looks = ElementUltimates.Styles[element]
	assert(looks, "No ultimate style for element " .. tostring(element))
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			local look = looks[baseName(part.Name)]
			if look then
				part.Color = look.Color
				part.Material = look.Material
				part.Transparency = look.Transparency
			elseif isMarker(part) then
				part.Transparency = 1
			else
				warn("ElementUltimates: no style for part " .. part:GetFullName())
			end
		end
	end
	local _, length = markerFrame(template)
	template:ScaleTo(template:GetScale() * UNIT / length)
	template:SetAttribute("ElementUltimatePrepared", true)
	return template
end

local function findTemplate(element)
	local folder = ReplicatedStorage:WaitForChild("ElementUltimateModels")
	local template = folder:FindFirstChild(element) or folder:FindFirstChild(element .. "Ultimate")
	assert(template, "ReplicatedStorage.ElementUltimateModels has no model for " .. element)
	return ElementUltimates.prepare(template, element)
end

local function apply(rest, frame, state)
	local s = state.scale or 1
	if type(s) == "number" then
		s = Vector3.new(s, s, s)
	end
	local pivot = state.pivot or rest.pos
	local pos = pivot + (rest.pos - pivot) * s
	local orientation = rest.rot
	if state.rot then
		local rotPivot = state.rotPivot or pivot
		pos = rotPivot + state.rot:VectorToWorldSpace(pos - rotPivot)
		orientation = state.rot.Rotation * orientation
	end
	if state.offset then
		pos += state.offset
	end
	-- map the model-axis scale onto the part's own axes (imported parts are axis-aligned with the model)
	local partScale = rest.rot:VectorToObjectSpace(s)
	local part = rest.part
	part.Size = rest.size
		* Vector3.new(
			math.max(math.abs(partScale.X), 0.001),
			math.max(math.abs(partScale.Y), 0.001),
			math.max(math.abs(partScale.Z), 0.001)
		)
	part.CFrame = frame * (CFrame.new(pos) * orientation)
	part.Transparency = 1 - math.clamp(state.alpha or 1, 0, 1) * (1 - rest.transparency)
end

-- The CFrame at a character's feet, facing where the character faces. Pass it to play().
function ElementUltimates.feet(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(root and humanoid, "feet() needs a character with a HumanoidRootPart and Humanoid")
	return root.CFrame - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
end

-- Plays an element's ultimate at `at` (a CFrame at the user's feet; only its position and the
-- horizontal part of its facing are used). Options:
--   size     scale of the whole effect (default 1)
--   color    Color3 that repaints the element's glowing parts (see ElementUltimates.Recolorable)
--   colors   { PartName = Color3 } for full control, e.g. { Canopy = ..., Trunk = ... }
--   parent   where the model goes (default workspace)
--   onFinished  called when the effect ends and the model is removed
-- Returns the model and the effect's duration in seconds. Purely visual: damage stays in your scripts.
function ElementUltimates.play(element, at, options)
	options = options or {}
	local animation = Animations[element]
	assert(animation, "No ultimate animation for element " .. tostring(element))
	local size = options.size or 1

	local model = findTemplate(element):Clone()
	if size ~= 1 then
		model:ScaleTo(model:GetScale() * size)
	end

	local paint = {}
	if options.color then
		for _, name in ElementUltimates.Recolorable[element] or {} do
			paint[name] = options.color
		end
	end
	for name, color in options.colors or {} do
		paint[name] = color
	end

	local frame0 = markerFrame(model)
	local rests = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if isMarker(part) then
				part.Transparency = 1
			else
				local prefix, index = baseName(part.Name)
				if paint[prefix] then
					part.Color = paint[prefix]
				end
				local cf = frame0:ToObjectSpace(part.CFrame)
				local rot = cf.Rotation
				table.insert(rests, {
					part = part,
					prefix = prefix,
					index = index,
					pos = cf.Position,
					rot = rot,
					size = part.Size,
					transparency = part.Transparency,
					height = math.abs(rot:VectorToWorldSpace(part.Size).Y),
					distance = Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude,
				})
			end
		end
	end

	local look = at.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	local frame = CFrame.lookAt(at.Position, at.Position + look.Unit)

	local context = {
		size = size,
		random = Random.new(),
		v = function(x, y, z)
			return Vector3.new(x, y, z) * size
		end,
	}
	if animation.setup then
		animation.setup(context)
	end

	local t = 0
	local function step()
		if animation.frame then
			animation.frame(t, context)
		end
		for _, rest in rests do
			apply(rest, frame, animation.part(rest, t, context))
		end
	end
	step()
	model.Parent = options.parent or workspace

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t >= animation.duration or not model.Parent then
			connection:Disconnect()
			model:Destroy()
			if options.onFinished then
				options.onFinished()
			end
			return
		end
		step()
	end)
	return model, animation.duration
end

return ElementUltimates
