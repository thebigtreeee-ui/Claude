-- ElementUltimates (ModuleScript in ReplicatedStorage): plays the animated ultimate-move models.
--
-- Expects ReplicatedStorage.ElementUltimateModels holding the imported models, named after the
-- element ("Rift") or the file ("RiftUltimate"). Each model keeps three tiny marker parts from
-- Blender: Start (the user's feet), End (10 studs forward) and Top (10 studs up). This module reads
-- them to find which way the model faces, however the import was scaled or rotated, animates every
-- other part frame by frame, and adds particles, lights and live-generated lightning on top.
--
--   local ElementUltimates = require(game.ReplicatedStorage.ElementUltimates)
--   ElementUltimates.play("Void", ElementUltimates.feet(character))
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
local Smooth = Enum.Material.SmoothPlastic

-- Part name -> look. Numbered parts (Wall_03, Spike_05...) use the style of their base name.
ElementUltimates.Styles = {
	Rift = {
		Abyss = style(245, 252, 255, Neon), -- the blinding white inside of the tear
		Edge = style(215, 250, 255, Neon),
		Glow = style(70, 190, 210, ForceField, 0),
		Depth = style(80, 200, 220, Neon, 0.5),
		Cracks = style(120, 225, 240, Neon, 0.15),
		Shards = style(185, 225, 235, Glass, 0.35),
	},
	Electric = {
		Cloud = style(52, 52, 62, Smooth, 0.05),
		CloudBase = style(28, 28, 36, Smooth),
		CloudGlow = style(150, 110, 230, Neon, 0.4),
		Rain = style(160, 165, 190, Neon, 0.7),
	},
	Fire = {
		Core = style(255, 235, 190, Neon, 0.25),
		Shell = style(255, 140, 50, ForceField, 0),
		OuterShell = style(220, 70, 25, ForceField, 0),
	},
	Ice = {
		Frost = style(205, 230, 240, Enum.Material.Ice, 0.45),
		Cracks = style(170, 225, 245, Neon, 0.35),
		Spike = style(190, 225, 240, Glass, 0.25),
		Wall = style(180, 215, 230, Glass, 0.3),
		WallCore = style(95, 145, 180, Enum.Material.Ice, 0.1),
	},
	Wind = {
		Flash = style(240, 250, 250, Neon, 0.3),
		Rings = style(215, 235, 235, ForceField, 0),
		GroundRing = style(205, 215, 210, ForceField, 0),
		Streaks = style(215, 232, 230, Neon, 0.55),
		Debris = style(120, 115, 105, Enum.Material.Slate),
	},
	Void = {
		Core = style(8, 4, 14, Smooth),
		Horizon = style(140, 60, 255, ForceField, 0),
		Ring = style(205, 185, 255, Neon),
		Disk = style(130, 60, 255, Neon, 0.2),
		DiskOuter = style(90, 30, 200, Neon, 0.45),
		Jets = style(165, 140, 255, Neon, 0.3),
		Debris = style(25, 15, 40, Enum.Material.Slate),
	},
	Earth = {
		Fissure = style(255, 160, 60, Neon),
		Rubble = style(110, 95, 80, Enum.Material.Slate),
		Slab = style(100, 86, 72, Enum.Material.Slate),
		Spire = style(85, 74, 64, Enum.Material.Slate),
		Boulder = style(95, 82, 70, Enum.Material.Slate),
	},
	Water = {
		Wave = style(60, 150, 220, Glass, 0.3),
		Crest = style(235, 245, 255, Smooth, 0.15),
		Swirl = style(150, 215, 255, Neon, 0.5),
		Spray = style(225, 240, 255, Glass, 0.2),
		Foam = style(230, 242, 250, Smooth, 0.35),
	},
	Energy = {
		Beam = style(255, 255, 255, Neon),
		BeamGlow = style(90, 200, 255, Neon, 0.35),
		BeamAura = style(40, 140, 255, ForceField, 0),
		BeamCoils = style(160, 230, 255, Neon, 0.25),
		Head = style(110, 210, 255, Neon, 0.3),
		Ball = style(255, 255, 255, Neon),
		BallGlow = style(90, 200, 255, Neon, 0.3),
		Rings = style(190, 235, 255, Neon, 0.4),
		Aura = style(90, 200, 255, ForceField, 0),
		Cracks = style(150, 220, 255, Neon, 0.2),
		Rocks = style(105, 95, 85, Enum.Material.Slate),
	},
}

-- Which parts `options.color` repaints for each element. The element's particles and lightning
-- follow `options.color` too.
ElementUltimates.Recolorable = {
	Rift = { "Edge", "Glow", "Depth", "Cracks" },
	Electric = { "CloudGlow" },
	Fire = { "Core", "Shell", "OuterShell" },
	Ice = { "Cracks", "Frost" },
	Wind = { "Flash", "Rings", "GroundRing", "Streaks" },
	Void = { "Disk", "DiskOuter", "Jets", "Ring", "Horizon" },
	Earth = { "Fissure" },
	Water = { "Wave", "Swirl" },
	Energy = { "BeamGlow", "BeamAura", "BeamCoils", "Head", "BallGlow", "Rings", "Aura", "Cracks" },
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

local function outQuart(x)
	return 1 - (1 - x) ^ 4
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

-- ---------------------------------------------------------------- particles, lights and helpers

local TEXTURE = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
}

local function numbers(points, scale)
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2] * (scale or 1)))
	end
	return NumberSequence.new(keys)
end

local function colors(points)
	local keys = {}
	for _, point in points do
		table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keys)
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- An invisible anchored part at a model-space CFrame, to hang particles and lights on.
-- Its volume is the emission area; its front face (LookVector) points along the model's local CFrame.
local function holder(c, localCFrame, size)
	local part = Instance.new("Part")
	part.Name = "FX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = c.frame * localCFrame
	part.Parent = c.model
	return part
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

