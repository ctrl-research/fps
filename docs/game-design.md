# FPS Game Design Document

## Concept Overview

**Project Codename:** Tactical Extraction FPS

A team-based multiplayer first-person shooter featuring tactical depth through a round-based loadout economy, strategic utility systems, and an innovative "downed state" mechanic that extends firefights beyond the initial elimination.

### Core Pillars

1. **Downed State Mechanics** - Players who take lethal damage enter a downed state rather than immediate death, allowing teammates to revive or finish them off
2. **Utility Grenades** - Four distinct grenade types (Flash, Smoke, EMP, Push) that create tactical opportunities
3. **Mobility Utility** - Special movement abilities that reward positioning and map control
4. **Round-Based Loadout Economy** - Strategic credit system for purchasing weapons and equipment

---

## Proposed Game Mode: Hot Potato Extraction

### Objective

Two teams compete to capture and extract a valuable objective (the "Hot Potato" - a strategic asset/intel package) from a contested zone. The round ends when:

- **Attackers win:** Successfully extract the Hot Potato to the designated extraction point
- **Defenders win:** Eliminate all attackers OR prevent extraction for the duration

### Round Structure

1. **Buy Phase (15 seconds)** - Attackers and defenders purchase loadouts
2. **Combat Phase (4 minutes)** - Teams fight for control of the Hot Potato zone
3. **Extraction Window (30 seconds)** - Once attackers grab the objective, they have 30 seconds to extract

### Hot Potato Mechanics

- The Hot Potato spawns at a randomized location within the objective zone at round start
- Attackers must pick up the objective (1.5 second channel)
- While carrying the objective, movement speed is reduced by 30%
- If the carrier dies, the objective drops and can be re-picked up by either team
- Defenders can "secure" a dropped objective (2 second channel) to prevent enemy pickup

---

## Core Systems Overview

### 1. Downed State Mechanics

When a player's health reaches 0, they enter the **Downed State**:

| Property | Value |
|----------|-------|
| Duration | 10 seconds before bleed-out death |
| Movement | Crawling at 20% speed |
| Vision | Limited to ground-level view |
| Revive Window | Any time before bleed-out |
| Self-Revive | None (teamwork required) |

**Revive Mechanics:**
- Teammates can revive downed players (3 second channel)
- Revived players return with 50% max health
- Revived players cannot use equipment consumed before going down
- Downed players can be finished by any damage source

**Strategic Implications:**
- Shooting a downed enemy prevents revival for 2 seconds (interrupt mechanic)
- Utility grenades affect downed players normally
- Downed players can still communicate via proximity voice

### 2. Grenade Types

| Type | Effect | Duration | Radius |
|------|--------|----------|--------|
| **Flashbang** | Blinds and deafens (no墙角 bounce) | 2 seconds | 5m |
| **Smoke** | Creates vision-blocking cover | 8 seconds | 6m |
| **EMP** | Disables electronics (utility items, scopes) | 4 seconds | 4m |
| **Push** | Applies knockback force | Instant | 3m |

**Utility Inventory:**
- Players can carry up to 2 grenades of any type
- Grenades can be cooked (delayed throw) for all types except EMP
- EMP affects: enemy utility items, electronic scopes, motion sensors

### 3. Equipment & Gear

**Primary Equipment:**
- **Armor** - Reduces incoming damage (2 levels: Light 20%, Heavy 40%)
- **Mobility Tool** - One-time use movement enhancer (grapple, dash, leap)
- **Medical Kit** - Instant heal to 100% (limited inventory)

**Consumables:**
- **Health Pack** - 50% health restoration
- **Ammo Pack** - Resupplies reserve ammunition

### 4. Economy System

**Starting Credits:** 800 per round

**Credit Rewards:**
| Action | Credit Value |
|--------|--------------|
| Elimination | +300 |
| Assist | +150 |
| Downed Enemy Revive Fail | +100 |
| Round Win | +1000 |
| Round Loss | +500 |
| Hot Potato Extraction | +500 |
| Hot Potato Defend | +300 |

**Buy Phase Restrictions:**
- Players can save credits between rounds (carry over up to 3200)
- Equipment resets each round
- Weapons persist until destroyed or sold

### 5. Weapon System

Firing, hit detection, and damage are driven by the per-player `WeaponController`
(`player/weapon_controller.gd`). All stats are read live from the
`WeaponDatabase`, which stays the single source of truth.

**Weapon classes & stats** (from `resources/weapon_database.gd`):

| Class | Examples | Damage | Fire rate (s) | Mag | Reserve | Spread | Recoil |
|-------|----------|--------|---------------|-----|---------|--------|--------|
| Assault Rifle | AR-15, AK-74 | 30–35 | 0.10–0.12 | 30 | 75–90 | 0.03–0.04 | 0.15–0.20 |
| SMG | MP5, Vector | 20–22 | 0.05–0.06 | 30–50 | 120–150 | 0.04–0.05 | 0.08–0.10 |
| Shotgun | M870, AA-12 | 50–80 | 0.30–0.80 | 8–20 | 24–60 | 0.15–0.18 | 0.35–0.40 |
| Sniper | AWP, MSG90 | 85–115 | 0.50–1.20 | 10 | 30–40 | 0.01–0.02 | 0.35–0.60 |
| Pistol | Glock 17, Deagle | 18–35 | 0.15–0.40 | 7–17 | 28–51 | 0.02–0.03 | 0.03–0.12 |

