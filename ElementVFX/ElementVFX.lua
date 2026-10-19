-- ElementVFX (ModuleScript): Eternium's element beams, blasts and ultimates, v2.
--
-- Each effect is built from layers rather than one solid model:
--   * scrolling textured Beams that always face the camera (the energy streams),
--   * solid glowing toon meshes (spirals, flame tongues, lightning bolts, rings, cores) for real volume,
--   * flipbook ParticleEmitters with hand-drawn, toon-banded animation (fire puffs, sparks, explosions),
--   * lights.
-- Every colour comes from three recolourable picks: Main, Accent (hot core / highlights) and Glow (rims).
--
--   local VFX = require(ReplicatedStorage.Eternium.ElementVFX)
--   VFX.beam("Fire", originPart_or_Vector3, targetVector3, { duration = 2.2 })
--   VFX.blast("Electric", origin, target, { onHit = function(pos) end })
--   VFX.ultimate("Fire", character.HumanoidRootPart.CFrame * CFrame.new(0, -3, 0))
--
-- Run effects on every client (FireAllClients); they are purely visual. The old names work too:
-- VFX.fire = VFX.beam and VFX.play = VFX.ultimate.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VFX = {}

-- Upload the PNGs in ElementVFX/textures and paste their ids here ("rbxassetid://123...").
VFX.Textures = {
	F_Burst8 = "", F_Tongue4 = "", F_Smoke4 = "", F_Explode8 = "", F_Stream = "", F_Core = "", F_Ember = "", F_Ring = "",
	E_Bolt1 = "", E_Bolt2 = "", E_Bolt3 = "", E_Plasma = "", E_Spark4 = "", E_Arc8 = "", E_Orb4 = "", E_Cloud4 = "", E_Ring = "",
	X_Glow = "",
}
-- Built-in stand-ins so everything works before the uploads are in (flipbooks need the real sheets).
local FALLBACK = {
	F_Burst8 = "rbxasset://textures/particles/fire_main.dds",
	F_Tongue4 = "rbxasset://textures/particles/fire_main.dds",
	F_Smoke4 = "rbxasset://textures/particles/smoke_main.dds",
	F_Explode8 = "rbxasset://textures/particles/explosion01_core_main.dds",
	F_Ember = "rbxasset://textures/particles/sparkles_main.dds",
	E_Spark4 = "rbxasset://textures/particles/sparkles_main.dds",
	E_Arc8 = "rbxasset://textures/particles/sparkles_main.dds",
	E_Orb4 = "rbxasset://textures/particles/sparkles_main.dds",
	E_Cloud4 = "rbxasset://textures/particles/smoke_main.dds",
	X_Glow = "rbxasset://textures/particles/sparkles_main.dds",
}
local FLIPBOOK = { -- name -> grid size
	F_Burst8 = 8, F_Explode8 = 8, E_Arc8 = 8, F_Tongue4 = 4, F_Smoke4 = 4, E_Spark4 = 4, E_Orb4 = 4, E_Cloud4 = 4,
}

local function texture(name: string): string
	local id = VFX.Textures[name]
	if id and id ~= "" then
		return id
	end
	return FALLBACK[name] or ""
end
VFX.texture = texture

-- Where the imported VFX meshes live (one MeshPart per OBJ in ElementVFX/meshes, named as the file).
VFX.MeshFolder = nil :: Instance?
local function meshFolder(): Instance?
	if VFX.MeshFolder then
		return VFX.MeshFolder
	end
	local here = script.Parent and script.Parent:FindFirstChild("VFXMeshes")
	if here then
		VFX.MeshFolder = here
	end
	return here
end

-- Default colours per element; any of them can be overridden per call with options.colors.
VFX.Palettes = {
	Fire = {
		Main = Color3.fromRGB(255, 112, 18),
		Accent = Color3.fromRGB(255, 214, 92),
		Glow = Color3.fromRGB(214, 38, 12),
		Smoke = Color3.fromRGB(60, 44, 40),
	},
	Electric = {
		Main = Color3.fromRGB(168, 92, 255),
		Accent = Color3.fromRGB(240, 222, 255),
		Glow = Color3.fromRGB(104, 36, 224),
		Smoke = Color3.fromRGB(28, 22, 38),
	},
}

-- 1 = full effect, 0.5 = lighter (fewer particles, fewer arcs). Picked from the player's graphics level.
VFX.Quality = nil :: number?
local function quality(): number
	if VFX.Quality then
		return VFX.Quality
	end
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	if ok and typeof(level) == "number" and level > 0 and level <= 4 then
		return 0.5
	end
	return 1
end

-- ---------------------------------------------------------------- helpers

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function phase(t: number, a: number, b: number): number
	return clamp01((t - a) / (b - a))
end
local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end
local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end
local function colors(points: { { any } }): ColorSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(keys)
end
local function tone(c: Color3, k: number): Color3
	if k >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), k)
	end
	return c:Lerp(Color3.new(0, 0, 0), -k)
end

-- ---------------------------------------------------------------- the effect context

local Fx = {}
Fx.__index = Fx

local function newFx(element: string, options: any)
	options = options or {}
	local pal = VFX.Palettes[element]
	assert(pal, "ElementVFX: unknown element " .. tostring(element))
	local given = options.colors or {}
	if options.color then
		given = table.clone(given)
		given.Main = options.color
	end
	local folder = Instance.new("Folder")
	folder.Name = "ElementVFX_" .. element
	folder.Parent = Workspace
	local self = setmetatable({
		element = element,
		options = options,
		c = {
			Main = given.Main or pal.Main,
			Accent = given.Accent or pal.Accent,
			Glow = given.Glow or pal.Glow,
			Smoke = given.Smoke or pal.Smoke,
		},
		q = quality(),
		folder = folder,
		instances = {},
		updaters = {},
		timers = {},
		t = 0,
		rng = Random.new(),
		lifetime = 6,
	}, Fx)
	return self
end

function Fx:track(inst: Instance): any
	table.insert(self.instances, inst)
	return inst
end

-- an invisible anchored holder part (for attachments, emitters and lights)
function Fx:holder(cf: CFrame, size: Vector3?): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Parent = self.folder
	return self:track(p)
end