local function light(parent, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Runs fn once, the first frame t reaches `at`.
local function once(c, key, t, at, fn)
	if t >= at and not c.done[key] then
		c.done[key] = true
		fn()
	end
end

-- ---------------------------------------------------------------- live lightning

local function randomPerpendicular(rng, direction)
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	v -= direction * v:Dot(direction)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function jaggedPath(rng, a, b, depth, roughness)
	local points = { a, b }
	for _ = 1, depth do
		local refined = { points[1] }
		for i = 1, #points - 1 do
			local p, q = points[i], points[i + 1]
			local d = q - p
			local mid = (p + q) / 2 + randomPerpendicular(rng, d.Unit) * d.Magnitude * roughness * rng:NextNumber(-1, 1)
			table.insert(refined, mid)
			table.insert(refined, q)
		end
		points = refined
	end
	return points
end

local function segment(parent, a, b, width, color, transparency)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = Vector3.new(width, width, (b - a).Magnitude + width * 0.5)
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Parent = parent
	return part
end

-- A forked lightning bolt between two world points, built from thin neon parts. Returns a Folder.
local function lightningBolt(rng, parent, from, to, width, coreColor, glowColor)
	local folder = Instance.new("Folder")
	folder.Name = "Bolt"
	local main = jaggedPath(rng, from, to, 5, 0.2)
	for i = 1, #main - 1 do
		segment(folder, main[i], main[i + 1], width, coreColor, 0)
		segment(folder, main[i], main[i + 1], width * 3.5, glowColor, 0.75)
	end
	local length = (to - from).Magnitude
	for _ = 1, 4 do
		local start = main[rng:NextInteger(6, #main - 8)]
		local direction = ((to - from).Unit + randomPerpendicular(rng, (to - from).Unit) * rng:NextNumber(0.6, 1.2)).Unit
		local branch = jaggedPath(rng, start, start + direction * length * rng:NextNumber(0.12, 0.28), 3, 0.25)
		for i = 1, #branch - 1 do
			segment(folder, branch[i], branch[i + 1], width * 0.45 * (1 - i / #branch) + 0.04, coreColor, 0.1)
		end
	end
	folder.Parent = parent
	return folder
end

local function setBoltTransparency(folder, extra)
	for _, part in folder:GetChildren() do
		local base = part:GetAttribute("Base")
		if base == nil then
			base = part.Transparency
			part:SetAttribute("Base", base)
		end
		part.Transparency = base + (1 - base) * extra
	end
end

-- ---------------------------------------------------------------- animations
--
-- Model space: X = the user's right, Y = up, -Z = forward, origin = the user's feet.
-- c.v(x, y, z) builds a model-space point already scaled to the ultimate's size.
-- Each part() returns how to show one part at time t:
--   scale (number or Vector3, model axes), pivot (scale about this point), rot (CFrame rotation),
--   rotPivot, offset (Vector3), alpha (0 = invisible, 1 = its normal transparency).
-- setup(c) runs once (create particles/lights here); frame(t, c) runs every frame before the parts.

local Animations = {}

Animations.Rift = {
	duration = 6.5,
	setup = function(c)
		local S = c.size
		local C = c.v(0, 6.5, -10)
		local box = holder(c, CFrame.new(C), Vector3.new(6, 12, 2) * S)
		local tint = c.color or rgb(120, 230, 255)
		c.sparks = emitter(box, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(225, 250, 255) }, { 1, tint } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.35 }, { 1, 0 } }, S),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(1 * S, 4 * S),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 1,
			Rate = 40,
		})
		c.wisps = emitter(box, {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(20, 45, 55) }, { 1, rgb(5, 12, 18) } }),
			Size = numbers({ { 0, 2 }, { 1, 5 } }, S),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.7 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(0.5 * S, 1.5 * S),
			SpreadAngle = Vector2.new(180, 180),
			RotSpeed = NumberRange.new(-20, 20),
			Rate = 6,
		})
		c.light = light(box, tint, 28 * S)
	end,
	frame = function(t, c)
		c.sparks.Enabled = t > 0.3 and t < 4.8
		c.wisps.Enabled = t > 0.4 and t < 4.8
		once(c, "rip", t, 0.2, function()
			c.sparks:Emit(60)
		end)
		once(c, "close", t, 5.0, function()
			c.sparks:Emit(80)
		end)
		local open = phase(t, 0.15, 0.6) * (1 - phase(t, 4.7, 5.2))
		local flash = math.max(1 - math.abs(t - 0.25) / 0.2, 1 - math.abs(t - 5.05) / 0.25, 0)
		c.light.Brightness = 3.5 * open + 9 * flash
	end,
	part = function(r, t, c)
		local C = c.v(0, 6.5, -10)
		local close = inQuad(phase(t, 4.7, 5.2))
		-- the tear starts as a slit and rips wide open
		local width = math.max(outQuart(phase(t, 0.15, 0.6)) * (1 - close), 0.02)
		local height = 0.35 + 0.65 * outQuart(phase(t, 0, 0.3))
		local opening = Vector3.new(width, height, 1)
		local p = r.prefix
		if p == "Abyss" then
			return { scale = opening, pivot = C, alpha = phase(t, 0.1, 0.2) }
		elseif p == "Edge" then
			return { scale = opening, pivot = C, alpha = phase(t, 0, 0.1) * (0.85 + 0.15 * math.sin(t * 40)) }
		elseif p == "Glow" then
			return { scale = opening, pivot = C, alpha = phase(t, 0.1, 0.4) * (0.6 + 0.4 * math.sin(t * 3)) }
		elseif p == "Depth" then
			return {
				scale = opening,
				pivot = C,
				rot = CFrame.Angles(0, 0, t * 0.8),
				rotPivot = C,
				alpha = phase(t, 0.5, 1.0) * (1 - close),
			}
		elseif p == "Cracks" then
			-- reality cracks first, a moment before the tear opens
			return { scale = math.max(outQuart(phase(t, 0, 0.35)), 0.01), pivot = C, alpha = 1 - phase(t, 4.5, 5.0) }
		else -- Shards drift slowly outwards and round
			return {
				scale = 0.85 + 0.25 * phase(t, 0.3, 5),
				pivot = C,
				rot = CFrame.Angles(0, 0, t * 0.25),
				rotPivot = C,
				alpha = phase(t, 0.3, 0.7) * (1 - close),
			}
		end
	end,
}