**Equip / switch:** primary and secondary slots are filled from the player's
`PlayerLoadout`. Press **1** (primary) / **2** (secondary) to switch.

**Firing:**
- **Hitscan** (default) — a raycast from the camera centre. Shotguns fire
  multiple pellets (`pellets`, default 8), each its own raycast.
- **Projectile** — a travelling `Area3D` (`player/projectile.tscn`), used when a
  weapon defines `"fire_mode": "projectile"` (with optional `projectile_speed`).

**Hit detection & damage:** a hit on a `PlayerController` routes damage to that
body's owning peer, which applies it and broadcasts the resulting health.
Reaching 0 health emits `died`.

**Accuracy:** the effective spread cone combines the weapon's base spread, a
movement penalty (scaled by horizontal speed), and a spray buildup. Recoil kicks
the aim upward in a decelerating, CS-style climb with slight horizontal sway, and
recovers when the trigger is released.

**Ammo & reload:** each weapon tracks current magazine and reserve ammo. Press
**R** to reload; reload time defaults per class (pistol 1.5s → sniper 3.5s) and
can be overridden per weapon with a `"reload_time"` key.

**Feedback:** every shot plays a muzzle flash (mesh + light) and a procedural
gunshot, mirrored to other clients. A dynamic HUD crosshair widens with the
current spread, alongside a weapon/ammo/reload readout.

**Controls:**

| Action | Bind |
|--------|------|
| Fire | Left Mouse (held for automatic AR/SMG, tap for semi-auto) |
| Reload | R |
| Equip primary / secondary | 1 / 2 |

---

## Round Flow & Buy Phase

### Round Sequence

```
┌─────────────────────────────────────────────────────────────┐
│                      BUY PHASE (15s)                        │
│  • Teams purchase weapons, equipment, grenades               │
│  • Strategy discussion and loadout planning                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   LIVE ROUND PHASE                          │
│  • Combat begins simultaneously                             │
│  • Teams fight for objective control                        │
│  • Economy active for utility purchases                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ROUND END                                │
│  • Win condition met (elimination/extraction)               │
│  • Credits awarded                                          │
│  • Match continues until winning score reached              │
└─────────────────────────────────────────────────────────────┘
```

### Buy Phase Interface

- Weapon loadout display with stats
- Credit counter
- Inventory management (equip/unequip)
- Utility quick-buy shortcuts
- "Ready" indicator to start round early

### Match Format

- **Best of 15 rounds** (first to 8 wins)
- **Team swap** after 7 rounds
- **Timeout:** 60 seconds per round per team

---

## Game Modes

The game targets the casual "play-with-friends" niche: low ramp-up, constant
action, comeback potential, and **quick matches (< 15 min)**. Modes are layered
on top of the existing systems (weapons, grenades, economy, round machine,
downed/respawn, bots) so most are cheap to build.

Match length guidance: a single timed round or a first-to-N target keeps matches
short — set `ROUNDS_TO_WIN = 1` with a kill/score limit rather than a long
best-of-15 for the casual modes.

### Roadmap (by fun-per-effort)

| Mode | Hook | Status | Reuses |
|------|------|--------|--------|
| **Gun Game** | Each kill upgrades you through a weapon ladder; first to finish wins. FFA, no economy, instant respawn. | **In progress** | Weapon system, WeaponDatabase ladder, downed/respawn, bots |
| **Grenade Warfare** | Grenades only, auto-replenished. Push people off ledges. | Planned | Full grenade kit |
| **FFA Deathmatch** | Everyone vs everyone, first to N kills or timer. | Planned | Combat, respawn, round timer/score |
| **Juggernaut** | One buffed player; killer inherits the role. | Planned | Health scaling, downed state |
| **Hot Potato Extraction** | Carry an objective to extract while the enemy defends. Signature objective mode. | Scaffolded (`examples/hot_potato_extraction.gd`) | Round machine, team scoring |
| **Infection / Last Man Standing** | Few fast melee "infected" convert survivors. | Planned | Needs melee + role conversion |

### Mutators (force multiplier)

Cheap toggles that turn any mode into a different night — mostly flipping
existing constants:

- Low gravity / super-slide / double-jump (movement constants)
- One in the Chamber (1 bullet, refunded on kill)
- Big-head / tiny / giant players
- Bouncy or instant-cook grenades
- Headshots-only / snipers-only

A mutator dropdown over 2–3 base modes yields a dozen "modes" for little code.

### Gun Game (first mode)

- FFA: player + bots, no teams, no buy economy.
- Each participant has a **level** = index into a weapon ladder (pistol → SMGs →
  rifles → shotguns → snipers → finisher pistol).
- A kill **advances the killer one level** (swaps to the next weapon). Reaching
  past the final weapon **wins**.
- Instant/quick respawn; level persists through death.
- Testable offline with bots before any networking (no broker needed).

---

## Future Considerations

- Competitive ranking system
- Custom match browser
- Spectator camera
- Replay system
- Map rotation and new map development