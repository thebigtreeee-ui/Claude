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
	R_Stream = "", R_Crack1 = "", R_Crack2 = "", R_Shard4 = "", R_Tear8 = "", R_Glint = "", R_Hex = "",
	V_Stream = "", V_Swirl8 = "", V_Smoke4 = "", V_Mote = "", V_Ring = "",
	N_Stream = "", N_Leaf4 = "", N_Petal4 = "", N_Bloom8 = "", N_Spore = "",
	I_Stream = "", I_Shard4 = "", I_Frost8 = "", I_Mist4 = "", I_Flake = "",
	W_Stream = "", W_Swirl4 = "", W_Crescent8 = "", W_Dust4 = "", W_Ring = "",
	G_Stream = "", G_Rock4 = "", G_Dust8 = "", G_Crack = "",
	A_Stream = "", A_Splash8 = "", A_Drop = "", A_Foam4 = "", A_Ring = "",
	K_Stream = "", K_Burst8 = "", K_Twinkle4 = "", K_Orb4 = "", K_Ring = "",
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
	R_Shard4 = "rbxasset://textures/particles/sparkles_main.dds",
	R_Tear8 = "rbxasset://textures/particles/sparkles_main.dds",
	R_Glint = "rbxasset://textures/particles/sparkles_main.dds",
	V_Swirl8 = "rbxasset://textures/particles/smoke_main.dds",
	V_Smoke4 = "rbxasset://textures/particles/smoke_main.dds",
	V_Mote = "rbxasset://textures/particles/sparkles_main.dds",
	N_Leaf4 = "rbxasset://textures/particles/sparkles_main.dds",
	N_Petal4 = "rbxasset://textures/particles/sparkles_main.dds",
	N_Bloom8 = "rbxasset://textures/particles/sparkles_main.dds",
	N_Spore = "rbxasset://textures/particles/sparkles_main.dds",
	I_Shard4 = "rbxasset://textures/particles/sparkles_main.dds",
	I_Frost8 = "rbxasset://textures/particles/sparkles_main.dds",
	I_Mist4 = "rbxasset://textures/particles/smoke_main.dds",
	I_Flake = "rbxasset://textures/particles/sparkles_main.dds",
	W_Swirl4 = "rbxasset://textures/particles/smoke_main.dds",
	W_Crescent8 = "rbxasset://textures/particles/sparkles_main.dds",
	W_Dust4 = "rbxasset://textures/particles/smoke_main.dds",
	G_Rock4 = "rbxasset://textures/particles/smoke_main.dds",
	G_Dust8 = "rbxasset://textures/particles/smoke_main.dds",
	A_Splash8 = "rbxasset://textures/particles/smoke_main.dds",
	A_Drop = "rbxasset://textures/particles/sparkles_main.dds",
	A_Foam4 = "rbxasset://textures/particles/smoke_main.dds",
	K_Burst8 = "rbxasset://textures/particles/explosion01_core_main.dds",
	K_Twinkle4 = "rbxasset://textures/particles/sparkles_main.dds",
	K_Orb4 = "rbxasset://textures/particles/sparkles_main.dds",
	X_Glow = "rbxasset://textures/particles/sparkles_main.dds",
}
local FLIPBOOK = { -- name -> grid size
	F_Burst8 = 8, F_Explode8 = 8, E_Arc8 = 8, F_Tongue4 = 4, F_Smoke4 = 4, E_Spark4 = 4, E_Orb4 = 4, E_Cloud4 = 4,
	R_Tear8 = 8, V_Swirl8 = 8, N_Bloom8 = 8, I_Frost8 = 8, W_Crescent8 = 8, G_Dust8 = 8, A_Splash8 = 8, K_Burst8 = 8,
	R_Shard4 = 4, V_Smoke4 = 4, N_Leaf4 = 4, N_Petal4 = 4, I_Shard4 = 4, I_Mist4 = 4, W_Swirl4 = 4, W_Dust4 = 4,
	G_Rock4 = 4, A_Foam4 = 4, K_Twinkle4 = 4, K_Orb4 = 4,
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
local function palette(main, accent, glow, smoke)
	return {
		Main = Color3.fromRGB(table.unpack(main)),
		Accent = Color3.fromRGB(table.unpack(accent)),
		Glow = Color3.fromRGB(table.unpack(glow)),
		Smoke = Color3.fromRGB(table.unpack(smoke)),
	}
end
VFX.Palettes.Rift = palette({ 40, 220, 230 }, { 235, 255, 255 }, { 20, 150, 170 }, { 10, 30, 36 })
VFX.Palettes.Void = palette({ 130, 60, 255 }, { 205, 185, 255 }, { 70, 20, 160 }, { 8, 4, 14 })
VFX.Palettes.Nature = palette({ 90, 220, 90 }, { 220, 255, 170 }, { 30, 160, 90 }, { 40, 60, 30 })
VFX.Palettes.Ice = palette({ 120, 200, 255 }, { 235, 250, 255 }, { 60, 140, 230 }, { 200, 225, 240 })
VFX.Palettes.Wind = palette({ 190, 255, 235 }, { 255, 255, 255 }, { 110, 210, 190 }, { 150, 140, 120 })
VFX.Palettes.Earth = palette({ 130, 100, 70 }, { 255, 170, 70 }, { 230, 90, 30 }, { 120, 100, 80 })
VFX.Palettes.Water = palette({ 40, 140, 255 }, { 220, 245, 255 }, { 20, 80, 200 }, { 180, 215, 240 })
VFX.Palettes.Energy = palette({ 90, 180, 255 }, { 240, 250, 255 }, { 40, 110, 255 }, { 40, 50, 80 })

-- Upload the OGGs in ElementVFX/sounds and paste their ids here. Each element has Beam_Start,
-- Beam_Loop (looped while the beam is on), Blast_Cast, Blast_Hit and Ultimate (plus Electric_Strike).
-- Sounds with no id are simply skipped.
VFX.Sounds = {}
VFX.SoundVolume = 1
local SOUND_LENGTH = { -- seconds; an effect stays alive until its sounds have finished
	Beam_Start = 1.0, Beam_Loop = 0, Blast_Cast = 0.8, Blast_Hit = 2.0, Strike = 2.4,
	Ultimate = { Fire = 6.0, Electric = 6.8, Rift = 6.0, Void = 8.0, Nature = 6.0, Ice = 7.0, Wind = 2.4, Earth = 6.8, Water = 6.5, Energy = 9.2 },
}
for _, element in { "Fire", "Electric", "Rift", "Void", "Nature", "Ice", "Wind", "Earth", "Water", "Energy" } do
	for _, move in { "Beam_Start", "Beam_Loop", "Blast_Cast", "Blast_Hit", "Ultimate" } do
		VFX.Sounds[element .. "_" .. move] = ""
	end
end
VFX.Sounds.Electric_Strike = ""

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

-- a 3D sound for this element ("Beam_Start" plays <Element>_Beam_Start) from a part, so it moves with it
function Fx:sound(move: string, parent: Instance, props: { [string]: any }?): Sound?
	local id = VFX.Sounds[self.element .. "_" .. move]
	if not id or id == "" or self.options.sounds == false then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = self.element .. "_" .. move
	snd.SoundId = id
	snd.Volume = 0.8 * VFX.SoundVolume * (self.options.volume or 1)
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = move == "Ultimate" and 30 or 14
	snd.RollOffMaxDistance = move == "Ultimate" and 500 or 260
	for k, v in props or {} do
		(snd :: any)[k] = v
	end
	snd.Parent = parent
	self:track(snd)
	snd:Play()
	local length = SOUND_LENGTH[move]
	if typeof(length) == "table" then
		length = length[self.element]
	end
	if not snd.Looped then
		self.lifetime = math.max(self.lifetime, self.t + (length or 2) + 0.1)
	end
	return snd
end

-- beam audio: the start hit, then a loop that swells in and fades out when the beam ends at D
function Fx:beamAudio(parent: Instance, D: number)
	self:sound("Beam_Start", parent)
	local loop = self:sound("Beam_Loop", parent, { Looped = true, Volume = 0 })
	if loop then
		local full = 0.8 * VFX.SoundVolume * (self.options.volume or 1)
		self:every(function(t)
			loop.Volume = full * phase(t, 0.05, 0.35) * (1 - phase(t, D, D + 0.35))
			if t > D + 0.35 then
				loop:Stop()
				return true
			end
			return false
		end)
	end
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
function Fx:pulse(name: string, color: Color3, cf: CFrame, from: Vector3, to: Vector3, life: number, startTransparency: number?)
	local s0 = startTransparency or 0.1
	local m = self:mesh(name, color, cf, from, s0)
	if not m then
		return
	end
	local born = self.t
	self:every(function(t)
		local k = phase(t - born, 0, life)
		rescale(m, from:Lerp(to, easeOut(k)))
		m.Transparency = s0 + (1 - s0) * k ^ 1.5
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
	fx:beamAudio(s.startPart, D)
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
	fx:sound("Blast_Cast", ball)
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
	fx:sound("Blast_Hit", h)
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
	fx:sound("Ultimate", fx:holder(at * CFrame.new(0, 3, -4)))
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
	local cone = nil :: BasePart?
	local coneInner = fx:mesh("FlameCone", c.Main, aim, Vector3.new(0.01, 0.01, 0.01), 0.55)
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
			coneInner.CFrame = aim * CFrame.new(0, 0, -L * 0.28) * CFrame.Angles(0, 0, -t * 6)
			local w = 4.5 * S * burst
			rescale(coneInner, Vector3.new(w, w, math.max(L * 0.55, 0.01)))
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
	fx:beamAudio(s.startPart, D)
	local cores = {
		fx:beam(a0, a1, "E_Plasma", { Color = ColorSequence.new(c.Accent), TextureSpeed = 5, TextureLength = 8, ZOffset = 0.3, Transparency = NumberSequence.new(0.2) }),
		fx:beam(a0, a1, "E_Plasma", { Color = colors({ { 0, c.Main }, { 1, c.Glow } }), TextureSpeed = -3, TextureLength = 12, ZOffset = 0.1, LightEmission = 0.3, Transparency = NumberSequence.new(0.1) }),
	}
	local bolts = {}
	for i = 1, 4 do
		table.insert(bolts, fx:beam(a0, a1, BOLTS[(i - 1) % 3 + 1], {
			Color = i == 1 and colors({ { 0, c.Accent }, { 1, c.Main } }) or colors({ { 0, c.Main }, { 1, c.Glow } }),
			LightEmission = i == 1 and 1 or 0.6, TextureSpeed = 0, TextureLength = 8, ZOffset = 0.2,
		}))
	end
	local rings = {}
	for i = 1, 5 do
		local m = fx:mesh("ZapRing", i % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(1, 1, 1), 0.1)
		table.insert(rings, { m = m, u = (i - 1) / 5, spin = fx.rng:NextNumber(-12, 12) })
	end
	local sparks = fx:emitter(s.spine, "E_Spark4", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(1.6 * W, 3.2 * W),
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
			b.Width0 = (i == 1 and 0.5 or 2.2) * W * fade * flicker
			b.Width1 = (i == 1 and 0.6 or 2.5) * W * fade * flicker
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
			fx:arc(pa, pa + out * fx.rng:NextNumber(2, 5) * W + s.cf.LookVector * fx.rng:NextNumber(-2, 2), 1.2 * W, colors({ { 0, c.Main }, { 1, c.Glow } }), 0.09)
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
	fx:sound("Blast_Cast", ball)
	local core = fx:mesh("Orb", c.Accent, look, Vector3.new(1, 1, 1) * W, 0)
	local shell = fx:mesh("Orb", c.Main, look, Vector3.new(1, 1, 1) * W, 0.55)
	local orb = fx:emitter(ball, "E_Orb4", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(5.2 * W, 5.8 * W), LockedToPart = true, LightEmission = 0.7,
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
				local s2 = W * (1.5 + 0.2 * math.sin(t * 50))
				rescale(core, Vector3.new(s2, s2, s2))
			end
			if shell then
				shell.CFrame = ball.CFrame
				local s3 = W * (2.6 + 0.3 * math.sin(t * 37))
				rescale(shell, Vector3.new(s3, s3, s3))
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
				if shell then
					shell:Destroy()
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
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(16 * W, 16 * W),
		Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
	})
	fx:puff(at, "E_Orb4", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Glow } }), Size = numbers({ { 0, 4 * W }, { 1, 9 * W } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.25, 0.25), Speed = NumberRange.new(0, 0), Flipbook = { mode = "Loop", fps = 30 },
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
	fx:sound("Blast_Hit", h)
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
	fx:sound("Strike", hh, big and { Volume = 1.1 * VFX.SoundVolume * (fx.options.volume or 1), PlaybackSpeed = 0.85 } or { PlaybackSpeed = fx.rng:NextNumber(0.9, 1.15) })
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
	fx:sound("Ultimate", fx:holder(centre * CFrame.new(0, 6, 0)))
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

-- ====================================================================== shared helpers for the elements below

-- turn a CFrame so a mesh's long Y axis points along its look direction
local function alongY(cf: CFrame): CFrame
	return cf * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function backOut(x: number): number
	local k = 1.7
	return 1 + (k + 1) * (x - 1) ^ 3 + k * (x - 1) ^ 2
end

-- size a ground-rooted mesh (base at its -Y face) and keep that base on `base`
local function rooted(m: BasePart?, base: CFrame, w: number, h: number, d: number?)
	if m then
		local hh = math.max(h, 0.001)
		rescale(m, Vector3.new(w, hh, d or w))
		m.CFrame = base * CFrame.new(0, hh * (m:GetAttribute("BaseSize") :: Vector3).Y / 2, 0)
	end
end

-- the common start of every beam: duration, width, the stream, its end attachments and the audio
local function beamBase(fx, origin, target: Vector3, linger: number)
	local o = fx.options
	local D = o.duration or 2.2
	local W = o.width or 1
	fx.lifetime = D + linger
	local s = stream(fx, origin, target)
	local a0, a1 = fx:attach(s.startPart), fx:attach(s.endPart)
	fx:beamAudio(s.startPart, D)
	return s, a0, a1, D, W
end

-- switch off or remove a projectile's flying layers when it lands
local function retire(list: { any })
	for _, x in list do
		if x:IsA("ParticleEmitter") or x:IsA("Beam") or x:IsA("Trail") then
			x.Enabled = false
		elseif x:IsA("PointLight") then
			x.Brightness = 0
		else
			x:Destroy()
		end
	end
end

-- a ribbon trail between two offsets on a moving part
function Fx:trail(parent: BasePart, tex: string, p0: Vector3, p1: Vector3, color: ColorSequence, life: number): Trail
	local tA, tB = self:attach(parent), self:attach(parent)
	tA.Position, tB.Position = p0, p1
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = tA, tB
	tr.Texture = texture(tex)
	tr.Color = color
	tr.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
	tr.Lifetime = life
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Parent = parent
	return self:track(tr)
end

-- chunks thrown out from a point: meshes with velocity, gravity and spin that fade out
function Fx:debris(names: { string }, color: Color3, at: Vector3, count: number, speed: number, size: number, life: number, material: any?, up: number?)
	for _ = 1, math.max(1, math.floor(count * self.q + 0.5)) do
		local rot = CFrame.Angles(self.rng:NextNumber(0, 6.28), self.rng:NextNumber(0, 6.28), 0)
		local sz = size * self.rng:NextNumber(0.6, 1.3)
		local m = self:mesh(names[self.rng:NextInteger(1, #names)], color, rot + at, Vector3.new(sz, sz, sz), 0)
		if m then
			if material then
				m.Material = material
			end
			local dir = Vector3.new(self.rng:NextNumber(-1, 1), self.rng:NextNumber(0.2, 1) + (up or 0), self.rng:NextNumber(-1, 1)).Unit
			local vel = dir * speed * self.rng:NextNumber(0.5, 1)
			local spin = Vector3.new(self.rng:NextNumber(-8, 8), self.rng:NextNumber(-8, 8), self.rng:NextNumber(-8, 8))
			local pos = at
			local born = self.t
			self:every(function(t, dt)
				vel += Vector3.new(0, -50 * dt, 0)
				pos += vel * dt
				rot = rot * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
				m.CFrame = rot + pos
				m.Transparency = phase(t - born, life * 0.6, life)
				if t - born >= life then
					m:Destroy()
					return true
				end
				return false
			end)
		end
	end
end

-- crystals that stab out of a point (mostly upwards), hold, then fade
function Fx:crystals(at: Vector3, count: number, len: number, width: number, colorA: Color3, colorB: Color3, hold: number, spread: number?)
	for i = 1, math.max(1, math.floor(count * self.q + 0.5)) do
		local sp = spread or 0.8
		local dir = Vector3.new(self.rng:NextNumber(-sp, sp), 1, self.rng:NextNumber(-sp, sp)).Unit
		local cf = alongY(CFrame.lookAt(at, at + dir))
		local l = len * self.rng:NextNumber(0.6, 1.2)
		local m = self:mesh("Crystal" .. self.rng:NextInteger(1, 3), i % 2 == 0 and colorA or colorB, cf, Vector3.new(0.01, 0.01, 0.01), 0.1)
		if m then
			local born = self.t
			self:every(function(t)
				local age = t - born
				local k = easeOut(phase(age, 0, 0.1))
				rescale(m, Vector3.new(width * 5, l * k, width * 5))
				m.CFrame = cf * CFrame.new(0, l * k * 0.35, 0)
				m.Transparency = 0.1 + 0.9 * phase(age, hold, hold + 0.3)
				if age >= hold + 0.3 then
					m:Destroy()
					return true
				end
				return false
			end)
		end
	end
end

-- a flash of light at a point that fades out
function Fx:flash(at: Vector3, color: Color3, range: number, brightness: number, life: number)
	local h = self:holder(CFrame.new(at))
	local l = self:light(h, color, range, brightness)
	local born = self.t
	self:every(function(t)
		l.Brightness = brightness * (1 - phase(t - born, 0, life))
		return t - born > life
	end)
end

-- a projectile: a holder flying from origin to target. go(step, impact): step(t, cf, grow, dt) runs each
-- frame of the flight, impact(position) once on arrival (along with the hit sound and onHit)
local function projectile(fx, origin, target: Vector3, speed: number, linger: number)
	local p = {}
	p.from = positionOf(origin)
	p.travel = math.max((target - p.from).Magnitude / speed, 0.05)
	fx.lifetime = p.travel + linger
	p.look = CFrame.lookAt(p.from, target)
	p.ball = fx:holder(p.look)
	fx:sound("Blast_Cast", p.ball)
	function p.go(step: (number, CFrame, number, number) -> (), impact: (Vector3) -> ())
		fx:every(function(t, dt)
			local k = phase(t, 0, p.travel)
			p.ball.CFrame = p.look.Rotation + p.from:Lerp(target, k)
			step(t, p.ball.CFrame, easeOut(phase(t, 0, 0.12)), dt)
			if k >= 1 then
				fx:sound("Blast_Hit", fx:holder(CFrame.new(target)))
				impact(target)
				if fx.options.onHit then
					task.spawn(fx.options.onHit, target)
				end
				return true
			end
			return false
		end)
	end
	return p
end

-- ====================================================================== RIFT

local Rift = {}
local CRACKS = { "R_Crack1", "R_Crack2" }

-- a jagged crack of light splitting the air from a towards b
function Fx:crack(a: Vector3, b: Vector3, width: number, color: ColorSequence, life: number, grow: number?)
	local h0, h1 = self:holder(CFrame.new(a)), self:holder(CFrame.new(a))
	local beam = self:beam(self:attach(h0), self:attach(h1), CRACKS[self.rng:NextInteger(1, 2)], {
		Color = color, Width0 = width, Width1 = width * 0.5, TextureSpeed = 0,
		TextureLength = math.max((b - a).Magnitude, 1), Segments = 2,
	})
	local born = self.t
	self:every(function(t)
		local age = t - born
		h1.CFrame = CFrame.new(a:Lerp(b, easeOut(phase(age, 0, grow or 0.08))))
		beam.Transparency = NumberSequence.new(phase(age, life * 0.6, life))
		if age >= life then
			h0:Destroy()
			h1:Destroy()
			return true
		end
		return false
	end)
end

-- A crystal-lattice beam: a white-hot core in a faceted cyan body, angular cracks of light that
-- re-split every few frames, hexagonal gates turning along it and glass shards spraying off it.
-- Where it hits, reality splinters: tears flash open and crystals stab out of the impact.
function Rift.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.2)
	local core = fx:beam(a0, a1, "R_Stream", { Color = ColorSequence.new(c.Accent), TextureSpeed = 4, TextureLength = 5, ZOffset = 0.3 })
	local body = fx:beam(a0, a1, "R_Stream", {
		Color = colors({ { 0, c.Accent }, { 0.12, c.Main }, { 1, c.Glow } }), TextureSpeed = -2.5, TextureLength = 8,
		LightEmission = 0.2, ZOffset = 0.1,
	})
	local cracks = {}
	for i = 1, 3 do
		table.insert(cracks, fx:beam(a0, a1, CRACKS[(i - 1) % 2 + 1], {
			Color = i == 1 and colors({ { 0, c.Accent }, { 1, c.Main } }) or colors({ { 0, c.Main }, { 1, c.Glow } }),
			LightEmission = i == 1 and 0.8 or 0.4, TextureSpeed = 0, TextureLength = 9, ZOffset = 0.2, Segments = 6,
		}))
	end
	local gates = {}
	for i = 1, 4 do
		table.insert(gates, { m = fx:mesh("HexGate", i % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(1, 1, 1), 0.15), u = (i - 1) / 4 })
	end
	local muzzle = fx:mesh("HexGate", c.Accent, s.cf, Vector3.new(1, 1, 1), 0)
	local muzzle2 = fx:mesh("HexGate", c.Main, s.cf, Vector3.new(1, 1, 1), 0.2)
	local shards = fx:emitter(s.spine, "R_Shard4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.6 * W, 1.3 * W), LightEmission = 0.6,
		Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Transparency = numbers({ { 0, 0 }, { 0.7, 0 }, { 1, 1 } }),
		Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 40,
	})
	local glints = fx:emitter(s.spine, "R_Glint", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.5, 1.8 * W }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0, 1), Rotation = NumberRange.new(-20, 20), Rate = 25,
	})
	local hitLight = fx:light(s.endPart, c.Main, 22)
	local beamLight = fx:light(s.spine, c.Main, 14)
	local jut = {}
	local nextJitter, nextTear, nextJut = 0, 0, 0
	fx:when(D, function()
		fx:puff(s.tip, "R_Shard4", 14, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.8 * W, 1.6 * W), Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -20, 0), Flipbook = { mode = "Random", fps = 1, random = true },
		})
	end)
	fx:every(function(t, dt)
		local grow = easeOut(phase(t, 0, 0.14))
		local fade = 1 - phase(t, D, D + 0.25)
		s:update(grow)
		local len = s.len * grow
		core.Width0, core.Width1 = 0.35 * W * fade, 0.45 * W * fade
		body.Width0, body.Width1 = 2.4 * W * fade, 3.0 * W * fade
		if t >= nextJitter then
			-- the cracks re-split: new shapes and kinks
			nextJitter = t + 0.07
			for i, b in cracks do
				b.Texture = texture(CRACKS[fx.rng:NextInteger(1, 2)])
				b.CurveSize0 = fx.rng:NextNumber(-1, 1) * 1.6 * W
				b.CurveSize1 = fx.rng:NextNumber(-1, 1) * 1.6 * W
				local w = (0.9 + 0.35 * i) * W * fade
				b.Width0, b.Width1 = w, w * fx.rng:NextNumber(0.8, 1.3)
			end
		end
		for i, g in gates do
			if g.m then
				g.u = (g.u + dt * 0.35) % 1
				g.m.CFrame = s.cf * CFrame.new(0, 0, -len * g.u) * CFrame.Angles(0, 0, t * (i % 2 == 0 and 2 or -2.6))
				local sz = 4.2 * W * fade * math.sin(math.pi * g.u) ^ 0.4
				rescale(g.m, Vector3.new(sz, sz, 1))
			end
		end
		local mp = 1 + 0.06 * math.sin(t * 24)
		if muzzle then
			muzzle.CFrame = s.cf * CFrame.new(0, 0, -0.6) * CFrame.Angles(0, 0, t * 3)
			rescale(muzzle, Vector3.new(3.6, 3.6, 1) * W * fade * mp)
		end
		if muzzle2 then
			muzzle2.CFrame = s.cf * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, 0, -t * 2 + 0.5)
			rescale(muzzle2, Vector3.new(5, 5, 1) * W * fade * (2 - mp))
		end
		local on = t < D
		shards.Enabled, glints.Enabled = on, on
		beamLight.Brightness = 3 * fade
		if grow >= 1 and on then
			hitLight.Brightness = 4 + math.sin(t * 20)
			if t >= nextTear then
				-- tears in space flash open round the impact
				nextTear = t + 0.25
				fx:puff(s.tip + Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1)) * W, "R_Tear8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(7 * W, 9 * W), Rotation = NumberRange.new(-40, 40),
					Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 140 },
				})
				fx:puff(s.tip, "R_Shard4", 6, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.7 * W, 1.4 * W), Lifetime = NumberRange.new(0.3, 0.5),
					Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-300, 300), Flipbook = { mode = "Random", fps = 1, random = true },
				})
			end
			if t >= nextJut and #jut < 9 then
				nextJut = t + 0.18 / fx.q
				local dir = Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(0.1, 1), fx.rng:NextNumber(-1, 1)).Unit
				local cf = alongY(CFrame.lookAt(s.tip, s.tip + dir))
				local m = fx:mesh("Crystal" .. fx.rng:NextInteger(1, 3), fx.rng:NextNumber() < 0.5 and c.Main or c.Accent, cf, Vector3.new(0.01, 0.01, 0.01), 0.1)
				if m then
					table.insert(jut, { m = m, cf = cf, born = t, len = fx.rng:NextNumber(3, 5.5) * W })
				end
			end
		else
			hitLight.Brightness *= 0.85
		end
		for _, j in jut do
			local k = easeOut(phase(t - j.born, 0, 0.12))
			rescale(j.m, Vector3.new(5 * W, j.len * k, 5 * W))
			j.m.CFrame = j.cf * CFrame.new(0, j.len * k * 0.3, 0)
			j.m.Transparency = 0.1 + 0.9 * phase(t, D, D + 0.25)
		end
		return t > D + 0.4
	end)
