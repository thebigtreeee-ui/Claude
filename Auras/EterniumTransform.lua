-- EterniumTransform (ModuleScript next to EterniumAuras in ReplicatedStorage.Eternium): the 3.5-second
-- aura transformation, with a shared spine and a signature build-up and finish for every aura.
--
--   0.0 - 3.0  BUILD-UP  the ground cracks, rocks tear loose and float, the air shakes, a charge glow
--                        swells, streams of energy spiral in, and the aura's own build-up plays
--   3.0        BURST     blinding flash, two shockwaves across the ground, a pillar of light, the rocks
--                        blasted away, and the aura's own finish
--   3.0 - 3.5  SETTLE    landing in the powered-up stance; the debris keeps flying and fading after
--
-- The transforming player gets a short cinematic (camera shots, building shake, FOV punch, screen
-- flash, colour grade) and can't move during it. Everyone else sees the same effects without their
-- camera moving. Run it on every client:
--
--   server:  TransformEvent:FireAllClients(character, "FrostCrown", { Main = ..., Accent = ..., Glow = ... })
--   client:  TransformEvent.OnClientEvent:Connect(function(character, aura, colors)
--                EterniumTransform.play(character, aura, colors, { onBurst = function() ... end })
--            end)
--
-- Purely visual: set AuraStage = 2 (and anything gameplay) on the server at the 3-second mark.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local EterniumAuras = require(script.Parent:WaitForChild("EterniumAuras"))
local texture = EterniumAuras.texture

local Transform = {}

local BURST = 3.0
local SETTLE = 3.5
local LIFETIME = 6.0 -- the debris and lingering light finish fading by then
Transform.Duration = SETTLE

-- Optional animation IDs ("rbxassetid://...") played on the transforming character.
Transform.Animations = { Buildup = "", Burst = "", Stance = "" }
-- Optional sounds per aura: Transform.Sounds.FrostCrown = { Buildup = "rbxassetid://...", Burst = "..." }
Transform.Sounds = {}

-- ---------------------------------------------------------------- small helpers

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

local function phase(t, a, b)
	return clamp01((t - a) / (b - a))
end

local function easeInOut(x)
	return x * x * (3 - 2 * x)
end

local function easeOut(x)
	return 1 - (1 - x) ^ 3
end

local function numbers(points, scale)
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2] * (scale or 1)))
	end
	return NumberSequence.new(keys)
end

local function tone(color, k)
	if k >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), k)
	end
	return color:Lerp(Color3.new(0, 0, 0), -k)
end

local function gradient(color, a, b)
	return ColorSequence.new(tone(color, a), tone(color, b))
end

-- ---------------------------------------------------------------- the effect context

local Ctx = {}
Ctx.__index = Ctx

function Ctx:track(inst)
	table.insert(self.instances, inst)
	return inst
end

-- a world point from feet-space coordinates (x right, y up, -z forward)
function Ctx:at(x, y, z)
	return self.cf * Vector3.new(x, y, z)
end

function Ctx:part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = self.folder
	return self:track(p)
end

-- an invisible anchored part at a world position to hang emitters, beams and lights on
function Ctx:anchor(position, size)
	return self:part({ Transparency = 1, Size = size or Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(position) * self.cf.Rotation })
end

function Ctx:attachment(parent, position)
	local a = Instance.new("Attachment")
	a.Parent = parent
	if position then
		a.WorldPosition = position
	end
	return self:track(a)
end

function Ctx:emitter(parent, tex, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture(tex)
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.Enabled = false
	for key, value in props do
		if key == "Squash" then
			pcall(function()
				e.Squash = value
			end)
		else
			e[key] = value
		end
	end
	e.Parent = parent
	return self:track(e)
end

function Ctx:beam(a0, a1, tex, props)
	local b = Instance.new("Beam")
	b.Texture = texture(tex)
	b.Attachment0, b.Attachment1 = a0, a1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 10
	for key, value in props do
		b[key] = value
	end
	b.Parent = a0.Parent
	return self:track(b)
end

function Ctx:light(parent, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Parent = parent
	return self:track(l)
end

-- run fn(t, dt) every frame until it returns true
function Ctx:every(fn)
	table.insert(self.updaters, fn)
end

-- run fn once when the timeline reaches `time`
function Ctx:when(time, fn)
	table.insert(self.timers, { time = time, fn = fn })
end

-- a one-off particle burst at a world point
function Ctx:puff(position, tex, count, props)
	local holder = self:anchor(position)
	local e = self:emitter(holder, tex, props)
	e:Emit(count)
	return e
end

-- a flat ring racing out across the ground
function Ctx:shockwave(position, color, from, to, life, tex)
	self:puff(position + Vector3.new(0, 0.15, 0), tex or "TX_Ring", 1, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01, 0.01),
		Size = numbers({ { 0, from }, { 1, to } }),
		Transparency = numbers({ { 0, 0 }, { 0.6, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(life, life),
		Rotation = NumberRange.new(0, 360),
		Color = gradient(color, 0.5, 0),
		LightEmission = 1,
	})
end

-- a jagged lightning bolt made of neon parts that flickers and fades
local function perpendicular(rng, d)
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	v -= d * v:Dot(d)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

function Ctx:bolt(from, to, width, color, life, branches)
	local rng = self.rng
	local function path(a, b, depth, rough)
		local pts = { a, b }
		for _ = 1, depth do
			local nxt = { pts[1] }
			for i = 1, #pts - 1 do
				local p, q = pts[i], pts[i + 1]
				local d = q - p
				table.insert(nxt, (p + q) / 2 + perpendicular(rng, d.Unit) * d.Magnitude * rough * rng:NextNumber(-1, 1))
				table.insert(nxt, q)
			end
			pts = nxt
		end
		return pts
	end
	local segments = {}
	local function draw(pts, w, glow)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			if len > 0.01 then
				table.insert(segments, self:part({
					Material = Enum.Material.Neon,
					Color = glow and color or tone(color, 0.7),
					Transparency = glow and 0.8 or 0,
					Size = Vector3.new(w, w, len + w * 0.5),
					CFrame = CFrame.lookAt((a + b) / 2, b),
				}))
			end
		end
	end
	-- detail scales with length: a sky-high strike is finely jagged, a short crackle only needs a few kinks
	local length = (to - from).Magnitude
	local main = path(from, to, length > 24 and 4 or length > 8 and 3 or 2, 0.2)
	draw(main, width, false)
	if width >= 0.25 then
		draw(main, width * 2.2, true)
	end
	for _ = 1, branches or 2 do
		local s = main[rng:NextInteger(2, #main - 1)]
		local dir = ((to - from).Unit + perpendicular(rng, (to - from).Unit) * rng:NextNumber(0.6, 1.2)).Unit
		draw(path(s, s + dir * (to - from).Magnitude * rng:NextNumber(0.15, 0.3), 2, 0.3), width * 0.45, false)
	end
	local born = self.t
	self:every(function(t)
		local age = t - born
		local hidden = (age > 0.04 and age < 0.07) and 0.8 or phase(age, life * 0.5, life)
		for _, p in segments do
			if p.Parent then
				local base = p.Size.X > width * 1.6 and 0.8 or 0
				p.Transparency = base + (1 - base) * hidden
			end
		end
		if age >= life then
			for _, p in segments do
				p:Destroy()
			end
			return true
		end
		return false
	end)
end

-- ---------------------------------------------------------------- the shared spine

local function groundAt(character, root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -25, 0), params)
	if hit then
		return hit.Position, hit.Instance.Color, hit.Instance.Material
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local drop = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2
	return root.Position - Vector3.new(0, drop, 0), Color3.fromRGB(110, 105, 100), Enum.Material.Slate
end

local function cracks(ctx)
	local rng = ctx.rng
	local list = {}
	for k = 1, 11 do
		local angle = (k / 11) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local pos = Vector3.new(math.cos(angle) * 0.6, 0.04, math.sin(angle) * 0.6)
		local reach = rng:NextNumber(6, 10)
		local n = 7
		for i = 1, n do
			angle += rng:NextNumber(-0.45, 0.45)
			local step = reach / n
			local nxt = pos + Vector3.new(math.cos(angle) * step, 0, math.sin(angle) * step)
			local a, b = ctx.cf * pos, ctx.cf * nxt
			local p = ctx:part({
				Material = Enum.Material.Neon,
				Color = ctx.colors.Glow,
				Transparency = 1,
				Size = Vector3.new(0.16 * (1 - i / (n + 2)) + 0.04, 0.05, step + 0.1),
				CFrame = CFrame.lookAt((a + b) / 2, b),
			})
			-- cracks spread outwards across the build-up, faster towards the end
			table.insert(list, { part = p, appear = 0.15 + 2.6 * ((i - 1) / n) ^ 1.3 + rng:NextNumber(0, 0.25) })
			pos = nxt
		end
	end
	ctx:every(function(t)
		for _, c in list do
			local on = phase(t, c.appear, c.appear + 0.15)
			local flare = math.max(0, 1 - math.abs(t - BURST) / 0.25)
			local fade = phase(t, 3.6, 5.2)
			c.part.Transparency = 1 - on * (0.35 + 0.35 * flare + 0.15 * math.sin(t * 9 + c.appear * 7)) * (1 - fade)
		end
		return t > 5.3
	end)
end

local function rocks(ctx)
	local rng = ctx.rng
	local list = {}
	for i = 1, 16 do
		local angle = rng:NextNumber(0, math.pi * 2)
		if ctx.isLocal then
			-- keep a clear lane in front of the face for the cinematic's push-in (forward is -z, angle 3pi/2)
			angle = 3 * math.pi / 2 + 0.55 + rng:NextNumber(0, math.pi * 2 - 1.1)
		end
		local r = rng:NextNumber(2.5, 7.5)
		local size = rng:NextNumber(0.35, 1.3)
		local home = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local rock = ctx:part({
			Material = ctx.groundMaterial,
			Color = tone(ctx.groundColor, rng:NextNumber(-0.2, 0.05)),
			Size = Vector3.new(size, size * rng:NextNumber(0.55, 1), size * rng:NextNumber(0.7, 1.1)),
			Transparency = 1,
		})
		table.insert(list, {
			part = rock,
			home = home,
			tear = rng:NextNumber(0.25, 1.9),
			height = rng:NextNumber(1.2, 5.5),
			spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)),
			phase = rng:NextNumber(0, 6),
		})
	end
	ctx:every(function(t, dt)
		for _, r in list do
			if t < BURST then
				local lift = easeOut(phase(t, r.tear, r.tear + 1.1))
				if lift > 0 and not r.torn then
					r.torn = true
					ctx:puff(ctx.cf * r.home, "Glow", 6, {
						Color = ColorSequence.new(tone(ctx.groundColor, 0.1)),
						Size = numbers({ { 0, 0.8 }, { 1, 2.4 } }),
						Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }),
						Lifetime = NumberRange.new(0.6, 1),
						Speed = NumberRange.new(1, 3),
						SpreadAngle = Vector2.new(70, 70),
						EmissionDirection = Enum.NormalId.Top,
						LightEmission = 0,
					})
				end
				local shake = Vector3.new(math.noise(t * 9, r.phase), 0, math.noise(r.phase, t * 9)) * 0.08 * lift
				local bob = math.sin(t * 2 + r.phase) * 0.15 * lift
				local pos = r.home + Vector3.new(0, -0.4 + (r.height + 0.4) * lift + bob, 0) + shake
				local rot = CFrame.fromAxisAngle(r.spin.Unit, t * 0.8 * lift + r.phase)
				r.part.CFrame = ctx.cf * (CFrame.new(pos) * rot)
				r.part.Transparency = r.torn and 0 or 1
				r.last = pos
			else
				if not r.velocity then
					-- blasted away by the burst
					local out = Vector3.new(r.home.X, 0, r.home.Z).Unit
					r.velocity = out * ctx.rng:NextNumber(28, 48) + Vector3.new(0, ctx.rng:NextNumber(10, 22), 0)
					r.pos = r.last or r.home
				end
				r.velocity += Vector3.new(0, -70, 0) * dt
				r.pos += r.velocity * dt
				r.part.CFrame = ctx.cf * (CFrame.new(r.pos) * CFrame.fromAxisAngle(r.spin.Unit, t * 12 + r.phase))
				r.part.Transparency = phase(t, BURST + 0.9, BURST + 1.5)
			end
		end
		return t > BURST + 1.6
	end)