function Fx:attach(parent: Instance, position: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Parent = parent
	if position then
		a.WorldPosition = position
	end
	return self:track(a)
end

-- a camera-facing scrolling beam between two attachments
function Fx:beam(a0: Attachment, a1: Attachment, tex: string, props: { [string]: any }): Beam
	local b = Instance.new("Beam")
	b.Texture = texture(tex)
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.LightInfluence = 0
	b.LightEmission = 1
	b.TextureMode = Enum.TextureMode.Wrap
	b.Segments = 12
	for k, v in props do
		(b :: any)[k] = v
	end
	b.Parent = a0.Parent
	return self:track(b)
end

-- a particle emitter; flipbook sheets are set up automatically from the texture name
function Fx:emitter(parent: Instance, tex: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture(tex)
	e.LightInfluence = 0
	e.LightEmission = 1
	e.Rate = 0
	e.Enabled = true
	local gridSize = FLIPBOOK[tex]
	if gridSize and VFX.Textures[tex] ~= "" then
		pcall(function()
			(e :: any).FlipbookLayout = gridSize == 8 and Enum.ParticleFlipbookLayout.Grid8x8 or Enum.ParticleFlipbookLayout.Grid4x4
			;(e :: any).FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		end)
	end
	for k, v in props do
		if k == "Flipbook" then -- { mode = "Loop"/"OneShot"/"Random", fps = n }
			pcall(function()
				(e :: any).FlipbookMode = (Enum.ParticleFlipbookMode :: any)[v.mode or "OneShot"]
				;(e :: any).FlipbookFramerate = NumberRange.new(v.fps or 30)
				;(e :: any).FlipbookStartRandom = v.random or false
			end)
		elseif k == "Squash" or k == "Shape" or k == "ShapeInOut" or k == "ShapeStyle" then
			pcall(function()
				(e :: any)[k] = v
			end)
		elseif k == "Rate" then
			e.Rate = v * self.q
		else
			(e :: any)[k] = v
		end
	end
	e.Parent = parent
	return self:track(e)
end

function Fx:light(parent: Instance, color: Color3, range: number, brightness: number?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 0
	l.Shadows = false
	l.Parent = parent
	return self:track(l)
end

-- a solid glowing toon mesh cloned from the VFX mesh folder; scale multiplies its imported size
function Fx:mesh(name: string, color: Color3, cf: CFrame, scale: Vector3, transparency: number?): BasePart?
	local folder = meshFolder()
	local template = folder and folder:FindFirstChild(name)
	if not template then
		return nil
	end
	local m = (template :: BasePart):Clone()
	m.Anchored, m.CanCollide, m.CanQuery, m.CanTouch, m.CastShadow = true, false, false, false, false
	m.Material = Enum.Material.Neon
	m.Color = color
	m.Transparency = transparency or 0
	m:SetAttribute("BaseSize", (template :: BasePart).Size)
	m.Size = (template :: BasePart).Size * scale
	m.CFrame = cf
	m.Parent = self.folder
	return self:track(m)
end

-- resize a cloned mesh relative to its imported size
local function rescale(m: BasePart?, scale: Vector3)
	if m then
		local base = m:GetAttribute("BaseSize") :: Vector3
		m.Size = base * Vector3.new(math.max(scale.X, 1e-3), math.max(scale.Y, 1e-3), math.max(scale.Z, 1e-3))
	end
end

-- run fn(t, dt) every frame until it returns true
function Fx:every(fn: (number, number) -> boolean?)
	table.insert(self.updaters, fn)
end

function Fx:when(time: number, fn: () -> ())
	table.insert(self.timers, { time = time, fn = fn })
end

-- a one-off burst of particles at a point
function Fx:puff(position: Vector3, tex: string, count: number, props: { [string]: any }): ParticleEmitter
	local h = self:holder(CFrame.new(position))
	local e = self:emitter(h, tex, props)
	e:Emit(math.max(1, math.floor(count * self.q + 0.5)))
	return e
end

-- a glowing mesh that flashes outward and fades (rings, starbursts)
function Fx:pulse(name: string, color: Color3, cf: CFrame, from: Vector3, to: Vector3, life: number)
	local m = self:mesh(name, color, cf, from, 0)
	if not m then
		return
	end
	local born = self.t
	self:every(function(t)
		local k = phase(t - born, 0, life)
		rescale(m, from:Lerp(to, easeOut(k)))
		m.Transparency = 0.1 + 0.9 * k ^ 1.5
		if k >= 1 then
			m:Destroy()
			return true
		end
		return false
	end)
end

function Fx:run(onFinished: (() -> ())?)
	local handle = {}
	local connection: RBXScriptConnection? = nil
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		self.folder:Destroy()
		for _, inst in self.instances do
			inst:Destroy()
		end
		table.clear(self.instances)
		if onFinished then
			onFinished()
		end
	end
	function handle:Stop()
		self._stop = true
	end
	function handle:Destroy()
		finish()
	end
	self.handle = handle
	local event = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
	connection = event:Connect(function(dt: number)
		self.t += dt
		local t = self.t
		for i = #self.timers, 1, -1 do
			local timer = self.timers[i]
			if t >= timer.time then
				table.remove(self.timers, i)
				timer.fn()
			end
		end
		local i = 1
		while i <= #self.updaters do
			if self.updaters[i](t, dt) then
				table.remove(self.updaters, i)
			else
				i += 1
			end
		end
		if t >= self.lifetime then
			finish()
		end
	end)
	return handle
end

local function positionOf(x: any): Vector3
	if typeof(x) == "Vector3" then
		return x
	elseif typeof(x) == "CFrame" then
		return x.Position
	elseif typeof(x) == "Instance" then
		if x:IsA("Attachment") then
			return x.WorldPosition
		end
		return (x :: BasePart).Position
	end
	error("ElementVFX: expected a Vector3, CFrame, Attachment or BasePart")
end

-- a "stream" between origin and target: holders at both ends whose positions update every frame
-- (so the beam follows a moving caster), plus helpers for points along it
local function stream(fx, origin: any, target: Vector3)
	local s = {}
	s.from = positionOf(origin)
	s.to = target
	s.front = 0 -- 0..1: how far the beam has reached
	s.startPart = fx:holder(CFrame.new(s.from))
	s.endPart = fx:holder(CFrame.new(s.to))
	s.spine = fx:holder(CFrame.new(s.from), Vector3.new(1, 1, 1)) -- spans the beam (for volume emitters)
	function s:update(front: number)
		self.from = positionOf(origin)
		self.front = front
		local dir = self.to - self.from
		local len = math.max(dir.Magnitude, 0.01)
		local tip = self.from + dir * front
		local look = CFrame.lookAt(self.from, self.to)
		self.startPart.CFrame = look
		self.endPart.CFrame = look.Rotation + tip
		self.spine.CFrame = look * CFrame.new(0, 0, -len * front / 2)
		self.spine.Size = Vector3.new(1.2, 1.2, math.max(len * front, 0.05))
		self.cf = look
		self.len = len
		self.tip = tip
	end
	function s:at(u: number, side: number?, up: number?): Vector3
		local cf = self.cf * CFrame.new((side or 0), (up or 0), -self.len * self.front * u)
		return cf.Position
	end
	s:update(0)
	return s
end

-- ====================================================================== FIRE

local Fire = {}

-- A roaring stream of flame: a white-hot core, three counter-flowing flame bodies, two spiralling
-- flame ribbons, fire puffs billowing all along it and an explosion of fire where it hits.
function Fire.beam(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local D = o.duration or 2.2
	local W = o.width or 1
	fx.lifetime = D + 1.6
	local s = stream(fx, origin, target)
	local a0 = fx:attach(s.startPart)
	local a1 = fx:attach(s.endPart)
	-- layered for colour, not just brightness: only the thin core is fully additive; the flame bodies
	-- are mostly alpha-blended so their toon bands keep the orange-to-red colour
	local core = {
		fx:beam(a0, a1, "F_Core", { Color = ColorSequence.new(c.Accent), TextureSpeed = 3.5, TextureLength = 6, ZOffset = 0.3, Transparency = NumberSequence.new(0.15) }),
	}
	local bodies = {}
	local bodyColors = {
		colors({ { 0, c.Accent }, { 0.12, c.Main }, { 1, c.Main } }),
		colors({ { 0, c.Main }, { 1, c.Glow } }),
		colors({ { 0, c.Glow }, { 1, tone(c.Glow, -0.35) } }),
	}
	for i, spec in { { 2.2, 7, 0.15, 0.05 }, { 3.1, 9, 0.05, 0.12 }, { 4.0, 12, 0.0, 0.25 } } do
		table.insert(bodies, fx:beam(a0, a1, "F_Stream", {
			Color = bodyColors[i],
			Transparency = numbers({ { 0, spec[4] }, { 0.85, spec[4] + 0.1 }, { 1, 0.7 } }),
			TextureSpeed = spec[1], TextureLength = spec[2], ZOffset = 0.25 - 0.08 * i,
			LightEmission = spec[3],
		}))
	end
	local spiral = fx:mesh("Spiral", c.Glow, s.cf, Vector3.new(1, 1, 1), 0.25)
	local spiral2 = fx:mesh("SpiralThin", c.Main, s.cf, Vector3.new(1, 1, 1), 0.3)
	-- volume: fire puffs and embers all along the beam
	local puffs = fx:emitter(s.spine, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.25, c.Main }, { 0.7, c.Glow }, { 1, tone(c.Glow, -0.3) } }), LightEmission = 0.15,
		Size = numbers({ { 0, 2.2 * W }, { 0.4, 4.6 * W }, { 1, 5.4 * W } }),
		Transparency = numbers({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.45, 0.65), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(-25, 25), RotSpeed = NumberRange.new(-30, 30),
		Flipbook = { mode = "OneShot", fps = 110 }, Rate = 55,
	})
	local embers = fx:emitter(s.spine, "F_Ember", {
		Color = ColorSequence.new(c.Accent, c.Main),
		Size = numbers({ { 0, 0.35 }, { 1, 0 } }), Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		Acceleration = Vector3.new(0, 8, 0), Rate = 40,
	})
	-- muzzle: a flame cone erupting from the hands
	local muzzle = fx:mesh("FlameCone", c.Main, s.cf, Vector3.new(1, 1, 1), 0.25)
	local muzzleInner = fx:mesh("FlameCone", c.Accent, s.cf, Vector3.new(1, 1, 1), 0.2)
	local mpuff = fx:emitter(s.startPart, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.4, c.Main }, { 1, c.Glow } }),
		Size = numbers({ { 0, 2 * W }, { 1, 4.5 * W } }), Transparency = numbers({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Front, Flipbook = { mode = "OneShot", fps = 150 }, Rate = 30,
	})
	-- impact
	local hitLight = fx:light(s.endPart, c.Main, 22)
	local hitFire = fx:emitter(s.endPart, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.3, c.Main }, { 1, c.Glow } }),
		Size = numbers({ { 0, 3 * W }, { 0.5, 6 * W }, { 1, 7 * W } }), Transparency = numbers({ { 0, 0 }, { 0.8, 0.15 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 10, 0), Flipbook = { mode = "OneShot", fps = 90 }, Rate = 0,
	})
	local hitSmoke = fx:emitter(s.endPart, "F_Smoke4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6,
		Size = numbers({ { 0, 4 * W }, { 1, 9 * W } }), Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.0, 1.6), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 6, 0), Flipbook = { mode = "OneShot", fps = 12 }, Rate = 0,
	})
	local beamLight = fx:light(s.spine, c.Main, 16)
	local nextBoom, nextRing = 0, 0
	local hit = false
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.18))
		local fade = 1 - phase(t, D, D + 0.32)
		s:update(grow)
		local len = s.len * grow
		local mid = s.cf * CFrame.new(0, 0, -len / 2)
		for _, b in core do
			b.Width0, b.Width1 = 0.45 * W * fade, 0.6 * W * fade
		end
		for i, b in bodies do
			local wob = math.sin(t * (9 + i * 3) + i) * (0.4 + 0.3 * i)
			b.Width0 = (1.4 + 0.7 * i) * W * fade
			b.Width1 = (2.2 + 1.3 * i + wob) * W * fade
			b.CurveSize0 = math.sin(t * 7 + i * 2) * 0.6
			b.CurveSize1 = math.cos(t * 6 + i) * 0.8
		end
		if spiral then
			spiral.CFrame = mid * CFrame.Angles(0, 0, t * 9)
			rescale(spiral, Vector3.new(3.3 * W * fade, 3.3 * W * fade, len))
		end
		if spiral2 then
			spiral2.CFrame = mid * CFrame.Angles(0, 0, -t * 13)
			rescale(spiral2, Vector3.new(2.3 * W * fade, 2.3 * W * fade, len))
		end
		local ml = 3.2 * W * fade * (1 + 0.08 * math.sin(t * 30))
		if muzzle then
			muzzle.CFrame = s.cf * CFrame.new(0, 0, -ml * 0.5) * CFrame.Angles(0, 0, t * 6)
			rescale(muzzle, Vector3.new(2.8 * W * fade, 2.8 * W * fade, ml))
		end
		if muzzleInner then
			muzzleInner.CFrame = s.cf * CFrame.new(0, 0, -ml * 0.35) * CFrame.Angles(0, 0, -t * 9)
			rescale(muzzleInner, Vector3.new(1.6 * W * fade, 1.6 * W * fade, ml * 0.7))
		end
		local on = t < D
		puffs.Enabled, embers.Enabled, mpuff.Enabled = on, on, on
		beamLight.Brightness = 3 * fade
		-- the impact: rolling explosions and shockwaves while the beam is on target
		if grow >= 1 and on then
			if not hit then
				hit = true
				fx:puff(s.tip, "F_Explode8", 1, {
					Color = colors({ { 0, c.Accent }, { 0.4, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(10 * W, 10 * W),
					Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
				})
			end
			hitFire.Rate = 26 * fx.q
			hitSmoke.Rate = 6 * fx.q
			hitLight.Brightness = 4 + 1.5 * math.sin(t * 25)
			if t >= nextBoom then
				nextBoom = t + 0.22
				fx:puff(s.tip + Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-0.5, 1), fx.rng:NextNumber(-1, 1)) * 1.5 * W, "F_Explode8", 1, {
					Color = colors({ { 0, c.Accent }, { 0.4, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(6 * W, 8 * W),
					Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360),
					Flipbook = { mode = "OneShot", fps = 160 },
				})
			end
			if t >= nextRing then
				nextRing = t + 0.35
				fx:pulse("RingJag", c.Main, CFrame.new(s.tip) * (s.cf.Rotation * CFrame.Angles(math.pi / 2, 0, 0)), Vector3.new(1, 1, 1) * W, Vector3.new(12, 1, 12) * W, 0.45)
			end
		else
			hitFire.Rate, hitSmoke.Rate = 0, 0
			hitLight.Brightness = hitLight.Brightness * 0.85
		end
		return t > D + 0.4
	end)
end

-- A fireball: a white-hot core in a churning shell, flame tongues streaming back off it, a comet tail
-- of fire and embers; it bursts into an explosion with a shockwave and a spray of flame.
function Fire.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local speed = o.speed or 70
	local from = positionOf(origin)
	local dist = (target - from).Magnitude
	local travel = math.max(dist / speed, 0.05)
	fx.lifetime = travel + 2.2
	local look = CFrame.lookAt(from, target)
	local ball = fx:holder(look)
	local tailA = fx:attach(ball)
	local tailEnd = fx:holder(look)
	local tailB = fx:attach(tailEnd)
	local core = fx:mesh("Orb", c.Accent, look, Vector3.new(1.5, 1.5, 1.5) * W, 0)
	local shell = fx:mesh("Orb", c.Main, look, Vector3.new(2.5, 2.5, 2.5) * W, 0.35)
	local tongues = {}
	for k = 1, 6 do
		local m = fx:mesh("Tongue" .. ((k - 1) % 3 + 1), k % 2 == 0 and c.Main or c.Glow, look, Vector3.new(1, 1, 1), 0.15)
		table.insert(tongues, m)
	end
	local tails = {
		fx:beam(tailA, tailB, "F_Stream", { Color = colors({ { 0, c.Accent }, { 0.3, c.Main }, { 1, c.Glow } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }), TextureSpeed = -3, TextureLength = 5 }),
		fx:beam(tailA, tailB, "F_Core", { Color = ColorSequence.new(c.Accent), Transparency = numbers({ { 0, 0 }, { 1, 1 } }), TextureSpeed = -4, TextureLength = 4, ZOffset = 0.2 }),
	}
	local trail = fx:emitter(ball, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.35, c.Main }, { 1, c.Glow } }),
		Size = numbers({ { 0, 2.2 * W }, { 1, 3.4 * W } }), Transparency = numbers({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
		Flipbook = { mode = "OneShot", fps = 150 }, Rate = 70,
	})
	local embers = fx:emitter(ball, "F_Ember", {
		Color = ColorSequence.new(c.Accent, c.Main), Size = numbers({ { 0, 0.3 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Drag = 2, Rate = 50,
	})
	local smoke = fx:emitter(ball, "F_Smoke4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6,
		Size = numbers({ { 0, 1.8 * W }, { 1, 4 * W } }), Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 4, 0), Flipbook = { mode = "OneShot", fps = 18 }, Rate = 14,
	})
	local light = fx:light(ball, c.Main, 16, 3)
	local exploded = false
	fx:every(function(t)
		local k = phase(t, 0, travel)
		local pos = from:Lerp(target, k)
		if not exploded then
			local grow = easeOut(phase(t, 0, 0.1))
			ball.CFrame = look.Rotation + pos
			tailEnd.CFrame = look.Rotation + from:Lerp(pos, math.max(0, 1 - 7 * W / math.max((pos - from).Magnitude, 0.01)))
			local pulse = 1 + 0.08 * math.sin(t * 40)
			if core then
				core.CFrame = ball.CFrame * CFrame.Angles(t * 7, t * 5, 0)
				rescale(core, Vector3.new(1.5, 1.5, 1.5) * W * grow * pulse)
			end
			if shell then
				shell.CFrame = ball.CFrame * CFrame.Angles(-t * 5, t * 9, 0)
				rescale(shell, Vector3.new(2.6, 2.6, 2.6) * W * grow * (2 - pulse))
			end
			for i, m in tongues do
				if m then
					-- tongues licking backwards off the ball, spinning round its flight axis
					local a = i / #tongues * math.pi * 2 + t * 6
					m.CFrame = ball.CFrame * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.6 * W, 0.4 * W) * CFrame.Angles(math.rad(70 + 15 * math.sin(t * 20 + i)), 0, 0)
					local flick = 1 + 0.25 * math.sin(t * 30 + i * 2)
					rescale(m, Vector3.new(1.4, 3.2 * flick, 1.4) * W * grow)
				end
			end
			for i, b in tails do
				b.Width0 = (i == 1 and 2.4 or 1.2) * W * grow
				b.Width1 = 0.2 * W
			end
			if k >= 1 then
				exploded = true
				trail.Enabled, embers.Enabled, smoke.Enabled = false, false, false
				for _, m in { core, shell } do
					if m then
						m:Destroy()
					end
				end
				for _, m in tongues do
					if m then
						m:Destroy()
					end
				end
				for _, b in tails do
					b.Enabled = false
				end
				Fire.explode(fx, target, W)
				if o.onHit then
					task.spawn(o.onHit, target)
				end
			end
		else
			light.Brightness = light.Brightness * 0.9
		end
		return exploded and t > travel + 1.2
	end)