Animations.Electric = {
	duration = 7.5,
	setup = function(c)
		local S = c.size
		local CC = c.v(0, 26, -14)
		local tint = c.color or rgb(165, 120, 255)
		c.boltCore = rgb(250, 242, 255)
		c.boltGlow = tint
		local cloud = holder(c, CFrame.new(CC), Vector3.new(30, 4, 24) * S)
		c.smoke = emitter(cloud, {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(50, 50, 60) }, { 1, rgb(35, 35, 44) } }),
			Size = numbers({ { 0, 8 }, { 1, 14 } }, S),
			Transparency = numbers({ { 0, 1 }, { 0.2, 0.55 }, { 1, 1 } }),
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.2 * S, 1 * S),
			SpreadAngle = Vector2.new(180, 180),
			RotSpeed = NumberRange.new(-15, 15),
			Rate = 10,
		})
		c.cloudLight = light(cloud, tint, 45 * S)

		c.impact = holder(c, CFrame.new(c.v(0, 0.5, -14)))
		c.sparks = emitter(c.impact, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(245, 235, 255) }, { 1, tint } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.5 }, { 1, 0 } }, S),
			Lifetime = NumberRange.new(0.3, 0.7),
			Speed = NumberRange.new(15 * S, 35 * S),
			SpreadAngle = Vector2.new(80, 80),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -40 * S, 0),
		})
		c.dust = emitter(c.impact, {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(95, 90, 100) }, { 1, rgb(60, 58, 66) } }),
			Size = numbers({ { 0, 2 }, { 1, 6 } }, S),
			Transparency = numbers({ { 0, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.5),
			Speed = NumberRange.new(4 * S, 8 * S),
			SpreadAngle = Vector2.new(85, 85),
			EmissionDirection = Enum.NormalId.Top,
		})
		c.impactLight = light(c.impact, tint, 35 * S)

		-- strikes come in an irregular rhythm, sometimes two at once
		c.strikes = {}
		local time = 1.4
		while time < 6.4 do
			table.insert(c.strikes, { time = time })
			if c.random:NextNumber() < 0.25 then
				table.insert(c.strikes, { time = time + 0.05 })
			end
			time += c.random:NextNumber(0.25, 0.75)
		end
	end,
	frame = function(t, c)
		local S = c.size
		c.smoke.Enabled = t > 0.3 and t < 6.3
		c.flash = 0
		local impactFlash = 0
		for _, strike in c.strikes do
			local since = t - strike.time
			if since >= 0 and not strike.bolt and not strike.over then
				local from = c.frame:PointToWorldSpace(c.v(c.random:NextNumber(-12, 12), 23.5, -14 + c.random:NextNumber(-9, 9)))
				local angle = c.random:NextNumber(0, math.pi * 2)
				local reach = c.random:NextNumber(2, 13)
				local to = c.frame:PointToWorldSpace(c.v(math.cos(angle) * reach, 0, -14 + math.sin(angle) * reach))
				strike.bolt = lightningBolt(c.random, c.model, from, to, 0.35 * S, c.boltCore, c.boltGlow)
				c.impact.CFrame = CFrame.new(to + Vector3.new(0, 0.3 * S, 0)) * c.frame.Rotation
				c.sparks:Emit(40)
				c.dust:Emit(12)
			end
			if strike.bolt then
				if since > 0.22 then
					strike.bolt:Destroy()
					strike.bolt = nil
					strike.over = true
				else
					-- a double flicker, then a quick fade
					local hidden = (since > 0.06 and since < 0.1) and 0.85 or phase(since, 0.12, 0.22)
					setBoltTransparency(strike.bolt, hidden)
					c.flash = 1
					impactFlash = math.max(impactFlash, 1 - phase(since, 0, 0.25))
				end
			end
		end
		c.cloudLight.Brightness = 1 + 6 * c.flash
		c.impactLight.Brightness = 10 * impactFlash
	end,
	part = function(r, t, c)
		local CC = c.v(0, 26, -14)
		local appear = outQuad(phase(t, 0, 1.4))
		local fade = phase(t, 6.5, 7.5)
		local p = r.prefix
		if p == "Rain" then
			local period = 4 * c.size
			return { offset = Vector3.new(0, -((t * 55 * c.size) % period), 0), alpha = phase(t, 1.2, 1.8) * (1 - phase(t, 6.3, 7)) }
		end
		local alpha = appear * (1 - fade)
		if p == "CloudGlow" then
			alpha *= 0.15 + 0.85 * c.flash
		end
		return {
			scale = 0.3 + 0.7 * appear,
			pivot = CC,
			rot = CFrame.Angles(0, t * 0.05, 0),
			rotPivot = CC,
			alpha = alpha,
		}
	end,
}