end

local function charge(ctx)
	local chest = ctx:anchor(ctx:at(0, 3.2, 0), Vector3.new(2, 4, 1))
	local glow = ctx:emitter(chest, "Glow", {
		Color = gradient(ctx.colors.Glow, 0.3, 0),
		Size = numbers({ { 0, 3 }, { 1, 4 } }),
		Transparency = numbers({ { 0, 1 }, { 0.3, 0.75 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.4, 0.6),
		Speed = NumberRange.new(0, 0),
		LightEmission = 1,
		Rate = 10,
	})
	glow.Enabled = true
	local light = ctx:light(chest, ctx.colors.Glow, 10)
	local dust = ctx:emitter(ctx:anchor(ctx:at(0, 0.2, 0), Vector3.new(9, 0.2, 9)), "Glow", {
		Color = ColorSequence.new(tone(ctx.groundColor, 0.15)),
		Size = numbers({ { 0, 0.6 }, { 1, 1.6 } }),
		Transparency = numbers({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(20, 20),
		LightEmission = 0,
		Rate = 0,
	})
	dust.Enabled = true
	ctx:every(function(t)
		local build = phase(t, 0, BURST)
		glow.Size = numbers({ { 0, 3 + 5 * build }, { 1, 4 + 6 * build } })
		glow.Enabled = t < BURST
		dust.Rate = t < BURST and (6 + 30 * build) or 0
		local flash = math.max(0, 1 - (t - BURST) / 0.6)
		light.Range = 10 + 30 * build + 30 * flash
		light.Brightness = (t < BURST and (0.5 + 4 * build * build) or 0) + 18 * (t >= BURST and flash or 0)
		return t > BURST + 0.7
	end)
end

-- streams of energy spiralling in towards the body
local function streams(ctx)
	local base = ctx:anchor(ctx:at(0, 0, 0))
	local list = {}
	for i = 1, 7 do
		local a0, a1 = ctx:attachment(base), ctx:attachment(base)
		local tr = Instance.new("Trail")
		tr.Texture = texture("TX_Pillar")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.35
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Color = gradient(ctx.colors.Main, 0.6, 0)
		tr.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
		tr.Parent = base
		ctx:track(tr)
		table.insert(list, { a0 = a0, a1 = a1, trail = tr, offset = i / 7, phase = i * 0.9, last = 0 })
	end
	ctx:every(function(t)
		local build = phase(t, 0, BURST)
		for _, s in list do
			local rate = 0.9 + 1.4 * build -- the streams come in faster as the power builds
			local cycle = (t * rate + s.offset) % 1
			if cycle < s.last then
				s.trail:Clear()
			end
			s.last = cycle
			local r = 9 * (1 - cycle) ^ 1.5 + 0.4
			local angle = s.phase + cycle * math.pi * 3
			local y = 0.4 + 3 * cycle
			local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
			s.a0.Position = pos
			s.a1.Position = pos + Vector3.new(0, 0.12 + 0.25 * (1 - cycle), 0)
			s.trail.Enabled = t < BURST - 0.05
		end
		return t > BURST
	end)
end

local function burst(ctx)
	local c = ctx.colors
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 3.5, 0), "TX_Flash", 1, {
			Color = gradient(c.Main, 0.8, 0.4),
			Size = numbers({ { 0, 4 }, { 0.25, 34 }, { 1, 40 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.45),
			Speed = NumberRange.new(0, 0),
			LightEmission = 1,
		})
		ctx:shockwave(ctx:at(0, 0, 0), c.Main, 2, 60, 0.75)
		ctx:when(BURST + 0.12, function()
			ctx:shockwave(ctx:at(0, 0, 0), c.Glow, 2, 42, 0.95)
		end)
		ctx:puff(ctx:at(0, 0.4, 0), "Glow", 40, {
			Color = ColorSequence.new(tone(ctx.groundColor, 0.2)),
			Size = numbers({ { 0, 2 }, { 1, 5 } }),
			Transparency = numbers({ { 0, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(30, 45),
			SpreadAngle = Vector2.new(88, 4),
			EmissionDirection = Enum.NormalId.Top,
			Drag = 4,
			LightEmission = 0,
		})
		-- the pillar of light
		local foot = ctx:anchor(ctx:at(0, 0, 0))
		local a0 = ctx:attachment(foot, ctx:at(0, 0, 0))
		local a1 = ctx:attachment(foot, ctx:at(0, 140, 0))
		local outer = ctx:beam(a0, a1, "TX_Pillar", { Color = gradient(c.Main, 0.4, 0), LightEmission = 1, Width0 = 0, Width1 = 0, Segments = 2 })
		local core = ctx:beam(a0, a1, "TX_Pillar", { Color = ColorSequence.new(tone(c.Main, 0.85)), LightEmission = 1, Width0 = 0, Width1 = 0, Segments = 2 })
		ctx:every(function(t)
			local age = t - BURST
			local w = easeOut(phase(age, 0, 0.08)) * (1 - phase(age, 0.15, 0.85))
			outer.Width0, outer.Width1 = 9 * w, 13 * w
			core.Width0, core.Width1 = 3.5 * w, 5 * w
			outer.Transparency = numbers({ { 0, 0.1 }, { 1, 0.6 } })
			return age > 0.9
		end)
	end)
	ctx:when(BURST + 0.38, function()
		-- landing in the stance: a last puff of dust
		ctx:shockwave(ctx:at(0, 0, 0), c.Accent, 1, 9, 0.4)
	end)
end

-- ---------------------------------------------------------------- the cinematic (transforming player only)

local function cinematic(ctx)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local oldType, oldFov = camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	-- used if the transformation is cut short (cancelled, or the character despawns)
	ctx.restoreCamera = function()
		camera.CameraType = oldType
		camera.FieldOfView = oldFov
	end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "EterniumTransformGrade"
	grade.Parent = Lighting
	ctx:track(grade)

	local gui = Instance.new("ScreenGui")
	gui.Name = "EterniumTransformFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = tone(ctx.colors.Main, 0.75)
	flash.BackgroundTransparency = 1
	flash.Parent = gui
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	gui.Parent = playerGui
	ctx:track(gui)

	local function orbit(angleDeg, dist, height, lookY)
		local a = math.rad(angleDeg)
		local pos = ctx:at(math.sin(a) * dist, height, -math.cos(a) * dist)
		return CFrame.lookAt(pos, ctx:at(0, lookY, 0))
	end

	-- the shot list: smooth moves within each shot, hard cuts between them
	local function shot(t)
		if t < 1.0 then -- low and close, sliding round the front as the ground starts to crack
			local e = easeInOut(t / 1.0)
			return orbit(-40 + 28 * e, 11 - e, 1.3, 3.6), 70
		elseif t < 2.0 then -- high and wide from behind: the rocks rising, the cracks spreading
			local e = easeInOut(t - 1.0)
			return orbit(150 + 50 * e, 15, 8 - e, 2.4), 70
		elseif t < BURST then -- slow push in to the face as the power peaks: a long-lens zoom from low
			-- down, kept back past the floating rocks and rings so the camera never clips into them
			local e = easeInOut((t - 2.0) / (BURST - 2.0))
			return orbit(8 - 6 * e, 13 - 1.2 * e, 2.8 + 0.8 * e, 4.5), 46 - 22 * e
		else -- the burst: cut wide and low, FOV punch, then ease into the hero stance
			local e = easeOut(phase(t, BURST, SETTLE))
			return orbit(-22 + 6 * e, 17 - 3 * e, 1.1 + 0.3 * e, 4.8), 96 - 24 * easeOut(phase(t, BURST, BURST + 0.35))
		end
	end

	ctx:every(function(t)
		if t >= SETTLE then
			-- hand the camera back with a short blend into the player's own view
			local from = camera.CFrame
			ctx.restoreCamera()
			ctx.restoreCamera = nil
			local start = os.clock()
			local name = "EterniumTransformBlend" .. tostring(ctx.id)
			RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
				local k = easeInOut(clamp01((os.clock() - start) / 0.35))
				camera.CFrame = from:Lerp(camera.CFrame, k)
				if k >= 1 then
					RunService:UnbindFromRenderStep(name)
				end
			end)
			ctx.cameraName = name
			flash.BackgroundTransparency = 1
			grade.Enabled = false
			return true
		end
		local cf, fov = shot(t)
		local build = phase(t, 0, BURST)
		local amp = (t < BURST) and (0.02 + 0.13 * build * build) or (0.9 * math.exp(-(t - BURST) * 7))
		local shake = Vector3.new(math.noise(t * 23, 1.7), math.noise(t * 23, 7.3), math.noise(t * 23, 3.1)) * amp
		camera.CFrame = cf * CFrame.new(shake)
		camera.FieldOfView = fov
		-- the world drains of colour as the power builds, then pops at the burst
		local pop = math.max(0, 1 - (t - BURST) / 0.45)
		grade.Saturation = t < BURST and -0.4 * build or 0.25 * pop
		grade.Contrast = t < BURST and 0.15 * build or 0.3 * pop
		grade.TintColor = Color3.new(1, 1, 1):Lerp(tone(ctx.colors.Glow, 0.55), t < BURST and 0.35 * build or 0.4 * pop)
		flash.BackgroundTransparency = t < BURST and 1 or phase(t, BURST, BURST + 0.45)
		return false
	end)
end

-- hold the transforming player still, and play the optional animations
local function freeze(ctx)
	local humanoid = ctx.character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local saved = { humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate }
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate = 0, 0, 0, false
	ctx.restore = function()
		if humanoid.Parent then
			humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate = saved[1], saved[2], saved[3], saved[4]
		end
	end
	ctx:when(SETTLE, function()
		if ctx.restore then
			ctx.restore()
			ctx.restore = nil
		end
	end)
end

local function animations(ctx)
	local humanoid = ctx.character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local function load(id)
		if not id or id == "" then
			return nil
		end
		local anim = ctx:track(Instance.new("Animation"))
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		return ok and track or nil
	end
	local buildup, burstTrack, stance = load(Transform.Animations.Buildup), load(Transform.Animations.Burst), load(Transform.Animations.Stance)
	if buildup then
		buildup:Play(0.2)
	end
	ctx:when(BURST, function()
		if buildup then
			buildup:Stop(0.05)
		end
		if burstTrack then
			burstTrack:Play(0.05)
		end
	end)
	ctx:when(BURST + 0.25, function()
		if stance then
			stance:Play(0.2)
		end
	end)
	ctx:when(SETTLE + 0.8, function()
		if stance then
			stance:Stop(0.3)
		end
	end)
end

-- ---------------------------------------------------------------- the body: a procedural performance
-- The character acts out the transformation by posing its own joints every frame, so it needs no
-- uploaded animations and every client sees it. It blends in over the player's own animations and
-- hands back to them afterwards. Supplying Transform.Animations switches this off.
--
-- Joint rotations are in each joint's parent space, in degrees: x pitches (+ swings a limb forward,
-- or tips the torso / head back), y turns, z rolls (+ swings towards the character's right).
local JOINT_NAMES = {
	Root = { "Root", "RootJoint" },
	Waist = { "Waist" },
	Neck = { "Neck" },
	LShoulder = { "LeftShoulder", "Left Shoulder" },
	RShoulder = { "RightShoulder", "Right Shoulder" },
	LElbow = { "LeftElbow" },
	RElbow = { "RightElbow" },
	LHip = { "LeftHip", "Left Hip" },
	RHip = { "RightHip", "Right Hip" },
	LKnee = { "LeftKnee" },
	RKnee = { "RightKnee" },
	LAnkle = { "LeftAnkle" },
	RAnkle = { "RightAnkle" },
}

-- a full-body pose from a few intentions; arms are mirrored unless `right` overrides the right arm
local function pose(p)
	local arm = p.arms or { 0, 0, 0 } -- { pitch, roll outwards, elbow }
	local right = p.right or arm
	local c, w = p.crouch or 0, p.wide or 0
	return {
		crouch = c,
		lift = p.lift or 0,
		Root = { p.tilt or 0, 0, 0 },
		Waist = { p.lean or 0, p.twist or 0, 0 },
		Neck = { p.head or 0, p.look or 0, 0 },
		LShoulder = { arm[1], -(arm[4] or 0), -arm[2] },
		RShoulder = { right[1], right[4] or 0, right[2] },
		LElbow = { arm[3], 0, 0 },
		RElbow = { right[3], 0, 0 },
		LHip = { c, 0, -w },
		RHip = { c, 0, w },
		LKnee = { -2 * c, 0, 0 },
		RKnee = { -2 * c, 0, 0 },
		LAnkle = { c, 0, w },
		RAnkle = { c, 0, -w },
	}
end

-- the shared performance: power stance, straining crouch, coil, explosive release, powered-up stance
local function performance(rightArm)
	local function key(t, p)
		if rightArm and rightArm[t] then
			p.right = rightArm[t].arm
			p.twist = rightArm[t].twist or p.twist
		end
		return { t = t, pose = pose(p) }
	end
	return {
		key(0, {}),
		key(0.3, { crouch = 22, wide = 10, lean = -8, head = -6, arms = { -12, 18, 70 } }),
		key(1.4, { crouch = 30, wide = 12, lean = -13, head = -14, arms = { -18, 25, 88 } }),
		key(2.55, { crouch = 36, wide = 12, lean = -18, head = -22, arms = { -22, 30, 98 } }),
		key(2.92, { crouch = 42, wide = 12, lean = -27, head = -26, arms = { 58, -28, 122 } }),
		key(BURST + 0.06, { crouch = 6, wide = 16, lift = 0.9, lean = 18, head = 30, arms = { -32, 120, 12 } }),
		key(BURST + 0.24, { crouch = 8, wide = 16, lift = 0.6, lean = 14, head = 22, arms = { -26, 108, 16 } }),
		key(SETTLE, { crouch = 18, wide = 14, lean = -4, head = 0, arms = { -8, 22, 35 } }),
	}
end

-- Radiant Edge raises its sword hand to the sky while the blade forms, winds up, and the arm delivers
-- the slash itself; it ends with the sword held low and forward until it dissolves
local RADIANT_ARM = {
	[0.3] = { arm = { 60, 10, 30 } },
	[1.4] = { arm = { 172, 8, 8 } },
	[2.55] = { arm = { 176, 6, 6 } },
	[2.92] = { arm = { 198, 4, 30 }, twist = 14 },
	[BURST + 0.06] = { arm = { 78, -24, 4 }, twist = -28 },
	[BURST + 0.24] = { arm = { 76, -22, 6 }, twist = -24 },
	[SETTLE] = { arm = { 70, -10, 10 }, twist = -8 },
}

Transform.Performances = { Default = performance(), RadiantEdge = performance(RADIANT_ARM) }
-- when each aura hands the body back to the player's animations (Radiant Edge holds its sword until
-- the blade has dissolved)
Transform.PerformanceRelease = { Default = SETTLE, RadiantEdge = SETTLE + 0.8 }

local function perform(ctx)
	local motors = {}
	for _, d in ctx.character:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local joints = {}
	for key, names in JOINT_NAMES do
		for _, name in names do
			if motors[name] then
				joints[key] = motors[name]
				break
			end
		end
	end
	if not joints.Root and not joints.Waist and not joints.RShoulder then
		return
	end
	-- crouching lowers the body by however far bent legs shorten; rigs without knees just pose upright
	local legs = 0
	local upper, lower = ctx.character:FindFirstChild("RightUpperLeg"), ctx.character:FindFirstChild("RightLowerLeg")
	if joints.RKnee and upper and lower then
		legs = upper.Size.Y * 0.85 + lower.Size.Y
	end
	local keys = Transform.Performances[ctx.name] or Transform.Performances.Default
	local release = Transform.PerformanceRelease[ctx.name] or Transform.PerformanceRelease.Default
	local written = {}

	local function sample(t)
		local i = 1
		while i < #keys and keys[i + 1].t <= t do
			i += 1
		end
		local a, b = keys[i], keys[math.min(i + 1, #keys)]
		local k = (b.t > a.t) and easeInOut(clamp01((t - a.t) / (b.t - a.t))) or 0
		return a.pose, b.pose, k
	end

	local function apply(t)
		local weight = easeInOut(phase(t, 0, 0.18)) * (1 - easeInOut(phase(t, release, release + 0.55)))
		if weight <= 0 then
			return
		end
		local pa, pb, k = sample(t)
		local crouch = pa.crouch + (pb.crouch - pa.crouch) * k
		if not joints.RKnee then
			crouch = 0
		end
		local lift = pa.lift + (pb.lift - pa.lift) * k
		local drop = legs * (1 - math.cos(math.rad(crouch)))
		-- the strain: a tremble that builds through the charge, a jolt at the burst, then breathing
		local tremble = t < BURST and (0.4 + 2.6 * phase(t, 0.3, BURST) ^ 2) or 4 * math.exp(-(t - BURST) * 9)
		local breathe = math.sin(t * (t < BURST and 7 or 3.5)) * (t < BURST and 2.5 or 1.5)
		for name, motor in joints do
			local ra, rb = pa[name], pb[name]
			local x, y, z = ra[1] + (rb[1] - ra[1]) * k, ra[2] + (rb[2] - ra[2]) * k, ra[3] + (rb[3] - ra[3]) * k
			if name == "Root" and crouch == 0 then
				x = 0
			elseif (name == "LHip" or name == "RHip" or name == "LKnee" or name == "RKnee" or name == "LAnkle" or name == "RAnkle") and not joints.RKnee then
				x = 0
			end
			if name == "Waist" or name == "Neck" or name == "LShoulder" or name == "RShoulder" then
				local seed = #name * 1.7
				x += math.noise(t * 17, seed) * tremble + (name == "Waist" and breathe or 0)
				z += math.noise(seed, t * 17) * tremble * 0.6
			end
			local rot = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
			local frame = motor.C0.Rotation
			local target = frame:Inverse() * rot * frame
			if name == "Root" then
				target = CFrame.new(frame:Inverse() * Vector3.new(0, lift - drop, 0)) * target
			end
			-- blend over whatever the player's own animations put there this frame
			local current = motor.Transform
			if written[motor] and current == written[motor] then
				current = CFrame.new()
			end
			local result = current:Lerp(target, weight)
			motor.Transform = result
			written[motor] = result
		end
	end

	ctx.performing = true
	ctx.performEnd = release + 0.55
	local okSignal, stepped = pcall(function()
		return RunService.PreSimulation
	end)
	if not okSignal or not stepped then
		stepped = RunService.Stepped
	end
	-- animations are evaluated before this step, so poses written here win for this frame
	ctx.poseConnection = stepped:Connect(function()
		if ctx.t <= ctx.performEnd then
			apply(ctx.t)
		end
	end)
	ctx.resetPose = function()
		for motor, value in written do
			if motor.Parent and motor.Transform == value then
				motor.Transform = CFrame.new()
			end
		end
	end
end

local function sound(ctx, kind, at)
	local set = Transform.Sounds[ctx.name]
	local id = set and set[kind]
	if not id or id == "" then
		return
	end
	ctx:when(at, function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = 0.9
		s.Parent = ctx.root
		s:Play()
		ctx:track(s)
	end)
end

-- ---------------------------------------------------------------- each aura's own build-up and finish

local Signatures = {}
Transform.Signatures = Signatures

-- Limit Breaker: lightning strikes down onto you, faster and faster, arcs crawling out over the ground
Signatures.LimitBreaker = function(ctx)
	local c = ctx.colors
	local time, gap = 0.35, 0.55
	while time < BURST - 0.05 do
		local strikeTime = time
		ctx:when(strikeTime, function()
			local top = ctx:at(ctx.rng:NextNumber(-4, 4), 45, ctx.rng:NextNumber(-4, 4))
			ctx:bolt(top, ctx:at(ctx.rng:NextNumber(-0.4, 0.4), 4.8, 0), 0.32, c.Main, 0.16, 2)
			ctx:puff(ctx:at(0, 4.5, 0), "LB_Flare", 1, {
				Color = gradient(c.Main, 0.7, 0.3),
				Size = numbers({ { 0, 1 }, { 0.3, 6 }, { 1, 0 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.2, 0.2),
				Speed = NumberRange.new(0, 0),
				LightEmission = 1,
			})
		end)
		time += gap
		gap = math.max(0.06, gap * 0.8) -- faster and faster
	end
	ctx:every(function(t)
		ctx.nextArc = ctx.nextArc or 0.2
		if t >= ctx.nextArc and t < BURST then
			local angle = ctx.rng:NextNumber(0, math.pi * 2)
			local reach = ctx.rng:NextNumber(2.5, 6) * (0.6 + 0.6 * phase(t, 0, BURST))
			ctx:bolt(ctx:at(0, 0.15, 0), ctx:at(math.cos(angle) * reach, 0.15, math.sin(angle) * reach), 0.12, c.Accent, 0.14, 1)
			ctx.nextArc = t + 0.16 - 0.1 * phase(t, 0, BURST)
		end
		return t > BURST
	end)
	ctx:when(BURST, function()
		ctx:bolt(ctx:at(0, 80, 0), ctx:at(0, 3, 0), 1.6, c.Main, 0.35, 4)
		for k = 1, 4 do
			local a = k * math.pi / 2 + 0.4
			ctx:bolt(ctx:at(math.cos(a) * 3, 60, math.sin(a) * 3), ctx:at(math.cos(a) * 6, 0, math.sin(a) * 6), 0.6, c.Main, 0.3, 2)
		end
	end)
end

-- Azure Surge: a storm gathers overhead, arcs crackle round the body, lightning lashes the ground
Signatures.AzureSurge = function(ctx)
	local c = ctx.colors
	local cloud = ctx:emitter(ctx:anchor(ctx:at(0, 16, 0), Vector3.new(26, 2, 26)), "AS_Plasma", {
		Color = ColorSequence.new(tone(c.Glow, -0.75), tone(c.Glow, -0.85)),
		Size = numbers({ { 0, 7 }, { 1, 12 } }),
		Transparency = numbers({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(0.5, 1.5),
		RotSpeed = NumberRange.new(-20, 20),
		LightEmission = 0,
		Rate = 0,
	})
	cloud.Enabled = true
	ctx:every(function(t)
		local build = phase(t, 0, BURST)
		cloud.Rate = t < BURST + 0.3 and 8 + 30 * build or 0
		ctx.nextCrackle = ctx.nextCrackle or 0.1
		if t >= ctx.nextCrackle and t < BURST then
			local function around()
				local d = Vector3.new(ctx.rng:NextNumber(-1, 1), ctx.rng:NextNumber(-0.6, 1), ctx.rng:NextNumber(-1, 1)).Unit
				return ctx:at(0, 3.2, 0) + d * ctx.rng:NextNumber(1.6, 2.8)
			end
			ctx:bolt(around(), around(), 0.14, c.Accent, 0.1, 1)
			ctx.nextCrackle = t + 0.12 - 0.08 * build
		end
		ctx.nextLash = ctx.nextLash or 0.6
		if t >= ctx.nextLash and t < BURST then
			local a = ctx.rng:NextNumber(0, math.pi * 2)
			local r = ctx.rng:NextNumber(3.5, 6.5)
			ctx:bolt(ctx:at(math.cos(a) * r * 0.5, 16, math.sin(a) * r * 0.5), ctx:at(math.cos(a) * r, 0, math.sin(a) * r), 0.35, c.Main, 0.18, 3)
			ctx:shockwave(ctx:at(math.cos(a) * r, 0, math.sin(a) * r), c.Glow, 0.5, 5, 0.3, "AS_Plasma")
			ctx.nextLash = t + 0.5 - 0.3 * build
		end
		return t > BURST + 0.3
	end)
	ctx:when(BURST, function()
		for k = 1, 12 do
			local a = k / 12 * math.pi * 2
			ctx:bolt(ctx:at(0, 3.2, 0), ctx:at(math.cos(a) * 11, ctx.rng:NextNumber(0, 6), math.sin(a) * 11), 0.4, c.Main, 0.3, 2)
		end
		ctx:puff(ctx:at(0, 3.2, 0), "AS_Fork", 30, {
			Color = gradient(c.Main, 0.6, 0.3),
			Size = numbers({ { 0, 6 }, { 1, 9 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.12, 0.2),
			Speed = NumberRange.new(0, 0),
			LightEmission = 1,
		})
	end)
end

-- Phantom Blaze: phantom flames burst up out of the ground in a widening ring
Signatures.PhantomBlaze = function(ctx)
	local c = ctx.colors
	local center = ctx:anchor(ctx:at(0, 0, 0))
	local ring = {}
	for k = 1, 22 do
		local a = ctx:attachment(center)
		local e = ctx:emitter(a, "PB_Flame", {
			Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, tone(c.Main, 0.4)), ColorSequenceKeypoint.new(0.6, c.Main), ColorSequenceKeypoint.new(1, c.Accent) }),
			Size = numbers({ { 0, 1 }, { 0.5, 2.2 }, { 1, 0.5 } }),
			Transparency = numbers({ { 0, 1 }, { 0.15, 0.05 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.7),
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(8, 8),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(-10, 10),
			LightEmission = 0.9,
			Rate = 0,
		})
		e.Enabled = true
		table.insert(ring, { a = a, e = e, angle = k / 22 * math.pi * 2 })
	end
	local smoke = ctx:emitter(center, "PB_Smoke", {
		Color = ColorSequence.new(tone(c.Glow, -0.2)),
		Size = numbers({ { 0, 3 }, { 1, 7 } }),
		Transparency = numbers({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60),
		LightEmission = 0,
		Rate = 6,
	})
	smoke.Enabled = true
	ctx:every(function(t)
		local build = phase(t, 0.2, BURST)
		local radius = 1 + 7 * easeOut(build)
		local roar = t >= BURST and math.max(0, 1 - (t - BURST) / 0.5) or 0
		for _, f in ring do
			f.a.Position = Vector3.new(math.cos(f.angle + t * 0.4) * radius, 0, math.sin(f.angle + t * 0.4) * radius)
			f.e.Rate = (t < BURST + 0.5) and (6 + 14 * build + 40 * roar) or 0
			f.e.Speed = NumberRange.new(4 + 8 * roar, 7 + 14 * roar)
		end
		smoke.Enabled = t < BURST
		return t > BURST + 0.6
	end)
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 0.5, 0), "PB_Flame", 40, {
			Color = gradient(c.Main, 0.5, 0),
			Size = numbers({ { 0, 2 }, { 0.5, 5 }, { 1, 1 } }),
			Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(25, 40),
			SpreadAngle = Vector2.new(12, 12),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 1,
		})
	end)
end

-- Frost Crown: ice crystals erupt from the ground in a widening ring, then shatter outwards
Signatures.FrostCrown = function(ctx)
	local c = ctx.colors
	local crystals = {}
	for k = 1, 30 do
		local ringIndex = (k - 1) % 3
		local a = (k / 30) * math.pi * 2 + ringIndex * 0.3
		local r = 2.2 + ringIndex * 1.8
		local h = ctx.rng:NextNumber(1.5, 3.8) * (1 - ringIndex * 0.15)
		local w = ctx.rng:NextNumber(0.35, 0.65)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local tilt = CFrame.fromAxisAngle(Vector3.new(-out.Z, 0, out.X), math.rad(ctx.rng:NextNumber(12, 30)))
		local p = ctx:part({
			Material = Enum.Material.Glass,
			Color = tone(c.Main, ctx.rng:NextNumber(-0.1, 0.2)),
			Transparency = 1,
			Size = Vector3.new(w, h, w),
			Reflectance = 0.1,
		})
		table.insert(crystals, { part = p, base = out * r, tilt = tilt, h = h, rise = 0.3 + (r - 2.2) / 3.6 * 2.1 + ctx.rng:NextNumber(0, 0.25) })
	end
	local frost = ctx:emitter(ctx:anchor(ctx:at(0, 0.1, 0), Vector3.new(12, 0.2, 12)), "FC_Glint", {
		Color = gradient(c.Accent, 0.3, 0),
		Size = numbers({ { 0, 0 }, { 0.5, 0.5 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(0, 0),
		LightEmission = 1,
		Rate = 25,
	})
	frost.Enabled = true
	ctx:every(function(t)
		for _, cr in crystals do
			if cr.part.Parent then
				local e = easeOut(phase(t, cr.rise, cr.rise + 0.18))
				local rumble = (1 - phase(t, cr.rise, cr.rise + 0.5)) * 0.05
				local cf = CFrame.new(cr.base + Vector3.new(math.noise(t * 30, cr.rise) * rumble, -cr.h / 2 + cr.h * e * 0.95, 0)) * cr.tilt
				cr.part.CFrame = ctx.cf * cf
				cr.part.Transparency = e > 0 and 0.2 or 1
			end
		end
		frost.Enabled = t < BURST
		return t > BURST
	end)
	ctx:when(BURST, function()
		for _, cr in crystals do
			local pos = cr.part.Position
			cr.part:Destroy()
			ctx:puff(pos, "FC_Shard", 7, {
				Color = gradient(c.Main, 0.4, 0),
				Size = numbers({ { 0, 0.5 }, { 1, 0.3 } }),
				Transparency = numbers({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1.1),
				Speed = NumberRange.new(20, 36),
				SpreadAngle = Vector2.new(60, 60),
				Acceleration = Vector3.new(0, -40, 0),
				RotSpeed = NumberRange.new(-300, 300),
				LightEmission = 0.6,
			})
			ctx:puff(pos, "FC_Glint", 2, {
				Color = ColorSequence.new(tone(c.Accent, 0.5)),
				Size = numbers({ { 0, 0 }, { 0.3, 2.5 }, { 1, 0 } }),
				Lifetime = NumberRange.new(0.25, 0.35),
				Speed = NumberRange.new(0, 0),
				LightEmission = 1,
			})
		end
	end)
end

-- Verdant Bloom: leaves whirl up around you, faster and faster, and scatter in a burst of petals
Signatures.VerdantBloom = function(ctx)
	local c = ctx.colors
	local center = ctx:anchor(ctx:at(0, 0, 0))
	local whirl = {}
	for k = 1, 9 do
		local a = ctx:attachment(center)
		local leaves = ctx:emitter(a, "VB_Leaf", {
			Color = gradient(c.Accent, 0.15, -0.15),
			Size = numbers({ { 0, 0.5 }, { 1, 0.35 } }),
			Transparency = numbers({ { 0, 1 }, { 0.1, 0 }, { 0.8, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(0.5, 1),
			RotSpeed = NumberRange.new(-300, 300),
			LightEmission = 0.1,
			Rate = 16,
		})
		local petals = ctx:emitter(a, "VB_Petal", {
			Color = gradient(c.Main, 0.2, -0.1),
			Size = numbers({ { 0, 0.4 }, { 1, 0.25 } }),
			Transparency = numbers({ { 0, 1 }, { 0.1, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(0.5, 1),
			RotSpeed = NumberRange.new(-200, 200),
			LightEmission = 0.2,
			Rate = 8,
		})
		leaves.Enabled, petals.Enabled = true, true
		table.insert(whirl, { a = a, leaves = leaves, petals = petals, offset = k / 9, phase = k * 0.7 })
	end
	ctx:every(function(t)
		local build = phase(t, 0, BURST)
		for _, w in whirl do
			local cycle = (t * (0.35 + 0.6 * build) + w.offset) % 1
			local r = 3.2 - 1.6 * cycle
			local angle = w.phase + t * (2 + 6 * build)
			w.a.Position = Vector3.new(math.cos(angle) * r, 0.3 + 6.5 * cycle, math.sin(angle) * r)
			w.leaves.Enabled = t < BURST
			w.petals.Enabled = t < BURST
		end
		return t > BURST
	end)
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 3.5, 0), "VB_Leaf", 70, {
			Color = gradient(c.Accent, 0.2, -0.1),
			Size = numbers({ { 0, 0.6 }, { 1, 0.4 } }),
			Transparency = numbers({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(25, 40),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			RotSpeed = NumberRange.new(-400, 400),
			LightEmission = 0.2,
		})
		ctx:shockwave(ctx:at(0, 0, 0), c.Main, 1, 20, 0.9, "VB_Ripple")
	end)
end

-- Void Current / Umbral Veil: dark tendrils reach up out of the ground towards you while a sphere of
-- darkness closes in on your body, then the darkness shatters outwards
local function darkness(ctx, tendrilTexture, extra)
	local c = ctx.colors
	local chest = ctx:at(0, 3.2, 0)
	local sphere = ctx:part({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = tone(c.Glow, -0.3),
		Transparency = 1,
		Size = Vector3.new(24, 24, 24),
		CFrame = CFrame.new(chest),
	})
	local inner = ctx:part({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.SmoothPlastic,
		Color = tone(c.Glow, -0.6),
		Transparency = 1,
		Size = Vector3.new(24, 24, 24),
		CFrame = CFrame.new(chest),
	})
	local tendrils = {}
	local holder = ctx:anchor(ctx:at(0, 0, 0))
	local target = ctx:attachment(holder, chest)
	for k = 1, 9 do
		local a = k / 9 * math.pi * 2 + ctx.rng:NextNumber(-0.2, 0.2)
		local r = ctx.rng:NextNumber(5, 8)
		local root = ctx:attachment(holder, ctx:at(math.cos(a) * r, 0, math.sin(a) * r))
		local tip = ctx:attachment(holder, ctx:at(math.cos(a) * r, 0, math.sin(a) * r))
		local b = ctx:beam(root, tip, tendrilTexture, {
			Color = ColorSequence.new(tone(c.Glow, -0.2), c.Main),
			Width0 = 0.9,
			Width1 = 0.25,
			LightEmission = 0.3,
			TextureMode = Enum.TextureMode.Stretch,
			TextureSpeed = 1.5,
			Transparency = numbers({ { 0, 0.1 }, { 1, 0.4 } }),
		})
		table.insert(tendrils, { root = root, tip = tip, beam = b, from = root.WorldPosition, reach = 0.4 + k * 0.15, phase = k * 1.3 })
	end
	ctx:every(function(t)
		local close = easeInOut(phase(t, 0.4, BURST))
		if t < BURST then
			local size = 24 - 19 * close
			sphere.Size = Vector3.new(size, size, size)
			inner.Size = sphere.Size * 0.97
			sphere.Transparency = 1 - 0.75 * phase(t, 0.4, 1.2)
			inner.Transparency = 1 - 0.35 * close
		else
			-- shatters outwards
			local e = easeOut(phase(t, BURST, BURST + 0.35))
			local size = 5 + 40 * e
			sphere.Size = Vector3.new(size, size, size)
			inner.Size = sphere.Size * 0.97
			sphere.Transparency = 0.25 + 0.75 * e
			inner.Transparency = 0.65 + 0.35 * phase(t, BURST, BURST + 0.12)
		end
		for _, td in tendrils do
			local grow = easeInOut(phase(t, td.reach, BURST - 0.2))
			local whip = t >= BURST and easeOut(phase(t, BURST, BURST + 0.3)) or 0
			local goal = td.from:Lerp(chest, 0.92)
			local tip = td.from:Lerp(goal, grow)
			if whip > 0 then
				tip = goal + (td.from - chest) * whip * 1.6 + Vector3.new(0, 4 * whip, 0)
			end
			td.tip.WorldPosition = tip
			td.beam.CurveSize0 = 2.5 * math.sin(t * 3 + td.phase)
			td.beam.CurveSize1 = -1.5 * math.sin(t * 2.3 + td.phase)
			td.beam.Enabled = t < BURST + 0.35
		end
		if extra then
			extra(t, close)
		end
		return t > BURST + 0.4
	end)
end

Signatures.VoidCurrent = function(ctx)
	darkness(ctx, "VC_Tendril")
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 3.2, 0), "VC_Flame", 36, {
			Color = ColorSequence.new(ctx.colors.Main, tone(ctx.colors.Glow, -0.3)),
			Size = numbers({ { 0, 1.5 }, { 1, 4 } }),
			Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(20, 32),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			LightEmission = 0.2,
		})
	end)
end

Signatures.UmbralVeil = function(ctx)
	local static = ctx:emitter(ctx:anchor(ctx:at(0, 3.2, 0), Vector3.new(6, 6, 6)), "UV_Glitch", {
		Color = gradient(ctx.colors.Accent, 0.3, 0),
		Size = numbers({ { 0, 1.5 }, { 1, 2 } }),
		Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.06, 0.14),
		Speed = NumberRange.new(0, 0),
		Rotation = NumberRange.new(0, 0),
		LightEmission = 0.7,
		Rate = 0,
	})
	static.Enabled = true
	darkness(ctx, "UV_Scribble", function(t, close)
		static.Rate = t < BURST and 10 + 50 * close or 0
	end)
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 3.2, 0), "UV_Glitch", 40, {
			Color = gradient(ctx.colors.Accent, 0.4, 0),
			Size = numbers({ { 0, 2 }, { 1, 3 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.15, 0.35),
			Speed = NumberRange.new(20, 40),
			SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 0),
			LightEmission = 0.8,
		})
	end)
end

-- Silver Sheen: columns of light rise around you while rings pulse off your body like a speeding heartbeat
Signatures.SilverSheen = function(ctx)
	local c = ctx.colors
	local holder = ctx:anchor(ctx:at(0, 0, 0))
	local columns = {}
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		local base = ctx:at(math.cos(a) * 5.5, 0, math.sin(a) * 5.5)
		local a0 = ctx:attachment(holder, base)
		local a1 = ctx:attachment(holder, base)
		local b = ctx:beam(a0, a1, "TX_Pillar", {
			Color = gradient(c.Main, 0.5, 0.1),
			Width0 = 1.4,
			Width1 = 1.4,
			LightEmission = 1,
			Segments = 2,
			Transparency = numbers({ { 0, 0.1 }, { 1, 0.9 } }),
		})
		table.insert(columns, { a1 = a1, base = base, beam = b, start = 0.2 + k * 0.32, angle = a })
	end
	local beats = {}
	local time, gap = 0.3, 0.7
	while time < BURST - 0.05 do
		table.insert(beats, time)
		time += gap
		gap = math.max(0.12, gap * 0.82) -- the heartbeat speeds up
	end
	for _, beat in beats do
		ctx:when(beat, function()
			ctx:shockwave(ctx:at(0, 3.2, 0), c.Main, 2, 11, 0.5, "SS_Ripple")
		end)
	end
	ctx:every(function(t)
		for _, col in columns do
			local h = easeOut(phase(t, col.start, col.start + 0.6)) * 22
			local collapse = t >= BURST and easeOut(phase(t, BURST, BURST + 0.25)) or 0
			local base = col.base:Lerp(ctx:at(0, 0, 0), collapse)
			col.a1.WorldPosition = base + Vector3.new(0, math.max(h, 0.01), 0)
			col.beam.Attachment0.WorldPosition = base
			local pulse = 0
			for _, beat in beats do
				pulse = math.max(pulse, 1 - math.abs(t - beat) / 0.1)
			end
			local w = (1.2 + 0.8 * pulse) * (1 - collapse)
			col.beam.Width0, col.beam.Width1 = w, w
			col.beam.Enabled = t < BURST + 0.25
		end
		return t > BURST + 0.3
	end)
	ctx:when(BURST, function()
		ctx:puff(ctx:at(0, 3.2, 0), "SS_Flare", 1, {
			Color = ColorSequence.new(tone(c.Accent, 0.6)),
			Size = numbers({ { 0, 2 }, { 0.3, 22 }, { 1, 0 } }),
			Lifetime = NumberRange.new(0.4, 0.4),
			Speed = NumberRange.new(0, 0),
			RotSpeed = NumberRange.new(90, 90),
			LightEmission = 1,
		})
	end)
end

-- Dusk Wings: a funnel of wind twists up around you; at the burst, two wings of light sweep open
Signatures.DuskWings = function(ctx)
	local c = ctx.colors
	local base = ctx:anchor(ctx:at(0, 0, 0))
	local funnel = {}
	for i = 1, 9 do
		local a0, a1 = ctx:attachment(base), ctx:attachment(base)
		local tr = Instance.new("Trail")
		tr.Texture = texture("DW_Rib")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.5
		tr.LightEmission = 0.7
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Color = gradient(c.Glow, 0.4, 0)
		tr.Transparency = numbers({ { 0, 0.2 }, { 1, 1 } })
		tr.Parent = base
		ctx:track(tr)
		table.insert(funnel, { a0 = a0, a1 = a1, trail = tr, offset = i / 9, phase = i * 0.7, last = 0 })
	end
	local feathers = ctx:emitter(ctx:anchor(ctx:at(0, 3, 0), Vector3.new(6, 6, 6)), "DW_Feather", {
		Color = gradient(c.Accent, 0.2, 0),
		Size = numbers({ { 0, 0.5 }, { 1, 0.35 } }),
		Transparency = numbers({ { 0, 1 }, { 0.15, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
		RotSpeed = NumberRange.new(-200, 200),
		LightEmission = 0.5,
		Rate = 14,
	})
	feathers.Enabled = true
	ctx:every(function(t)
		local build = phase(t, 0, BURST)
		for _, f in funnel do
			local cycle = (t * (0.6 + 0.8 * build) + f.offset) % 1
			if cycle < f.last then
				f.trail:Clear()
			end
			f.last = cycle
			local h = cycle * 9
			local r = 1.4 + h * 0.42
			local angle = f.phase + t * (4 + 5 * build)
			local pos = Vector3.new(math.cos(angle) * r, h, math.sin(angle) * r)
			f.a0.Position = pos
			f.a1.Position = pos + Vector3.new(0, 0.3, 0)
			f.trail.Enabled = t < BURST
		end
		feathers.Enabled = t < BURST
		return t > BURST
	end)
	-- the wings of light sweeping open at the burst
	ctx:when(BURST, function()
		local back = ctx:anchor(ctx:at(0, 4.2, 0.6))
		local wings = {}
		for _, side in { -1, 1 } do
			for k, deg in ipairs({ 70, 45, 22, 2, -18 }) do
				local root = ctx:attachment(back, ctx:at(side * 0.3, 4.2, 0.6))
				local tip = ctx:attachment(back, ctx:at(side * 0.3, 4.2, 0.6))
				local b = ctx:beam(root, tip, "DW_Rib", {
					Color = gradient(c.Glow, 0.6, 0.1),
					Width0 = 0.4,
					Width1 = 0.12,
					LightEmission = 1,
					CurveSize0 = 0.8,
				})
				table.insert(wings, { tip = tip, side = side, deg = deg, length = 6.5 - k * 0.6, beam = b })
			end
		end
		local opened = ctx.t
		ctx:every(function(t)
			local age = t - opened
			local open = easeOut(phase(age, 0, 0.35))
			local fade = phase(age, 0.6, 1.3)
			for _, w in wings do
				-- folded straight down behind the back, sweeping out and up to full span
				local a = math.rad(-90 + (w.deg + 90) * open)
				local dir = Vector3.new(w.side * math.cos(a), math.sin(a), 0.3 * (1 - open))
				w.tip.WorldPosition = ctx.cf * (Vector3.new(w.side * 0.3, 4.2, 0.6) + dir * w.length * (0.4 + 0.6 * open))
				w.beam.Transparency = numbers({ { 0, fade }, { 1, 0.3 + 0.7 * fade } })
			end
			return age > 1.35
		end)
		ctx:puff(ctx:at(0, 3.5, 0), "DW_Slash", 6, {
			Color = gradient(c.Main, 0.5, 0),
			Size = numbers({ { 0, 3 }, { 1, 8 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.25, 0.35),
			Speed = NumberRange.new(0, 0),
			LightEmission = 1,
		})
	end)
end

-- Radiant Edge: a sword of pure light forms in your raised hand, slashes with a short trail at the
-- burst, then dissolves once the transformation is done
Signatures.RadiantEdge = function(ctx)
	local c = ctx.colors
	local hand = ctx.character:FindFirstChild("RightHand") or ctx.character:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local grip = CFrame.new(0, -hand.Size.Y / 2, 0)
	local blade = Instance.new("Part")
	blade.Name = "LightBlade"
	blade.Material = Enum.Material.Neon
	blade.Color = tone(c.Main, 0.6)
	blade.CanCollide, blade.CanQuery, blade.CanTouch, blade.Massless, blade.CastShadow = false, false, false, true, false
	blade.Size = Vector3.new(0.18, 0.05, 0.05)
	blade.Transparency = 1
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1 = hand, blade
	weld.Parent = blade
	blade.Parent = ctx.folder
	ctx:track(blade)
	local glow = ctx:emitter(blade, "RE_Shard", {
		Color = gradient(c.Main, 0.5, 0.2),
		Size = numbers({ { 0, 0.4 }, { 1, 0 } }),
		Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(-2, -1),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Rate = 30,
	})
	glow.Enabled = true
	local light = ctx:light(blade, c.Main, 10)
	local base = Instance.new("Attachment")
	base.Parent = blade
	local tipAtt = Instance.new("Attachment")
	tipAtt.Parent = blade
	ctx:track(base)
	ctx:track(tipAtt)
	local trail = Instance.new("Trail")
	trail.Texture = texture("RE_Edge")
	trail.Attachment0, trail.Attachment1 = base, tipAtt
	trail.Lifetime = 0.18
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = gradient(c.Main, 0.7, 0.2)
	trail.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
	trail.Enabled = false
	trail.Parent = blade
	ctx:track(trail)

	ctx:every(function(t)
		if not blade.Parent then
			return true
		end
		local form = easeOut(phase(t, 0.5, 2.4))
		local length = 0.1 + 5 * form
		blade.Size = Vector3.new(0.16 + 0.06 * form, length, 0.05)
		-- held point-up, then a slash: a fast arc from overhead forward and down across the burst
		local swing = easeInOut(phase(t, BURST - 0.2, BURST + 0.08))
		if ctx.performing then
			-- the body raises the sword and swings it: the blade simply extends out of the fist
			weld.C0 = grip * CFrame.new(0, -(length / 2 + 0.05), 0)
		else
			-- custom animations: angle the blade up and out so it reads clear of the arm, and sweep it
			-- diagonally across the body to finish forward and low, clear of the ground
			local pitch = math.rad(-18 - 92 * swing)
			local sweep = math.rad(55 * swing)
			local hold = hand.Name == "Right Arm" and grip or CFrame.new()
			weld.C0 = hold * CFrame.Angles(0, sweep, math.rad(-28)) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, length / 2 + 0.1, 0)
		end
		local out = ctx.performing and -1 or 1 -- which end of the blade points away from the hand
		base.Position = Vector3.new(0, -out * (length / 2 - 0.6), 0)
		tipAtt.Position = Vector3.new(0, out * length / 2, 0)
		trail.Enabled = swing > 0 and swing < 1
		local dissolve = phase(t, SETTLE + 0.1, SETTLE + 0.8)
		blade.Transparency = (form > 0 and 0.05 or 1) + 0.95 * dissolve
		glow.Speed = dissolve > 0 and NumberRange.new(2, 5) or NumberRange.new(-2, -1)
		glow.Rate = dissolve > 0 and 60 * (1 - dissolve) or 30
		light.Brightness = 2 * form * (1 - dissolve) + 6 * math.max(0, 1 - math.abs(t - BURST) / 0.2)
		if dissolve >= 1 then
			blade:Destroy()
			return true
		end
		return false
	end)
end

-- ---------------------------------------------------------------- public API

local nextId = 0

-- Plays the transformation on `character` (every client should call this). colors = the aura's
-- { Main, Accent, Glow }. options.onBurst() fires at the 3-second burst, options.onFinished() when
-- everything has faded. Returns a handle with :Cancel().
function Transform.play(character, auraName, colors, options)
	options = options or {}
	local root = character:FindFirstChild("HumanoidRootPart")
	assert(root, "EterniumTransform: character has no HumanoidRootPart")
	assert(Signatures[auraName], "EterniumTransform: unknown aura " .. tostring(auraName))
	local defaults = EterniumAuras.Defaults[auraName]
	colors = colors or {}
	nextId += 1

	local ground, groundColor, groundMaterial = groundAt(character, root)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local folder = Instance.new("Folder")
	folder.Name = "EterniumTransform"
	folder.Parent = workspace

	local ctx = setmetatable({
		id = nextId,
		name = auraName,
		character = character,
		root = root,
		cf = CFrame.lookAt(ground, ground + look),
		colors = { Main = colors.Main or defaults.Main, Accent = colors.Accent or defaults.Accent, Glow = colors.Glow or defaults.Glow },
		groundColor = groundColor,
		groundMaterial = groundMaterial == Enum.Material.Air and Enum.Material.Slate or groundMaterial,
		rng = Random.new(),
		folder = folder,
		instances = {},
		updaters = {},
		timers = {},
		t = 0,
	}, Ctx)
	ctx.isLocal = Players.LocalPlayer ~= nil and character == Players.LocalPlayer.Character

	cracks(ctx)
	rocks(ctx)
	charge(ctx)
	streams(ctx)
	burst(ctx)
	Signatures[auraName](ctx)
	sound(ctx, "Buildup", 0)
	sound(ctx, "Burst", BURST)
	local custom = Transform.Animations.Buildup ~= "" or Transform.Animations.Burst ~= "" or Transform.Animations.Stance ~= ""
	if not custom then
		perform(ctx)
	end
	if ctx.isLocal then
		cinematic(ctx)
		freeze(ctx)
		if custom then
			animations(ctx)
		end
	end
	if options.onBurst then
		ctx:when(BURST, options.onBurst)
	end

	local handle = {}
	local connection
	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if ctx.restore then
			ctx.restore()
			ctx.restore = nil
		end
		if ctx.restoreCamera then
			ctx.restoreCamera()
			ctx.restoreCamera = nil
		end
		if ctx.poseConnection then
			ctx.poseConnection:Disconnect()
			ctx.poseConnection = nil
			ctx.resetPose()
		end
		folder:Destroy()
		for _, inst in ctx.instances do
			inst:Destroy()
		end
		ctx.instances = {}
		if options.onFinished then
			options.onFinished()
		end
	end
	function handle:Cancel()
		if ctx.cameraName then
			RunService:UnbindFromRenderStep(ctx.cameraName)
		end
		finish()
	end

	local event = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
	connection = event:Connect(function(dt)
		ctx.t += dt
		local t = ctx.t
		for i = #ctx.timers, 1, -1 do
			local timer = ctx.timers[i]
			if t >= timer.time then
				table.remove(ctx.timers, i)
				timer.fn()
			end
		end
		local i = 1
		while i <= #ctx.updaters do
			if ctx.updaters[i](t, dt) then
				table.remove(ctx.updaters, i)
			else
				i += 1
			end
		end
		if t >= LIFETIME or not character.Parent then
			finish()
		end
	end)
	return handle
end

return Transform