end

function Fire.explode(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "F_Explode8", 1, {
		Color = colors({ { 0, c.Accent }, { 0.35, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(13 * W, 13 * W),
		Lifetime = NumberRange.new(0.55, 0.55), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "F_Explode8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(8 * W, 8 * W), Rotation = NumberRange.new(0, 360),
		Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
	})
	fx:puff(at, "F_Burst8", 22, {
		Color = colors({ { 0, c.Accent }, { 0.3, c.Main }, { 1, c.Glow } }),
		Size = numbers({ { 0, 2.5 * W }, { 1, 5 * W } }), Transparency = numbers({ { 0, 0 }, { 0.8, 0.15 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Drag = 4,
		Acceleration = Vector3.new(0, 6, 0), Flipbook = { mode = "OneShot", fps = 100 },
	})
	fx:puff(at, "F_Smoke4", 10, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6,
		Size = numbers({ { 0, 4 * W }, { 1, 9 * W } }), Transparency = numbers({ { 0, 0.25 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.0, 1.6), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Acceleration = Vector3.new(0, 5, 0), Flipbook = { mode = "OneShot", fps = 11 },
	})
	fx:puff(at, "F_Ember", 45, {
		Color = ColorSequence.new(c.Accent, c.Main), Size = numbers({ { 0, 0.4 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		Acceleration = Vector3.new(0, -12, 0),
	})
	fx:pulse("RingJag", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(18, 1, 18) * W, 0.55)
	fx:pulse("Spikes", c.Accent, CFrame.new(at) * CFrame.Angles(fx.rng:NextNumber(0, 6), fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(9, 9, 9) * W, 0.25)
	local h = fx:holder(CFrame.new(at))
	local l = fx:light(h, c.Main, 30, 8)
	local born = fx.t
	fx:every(function(t)
		l.Brightness = 8 * (1 - phase(t - born, 0, 0.6))
		return t - born > 0.6
	end)
end

-- Ultimate: flames erupt from the hands. The ground ignites round the user, fire gathers in the
-- hands, then a colossal cone of fire roars forward, setting the ground alight as it passes.
function Fire.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	local reach = (o.reach or 30) * S
	fx.lifetime = 7
	local hands = at * CFrame.new(0, 3.3 * S, -1.6 * S)
	local aim = hands * CFrame.Angles(math.rad(-4), 0, 0) -- aimed slightly down the ground
	-- wind-up: a ring of flame tongues bursts from the ground round the user
	local ringTongues = {}
	for k = 1, 10 do
		local a = k / 10 * math.pi * 2
		local p = at * CFrame.new(math.cos(a) * 4 * S, 0, math.sin(a) * 4 * S)
		local m = fx:mesh("Tongue" .. ((k - 1) % 3 + 1), k % 2 == 0 and c.Main or c.Glow, p, Vector3.new(0.01, 0.01, 0.01), 0.15)
		table.insert(ringTongues, { m = m, cf = p * CFrame.Angles(0, -a, 0), delay = k * 0.03 })
	end
	local gather = fx:holder(hands)
	local gatherFire = fx:emitter(gather, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.4, c.Main }, { 1, c.Glow } }),
		Size = numbers({ { 0, 0.8 * S }, { 1, 2.4 * S } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.25, 0.35), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
		Flipbook = { mode = "OneShot", fps = 180 }, Rate = 40,
	})
	local gatherCore = fx:mesh("Orb", c.Accent, hands, Vector3.new(0.01, 0.01, 0.01), 0)
	local handLight = fx:light(gather, c.Main, 18, 0)
	-- the torrent
	local mouth = fx:holder(aim)
	local torrent = fx:emitter(mouth, "F_Burst8", {
		Color = colors({ { 0, c.Accent }, { 0.25, c.Main }, { 0.8, c.Glow }, { 1, tone(c.Glow, -0.4) } }),
		Size = numbers({ { 0, 2.5 * S }, { 0.5, 9 * S }, { 1, 13 * S } }), Transparency = numbers({ { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 0.8), Speed = NumberRange.new(42 * S, 52 * S), SpreadAngle = Vector2.new(14, 14),
		EmissionDirection = Enum.NormalId.Front, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		Flipbook = { mode = "OneShot", fps = 85 }, Rate = 0,
	})
	local torrentSmoke = fx:emitter(mouth, "F_Smoke4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6,
		Size = numbers({ { 0, 5 * S }, { 1, 14 * S } }), Transparency = numbers({ { 0, 0.45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.0, 1.4), Speed = NumberRange.new(26 * S, 34 * S), SpreadAngle = Vector2.new(18, 18),
		EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, 12, 0), Flipbook = { mode = "OneShot", fps = 12 }, Rate = 0,
	})
	local torrentEmbers = fx:emitter(mouth, "F_Ember", {
		Color = ColorSequence.new(c.Accent, c.Main), Size = numbers({ { 0, 0.5 * S }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(40 * S, 60 * S), SpreadAngle = Vector2.new(22, 22),
		EmissionDirection = Enum.NormalId.Front, Rate = 0,
	})
	local cone = fx:mesh("FlameCone", c.Main, aim, Vector3.new(0.01, 0.01, 0.01), 0.35)
	local coneInner = fx:mesh("FlameCone", c.Accent, aim, Vector3.new(0.01, 0.01, 0.01), 0.3)
	local streams = {}
	local mouthA = fx:attach(mouth)
	for k = 1, 4 do
		local endP = fx:holder(aim)
		local b = fx:beam(mouthA, fx:attach(endP), "F_Stream", {
			Color = colors({ { 0, c.Accent }, { 0.3, c.Main }, { 1, c.Glow } }),
			Transparency = numbers({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), TextureSpeed = 4 + k, TextureLength = 10,
		})
		table.insert(streams, { b = b, endP = endP, a = k / 4 * math.pi * 2 })
	end
	local light = fx:light(mouth, c.Main, 40, 0)
	local ground = {}
	local T0, T1 = 0.7, 3.4
	local nextGround = T0 + 0.2
	fx:every(function(t)
		-- ring of tongues
		for _, r in ringTongues do
			if r.m then
				local k = easeOut(phase(t, r.delay, r.delay + 0.25)) * (1 - phase(t, T1, T1 + 0.6))
				local flick = 1 + 0.2 * math.sin(t * 25 + r.delay * 50)
				r.m.CFrame = r.cf * CFrame.new(0, 1.2 * S * k * flick, 0)
				rescale(r.m, Vector3.new(1.4, 2.6 * flick, 1.4) * S * math.max(k, 0.001))
			end
		end
		-- gathering in the hands
		local g = phase(t, 0.1, T0)
		gatherFire.Enabled = t < T0
		if gatherCore then
			local s2 = (0.3 + 1.2 * g) * S * (1 - phase(t, T0, T0 + 0.15))
			gatherCore.CFrame = hands * CFrame.Angles(t * 5, t * 7, 0)
			rescale(gatherCore, Vector3.new(s2, s2, s2))
		end
		handLight.Brightness = 3 * g * (1 - phase(t, T0, T0 + 0.2))
		-- the torrent
		local on = t >= T0 and t < T1
		local burst = easeOut(phase(t, T0, T0 + 0.25)) * (1 - phase(t, T1, T1 + 0.5))
		torrent.Rate = on and 85 * fx.q or 0
		torrentSmoke.Rate = on and 10 * fx.q or 0
		torrentEmbers.Rate = on and 60 * fx.q or 0
		light.Brightness = 6 * burst
		local L = reach * burst
		if cone then
			cone.CFrame = aim * CFrame.new(0, 0, -L * 0.5) * CFrame.Angles(0, 0, t * 4)
			local w = 11 * S * burst * (1 + 0.05 * math.sin(t * 22))
			rescale(cone, Vector3.new(w, w, math.max(L, 0.01)))
		end
		if coneInner then
			coneInner.CFrame = aim * CFrame.new(0, 0, -L * 0.36) * CFrame.Angles(0, 0, -t * 6)
			local w = 6 * S * burst
			rescale(coneInner, Vector3.new(w, w, math.max(L * 0.72, 0.01)))
		end
		for _, st in streams do
			local a = st.a + t * 1.5
			st.endP.CFrame = aim * CFrame.new(math.cos(a) * 4.5 * S * burst, math.sin(a) * 4.5 * S * burst, -math.max(L, 0.01))
			st.b.Width0 = 1.5 * S * burst
			st.b.Width1 = 7 * S * burst
		end
		-- the ground catches fire along the path
		if on and t >= nextGround then
			nextGround = t + 0.12 / fx.q
			local d = fx.rng:NextNumber(4, reach * burst)
			local side = fx.rng:NextNumber(-1, 1) * d * 0.22
			local p = (at * CFrame.new(side, 0, -d)).Position
			local h = fx:holder(CFrame.new(p))
			local e = fx:emitter(h, "F_Tongue4", {
				Color = colors({ { 0, c.Accent }, { 0.4, c.Main }, { 1, c.Glow } }), Size = numbers({ { 0, 1.5 * S }, { 0.4, 3.2 * S }, { 1, 2 * S } }),
				Transparency = numbers({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10),
				Flipbook = { mode = "Loop", fps = 24 }, Rate = 8,
			})
			local m = fx:mesh("Tongue" .. fx.rng:NextInteger(1, 3), c.Main, CFrame.new(p) * CFrame.Angles(0, fx.rng:NextNumber(0, 6.28), 0), Vector3.new(0.01, 0.01, 0.01), 0.2)
			table.insert(ground, { e = e, m = m, born = t, p = p })
		end
		for _, gfire in ground do
			local age = t - gfire.born
			local k = easeOut(phase(age, 0, 0.2)) * (1 - phase(t, 4.6, 5.6))
			gfire.e.Enabled = t < 4.8
			if gfire.m then
				local flick = 1 + 0.25 * math.sin(t * 22 + gfire.born * 30)
				gfire.m.CFrame = CFrame.new(gfire.p) * CFrame.new(0, 1.0 * S * k * flick, 0)
				rescale(gfire.m, Vector3.new(1.1, 2.2 * flick, 1.1) * S * math.max(k, 0.001))
			end
		end
		return t > 5.7
	end)
end

-- ====================================================================== ELECTRIC

local Electric = {}

local BOLTS = { "E_Bolt1", "E_Bolt2", "E_Bolt3" }

-- a short-lived lightning arc between two points (a jittering bolt beam)
function Fx:arc(a: Vector3, b: Vector3, width: number, color: ColorSequence, life: number)
	local h0, h1 = self:holder(CFrame.new(a)), self:holder(CFrame.new(b))
	local beam = self:beam(self:attach(h0), self:attach(h1), BOLTS[self.rng:NextInteger(1, 3)], {
		Color = color, Width0 = width, Width1 = width * 0.6, TextureSpeed = 0, TextureLength = math.max((b - a).Magnitude, 1),
		CurveSize0 = self.rng:NextNumber(-2, 2), CurveSize1 = self.rng:NextNumber(-2, 2),
	})
	local born = self.t
	self:every(function(t)
		local age = t - born
		beam.Transparency = NumberSequence.new(phase(age, life * 0.4, life))
		if age >= life then
			h0:Destroy()
			h1:Destroy()
			return true
		end
		return false
	end)
end

-- A lightning beam: a crackling plasma core inside four jittering bolts that re-strike every few
-- frames, electric rings racing along it, arcs leaping off its sides, and a storm of sparks and
-- ground strikes where it hits.
function Electric.beam(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local D = o.duration or 2.2
	local W = o.width or 1
	fx.lifetime = D + 1.2
	local s = stream(fx, origin, target)
	local a0 = fx:attach(s.startPart)
	local a1 = fx:attach(s.endPart)
	local cores = {
		fx:beam(a0, a1, "E_Plasma", { Color = ColorSequence.new(c.Accent), TextureSpeed = 5, TextureLength = 8, ZOffset = 0.3 }),
		fx:beam(a0, a1, "E_Plasma", { Color = colors({ { 0, c.Main }, { 1, c.Glow } }), TextureSpeed = -3, TextureLength = 12, ZOffset = 0.1, Transparency = NumberSequence.new(0.25) }),
	}
	local bolts = {}
	for i = 1, 4 do
		table.insert(bolts, fx:beam(a0, a1, BOLTS[(i - 1) % 3 + 1], {
			Color = i <= 2 and ColorSequence.new(c.Accent) or colors({ { 0, c.Accent }, { 1, c.Main } }),
			TextureSpeed = 0, TextureLength = 8, ZOffset = 0.2,
		}))
	end
	local rings = {}
	for i = 1, 5 do
		local m = fx:mesh("ZapRing", i % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(1, 1, 1), 0.1)
		table.insert(rings, { m = m, u = (i - 1) / 5, spin = fx.rng:NextNumber(-12, 12) })
	end
	local sparks = fx:emitter(s.spine, "E_Spark4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(1.6 * W, 3.2 * W),
		Lifetime = NumberRange.new(0.08, 0.14), Speed = NumberRange.new(0, 1), Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "Random", fps = 30 }, Rate = 45,
	})
	local muzzle = fx:emitter(s.startPart, "E_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(3.2 * W, 3.8 * W),
		Lifetime = NumberRange.new(0.1, 0.1), Speed = NumberRange.new(0, 0), LockedToPart = true, Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "Loop", fps = 30 }, Rate = 30,
	})
	local muzzleSpark = fx:emitter(s.startPart, "E_Spark4", {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(2.4 * W, 3.6 * W), Lifetime = NumberRange.new(0.06, 0.1),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "Random", fps = 30 }, Rate = 20,
	})
	local hitLight = fx:light(s.endPart, c.Main, 24)
	local beamLight = fx:light(s.spine, c.Main, 16)
	local hit = false
	local nextJitter, nextArc, nextStrike, nextBurst = 0, 0, 0, 0
	fx:every(function(t, dt)
		local grow = easeOut(phase(t, 0, 0.1))
		local fade = 1 - phase(t, D, D + 0.2)
		s:update(grow)
		local len = s.len * grow
		local flicker = (math.floor(t * 40) % 3 == 0) and 0.55 or 1
		for i, b in cores do
			b.Width0 = (i == 1 and 0.9 or 1.8) * W * fade * flicker
			b.Width1 = (i == 1 and 1.0 or 2.0) * W * fade * flicker
		end
		if t >= nextJitter then
			-- the bolts re-strike: new shapes, new curves, new widths
			nextJitter = t + 0.05
			for i, b in bolts do
				b.Texture = texture(BOLTS[fx.rng:NextInteger(1, 3)])
				b.CurveSize0 = fx.rng:NextNumber(-1, 1) * 2.5 * W
				b.CurveSize1 = fx.rng:NextNumber(-1, 1) * 2.5 * W
				b.TextureLength = fx.rng:NextNumber(6, 10) * W
				local w = (i <= 2 and 2.2 or 3.0) * W * fade
				b.Width0, b.Width1 = w * fx.rng:NextNumber(0.7, 1.1), w * fx.rng:NextNumber(0.8, 1.3)
			end
		end
		for _, r in rings do
			if r.m then
				r.u = (r.u + dt * 1.3) % 1 -- race along the beam
				local p = s.cf * CFrame.new(0, 0, -len * r.u)
				r.m.CFrame = p * CFrame.Angles(0, 0, t * r.spin)
				local sz = (2.4 + 0.6 * math.sin(t * 30 + r.u * 10)) * W * fade
				rescale(r.m, Vector3.new(sz, sz, 1))
				r.m.Transparency = (math.floor(t * 30 + r.u * 7) % 4 == 0) and 0.8 or 0.1
			end
		end
		-- arcs leaping off the beam
		if t < D and t >= nextArc then
			nextArc = t + fx.rng:NextNumber(0.04, 0.09) / fx.q
			local u = fx.rng:NextNumber(0.05, 0.95)
			local pa = s:at(u)
			local out = (s.cf * CFrame.Angles(0, 0, fx.rng:NextNumber(0, 6.28))).UpVector
			fx:arc(pa, pa + out * fx.rng:NextNumber(2, 5) * W + s.cf.LookVector * fx.rng:NextNumber(-2, 2), 1.2 * W, colors({ { 0, c.Accent }, { 1, c.Main } }), 0.09)
		end
		local on = t < D
		sparks.Enabled, muzzle.Enabled, muzzleSpark.Enabled = on, on, on
		beamLight.Brightness = (3 + 2 * flicker) * fade
		if grow >= 1 and on then
			hitLight.Brightness = 3 + 4 * flicker
			if not hit or t >= nextBurst then
				hit = true
				nextBurst = t + 0.16
				fx:puff(s.tip, "E_Arc8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(7 * W, 10 * W), Rotation = NumberRange.new(0, 360),
					Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 210 },
				})
			end
			if t >= nextStrike then
				-- crackling strikes into the ground round the impact
				nextStrike = t + 0.09 / fx.q
				local a = fx.rng:NextNumber(0, 6.28)
				local r = fx.rng:NextNumber(1.5, 5) * W
				local foot = s.tip + Vector3.new(math.cos(a) * r, -1.5 * W, math.sin(a) * r)
				fx:arc(s.tip, foot, 1.4 * W, ColorSequence.new(c.Accent), 0.08)
				fx:pulse("RingJag", c.Main, CFrame.new(foot), Vector3.new(0.5, 1, 0.5) * W, Vector3.new(3, 1, 3) * W, 0.2)
			end
		else
			hitLight.Brightness = hitLight.Brightness * 0.8
		end
		return t > D + 0.3
	end)
end

-- Ball lightning: a white core in a crackling plasma sphere that throws arcs in every direction and
-- trails sparks; it bursts into a shock of radiating bolts and an electric ring.
function Electric.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local speed = o.speed or 85
	local from = positionOf(origin)
	local dist = (target - from).Magnitude
	local travel = math.max(dist / speed, 0.05)
	fx.lifetime = travel + 1.6
	local look = CFrame.lookAt(from, target)
	local ball = fx:holder(look)
	local core = fx:mesh("Orb", c.Accent, look, Vector3.new(1, 1, 1) * W, 0)
	local orb = fx:emitter(ball, "E_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(3.4 * W, 3.8 * W), LockedToPart = true,
		Lifetime = NumberRange.new(0.08, 0.08), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "Loop", fps = 30 }, Rate = 40,
	})
	local trail = fx:emitter(ball, "E_Spark4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(1.4 * W, 2.4 * W),
		Lifetime = NumberRange.new(0.1, 0.2), Speed = NumberRange.new(0, 1), Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "Random", fps = 30 }, Rate = 60,
	})
	local tA = fx:attach(ball, nil)
	local tB = fx:attach(ball, nil)
	tA.Position, tB.Position = Vector3.new(0, 0.6 * W, 0), Vector3.new(0, -0.6 * W, 0)
	local ribbon = Instance.new("Trail")
	ribbon.Attachment0, ribbon.Attachment1 = tA, tB
	ribbon.Texture = texture("E_Plasma")
	ribbon.Color = colors({ { 0, c.Accent }, { 1, c.Main } })
	ribbon.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
	ribbon.Lifetime = 0.18
	ribbon.LightEmission = 1
	ribbon.LightInfluence = 0
	ribbon.FaceCamera = true
	ribbon.Parent = ball
	fx:track(ribbon)
	local light = fx:light(ball, c.Main, 16, 3)
	local exploded = false
	local nextArc = 0
	fx:every(function(t)
		local k = phase(t, 0, travel)
		local pos = from:Lerp(target, k)
		if not exploded then
			ball.CFrame = look.Rotation + pos
			if core then
				core.CFrame = ball.CFrame
				local s2 = W * (1.1 + 0.15 * math.sin(t * 50))
				rescale(core, Vector3.new(s2, s2, s2))
			end
			light.Brightness = (math.floor(t * 40) % 3 == 0) and 1.5 or 4
			if t >= nextArc then
				nextArc = t + 0.035 / fx.q
				local d = Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1)).Unit
				fx:arc(pos, pos + d * fx.rng:NextNumber(2, 4) * W, 0.9 * W, colors({ { 0, c.Accent }, { 1, c.Main } }), 0.06)
			end
			if k >= 1 then
				exploded = true
				orb.Enabled, trail.Enabled = false, false
				if core then
					core:Destroy()
				end
				Electric.discharge(fx, target, W)
				if o.onHit then
					task.spawn(o.onHit, target)
				end
			end
		else
			light.Brightness = light.Brightness * 0.85
		end
		return exploded and t > travel + 0.9
	end)
end

function Electric.discharge(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "E_Arc8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(14 * W, 14 * W),
		Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
	})
	fx:puff(at, "E_Spark4", 16, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(2 * W, 4 * W), Rotation = NumberRange.new(0, 360),
		Lifetime = NumberRange.new(0.1, 0.25), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Drag = 6,
		Flipbook = { mode = "Random", fps = 30 },
	})
	for k = 1, 7 do
		local d = Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-0.4, 1), fx.rng:NextNumber(-1, 1)).Unit
		fx:arc(at, at + d * fx.rng:NextNumber(4, 8) * W, 1.6 * W, ColorSequence.new(c.Accent), 0.14)
	end
	fx:pulse("RingJag", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(14, 1, 14) * W, 0.4)
	fx:pulse("Spikes", c.Accent, CFrame.new(at) * CFrame.Angles(fx.rng:NextNumber(0, 6), fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(7, 7, 7) * W, 0.18)
	local h = fx:holder(CFrame.new(at))
	local l = fx:light(h, c.Main, 26, 8)
	local born = fx.t
	fx:every(function(t)
		local age = t - born
		l.Brightness = ((math.floor(age * 40) % 2 == 0) and 8 or 3) * (1 - phase(age, 0, 0.5))
		return age > 0.5
	end)
end

-- a full lightning strike from the sky: a 3D bolt mesh wrapped in a glowing bolt beam, a ground burst
function Electric.strike(fx, top: Vector3, foot: Vector3, W: number, big: boolean?)
	local c = fx.c
	local h = (top - foot).Magnitude
	local cf = CFrame.lookAt((top + foot) / 2, foot) * CFrame.Angles(math.rad(90), 0, 0) -- mesh Y runs along the strike
	local m = fx:mesh("Bolt" .. fx.rng:NextInteger(1, 3), c.Accent, cf * CFrame.Angles(0, fx.rng:NextNumber(0, 6.28), 0), Vector3.new(1, 1, 1), 0)
	local width = (big and 6 or 3.5) * W
	rescale(m, Vector3.new(width / math.max((m and (m:GetAttribute("BaseSize") :: Vector3).X) or 1, 0.01) * 0.3, h, width / math.max((m and (m:GetAttribute("BaseSize") :: Vector3).Z) or 1, 0.01) * 0.3))
	fx:arc(top, foot, (big and 5 or 3) * W, colors({ { 0, c.Main }, { 1, c.Accent } }), big and 0.25 or 0.15)
	fx:puff(foot, "E_Arc8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new((big and 18 or 9) * W, (big and 18 or 9) * W),
		Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 210 },
	})
	fx:puff(foot, "E_Spark4", big and 14 or 6, {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(1.5 * W, 3 * W), Rotation = NumberRange.new(0, 360),
		Lifetime = NumberRange.new(0.1, 0.2), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top, Flipbook = { mode = "Random", fps = 30 },
	})
	fx:pulse("RingJag", c.Main, CFrame.new(foot), Vector3.new(1, 1, 1) * W, Vector3.new(big and 22 or 9, 1, big and 22 or 9) * W, big and 0.6 or 0.35)
	local hh = fx:holder(CFrame.new(foot + Vector3.new(0, 2, 0)))
	local l = fx:light(hh, c.Main, big and 40 or 20, big and 10 or 6)
	local born = fx.t
	local life = big and 0.3 or 0.16
	fx:every(function(t)
		local age = t - born
		if m then
			m.Transparency = (age > life * 0.35 and age < life * 0.55) and 0.7 or phase(age, life * 0.6, life)
		end
		l.Brightness = (big and 10 or 6) * (1 - phase(age, 0, life * 1.5))
		if age >= life * 1.5 then
			if m then
				m:Destroy()
			end
			return true
		end
		return false
	end)