end

-- A spinning crystal spear with a hexagonal gate turning behind it, shedding glass shards and glints.
-- It lands in a splinter of reality: a tear flashes open, shards and cracks burst out.
function Rift.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 90, 1.6)
	local crystal = fx:mesh("Crystal1", c.Main, alongY(p.look), Vector3.new(0.01, 0.01, 0.01), 0.35)
	local inner = fx:mesh("Crystal2", c.Accent, alongY(p.look), Vector3.new(0.01, 0.01, 0.01), 0)
	local gate = fx:mesh("HexGate", c.Accent, p.look, Vector3.new(0.01, 0.01, 0.01), 0.1)
	local trail = fx:trail(p.ball, "R_Stream", Vector3.new(0, 0.7 * W, 0), Vector3.new(0, -0.7 * W, 0), colors({ { 0, c.Accent }, { 1, c.Main } }), 0.2)
	local shards = fx:emitter(p.ball, "R_Shard4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.5 * W, 1.1 * W), LightEmission = 0.6,
		Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 45,
	})
	local glints = fx:emitter(p.ball, "R_Glint", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.5, 1.6 * W }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0, 1), Rate = 30,
	})
	local light = fx:light(p.ball, c.Main, 16, 3)
	p.go(function(t, cf, grow)
		if crystal then
			crystal.CFrame = alongY(cf) * CFrame.Angles(0, t * 14, 0)
			rescale(crystal, Vector3.new(9, 4.2, 9) * W * grow)
		end
		if inner then
			inner.CFrame = alongY(cf) * CFrame.Angles(0, -t * 20, 0)
			rescale(inner, Vector3.new(5, 3.2, 5) * W * grow)
		end
		if gate then
			gate.CFrame = cf * CFrame.new(0, 0, 1.4 * W) * CFrame.Angles(0, 0, t * 9)
			local sz = 3.2 * W * grow * (1 + 0.1 * math.sin(t * 30))
			rescale(gate, Vector3.new(sz, sz, 1))
		end
	end, function(at)
		retire({ crystal, inner, gate, trail, shards, glints, light })
		Rift.shatter(fx, at, W)
	end)
end

function Rift.shatter(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "R_Tear8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(14 * W, 14 * W), Rotation = NumberRange.new(-25, 25),
		Lifetime = NumberRange.new(0.55, 0.55), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "X_Glow", 1, {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 6 * W }, { 1, 12 * W } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.25, 0.25), Speed = NumberRange.new(0, 0),
	})
	fx:puff(at, "R_Shard4", 26, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.8 * W, 1.8 * W), Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -15, 0), Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:puff(at, "R_Glint", 12, {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.4, 2.4 * W }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(6, 16), SpreadAngle = Vector2.new(180, 180), Drag = 5,
	})
	fx:debris({ "Shard1", "Shard2" }, c.Accent, at, 7, 26, 1.6 * W, 0.8)
	for _ = 1, 6 do
		local d = Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-0.5, 1), fx.rng:NextNumber(-1, 1)).Unit
		fx:crack(at, at + d * fx.rng:NextNumber(4, 8) * W, 1.3 * W, colors({ { 0, c.Accent }, { 1, c.Main } }), 0.5)
	end
	fx:pulse("HexGate", c.Accent, CFrame.new(at) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(1, 1, 1) * W, Vector3.new(14, 14, 1) * W, 0.4)
	fx:pulse("Ring", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(17, 1, 17) * W, 0.5)
	fx:flash(at, c.Main, 26, 8, 0.6)
end

-- Ultimate: Rift tear. Cracks splinter through the air ahead, then rip open into a blinding tear in
-- reality, ringed by turning hex gates, spitting shards and filaments of light, until it snaps shut.
function Rift.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 6.2
	local centre = at * CFrame.new(0, 7 * S, -(o.distance or 14) * S)
	local cp = centre.Position
	local hub = fx:holder(centre, Vector3.new(5, 12, 1) * S)
	fx:sound("Ultimate", hub)
	local crackCol = colors({ { 0, c.Accent }, { 1, c.Main } })
	-- the tear: a white lens with a cyan edge (the edge sits just behind, from the caster's side)
	local edge = fx:mesh("Lens", c.Main, centre * CFrame.new(0, 0, -0.08), Vector3.new(0.01, 0.01, 1), 0)
	local tear = fx:mesh("Lens", c.Accent, centre * CFrame.new(0, 0, 0.08), Vector3.new(0.01, 0.01, 1), 0)
	local gates = {}
	for k = 1, 3 do
		table.insert(gates, { m = fx:mesh("HexGate", k == 2 and c.Accent or c.Main, centre, Vector3.new(0.01, 0.01, 1), 0.3 + 0.1 * k), size = (14 + 5 * k) * S, spin = (k % 2 == 0 and -1 or 1) * (0.5 + 0.3 * k) })
	end
	local orbit = {}
	for k = 1, 6 do
		table.insert(orbit, { m = fx:mesh("Shard" .. (k % 2 + 1), k % 2 == 0 and c.Main or c.Accent, centre, Vector3.new(0.01, 0.01, 0.01), 0.1), a = k / 6 * math.pi * 2, r = fx.rng:NextNumber(8, 11) * S, h = fx.rng:NextNumber(-3, 3) * S })
	end
	local spit = fx:emitter(hub, "R_Shard4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.8 * S, 1.8 * S), LightEmission = 0.6,
		Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(8 * S, 18 * S), SpreadAngle = Vector2.new(180, 180), Drag = 1.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 0,
	})
	local pull = fx:emitter(fx:holder(centre, Vector3.new(32, 32, 32) * S), "R_Glint", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.3, 1.6 * S }, { 1, 0.4 * S } }),
		Lifetime = NumberRange.new(1.1, 1.3), Speed = NumberRange.new(13 * S, 13 * S), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 0,
	})
	local groundRing = fx:mesh("Ring", c.Main, at * CFrame.new(0, 0.1, -(o.distance or 14) * S), Vector3.new(0.01, 1, 0.01), 0.3)
	local light = fx:light(hub, c.Main, 45, 0)
	-- 0-1.0: cracks splinter outward from the centre, each new one branching off an old one
	local tips = { cp }
	local nextCrack, nextFil = 0.05, 1.6
	fx:when(1.0, function()
		fx:puff(cp, "R_Tear8", 1, {
			Color = crackCol, Size = NumberRange.new(26 * S, 26 * S), Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0),
			Flipbook = { mode = "OneShot", fps = 128 },
		})
		fx:puff(cp, "R_Shard4", 24, {
			Color = crackCol, Size = NumberRange.new(1 * S, 2 * S), Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(16 * S, 30 * S),
			SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
			Flipbook = { mode = "Random", fps = 1, random = true },
		})
		fx:pulse("Ring", c.Main, centre * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(4, 1, 4) * S, Vector3.new(30, 1, 30) * S, 0.45, 0.45)
		fx:flash(cp, c.Main, 60, 8, 0.5)
	end)
	fx:when(4.8, function()
		-- the snap
		fx:puff(cp, "X_Glow", 1, {
			Color = ColorSequence.new(c.Main), Size = numbers({ { 0, 12 * S }, { 1, 26 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0, 0),
		})
		fx:puff(cp, "R_Tear8", 1, {
			Color = crackCol, Size = NumberRange.new(30 * S, 30 * S), Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0),
			Flipbook = { mode = "OneShot", fps = 140 },
		})
		fx:puff(cp, "R_Shard4", 40, {
			Color = crackCol, Size = NumberRange.new(1 * S, 2.4 * S), Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(20 * S, 40 * S),
			SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
			Acceleration = Vector3.new(0, -20, 0), Flipbook = { mode = "Random", fps = 1, random = true },
		})
		fx:debris({ "Shard1", "Shard2" }, c.Accent, cp, 10, 40, 2.6 * S, 1.1)
		for _ = 1, 10 do
			local a = fx.rng:NextNumber(0, 6.28)
			fx:crack(cp, (centre * CFrame.new(math.cos(a) * 14 * S, math.sin(a) * 14 * S, 0)).Position, 2 * S, crackCol, 0.5, 0.1)
		end
		fx:pulse("Ring", c.Main, centre * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(2, 1, 2) * S, Vector3.new(44, 1, 44) * S, 0.55, 0.4)
		fx:pulse("HexGate", c.Main, centre, Vector3.new(4, 4, 1) * S, Vector3.new(40, 40, 1) * S, 0.5)
		fx:pulse("RingJag", c.Main, at * CFrame.new(0, 0.2, -(o.distance or 14) * S), Vector3.new(2, 1, 2) * S, Vector3.new(44, 1, 44) * S, 0.7)
		fx:flash(cp, c.Main, 70, 9, 0.8)
	end)
	fx:every(function(t, dt)
		if t < 1.0 and t >= nextCrack then
			nextCrack = t + 0.05 / fx.q
			local from = tips[fx.rng:NextInteger(1, #tips)]
			local a = fx.rng:NextNumber(0, 6.28)
			local r = fx.rng:NextNumber(2, 4) * S
			local to = from + (centre.RightVector * math.cos(a) + centre.UpVector * math.sin(a) * 1.6) * r
			if (to - cp).Magnitude < 12 * S then
				table.insert(tips, to)
			end
			fx:crack(from, to, 1.5 * S, crackCol, 1.7 - t, 0.1)
			fx:puff(to, "R_Glint", 1, {
				Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.3, 2.5 * S }, { 1, 0 } }),
				Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0, 0),
			})
		end
		-- 1.0-1.6 the rip, 1.6-4.8 the hum, 4.8 the snap
		local open = easeOut(phase(t, 1.0, 1.6)) * (1 - phase(t, 4.8, 4.92))
		local hum = 1 + 0.05 * math.sin(t * 17) + 0.03 * math.sin(t * 41)
		local w, h = 6 * S * open * hum, (4 + 10 * easeOut(phase(t, 1.0, 1.3))) * S
		if edge then
			edge.CFrame = centre * CFrame.new(0, 0, -0.08)
			rescale(edge, Vector3.new(w * 1.25 + 0.6 * S * open, h * 1.08, 1))
		end
		if tear then
			tear.CFrame = centre * CFrame.new(0, 0, 0.08)
			rescale(tear, Vector3.new(w, h, 1))
		end
		local g = easeOut(phase(t, 1.3, 2.0)) * (1 - phase(t, 4.75, 4.9))
		for _, gate in gates do
			if gate.m then
				gate.m.CFrame = centre * CFrame.Angles(0, 0, t * gate.spin)
				rescale(gate.m, Vector3.new(gate.size * g, gate.size * g, 1))
			end
		end
		for _, sh in orbit do
			if sh.m then
				local a = sh.a + t * 0.9
				sh.m.CFrame = centre * CFrame.new(math.cos(a) * sh.r, sh.h + math.sin(t * 2 + sh.a), math.sin(a) * sh.r * 0.5) * CFrame.Angles(t * 2, t * 3, sh.a)
				rescale(sh.m, Vector3.new(2.6, 2.6, 2.6) * S * g)
			end
		end
		if groundRing then
			local gr = 22 * S * g
			rescale(groundRing, Vector3.new(gr, 1, gr))
		end
		local humming = t >= 1.6 and t < 4.8
		spit.Rate = humming and 40 * fx.q or 0
		pull.Rate = (t >= 1.2 and t < 4.6) and 50 * fx.q or 0
		light.Brightness = 5 * open * hum
		if humming and t >= nextFil then
			-- filaments of light whip off the rim of the tear
			nextFil = t + 0.06 / fx.q
			local a = fx.rng:NextNumber(0, 6.28)
			local rim = (centre * CFrame.new(math.cos(a) * w * 0.5, math.sin(a) * h * 0.5, 0)).Position
			local out = (rim - cp).Unit
			fx:crack(rim, rim + out * fx.rng:NextNumber(3, 7) * S + Vector3.new(0, fx.rng:NextNumber(-1, 1), 0), 1.0 * S, crackCol, 0.16, 0.04)
		end
		return t > 6
	end)
