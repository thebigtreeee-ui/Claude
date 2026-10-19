# ElementVFX (v2): layered anime-style beams, blasts and ultimates

The new element effects aren't solid 3D models and aren't flat 2D images. Each one is built from
layers that Roblox renders well, on PC and on phones:

| Layer | What it gives |
|---|---|
| **Scrolling beams** (camera-facing) | The energy streams: flowing fire, crackling plasma, jittering lightning |
| **Glowing toon meshes** (Neon) | Real volume: spiral ribbons, flame cones and tongues, 3D lightning bolts, shockwave rings, cores |
| **Flipbook particles** | Hand-drawn, toon-banded animation: fire puffs, explosions, sparks, arc bursts, storm clouds |
| **Lights** | The effect lights up the world around it |

Every colour comes from three picks, so everything is recolourable:
- **Main:** the body of the effect.
- **Accent:** the hot core and highlights.
- **Glow:** the rims and the light it casts.

Preview of all six effects: [previews/ElementVFX_FireElectric.mp4](previews/ElementVFX_FireElectric.mp4).
It's rendered outside Roblox from the module's own frame-by-frame output, with the real textures, meshes and flipbooks.

**Status:** Fire and Electric are done, for your approval. The other eight elements will be built the
same way once you're happy with the style.

## The effects so far

| | Beam | Blast | Ultimate |
|---|---|---|---|
| **Fire** | A white-hot core inside three counter-flowing flame bodies, two spiralling flame ribbons, fire puffs billowing off the whole length, a flame cone at the hands, and rolling explosions with shockwaves at the impact | A fireball: a hot core in a churning shell, flame tongues licking back off it, a comet tail, embers and smoke. It bursts into an explosion with a shockwave ring, a starburst and a spray of flame | **Flames from the hands:** a ring of flame tongues bursts from the ground, fire gathers in the hands, then a colossal roaring cone of fire sets the ground alight as it passes |
| **Electric** | A plasma core inside four jittering bolts that re-strike every few frames. Electric rings race along it, arcs leap off its sides, and a storm of sparks and ground strikes lands where it hits | Ball lightning: a white core in a crackling plasma sphere, throwing arcs in every direction and trailing sparks. It bursts into radiating bolts and an electric ring | **Thunderstorm:** a black storm cloud boils up, flickering with inner lightning, then strike after strike lands, faster and faster, ending in one colossal bolt |

## Setup

1. **Textures.** Bulk-import every PNG in `textures/` (except `_contact_sheet.png`) with the
   Asset Manager. Paste each id into `VFX.Textures` at the top of the module.
   - The `*4` and `*8` sheets are flipbooks: 4×4 and 8×8 grids. The module sets up the grid itself.
   - Until the ids are in, built-in Roblox textures stand in, without the animation.
2. **Meshes.** Import every `.obj` in `meshes/` with the 3D Importer.
   - Put the resulting MeshParts in a Folder named `VFXMeshes`, next to the module (same parent).
   - Keep each MeshPart named as its file: `Spiral`, `FlameCone`, `Tongue1`, `Bolt2` and so on.
   - The meshes are already in Roblox axes (Y up, forward = -Z), so no rotation is needed.
   - If the folder is missing, the effects still run, just without the mesh layers.
3. **Module.** Put `ElementVFX.lua` in `ReplicatedStorage.Eternium` as a ModuleScript named `ElementVFX`.

## Use

Effects are visual only. Fire a RemoteEvent to all clients and play them there:

```lua
local VFX = require(game.ReplicatedStorage.Eternium.ElementVFX)

-- beam: origin can be a Vector3, a CFrame, an Attachment or a BasePart (a part/attachment is followed)
VFX.beam("Fire", character.RightHand, mouseHitPosition, { duration = 2.2, width = 1 })

-- blast: travels to the target and explodes there; onHit fires on impact
VFX.blast("Electric", character.RightHand.Position, target, {
	speed = 85,
	onHit = function(position) end,
})

-- ultimate: at = a CFrame at the user's feet, facing where the move goes
VFX.ultimate("Fire", character.HumanoidRootPart.CFrame * CFrame.new(0, -3, 0))
VFX.ultimate("Electric", rootCFrame, { distance = 20 })  -- storm centred 20 studs ahead
```

**Recolouring:**
- Pass any of the picks: `{ colors = { Main = ..., Accent = ..., Glow = ... } }`.
- Or pass `{ color = ... }` to change Main only.

**Handles:** every call returns a handle. `handle:Destroy()` ends the effect at once and cleans
everything up.

**Old names still work:** `VFX.fire` = `VFX.beam`, and `VFX.play` = `VFX.ultimate`.

## Performance

- On low graphics settings the effects automatically halve their particles and arcs. Set
  `VFX.Quality = 1` (full) or `0.5` (light) to force one.
- A typical beam uses about 45–65 instances. The thunderstorm peaks around 220.
- Everything cleans itself up when the effect ends.

## Rebuilding the assets

```
python tools/vfx/textures.py   # textures + flipbooks -> ElementVFX/textures
python tools/vfx/meshes.py     # toon meshes (OBJ)    -> ElementVFX/meshes
```
