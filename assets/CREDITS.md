# Asset Credits

Attribution and licensing for the third-party asset packs in `assets/`.

All packs below are by **Kay Lousberg** and licensed **CC0** (public domain) —
free for personal, educational, and commercial use, **no attribution required**.
Crediting is appreciated and recorded here anyway. Support: https://kaylousberg.com

| Pack | Author / Source | License | Location | Used for |
|------|-----------------|---------|----------|----------|
| KayKit — Adventurers (2.0) | Kay Lousberg · kaylousberg.itch.io | CC0 | `characters/kaykit_adventurers/` | player models (Mage is the default) |
| KayKit — Skeletons (1.1 FREE) | Kay Lousberg · kaylousberg.itch.io | CC0 | `characters/kaykit_skeletons/` | bot models (Skeleton Warrior for now) |
| KayKit — Character Animations (1.1) | Kay Lousberg · kaylousberg.itch.io | CC0 | `animations/rig_medium/` | shared Rig_Medium animation clips |
| KayKit — Dungeon Remastered (1.1 FREE) | Kay Lousberg · kaylousberg.itch.io | CC0 | `environments/kaykit_dungeon/` | map / level objects |

## Notes

- **Format:** glTF only. The FBX / OBJ / Unity variants and sample scenes from the
  original downloads were intentionally **not** copied (we use glTF and want to
  keep the repo / web build lean).
- **Characters** are self-contained `.glb` files with embedded textures.
- **Rig:** the Adventurers and Skeletons characters both use the **Rig_Medium**
  skeleton, so the single `animations/rig_medium/` set drives players and bots
  alike (same bone names → clips apply without retargeting).
- **Attribution string** (optional, if ever surfaced in credits/UI):
  `Kay Lousberg, www.kaylousberg.com`.

Each pack's original `License.txt` is preserved alongside its files.