end

-- ====================================================================== VOID

local Void = {}

-- A beam of darkness: a black core inside a dark violet stream with a glowing rim, black spiral
-- tendrils and dark matter dragged along it; where it lands, space caves in on itself.
function Void.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.4)
	local dark = tone(c.Smoke, -0.3)
	local halo = fx:beam(a0, a1, "V_Stream", {
		Color = colors({ { 0, c.Accent }, { 0.2, c.Main }, { 1, c.Glow } }), TextureSpeed = 2, TextureLength = 10,
		Transparency = NumberSequence.new(0.45), ZOffset = -0.1,
	})
	local body = fx:beam(a0, a1, "V_Stream", { Color = colors({ { 0, c.Main }, { 1, c.Glow } }), TextureSpeed = -3, TextureLength = 7, LightEmission = 0, ZOffset = 0.1 })
	local core = fx:beam(a0, a1, "V_Stream", { Color = ColorSequence.new(dark), TextureSpeed = 4.5, TextureLength = 5, LightEmission = 0, ZOffset = 0.2 })
	local tendril = fx:mesh("Spiral", dark, s.cf, Vector3.new(1, 1, 1), 0.05)
	local tendril2 = fx:mesh("SpiralThin", c.Main, s.cf, Vector3.new(1, 1, 1), 0.3)
	local matter = fx:emitter(s.spine, "V_Smoke4", {
		Color = ColorSequence.new(dark), LightEmission = 0, Size = numbers({ { 0, 1.6 * W }, { 1, 3.6 * W } }),
		Transparency = numbers({ { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		Flipbook = { mode = "OneShot", fps = 30 }, Rate = 30,
	})
	local motes = fx:emitter(s.spine, "V_Mote", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.6 }, { 1, 0 } }), Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Drag = 2, Rate = 35,
	})
	-- at the hands: a little accretion disc round a black pinpoint
	local disk = fx:mesh("Disk", c.Main, s.cf, Vector3.new(0.01, 1, 0.01), 0.1)
	local pin = fx:mesh("Orb", dark, s.cf, Vector3.new(0.01, 0.01, 0.01), 0)
	-- the impact: a black orb that swallows its surroundings
	local well = fx:mesh("Orb", dark, s.cf, Vector3.new(0.01, 0.01, 0.01), 0)
	local wellDisk = fx:mesh("Disk", c.Main, s.cf, Vector3.new(0.01, 1, 0.01), 0.1)
	local swirl = fx:emitter(s.endPart, "V_Swirl8", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(9 * W, 10 * W), Transparency = NumberSequence.new(0.2),
		Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, -150),
		LockedToPart = true, Flipbook = { mode = "OneShot", fps = 128 }, Rate = 0,
	})
	local suckPart = fx:holder(CFrame.new(target), Vector3.new(14, 14, 14) * W)
	local suck = fx:emitter(suckPart, "V_Mote", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.3 }, { 1, 0.8 } }), Lifetime = NumberRange.new(0.5, 0.6),
		Speed = NumberRange.new(13 * W, 13 * W), Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 0,
	})
	local hitLight = fx:light(s.endPart, c.Main, 20)
	local beamLight = fx:light(s.spine, c.Glow, 12)
	local tilt = CFrame.Angles(math.rad(70), 0, math.rad(15))
	local nextRing = 0
	local hit = false
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.2))
		local fade = 1 - phase(t, D, D + 0.3)
		s:update(grow)
		local len = s.len * grow
		local mid = s.cf * CFrame.new(0, 0, -len / 2)
		local wob = 1 + 0.08 * math.sin(t * 13)
		halo.Width0, halo.Width1 = 3.2 * W * fade, 4.4 * W * fade * wob
		body.Width0, body.Width1 = 2.2 * W * fade, 3.0 * W * fade
		core.Width0, core.Width1 = 0.9 * W * fade, 1.2 * W * fade
		if tendril then
			tendril.CFrame = mid * CFrame.Angles(0, 0, -t * 6)
			rescale(tendril, Vector3.new(3.4 * W * fade, 3.4 * W * fade, len))
		end
		if tendril2 then
			tendril2.CFrame = mid * CFrame.Angles(0, 0, t * 9)
			rescale(tendril2, Vector3.new(2.6 * W * fade, 2.6 * W * fade, len))
		end
		if disk then
			disk.CFrame = s.cf * CFrame.new(0, 0, -0.8) * CFrame.Angles(math.pi / 2, t * 8, 0)
			rescale(disk, Vector3.new(4.6, 1, 4.6) * W * fade)
		end
		if pin then
			pin.CFrame = s.cf * CFrame.new(0, 0, -0.8)
			rescale(pin, Vector3.new(1.4, 1.4, 1.4) * W * fade)
		end
		local on = t < D
		matter.Enabled, motes.Enabled = on, on
		beamLight.Brightness = 2 * fade
		local landed = grow >= 1 and on
		if landed and not hit then
			hit = true
			fx:pulse("Ring", c.Accent, CFrame.new(s.tip) * tilt, Vector3.new(1, 1, 1) * W, Vector3.new(14, 1, 14) * W, 0.4)
		end
		local wk = (hit and 1 or 0) * (1 - phase(t, D, D + 0.25))
		if well then
			well.CFrame = CFrame.new(s.tip)
			local r = 3.4 * W * wk * (1 + 0.06 * math.sin(t * 30))
			rescale(well, Vector3.new(r, r, r))
		end
		if wellDisk then
			wellDisk.CFrame = CFrame.new(s.tip) * tilt * CFrame.Angles(0, t * 6, 0)
			rescale(wellDisk, Vector3.new(10, 1, 10) * W * wk)
		end
		swirl.Rate = landed and 10 * fx.q or 0
		suck.Rate = landed and 40 * fx.q or 0
		hitLight.Brightness = landed and 3 + math.sin(t * 15) or hitLight.Brightness * 0.85
		if landed and t >= nextRing then
			-- rings of space collapsing inward
			nextRing = t + 0.3
			fx:pulse("Ring", c.Main, CFrame.new(s.tip) * tilt * CFrame.Angles(0, fx.rng:NextNumber(0, 6), 0), Vector3.new(13, 1, 13) * W, Vector3.new(2, 1, 2) * W, 0.3, 0.3)
		end
		return t > D + 0.4
	end)
	fx:when(D + 0.25, function()
		-- the hole closes with a pop
		fx:puff(s.tip, "V_Swirl8", 1, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 10 * W }, { 1, 2 * W } }), Lifetime = NumberRange.new(0.3, 0.3),
			Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 200 },
		})
		fx:pulse("Ring", c.Accent, CFrame.new(s.tip) * tilt, Vector3.new(1, 1, 1) * W, Vector3.new(12, 1, 12) * W, 0.35)
	end)
end

-- A miniature black hole: a black core inside a spinning violet disc and a burning photon ring,
-- trailing dark matter. It lands, swallows the air round it, then bursts.
function Void.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local dark = tone(c.Smoke, -0.3)
	local p = projectile(fx, origin, target, o.speed or 70, 1.8)
	local core = fx:mesh("Orb", dark, p.look, Vector3.new(0.01, 0.01, 0.01), 0)
	local disk = fx:mesh("Disk", c.Main, p.look, Vector3.new(0.01, 1, 0.01), 0.1)
	local disk2 = fx:mesh("Disk", c.Accent, p.look, Vector3.new(0.01, 1, 0.01), 0.2)
	local ring = fx:mesh("Ring", c.Accent, p.look, Vector3.new(0.01, 1, 0.01), 0)
	local halo = fx:emitter(p.ball, "V_Swirl8", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), Size = NumberRange.new(8.5 * W, 9 * W), Transparency = NumberSequence.new(0.55), LightEmission = 0.7,
		Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, -200),
		LockedToPart = true, Flipbook = { mode = "OneShot", fps = 200 }, Rate = 24,
	})
	local smoke = fx:emitter(p.ball, "V_Smoke4", {
		Color = ColorSequence.new(dark), LightEmission = 0, Size = numbers({ { 0, 2 * W }, { 1, 3.5 * W } }),
		Transparency = numbers({ { 0, 0.15 }, { 1, 1 } }), Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 30 }, Rate = 30,
	})
	local motes = fx:emitter(p.ball, "V_Mote", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.5 }, { 1, 0 } }), Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rate = 30,
	})
	local trail = fx:trail(p.ball, "V_Stream", Vector3.new(0, 0.9 * W, 0), Vector3.new(0, -0.9 * W, 0), colors({ { 0, c.Main }, { 1, c.Glow } }), 0.22)
	local light = fx:light(p.ball, c.Main, 14, 2.5)
	local tilt = CFrame.Angles(math.rad(65), 0, math.rad(20))
	p.go(function(t, cf, grow)
		if core then
			core.CFrame = cf
			rescale(core, Vector3.new(2, 2, 2) * W * grow)
		end
		if disk then
			disk.CFrame = cf * tilt * CFrame.Angles(0, t * 10, 0)
			rescale(disk, Vector3.new(6, 1, 6) * W * grow)
		end
		if disk2 then
			disk2.CFrame = cf * tilt * CFrame.Angles(0, -t * 14, 0)
			rescale(disk2, Vector3.new(4, 1, 4) * W * grow)
		end
		if ring then
			ring.CFrame = cf * tilt
			local r = 2.7 * W * grow * (1 + 0.05 * math.sin(t * 40))
			rescale(ring, Vector3.new(r, 1, r))
		end
	end, function(at)
		retire({ core, disk, disk2, ring, halo, smoke, motes, trail, light })
		Void.collapse(fx, at, W)
	end)
end

function Void.collapse(fx, at: Vector3, W: number)
	local c = fx.c
	local dark = tone(c.Smoke, -0.3)
	local hole = fx:mesh("Orb", dark, CFrame.new(at), Vector3.new(0.01, 0.01, 0.01), 0)
	local rim = fx:mesh("Orb", c.Glow, CFrame.new(at), Vector3.new(0.01, 0.01, 0.01), 0.75)
	local disk = fx:mesh("Disk", c.Main, CFrame.new(at), Vector3.new(0.01, 1, 0.01), 0.1)
	fx:puff(at, "V_Swirl8", 1, {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), Size = numbers({ { 0, 12 * W }, { 1, 5 * W } }), Transparency = NumberSequence.new(0.4),
		LightEmission = 0.7, Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0), RotSpeed = NumberRange.new(-400, -400),
		Flipbook = { mode = "OneShot", fps = 140 },
	})
	local suck = fx:holder(CFrame.new(at), Vector3.new(16, 16, 16) * W)
	fx:emitter(suck, "V_Mote", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.3 }, { 1, 0.9 } }), Lifetime = NumberRange.new(0.4, 0.45),
		Speed = NumberRange.new(18 * W, 18 * W), Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 0,
	}):Emit(math.floor(30 * fx.q + 0.5))
	fx:pulse("Ring", c.Main, CFrame.new(at) * CFrame.Angles(math.rad(70), 0, 0.3), Vector3.new(14, 1, 14) * W, Vector3.new(1, 1, 1) * W, 0.35, 0.3)
	fx:pulse("Ring", c.Accent, CFrame.new(at) * CFrame.Angles(0.2, 0, math.rad(-60)), Vector3.new(11, 1, 11) * W, Vector3.new(1, 1, 1) * W, 0.4, 0.3)
	local born = fx.t
	fx:every(function(t)
		local age = t - born
		local r = 5 * W * easeOut(phase(age, 0, 0.15)) * (1 - phase(age, 0.3, 0.45) ^ 2)
		if hole then
			rescale(hole, Vector3.new(r, r, r))
		end
		if rim then
			rescale(rim, Vector3.new(r, r, r) * 1.2)
		end
		if disk then
			disk.CFrame = CFrame.new(at) * CFrame.Angles(math.rad(65), age * 12, math.rad(20))
			rescale(disk, Vector3.new(r, 0.5, r) * 2.4)
		end
		if age >= 0.45 then
			for _, m in { hole, rim, disk } do
				m:Destroy()
			end
			return true
		end
		return false
	end)
	fx:when(born + 0.45, function()
		fx:puff(at, "V_Swirl8", 1, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 4 * W }, { 1, 16 * W } }), Lifetime = NumberRange.new(0.45, 0.45),
			Speed = NumberRange.new(0, 0), RotSpeed = NumberRange.new(200, 200), Flipbook = { mode = "OneShot", fps = 140 },
		})
		fx:puff(at, "V_Smoke4", 12, {
			Color = ColorSequence.new(dark), LightEmission = 0, Size = numbers({ { 0, 3 * W }, { 1, 7 * W } }), Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 18 },
		})
		fx:puff(at, "V_Mote", 30, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.8 }, { 1, 0 } }), Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(16, 30), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		})
		fx:pulse("Ring", c.Accent, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(20, 1, 20) * W, 0.5)
		fx:pulse("Spikes", c.Main, CFrame.new(at) * CFrame.Angles(fx.rng:NextNumber(0, 6), fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(8, 8, 8) * W, 0.22)
		fx:flash(at, c.Main, 28, 8, 0.6)
	end)
end

-- Ultimate: Event Horizon. A black hole tears open ahead: everything is dragged into it, a violet
-- accretion disc spins up, debris spirals in, then it collapses and detonates.
function Void.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 8.2
	local dark = tone(c.Smoke, -0.3)
	local centre = at * CFrame.new(0, 8 * S, -(o.distance or 16) * S)
	local cp = centre.Position
	local tilt = centre * CFrame.Angles(math.rad(18), 0, math.rad(-10))
	local hub = fx:holder(centre)
	fx:sound("Ultimate", hub)
	local core = fx:mesh("Orb", dark, centre, Vector3.new(0.01, 0.01, 0.01), 0)
	local rim = fx:mesh("Orb", c.Glow, centre, Vector3.new(0.01, 0.01, 0.01), 0.8)
	local disk = fx:mesh("Disk", c.Main, tilt, Vector3.new(0.01, 1, 0.01), 0.05)
	local disk2 = fx:mesh("Disk", c.Accent, tilt, Vector3.new(0.01, 1, 0.01), 0.2)
	local photon = fx:mesh("Ring", c.Accent, tilt, Vector3.new(0.01, 1, 0.01), 0)
	local halo = fx:emitter(hub, "V_Swirl8", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(20 * S, 24 * S), Transparency = numbers({ { 0, 1 }, { 0.2, 0.35 }, { 0.8, 0.35 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.2, 1.2), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, -80),
		LockedToPart = true, Flipbook = { mode = "Loop", fps = 24 }, Rate = 0,
	})
	local field = fx:holder(centre, Vector3.new(50, 50, 50) * S)
	local suckMotes = fx:emitter(field, "V_Mote", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 0.5 * S }, { 1, 1.2 * S } }), Lifetime = NumberRange.new(1.2, 1.25),
		Speed = NumberRange.new(20 * S, 20 * S), Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 0,
	})
	local suckSmoke = fx:emitter(field, "V_Smoke4", {
		Color = ColorSequence.new(dark), LightEmission = 0, Size = numbers({ { 0, 6 * S }, { 1, 2 * S } }), Transparency = numbers({ { 0, 1 }, { 0.3, 0.3 }, { 1, 0.6 } }),
		Lifetime = NumberRange.new(1.2, 1.25), Speed = NumberRange.new(20 * S, 20 * S), Rotation = NumberRange.new(0, 360),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Flipbook = { mode = "Loop", fps = 12 }, Rate = 0,
	})
	local light = fx:light(hub, c.Main, 50, 0)
	local rocks = {}
	local nextRock, nextRing = 0.8, 1.0
	local T1 = 6.8
	fx:when(6.9, function()
		fx:puff(cp, "X_Glow", 1, {
			Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 24 * S }, { 1, 50 * S } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0),
		})
		fx:puff(cp, "V_Swirl8", 1, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 10 * S }, { 1, 40 * S } }), Lifetime = NumberRange.new(0.6, 0.6),
			Speed = NumberRange.new(0, 0), RotSpeed = NumberRange.new(150, 150), Flipbook = { mode = "OneShot", fps = 106 },
		})
		fx:puff(cp, "V_Smoke4", 20, {
			Color = ColorSequence.new(dark), LightEmission = 0, Size = numbers({ { 0, 6 * S }, { 1, 14 * S } }), Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.9, 1.3), Speed = NumberRange.new(20 * S, 36 * S), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 14 },
		})
		fx:puff(cp, "V_Mote", 50, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = numbers({ { 0, 1.2 * S }, { 1, 0 } }), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(30 * S, 60 * S), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		})
		fx:pulse("Ring", c.Accent, tilt, Vector3.new(2, 1, 2) * S, Vector3.new(60, 1, 60) * S, 0.7)
		fx:pulse("Ring", c.Main, centre * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(2, 1, 2) * S, Vector3.new(44, 1, 44) * S, 0.6)
		fx:pulse("Spikes", c.Accent, centre, Vector3.new(2, 2, 2) * S, Vector3.new(22, 22, 22) * S, 0.3)
		fx:pulse("RingJag", c.Main, at * CFrame.new(0, 0.2, -(o.distance or 16) * S), Vector3.new(2, 1, 2) * S, Vector3.new(50, 1, 50) * S, 0.8)
		fx:flash(cp, c.Accent, 80, 15, 1.0)
	end)
	fx:every(function(t, dt)
		local form = easeOut(phase(t, 0.3, 1.2))
		local gone = 1 - phase(t, T1, T1 + 0.12) -- the collapse
		local k = form * gone
		local throb = 1 + 0.04 * math.sin(t * 9) + 0.02 * math.sin(t * 23)
		if core then
			local r = 6 * S * k * throb
			rescale(core, Vector3.new(r, r, r))
		end
		if rim then
			local r = 6.9 * S * k * throb
			rescale(rim, Vector3.new(r, r, r))
		end
		if disk then
			disk.CFrame = tilt * CFrame.Angles(0, t * 2.2, 0)
			rescale(disk, Vector3.new(26, 1, 26) * S * k)
		end
		if disk2 then
			disk2.CFrame = tilt * CFrame.Angles(0, -t * 3.1, 0)
			rescale(disk2, Vector3.new(16, 1, 16) * S * k)
		end
		if photon then
			local r = 8 * S * k * throb
			rescale(photon, Vector3.new(r, 1, r))
		end
		local live = t >= 0.2 and t < T1 - 0.4
		halo.Rate = (t >= 0.8 and t < T1) and 3 * fx.q or 0
		suckMotes.Rate = live and 70 * fx.q or 0
		suckSmoke.Rate = live and 14 * fx.q or 0
		light.Brightness = 4 * k
		if t >= nextRing and t < T1 - 0.2 then
			nextRing = t + 0.8
			fx:pulse("Ring", c.Main, tilt * CFrame.Angles(0, fx.rng:NextNumber(0, 6), 0), Vector3.new(40, 1, 40) * S, Vector3.new(6, 1, 6) * S, 0.8, 0.5)
		end
		-- debris spirals in along the disc
		if t >= nextRock and t < T1 - 1.4 then
			nextRock = t + 0.22 / fx.q
			local m = fx:mesh("Rock" .. fx.rng:NextInteger(1, 3), tone(c.Main, -0.65), centre, Vector3.new(0.01, 0.01, 0.01), 0)
			if m then
				m.Material = Enum.Material.SmoothPlastic
				table.insert(rocks, { m = m, born = t, a = fx.rng:NextNumber(0, 6.28), r = fx.rng:NextNumber(18, 24) * S, h = fx.rng:NextNumber(-5, 5) * S, size = fx.rng:NextNumber(1.2, 2.6) * S })
			end
		end
		for i = #rocks, 1, -1 do
			local r = rocks[i]
			local kk = phase(t - r.born, 0, 1.6) ^ 1.5
			local a = r.a + kk * 7
			local rad = r.r * (1 - kk)
			r.m.CFrame = tilt * CFrame.new(math.cos(a) * rad, r.h * (1 - kk), math.sin(a) * rad) * CFrame.Angles(t * 3, t * 2, 0)
			rescale(r.m, Vector3.new(r.size, r.size, r.size) * (1 - kk * 0.85))
			if kk >= 1 or t >= T1 then
				r.m:Destroy()
				table.remove(rocks, i)
			end
		end
		return t > 8
	end)
