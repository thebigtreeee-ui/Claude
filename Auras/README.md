# Eternium Auras

The ten player auras, rebuilt from scratch. No Creator Store packs and no meshes: every aura is built
by `EterniumAuras.lua` out of particles, beams, trails and lights riding the body parts (R15 and R6),
and animated every frame.

The rules every aura follows:
- **Individual:** each aura has its **own textures** and its **own signature motion**. No layer is
  shared between auras. The test suite checks that no texture is used by two of them (the soft haze
  texture aside).
- **Recolourable** from the three picks:
  - **Main:** the body of the aura.
  - **Accent:** sparks and details.
  - **Glow:** outline, haze and the light it casts.
- **Stage 2** changes each aura in its own way, and switching stages re-plays the ignite effect.

![Textures](textures/_contact_sheet.png)

## The ten auras

| Aura | Signature (Stage 1) | Stage 2 |
|---|---|---|
| **Limit Breaker** (default) | Ribbons of light **spiral up round the body like a drill of energy**. Streaks shoot off the hands and feet, chevrons of power rise from the ground, and the gold light throbs twice a second | Six ribbons instead of three, 20% taller and 25% faster, with **pressure rings bursting out along the ground** |
| **Void Current** | Dark flames with black edges rise off the limbs while the darkness **drips off the hands and body and pools at the feet** in a slow, rotating whirl | **Shadow tendrils writhe** from the hands down into the pool |
| **Azure Surge** | **Real arcs leap from limb to limb**, re-forming many times a second, over a crackling skin of static, with spark bursts popping on the hands, chest and head | Both arms become **storm conduits** wrapped in continuous lightning, and a **ring of static spins above the head** |
| **Frost Crown** | A **crown of ice crystals hovers and turns above the head**. Cold wind circles the body, ice forms on the limbs and breaks off, snowflakes drift and glints sparkle | A **taller, wider crown** (11 crystals), **crystal pauldrons** on the shoulders and a thicker blizzard |
| **Verdant Bloom** | Soft **ripples spread from the feet** while **petals spiral up out of them in a slow vortex**, and leaves tumble round the body | **Flowers bloom** on the shoulders and head, and a gentle **spirit flame** rises from the ring of ripples |
| **Umbral Veil** | Wings of **frantic scribbled shadow** twitch on the back, redrawn many times a second. Static fizzes at the body's edges and stars wink, framing the body without covering it | The shadow **tears**: glitch blocks burst off the body, and the wings jump and split into an offset ghost copy |
| **Radiant Edge** | Razor-thin lines of light **run up the edges of every limb over and over**, as if the body were being drawn in light, under a slowly turning **halo**, with dark wisps licking off | The tracing quickens, a **second halo counter-rotates** and **shards of light** fly off |
| **Phantom Blaze** | **Hollow, bright-edged ghost fire** clings to every limb over a smoky core, while **will-o'-wisps drift round the body in slow figure-eights** | The **hands erupt into towering phantom fire**, and the wisps multiply and quicken |
| **Dusk Wings** | Two great **wings of glowing ribs and see-through light membrane** beat slowly from the upper back, shedding feathers, while **crescent blades of light slash the air** around the body | The wings **span wider** and a **second, smaller pair** opens below them, with twice as many slashes |
| **Silver Sheen** | **Bands of sheen slide up the limbs** like light across polished metal, with silver dust settling round the body | **Mercury ripples roll up the body** ring by ring, bright **flares glint** on the limbs, and silver crackles off |

## Setup

### 1. Upload the textures (once)
1. In Studio, open **View → Asset Manager → Bulk Import** and select every PNG in `textures/`
   (all except `_contact_sheet.png`).
2. Copy each image's asset ID (right-click → Copy Asset ID).
3. Paste each ID into `EterniumAuras.Textures` at the top of the module, as
   `LB_Trail = "rbxassetid://123..."` and so on.

Any texture left empty falls back to a built-in Roblox texture, so the auras work straight away.
They'll only look truly individual once the uploads are in.

### 2. Add the module
Put `EterniumAuras.lua` in `ReplicatedStorage.Eternium` as a ModuleScript named `EterniumAuras`.
Optionally fill `EterniumAuras.Sounds` with your existing ignite and loop sounds:

```lua
EterniumAuras.Sounds.LimitBreaker = { Ignite = "rbxassetid://...", Loop = "rbxassetid://..." }
```

### 3. Drive it with attributes (recommended)
The auras animate every frame, so they should run on each player's own client. The server only says
which aura someone wears:

```lua
-- server, wherever the aura is equipped / recoloured / empowered
character:SetAttribute("Aura", "FrostCrown")    -- "" removes it
character:SetAttribute("AuraStage", 2)
character:SetAttribute("AuraMain", Color3.fromRGB(180, 230, 255))
character:SetAttribute("AuraAccent", Color3.fromRGB(255, 255, 255))
character:SetAttribute("AuraGlow", Color3.fromRGB(100, 180, 255))
```

```lua
-- one LocalScript (e.g. StarterPlayerScripts)
require(game.ReplicatedStorage.Eternium.EterniumAuras).watch()
```

`watch()` builds, recolours, re-stages and removes every player's aura as those attributes change,
including on respawn.

### Or drive one directly

```lua
local EterniumAuras = require(game.ReplicatedStorage.Eternium.EterniumAuras)
local aura = EterniumAuras.apply(character, "DuskWings", { Main = ..., Accent = ..., Glow = ... }, 1)
aura:SetStage(2)
aura:SetColors({ Glow = Color3.fromRGB(255, 90, 140) }) -- any picks you leave out are kept
aura:Destroy()
```

Aura names: `LimitBreaker`, `VoidCurrent`, `AzureSurge`, `FrostCrown`, `VerdantBloom`, `UmbralVeil`,
`RadiantEdge`, `PhantomBlaze`, `DuskWings`, `SilverSheen`.

### 4. Retire the old system
Once the new auras are in, the old invisible-accessory auras and the packs in
`ReplicatedStorage.Eternium.Assets.Auras` (including the unused Spiky and GoldSpiky) can be removed.

## Tweaking
- `EterniumAuras.Defaults`: each aura's default Main, Accent and Glow.
- `EterniumAuras.Designs.<Aura>`: each aura's layers (`build`), motion (`update`) and ignite burst
  (`ignite`), all written out by hand so you can adjust rates, sizes and speeds directly.
- Textures are regenerated with `python tools/build_aura_textures.py`.