Animations.Fire = {
	duration = 6.2,
	setup = function(c)
		local S = c.size
		local tint = c.color
		c.flames, c.embers = {}, {}
		for _, x in { -0.9, 0.9 } do
			local hand = holder(c, CFrame.new(c.v(x, 3.2, -1.5)))
			table.insert(c.flames, emitter(hand, {
				Texture = TEXTURE.Fire,
				EmissionDirection = Enum.NormalId.Front,
				Color = tint and colors({ { 0, rgb(255, 250, 230) }, { 0.3, tint }, { 1, tint:Lerp(Color3.new(), 0.7) } })
					or colors({ { 0, rgb(255, 250, 220) }, { 0.25, rgb(255, 190, 80) }, { 0.6, rgb(240, 90, 30) }, { 1, rgb(90, 30, 20) } }),
				LightEmission = 1,
				Size = numbers({ { 0, 0.8 }, { 0.5, 3.5 }, { 1, 6 } }, S),
				Transparency = numbers({ { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.4, 0.6),
				Speed = NumberRange.new(40 * S, 55 * S),
				SpreadAngle = Vector2.new(9, 9),
				RotSpeed = NumberRange.new(-90, 90),
				Drag = 1.5,
				Acceleration = Vector3.new(0, 6 * S, 0),
				Rate = 160,
			}))
			table.insert(c.embers, emitter(hand, {
				Texture = TEXTURE.Spark,
				EmissionDirection = Enum.NormalId.Front,
				Color = colors({ { 0, rgb(255, 210, 110) }, { 1, tint or rgb(255, 90, 30) } }),
				LightEmission = 1,
				Size = numbers({ { 0, 0.3 }, { 1, 0 } }, S),
				Lifetime = NumberRange.new(0.6, 1.1),
				Speed = NumberRange.new(25 * S, 50 * S),
				SpreadAngle = Vector2.new(22, 22),
				Acceleration = Vector3.new(0, 10 * S, 0),
				Rate = 50,
			}))
		end
		local smokeBox = holder(c, CFrame.new(c.v(0, 4.5, -17)), Vector3.new(8, 6, 10) * S)
		c.smoke = emitter(smokeBox, {
			Texture = TEXTURE.Smoke,
			EmissionDirection = Enum.NormalId.Top,
			Color = colors({ { 0, rgb(70, 60, 55) }, { 1, rgb(40, 38, 38) } }),
			Size = numbers({ { 0, 4 }, { 1, 11 } }, S),
			Transparency = numbers({ { 0, 1 }, { 0.15, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.6, 2.6),
			Speed = NumberRange.new(2 * S, 5 * S),
			RotSpeed = NumberRange.new(-20, 20),
			Rate = 22,
		})
		c.light = light(holder(c, CFrame.new(c.v(0, 3.5, -8))), tint or rgb(255, 150, 60), 30 * S)
	end,
	frame = function(t, c)
		local on = t > 0.02 and t < 3.6
		for _, e in c.flames do
			e.Enabled = on
		end
		for _, e in c.embers do
			e.Enabled = on
		end
		c.smoke.Enabled = t > 0.3 and t < 4.0
		local level = outQuad(phase(t, 0, 0.3)) * (1 - phase(t, 3.6, 4.3))
		c.light.Brightness = level * (3.5 + 0.8 * math.sin(t * 23) + 0.5 * math.sin(t * 37))
	end,
	part = function(r, t, c)
		local axis = c.v(0, 3.2, -1.5) -- the hands; the flames pour forwards (-Z) from here
		local grow = outQuad(phase(t, 0, 0.3))
		local fade = phase(t, 3.6, 4.3)
		local width = 1 - 0.4 * fade
		local stretch = Vector3.new(width, width, math.max(grow, 0.02))
		local p = r.prefix
		if p == "Core" then
			stretch *= Vector3.new(1 + 0.08 * math.sin(t * 31), 1 + 0.08 * math.sin(t * 27), 1)
			return { scale = stretch, pivot = axis, alpha = 1 - fade }
		elseif p == "Shell" then
			return {
				scale = stretch * (1 + 0.05 * math.sin(t * 23)),
				pivot = axis,
				rot = CFrame.Angles(0, 0, t * 2.5),
				rotPivot = axis,
				alpha = (1 - fade) * (0.75 + 0.25 * math.sin(t * 17)),
			}
		else -- OuterShell
			return {
				scale = stretch,
				pivot = axis,
				rot = CFrame.Angles(0, 0, -t * 1.8),
				rotPivot = axis,
				alpha = (1 - fade) * (0.6 + 0.4 * math.sin(t * 11 + 1)),
			}
		end
	end,
}

-- when a wall slab / spike starts rising, given how far it is from the stomp
local function iceDelay(r, c)
	return 0.08 + r.distance / (38 * c.size)
end

local function iceShatter(r, c)
	return 5.0 + r.distance / (80 * c.size)
end

Animations.Ice = {
	duration = 7.4,
	setup = function(c)
		local S = c.size
		local feet = holder(c, CFrame.new(c.v(0, 0.3, 0)))
		local chips = {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(235, 248, 255) }, { 1, rgb(150, 200, 230) } }),
			LightEmission = 0.6,
			Size = numbers({ { 0, 0.45 }, { 1, 0.1 } }, S),
			Lifetime = NumberRange.new(0.5, 1.0),
			Speed = NumberRange.new(18 * S, 32 * S),
			SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -45 * S, 0),
			RotSpeed = NumberRange.new(-200, 200),
		}
		local mist = {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(225, 238, 248) }, { 1, rgb(190, 215, 235) } }),
			Size = numbers({ { 0, 2 }, { 1, 7 } }, S),
			Transparency = numbers({ { 0, 0.45 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(4 * S, 10 * S),
			SpreadAngle = Vector2.new(80, 80),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(-25, 25),
			Drag = 2,
		}
		c.stompChips = emitter(feet, chips)
		c.stompMist = emitter(feet, mist)
		-- a puff of mist and a spray of ice chips where every wall section breaks the ground
		c.sections = {}
		for _, r in c.rests do
			if r.prefix == "Wall" then
				local base = holder(c, CFrame.new(Vector3.new(r.pos.X, 0.5 * S, r.pos.Z)))
				table.insert(c.sections, {
					rest = r,
					chips = emitter(base, chips),
					mist = emitter(base, mist),
				})
			end
		end
		c.light = light(holder(c, CFrame.new(c.v(0, 6, -14))), c.color or rgb(170, 215, 255), 35 * S)
	end,
	frame = function(t, c)
		once(c, "stomp", t, 0.02, function()
			c.stompChips:Emit(70)
			c.stompMist:Emit(25)
		end)
		for i, section in c.sections do
			once(c, "rise" .. i, t, iceDelay(section.rest, c), function()
				section.chips:Emit(25)
				section.mist:Emit(14)
			end)
			once(c, "shatter" .. i, t, iceShatter(section.rest, c), function()
				section.chips:Emit(40)
				section.mist:Emit(10)
			end)
		end
		c.light.Brightness = 2.5 * phase(t, 0.4, 0.9) * (1 - phase(t, 5, 6))
	end,
	part = function(r, t, c)
		local p = r.prefix
		if p == "Frost" then
			return { scale = flat(outQuad(phase(t, 0, 0.9))), pivot = Vector3.zero, alpha = 1 - phase(t, 5.6, 6.4) }
		elseif p == "Cracks" then
			return { scale = flat(outQuart(phase(t, 0, 0.45))), pivot = Vector3.zero, alpha = 1 - phase(t, 5.4, 6.2) }
		end
		-- Spike_NN / Wall_NN / WallCore_NN: punch up out of the ground in a wave travelling away
		-- from the stomp, rumble, then shatter in the same order
		local delay = iceDelay(r, c)
		local rise = phase(t, delay, delay + 0.22)
		if rise <= 0 then
			return { alpha = 0 }
		end
		local e = outQuart(rise)
		local shatter = phase(t, iceShatter(r, c), iceShatter(r, c) + 0.35)
		local rumble = math.sin(t * 70) * 0.06 * c.size * math.max(0, 1 - (t - delay) / 0.5)
		return {
			scale = Vector3.new(0.75 + 0.25 * e, math.max(e * (1 - 0.15 * shatter), 0.01), 0.75 + 0.25 * e),
			pivot = Vector3.new(r.pos.X, 0, r.pos.Z),
			offset = Vector3.new(rumble, -shatter * c.size, 0),
			alpha = 1 - shatter,
		}
	end,
}

Animations.Wind = {
	duration = 2,
	setup = function(c)
		local S = c.size
		local K = c.v(0, 4.3, -1.6)
		local hands = holder(c, CFrame.new(K))
		c.gust = emitter(hands, {
			Texture = TEXTURE.Spark,
			EmissionDirection = Enum.NormalId.Front,
			Color = colors({ { 0, rgb(245, 250, 250) }, { 1, c.color or rgb(210, 235, 232) } }),
			LightEmission = 0.5,
			Size = numbers({ { 0, 0.25 }, { 1, 0 } }, S),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(50 * S, 80 * S),
			SpreadAngle = Vector2.new(45, 30),
			Drag = 2,
		})
		c.puff = emitter(hands, {
			Texture = TEXTURE.Smoke,
			EmissionDirection = Enum.NormalId.Front,
			Color = colors({ { 0, rgb(235, 240, 240) }, { 1, rgb(215, 222, 222) } }),
			Size = numbers({ { 0, 1 }, { 1, 7 } }, S),
			Transparency = numbers({ { 0, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 1.0),
			Speed = NumberRange.new(30 * S, 45 * S),
			SpreadAngle = Vector2.new(35, 25),
			Drag = 5,
			RotSpeed = NumberRange.new(-60, 60),
		})
		-- dust thrown out in every direction along the ground
		c.dust = {}
		for i = 1, 12 do
			local a = math.pi * 2 * i / 12
			local pos = c.v(math.cos(a) * 1.5, 0.4, math.sin(a) * 1.5)
			local base = holder(c, CFrame.lookAt(pos, pos + Vector3.new(math.cos(a), 0, math.sin(a))))
			table.insert(c.dust, emitter(base, {
				Texture = TEXTURE.Smoke,
				EmissionDirection = Enum.NormalId.Front,
				Color = colors({ { 0, rgb(180, 170, 155) }, { 1, rgb(150, 142, 130) } }),
				Size = numbers({ { 0, 1.5 }, { 1, 5 } }, S),
				Transparency = numbers({ { 0, 0.45 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.8, 1.4),
				Speed = NumberRange.new(18 * S, 28 * S),
				SpreadAngle = Vector2.new(20, 12),
				Drag = 4,
				RotSpeed = NumberRange.new(-40, 40),
			}))
		end
		c.light = light(hands, rgb(235, 245, 245), 22 * S)
	end,
	frame = function(t, c)
		once(c, "clap", t, 0.01, function()
			c.gust:Emit(60)
			c.puff:Emit(18)
		end)
		once(c, "dust", t, 0.03, function()
			for _, e in c.dust do
				e:Emit(6)
			end
		end)
		c.light.Brightness = 8 * (1 - phase(t, 0, 0.25))
	end,
	part = function(r, t, c)
		local K = c.v(0, 4.3, -1.6) -- where the user's hands meet
		local p = r.prefix
		if p == "Flash" then
			return { scale = 0.3 + 1.2 * outQuad(phase(t, 0, 0.12)), pivot = K, alpha = 1 - phase(t, 0.06, 0.22) }
		elseif p == "Rings" then
			local e = outQuart(phase(t, 0.02, 0.5))
			return { scale = 0.15 + 1.6 * e, pivot = K, offset = Vector3.new(0, 0, -6 * c.size * e), alpha = 1 - phase(t, 0.2, 0.65) }
		elseif p == "GroundRing" then
			local e = outQuart(phase(t, 0.05, 0.6))
			return { scale = flat(0.3 + 3.5 * e), pivot = c.v(0, 0, -0.5), alpha = 1 - phase(t, 0.25, 0.75) }
		elseif p == "Streaks" then
			local s = math.max(outQuart(phase(t, 0, 0.25)), 0.01) * (1 + 0.6 * phase(t, 0.25, 0.8))
			return { scale = s, pivot = K, alpha = 1 - phase(t, 0.3, 0.8) }
		else -- Debris kicked outwards along the ground
			local e = outQuad(phase(t, 0.03, 0.7))
			return {
				scale = flat(1 + 3.5 * e),
				pivot = Vector3.zero,
				offset = Vector3.new(0, math.sin(math.pi * e) * 0.8 * c.size, 0),
				alpha = 1 - phase(t, 0.4, 0.8),
			}
		end
	end,
}

-- ground parts burst up in a wave travelling away from the user, then sink in the same order
local function heave(r, t, c, delay, riseTime, sinkStart)
	local rise = phase(t, delay, delay + riseTime)
	if rise <= 0 then
		return { alpha = 0 }
	end
	local e = outQuart(rise)
	local sink = inQuad(phase(t, sinkStart, sinkStart + 0.7))
	local rumble = math.sin(t * 65 + r.distance) * 0.07 * c.size * math.max(0, 1 - (t - delay) / 0.5)
	return {
		scale = Vector3.new(0.8 + 0.2 * e, math.max(e, 0.01), 0.8 + 0.2 * e),
		pivot = Vector3.new(r.pos.X, 0, r.pos.Z),
		offset = Vector3.new(rumble, -sink * r.height, 0),
		alpha = 1 - sink,
	}
end

local function earthDelay(r, c)
	if r.prefix == "Spire" then
		return 0.25 + r.distance / (42 * c.size)
	end
	return 0.1 + r.distance / (48 * c.size)
end

Animations.Earth = {
	duration = 6.8,
	setup = function(c)
		local S = c.size
		local tint = c.color or rgb(255, 160, 60)
		local dust = {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(140, 120, 95) }, { 1, rgb(105, 92, 78) } }),
			Size = numbers({ { 0, 2 }, { 1, 7 } }, S),
			Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.0, 2.0),
			Speed = NumberRange.new(4 * S, 10 * S),
			SpreadAngle = Vector2.new(75, 75),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(-30, 30),
			Drag = 2,
		}
		local chips = {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(150, 130, 105) }, { 1, rgb(90, 78, 66) } }),
			LightEmission = 0,
			Size = numbers({ { 0, 0.45 }, { 1, 0.2 } }, S),
			Lifetime = NumberRange.new(0.5, 1.0),
			Speed = NumberRange.new(14 * S, 26 * S),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -50 * S, 0),
			RotSpeed = NumberRange.new(-200, 200),
		}
		local feet = holder(c, CFrame.new(c.v(0, 0.3, 0)))
		c.stompDust = emitter(feet, dust)
		c.stompChips = emitter(feet, chips)
		-- a dust burst and flying chips wherever a slab or spire breaks the ground
		c.risers = {}
		c.boulders = {}
		for _, r in c.rests do
			if r.prefix == "Slab" or r.prefix == "Spire" then
				local base = holder(c, CFrame.new(Vector3.new(r.pos.X, 0.4 * S, r.pos.Z)))
				table.insert(c.risers, { rest = r, dust = emitter(base, dust), chips = emitter(base, chips) })
			elseif r.prefix == "Boulder" then
				local base = holder(c, CFrame.new(Vector3.new(r.pos.X, 0.4 * S, r.pos.Z)))
				table.insert(c.boulders, { dust = emitter(base, dust), chips = emitter(base, chips) })
			end
		end
		local fissure = holder(c, CFrame.new(c.v(0, 0.3, -15)), Vector3.new(2, 0.5, 28) * S)
		c.embers = emitter(fissure, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(255, 230, 160) }, { 1, tint } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.3 }, { 1, 0 } }, S),
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(3 * S, 8 * S),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 35,
		})
		c.lights = {
			light(holder(c, CFrame.new(c.v(0, 1.5, -8))), tint, 22 * S),
			light(holder(c, CFrame.new(c.v(0, 1.5, -22))), tint, 22 * S),
		}
	end,
	frame = function(t, c)
		once(c, "stomp", t, 0.02, function()
			c.stompDust:Emit(25)
			c.stompChips:Emit(40)
		end)
		for i, riser in c.risers do
			once(c, "rise" .. i, t, earthDelay(riser.rest, c), function()
				riser.dust:Emit(10)
				riser.chips:Emit(16)
			end)
		end
		once(c, "slam", t, 4.85, function()
			for _, b in c.boulders do
				b.dust:Emit(14)
				b.chips:Emit(20)
			end
		end)
		c.embers.Enabled = t > 0.5 and t < 5.8
		local glow = outQuart(phase(t, 0, 0.55)) * (1 - phase(t, 5.8, 6.6)) * (0.85 + 0.15 * math.sin(t * 6))
		for _, l in c.lights do
			l.Brightness = 3 * glow
		end
	end,
	part = function(r, t, c)
		local p = r.prefix
		if p == "Fissure" or p == "Rubble" then
			-- rips forwards from the user's feet
			local e = outQuart(phase(t, 0, 0.55))
			local alpha = 1 - phase(t, 5.9, 6.6)
			if p == "Fissure" then
				alpha *= 0.8 + 0.2 * math.sin(t * 6)
			end
			return { scale = Vector3.new(1, 1, math.max(e, 0.01)), pivot = Vector3.zero, alpha = alpha }
		elseif p == "Slab" then
			return heave(r, t, c, earthDelay(r, c), 0.25, 5.2 + r.distance / (90 * c.size))
		elseif p == "Spire" then
			return heave(r, t, c, earthDelay(r, c), 0.2, 5.3 + r.distance / (90 * c.size))
		else -- Boulder_NN: torn loose, held floating and turning, then slammed down
			local index = r.index or 1
			local start = 0.3 + index * 0.08
			local lift = outQuad(phase(t, start, start + 1.0))
			local slam = inQuad(phase(t, 4.6, 4.85))
			local hover = (lift - 1) * 3 * c.size + 0.3 * c.size * math.sin(t * 2 + index) * (1 - slam)
			return {
				rot = CFrame.Angles(t * 0.5 * (1 - slam), t * 0.7 * (1 - slam), 0),
				rotPivot = r.pos,
				offset = Vector3.new(0, hover - slam * (r.pos.Y - 0.6 * c.size), 0),
				alpha = phase(t, start, start + 0.2) * (1 - phase(t, 5.3, 5.9)),
			}
		end
	end,
}