end

-- ====================================================================== NATURE

local Nature = {}

-- A living beam: a stream of green light wrapped in twisting vines, shedding leaves, petals and
-- glowing spores, a flower of leaves opening at the hands and blossoms bursting where it lands.
function Nature.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.3)
	local core = fx:beam(a0, a1, "N_Stream", { Color = ColorSequence.new(c.Accent), TextureSpeed = 4, TextureLength = 6, ZOffset = 0.3 })
	local body = fx:beam(a0, a1, "N_Stream", {
		Color = colors({ { 0, c.Accent }, { 0.15, c.Main }, { 1, c.Glow } }), TextureSpeed = 2.5, TextureLength = 9,
		LightEmission = 0.35, ZOffset = 0.1, Transparency = NumberSequence.new(0.05),
	})
	local vine = fx:mesh("SpiralThin", c.Glow, s.cf, Vector3.new(1, 1, 1), 0.05)
	local vine2 = fx:mesh("Spiral", c.Main, s.cf, Vector3.new(1, 1, 1), 0.3)
	local leaves = fx:emitter(s.spine, "N_Leaf4", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(0.9 * W, 1.5 * W),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-220, 220), Transparency = numbers({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 35,
	})
	local petals = fx:emitter(s.spine, "N_Petal4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.5, Size = NumberRange.new(0.6 * W, 1.1 * W),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-260, 260), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 18,
	})
	local spores = fx:emitter(s.spine, "N_Spore", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.3, 0.7 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 2, 0), Rate = 30,
	})
	-- a flower of leaves opening round the hands
	local petalsAtHand = {}
	for k = 1, 6 do
		table.insert(petalsAtHand, fx:mesh("Leaf", k % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(0.01, 0.01, 0.01), 0.1))
	end
	local bloom = fx:emitter(s.startPart, "N_Bloom8", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(3.4 * W, 4 * W), Lifetime = NumberRange.new(0.4, 0.4),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "OneShot", fps = 160 }, Rate = 10,
	})
	local hitLight = fx:light(s.endPart, c.Main, 20)
	local beamLight = fx:light(s.spine, c.Main, 14)
	local sprouts = {}
	local nextBloom, nextSprout = 0, 0
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.2))
		local fade = 1 - phase(t, D, D + 0.3)
		s:update(grow)
		local len = s.len * grow
		local mid = s.cf * CFrame.new(0, 0, -len / 2)
		core.Width0, core.Width1 = 0.6 * W * fade, 0.7 * W * fade
		body.Width0 = 2.0 * W * fade
		body.Width1 = (2.6 + 0.3 * math.sin(t * 8)) * W * fade
		body.CurveSize0, body.CurveSize1 = math.sin(t * 5) * 0.5, math.cos(t * 4) * 0.6
		if vine then
			vine.CFrame = mid * CFrame.Angles(0, 0, t * 4)
			rescale(vine, Vector3.new(3 * W * fade, 3 * W * fade, len))
		end
		if vine2 then
			vine2.CFrame = mid * CFrame.Angles(0, 0, -t * 3)
			rescale(vine2, Vector3.new(3.8 * W * fade, 3.8 * W * fade, len))
		end
		local open = easeOut(phase(t, 0, 0.3)) * fade
		for k, m in petalsAtHand do
			if m then
				local a = k / #petalsAtHand * math.pi * 2 + t * 1.5
				local l = 2.6 * W * open
				m.CFrame = s.cf * CFrame.Angles(0, 0, a) * CFrame.Angles(-math.rad(50), 0, 0) * CFrame.new(0, l * 0.5, 0)
				rescale(m, Vector3.new(1.2 * W * open, l, 1))
			end
		end
		local on = t < D
		leaves.Enabled, petals.Enabled, spores.Enabled, bloom.Enabled = on, on, on, on
		beamLight.Brightness = 2.5 * fade
		if grow >= 1 and on then
			hitLight.Brightness = 3.5 + math.sin(t * 12)
			if t >= nextBloom then
				nextBloom = t + 0.22
				fx:puff(s.tip + Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1)) * W, "N_Bloom8", 1, {
					Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(7 * W, 9 * W), Rotation = NumberRange.new(0, 360),
					Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
				})
				fx:puff(s.tip, "N_Leaf4", 6, {
					Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(1 * W, 1.8 * W),
					Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(180, 180), Drag = 3,
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -6, 0),
					Flipbook = { mode = "Random", fps = 1, random = true },
				})
			end
			if t >= nextSprout and #sprouts < 8 then
				-- big leaves sprout out of the impact like a flower opening
				nextSprout = t + 0.15 / fx.q
				local a = #sprouts / 8 * math.pi * 2
				local m = fx:mesh("Leaf", #sprouts % 2 == 0 and c.Main or c.Glow, CFrame.new(s.tip), Vector3.new(0.01, 0.01, 0.01), 0.1)
				if m then
					table.insert(sprouts, { m = m, a = a, born = t })
				end
			end
		else
			hitLight.Brightness *= 0.85
		end
		for _, sp in sprouts do
			local k = backOut(phase(t - sp.born, 0, 0.25)) * (1 - phase(t, D, D + 0.3))
			local l = 4 * W * k
			sp.m.CFrame = CFrame.new(s.tip) * CFrame.Angles(0, sp.a, 0) * CFrame.Angles(-math.rad(60), 0, 0) * CFrame.new(0, l * 0.5, 0)
			rescale(sp.m, Vector3.new(1.8 * W * math.max(k, 0.01), math.max(l, 0.01), 1))
		end
		return t > D + 0.4
	end)
end

-- A seed of light in a leafy shell, leaves orbiting it, trailing petals and spores. It bursts into
-- a giant flower that opens and scatters.
function Nature.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 75, 1.6)
	local core = fx:mesh("Orb", c.Accent, p.look, Vector3.new(0.01, 0.01, 0.01), 0)
	local shell = fx:mesh("Orb", c.Main, p.look, Vector3.new(0.01, 0.01, 0.01), 0.15)
	local orbit = {}
	for k = 1, 5 do
		table.insert(orbit, fx:mesh("Leaf", k % 2 == 0 and c.Main or c.Glow, p.look, Vector3.new(0.01, 0.01, 0.01), 0.05))
	end
	local trail = fx:trail(p.ball, "N_Stream", Vector3.new(0, 0.8 * W, 0), Vector3.new(0, -0.8 * W, 0), colors({ { 0, c.Main }, { 1, c.Glow } }), 0.25)
	local leaves = fx:emitter(p.ball, "N_Leaf4", {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(0.8 * W, 1.3 * W),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-260, 260), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 30,
	})
	local petals = fx:emitter(p.ball, "N_Petal4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.5, Size = NumberRange.new(0.6 * W, 1 * W), Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-260, 260),
		Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 20,
	})
	local spores = fx:emitter(p.ball, "N_Spore", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.3, 0.6 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Rate = 30,
	})
	local light = fx:light(p.ball, c.Main, 14, 2.5)
	p.go(function(t, cf, grow)
		local pulse = 1 + 0.08 * math.sin(t * 25)
		if core then
			core.CFrame = cf
			rescale(core, Vector3.new(1.0, 1.0, 1.0) * W * grow * pulse)
		end
		if shell then
			shell.CFrame = cf * CFrame.Angles(t * 4, t * 6, 0)
			rescale(shell, Vector3.new(2.3, 2.3, 2.3) * W * grow * (2 - pulse))
		end
		for k, m in orbit do
			if m then
				local a = k / #orbit * math.pi * 2 + t * 9
				m.CFrame = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.2 * W, 0.3 * W) * CFrame.Angles(math.rad(70), 0, 0)
				rescale(m, Vector3.new(1, 2.2, 1) * W * grow)
			end
		end
	end, function(at)
		local list = { core, shell, trail, leaves, petals, spores, light }
		for _, m in orbit do
			table.insert(list, m)
		end
		retire(list)
		Nature.bloom(fx, at, W)
	end)
end

function Nature.bloom(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "N_Bloom8", 1, {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(14 * W, 14 * W), Lifetime = NumberRange.new(0.55, 0.55),
		Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "N_Petal4", 30, {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.5, Size = NumberRange.new(0.8 * W, 1.5 * W), Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -4, 0), Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:puff(at, "N_Leaf4", 14, {
		Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(1 * W, 1.8 * W), Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -6, 0), Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:puff(at, "N_Spore", 20, {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.3, 0.9 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180), Drag = 2, Acceleration = Vector3.new(0, 3, 0),
	})
	-- a flower of big leaves opens and fades
	local flower = {}
	for k = 1, 10 do
		table.insert(flower, { m = fx:mesh("Leaf", k % 2 == 0 and c.Main or c.Glow, CFrame.new(at), Vector3.new(0.01, 0.01, 0.01), 0.1), a = k / 10 * math.pi * 2 })
	end
	local born = fx.t
	fx:every(function(t)
		local age = t - born
		local k = backOut(phase(age, 0, 0.22))
		for _, f in flower do
			if f.m then
				local l = 5 * W * k
				f.m.CFrame = CFrame.new(at) * CFrame.Angles(0, f.a, 0) * CFrame.Angles(-math.rad(72), 0, 0) * CFrame.new(0, l * 0.5, 0)
				rescale(f.m, Vector3.new(2.2 * W * math.max(k, 0.01), math.max(l, 0.01), 1))
				f.m.Transparency = 0.1 + 0.9 * phase(age, 0.6, 1.1)
			end
		end
		return age > 1.1
	end)
	fx:pulse("Ring", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(16, 1, 16) * W, 0.5)
	fx:flash(at, c.Main, 24, 6, 0.6)
end

-- Ultimate: Sacred Grove. Spores of light rise round the user, then glowing trees burst from the
-- ground in a ring, their canopies bloom and pulse with light, then dissolve into a storm of petals.
function Nature.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 6.2
	fx:sound("Ultimate", fx:holder(at * CFrame.new(0, 3, 0)))
	local ground = fx:holder(at * CFrame.new(0, 0.2, 0), Vector3.new(18, 0.5, 18) * S)
	local rise = fx:emitter(ground, "N_Spore", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0 }, { 0.2, 0.8 * S }, { 1, 0 } }), Lifetime = NumberRange.new(1.2, 2.0),
		Speed = NumberRange.new(2, 5), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15), Rate = 0,
	})
	local groundRing = fx:mesh("Ring", c.Main, at * CFrame.new(0, 0.1, 0), Vector3.new(0.01, 1, 0.01), 0.2)
	local groundRing2 = fx:mesh("Ring", c.Accent, at * CFrame.new(0, 0.12, 0), Vector3.new(0.01, 1, 0.01), 0.3)
	local trees = {}
	for k = 1, 6 do
		local a = (k - 0.5) / 6 * math.pi * 2
		local r = 8 * S
		local base = at * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, fx.rng:NextNumber(0, 6.28), 0)
		local tree = {
			base = base, t0 = 0.6 + (k - 1) * 0.18, h = fx.rng:NextNumber(7, 9) * S,
			trunk = fx:mesh("Trunk", c.Glow, base, Vector3.new(0.01, 0.01, 0.01), 0.05),
			canopy = fx:mesh("Canopy", c.Main, base, Vector3.new(0.01, 0.01, 0.01), 0.3),
			inner = fx:mesh("Canopy", c.Accent, base, Vector3.new(0.01, 0.01, 0.01), 0.15),
		}
		local top = fx:holder(base * CFrame.new(0, tree.h, 0), Vector3.new(5, 2, 5) * S)
		tree.top = top
		tree.leaves = fx:emitter(top, "N_Leaf4", {
			Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(0.9 * S, 1.4 * S),
			Lifetime = NumberRange.new(1.4, 2.0), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), Acceleration = Vector3.new(0, -3, 0),
			Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 0,
		})
		tree.petals = fx:emitter(top, "N_Petal4", {
			Color = ColorSequence.new(c.Accent), LightEmission = 0.5, Size = NumberRange.new(0.6 * S, 1 * S), Lifetime = NumberRange.new(1.4, 2.2),
			Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-160, 160), Acceleration = Vector3.new(0, -2.5, 0), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 0,
		})
		tree.light = fx:light(top, c.Main, 18, 0)
		table.insert(trees, tree)
		fx:when(tree.t0, function()
			fx:puff(base.Position, "N_Bloom8", 1, {
				Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(6 * S, 6 * S), Lifetime = NumberRange.new(0.45, 0.45),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 140 },
			})
			fx:pulse("Ring", c.Main, base * CFrame.new(0, 0.15, 0), Vector3.new(1, 1, 1) * S, Vector3.new(7, 1, 7) * S, 0.4)
		end)
	end
	fx:when(0.05, function()
		fx:puff(at.Position + Vector3.new(0, 1, 0), "N_Bloom8", 1, {
			Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(9 * S, 9 * S), Lifetime = NumberRange.new(0.5, 0.5),
			Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
		})
	end)
	fx:when(4.8, function()
		for _, tree in trees do
			local p = tree.top.Position
			fx:puff(p, "N_Petal4", 30, {
				Color = ColorSequence.new(c.Accent), LightEmission = 0.5, Size = NumberRange.new(0.8 * S, 1.5 * S), Lifetime = NumberRange.new(1.0, 1.6),
				Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Drag = 2, Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -2, 0), Flipbook = { mode = "Random", fps = 1, random = true },
			})
			fx:puff(p, "N_Leaf4", 10, {
				Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.3, Size = NumberRange.new(1 * S, 1.6 * S), Lifetime = NumberRange.new(1.0, 1.4),
				Speed = NumberRange.new(5, 10), SpreadAngle = Vector2.new(180, 180), Drag = 2, Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -4, 0), Flipbook = { mode = "Random", fps = 1, random = true },
			})
			fx:puff(p, "N_Bloom8", 1, {
				Color = colors({ { 0, c.Main }, { 1, c.Glow } }), LightEmission = 0.5, Size = NumberRange.new(10 * S, 10 * S), Lifetime = NumberRange.new(0.5, 0.5),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
			})
		end
		fx:flash(at.Position + Vector3.new(0, 5, 0), c.Accent, 40, 6, 0.8)
	end)
	fx:every(function(t)
		local shimmer = easeOut(phase(t, 0, 0.6)) * (1 - phase(t, 4.8, 5.6))
		rise.Rate = t < 4.8 and 40 * fx.q or 0
		if groundRing then
			local r = 20 * S * shimmer
			rescale(groundRing, Vector3.new(r, 1, r))
		end
		if groundRing2 then
			local r = (14 + math.sin(t * 3)) * S * shimmer
			groundRing2.CFrame = at * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, t, 0)
			rescale(groundRing2, Vector3.new(r, 1, r))
		end
		local breath = 1 + 0.05 * math.sin(t * 3.2)
		local dissolve = phase(t, 4.8, 5.5)
		for i, tree in trees do
			local g = easeOut(phase(t, tree.t0, tree.t0 + 1.0))
			local h = tree.h * g * (1 - 0.4 * dissolve)
			rooted(tree.trunk, tree.base, 3 * S * (1 - 0.4 * dissolve), h, 3 * S * (1 - 0.4 * dissolve))
			if tree.trunk then
				tree.trunk.Transparency = 0.05 + 0.95 * dissolve
			end
			local cg = backOut(phase(t, tree.t0 + 0.7, tree.t0 + 1.2)) * (1 - 0.5 * dissolve)
			local cs = 6.5 * S * math.max(cg, 0.001) * (cg > 0.9 and breath or 1)
			local cpos = tree.base * CFrame.new(0, h * 0.9 + cs * 0.25, 0) * CFrame.Angles(0, t * 0.3 + i, 0)
			if tree.canopy then
				tree.canopy.CFrame = cpos
				rescale(tree.canopy, Vector3.new(cs, cs * 0.8, cs))
				tree.canopy.Transparency = 0.3 + 0.7 * dissolve
			end
			if tree.inner then
				tree.inner.CFrame = cpos * CFrame.Angles(0, 1, 0)
				rescale(tree.inner, Vector3.new(cs, cs * 0.8, cs) * 0.6)
				tree.inner.Transparency = 0.15 + 0.85 * dissolve
			end
			tree.top.CFrame = cpos
			local alive = cg > 0.5 and t < 4.8
			tree.leaves.Rate = alive and 3 * fx.q or 0
			tree.petals.Rate = alive and 5 * fx.q or 0
			tree.light.Brightness = 2.5 * cg * (cg > 0.9 and breath or 1) * (1 - dissolve)
		end
		return t > 6
	end)
end

-- ====================================================================== ICE

local Ice = {}

