# ElementVFX import guide (hand-off for whoever imports this into Roblox)

This package is a finished Roblox VFX system for the game **Eternium**: 10 elements (Fire, Electric,
Rift, Void, Nature, Ice, Wind, Earth, Water, Energy), each with a **beam**, a **blast** and an
**ultimate**, plus synthesized 3D sound effects for every move. The code is done and tested; the only
work left is importing the assets into Roblox Studio and wiring up their ids.

## What's in the package

| Path | What it is | Count |
|---|---|---|
| `ElementVFX.lua` | The ModuleScript: all effects and the public API | 1 |
| `ElementVFXAssets.lua` | A ModuleScript template where the uploaded asset ids get pasted | 1 |
| `textures/*.png` | Beam textures, particle sprites and flipbook sheets (`*4` = 4×4 grid, `*8` = 8×8 grid) | 59 (+ `_contact_sheet.png`, a preview only; don't upload it) |
| `meshes/*.obj` | Toon meshes, already in Roblox axes (Y up, forward = -Z) | 34 |
| `sounds/*.ogg` | Sound effects (mono OGG Vorbis) | 51 |
| `README.md` | Full API and effect descriptions | |
| `previews/*.mp4` | Preview video(s), for reference only | |

## Target layout in Studio

```
ReplicatedStorage
└── Eternium                  (Folder)
    ├── ElementVFX            (ModuleScript)  <- contents of ElementVFX.lua
    ├── ElementVFXAssets      (ModuleScript)  <- contents of ElementVFXAssets.lua, ids filled in
    └── VFXMeshes             (Folder)        <- the 34 imported MeshParts
```

All three must share the same parent. The module finds `VFXMeshes` and `ElementVFXAssets` through
`script.Parent`.

## Steps

### 1. Textures (59 PNGs)
1. Bulk-upload every PNG in `textures/` except `_contact_sheet.png` (Asset Manager → Bulk Import, or the Open Cloud Assets API).
2. In `ElementVFXAssets.lua`, under `Textures`, fill in each id: `F_Burst8 = "rbxassetid://1234567890",`.
   - The key is the file name without `.png`.
   - Upload the flipbook sheets (names ending in 4 or 8) as plain images. The module sets the grid layout itself.

### 2. Sounds (51 OGGs)
1. Bulk-upload every OGG in `sounds/`.
2. Fill in each id under `Sounds` in `ElementVFXAssets.lua`. The key is the file name without `.ogg`, for example `Rift_Beam_Start`.

### 3. Meshes (34 OBJs)
1. Import each `.obj` in `meshes/` with the 3D Importer as a **MeshPart**.
2. Name each MeshPart exactly like its file (`Spiral`, `FlameCone`, `Crystal1`, `Wave` and so on), with no suffixes like `_Mesh`.
3. Put all 34 directly inside the `VFXMeshes` folder.

Don't rotate or rescale them:
- The meshes are already in Roblox axes and normalised.
- The module scales them from each template's imported `Size`.
- Material, colour and collision are set by the module at runtime.

If the importer wraps a mesh in a Model, take the MeshPart out, rename it and delete the Model.

### 4. Module
1. Create the `ElementVFX` ModuleScript and paste `ElementVFX.lua` into it.
2. Create the `ElementVFXAssets` ModuleScript and paste your filled-in `ElementVFXAssets.lua`.

Any id left as just `"rbxassetid://"` is ignored, and the module falls back safely:
- A missing texture falls back to a built-in Roblox texture.
- A missing sound is skipped.
- A missing mesh skips that mesh layer.

So a partial import still runs.

## Verifying the import

Paste this in the Studio command bar during Play (client), or put it in a LocalScript:

```lua
local VFX = require(game.ReplicatedStorage.Eternium.ElementVFX)
local folder = game.ReplicatedStorage.Eternium.VFXMeshes
local need = { "Spiral","SpiralThin","FlameCone","Tongue1","Tongue2","Tongue3","Bolt1","Bolt2","Bolt3","Ring","RingJag",
	"ZapRing","Spikes","Orb","Crystal1","Crystal2","Crystal3","Shard1","Shard2","HexGate","Lens","Disk","Leaf","Trunk",
	"Canopy","Rock1","Rock2","Rock3","Slab1","Slab2","Spire","Crescent","Wave","Dome" }
for _, n in need do if not folder:FindFirstChild(n) then warn("missing mesh", n) end end
for k, v in VFX.Textures do if v == "" then warn("missing texture id", k) end end
for k, v in VFX.Sounds do if v == "" then warn("missing sound id", k) end end
print("check done")
```

Then try an effect in front of the player:

```lua
local root = game.Players.LocalPlayer.Character.HumanoidRootPart
VFX.ultimate("Energy", root.CFrame * CFrame.new(0, -3, 0))
VFX.beam("Rift", root, (root.CFrame * CFrame.new(0, 0, -40)).Position)
```

## Using it in the game

The effects are visual only. Run them on every client: the server fires a RemoteEvent with
`FireAllClients`, and each client calls the module.

```lua
VFX.beam(element, originPartOrVector3, targetVector3, { duration = 2.2 })
VFX.blast(element, origin, target, { onHit = function(position) end })
VFX.ultimate(element, rootCFrame * CFrame.new(0, -3, 0))   -- CFrame at the feet, facing the move
```

- `element` is one of: `"Fire"`, `"Electric"`, `"Rift"`, `"Void"`, `"Nature"`, `"Ice"`, `"Wind"`, `"Earth"`, `"Water"` or `"Energy"`.
- Every call returns a handle; `handle:Destroy()` stops the effect and cleans it up.
- Common options:
  - `colors = { Main=, Accent=, Glow= }` or `color =` to recolour.
  - `width` (beam), `size` and `speed` (blast), `scale` (ultimate).
  - `distance` / `reach` (ultimate).
  - `sounds = false` to mute, `volume` to scale the sound.
- See `README.md` for the full list.
