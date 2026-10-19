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

Previews (rendered outside Roblox from the module's own frame-by-frame output, with the real
textures, meshes, flipbooks and sounds):
- [previews/ElementVFX_FireElectric.mp4](previews/ElementVFX_FireElectric.mp4): Fire and Electric.
- [previews/ElementVFX_AllElements.mp4](previews/ElementVFX_AllElements.mp4): the other eight, with sound.

**Status:** all ten elements are done, each with a beam, a blast and an ultimate, and every move has
its own sound effects.

## The effects

| | Beam | Blast | Ultimate |
|---|---|---|---|
| **Fire** | A white-hot core inside three counter-flowing flame bodies, two spiralling flame ribbons, fire puffs billowing off the whole length, a flame cone at the hands, and rolling explosions with shockwaves at the impact | A fireball: a hot core in a churning shell, flame tongues licking back off it, a comet tail, embers and smoke. It bursts into an explosion with a shockwave ring, a starburst and a spray of flame | **Flames from the hands:** a ring of flame tongues bursts from the ground, fire gathers in the hands, then a colossal roaring cone of fire sets the ground alight as it passes |
| **Electric** | A plasma core inside four jittering bolts that re-strike every few frames. Electric rings race along it, arcs leap off its sides, and a storm of sparks and ground strikes lands where it hits | Ball lightning: a white core in a crackling plasma sphere, throwing arcs in every direction and trailing sparks. It bursts into radiating bolts and an electric ring | **Thunderstorm:** a black storm cloud boils up, flickering with inner lightning, then strike after strike lands, faster and faster, ending in one colossal bolt |
| **Rift** | A crystal-lattice beam: angular cracks of light that re-split every few frames, hexagonal gates turning along it, glass shards spraying off it. Tears in space flash open at the impact and crystals stab out of it | A spinning crystal spear with a hex gate turning behind it. It lands in a splinter of reality: a tear, shards, cracks of light | **Rift Tear:** cracks splinter through the air ahead, then rip open into a blinding tear ringed by turning hex gates, spitting shards and filaments, until it snaps shut |
| **Void** | A black core in a dark violet stream with a glowing rim, black spiral tendrils and dark matter. Where it lands, a black orb swallows its surroundings, with rings of space collapsing inward | A miniature black hole: a black core in a spinning violet disc and a burning photon ring. It swallows the air round it, then bursts | **Event Horizon:** a black hole opens ahead, everything is dragged into it, an accretion disc spins up and debris spirals in, then it collapses and detonates |
| **Nature** | A stream of green light wrapped in twisting vines, shedding leaves, petals and spores, with a flower of leaves opening at the hands; big leaves sprout out of the impact like a flower | A seed of light in a leafy shell with leaves orbiting it. It bursts into a giant flower that opens and scatters petals | **Sacred Grove (new):** spores of light rise round the user, then a ring of glowing trees bursts from the ground, their canopies bloom and pulse, then dissolve into a storm of petals |
| **Ice** | A freezing ray: crystals of ice grow out of the air all along it, frost mist and snowflakes, a crown of ice at the hands, a cluster of spikes at the impact; when it stops, every crystal shatters | An ice spear with a glowing heart, trailing frost. It shatters into flying shards and a cluster of ice spikes | **Glacier Wall:** a stomp sends frost racing over the ground, a wall of ice erupts section by section, mist rolls at its base and snow falls, then the whole wall shatters |
| **Wind** | Streaks of wind spiralling round each other, crescent blades swirling along it, rings of pressure racing down it; slashing crescents and dust at the impact | A flat glowing crescent blade with a sheet of wind streaming off it. It bursts into a whirl of slashes, swirls and dust | **Thunderclap:** one clap, and the air explodes: pressure shells balloon out, rings of air blast forward, crescents slash outward along the ground in a ring of dust |
| **Earth** | A molten line inside a stream of grinding stone, boulders tumbling along it, pebbles and dust pouring off it; rock bursts and lava cracks open at the impact | A boulder with glowing molten seams, tumbling through dust and grit. It smashes into flying rock, dust, lava cracks and spikes of stone | **Tectonic Fury:** a glowing fissure races forward, slabs heave up, spires erupt one after another, boulders tear free and float, then all slam down at the end; the earth settles back |
| **Water** | A pressurised jet: a bright core in a rushing stream, spiralling ribbons of water, spray and foam; a crown of splashes and ripples where it hits | A wobbling water orb with a bright heart and a ring of current. It bursts in a dome of water, a crown splash and ripples | **Tidal Crash:** water surges up round the user, a towering wave rises behind them, rolls forward with foam pouring off its crest and crashes down ahead |
| **Energy** | A thick blue ki wave with a blinding core, a spiral of energy round it and a huge sphere of ki leading its head; it slams into an explosion of light and rings | A ki ball: a blazing core in a pulsing sphere with two gyro rings and a sparkle trail. It detonates in a dome of light | **Spirit Bomb:** streaks of energy pour in from every direction and a giant sphere of ki swells overhead; it is hurled forward and detonates in a vast dome of light |