-- A freezing ray: a white core in a pale blue stream, ice crystals growing out of the air along its
-- path, frost mist and snowflakes, a crown of ice at the hands; the impact freezes into a cluster of
-- spikes. When it stops, every crystal shatters.
function Ice.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.4)
	local core = fx:beam(a0, a1, "I_Stream", { Color = ColorSequence.new(c.Accent), TextureSpeed = 4, TextureLength = 6, ZOffset = 0.3 })
	local body = fx:beam(a0, a1, "I_Stream", {
		Color = colors({ { 0, c.Accent }, { 0.15, c.Main }, { 1, c.Glow } }), TextureSpeed = 3, TextureLength = 9,
		LightEmission = 0.4, ZOffset = 0.1, Transparency = NumberSequence.new(0.05),
	})
	local haze = fx:beam(a0, a1, "I_Stream", { Color = ColorSequence.new(c.Glow), TextureSpeed = -1.5, TextureLength = 12, Transparency = NumberSequence.new(0.5), ZOffset = -0.1 })
	local mist = fx:emitter(s.spine, "I_Mist4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 2 * W }, { 1, 4 * W } }),
		Transparency = numbers({ { 0, 0.5 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 20 }, Rate = 15,
	})
	local flakes = fx:emitter(s.spine, "I_Flake", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0.5 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-180, 180),
		Drag = 2, Acceleration = Vector3.new(0, -3, 0), Rate = 30,
	})
	local frost = fx:emitter(s.startPart, "I_Frost8", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(3.6 * W, 4.2 * W), Lifetime = NumberRange.new(0.4, 0.4),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "OneShot", fps = 160 }, Rate = 12,
	})
	local crown = {}
	for k = 1, 6 do
		table.insert(crown, fx:mesh("Crystal" .. (k % 3 + 1), k % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(0.01, 0.01, 0.01), 0.1))
	end
	local hitLight = fx:light(s.endPart, c.Main, 20)
	local beamLight = fx:light(s.spine, c.Main, 14)
	local grown = {}
	local nextCrystal, nextFrost = 0, 0
	local cluster = false
	fx:when(D, function()
		-- everything shatters
		for i, g in grown do
			if i % 3 == 0 then
				fx:puff(g.m.Position, "I_Shard4", 5, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.6 * W, 1.2 * W), Lifetime = NumberRange.new(0.4, 0.7),
					Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true },
				})
			end
		end
		fx:debris({ "Shard1", "Shard2" }, c.Accent, s.tip, 6, 22, 1.4 * W, 0.8)
	end)
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.25))
		local fade = 1 - phase(t, D, D + 0.25)
		s:update(grow)
		core.Width0, core.Width1 = 0.55 * W * fade, 0.65 * W * fade
		body.Width0, body.Width1 = 2.0 * W * fade, 2.4 * W * fade
		haze.Width0, haze.Width1 = 3.0 * W * fade, 3.6 * W * fade
		for k, m in crown do
			if m then
				local a = k / #crown * math.pi * 2 + t * 0.8
				local l = 2.2 * W * easeOut(phase(t, 0, 0.2)) * fade
				m.CFrame = alongY(s.cf * CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(35), 0, 0)) * CFrame.new(0, l * 0.5, 0)
				rescale(m, Vector3.new(4 * W, math.max(l, 0.01), 4 * W))
			end
		end
		local on = t < D
		mist.Enabled, flakes.Enabled, frost.Enabled = on, on, on
		beamLight.Brightness = 2.5 * fade
		-- crystals freeze out of the air along the path
		if on and t >= nextCrystal and #grown < 26 * fx.q then
			nextCrystal = t + 0.05 / fx.q
			local u = fx.rng:NextNumber(0.08, 0.95) * grow
			local a = fx.rng:NextNumber(0, 6.28)
			local out = (s.cf * CFrame.Angles(0, 0, a)).UpVector
			local p = s:at(u) + out * 0.6 * W
			local cf = alongY(CFrame.lookAt(p, p + out + s.cf.LookVector * fx.rng:NextNumber(0.2, 0.9)))
			local m = fx:mesh("Crystal" .. fx.rng:NextInteger(1, 3), fx.rng:NextNumber() < 0.6 and c.Main or c.Accent, cf, Vector3.new(0.01, 0.01, 0.01), 0.15)
			if m then
				table.insert(grown, { m = m, cf = cf, born = t, len = fx.rng:NextNumber(1.5, 3.5) * W })
			end
		end
		for _, g in grown do
			local k = easeOut(phase(t - g.born, 0, 0.15))
			rescale(g.m, Vector3.new(5 * W * k, g.len * k, 5 * W * k))
			g.m.CFrame = g.cf * CFrame.new(0, g.len * k * 0.4, 0)
			g.m.Transparency = 0.15 + 0.85 * phase(t, D, D + 0.12)
		end
		if grow >= 1 and on then
			hitLight.Brightness = 3 + 0.6 * math.sin(t * 14)
			if not cluster then
				cluster = true
				fx:crystals(s.tip, 7, 4.5 * W, 1.2 * W, c.Main, c.Accent, D - t, 1.0)
			end
			if t >= nextFrost then
				nextFrost = t + 0.2
				fx:puff(s.tip, "I_Frost8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(7 * W, 9 * W), Rotation = NumberRange.new(0, 360),
					Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 140 },
				})
				fx:puff(s.tip, "I_Mist4", 2, {
					Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 3 * W }, { 1, 6 * W } }),
					Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(2, 5),
					SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 16 },
				})
				fx:puff(s.tip, "I_Shard4", 4, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.6 * W, 1.2 * W), Lifetime = NumberRange.new(0.3, 0.5),
					Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -20, 0), Flipbook = { mode = "Random", fps = 1, random = true },
				})
			end
		else
			hitLight.Brightness *= 0.85
		end
		return t > D + 0.4
	end)
end

-- An ice spear: a long faceted crystal with a glowing heart, spinning slowly, trailing frost and
-- snowflakes. It shatters into flying shards and a cluster of ice spikes.
function Ice.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 95, 1.8)
	local spear = fx:mesh("Crystal1", c.Main, alongY(p.look), Vector3.new(0.01, 0.01, 0.01), 0.25)
	local heart = fx:mesh("Crystal3", c.Accent, alongY(p.look), Vector3.new(0.01, 0.01, 0.01), 0)
	local trail = fx:trail(p.ball, "I_Stream", Vector3.new(0, 0.6 * W, 0), Vector3.new(0, -0.6 * W, 0), colors({ { 0, c.Accent }, { 1, c.Main } }), 0.25)
	local mist = fx:emitter(p.ball, "I_Mist4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 1.4 * W }, { 1, 3 * W } }),
		Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 24 }, Rate = 24,
	})
	local flakes = fx:emitter(p.ball, "I_Flake", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0.5 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-180, 180), Rate = 30,
	})
	local light = fx:light(p.ball, c.Main, 14, 2.5)
	p.go(function(t, cf, grow)
		if spear then
			spear.CFrame = alongY(cf) * CFrame.Angles(0, t * 4, 0)
			rescale(spear, Vector3.new(8, 5, 8) * W * grow)
		end
		if heart then
			heart.CFrame = alongY(cf) * CFrame.Angles(0, -t * 6, 0)
			rescale(heart, Vector3.new(4.5, 3.6, 4.5) * W * grow)
		end
	end, function(at)
		retire({ spear, heart, trail, mist, flakes, light })
		Ice.shatter(fx, at, W)
	end)
end

function Ice.shatter(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "I_Frost8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(13 * W, 13 * W), Lifetime = NumberRange.new(0.55, 0.55),
		Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "I_Shard4", 24, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(0.8 * W, 1.6 * W), Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(14, 28), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:puff(at, "I_Mist4", 8, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 4 * W }, { 1, 8 * W } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 12 },
	})
	fx:puff(at, "I_Flake", 16, {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0.7 * W }, { 1, 0 } }), Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360),
	})
	fx:debris({ "Shard1", "Shard2" }, c.Accent, at, 8, 24, 1.4 * W, 0.9)
	fx:crystals(at, 6, 4 * W, 1.1 * W, c.Main, c.Accent, 0.9)
	fx:pulse("Ring", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(15, 1, 15) * W, 0.5)
	fx:flash(at, c.Main, 24, 7, 0.6)
end

-- Ultimate: Glacier Wall. A stomp sends frost racing over the ground, then a wall of ice erupts
-- section by section ahead of the user, bristling with spikes, mist rolling at its base and snow
-- falling, until the whole wall shatters.
function Ice.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 7.2
	local dist = (o.distance or 14) * S
	fx:sound("Ultimate", fx:holder(at * CFrame.new(0, 2, -dist * 0.6)))
	local shardCol = colors({ { 0, c.Accent }, { 1, c.Main } })
	-- the stomp
	fx:pulse("RingJag", c.Main, at * CFrame.new(0, 0.1, 0), Vector3.new(1, 1, 1) * S, Vector3.new(14, 1, 14) * S, 0.5)
	fx:puff(at.Position, "I_Frost8", 1, {
		Color = shardCol, Size = NumberRange.new(10 * S, 10 * S), Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0),
		Flipbook = { mode = "OneShot", fps = 128 },
	})
	fx:puff(at.Position, "I_Mist4", 10, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 3 * S }, { 1, 7 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(8, 14), SpreadAngle = Vector2.new(80, 5),
		EmissionDirection = Enum.NormalId.Top, Drag = 3, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 14 },
	})
	fx:crystals(at.Position, 5, 2.5 * S, 0.8 * S, c.Main, c.Accent, 1.2, 1.2)
	-- the wall
	local sections = {}
	for k = 0, 6 do
		local base = at * CFrame.new((k - 3) * 3.2 * S, 0, -dist) * CFrame.Angles(0, fx.rng:NextNumber(-0.25, 0.25), fx.rng:NextNumber(-0.06, 0.06))
		local sec = {
			base = base, t0 = 1.2 + k * 0.2, h = fx.rng:NextNumber(9, 12) * S,
			m = fx:mesh("Slab" .. (k % 2 + 1), c.Main, base, Vector3.new(0.01, 0.01, 0.01), 0.1),
		}
		table.insert(sections, sec)
		fx:when(sec.t0, function()
			local p = base.Position
			fx:puff(p + Vector3.new(0, 2, 0), "I_Shard4", 10, {
				Color = shardCol, Size = NumberRange.new(0.8 * S, 1.6 * S), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(10, 20),
				SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true },
			})
			fx:puff(p, "I_Mist4", 3, {
				Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 4 * S }, { 1, 8 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(90, 10), Rotation = NumberRange.new(0, 360),
				Flipbook = { mode = "OneShot", fps = 14 },
			})
			fx:pulse("Ring", c.Accent, base * CFrame.new(0, 0.15, 0), Vector3.new(1, 1, 1) * S, Vector3.new(8, 1, 8) * S, 0.35)
			fx:crystals((base * CFrame.new(0, 0, 1.6 * S)).Position, 2, 3.5 * S, 1 * S, c.Main, c.Accent, 5.4 - sec.t0, 0.9)
		end)
	end
	-- frost racing from the stomp to the wall
	local frostLine = {}
	local nextFrost = 0.4
	local wallCentre = at * CFrame.new(0, 0, -dist)
	local mistBase = fx:holder(wallCentre * CFrame.new(0, 0.5, 1.5 * S), Vector3.new(24, 1, 3) * S)
	local mist = fx:emitter(mistBase, "I_Mist4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0.2, Size = numbers({ { 0, 4 * S }, { 1, 8 * S } }), Transparency = numbers({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.6, 2.2), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Back, SpreadAngle = Vector2.new(40, 5),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20), Flipbook = { mode = "Loop", fps = 8 }, Rate = 0,
	})
	local sky = fx:holder(at * CFrame.new(0, 16 * S, -dist * 0.6), Vector3.new(30, 1, 22) * S)
	local snow = fx:emitter(sky, "I_Flake", {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(0.4 * S, 0.8 * S), Lifetime = NumberRange.new(3, 4),
		Speed = NumberRange.new(3, 5), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(20, 20),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), Rate = 0,
	})
	local light = fx:light(fx:holder(wallCentre * CFrame.new(0, 5 * S, 2 * S)), c.Main, 40, 0)
	fx:when(5.4, function()
		-- the shatter
		for _, sec in sections do
			local mid = sec.base * CFrame.new(0, sec.h * 0.5, 0)
			fx:debris({ "Shard1", "Shard2" }, c.Main, mid.Position, 5, 26, 2.2 * S, 1.2, nil, 0.3)
			fx:puff(mid.Position, "I_Shard4", 12, {
				Color = shardCol, Size = NumberRange.new(1 * S, 2 * S), Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(12, 26),
				SpreadAngle = Vector2.new(180, 180), Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
				Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true },
			})
			fx:puff(mid.Position, "I_Frost8", 1, {
				Color = shardCol, Size = NumberRange.new(10 * S, 10 * S), Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0),
				Flipbook = { mode = "OneShot", fps = 128 },
			})
			if sec.m then
				sec.m:Destroy()
				sec.m = nil
			end
		end
		for _, f in frostLine do
			if f.m then
				f.m:Destroy()
				f.m = nil
			end
		end
		fx:pulse("Ring", c.Accent, wallCentre * CFrame.new(0, 0.2, 0), Vector3.new(4, 1, 4) * S, Vector3.new(44, 1, 44) * S, 0.6)
		fx:flash((wallCentre * CFrame.new(0, 5, 0)).Position, c.Accent, 60, 10, 0.7)
	end)
	fx:every(function(t)
		if t >= nextFrost and t < 1.2 then
			nextFrost = t + 0.05 / fx.q
			local d = dist * phase(t, 0.4, 1.2)
			local p = (at * CFrame.new(fx.rng:NextNumber(-1.5, 1.5) * S, 0, -d)).Position
			fx:puff(p, "I_Frost8", 1, {
				Color = shardCol, Size = NumberRange.new(3 * S, 4 * S), Rotation = NumberRange.new(0, 360), Lifetime = NumberRange.new(0.4, 0.4),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
			})
			local dir = Vector3.new(fx.rng:NextNumber(-0.6, 0.6), 1, fx.rng:NextNumber(-0.6, 0.6)).Unit
			local cf = alongY(CFrame.lookAt(p, p + dir))
			local m = fx:mesh("Crystal" .. fx.rng:NextInteger(1, 3), fx.rng:NextNumber() < 0.5 and c.Main or c.Accent, cf, Vector3.new(0.01, 0.01, 0.01), 0.1)
			if m then
				table.insert(frostLine, { m = m, cf = cf, born = t, len = fx.rng:NextNumber(1.2, 2.6) * S })
			end
		end
		for _, f in frostLine do
			if f.m then
				local k = easeOut(phase(t - f.born, 0, 0.12))
				rescale(f.m, Vector3.new(4 * S * k, f.len * k, 4 * S * k))
				f.m.CFrame = f.cf * CFrame.new(0, f.len * k * 0.35, 0)
			end
		end
		for _, sec in sections do
			if sec.m then
				local k = backOut(phase(t, sec.t0, sec.t0 + 0.25))
				local shimmer = t > 2.6 and 0.06 * math.sin(t * 5 + sec.t0 * 9) or 0
				rooted(sec.m, sec.base, 3.6 * S, sec.h * math.max(k, 0.001), 2.2 * S)
				sec.m.Transparency = 0.1 + shimmer
			end
		end
		local cold = t >= 2.0 and t < 5.4
		mist.Rate = cold and 14 * fx.q or 0
		snow.Rate = cold and 40 * fx.q or 0
		light.Brightness = 3 * phase(t, 1.2, 2.4) * (1 - phase(t, 5.4, 6.0))
		return t > 7
	end)
end

-- ====================================================================== WIND

local Wind = {}

-- A gale beam: several streaks of wind spiralling round each other, crescent blades swirling along
-- it, rings of pressure racing down it; the impact explodes into slashing crescents and dust.
function Wind.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.0)
	local streaks = {}
	for i, spec in { { 1.2, 9, 0.1 }, { 2.2, 7, 0.25 }, { 3.0, 8, 0.4 }, { 3.8, 6, 0.55 } } do
		table.insert(streaks, {
			w = spec[1],
			b = fx:beam(a0, a1, "W_Stream", {
				Color = i == 1 and ColorSequence.new(c.Accent) or colors({ { 0, c.Accent }, { 1, c.Main } }),
				Transparency = numbers({ { 0, spec[3] }, { 0.85, spec[3] }, { 1, 0.8 } }), TextureSpeed = spec[2], TextureLength = 10 + i * 2,
				LightEmission = 0.6, ZOffset = 0.3 - 0.1 * i,
			}),
		})
	end
	local blades = {}
	for i = 1, 6 do
		table.insert(blades, { m = fx:mesh("Crescent", i % 2 == 0 and c.Main or c.Accent, s.cf, Vector3.new(0.01, 1, 0.01), 0.15), u = (i - 1) / 6, spin = (i % 2 == 0 and 1 or -1) * 9 })
	end
	local rings = {}
	for i = 1, 4 do
		table.insert(rings, { m = fx:mesh("Ring", c.Accent, s.cf, Vector3.new(0.01, 1, 0.01), 0.6), u = (i - 1) / 4 })
	end
	local swirl = fx:emitter(s.spine, "W_Swirl4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(2 * W, 3.5 * W),
		Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.35, 0.5), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(300, 500),
		Flipbook = { mode = "OneShot", fps = 40 }, Rate = 20,
	})
	local muzzle = fx:emitter(s.startPart, "W_Swirl4", {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(3.2 * W, 3.8 * W), Transparency = NumberSequence.new(0.2),
		Lifetime = NumberRange.new(0.25, 0.25), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(600, 700),
		LockedToPart = true, Flipbook = { mode = "OneShot", fps = 64 }, Rate = 14,
	})
	local dust = fx:emitter(s.endPart, "W_Dust4", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 3 * W }, { 1, 7 * W } }),
		Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 20), Drag = 3, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 20 }, Rate = 0,
	})
	local hitLight = fx:light(s.endPart, c.Main, 16)
	local nextSlash, nextRing, nextPuff = 0, 0, 0
	fx:every(function(t, dt)
		local grow = easeOut(phase(t, 0, 0.12))
		local fade = 1 - phase(t, D, D + 0.2)
		s:update(grow)
		local len = s.len * grow
		for i, st in streaks do
			st.b.Width0 = st.w * 0.7 * W * fade
			st.b.Width1 = (st.w + 0.5 * math.sin(t * (8 + i * 2) + i)) * W * fade
			st.b.CurveSize0 = math.sin(t * 9 + i * 1.7) * 1.2
			st.b.CurveSize1 = math.cos(t * 8 + i * 2.3) * 1.4
		end
		for _, b in blades do
			if b.m then
				b.u = (b.u + dt * 1.6) % 1
				b.m.CFrame = s.cf * CFrame.new(0, 0, -len * b.u) * CFrame.Angles(0, 0, t * b.spin + b.u * 6) * CFrame.Angles(math.pi / 2, 0, 0)
				local sz = 4.5 * W * fade * math.sin(math.pi * b.u) ^ 0.3
				rescale(b.m, Vector3.new(sz, 1, sz))
			end
		end
		for _, r in rings do
			if r.m then
				r.u = (r.u + dt * 2.2) % 1
				r.m.CFrame = s.cf * CFrame.new(0, 0, -len * r.u) * CFrame.Angles(math.pi / 2, 0, 0)
				local sz = (2.5 + 2 * r.u) * W * fade
				rescale(r.m, Vector3.new(sz, 1, sz))
				r.m.Transparency = 0.5 + 0.5 * r.u
			end
		end
		local on = t < D
		swirl.Enabled, muzzle.Enabled = on, on
		if on and t >= nextRing then
			nextRing = t + 0.25
			fx:pulse("Ring", c.Accent, s.cf * CFrame.new(0, 0, -1) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(1, 1, 1) * W, Vector3.new(6, 1, 6) * W, 0.3, 0.4)
		end
		if grow >= 1 and on then
			dust.Rate = 16 * fx.q
			hitLight.Brightness = 2
			if t >= nextSlash then
				nextSlash = t + 0.18
				fx:puff(s.tip, "W_Crescent8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(6 * W, 8 * W), Rotation = NumberRange.new(0, 360),
					Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
				})
			end
			if t >= nextPuff then
				nextPuff = t + 0.3
				fx:pulse("Ring", c.Main, CFrame.new(s.tip), Vector3.new(1, 1, 1) * W, Vector3.new(12, 1, 12) * W, 0.35, 0.3)
			end
		else
			dust.Rate = 0
			hitLight.Brightness *= 0.85
		end
		return t > D + 0.3
	end)