end

-- Ultimate: a black storm cloud boils up over the target area, flickering with inner lightning, then
-- unleashes a thunderstorm: strike after strike, faster and faster, ending in one colossal bolt.
function Electric.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 8
	local centre = at * CFrame.new(0, 0, -(o.distance or 20) * S)
	local cloudY = 24 * S
	local radius = 16 * S
	local cloudPart = fx:holder(centre * CFrame.new(0, cloudY, 0), Vector3.new(radius * 2, 3 * S, radius * 2))
	local cloud = fx:emitter(cloudPart, "E_Cloud4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.4,
		Size = numbers({ { 0, 8 * S }, { 0.3, 14 * S }, { 1, 16 * S } }), Transparency = numbers({ { 0, 1 }, { 0.15, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2.4, 3.2), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 10),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-12, 12), Flipbook = { mode = "Loop", fps = 8 }, Rate = 0,
	})
	local cloudCore = fx:emitter(cloudPart, "E_Cloud4", {
		Color = ColorSequence.new(tone(c.Smoke, -0.3)), LightEmission = 0, LightInfluence = 0.3,
		Size = numbers({ { 0, 10 * S }, { 1, 18 * S } }), Transparency = numbers({ { 0, 1 }, { 0.2, 0 }, { 0.8, 0.05 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2.8, 3.4), Speed = NumberRange.new(0, 1), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8), Flipbook = { mode = "Loop", fps = 6 }, Rate = 0,
	})
	local inner = {}
	for k = 1, 4 do
		local h = fx:holder(centre * CFrame.new(fx.rng:NextNumber(-1, 1) * radius * 0.6, cloudY - 1, fx.rng:NextNumber(-1, 1) * radius * 0.6))
		table.insert(inner, fx:light(h, c.Main, 30, 0))
	end
	local function strikeAt(big: boolean?)
		local a = fx.rng:NextNumber(0, 6.28)
		local r = big and 0 or fx.rng:NextNumber(0, radius * 0.9)
		local foot = (centre * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)).Position
		local top = foot + Vector3.new(fx.rng:NextNumber(-2, 2), cloudY - 1.5 * S, fx.rng:NextNumber(-2, 2))
		Electric.strike(fx, top, foot, S, big)
	end
	local nextStrike, nextFlash = 1.3, 0.4
	fx:every(function(t)
		local form = phase(t, 0, 1.2)
		local on = t < 5.2
		cloud.Rate = on and (30 * form + 10) * fx.q or 0
		cloudCore.Rate = on and (12 * form + 4) * fx.q or 0
		if t >= nextFlash and t < 5.6 then
			-- lightning flickering inside the cloud
			nextFlash = t + fx.rng:NextNumber(0.05, 0.2)
			for _, l in inner do
				l.Brightness = fx.rng:NextNumber() < 0.4 and fx.rng:NextNumber(2, 6) or 0
			end
		end
		if t >= nextStrike and t < 4.7 then
			strikeAt(false)
			if fx.q >= 1 and t > 3 then
				strikeAt(false)
			end
			nextStrike = t + math.max(0.08, 0.45 - 0.12 * (t - 1.3))
		end
		return t > 6.5
	end)
	fx:when(4.85, function()
		strikeAt(true)
	end)
end

-- ====================================================================== public API

local ELEMENTS = { Fire = Fire, Electric = Electric }
VFX.Elements = ELEMENTS

local function launch(kind: string, element: string, ...)
	local impl = ELEMENTS[element]
	assert(impl and impl[kind], "ElementVFX: no " .. kind .. " for element " .. tostring(element))
	local args = { ... }
	local options = args[#args]
	if typeof(options) ~= "table" then
		options = {}
	end
	local fx = newFx(element, options)
	impl[kind](fx, ...)
	return fx:run(options.onFinished)
end

-- origin: Vector3 / CFrame / Attachment / BasePart (a part or attachment is followed as it moves)
function VFX.beam(element: string, origin: any, target: Vector3, options: any?)
	return launch("beam", element, origin, target, options or {})
end

function VFX.blast(element: string, origin: any, target: Vector3, options: any?)
	return launch("blast", element, origin, target, options or {})
end

-- at: CFrame at the user's feet, facing where the move goes
function VFX.ultimate(element: string, at: CFrame, options: any?)
	return launch("ultimate", element, at, options or {})
end

-- the old ElementBeams / ElementUltimates names
VFX.fire = VFX.beam
VFX.play = VFX.ultimate

return VFX