local function waveState(t, c)
	local S = c.size
	local rise = outQuad(phase(t, 0, 1.1))
	local travel = 20 * S * (1 - math.cos(math.pi * phase(t, 1.0, 4.2))) / 2
	local crash = inQuad(phase(t, 4.2, 5.0))
	return rise, travel, crash
end

Animations.Water = {
	duration = 6.5,
	setup = function(c)
		local S = c.size
		local tint = c.color or rgb(120, 190, 240)
		c.crest = holder(c, CFrame.new(c.v(0, 11, -6)), Vector3.new(26, 2, 3) * S)
		local mist = {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(235, 245, 252) }, { 1, rgb(205, 225, 240) } }),
			Size = numbers({ { 0, 2 }, { 1, 6 } }, S),
			Transparency = numbers({ { 0, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(2 * S, 6 * S),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(-30, 30),
		}
		local droplets = {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(240, 250, 255) }, { 1, tint } }),
			LightEmission = 0.3,
			Size = numbers({ { 0, 0.35 }, { 1, 0.1 } }, S),
			Lifetime = NumberRange.new(0.6, 1.2),
			Speed = NumberRange.new(8 * S, 18 * S),
			SpreadAngle = Vector2.new(50, 50),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -40 * S, 0),
		}
		c.crestMist = emitter(c.crest, mist)
		c.crestMist.Rate = 25
		c.crestDrops = emitter(c.crest, droplets)
		c.crestDrops.Rate = 70
		c.base = holder(c, CFrame.new(c.v(0, 0.5, -5)), Vector3.new(26, 1, 4) * S)
		c.baseMist = emitter(c.base, mist)
		c.baseDrops = emitter(c.base, droplets)
		c.light = light(c.crest, tint, 35 * S)
	end,
	frame = function(t, c)
		local S = c.size
		local rise, travel, crash = waveState(t, c)
		local height = 11 * S * math.max(rise, 0.05) * (1 - 0.85 * crash)
		c.crest.CFrame = c.frame * CFrame.new(0, height, -6 * S - travel - 4 * S * crash)
		c.base.CFrame = c.frame * CFrame.new(0, 0.5 * S, -5 * S - travel - 4 * S * crash)
		c.crestMist.Enabled = t > 0.8 and t < 4.5
		c.crestDrops.Enabled = t > 0.8 and t < 4.5
		once(c, "surge", t, 0.05, function()
			c.baseMist:Emit(30)
		end)
		once(c, "crash", t, 4.55, function()
			c.baseMist:Emit(60)
			c.baseDrops:Emit(220)
		end)
		c.light.Brightness = 1.5 * rise * (1 - phase(t, 4.6, 5.6))
	end,
	part = function(r, t, c)
		local S = c.size
		local rise, travel, crash = waveState(t, c)
		local p = r.prefix
		if p == "Foam" then
			return {
				scale = flat(outQuad(phase(t, 0, 1.0)) * (1 + 1.5 * crash)),
				pivot = c.v(0, 0, -4.5),
				offset = Vector3.new(0, 0, -travel - 4 * S * crash),
				alpha = 1 - phase(t, 5.2, 6.4),
			}
		end
		-- the wave surges up out of the ground, rolls forwards, then crashes down and spreads
		local alpha = 1 - phase(t, 4.6, 5.4)
		if p == "Spray" then
			alpha *= phase(t, 0.7, 1.1) * (0.75 + 0.25 * math.sin(t * 9))
		end
		return {
			scale = Vector3.new(1, math.max(rise * (1 - 0.85 * crash), 0.01), (0.6 + 0.4 * rise) * (1 + 0.6 * crash)),
			pivot = c.v(0, 0, -5),
			offset = Vector3.new(0, 0, -travel - 4 * S * crash),
			alpha = alpha,
		}
	end,
}