end

-- A crescent air blade: a flat glowing sickle slicing forward with a sheet of wind streaming off it.
-- It bursts into a whirl of slashes, swirls and dust.
function Wind.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 110, 1.4)
	local blade = fx:mesh("Crescent", c.Main, p.look, Vector3.new(0.01, 1, 0.01), 0.1)
	local edge = fx:mesh("Crescent", c.Accent, p.look, Vector3.new(0.01, 1, 0.01), 0.05)
	local sheet = fx:trail(p.ball, "W_Stream", Vector3.new(-3 * W, 0, 0.5 * W), Vector3.new(3 * W, 0, 0.5 * W), colors({ { 0, c.Accent }, { 1, c.Main } }), 0.18)
	local swirl = fx:emitter(p.ball, "W_Swirl4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(1.6 * W, 2.6 * W),
		Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(400, 600),
		Flipbook = { mode = "OneShot", fps = 40 }, Rate = 24,
	})
	local light = fx:light(p.ball, c.Main, 12, 1.5)
	p.go(function(t, cf, grow)
		local roll = CFrame.Angles(0, 0, math.sin(t * 6) * 0.15)
		if blade then
			blade.CFrame = cf * roll
			rescale(blade, Vector3.new(7, 1, 3.5) * W * grow)
		end
		if edge then
			edge.CFrame = cf * roll * CFrame.new(0, 0.05, -0.3 * W)
			rescale(edge, Vector3.new(5.6, 1, 2.6) * W * grow)
		end
	end, function(at)
		retire({ blade, edge, sheet, swirl, light })
		Wind.burst(fx, at, W)
	end)
end

function Wind.burst(fx, at: Vector3, W: number)
	local c = fx.c
	for k = 1, 3 do
		fx:puff(at, "W_Crescent8", 1, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new((9 + 2 * k) * W, (9 + 2 * k) * W), Rotation = NumberRange.new(0, 360),
			Lifetime = NumberRange.new(0.4 + 0.05 * k, 0.4 + 0.05 * k), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 140 },
		})
	end
	fx:puff(at, "W_Swirl4", 10, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(2.5 * W, 4 * W),
		Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(400, 600),
		Flipbook = { mode = "OneShot", fps = 32 },
	})
	fx:puff(at, "W_Dust4", 12, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 3 * W }, { 1, 8 * W } }),
		Transparency = numbers({ { 0, 0.25 }, { 1, 1 } }), Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(180, 30), Drag = 3, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 16 },
	})
	fx:pulse("Ring", c.Accent, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(16, 1, 16) * W, 0.4, 0.2)
	fx:pulse("Ring", c.Main, CFrame.new(at) * CFrame.Angles(math.pi / 2, fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(12, 1, 12) * W, 0.35, 0.3)
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2 + fx.rng:NextNumber(0, 1)
		fx:pulse("Crescent", k % 2 == 0 and c.Main or c.Accent, CFrame.new(at) * CFrame.Angles(fx.rng:NextNumber(-0.6, 0.6), a, fx.rng:NextNumber(-0.6, 0.6)), Vector3.new(1, 1, 0.5) * W, Vector3.new(14, 1, 7) * W, 0.35)
	end
	fx:flash(at, c.Main, 18, 3, 0.4)
end

-- Ultimate: Thunderclap. The user claps; the air itself explodes: pressure shells balloon out,
-- rings of compressed air blast forward, crescents slash outward along the ground in a ring of dust.
function Wind.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 2.6
	local hands = at * CFrame.new(0, 3.2 * S, -1.2 * S)
	fx:sound("Ultimate", fx:holder(hands))
	fx:puff(hands.Position, "W_Swirl4", 4, {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 4 * S }, { 1, 1 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.15, 0.15), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-900, -700),
		Flipbook = { mode = "OneShot", fps = 100 },
	})
	fx:when(0.15, function()
		local hp = hands.Position
		fx:puff(hp, "W_Crescent8", 2, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(9 * S, 12 * S), Rotation = NumberRange.new(0, 360),
			Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 160 },
		})
		fx:puff(hp, "W_Swirl4", 14, {
			Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(3 * S, 5 * S),
			Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(14 * S, 26 * S),
			SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(400, 600),
			Flipbook = { mode = "OneShot", fps = 32 },
		})
		-- the pressure shells
		fx:pulse("Orb", c.Accent, hands, Vector3.new(1, 1, 1) * S, Vector3.new(26, 26, 26) * S, 0.5, 0.75)
		fx:when(0.23, function()
			fx:pulse("Orb", c.Main, hands, Vector3.new(2, 2, 2) * S, Vector3.new(40, 40, 40) * S, 0.8, 0.85)
		end)
		-- rings of compressed air blasting forward
		for k = 0, 3 do
			fx:when(0.15 + 0.03 * k, function()
				fx:pulse("Ring", k % 2 == 0 and c.Accent or c.Main, hands * CFrame.new(0, 0, -(3 + k * 5) * S) * CFrame.Angles(math.pi / 2, 0, 0),
					Vector3.new(3, 1, 3) * S, Vector3.new(10 + k * 4, 1, 10 + k * 4) * S, 0.45, 0.15)
			end)
		end
		-- along the ground
		fx:pulse("RingJag", c.Main, at * CFrame.new(0, 0.15, 0), Vector3.new(1, 1, 1) * S, Vector3.new(46, 1, 46) * S, 0.7)
		fx:pulse("Ring", c.Accent, at * CFrame.new(0, 0.2, 0), Vector3.new(1, 1, 1) * S, Vector3.new(30, 1, 30) * S, 0.5)
		local n = math.max(6, math.floor(12 * fx.q))
		for k = 1, n do
			local a = k / n * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local p = at.Position + out * 2.5 * S + Vector3.new(0, 0.5, 0)
			local h = fx:holder(CFrame.lookAt(p, p + out))
			fx:emitter(h, "W_Dust4", {
				Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 3 * S }, { 1, 9 * S } }),
				Transparency = numbers({ { 0, 0.25 }, { 1, 1 } }), Lifetime = NumberRange.new(0.9, 1.3), Speed = NumberRange.new(26 * S, 34 * S),
				EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(12, 6), Drag = 3, Rotation = NumberRange.new(0, 360),
				Flipbook = { mode = "OneShot", fps = 14 }, Rate = 0,
			}):Emit(2)
		end
		for k = 1, 6 do
			local a = k / 6 * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local p = at.Position + out * 3 * S + Vector3.new(0, 1, 0)
			fx:pulse("Crescent", k % 2 == 0 and c.Main or c.Accent, CFrame.lookAt(p, p + out) * CFrame.new(0, 0, -4 * S), Vector3.new(2, 1, 1) * S, Vector3.new(16, 1, 8) * S, 0.4)
		end
		fx:flash(hp, c.Accent, 40, 8, 0.5)
	end)
	fx:every(function(t)
		return t > 2.4
	end)
end

-- ====================================================================== EARTH

local Earth = {}

-- a rock mesh with molten seams: a stone hull with a glowing copy turned inside it, whose corners
-- poke through as cracks of lava
local function boulder(fx, cf: CFrame, size: number)
	local i = fx.rng:NextInteger(1, 3)
	local rock = fx:mesh("Rock" .. i, tone(fx.c.Main, fx.rng:NextNumber(-0.15, 0.1)), cf, Vector3.new(size, size, size), 0)
	if rock then
		rock.Material = Enum.Material.SmoothPlastic
	end
	local seam = fx:mesh("Rock" .. (i % 3 + 1), fx.c.Glow, cf, Vector3.new(size, size, size) * 0.93, 0)
	return rock, seam
end

-- a jagged spire that erupts from the ground, holds and sinks back
function Earth.spire(fx, base: CFrame, w: number, h: number, sink: number)
	local c = fx.c
	local m = fx:mesh("Spire", c.Main, base, Vector3.new(0.01, 0.01, 0.01), 0)
	if m then
		m.Material = Enum.Material.SmoothPlastic
	end
	local glow = fx:mesh("Spire", c.Glow, base, Vector3.new(0.01, 0.01, 0.01), 0)
	local born = fx.t
	fx:puff(base.Position, "G_Dust8", 3, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 2 * w }, { 1, 5 * w } }),
		Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Drag = 2, Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "OneShot", fps = 80 },
	})
	fx:puff(base.Position, "G_Rock4", 6, {
		Color = ColorSequence.new(c.Main), LightEmission = 0, LightInfluence = 0.8, Size = NumberRange.new(0.4 * w, 0.9 * w),
		Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -50, 0),
		Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:every(function(t)
		local age = t - born
		local k = backOut(phase(age, 0, 0.14)) - easeOut(phase(t, sink, sink + 0.8))
		local hh = h * math.max(k, 0.001)
		rooted(m, base, w, hh)
		rooted(glow, base * CFrame.Angles(0, 1, 0), w * 0.9, hh * 0.97)
		if t >= sink + 0.8 then
			if m then
				m:Destroy()
			end
			if glow then
				glow:Destroy()
			end
			return true
		end
		return false
	end)
end

-- A rock torrent: a molten line inside a stream of grinding stone, boulders tumbling along it, pebbles
-- and dust pouring off it; at the impact, rock bursts, dust rolls and a ring of lava cracks open.
function Earth.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.4)
	local body = fx:beam(a0, a1, "G_Stream", { Color = ColorSequence.new(c.Main), TextureSpeed = 3, TextureLength = 8, LightEmission = 0, LightInfluence = 0.6, ZOffset = 0.1 })
	local molten = fx:beam(a0, a1, "F_Core", { Color = colors({ { 0, c.Accent }, { 1, c.Glow } }), TextureSpeed = 4, TextureLength = 6, ZOffset = 0.3 })
	local heat = fx:beam(a0, a1, "G_Stream", { Color = ColorSequence.new(c.Glow), TextureSpeed = -2, TextureLength = 11, Transparency = NumberSequence.new(0.6), ZOffset = -0.1 })
	local pebbles = fx:emitter(s.spine, "G_Rock4", {
		Color = ColorSequence.new(c.Main), LightEmission = 0, LightInfluence = 0.8, Size = NumberRange.new(0.5 * W, 1 * W),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 25,
	})
	local dust = fx:emitter(s.spine, "G_Dust8", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 2 * W }, { 1, 4.5 * W } }),
		Transparency = numbers({ { 0, 0.35 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 80 }, Rate = 12,
	})
	local orbit = {}
	for k = 1, 5 do
		local rock, seam = boulder(fx, s.cf, 1)
		table.insert(orbit, { rock = rock, seam = seam, a = k / 5 * math.pi * 2, size = fx.rng:NextNumber(0.7, 1.1) * W })
	end
	local hitDust = fx:emitter(s.endPart, "G_Dust8", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 4 * W }, { 1, 9 * W } }),
		Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 40), Drag = 2, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 60 }, Rate = 0,
	})
	local hitRocks = fx:emitter(s.endPart, "G_Rock4", {
		Color = ColorSequence.new(c.Main), LightEmission = 0, LightInfluence = 0.8, Size = NumberRange.new(0.6 * W, 1.4 * W),
		Lifetime = NumberRange.new(0.7, 1.0), Speed = NumberRange.new(12, 22), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -50, 0),
		Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 0,
	})
	local hitLight = fx:light(s.endPart, c.Glow, 20)
	local flying = {}
	local nextRock, nextCrack = 0, 0
	fx:every(function(t, dt)
		local grow = easeOut(phase(t, 0, 0.22))
		local fade = 1 - phase(t, D, D + 0.3)
		s:update(grow)
		local len = s.len * grow
		body.Width0, body.Width1 = 2.6 * W * fade, 3.2 * W * fade
		molten.Width0, molten.Width1 = 0.6 * W * fade, 0.8 * W * fade
		heat.Width0, heat.Width1 = 3.4 * W * fade, 4.2 * W * fade
		for _, r in orbit do
			local a = r.a + t * 5
			local cf = s.cf * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.8 * W, -0.5) * CFrame.Angles(t * 3, t * 2, 0)
			local sz = r.size * fade
			if r.rock then
				r.rock.CFrame = cf
				rescale(r.rock, Vector3.new(sz, sz, sz))
			end
			if r.seam then
				r.seam.CFrame = cf * CFrame.Angles(0.7, 0.4, 0)
				rescale(r.seam, Vector3.new(sz, sz, sz) * 0.93)
			end
		end
		local on = t < D
		pebbles.Enabled, dust.Enabled = on, on
		-- boulders tumbling down the stream
		if on and t >= nextRock and #flying < 30 then
			nextRock = t + 0.07 / fx.q
			local a = fx.rng:NextNumber(0, 6.28)
			local off = Vector3.new(math.cos(a), math.sin(a), 0) * fx.rng:NextNumber(0.3, 1.1) * W
			local sz = fx.rng:NextNumber(0.8, 1.7) * W
			local rock, seam = boulder(fx, s.cf, sz)
			table.insert(flying, { rock = rock, seam = seam, u = 0, off = off, sz = sz, spin = Vector3.new(fx.rng:NextNumber(-6, 6), fx.rng:NextNumber(-6, 6), 0) })
		end
		for i = #flying, 1, -1 do
			local r = flying[i]
			r.u += dt * 60 / math.max(s.len, 1)
			local cf = s.cf * CFrame.new(r.off.X, r.off.Y, -len * r.u) * CFrame.Angles(t * r.spin.X, t * r.spin.Y, 0)
			if r.rock then
				r.rock.CFrame = cf
			end
			if r.seam then
				r.seam.CFrame = cf * CFrame.Angles(0.7, 0.4, 0)
			end
			if r.u >= 1 or not on then
				if r.rock then
					r.rock:Destroy()
				end
				if r.seam then
					r.seam:Destroy()
				end
				table.remove(flying, i)
			end
		end
		if grow >= 1 and on then
			hitDust.Rate = 14 * fx.q
			hitRocks.Rate = 30 * fx.q
			hitLight.Brightness = 3 + math.sin(t * 18)
			if t >= nextCrack then
				nextCrack = t + 0.35
				fx:pulse("RingJag", c.Glow, CFrame.new(s.tip) * CFrame.Angles(0, fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(11, 1, 11) * W, 0.45)
			end
		else
			hitDust.Rate, hitRocks.Rate = 0, 0
			hitLight.Brightness *= 0.85
		end
		return t > D + 0.4
	end)
end

-- A boulder with glowing molten seams, tumbling end over end through a cloud of dust and grit. It
-- smashes into flying rock, a burst of dust, a ring of lava cracks and spikes of stone.
function Earth.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 65, 2.0)
	local rock, seam = boulder(fx, p.look, 0.01)
	local dust = fx:emitter(p.ball, "G_Dust8", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 2 * W }, { 1, 4 * W } }),
		Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 90 }, Rate = 24,
	})
	local grit = fx:emitter(p.ball, "G_Rock4", {
		Color = ColorSequence.new(c.Main), LightEmission = 0, LightInfluence = 0.8, Size = NumberRange.new(0.4 * W, 0.8 * W),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -30, 0), Flipbook = { mode = "Random", fps = 1, random = true }, Rate = 20,
	})
	local light = fx:light(p.ball, c.Glow, 12, 2)
	p.go(function(t, cf, grow)
		local spin = cf * CFrame.Angles(-t * 9, t * 2, 0)
		if rock then
			rock.CFrame = spin
			rescale(rock, Vector3.new(3.4, 3.4, 3.4) * W * grow)
		end
		if seam then
			seam.CFrame = spin * CFrame.Angles(0.7, 0.4, 0)
			rescale(seam, Vector3.new(3.15, 3.15, 3.15) * W * grow)
		end
	end, function(at)
		retire({ rock, seam, dust, grit, light })
		Earth.smash(fx, at, W)
	end)
end

