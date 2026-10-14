-- EterniumAuras (ModuleScript in ReplicatedStorage.Eternium): the ten player auras, built entirely from
-- particles, beams, trails and lights riding the body parts. No packs, no meshes. Every aura has its own
-- textures, its own signature motion and its own Stage 2, and recolours from three picks:
--   Main   = the body of the aura
--   Accent = sparks and details
--   Glow   = outline, haze and the light it casts
--
-- Recommended setup (smoothest, since the animation runs every frame):
--   server: set attributes on the character  Aura = "FrostCrown", AuraStage = 1,
--           AuraMain / AuraAccent / AuraGlow = Color3 values
--   client: require(this).watch()  -- keeps every player's aura in sync with those attributes
--
-- Or drive one aura directly:
--   local aura = EterniumAuras.apply(character, "LimitBreaker", { Main = ..., Accent = ..., Glow = ... }, 1)
--   aura:SetStage(2); aura:SetColors({ Main = Color3.fromRGB(255, 80, 80) }); aura:Destroy()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EterniumAuras = {}

-- ---------------------------------------------------------------- configuration

-- Paste the uploaded asset IDs here ("rbxassetid://123..."), one per file in Auras/textures.
-- Any left empty fall back to a built-in Roblox texture so the aura still works before upload.
EterniumAuras.Textures = {
	Glow = "",
	LB_Trail = "", LB_Streak = "", LB_Chevron = "", LB_Ring = "", LB_Flare = "",
	VC_Flame = "", VC_Tendril = "", VC_Drip = "",
	AS_Bolt = "", AS_Spark = "", AS_Static = "",
	FC_Shard = "", FC_Flake = "", FC_Glint = "", FC_Wind = "",
	VB_Petal = "", VB_Leaf = "", VB_Ripple = "", VB_SpiritFlame = "", VB_Flower = "",
	UV_Scribble = "", UV_Glitch = "", UV_Star = "", UV_Static = "",
	RE_Edge = "", RE_Wisp = "", RE_Halo = "", RE_Shard = "",
	PB_Flame = "", PB_Smoke = "", PB_Wisp = "",
	DW_Rib = "", DW_Membrane = "", DW_Feather = "", DW_Slash = "",
	SS_Band = "", SS_Mote = "", SS_Ripple = "", SS_Flare = "",
}

local BUILTIN = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}
-- what each texture falls back to until it is uploaded ("" = plain, which suits beams and trails)
local FALLBACK = {
	Glow = BUILTIN.smoke, LB_Streak = BUILTIN.spark, LB_Chevron = BUILTIN.spark, LB_Ring = BUILTIN.spark, LB_Flare = BUILTIN.spark,
	VC_Flame = BUILTIN.fire, VC_Drip = BUILTIN.spark, AS_Spark = BUILTIN.spark, AS_Static = BUILTIN.spark,
	FC_Shard = BUILTIN.spark, FC_Flake = BUILTIN.spark, FC_Glint = BUILTIN.spark,
	VB_Petal = BUILTIN.spark, VB_Leaf = BUILTIN.spark, VB_Ripple = BUILTIN.spark, VB_SpiritFlame = BUILTIN.fire, VB_Flower = BUILTIN.spark,
	UV_Glitch = BUILTIN.spark, UV_Star = BUILTIN.spark, UV_Static = BUILTIN.spark,
	RE_Wisp = BUILTIN.smoke, RE_Halo = BUILTIN.spark, RE_Shard = BUILTIN.spark,
	PB_Flame = BUILTIN.fire, PB_Smoke = BUILTIN.smoke, PB_Wisp = BUILTIN.spark,
	DW_Feather = BUILTIN.spark, DW_Slash = BUILTIN.spark,
	SS_Band = BUILTIN.smoke, SS_Mote = BUILTIN.spark, SS_Ripple = BUILTIN.spark, SS_Flare = BUILTIN.spark,
}

local function texture(name)
	local id = EterniumAuras.Textures[name]
	if id and id ~= "" then
		return id
	end
	return FALLBACK[name] or ""
end

-- Your existing ignite / loop sounds per aura ("rbxassetid://..."); leave empty for silence.
EterniumAuras.Sounds = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Default colours when a player hasn't picked any.
EterniumAuras.Defaults = {
	LimitBreaker = { Main = rgb(255, 200, 60), Accent = rgb(255, 240, 170), Glow = rgb(255, 165, 40) },
	VoidCurrent = { Main = rgb(120, 50, 210), Accent = rgb(200, 160, 255), Glow = rgb(12, 6, 22) },
	AzureSurge = { Main = rgb(90, 185, 255), Accent = rgb(225, 245, 255), Glow = rgb(40, 120, 255) },
	FrostCrown = { Main = rgb(185, 230, 255), Accent = rgb(255, 255, 255), Glow = rgb(110, 185, 255) },
	VerdantBloom = { Main = rgb(255, 160, 205), Accent = rgb(120, 220, 110), Glow = rgb(140, 255, 170) },
	UmbralVeil = { Main = rgb(30, 22, 42), Accent = rgb(185, 145, 255), Glow = rgb(0, 0, 0) },
	RadiantEdge = { Main = rgb(255, 255, 255), Accent = rgb(255, 238, 200), Glow = rgb(30, 18, 40) },
	PhantomBlaze = { Main = rgb(255, 95, 205), Accent = rgb(175, 95, 255), Glow = rgb(60, 22, 80) },
	DuskWings = { Main = rgb(255, 235, 205), Accent = rgb(255, 205, 160), Glow = rgb(255, 135, 110) },
	SilverSheen = { Main = rgb(225, 232, 242), Accent = rgb(255, 255, 255), Glow = rgb(165, 182, 210) },
}

-- ---------------------------------------------------------------- small helpers

local function numbers(points, scale)
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2] * (scale or 1)))
	end
	return NumberSequence.new(keys)
end

-- push a colour towards white (k > 0) or black (k < 0)
local function tone(color, k)
	if k >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), k)
	end
	return color:Lerp(Color3.new(0, 0, 0), -k)
end

-- a colour sequence from a shade list: { {time, k}, ... } applied to one base colour
local function shades(color, list)
	local keys = {}
	for _, p in list do
		table.insert(keys, ColorSequenceKeypoint.new(p[1], tone(color, p[2])))
	end
	return ColorSequence.new(keys)
end

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

-- ---------------------------------------------------------------- the rig

local function findPart(character, ...)
	for _, name in { ... } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Logical body slots for R15 and R6. On R6 several slots share a part, with an offset to the right spot.
local function buildRig(character)
	local r6 = character:FindFirstChild("Torso") ~= nil and character:FindFirstChild("UpperTorso") == nil
	local rig = {
		r6 = r6,
		Root = findPart(character, "HumanoidRootPart"),
		Head = findPart(character, "Head"),
		Torso = findPart(character, "UpperTorso", "Torso"),
		Lower = findPart(character, "LowerTorso", "Torso"),
	}
	for _, side in { "Left", "Right" } do
		rig[side .. "Arm"] = findPart(character, side .. "UpperArm", side .. " Arm")
		rig[side .. "Forearm"] = findPart(character, side .. "LowerArm", side .. " Arm")
		rig[side .. "Hand"] = findPart(character, side .. "Hand", side .. " Arm")
		rig[side .. "Leg"] = findPart(character, side .. "UpperLeg", side .. " Leg")
		rig[side .. "Shin"] = findPart(character, side .. "LowerLeg", side .. " Leg")
		rig[side .. "Foot"] = findPart(character, side .. "Foot", side .. " Leg")
	end
	return rig