## Sounds

Every element has its own synthesized sound set, matched to its look and timed to its moves:

| File | When it plays |
|---|---|
| `<Element>_Beam_Start` | The moment the beam fires |
| `<Element>_Beam_Loop` | Loops while the beam is on, then fades out |
| `<Element>_Blast_Cast` | At launch; it travels with the projectile |
| `<Element>_Blast_Hit` | On impact |
| `<Element>_Ultimate` | One track for the whole ultimate, synced to its timeline |
| `Electric_Strike` | Each lightning strike in the thunderstorm |

All sounds play in 3D from the effect itself, so they get quieter with distance. An effect stays alive
until its sounds have finished.
- Pass `{ sounds = false }` to mute one call, or `{ volume = 0.5 }` to scale it.
- Set `VFX.SoundVolume` to scale every effect's sounds.

## Setup

1. **Textures.** Bulk-import every PNG in `textures/` (except `_contact_sheet.png`) with the
   Asset Manager. Paste each id into `VFX.Textures` at the top of the module, or into the `ElementVFXAssets` template (see `IMPORT_GUIDE.md`).
   - The `*4` and `*8` sheets are flipbooks: 4×4 and 8×8 grids. The module sets up the grid itself.
   - Until the ids are in, built-in Roblox textures stand in, without the animation.
2. **Meshes.** Import every `.obj` in `meshes/` with the 3D Importer.
   - Put the resulting MeshParts in a Folder named `VFXMeshes`, next to the module (same parent).
   - Keep each MeshPart named as its file: `Spiral`, `FlameCone`, `Tongue1`, `Bolt2` and so on.
   - The meshes are already in Roblox axes (Y up, forward = -Z), so no rotation is needed.
   - If the folder is missing, the effects still run, just without the mesh layers.
3. **Sounds.** Bulk-import every OGG in `sounds/` and paste each id into `VFX.Sounds` (the keys
   match the file names, e.g. `Rift_Beam_Start`). Sounds with no id are simply skipped.
4. **Module.** Put `ElementVFX.lua` in `ReplicatedStorage.Eternium` as a ModuleScript named `ElementVFX`.

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
VFX.ultimate("Energy", rootCFrame, { distance = 40 })    -- where the Spirit Bomb lands
```

**Ultimate options:**
- `scale` sizes any ultimate.
- `distance` sets how far ahead it happens, for Electric, Rift, Void, Ice and Energy.
- `reach` sets how far it travels, for Fire, Earth and Water.

**Recolouring:**
- Pass any of the picks: `{ colors = { Main = ..., Accent = ..., Glow = ... } }`.
- Or pass `{ color = ... }` to change Main only.

**Handles:** every call returns a handle. `handle:Destroy()` ends the effect at once and cleans
everything up.

**Old names still work:** `VFX.fire` = `VFX.beam`, and `VFX.play` = `VFX.ultimate`.

## Performance

- On low graphics settings the effects automatically halve their particles and arcs. Set
  `VFX.Quality = 1` (full) or `0.5` (light) to force one.
- A typical beam uses about 40–65 instances. The biggest ultimates (the thunderstorm, Tectonic Fury,
  Event Horizon) peak at about 150–220.
- Everything cleans itself up when the effect ends.

## Rebuilding the assets

```
python tools/vfx/textures.py   # textures + flipbooks -> ElementVFX/textures
python tools/vfx/meshes.py     # toon meshes (OBJ)    -> ElementVFX/meshes
python tools/vfx/sounds.py     # sound effects (OGG)  -> ElementVFX/sounds
```