function Earth.smash(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "G_Dust8", 10, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 5 * W }, { 1, 11 * W } }),
		Transparency = numbers({ { 0, 0.15 }, { 1, 1 } }), Lifetime = NumberRange.new(1.0, 1.5), Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 40), Drag = 3, Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "OneShot", fps = 50 },
	})
	fx:puff(at, "G_Rock4", 26, {
		Color = ColorSequence.new(c.Main), LightEmission = 0, LightInfluence = 0.8, Size = NumberRange.new(0.6 * W, 1.4 * W),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(15, 30), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Acceleration = Vector3.new(0, -50, 0),
		Flipbook = { mode = "Random", fps = 1, random = true },
	})
	fx:debris({ "Rock1", "Rock2", "Rock3" }, c.Main, at, 6, 30, 1.4 * W, 1.2, Enum.Material.SmoothPlastic, 0.5)
	fx:pulse("RingJag", c.Glow, CFrame.new(at) * CFrame.Angles(0, fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(16, 1, 16) * W, 0.55)
	fx:pulse("Ring", c.Accent, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(10, 1, 10) * W, 0.3)
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2 + fx.rng:NextNumber(0, 0.8)
		local base = CFrame.new(at + Vector3.new(math.cos(a), 0, math.sin(a)) * 3 * W - Vector3.new(0, 0.5 * W, 0))
			* CFrame.Angles(math.cos(a) * 0.35, 0, -math.sin(a) * 0.35)
		Earth.spire(fx, base, 1.6 * W, fx.rng:NextNumber(3, 5) * W, fx.t + 0.7)
	end
	fx:flash(at, c.Glow, 26, 7, 0.6)
end

-- Ultimate: Tectonic Fury. A stomp splits the ground: a glowing fissure races forward, slabs of rock
-- heave up along it, spires erupt in sequence, boulders tear free and float, then all slam down at
-- the end of the fissure. The earth settles back.
function Earth.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 7
	local L = (o.reach or 26) * S
	fx:sound("Ultimate", fx:holder(at * CFrame.new(0, 2, -L * 0.4)))
	local slamPoint = (at * CFrame.new(0, 0, -L)).Position
	-- the stomp
	fx:pulse("RingJag", c.Glow, at * CFrame.new(0, 0.1, 0), Vector3.new(1, 1, 1) * S, Vector3.new(16, 1, 16) * S, 0.5)
	fx:puff(at.Position, "G_Dust8", 10, {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 3 * S }, { 1, 8 * S } }),
		Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(85, 5), EmissionDirection = Enum.NormalId.Top, Drag = 3, Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "OneShot", fps = 60 },
	})
	-- the fissure: a zig-zag of molten segments laid along the ground
	local points = {}
	for k = 0, 14 do
		local d = 2 * S + (L - 2 * S) * k / 14
		local side = (k == 0 or k == 14) and 0 or fx.rng:NextNumber(-1, 1) * 0.9 * S
		table.insert(points, (at * CFrame.new(side, 0.05, -d)).Position)
	end
	local segments = {}
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local seg = fx:holder(CFrame.lookAt((a + b) / 2, b), Vector3.new(0.01, 0.01, 0.01))
		seg.Transparency, seg.Material, seg.Color = 0, Enum.Material.Neon, c.Glow
		table.insert(segments, { part = seg, len = (b - a).Magnitude + 0.4, at = 0.2 + 0.8 * (k - 1) / (#points - 1), mid = (a + b) / 2 })
	end
	-- slabs heaving up along both sides
	local slabs = {}
	for k = 1, 8 do
		local d = L * (k - 0.5) / 8
		local side = (k % 2 == 0 and 1 or -1)
		local base = at * CFrame.new(side * 2.4 * S, -0.5, -d) * CFrame.Angles(0, fx.rng:NextNumber(-0.4, 0.4), side * -0.45)
		local m = fx:mesh("Slab" .. (k % 2 + 1), tone(c.Main, fx.rng:NextNumber(-0.1, 0.1)), base, Vector3.new(0.01, 0.01, 0.01), 0)
		if m then
			m.Material = Enum.Material.SmoothPlastic
		end
		table.insert(slabs, { m = m, base = base, t0 = 0.6 + 0.12 * k, h = fx.rng:NextNumber(3, 5) * S, w = fx.rng:NextNumber(2.4, 3.4) * S })
	end
	-- spires erupting along the fissure, one after another
	for k = 0, 9 do
		local d = 4 * S + k * (L - 6 * S) / 9
		local side = (k % 2 == 0 and 1 or -1) * 1.3 * S
		local base = at * CFrame.new(side, -0.3, -d) * CFrame.Angles(0, fx.rng:NextNumber(0, 6), side > 0 and -0.12 or 0.12)
		fx:when(1.2 + k * 0.17, function()
			Earth.spire(fx, base, 2.4 * S, fx.rng:NextNumber(6, 10) * S, 4.4 + k * 0.08)
			fx:pulse("RingJag", c.Glow, base * CFrame.new(0, 0.3, 0), Vector3.new(1, 1, 1) * S, Vector3.new(7, 1, 7) * S, 0.35)
		end)
	end
	-- boulders tearing free and floating, then hurled into the slam
	local floaters = {}
	for k = 1, 6 do
		local d = L * (0.2 + 0.6 * k / 6)
		local start = (at * CFrame.new(fx.rng:NextNumber(-5, 5) * S, -1, -d)).Position
		local rock, seam = boulder(fx, CFrame.new(start), 0.01)
		table.insert(floaters, {
			rock = rock, seam = seam, start = start, hover = start + Vector3.new(0, fx.rng:NextNumber(6, 10) * S, 0),
			size = fx.rng:NextNumber(2.2, 3.4) * S, t0 = 1.6 + k * 0.1, spin = fx.rng:NextNumber(-2, 2),
		})
	end
	local dustBand = fx:holder(at * CFrame.new(0, 0.5, -L / 2), Vector3.new(6 * S, 1, L))
	local lingering = fx:emitter(dustBand, "G_Dust8", {
		Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 3 * S }, { 1, 7 * S } }),
		Transparency = numbers({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }), Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(50, 50), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 40 }, Rate = 0,
	})
	local light = fx:light(dustBand, c.Glow, 40, 0)
	fx:when(3.8, function()
		Earth.smash(fx, slamPoint, 2.2 * S)
		fx:pulse("RingJag", c.Glow, CFrame.new(slamPoint), Vector3.new(2, 1, 2) * S, Vector3.new(44, 1, 44) * S, 0.8)
		fx:puff(slamPoint, "G_Dust8", 8, {
			Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 8 * S }, { 1, 18 * S } }),
			Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }), Lifetime = NumberRange.new(1.4, 2.0), Speed = NumberRange.new(14 * S, 24 * S),
			SpreadAngle = Vector2.new(85, 10), EmissionDirection = Enum.NormalId.Top, Drag = 2, Rotation = NumberRange.new(0, 360),
			Flipbook = { mode = "OneShot", fps = 36 },
		})
		fx:flash(slamPoint + Vector3.new(0, 3, 0), c.Glow, 60, 12, 1.0)
	end)
	fx:every(function(t)
		local settle = phase(t, 4.4, 6.0)
		for _, seg in segments do
			local k = easeOut(phase(t, seg.at, seg.at + 0.08))
			seg.part.Size = Vector3.new(0.5 * S * k * (1 - settle) + 0.001, 0.12, seg.len * k + 0.001)
			seg.part.Transparency = settle
			if k > 0 and not seg.puffed then
				seg.puffed = true
				fx:puff(seg.mid, "G_Dust8", 2, {
					Color = ColorSequence.new(c.Smoke), LightEmission = 0, LightInfluence = 0.6, Size = numbers({ { 0, 2 * S }, { 1, 5 * S } }),
					Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(3, 6),
					EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(50, 50), Rotation = NumberRange.new(0, 360),
					Flipbook = { mode = "OneShot", fps = 80 },
				})
			end
		end
		for _, sl in slabs do
			local k = backOut(phase(t, sl.t0, sl.t0 + 0.3)) * (1 - easeOut(settle))
			rooted(sl.m, sl.base, sl.w, sl.h * math.max(k, 0.001), sl.w * 0.6)
		end
		for _, f in floaters do
			local lift = easeOut(phase(t, f.t0, f.t0 + 0.8))
			local throw = phase(t, 3.55, 3.8) ^ 2
			local p = f.start:Lerp(f.hover, lift) + Vector3.new(0, math.sin(t * 2 + f.spin) * 0.4 * lift, 0)
			p = p:Lerp(slamPoint + Vector3.new(0, 1, 0), throw)
			local cf = CFrame.new(p) * CFrame.Angles(t * f.spin, t * 0.7, 0)
			local sz = f.size * (t < 3.8 and math.max(phase(t, f.t0, f.t0 + 0.3), 0.001) or 0.001)
			if f.rock then
				f.rock.CFrame = cf
				rescale(f.rock, Vector3.new(sz, sz, sz))
			end
			if f.seam then
				f.seam.CFrame = cf * CFrame.Angles(0.7, 0.4, 0)
				rescale(f.seam, Vector3.new(sz, sz, sz) * 0.93)
			end
		end
		lingering.Rate = (t > 0.4 and t < 5.6) and 10 * fx.q or 0
		light.Brightness = 3 * phase(t, 0.2, 1.0) * (1 - settle)
		return t > 6.8
	end)
end

-- ====================================================================== WATER

local Water = {}

-- A pressurised water jet: a bright core in a rushing blue stream, spiralling ribbons of water,
-- spray and foam flying off it, a splash at the hands; it hits in a crown of splashes and ripples.
function Water.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.4)
	local outer = fx:beam(a0, a1, "A_Stream", { Color = ColorSequence.new(c.Glow), TextureSpeed = 2, TextureLength = 12, Transparency = NumberSequence.new(0.55), ZOffset = -0.1 })
	local body = fx:beam(a0, a1, "A_Stream", {
		Color = colors({ { 0, c.Accent }, { 0.15, c.Main }, { 1, c.Glow } }), TextureSpeed = 4, TextureLength = 9, LightEmission = 0.35, ZOffset = 0.1,
	})
	local core = fx:beam(a0, a1, "A_Stream", { Color = ColorSequence.new(c.Accent), TextureSpeed = 6, TextureLength = 6, ZOffset = 0.3, Transparency = NumberSequence.new(0.1) })
	local ribbon = fx:mesh("Spiral", c.Main, s.cf, Vector3.new(1, 1, 1), 0.35)
	local ribbon2 = fx:mesh("SpiralThin", c.Accent, s.cf, Vector3.new(1, 1, 1), 0.25)
	local spray = fx:emitter(s.spine, "A_Drop", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(0.4 * W, 0.8 * W),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -35, 0), Rate = 40,
	})
	local foam = fx:emitter(s.spine, "A_Foam4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = NumberRange.new(1 * W, 2 * W), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200), Flipbook = { mode = "OneShot", fps = 32 }, Rate = 15,
	})
	local muzzle = fx:emitter(s.startPart, "A_Splash8", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(3.5 * W, 4.2 * W), Lifetime = NumberRange.new(0.35, 0.35),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(-90, -90), LockedToPart = true, Flipbook = { mode = "OneShot", fps = 180 }, Rate = 10,
	})
	local hitLight = fx:light(s.endPart, c.Main, 20)
	local beamLight = fx:light(s.spine, c.Main, 14)
	local nextSplash, nextRipple, nextRing = 0, 0, 0
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.2))
		local fade = 1 - phase(t, D, D + 0.3)
		s:update(grow)
		local len = s.len * grow
		local mid = s.cf * CFrame.new(0, 0, -len / 2)
		local surge = 1 + 0.1 * math.sin(t * 16)
		outer.Width0, outer.Width1 = 3.0 * W * fade, 3.8 * W * fade * surge
		body.Width0, body.Width1 = 2.0 * W * fade, 2.6 * W * fade * surge
		core.Width0, core.Width1 = 0.8 * W * fade, 1.0 * W * fade
		if ribbon then
			ribbon.CFrame = mid * CFrame.Angles(0, 0, t * 8)
			rescale(ribbon, Vector3.new(3.4 * W * fade, 3.4 * W * fade, len))
		end
		if ribbon2 then
			ribbon2.CFrame = mid * CFrame.Angles(0, 0, -t * 12)
			rescale(ribbon2, Vector3.new(2.6 * W * fade, 2.6 * W * fade, len))
		end
		local on = t < D
		spray.Enabled, foam.Enabled, muzzle.Enabled = on, on, on
		beamLight.Brightness = 2.5 * fade
		if on and t >= nextRing then
			nextRing = t + 0.3
			fx:pulse("Ring", c.Accent, s.cf * CFrame.new(0, 0, -1) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(1, 1, 1) * W, Vector3.new(5, 1, 5) * W, 0.3, 0.3)
		end
		if grow >= 1 and on then
			hitLight.Brightness = 3 + 0.6 * math.sin(t * 15)
			if t >= nextSplash then
				nextSplash = t + 0.18
				fx:puff(s.tip, "A_Splash8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(7 * W, 9 * W), Rotation = NumberRange.new(-15, 15),
					Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 140 },
				})
				fx:puff(s.tip, "A_Drop", 10, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(0.5 * W, 1 * W),
					Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(60, 60),
					EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -45, 0),
				})
			end
			if t >= nextRipple then
				nextRipple = t + 0.35
				fx:pulse("Ring", c.Main, CFrame.new(s.tip), Vector3.new(1, 1, 1) * W, Vector3.new(13, 1, 13) * W, 0.5, 0.2)
			end
		else
			hitLight.Brightness *= 0.85
		end
		return t > D + 0.4
	end)
end

-- A wobbling orb of water with a bright heart and a spinning ring of current, shedding drops and
-- foam. It bursts in a dome of water, a crown splash and rings of ripples.
function Water.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 80, 1.8)
	local shell = fx:mesh("Orb", c.Main, p.look, Vector3.new(0.01, 0.01, 0.01), 0.3)
	local heart = fx:mesh("Orb", c.Accent, p.look, Vector3.new(0.01, 0.01, 0.01), 0)
	local current = fx:mesh("Ring", c.Accent, p.look, Vector3.new(0.01, 1, 0.01), 0.1)
	local trail = fx:trail(p.ball, "A_Stream", Vector3.new(0, 0.9 * W, 0), Vector3.new(0, -0.9 * W, 0), colors({ { 0, c.Accent }, { 1, c.Main } }), 0.25)
	local drops = fx:emitter(p.ball, "A_Drop", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), LightEmission = 0.5, Size = NumberRange.new(0.4 * W, 0.7 * W),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -35, 0), Rate = 30,
	})
	local foam = fx:emitter(p.ball, "A_Foam4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = NumberRange.new(1 * W, 1.8 * W), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		Flipbook = { mode = "OneShot", fps = 40 }, Rate = 12,
	})
	local light = fx:light(p.ball, c.Main, 14, 2.5)
	p.go(function(t, cf, grow)
		local wob = math.sin(t * 22) * 0.12
		if shell then
			shell.CFrame = cf * CFrame.Angles(0, 0, t * 2)
			rescale(shell, Vector3.new(2.8 * (1 + wob), 2.8 * (1 - wob), 2.8 * (1 + wob * 0.5)) * W * grow)
		end
		if heart then
			heart.CFrame = cf * CFrame.new(0.2 * W * math.sin(t * 9), 0.2 * W * math.cos(t * 7), 0)
			rescale(heart, Vector3.new(1.3, 1.3, 1.3) * W * grow)
		end
		if current then
			current.CFrame = cf * CFrame.Angles(math.rad(70), t * 8, 0)
			rescale(current, Vector3.new(3.6, 1, 3.6) * W * grow)
		end
	end, function(at)
		retire({ shell, heart, current, trail, drops, foam, light })
		Water.splash(fx, at, W)
	end)
end

function Water.splash(fx, at: Vector3, W: number)
	local c = fx.c
	local col = colors({ { 0, c.Accent }, { 1, c.Main } })
	fx:puff(at, "A_Splash8", 1, {
		Color = col, Size = NumberRange.new(14 * W, 14 * W), Lifetime = NumberRange.new(0.55, 0.55), Speed = NumberRange.new(0, 0),
		Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "A_Splash8", 2, {
		Color = col, Size = NumberRange.new(8 * W, 10 * W), Rotation = NumberRange.new(-40, 40), Lifetime = NumberRange.new(0.5, 0.5),
		Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
	})
	fx:puff(at, "A_Drop", 40, {
		Color = col, LightEmission = 0.5, Size = NumberRange.new(0.5 * W, 1.1 * W), Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(12, 26), SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -45, 0),
	})
	fx:puff(at, "A_Foam4", 10, {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = numbers({ { 0, 2 * W }, { 1, 4 * W } }), Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 30), Drag = 3,
		Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 20 },
	})
	fx:pulse("Dome", c.Main, CFrame.new(at - Vector3.new(0, 0.5 * W, 0)), Vector3.new(2, 1, 2) * W, Vector3.new(14, 8, 14) * W, 0.5, 0.35)
	for k = 0, 2 do
		fx:when(fx.t + k * 0.15, function()
			fx:pulse("Ring", k == 1 and c.Accent or c.Main, CFrame.new(at), Vector3.new(2, 1, 2) * W, Vector3.new(16 + k * 4, 1, 16 + k * 4) * W, 0.6, 0.2)
		end)
	end
	fx:flash(at, c.Main, 24, 6, 0.6)
end