end

local LIMBS = { "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin" }
local EXTREMITIES = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }

-- ---------------------------------------------------------------- the aura object

local Aura = {}
Aura.__index = Aura

local Designs = {}
EterniumAuras.Designs = Designs

function Aura:track(inst)
	table.insert(self.instances, inst)
	return inst
end

-- An attachment on a body part (slot name or part), at an offset in the part's own space.
function Aura:attach(where, offset)
	local part = typeof(where) == "string" and self.rig[where] or where
	if not part then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "Aura"
	if typeof(offset) == "CFrame" then
		a.CFrame = offset
	else
		a.Position = offset or Vector3.zero
	end
	a.Parent = part
	return self:track(a)
end

-- Where the bottom end of a slot's part is (for R6 hands / feet, which share the whole limb part).
function Aura:endOf(slot)
	local part = self.rig[slot]
	if not part then
		return nil
	end
	if self.rig.r6 and (slot:find("Hand") or slot:find("Foot")) then
		return Vector3.new(0, -part.Size.Y / 2 + 0.2, 0)
	end
	return Vector3.zero
end

-- Each distinct body part once, for "every limb" effects (R6 repeats parts across slots).
function Aura:parts(slots)
	local seen, out = {}, {}
	for _, slot in slots do
		local part = self.rig[slot]
		if part and not seen[part] then
			seen[part] = true
			table.insert(out, part)
		end
	end
	return out
end

-- stage: 0 = always, 1 = Stage 1 only, 2 = Stage 2 only. role: "Main" | "Accent" | "Glow".
-- paint(inst, color) recolours it; defaults to a shaded colour sequence.
function Aura:item(inst, role, stage, paint, burst)
	local entry = { inst = inst, role = role, stage = stage or 0, paint = paint, burst = burst }
	table.insert(self.items, entry)
	self.stageOf[inst] = entry.stage
	self:track(inst)
	return inst
end

local DEFAULT_SHADE = { { 0, 0.35 }, { 0.4, 0 }, { 1, -0.2 } }

function Aura:emitter(att, tex, props, role, stage, shade, burst)
	if not att then
		return nil
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = tex
	e.Texture = texture(tex)
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.Enabled = false
	for key, value in props do
		e[key] = value
	end
	e.Parent = att
	shade = shade or DEFAULT_SHADE
	return self:item(e, role, stage, function(inst, color)
		inst.Color = shades(color, shade)
	end, burst)
end

function Aura:beam(a0, a1, tex, props, role, stage, shade)
	if not (a0 and a1) then
		return nil
	end
	local b = Instance.new("Beam")
	b.Name = tex
	b.Texture = texture(tex)
	b.Attachment0, b.Attachment1 = a0, a1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 12
	b.Enabled = false
	for key, value in props do
		b[key] = value
	end
	b.Parent = a0.Parent
	shade = shade or { { 0, 0.15 }, { 1, 0 } }
	return self:item(b, role, stage, function(inst, color)
		inst.Color = shades(color, shade)
	end)
end

function Aura:trail(a0, a1, tex, props, role, stage, shade)
	if not (a0 and a1) then
		return nil
	end
	local tr = Instance.new("Trail")
	tr.Name = tex
	tr.Texture = texture(tex)
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Enabled = false
	for key, value in props do
		tr[key] = value
	end
	tr.Parent = a0.Parent
	shade = shade or { { 0, 0.4 }, { 1, 0 } }
	return self:item(tr, role, stage, function(inst, color)
		inst.Color = shades(color, shade)
	end)
end

function Aura:light(where, role, range, stage)
	local part = typeof(where) == "string" and self.rig[where] or where
	if not part then
		return nil
	end
	local l = Instance.new("PointLight")
	l.Range = range or 12
	l.Brightness = 1
	l.Shadows = false
	l.Enabled = false
	l.Parent = part
	return self:item(l, role, stage, function(inst, color)
		inst.Color = color
	end)
end

-- true while an item belongs to the current stage
function Aura:live(inst)
	local stage = inst and self.stageOf[inst]
	return stage ~= nil and (stage == 0 or stage == self.stage)
end

function Aura:SetColors(colors)
	local defaults = EterniumAuras.Defaults[self.name]
	self.colors = {
		Main = (colors and colors.Main) or (self.colors and self.colors.Main) or defaults.Main,
		Accent = (colors and colors.Accent) or (self.colors and self.colors.Accent) or defaults.Accent,
		Glow = (colors and colors.Glow) or (self.colors and self.colors.Glow) or defaults.Glow,
	}
	for _, entry in self.items do
		if entry.paint and entry.inst.Parent then
			entry.paint(entry.inst, self.colors[entry.role])
		end
	end
end

function Aura:SetStage(stage)
	stage = (stage == 2) and 2 or 1
	local changed = stage ~= self.stage
	self.stage = stage
	for _, entry in self.items do
		local on = (entry.stage == 0 or entry.stage == stage) and not entry.burst
		entry.inst.Enabled = on
	end
	if changed and self.design.ignite then
		self.design.ignite(self, stage)
	end
	if changed then
		self:playSound("Ignite")
	end
end

function Aura:playSound(kind)
	local sounds = EterniumAuras.Sounds[self.name]
	local id = sounds and sounds[kind]
	if not id or id == "" or not self.rig.Root then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = kind == "Loop" and 0.35 or 0.8
	s.Looped = kind == "Loop"
	s.Parent = self.rig.Root
	s:Play()
	if kind == "Loop" then
		self:track(s)
	else
		task.delay(6, function()
			s:Destroy()
		end)
	end
end

function Aura:Destroy()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, inst in self.instances do
		inst:Destroy()
	end
	self.instances = {}
	self.items = {}
	self.stageOf = {}
end

-- ---------------------------------------------------------------- 1. Limit Breaker: a rising helix of power
-- Signature: ribbons of light spiral up round the body like a drill of energy, chevrons of power rise
-- off the feet, and the light throbs twice a second. Stage 2: more, taller, faster ribbons and
-- pressure rings bursting out along the ground.