-- Kamehameha: charge at the hip, thrust forwards, fire
local KAME_MUZZLE = Vector3.new(0, 3.6, -1.4) -- where the beam leaves the hands (model space, size 1)
local KAME_HIP = Vector3.new(1.3, 2.6, 0.2) -- where the ball is gathered while charging
local KAME_LENGTH = 60

local function kamehameha(t)
	local move = outQuart(phase(t, 2.0, 2.2)) -- ball thrust from the hip to the front
	local fire = outQuart(phase(t, 2.2, 2.5)) -- beam racing out to full length
	local thin = inQuad(phase(t, 4.6, 5.2)) -- beam collapsing to nothing
	return move, fire, thin
end

Animations.Energy = {
	duration = 6.2,
	setup = function(c)
		local S = c.size
		local tint = c.color or rgb(90, 200, 255)
		c.ball = holder(c, CFrame.new(KAME_HIP * S), Vector3.new(6, 6, 6) * S)
		c.gather = emitter(c.ball, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, tint }, { 1, rgb(255, 255, 255) } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.3 }, { 1, 0.05 } }, S),
			Lifetime = NumberRange.new(0.3, 0.5),
			Speed = NumberRange.new(6 * S, 10 * S),
			Rate = 90,
		})
		-- energy streams *into* the ball from all around (falls back to bursting outwards on old clients)
		pcall(function()
			c.gather.Shape = Enum.ParticleEmitterShape.Sphere
			c.gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
			c.gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		end)
		c.release = emitter(c.ball, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(255, 255, 255) }, { 1, tint } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.6 }, { 1, 0 } }, S),
			Lifetime = NumberRange.new(0.3, 0.7),
			Speed = NumberRange.new(30 * S, 60 * S),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
		})
		c.ballLight = light(c.ball, tint, 25 * S)

		local feet = holder(c, CFrame.new(c.v(0, 0.3, 0)), Vector3.new(3, 0.4, 3) * S)
		c.auraSparks = emitter(feet, {
			Texture = TEXTURE.Spark,
			Color = colors({ { 0, rgb(255, 255, 255) }, { 1, tint } }),
			LightEmission = 1,
			Size = numbers({ { 0, 0.35 }, { 1, 0 } }, S),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(6 * S, 12 * S),
			SpreadAngle = Vector2.new(15, 15),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 55,
		})
		c.auraLight = light(holder(c, CFrame.new(c.v(0, 3, 0))), tint, 18 * S)

		local path = holder(c, CFrame.new(c.v(0, 0.5, -31)), Vector3.new(8, 1, 56) * S)
		c.trench = emitter(path, {
			Texture = TEXTURE.Smoke,
			Color = colors({ { 0, rgb(150, 140, 125) }, { 1, rgb(110, 104, 95) } }),
			Size = numbers({ { 0, 3 }, { 1, 9 } }, S),
			Transparency = numbers({ { 0, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(4 * S, 10 * S),
			SpreadAngle = Vector2.new(50, 50),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(-30, 30),
			Rate = 45,
		})
		c.beamLights = {}
		for _, z in { -15, -35, -55 } do
			table.insert(c.beamLights, light(holder(c, CFrame.new(c.v(0, 3.6, z))), tint, 30 * S))
		end
	end,
	frame = function(t, c)
		local S = c.size
		local move, fire, thin = kamehameha(t)
		c.ball.CFrame = c.frame * CFrame.new((KAME_HIP:Lerp(KAME_MUZZLE, move)) * S)
		c.gather.Enabled = t > 0.2 and t < 2.0
		c.auraSparks.Enabled = t > 0.1 and t < 4.8
		c.trench.Enabled = t > 2.3 and t < 4.7
		once(c, "release", t, 2.2, function()
			c.release:Emit(150)
		end)
		local charge = outQuad(phase(t, 0.2, 2.0))
		local flash = math.max(0, 1 - math.abs(t - 2.25) / 0.2)
		c.ballLight.Brightness = (2 + 3 * charge) * (1 - phase(t, 4.6, 5.0)) + 10 * flash
		c.auraLight.Brightness = 2 * outQuart(phase(t, 0, 0.4)) * (1 - phase(t, 4.8, 5.6))
		for _, l in c.beamLights do
			l.Brightness = 4 * fire * (1 - thin)
		end
	end,
	part = function(r, t, c)
		local S = c.size
		local M = KAME_MUZZLE * S
		local move, fire, thin = kamehameha(t)
		local p = r.prefix
		if p == "Aura" then
			-- a ki aura flaring up round the user, flickering like flame
			local e = outQuart(phase(t, 0, 0.4))
			local flicker = 1 + 0.05 * math.sin(t * 23) + 0.03 * math.sin(t * 41)
			return {
				scale = Vector3.new(math.max(e * flicker, 0.01), math.max(e * (1 + 0.08 * math.sin(t * 17)), 0.01), math.max(e * flicker, 0.01)),
				pivot = Vector3.zero,
				alpha = (0.7 + 0.3 * math.sin(t * 13)) * (1 - phase(t, 4.8, 5.6)),
			}
		elseif p == "Cracks" then
			return { scale = flat(outQuart(phase(t, 0.3, 1.2))), pivot = Vector3.zero, alpha = 1 - phase(t, 5.4, 6.2) }
		elseif p == "Rocks" then
			-- lifted by the gathering energy, blasted outwards on release, dropped at the end
			local lift = outQuad(phase(t, 0.3, 1.8))
			local blown = outQuad(phase(t, 2.2, 2.6))
			local fall = inQuad(phase(t, 4.8, 5.4))
			local shake = (1 - blown) * math.sin(t * 37) * 0.05 * S
			return {
				scale = flat(1 + 0.8 * blown),
				pivot = Vector3.zero,
				rot = CFrame.Angles(0, t * 0.35, 0),
				rotPivot = Vector3.zero,
				offset = Vector3.new(shake, (lift - 1) * 2 * S + 0.15 * S * math.sin(t * 3) - 3 * S * fall, 0),
				alpha = phase(t, 0.3, 0.5) * (1 - phase(t, 5.0, 5.6)),
			}
		elseif p == "Ball" or p == "BallGlow" then
			local grow = 0.15 + 0.85 * outQuad(phase(t, 0.2, 2.0))
			local s = grow * (1 + 0.08 * math.sin(t * 25)) * (1 - inQuad(phase(t, 4.6, 5.0)))
			return {
				scale = math.max(s, 0.01),
				pivot = M,
				offset = (KAME_HIP - KAME_MUZZLE) * S * (1 - move),
				alpha = phase(t, 0.2, 0.4),
			}
		end
		if t < 2.2 then
			return { alpha = 0 }
		end
		local width = (1 + 0.04 * math.sin(t * 31)) * (1 - thin)
		if p == "Head" then
			-- the head rides the front of the beam as it races out
			return {
				scale = math.max((0.5 + 0.5 * fire) * (1 + 0.06 * math.sin(t * 19)) * (1 - thin), 0.01),
				pivot = r.pos,
				offset = Vector3.new(0, 0, (1 - fire) * KAME_LENGTH * S),
				alpha = 1 - phase(t, 4.8, 5.2),
			}
		elseif p == "Rings" then
			local e = outQuart(phase(t, 2.2, 2.8))
			return { scale = 0.3 + 1.2 * e, pivot = M, offset = Vector3.new(0, 0, -4 * S * e), alpha = 1 - phase(t, 2.4, 3.0) }
		end
		-- Beam / BeamGlow / BeamAura / BeamCoils
		local state = {
			scale = Vector3.new(math.max(width, 0.01), math.max(width, 0.01), math.max(fire, 0.01)),
			pivot = M,
			alpha = 1 - phase(t, 4.9, 5.3),
		}
		if p == "BeamCoils" then
			state.rot = CFrame.Angles(0, 0, t * 9)
			state.rotPivot = M
		elseif p == "BeamAura" then
			state.alpha *= 0.75 + 0.25 * math.sin(t * 21)
		end
		return state
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
--   color    Color3 that repaints the element's glowing parts and its particles
--   colors   { PartName = Color3 } for full control over individual parts
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
		color = options.color,
		random = Random.new(),
		model = model,
		frame = frame,
		rests = rests,
		done = {},
		flash = 0,
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