-- Ultimate: Tidal Crash. Water surges up round the user, then a towering wave rises behind them,
-- rolls forward over the battlefield with foam pouring off its crest, and crashes down ahead.
function Water.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 6.7
	local width = 30 * S
	local reach = (o.reach or 24) * S
	local wave = fx:mesh("Wave", c.Main, at, Vector3.new(0.01, 0.01, 0.01), 0.15)
	local waveHolder = fx:holder(at * CFrame.new(0, 2, 5 * S))
	fx:sound("Ultimate", waveHolder)
	local col = colors({ { 0, c.Accent }, { 1, c.Main } })
	local crest = fx:holder(at, Vector3.new(width, 1, 2 * S))
	local crestFoam = fx:emitter(crest, "A_Foam4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = numbers({ { 0, 2 * S }, { 1, 4 * S } }), Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(2, 5), EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(40, 40),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), Flipbook = { mode = "OneShot", fps = 28 }, Rate = 0,
	})
	local crestSpray = fx:emitter(crest, "A_Drop", {
		Color = col, LightEmission = 0.5, Size = NumberRange.new(0.5 * S, 1 * S), Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(6 * S, 12 * S), EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -35, 0), Rate = 0,
	})
	local churn = fx:holder(at, Vector3.new(width, 1, 3 * S))
	local churnFoam = fx:emitter(churn, "A_Foam4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = numbers({ { 0, 3 * S }, { 1, 5 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(50, 50),
		Rotation = NumberRange.new(0, 360), Flipbook = { mode = "OneShot", fps = 24 }, Rate = 0,
	})
	local light = fx:light(waveHolder, c.Main, 40, 0)
	local nextSurge, nextRipple = 0, 0
	local crashZ = -reach
	fx:when(4.0, function()
		local line = at * CFrame.new(0, 0, crashZ)
		for k = -3, 3 do
			local p = (line * CFrame.new(k * width / 7, 0.5, 0)).Position
			fx:puff(p, "A_Splash8", 1, {
				Color = col, Size = NumberRange.new(13 * S, 15 * S), Rotation = NumberRange.new(-15, 15), Lifetime = NumberRange.new(0.6, 0.6),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 106 },
			})
			if k % 2 == 0 then
				fx:pulse("Dome", c.Main, CFrame.new(p), Vector3.new(3, 1, 3) * S, Vector3.new(14, 9, 14) * S, 0.6, 0.35)
			end
		end
		fx:puff((line * CFrame.new(0, 2, 0)).Position, "A_Drop", 50, {
			Color = col, LightEmission = 0.5, Size = NumberRange.new(0.6 * S, 1.3 * S), Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(16 * S, 34 * S), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -45, 0),
		})
		for k = 0, 2 do
			fx:when(4.0 + k * 0.18, function()
				fx:pulse("Ring", k == 1 and c.Accent or c.Main, line * CFrame.new(0, 0.2, 0), Vector3.new(3, 1, 3) * S, Vector3.new(36 + 8 * k, 1, 36 + 8 * k) * S, 0.8, 0.2)
			end)
		end
		fx:flash((line * CFrame.new(0, 4, 0)).Position, c.Accent, 60, 10, 0.8)
	end)
	local foamBand = fx:holder(at * CFrame.new(0, 0.3, crashZ + 2 * S), Vector3.new(width, 1, 14 * S))
	local foam = fx:emitter(foamBand, "A_Foam4", {
		Color = ColorSequence.new(c.Accent), LightEmission = 0.4, Size = numbers({ { 0, 3 * S }, { 1, 6 * S } }), Transparency = numbers({ { 0, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0.5, 2), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(60, 60),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), Flipbook = { mode = "OneShot", fps = 16 }, Rate = 0,
	})
	fx:every(function(t)
		-- 0-1.4: water surges up round the user
		if t < 1.4 and t >= nextSurge then
			nextSurge = t + 0.1 / fx.q
			local a = fx.rng:NextNumber(0, 6.28)
			local p = (at * CFrame.new(math.cos(a) * 3.5 * S, 0.3, math.sin(a) * 3.5 * S)).Position
			fx:puff(p, "A_Splash8", 1, {
				Color = col, Size = NumberRange.new(4 * S, 6 * S), Lifetime = NumberRange.new(0.45, 0.45), Speed = NumberRange.new(0, 0),
				Flipbook = { mode = "OneShot", fps = 140 },
			})
		end
		if t < 1.6 and t >= nextRipple then
			nextRipple = t + 0.4
			fx:pulse("Ring", c.Main, at * CFrame.new(0, 0.15, 0), Vector3.new(2, 1, 2) * S, Vector3.new(14, 1, 14) * S, 0.6, 0.2)
		end
		-- the wave rises behind the user (0.3-1.8), rolls forward (1.8-4.0), crashes at 4.0
		local rise = easeOut(phase(t, 0.3, 1.8))
		local roll = phase(t, 1.8, 4.0) ^ 1.6
		local fall = phase(t, 4.0, 4.3)
		local z = 5 * S + (crashZ - 5 * S) * roll
		local h = 16 * S * rise * (1 - fall) + 0.01
		local depth = 9 * S * (0.3 + 0.7 * rise)
		local base = at * CFrame.new(0, 0, z) * CFrame.Angles(-0.12 * roll, 0, 0)
		rooted(wave, base, width, h, depth)
		if wave then
			wave.Transparency = 0.15 + 0.85 * fall
		end
		local live = t >= 0.5 and t < 4.0
		crest.CFrame = base * CFrame.new(0, h * 0.95, -depth * 0.35)
		crestFoam.Rate = live and 40 * fx.q * rise or 0
		crestSpray.Rate = live and 50 * fx.q * rise or 0
		churn.CFrame = base * CFrame.new(0, 0.3, 0)
		churnFoam.Rate = live and 24 * fx.q or 0
		waveHolder.CFrame = base * CFrame.new(0, h * 0.5, 0)
		light.Brightness = 3 * rise * (1 - fall)
		foam.Rate = (t >= 4.1 and t < 5.8) and 30 * fx.q or 0
		return t > 6.5
	end)
end

-- ====================================================================== ENERGY

local Energy = {}

-- A wave of pure ki: a blinding core in a thick blue beam with a glowing halo, a spiral of energy
-- round it and a huge sphere of ki leading its head; it slams into an explosion of light and rings.
function Energy.beam(fx, origin, target: Vector3)
	local c = fx.c
	local s, a0, a1, D, W = beamBase(fx, origin, target, 1.3)
	local halo = fx:beam(a0, a1, "K_Stream", { Color = ColorSequence.new(c.Glow), TextureSpeed = 3, TextureLength = 10, Transparency = NumberSequence.new(0.55), ZOffset = -0.1 })
	local body = fx:beam(a0, a1, "K_Stream", { Color = colors({ { 0, c.Accent }, { 0.1, c.Main }, { 1, c.Glow } }), TextureSpeed = 5, TextureLength = 8, LightEmission = 0.6, ZOffset = 0.1 })
	local core = fx:beam(a0, a1, "K_Stream", { Color = ColorSequence.new(c.Accent), TextureSpeed = 7, TextureLength = 6, ZOffset = 0.3 })
	local spiral = fx:mesh("SpiralThin", c.Accent, s.cf, Vector3.new(1, 1, 1), 0.3)
	local spiral2 = fx:mesh("Spiral", c.Main, s.cf, Vector3.new(1, 1, 1), 0.45)
	local head = fx:mesh("Orb", c.Accent, s.cf, Vector3.new(0.01, 0.01, 0.01), 0)
	local headShell = fx:mesh("Orb", c.Main, s.cf, Vector3.new(0.01, 0.01, 0.01), 0.55)
	local headGlow = fx:emitter(s.endPart, "K_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(8 * W, 9 * W), Lifetime = NumberRange.new(0.12, 0.12),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "Loop", fps = 30 }, Rate = 24,
	})
	local hands = fx:mesh("Orb", c.Accent, s.cf, Vector3.new(0.01, 0.01, 0.01), 0)
	local handGlow = fx:emitter(s.startPart, "K_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(5 * W, 5.5 * W), Lifetime = NumberRange.new(0.12, 0.12),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "Loop", fps = 30 }, Rate = 24,
	})
	local twinkle = fx:emitter(s.spine, "K_Twinkle4", {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(0.6 * W, 1.2 * W), Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "Loop", fps = 30 }, Rate = 30,
	})
	local hitLight = fx:light(s.endPart, c.Main, 26)
	local beamLight = fx:light(s.spine, c.Main, 18)
	local nextRing, nextBurst, nextRipple = 0, 0, 0
	fx:every(function(t)
		local grow = easeOut(phase(t, 0, 0.35))
		local fade = 1 - phase(t, D, D + 0.3)
		s:update(grow)
		local len = s.len * grow
		local mid = s.cf * CFrame.new(0, 0, -len / 2)
		local hum = 1 + 0.05 * math.sin(t * 30)
		halo.Width0, halo.Width1 = 4.0 * W * fade, 5.2 * W * fade * hum
		body.Width0, body.Width1 = 2.8 * W * fade, 3.4 * W * fade * hum
		core.Width0, core.Width1 = 1.2 * W * fade, 1.5 * W * fade
		if spiral then
			spiral.CFrame = mid * CFrame.Angles(0, 0, t * 10)
			rescale(spiral, Vector3.new(4 * W * fade, 4 * W * fade, len))
		end
		if spiral2 then
			spiral2.CFrame = mid * CFrame.Angles(0, 0, -t * 6)
			rescale(spiral2, Vector3.new(4.8 * W * fade, 4.8 * W * fade, len))
		end
		local hs = (grow < 1 and 1 or 0.85) * fade * hum
		if head then
			head.CFrame = CFrame.new(s.tip)
			rescale(head, Vector3.new(4.2, 4.2, 4.2) * W * hs)
		end
		if headShell then
			headShell.CFrame = CFrame.new(s.tip)
			rescale(headShell, Vector3.new(6.2, 6.2, 6.2) * W * hs * (2 - hum))
		end
		if hands then
			hands.CFrame = s.cf * CFrame.new(0, 0, -0.5)
			rescale(hands, Vector3.new(2.6, 2.6, 2.6) * W * fade * hum)
		end
		local on = t < D
		headGlow.Enabled, handGlow.Enabled, twinkle.Enabled = on, on, on
		beamLight.Brightness = 4 * fade
		if on and t >= nextRing then
			nextRing = t + 0.2
			fx:pulse("Ring", c.Accent, s.cf * CFrame.new(0, 0, -1.2) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(2, 1, 2) * W, Vector3.new(8, 1, 8) * W, 0.3, 0.3)
		end
		if grow >= 1 and on then
			hitLight.Brightness = 5 + math.sin(t * 25)
			if t >= nextBurst then
				nextBurst = t + 0.2
				fx:puff(s.tip + Vector3.new(fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1), fx.rng:NextNumber(-1, 1)) * W, "K_Burst8", 1, {
					Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(9 * W, 11 * W), Lifetime = NumberRange.new(0.5, 0.5),
					Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 128 },
				})
			end
			if t >= nextRipple then
				nextRipple = t + 0.35
				fx:pulse("Ring", c.Main, CFrame.new(s.tip), Vector3.new(2, 1, 2) * W, Vector3.new(16, 1, 16) * W, 0.45, 0.2)
			end
		else
			hitLight.Brightness *= 0.85
		end
		return t > D + 0.4
	end)
end

-- A ki ball: a blazing core in a pulsing sphere of energy ringed by two spinning gyro rings, with a
-- comet trail of sparkles. It detonates in a dome of light.
function Energy.blast(fx, origin, target: Vector3)
	local c, o = fx.c, fx.options
	local W = o.size or 1
	local p = projectile(fx, origin, target, o.speed or 90, 1.6)
	local core = fx:mesh("Orb", c.Accent, p.look, Vector3.new(0.01, 0.01, 0.01), 0)
	local shell = fx:mesh("Orb", c.Main, p.look, Vector3.new(0.01, 0.01, 0.01), 0.45)
	local gyro1 = fx:mesh("Ring", c.Accent, p.look, Vector3.new(0.01, 1, 0.01), 0.1)
	local gyro2 = fx:mesh("Ring", c.Main, p.look, Vector3.new(0.01, 1, 0.01), 0.1)
	local glow = fx:emitter(p.ball, "K_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(5 * W, 5.5 * W), Lifetime = NumberRange.new(0.1, 0.1),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "Loop", fps = 30 }, Rate = 30,
	})
	local twinkle = fx:emitter(p.ball, "K_Twinkle4", {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(0.6 * W, 1.1 * W), Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Flipbook = { mode = "Loop", fps = 30 }, Rate = 40,
	})
	local trail = fx:trail(p.ball, "K_Stream", Vector3.new(0, 1 * W, 0), Vector3.new(0, -1 * W, 0), colors({ { 0, c.Accent }, { 1, c.Main } }), 0.22)
	local light = fx:light(p.ball, c.Main, 16, 3)
	p.go(function(t, cf, grow)
		local pulse = 1 + 0.1 * math.sin(t * 35)
		if core then
			core.CFrame = cf
			rescale(core, Vector3.new(1.6, 1.6, 1.6) * W * grow * pulse)
		end
		if shell then
			shell.CFrame = cf
			rescale(shell, Vector3.new(2.6, 2.6, 2.6) * W * grow * (2 - pulse))
		end
		if gyro1 then
			gyro1.CFrame = cf * CFrame.Angles(t * 9, 0, 0.6)
			rescale(gyro1, Vector3.new(3.4, 1, 3.4) * W * grow)
		end
		if gyro2 then
			gyro2.CFrame = cf * CFrame.Angles(0, 0.5, t * 11)
			rescale(gyro2, Vector3.new(3.1, 1, 3.1) * W * grow)
		end
	end, function(at)
		retire({ core, shell, gyro1, gyro2, glow, twinkle, trail, light })
		Energy.detonate(fx, at, W)
	end)
end

function Energy.detonate(fx, at: Vector3, W: number)
	local c = fx.c
	fx:puff(at, "K_Burst8", 1, {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(15 * W, 15 * W), Lifetime = NumberRange.new(0.55, 0.55),
		Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 116 },
	})
	fx:puff(at, "K_Twinkle4", 24, {
		Color = ColorSequence.new(c.Accent), Size = NumberRange.new(0.8 * W, 1.6 * W), Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(12, 26), SpreadAngle = Vector2.new(180, 180), Drag = 4, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "Loop", fps = 30 },
	})
	fx:pulse("Dome", c.Accent, CFrame.new(at - Vector3.new(0, 1 * W, 0)), Vector3.new(1, 1, 1) * W, Vector3.new(14, 14, 14) * W, 0.5, 0.3)
	fx:pulse("Orb", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(12, 12, 12) * W, 0.35, 0.4)
	fx:pulse("Ring", c.Main, CFrame.new(at), Vector3.new(1, 1, 1) * W, Vector3.new(18, 1, 18) * W, 0.5)
	fx:pulse("Spikes", c.Accent, CFrame.new(at) * CFrame.Angles(fx.rng:NextNumber(0, 6), fx.rng:NextNumber(0, 6), 0), Vector3.new(1, 1, 1) * W, Vector3.new(9, 9, 9) * W, 0.22)
	fx:flash(at, c.Main, 30, 9, 0.6)
end

-- Ultimate: Spirit Bomb. The user raises their hands; streaks of energy pour in from every direction
-- and a giant sphere of ki swells overhead. It is hurled forward and detonates in a vast dome of light.
function Energy.ultimate(fx, at: CFrame)
	local c, o = fx.c, fx.options
	local S = o.scale or 1
	fx.lifetime = 9.4
	local top = at * CFrame.new(0, 16 * S, 0)
	local R = 9 * S
	local dest = (at * CFrame.new(0, 0, -(o.distance or 32) * S)).Position
	local bomb = fx:holder(top)
	fx:sound("Ultimate", bomb)
	local core = fx:mesh("Orb", c.Accent, top, Vector3.new(0.01, 0.01, 0.01), 0)
	local shell = fx:mesh("Orb", c.Main, top, Vector3.new(0.01, 0.01, 0.01), 0.35)
	local aura = fx:mesh("Orb", c.Glow, top, Vector3.new(0.01, 0.01, 0.01), 0.75)
	local gyro1 = fx:mesh("Ring", c.Accent, top, Vector3.new(0.01, 1, 0.01), 0.2)
	local gyro2 = fx:mesh("Ring", c.Main, top, Vector3.new(0.01, 1, 0.01), 0.2)
	local glow = fx:emitter(bomb, "K_Orb4", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(1, 1), Lifetime = NumberRange.new(0.15, 0.15), Transparency = NumberSequence.new(0.3),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true, Flipbook = { mode = "Loop", fps = 30 }, Rate = 0,
	})
	local field = fx:holder(top, Vector3.new(70, 70, 70) * S)
	local gather = fx:emitter(field, "K_Twinkle4", {
		Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 0.6 * S }, { 1, 1.4 * S } }), Lifetime = NumberRange.new(1.35, 1.4),
		Speed = NumberRange.new(24 * S, 24 * S), Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Flipbook = { mode = "Loop", fps = 30 }, Rate = 0,
	})
	local raised = at * CFrame.new(0, 6.2 * S, 0)
	local handPart = fx:holder(raised)
	local handOrb = fx:mesh("Orb", c.Accent, raised, Vector3.new(0.01, 0.01, 0.01), 0)
	local feed = fx:beam(fx:attach(handPart), fx:attach(bomb), "K_Stream", {
		Color = colors({ { 0, c.Accent }, { 1, c.Main } }), TextureSpeed = -4, TextureLength = 6, Width0 = 0, Width1 = 0, Transparency = NumberSequence.new(0.2),
	})
	local light = fx:light(bomb, c.Main, 60, 0)
	local nextStreak = 0.3
	fx:when(7.0, function()
		fx:puff(dest + Vector3.new(0, 4, 0), "X_Glow", 1, {
			Color = ColorSequence.new(c.Accent), Size = numbers({ { 0, 30 * S }, { 1, 60 * S } }), Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(0, 0),
		})
		for k = 1, 3 do
			fx:puff(dest + Vector3.new(fx.rng:NextNumber(-4, 4), 4 + 3 * k, fx.rng:NextNumber(-4, 4)) * S, "K_Burst8", 1, {
				Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(26 * S, 32 * S), Lifetime = NumberRange.new(0.7, 0.7),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 92 },
			})
		end
		for k = 1, 8 do
			local a = k / 8 * math.pi * 2
			fx:puff(dest + Vector3.new(math.cos(a), 0.2, math.sin(a)) * 16 * S, "K_Burst8", 1, {
				Color = colors({ { 0, c.Accent }, { 1, c.Main } }), Size = NumberRange.new(10 * S, 13 * S), Lifetime = NumberRange.new(0.6, 0.6),
				Speed = NumberRange.new(0, 0), Flipbook = { mode = "OneShot", fps = 106 },
			})
		end
		fx:puff(dest + Vector3.new(0, 4, 0), "K_Twinkle4", 40, {
			Color = ColorSequence.new(c.Accent), Size = NumberRange.new(1 * S, 2 * S), Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(30 * S, 60 * S), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360), Flipbook = { mode = "Loop", fps = 30 },
		})
		fx:pulse("Dome", c.Accent, CFrame.new(dest), Vector3.new(2, 2, 2) * S, Vector3.new(44, 30, 44) * S, 0.9, 0.15)
		fx:pulse("Dome", c.Main, CFrame.new(dest), Vector3.new(4, 3, 4) * S, Vector3.new(64, 44, 64) * S, 1.6, 0.4)
		fx:pulse("Spikes", c.Accent, CFrame.new(dest + Vector3.new(0, 4, 0)), Vector3.new(4, 4, 4) * S, Vector3.new(36, 36, 36) * S, 0.3)
		for k = 0, 2 do
			fx:when(7.0 + k * 0.2, function()
				fx:pulse(k == 1 and "Ring" or "RingJag", k == 1 and c.Accent or c.Main, CFrame.new(dest + Vector3.new(0, 0.3, 0)), Vector3.new(4, 1, 4) * S, Vector3.new(70 + 10 * k, 1, 70 + 10 * k) * S, 0.9)
			end)
		end
		fx:flash(dest + Vector3.new(0, 6, 0), c.Accent, 90, 16, 1.6)
	end)
	fx:every(function(t)
		local charge = easeOut(phase(t, 0.3, 6.4)) ^ 0.8
		local r = 0.5 * S + R * charge
		-- 6.5-7.0: hurled on a falling arc
		local k = phase(t, 6.5, 7.0) ^ 1.6
		local p0, p2 = top.Position, dest + Vector3.new(0, r * 0.5, 0)
		local p1 = (top * CFrame.new(0, 4 * S, -12 * S)).Position
		local pos = p0:Lerp(p1, k):Lerp(p1:Lerp(p2, k), k)
		local alive = t < 7.0
		local hum = 1 + 0.03 * math.sin(t * 12)
		bomb.CFrame = CFrame.new(pos)
		local d = alive and r * 2 or 0.001
		if core then
			core.CFrame = bomb.CFrame
			rescale(core, Vector3.new(d, d, d) * 0.62 * hum)
		end
		if shell then
			shell.CFrame = bomb.CFrame * CFrame.Angles(t, t * 0.7, 0)
			rescale(shell, Vector3.new(d, d, d) * hum)
		end
		if aura then
			aura.CFrame = bomb.CFrame
			rescale(aura, Vector3.new(d, d, d) * 1.18 * (2 - hum))
		end
		if gyro1 then
			gyro1.CFrame = bomb.CFrame * CFrame.Angles(t * 1.3, 0, 0.5)
			rescale(gyro1, Vector3.new(d, 1, d) * 1.3)
		end
		if gyro2 then
			gyro2.CFrame = bomb.CFrame * CFrame.Angles(0.4, 0, t * 1.7)
			rescale(gyro2, Vector3.new(d, 1, d) * 1.25)
		end
		glow.Size = NumberSequence.new(d * 1.4)
		glow.Rate = alive and 24 * fx.q or 0
		local charging = t >= 0.2 and t < 6.3
		gather.Rate = charging and 80 * fx.q or 0
		local feeding = (t >= 0.3 and t < 6.5) and 1 or 0
		feed.Width0 = 1.2 * S * feeding * hum
		feed.Width1 = 2.6 * S * feeding * charge
		if handOrb then
			local hs = 2.2 * S * feeding * hum
			rescale(handOrb, Vector3.new(hs, hs, hs))
		end
		light.Brightness = alive and 2 + 5 * charge or 0
		-- streaks of energy pouring into the sphere from all around
		if charging and t >= nextStreak then
			nextStreak = t + 0.12 / fx.q
			local a = fx.rng:NextNumber(0, 6.28)
			local el = fx.rng:NextNumber(0.1, 1.2)
			local far = top.Position + Vector3.new(math.cos(a) * math.cos(el), math.sin(el) * 0.7, math.sin(a) * math.cos(el)) * fx.rng:NextNumber(30, 45) * S
			local h0 = fx:holder(CFrame.new(far))
			local h1 = fx:holder(CFrame.new(far))
			local b = fx:beam(fx:attach(h0), fx:attach(h1), "K_Stream", {
				Color = colors({ { 0, c.Main }, { 1, c.Accent } }), TextureSpeed = 6, TextureLength = 5, Width0 = 0.3 * S, Width1 = 1.2 * S,
			})
			local born = t
			fx:every(function(tt)
				local age = tt - born
				local head = easeOut(phase(age, 0, 0.35))
				local tail = phase(age, 0.2, 0.55) ^ 2
				local goal = bomb.Position
				h1.CFrame = CFrame.new(far:Lerp(goal, head))
				h0.CFrame = CFrame.new(far:Lerp(goal, tail))
				b.Transparency = NumberSequence.new(phase(age, 0.4, 0.55))
				if age >= 0.55 then
					h0:Destroy()
					h1:Destroy()
					return true
				end
				return false
			end)
		end
		return t > 9.2
	end)
end

-- ====================================================================== public API

local ELEMENTS = {
	Fire = Fire, Electric = Electric, Rift = Rift, Void = Void, Nature = Nature,
	Ice = Ice, Wind = Wind, Earth = Earth, Water = Water, Energy = Energy,
}
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