Designs.LimitBreaker = {
	build = function(self)
		self.helix = {}
		for i = 1, 6 do
			local a0 = self:attach("Root")
			local a1 = self:attach("Root")
			local tr = self:trail(a0, a1, "LB_Trail", {
				Lifetime = 0.35,
				LightEmission = 1,
				MinLength = 0.05,
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				WidthScale = numbers({ { 0, 1 }, { 1, 0.2 } }),
			}, "Main", i <= 3 and 0 or 2, { { 0, 0.55 }, { 1, 0 } })
			table.insert(self.helix, { a0 = a0, a1 = a1, trail = tr, phase = (i - 1) * math.pi * 2 / 3 + (i > 3 and math.pi / 3 or 0), offset = (i - 1) / 6 })
		end
		for _, slot in EXTREMITIES do
			self:emitter(self:attach(slot, self:endOf(slot)), "LB_Streak", {
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Size = numbers({ { 0, 0.5 }, { 1, 0.15 } }),
				Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(7, 11),
				SpreadAngle = Vector2.new(12, 12),
				EmissionDirection = Enum.NormalId.Top,
				LightEmission = 1,
				Rate = 14,
			}, "Main")
		end
		self.chevrons = self:emitter(self:attach("Root", Vector3.new(0, -2.6, 0)), "LB_Chevron", {
			Size = numbers({ { 0, 0.35 }, { 0.5, 0.45 }, { 1, 0 } }),
			Transparency = numbers({ { 0, 1 }, { 0.15, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 0),
			LightEmission = 1,
			Rate = 10,
		}, "Accent")
		self:emitter(self:attach("Torso"), "Glow", {
			Size = numbers({ { 0, 3.5 }, { 1, 4.5 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.8 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 0.9),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			LightEmission = 1,
			Rate = 6,
		}, "Glow")
		self.rings = self:emitter(self:attach("Root", Vector3.new(0, -2.9, 0)), "LB_Ring", {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = numbers({ { 0, 1 }, { 1, 9 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 0.6),
			Speed = NumberRange.new(0.01, 0.01),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 0),
			LightEmission = 1,
		}, "Accent", 2, nil, true)
		self.flare = self:emitter(self:attach("Torso"), "LB_Flare", {
			Size = numbers({ { 0, 1 }, { 0.3, 6 }, { 1, 0 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.35, 0.35),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			LightEmission = 1,
		}, "Accent", 0, nil, true)
		self.light = self:light("Torso", "Glow", 14)
	end,
	update = function(self, t)
		local s2 = self.stage == 2
		local speed = s2 and 1.25 or 1
		local height = s2 and 7.2 or 6
		for _, h in self.helix do
			if self:live(h.trail) then
				local cycle = (t * 0.75 * speed + h.offset) % 1
				if cycle < h.last then
					h.trail:Clear() -- wrapped back to the feet: don't draw a streak down the body
				end
				h.last = cycle
				local radius = 1.6 - 0.6 * cycle
				local angle = h.phase + t * 5 * speed
				local y = -2.8 + cycle * height
				local pos = Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
				h.a0.Position = pos
				h.a1.Position = pos + Vector3.new(0, 0.25 + 0.25 * (1 - cycle), 0)
			end
		end
		self.light.Brightness = 1.4 + 0.8 * math.sin(t * math.pi * 4)
		if s2 then
			self.nextRing = self.nextRing or 0
			if t >= self.nextRing then
				self.rings:Emit(1)
				self.nextRing = t + 0.8
			end
		end
	end,
	ignite = function(self)
		self.flare:Emit(1)
		self.rings:Emit(2)
	end,
	init = function(self)
		for _, h in self.helix do
			h.last = 0
		end
	end,
}

-- ---------------------------------------------------------------- 2. Void Current: dark fire drawn down into a pool
-- Signature: the body's dark flames don't just rise, the darkness drips off the limbs and pools at the
-- feet in a slow, rotating whirl. Stage 2: shadow tendrils writhe from the hands down into the pool.

Designs.VoidCurrent = {
	build = function(self)
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "Torso", "LeftHand", "RightHand" }) do
			local a = self:attach(part)
			self:emitter(a, "VC_Flame", {
				Size = numbers({ { 0, 0.7 }, { 0.6, 1.4 }, { 1, 0.4 } }),
				Transparency = numbers({ { 0, 1 }, { 0.2, 0.15 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1.0),
				Speed = NumberRange.new(1.5, 3),
				SpreadAngle = Vector2.new(20, 20),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(-15, 15),
				RotSpeed = NumberRange.new(-20, 20),
				LightEmission = 0.15,
				Drag = 1,
				Rate = 9,
			}, "Main", 0, { { 0, 0.15 }, { 0.6, 0 }, { 1, -0.8 } })
			self:emitter(a, "Glow", {
				Size = numbers({ { 0, 1.6 }, { 1, 2.2 } }),
				Transparency = numbers({ { 0, 1 }, { 0.4, 0.75 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				LightEmission = 0,
				Rate = 4,
			}, "Glow", 0, { { 0, 0 }, { 1, 0 } })
		end
		for _, slot in { "LeftHand", "RightHand", "Torso" } do
			self:emitter(self:attach(slot, self:endOf(slot)), "VC_Drip", {
				Size = numbers({ { 0, 0.25 }, { 1, 0.1 } }),
				Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1.0),
				Speed = NumberRange.new(0.5, 1),
				Acceleration = Vector3.new(0, -9, 0),
				Rotation = NumberRange.new(180, 180),
				LightEmission = 0.5,
				Rate = 5,
			}, "Accent")
		end
		self.pool = self:attach("Root", Vector3.new(0, -2.95, 0))
		self:emitter(self.pool, "VC_Flame", {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = numbers({ { 0, 1.5 }, { 1, 4.5 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(0.01, 0.01),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(40, 70),
			LightEmission = 0,
			Rate = 4,
		}, "Glow", 0, { { 0, 0 }, { 1, 0 } })
		self:emitter(self.pool, "VC_Flame", {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = numbers({ { 0, 1 }, { 1, 3 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1, 1.5),
			Speed = NumberRange.new(0.01, 0.01),
			EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(60, 100),
			LightEmission = 0.3,
			Rate = 3,
		}, "Main")
		self.tendrils = {}
		for i, slot in { "LeftHand", "RightHand", "LeftHand", "RightHand" } do
			local from = self:attach(slot, self:endOf(slot))
			local angle = (i - 1) * math.pi / 2 + math.pi / 4
			local to = self:attach("Root", Vector3.new(math.cos(angle) * 2.2, -2.9, math.sin(angle) * 2.2))
			local b = self:beam(from, to, "VC_Tendril", {
				Width0 = 0.35,
				Width1 = 0.9,
				TextureMode = Enum.TextureMode.Stretch,
				TextureSpeed = 1.5,
				Transparency = numbers({ { 0, 0.2 }, { 1, 0.6 } }),
				LightEmission = 0.2,
			}, "Accent", 2, { { 0, 0.1 }, { 1, -0.4 } })
			table.insert(self.tendrils, { beam = b, phase = i * 1.7 })
		end
	end,
	update = function(self, t)
		self.pool.CFrame = CFrame.new(self.pool.Position) * CFrame.Angles(0, t * 0.6, 0)
		for _, td in self.tendrils do
			if self:live(td.beam) then
				td.beam.CurveSize0 = 1.6 * math.sin(t * 2.2 + td.phase)
				td.beam.CurveSize1 = -1.2 * math.sin(t * 1.7 + td.phase * 0.5)
			end
		end
	end,
}

-- ---------------------------------------------------------------- 3. Azure Surge: lightning leaping between the limbs
-- Signature: real arcs jump from limb to limb, re-forming many times a second, over a crackling skin
-- of static. Stage 2: both arms become storm conduits wrapped in continuous lightning, and a ring of
-- static spins above the head.

Designs.AzureSurge = {
	build = function(self)
		self.nodes = {}
		for _, slot in { "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head", "Torso", "LeftArm", "RightArm", "Lower" } do
			local a = self:attach(slot, self:endOf(slot))
			if a then
				table.insert(self.nodes, a)
			end
		end
		self.arcs = {}
		for i = 1, 5 do
			local a0, a1 = self:attach("Torso"), self:attach("Torso")
			local b = self:beam(a0, a1, "AS_Bolt", {
				Width0 = 0.3,
				Width1 = 0.3,
				TextureMode = Enum.TextureMode.Stretch,
				LightEmission = 1,
				Transparency = numbers({ { 0, 0 }, { 1, 0 } }),
			}, "Main", 0, { { 0, 0.5 }, { 1, 0.1 } })
			table.insert(self.arcs, { beam = b, a0 = a0, a1 = a1, next = 0 })
		end
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso", "Head" }) do
			self:emitter(self:attach(part), "AS_Static", {
				Size = numbers({ { 0, 0.5 }, { 1, 0.3 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.06, 0.14),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				LightEmission = 1,
				Rate = 16,
			}, "Glow", 0, { { 0, 0.3 }, { 1, 0 } })
		end
		self.sparks = {}
		for _, slot in { "LeftHand", "RightHand", "Torso", "Head" } do
			table.insert(self.sparks, self:emitter(self:attach(slot, self:endOf(slot)), "AS_Spark", {
				Size = numbers({ { 0, 0.4 }, { 0.2, 1.4 }, { 1, 0 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.12, 0.2),
				Speed = NumberRange.new(0, 0),
				LightEmission = 1,
			}, "Accent", 0, nil, true))
		end
		-- Stage 2: chains of lightning running shoulder -> elbow -> hand on both arms
		self.conduits = {}
		for _, side in { "Left", "Right" } do
			local chain = {
				self:attach(side .. "Arm", self.rig.r6 and Vector3.new(0, 0.8, 0) or Vector3.new(0, 0.3, 0)),
				self:attach(side .. "Forearm", self.rig.r6 and Vector3.zero or Vector3.new(0, 0.2, 0)),
				self:attach(side .. "Hand", self:endOf(side .. "Hand")),
			}
			for k = 1, 2 do
				for _, w in { 0.45, 0.22 } do
					local b = self:beam(chain[k], chain[k + 1], "AS_Bolt", {
						Width0 = w,
						Width1 = w,
						TextureMode = Enum.TextureMode.Wrap,
						TextureLength = 1.2,
						TextureSpeed = w > 0.3 and 6 or -9,
						LightEmission = 1,
					}, w > 0.3 and "Main" or "Accent", 2, { { 0, 0.4 }, { 1, 0 } })
					table.insert(self.conduits, b)
				end
			end
		end
		self.halo = {}
		for i = 1, 6 do
			local a = self:attach("Head")
			self:emitter(a, "AS_Static", {
				Size = numbers({ { 0, 0.5 }, { 1, 0.2 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.1, 0.2),
				Speed = NumberRange.new(0, 0),
				LightEmission = 1,
				Rate = 20,
			}, "Accent", 2)
			table.insert(self.halo, { a = a, phase = i * math.pi / 3 })
		end
		self.light = self:light("Torso", "Glow", 14)
	end,
	update = function(self, t)
		for _, arc in self.arcs do
			if t >= arc.next then
				-- jump to a new pair of limbs, with a new jag pattern
				local n = #self.nodes
				local i = math.random(1, n)
				local j = (i + math.random(1, n - 1) - 1) % n + 1
				arc.beam.Attachment0 = self.nodes[i]
				arc.beam.Attachment1 = self.nodes[j]
				arc.beam.TextureOffset = math.random()
				arc.beam.CurveSize0 = math.random() * 2 - 1
				arc.beam.CurveSize1 = math.random() * 2 - 1
				arc.next = t + 0.06 + math.random() * 0.12
				arc.beam.Enabled = self:live(arc.beam) and math.random() > 0.2
			end
		end
		self.nextSpark = self.nextSpark or 0
		if t >= self.nextSpark then
			self.sparks[math.random(1, #self.sparks)]:Emit(1)
			self.nextSpark = t + 0.12 + math.random() * 0.2
		end
		for _, b in self.conduits do
			if self:live(b) then
				b.CurveSize0 = math.random() * 0.6 - 0.3
			end
		end
		for _, h in self.halo do
			local angle = h.phase + t * 4
			h.a.Position = Vector3.new(math.cos(angle) * 1, 1.1, math.sin(angle) * 1)
		end
		self.light.Brightness = 1 + math.random() * 1.5
	end,
	ignite = function(self)
		for _, e in self.sparks do
			e:Emit(2)
		end
	end,
}

-- ---------------------------------------------------------------- 4. Frost Crown: a crown of ice, frost wind, a breaking shell
-- Signature: a ring of ice crystals hovers and turns above the head like a crown, cold wind circles the
-- body, and ice forms on the limbs and breaks off. Stage 2: a taller, wider crown with more crystals,
-- crystal pauldrons on the shoulders and a thicker blizzard.

Designs.FrostCrown = {
	build = function(self)
		self.crown = {}
		for i = 1, 11 do
			local stage = i <= 7 and 0 or 2
			local base = self:attach("Head")
			local tip = self:attach("Head")
			local b = self:beam(base, tip, "FC_Shard", {
				Width0 = 0.32,
				Width1 = 0.32,
				TextureMode = Enum.TextureMode.Stretch,
				LightEmission = 0.6,
				Segments = 1,
				Transparency = numbers({ { 0, 0.05 }, { 1, 0.05 } }),
			}, "Main", stage, { { 0, -0.1 }, { 1, 0.3 } })
			table.insert(self.crown, { beam = b, base = base, tip = tip, index = i, stage2 = stage == 2 })
		end
		self.pauldrons = {}
		for _, side in { "Left", "Right" } do
			for k = 1, 3 do
				local base = self:attach(side .. "Arm", Vector3.new(0, self.rig.r6 and 0.9 or 0.45, 0))
				local tip = self:attach(side .. "Arm", Vector3.new((side == "Left" and -1 or 1) * (0.3 + 0.15 * k), (self.rig.r6 and 0.9 or 0.45) + 0.5 + 0.2 * k, (k - 2) * 0.25))
				self:beam(base, tip, "FC_Shard", {
					Width0 = 0.3,
					Width1 = 0.3,
					TextureMode = Enum.TextureMode.Stretch,
					LightEmission = 0.6,
					Segments = 1,
				}, "Main", 2, { { 0, -0.1 }, { 1, 0.3 } })
			end
		end
		for _, part in self:parts({ "LeftForearm", "RightForearm", "LeftShin", "RightShin", "Torso" }) do
			local a = self:attach(part)
			self:emitter(a, "FC_Shard", {
				Size = numbers({ { 0, 0 }, { 0.3, 0.45 }, { 1, 0.45 } }),
				Transparency = numbers({ { 0, 0.1 }, { 0.85, 0.1 }, { 1, 1 } }),
				Lifetime = NumberRange.new(1.2, 2),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				LightEmission = 0.4,
				Rate = 3,
			}, "Main", 0, { { 0, 0.2 }, { 1, -0.1 } })
			self:emitter(a, "FC_Shard", {
				Size = numbers({ { 0, 0.25 }, { 1, 0.15 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(90, 90),
				Acceleration = Vector3.new(0, -18, 0),
				RotSpeed = NumberRange.new(-200, 200),
				LightEmission = 0.4,
				Rate = 3,
			}, "Accent")
			self:emitter(a, "FC_Glint", {
				Size = numbers({ { 0, 0 }, { 0.5, 0.6 }, { 1, 0 } }),
				Lifetime = NumberRange.new(0.25, 0.4),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				Rotation = NumberRange.new(0, 45),
				LightEmission = 1,
				Rate = 2,
			}, "Accent")
		end
		self.wind = {}
		for i = 1, 3 do
			local a0, a1 = self:attach("Root"), self:attach("Root")
			local tr = self:trail(a0, a1, "FC_Wind", {
				Lifetime = 0.6,
				LightEmission = 0.4,
				Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
			}, "Glow", i == 3 and 2 or 0)
			table.insert(self.wind, { a0 = a0, a1 = a1, phase = i * 2.1, trail = tr })
		end
		self.flakes = self:emitter(self:attach("Root"), "FC_Flake", {
			Size = numbers({ { 0, 0.25 }, { 1, 0.2 } }),
			Transparency = numbers({ { 0, 1 }, { 0.2, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -1.5, 0),
			RotSpeed = NumberRange.new(-60, 60),
			LightEmission = 0.5,
			Rate = 8,
		}, "Accent")
		self:emitter(self:attach("Root", Vector3.new(0, -2.8, 0)), "Glow", {
			Size = numbers({ { 0, 2 }, { 1, 4 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.75 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.5, 2.2),
			Speed = NumberRange.new(0.5, 1),
			SpreadAngle = Vector2.new(80, 10),
			LightEmission = 0.3,
			Rate = 4,
		}, "Glow")
		self.light = self:light("Head", "Glow", 12)
	end,
	update = function(self, t)
		local s2 = self.stage == 2
		local count = s2 and 11 or 7
		local radius = s2 and 1.05 or 0.8
		local tall = s2 and 1.35 or 1
		for _, c in self.crown do
			if self:live(c.beam) then
				local angle = (c.index - 1) / count * math.pi * 2 + t * 0.5
				local bob = 0.06 * math.sin(t * 2 + c.index)
				local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local h = (c.index % 2 == 0 and 0.75 or 0.55) * tall
				c.base.Position = out * radius + Vector3.new(0, 0.85 + bob, 0)
				c.tip.Position = out * (radius + 0.12 * tall) + Vector3.new(0, 0.85 + h + bob, 0)
				c.beam.Width0 = 0.32 * tall
				c.beam.Width1 = 0.32 * tall
			end
		end
		for i, w in ipairs(self.wind) do
			local angle = w.phase + t * (2.2 + i * 0.4)
			local y = -2.2 + 2.2 * (0.5 + 0.5 * math.sin(t * 0.7 + w.phase))
			local pos = Vector3.new(math.cos(angle) * 2.1, y, math.sin(angle) * 2.1)
			w.a0.Position = pos
			w.a1.Position = pos + Vector3.new(0, 0.35, 0)
		end
		self.flakes.Rate = s2 and 18 or 8
		self.light.Brightness = 0.9 + 0.2 * math.sin(t * 1.5)
	end,
}

-- ---------------------------------------------------------------- 5. Verdant Bloom: a rippling garden at your feet
-- Signature: soft ripples spread from the feet while petals spiral up out of them in a slow vortex,
-- and leaves tumble round the body. Stage 2: flowers bloom on the shoulders and head, and a gentle
-- spirit flame rises from the ring of ripples.

Designs.VerdantBloom = {
	build = function(self)
		self:emitter(self:attach("Root", Vector3.new(0, -2.95, 0)), "VB_Ripple", {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = numbers({ { 0, 0.5 }, { 1, 8 } }),
			Transparency = numbers({ { 0, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2, 2),
			Speed = NumberRange.new(0.01, 0.01),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 0),
			LightEmission = 0.6,
			Rate = 1.1,
		}, "Glow")
		self.vortex = {}
		for i = 1, 4 do
			local a = self:attach("Root")
			self:emitter(a, "VB_Petal", {
				Size = numbers({ { 0, 0.3 }, { 1, 0.22 } }),
				Transparency = numbers({ { 0, 1 }, { 0.15, 0 }, { 0.8, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(1.8, 2.6),
				Speed = NumberRange.new(1.5, 2.5),
				SpreadAngle = Vector2.new(15, 15),
				EmissionDirection = Enum.NormalId.Top,
				RotSpeed = NumberRange.new(-120, 120),
				LightEmission = 0.2,
				Drag = 0.5,
				Rate = 3,
			}, "Main", 0, { { 0, 0.2 }, { 1, -0.1 } })
			table.insert(self.vortex, { a = a, phase = i * math.pi / 2 })
		end
		self:emitter(self:attach("Torso"), "VB_Leaf", {
			Size = numbers({ { 0, 0.35 }, { 1, 0.3 } }),
			Transparency = numbers({ { 0, 1 }, { 0.15, 0 }, { 0.85, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0.6, -1.2, 0),
			RotSpeed = NumberRange.new(-150, 150),
			LightEmission = 0.1,
			Rate = 4,
		}, "Accent", 0, { { 0, 0.15 }, { 1, -0.2 } })
		for _, slot in { "Head", "LeftArm", "RightArm" } do
			local offset = slot == "Head" and Vector3.new(0.35, 0.45, 0) or Vector3.new(0, self.rig.r6 and 0.85 or 0.4, 0)
			self:emitter(self:attach(slot, offset), "VB_Flower", {
				Size = numbers({ { 0, 0 }, { 0.25, 0.5 }, { 0.85, 0.5 }, { 1, 0 } }),
				Lifetime = NumberRange.new(2.5, 3),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				RotSpeed = NumberRange.new(-20, 20),
				LightEmission = 0.3,
				Rate = 0.5,
			}, "Main", 2, { { 0, 0.3 }, { 1, 0 } })
		end
		self:emitter(self:attach("Root", Vector3.new(0, -2.6, 0)), "VB_SpiritFlame", {
			Size = numbers({ { 0, 0.6 }, { 0.5, 1.2 }, { 1, 0.2 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(1.5, 2.5),
			SpreadAngle = Vector2.new(70, 10),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(-10, 10),
			LightEmission = 0.6,
			Rate = 16,
		}, "Glow", 2)
		self.light = self:light("Lower", "Glow", 10)
	end,
	update = function(self, t)
		for _, v in self.vortex do
			local angle = v.phase + t * 1.4
			v.a.Position = Vector3.new(math.cos(angle) * 1.5, -2.7, math.sin(angle) * 1.5)
		end
		self.light.Brightness = 0.7 + 0.25 * math.sin(t * 1.2)
	end,
}

-- ---------------------------------------------------------------- 6. Umbral Veil: scribbled shadow wings and static
-- Signature: wings of frantic scribbled shadow twitch on the back, redrawn many times a second, with
-- static fizzing at the body's edges and stars winking. Stage 2: the shadow tears, glitch blocks burst
-- off the body and the wings jump and split into an offset ghost copy.

Designs.UmbralVeil = {
	build = function(self)
		self.back = self:attach("Torso", Vector3.new(0, 0.3, 0.45))
		self.wings = {}
		for _, side in { -1, 1 } do
			for k = 1, 3 do
				local tip = self:attach("Torso", Vector3.new(side * (1.4 + k * 0.7), 0.3 + (2 - k) * 0.7, 0.9))
				for _, ghost in { false, true } do
					local b = self:beam(self.back, tip, "UV_Scribble", {
						Width0 = 0.3,
						Width1 = 1.1 - k * 0.2,
						TextureMode = Enum.TextureMode.Stretch,
						LightEmission = ghost and 0.8 or 0,
						Transparency = numbers({ { 0, 0.1 }, { 1, 0.3 } }),
					}, ghost and "Accent" or "Main", ghost and 2 or 0, { { 0, 0 }, { 1, 0 } })
					table.insert(self.wings, { beam = b, tip = tip, home = tip.Position, ghost = ghost, side = side, k = k })
				end
			end
		end
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso", "Head" }) do
			self:emitter(self:attach(part), "UV_Static", {
				Size = numbers({ { 0, 1.1 }, { 1, 1.3 } }),
				Transparency = numbers({ { 0, 0.4 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.08, 0.16),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				LightEmission = 0,
				Rate = 10,
			}, "Glow", 0, { { 0, 0 }, { 1, 0 } })
		end
		self:emitter(self:attach("Torso"), "UV_Star", {
			Size = numbers({ { 0, 0 }, { 0.5, 0.35 }, { 1, 0 } }),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(1, 2.5),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			Rotation = NumberRange.new(0, 0),
			LightEmission = 1,
			Rate = 6,
		}, "Accent")
		self.glitch = self:emitter(self:attach("Torso"), "UV_Glitch", {
			Size = numbers({ { 0, 1.2 }, { 1, 1.6 } }),
			Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.08, 0.2),
			Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 0),
			LightEmission = 0.7,
			Rate = 14,
		}, "Accent", 2)
	end,
	update = function(self, t)
		self.nextScribble = self.nextScribble or 0
		local redraw = t >= self.nextScribble
		if redraw then
			self.nextScribble = t + 0.08
		end
		local torn = self.stage == 2
		for _, w in self.wings do
			if self:live(w.beam) then
				if redraw then
					w.beam.TextureOffset = math.random() -- a fresh scribble each redraw
				end
				local sway = math.sin(t * 1.6 + w.k) * 0.15
				local jump = Vector3.zero
				if torn and math.random() < 0.08 then
					jump = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.8
				end
				local ghostShift = w.ghost and Vector3.new(0.12 * w.side, 0.06, 0) or Vector3.zero
				w.tip.Position = w.home + Vector3.new(0, sway, sway * 0.5) + jump + ghostShift
			end
		end
	end,
}

-- ---------------------------------------------------------------- 7. Radiant Edge: light tracing the body's outline
-- Signature: razor-thin lines of white light run up the edges of every limb over and over, as if the
-- body is being drawn in light, under a slowly turning halo, with dark wisps licking off. Stage 2:
-- the tracing quickens, a second halo counter-rotates and shards of light fly off.

Designs.RadiantEdge = {
	build = function(self)
		self.tracers = {}
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso" }) do
			for _, side in { -1, 1 } do
				local a0, a1 = self:attach(part), self:attach(part)
				local tr = self:trail(a0, a1, "RE_Edge", {
					Lifetime = 0.3,
					LightEmission = 1,
					Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				}, "Main", 0, { { 0, 0.6 }, { 1, 0.2 } })
				table.insert(self.tracers, { a0 = a0, a1 = a1, trail = tr, part = part, side = side, offset = math.random(), last = 0 })
			end
		end
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Torso", "Head" }) do
			self:emitter(self:attach(part), "RE_Wisp", {
				Size = numbers({ { 0, 0.4 }, { 1, 0.9 } }),
				Transparency = numbers({ { 0, 1 }, { 0.25, 0.3 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1.0),
				Speed = NumberRange.new(1, 2.2),
				SpreadAngle = Vector2.new(25, 25),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(-20, 20),
				LightEmission = 0,
				Rate = 4,
			}, "Glow", 0, { { 0, 0 }, { 1, -0.3 } })
		end
		local behind = self:attach("Head", Vector3.new(0, 0.25, 0.6))
		self:emitter(behind, "RE_Halo", {
			Size = numbers({ { 0, 2.3 }, { 1, 2.3 } }),
			Transparency = numbers({ { 0, 1 }, { 0.2, 0.15 }, { 0.8, 0.15 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.5, 1.5),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			RotSpeed = NumberRange.new(25, 25),
			LightEmission = 1,
			Rate = 1.4,
		}, "Main", 0, { { 0, 0.3 }, { 1, 0.3 } })
		self:emitter(behind, "RE_Halo", {
			Size = numbers({ { 0, 3.2 }, { 1, 3.2 } }),
			Transparency = numbers({ { 0, 1 }, { 0.2, 0.35 }, { 0.8, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.5, 1.5),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			RotSpeed = NumberRange.new(-45, -45),
			LightEmission = 1,
			Rate = 1.4,
		}, "Accent", 2)
		self.shards = self:emitter(self:attach("Torso"), "RE_Shard", {
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Size = numbers({ { 0, 0.3 }, { 1, 0 } }),
			Lifetime = NumberRange.new(0.3, 0.5),
			Speed = NumberRange.new(10, 16),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
			Rate = 18,
		}, "Accent", 2)
		self.light = self:light("Torso", "Main", 12)
	end,
	update = function(self, t)
		local speed = self.stage == 2 and 2.2 or 1.4
		for _, tr in self.tracers do
			local cycle = (t * speed + tr.offset) % 1
			if cycle < tr.last then
				tr.trail:Clear()
			end
			tr.last = cycle
			local size = tr.part.Size
			local y = (cycle - 0.5) * size.Y
			local x = tr.side * (size.X / 2 + 0.02)
			tr.a0.Position = Vector3.new(x, y, 0)
			tr.a1.Position = Vector3.new(x + tr.side * 0.06, y, 0)
		end
		self.light.Brightness = 1.2 + 0.3 * math.sin(t * 3)
	end,
}

-- ---------------------------------------------------------------- 8. Phantom Blaze: hollow ghost fire and will-o'-wisps
-- Signature: hollow, bright-edged phantom fire clings to every limb over a smoky core, while
-- will-o'-wisps drift round the body in slow figure-eights. Stage 2: the hands erupt into towering
-- phantom fire and the wisps multiply and quicken.

Designs.PhantomBlaze = {
	build = function(self)
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso", "Head" }) do
			local a = self:attach(part)
			self:emitter(a, "PB_Flame", {
				Size = numbers({ { 0, 0.6 }, { 0.5, 1.2 }, { 1, 0.3 } }),
				Transparency = numbers({ { 0, 1 }, { 0.15, 0.05 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.45, 0.75),
				Speed = NumberRange.new(1.5, 3),
				SpreadAngle = Vector2.new(15, 15),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(-12, 12),
				LightEmission = 0.8,
				Rate = 8,
			}, "Main", 0, { { 0, 0.3 }, { 0.5, 0 }, { 1, -0.3 } })
			self:emitter(a, "PB_Smoke", {
				Size = numbers({ { 0, 0.8 }, { 1, 1.6 } }),
				Transparency = numbers({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.8, 1.2),
				Speed = NumberRange.new(0.5, 1),
				EmissionDirection = Enum.NormalId.Top,
				RotSpeed = NumberRange.new(-30, 30),
				LightEmission = 0,
				Rate = 3,
			}, "Glow", 0, { { 0, 0 }, { 1, -0.3 } })
		end
		for _, slot in { "LeftHand", "RightHand" } do
			self:emitter(self:attach(slot, self:endOf(slot)), "PB_Flame", {
				Size = numbers({ { 0, 1 }, { 0.5, 2.6 }, { 1, 0.6 } }),
				Transparency = numbers({ { 0, 1 }, { 0.12, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(4, 6),
				SpreadAngle = Vector2.new(10, 10),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(-8, 8),
				LightEmission = 0.9,
				Rate = 22,
			}, "Accent", 2, { { 0, 0.4 }, { 0.5, 0 }, { 1, -0.3 } })
		end
		self.wisps = {}
		for i = 1, 5 do
			local a = self:attach("Root")
			local stage = i <= 3 and 0 or 2
			self:emitter(a, "PB_Wisp", {
				Size = numbers({ { 0, 0.5 }, { 1, 0 } }),
				Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.35, 0.5),
				Speed = NumberRange.new(0, 0),
				Rotation = NumberRange.new(0, 0),
				LightEmission = 1,
				Rate = 30,
			}, "Accent", stage, { { 0, 0.5 }, { 1, 0 } })
			table.insert(self.wisps, { a = a, phase = i * 1.3, stage2 = stage == 2 })
		end
		self.light = self:light("Torso", "Main", 12)
	end,
	update = function(self, t)
		local speed = self.stage == 2 and 1.7 or 1
		for i, w in ipairs(self.wisps) do
			local s = t * 0.9 * speed + w.phase
			-- a slow figure-eight round the body
			w.a.Position = Vector3.new(math.sin(s) * 2.2, 0.6 * math.sin(s * 2 + i), math.sin(s) * math.cos(s) * 2.2)
		end
		self.light.Brightness = 1 + 0.4 * math.sin(t * 7) + 0.2 * math.sin(t * 13)
	end,
}

-- ---------------------------------------------------------------- 9. Dusk Wings: wings of energy and blades of light
-- Signature: two great wings of glowing ribs and see-through light membrane unfold from the upper back
-- and beat slowly, shedding feathers, while crescent blades of light slash the air around the body.
-- Stage 2: the wings span wider and a second, smaller pair opens below them; the slashes double.

local function wing(self, side, scale, lift, stage)
	local back = self:attach("Torso", Vector3.new(side * 0.25, 0.35 + lift, 0.5))
	local ribs = {}
	local angles = { 80, 55, 32, 12, -8 }
	for k, deg in ipairs(angles) do
		local tip = self:attach("Torso")
		local length = (2.2 + (k == 2 and 0.5 or 0) - (k - 1) * 0.15) * scale
		local b = self:beam(back, tip, "DW_Rib", {
			Width0 = 0.18 * scale,
			Width1 = 0.05 * scale,
			TextureMode = Enum.TextureMode.Stretch,
			LightEmission = 1,
			CurveSize0 = 0.4 * scale,
		}, "Glow", stage, { { 0, 0.5 }, { 1, 0.1 } })
		table.insert(ribs, { tip = tip, deg = deg, length = length, beam = b })
	end
	local membranes = {}
	for k = 1, #ribs - 1 do
		local mid = self:attach("Torso")
		local b = self:beam(back, mid, "DW_Membrane", {
			Width0 = 0.1,
			Width1 = 1,
			TextureMode = Enum.TextureMode.Stretch,
			LightEmission = 0.8,
			Transparency = numbers({ { 0, 0.5 }, { 1, 0.2 } }),
		}, "Glow", stage, { { 0, 0.3 }, { 1, 0 } })
		table.insert(membranes, { mid = mid, a = ribs[k], b = ribs[k + 1], beam = b })
	end
	self:emitter(ribs[2].tip, "DW_Feather", {
		Size = numbers({ { 0, 0.4 }, { 1, 0.3 } }),
		Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.5, 2.2),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1, 0),
		RotSpeed = NumberRange.new(-60, 60),
		LightEmission = 0.6,
		Rate = stage == 2 and 2 or 3,
	}, "Accent", stage)
	return { back = back, side = side, scale = scale, lift = lift, ribs = ribs, membranes = membranes }
end

Designs.DuskWings = {
	build = function(self)
		self.wingSet = {
			wing(self, -1, 1, 0, 1),
			wing(self, 1, 1, 0, 1),
			wing(self, -1, 1.3, 0, 2),
			wing(self, 1, 1.3, 0, 2),
			wing(self, -1, 0.65, -0.9, 2),
			wing(self, 1, 0.65, -0.9, 2),
		}
		self.slashes = self:emitter(self:attach("Root", Vector3.new(0, 0.3, 0)), "DW_Slash", {
			Size = numbers({ { 0, 1.5 }, { 0.3, 3 }, { 1, 3.4 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.2, 0.3),
			Speed = NumberRange.new(0, 0),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 1,
			Rate = 4,
		}, "Main", 0, { { 0, 0.4 }, { 1, 0 } })
		self:emitter(self:attach("Torso"), "Glow", {
			Size = numbers({ { 0, 4 }, { 1, 5 } }),
			Transparency = numbers({ { 0, 1 }, { 0.3, 0.85 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			LightEmission = 1,
			Rate = 3,
		}, "Glow")
		self.light = self:light("Torso", "Glow", 14)
	end,
	update = function(self, t)
		local beat = math.sin(t * 1.6) -- a slow wing beat
		for _, w in self.wingSet do
			if self:live(w.ribs[1].beam) then
				local base = w.back.Position
				for _, rib in w.ribs do
					local a = math.rad(rib.deg + beat * 10)
					local sweep = 0.55 + 0.35 * beat -- how far the wing sweeps back
					local dir = Vector3.new(w.side * math.cos(a), math.sin(a), sweep * math.cos(a) * 0.6)
					rib.tip.Position = base + dir.Unit * rib.length
				end
				for _, m in w.membranes do
					local pa, pb = m.a.tip.Position, m.b.tip.Position
					m.mid.Position = (pa + pb) / 2
					m.beam.Width1 = (pa - pb).Magnitude
				end
			end
		end
		self.slashes.Rate = self.stage == 2 and 8 or 4
		self.light.Brightness = 1.1 + 0.3 * beat
	end,
}

-- ---------------------------------------------------------------- 10. Silver Sheen: light flowing over the body like liquid metal
-- Signature: bands of silver sheen slide up the limbs like light across polished metal, with silver
-- dust settling round the body. Stage 2: mercury ripples roll up the body ring by ring, and bright
-- flares glint on the limbs.

Designs.SilverSheen = {
	build = function(self)
		for _, part in self:parts({ "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso", "Head" }) do
			self:emitter(self:attach(part, Vector3.new(0, -part.Size.Y / 2, 0)), "SS_Band", {
				Size = numbers({ { 0, part.Size.X * 1.4 }, { 1, part.Size.X * 1.4 } }),
				Transparency = numbers({ { 0, 1 }, { 0.25, 0.35 }, { 0.75, 0.35 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.9, 0.9),
				Speed = NumberRange.new(part.Size.Y / 0.9, part.Size.Y / 0.9),
				EmissionDirection = Enum.NormalId.Top,
				LockedToPart = true,
				Rotation = NumberRange.new(0, 0),
				LightEmission = 0.6,
				Rate = 1.6,
			}, "Main", 0, { { 0, 0.4 }, { 1, 0.4 } })
		end
		self:emitter(self:attach("Head", Vector3.new(0, 1.5, 0)), "SS_Mote", {
			Size = numbers({ { 0, 0 }, { 0.2, 0.2 }, { 1, 0.1 } }),
			Transparency = numbers({ { 0, 0 }, { 0.5, 0.5 }, { 0.6, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(0, -0.4, 0),
			LightEmission = 1,
			Rate = 7,
		}, "Accent")
		self:emitter(self:attach("Torso"), "Glow", {
			Size = numbers({ { 0, 4 }, { 1, 5 } }),
			Transparency = numbers({ { 0, 1 }, { 0.4, 0.82 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 1.6),
			Speed = NumberRange.new(0, 0),
			LockedToPart = true,
			LightEmission = 0.7,
			Rate = 2.5,
		}, "Glow")
		self.rippler = self:attach("Root")
		self.ripples = self:emitter(self.rippler, "SS_Ripple", {
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = numbers({ { 0, 1.5 }, { 1, 4.5 } }),
			Transparency = numbers({ { 0, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.5),
			Speed = NumberRange.new(0.01, 0.01),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 0),
			LockedToPart = true,
			LightEmission = 1,
		}, "Main", 2, { { 0, 0.5 }, { 1, 0.2 } }, true)
		-- overcharge: silver crackling off the body in quick bright flecks
		self:emitter(self:attach("Torso"), "SS_Mote", {
			Size = numbers({ { 0, 0.3 }, { 1, 0 } }),
			Transparency = numbers({ { 0, 0 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.15, 0.3),
			Speed = NumberRange.new(8, 14),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 6,
			LightEmission = 1,
			Rate = 26,
		}, "Accent", 2)
		self.flares = {}
		for _, slot in { "LeftHand", "RightHand", "Head", "LeftArm", "RightArm", "Torso" } do
			table.insert(self.flares, self:emitter(self:attach(slot, self:endOf(slot)), "SS_Flare", {
				Size = numbers({ { 0, 0 }, { 0.3, 1.6 }, { 1, 0 } }),
				Lifetime = NumberRange.new(0.3, 0.3),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
				RotSpeed = NumberRange.new(90, 90),
				LightEmission = 1,
			}, "Accent", 2, nil, true))
		end
		self.light = self:light("Torso", "Glow", 12)
	end,
	update = function(self, t)
		if self.stage == 2 then
			-- a ripple rolls up the body every 0.3 s
			local cycle = (t / 1.5) % 1
			self.rippler.Position = Vector3.new(0, -2.8 + cycle * 5, 0)
			self.nextRipple = self.nextRipple or 0
			if t >= self.nextRipple then
				self.ripples:Emit(1)
				self.nextRipple = t + 0.3
			end
			self.nextFlare = self.nextFlare or 0
			if t >= self.nextFlare then
				self.flares[math.random(1, #self.flares)]:Emit(1)
				self.nextFlare = t + 0.25 + math.random() * 0.4
			end
		end
		self.light.Brightness = (self.stage == 2 and 1.4 or 0.9) + 0.15 * math.sin(t * 0.8)
	end,
}

-- ---------------------------------------------------------------- public API

-- Builds an aura on a character. colors = { Main, Accent, Glow } (any missing use the defaults).
-- Returns a handle with :SetStage(1|2), :SetColors(colors) and :Destroy().
function EterniumAuras.apply(character, name, colors, stage)
	local design = Designs[name]
	assert(design, "Unknown aura " .. tostring(name))
	local self = setmetatable({
		name = name,
		design = design,
		character = character,
		rig = buildRig(character),
		items = {},
		instances = {},
		stageOf = {},
		stage = 0,
	}, Aura)
	assert(self.rig.Root and self.rig.Torso and self.rig.Head, "EterniumAuras: " .. character.Name .. " is missing body parts")
	design.build(self)
	if design.init then
		design.init(self)
	end
	self:SetColors(colors)
	self:SetStage(stage or 1)
	self:playSound("Loop")

	local start = os.clock()
	local event = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
	self.connection = event:Connect(function(dt)
		if not character.Parent then
			self:Destroy()
			return
		end
		if design.update then
			design.update(self, os.clock() - start, dt)
		end
	end)
	return self
end

local function readColors(character)
	return {
		Main = character:GetAttribute("AuraMain"),
		Accent = character:GetAttribute("AuraAccent"),
		Glow = character:GetAttribute("AuraGlow"),
	}
end

-- Client-side: keeps every player's aura in sync with attributes on their character:
--   Aura (string, empty = none), AuraStage (1/2), AuraMain / AuraAccent / AuraGlow (Color3).
-- Call once from a LocalScript. Returns a function that stops watching.
function EterniumAuras.watch()
	local active = {}
	local connections = {}

	local function refresh(character)
		local name = character:GetAttribute("Aura")
		local current = active[character]
		if current and current.name ~= name then
			current:Destroy()
			active[character] = nil
			current = nil
		end
		if not name or name == "" or not Designs[name] then
			return
		end
		if not current then
			local ok, aura = pcall(EterniumAuras.apply, character, name, readColors(character), character:GetAttribute("AuraStage"))
			if ok then
				active[character] = aura
			else
				warn(aura)
			end
		else
			current:SetColors(readColors(character))
			current:SetStage(character:GetAttribute("AuraStage"))
		end
	end

	local function hook(character)
		character:WaitForChild("HumanoidRootPart", 10)
		refresh(character)
		table.insert(connections, character.AttributeChanged:Connect(function(attribute)
			if string.sub(attribute, 1, 4) == "Aura" then
				refresh(character)
			end
		end))
		table.insert(connections, character.AncestryChanged:Connect(function(_, parent)
			if not parent and active[character] then
				active[character]:Destroy()
				active[character] = nil
			end
		end))
	end

	local function watchPlayer(player)
		if player.Character then
			task.spawn(hook, player.Character)
		end
		table.insert(connections, player.CharacterAdded:Connect(hook))
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		for _, aura in active do
			aura:Destroy()
		end
		active = {}
	end
end

EterniumAuras.List = {
	"LimitBreaker", "VoidCurrent", "AzureSurge", "FrostCrown", "VerdantBloom",
	"UmbralVeil", "RadiantEdge", "PhantomBlaze", "DuskWings", "SilverSheen",
}

return EterniumAuras
