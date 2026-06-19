# Assets

Imported 3D art (models, textures, materials). Code-built primitives still live
with their scenes under `addons/godot-multiplayer-weapon-system/`; this folder is
for downloaded/authored art.

## Layout

One subfolder **per pack** so each keeps its own relative texture paths:

```
assets/
  characters/<pack-name>/      players, bots
  props/<pack-name>/           weapons, grenades, pickups, small objects
  environments/<pack-name>/    map geometry, large set pieces
  CREDITS.md                   license + attribution for every pack (required)
```

## Format

**glTF 2.0 (`.glb` preferred, `.gltf`+textures also fine).** Godot 4 imports it
natively — just copy the files in and open the editor once; it generates a
`.import` sidecar per asset and a regenerable cache under `.godot/imported/`.

- `.glb` is self-contained (geometry + textures in one file) — simplest.
- `.gltf` keeps textures as separate files; keep them alongside the `.gltf`.

## Using a model (don't edit the import in place)

Instance the `.glb` in a scene, **or** right-click it → *New Inherited Scene* and
customize the copy. Never edit the imported file directly — re-importing wipes
changes. Per-asset import options (select the file → Import tab) control:

- **Scale** — glTF is metres / Y-up; fix here if a pack came in at the wrong size.
- **Collision** — generate a collision shape (e.g. *Single Convex* for props,
  *Trimesh* for static map geometry) instead of hand-building one.
- **Materials** — extract to `.tres` if you want to tweak/override them.

## Web / performance budget

This ships to the web on the **gl_compatibility** renderer with a quick-load
goal, so mind download size:

- Textures ≤ 1–2K; prefer `.glb` with embedded, reasonably-sized textures.
- Decimate high-poly meshes — silhouettes matter more than detail here, and the
  outline/dither look hides low-poly well.
- Watch the total committed art size; large packs balloon the web build.

## Committing

Commit the **source files** (`.glb`/`.gltf`/textures) **and** the generated
`.import` sidecars. The `.godot/` cache is gitignored and regenerates on import.
