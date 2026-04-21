# Mycelium Idle — Master Design Document
**Android Idle / Incremental Game — Godot 4.6.1 / GDScript**
*Updated: April 2026 | Solo Developer: Lincoln*

---

## Table of Contents
1. [Game Overview](#1-game-overview)
2. [Resource Systems](#2-resource-systems)
3. [Resource Nodes](#3-resource-nodes)
4. [Refinery System](#4-refinery-system)
5. [Mutagen Lab & Strains](#5-mutagen-lab--strains)
6. [Prestige System](#6-prestige-system)
7. [Mutation Chamber](#7-mutation-chamber)
8. [Discovery Tree](#8-discovery-tree)
9. [UI Systems](#9-ui-systems)
10. [Implementation Status](#10-implementation-status)
11. [Design Principles & Key Learnings](#11-design-principles--key-learnings)

---

## 1. Game Overview

Mycelium Idle is a portrait-orientation Android idle/incremental game built in Godot 4.6.1. The player manages a bioluminescent fungal network, unlocking and connecting resource nodes arranged in concentric rings around a central Spore Cloud.

### Core Loop
- Nodes produce raw resources automatically via the Pulse transport system
- Resources are refined into Compounds (Refinery) and Solutions (Synthesis Station)
- Advanced materials feed the Mutagen Lab, producing Strains
- Strains accumulate and convert to Genetic Strain (GS) at Prestige
- GS is spent in the Mutation Chamber on permanent cross-run upgrades

### Platform & Technical
- **Engine:** Godot 4.6.1 / GDScript
- **Target:** Android (ADB/USB debug testing)
- **Viewport:** 412×915 portrait
- **Project path:** `C:\Linc\Android Game\Mycelium Idle\v0refactor`
- **Git repo:** `v0` (files manually copied from v0refactor before committing)
- **Reference game:** Idle Planet Miner (IPM) — upgrade formulas, cost curves, unlock sequences

---

## 2. Resource Systems

### Currencies

| ID | Name | Kind | Notes |
|----|------|------|-------|
| nutrients | Nutrients | Currency | Main progression currency — earned from resource digestion |
| glowcaps | Glowcaps | Premium | Free-to-earn via Missions; purchasable with real money |
| strain_points | Strain Points (GS) | Prestige | Genetic Strain — earned at Prestige, spent in Mutation Chamber |

### Raw Resources (18 types)

Resources are produced by resource nodes and flow via the Pulse system to the Spore Cloud. Base values scale by roughly 2× per tier.

| # | ID | Name | Base Value | Ring(s) |
|---|----|------|-----------|---------|
| 1 | spores | Spores | 1 | Ring 1 |
| 2 | hyphae | Hyphae | 2 | Ring 1 |
| 3 | cellulose | Cellulose | 4 | Rings 1–2 |
| 4 | ichor | Ichor | 8 | Ring 2 |
| 5 | ferment | Ferment | 17 | Ring 3 |
| 6 | lignin | Lignin | 36 | Rings 3–4 |
| 7 | rift_mold | Rift Mold | 75 | Ring 4 |
| 8 | sporoplasm | Sporoplasm | 160 | Rings 4–5 |
| 9 | gloomspore | Gloomspore | 340 | Ring 5 |
| 10 | mycelium | Mycelium | 730 | Rings 5–6 |
| 11 | biolume | Biolume | 1,600 | Ring 6 |
| 12 | crystal_mold | Crystal Mold | 3,500 | Ring 6 |
| 13 | chitin | Chitin | 7,800 | Rings 6–7 |
| 14 | null_fiber | Null Fiber | 17,500 | Ring 7 |
| 15 | deep_enzyme | Deep Enzyme | 40,000 | Ring 7 |
| 16 | voidspore | Voidspore | 92,000 | Rings 7–8 |
| 17 | void_bloom | Void Bloom | 215,000 | Ring 8 |
| 18 | amber_dust | Amber Dust | 510,000 | Ring 8 |

---

## 3. Resource Nodes

40 nodes across 8 rings, revealed by aura expansion. Nodes produce resources via the Pulse system. Distance from center increases by ~20px per node (80px for node 1, 860px for node 40 in local space).

### Map Architecture
- **Map zoom:** 0.6× (world distances = local `distance_px` × 0.6)
- **Aura formula:** `BASE_R = 50 + log10(nutrients+1)×20 + reach_level×80` (local space)
- **Pulse interval:** 20 seconds
- **Node icons:** `res://assets/icons/nodes/NN_node_id.png` (128×128 PNG, scaled to ~48px display)

### Per-Node Upgrades

| ID | Name | Effect | Base Cost | Cost Multiplier |
|----|------|--------|-----------|----------------|
| yield | Yield | Increases production into node pool | 25 N | 1.3× |
| node_speed | Node Speed Bonus | Increases production speed | 25 N | 1.3× |

---

## 4. Refinery System

### Compounds (18 recipes)

Base resources → compounds (1,000 raw = 1 compound). Unlocked via the Primitive Refinery discovery. All compound costs are nutrient-based.

> See **Excel data file → Compounds sheet** for full recipe list.

### Refinery Slot Costs

| Slot | Unlock Cost (Nutrients) |
|------|------------------------|
| 1 | Free |
| 2 | 50,000 |
| 3 | 250,000 |
| 4 | 2,500,000 |
| 5 | 250,000,000 |
| 6 | 10,000,000,000 |

### Solutions (22 recipes)

Compounds → solutions in the Synthesis Station. Unlocked via the Synthesis discovery.

> See **Excel data file → Solutions sheet** for full recipe list.

### Synthesis Slot Costs

| Slot | Unlock Cost (Nutrients) |
|------|------------------------|
| 1 | Free |
| 2 | 125,000 |
| 3 | 1,250,000 |
| 4 | 125,000,000 |
| 5 | 5,000,000,000 |

---

## 5. Mutagen Lab & Strains

### Design

Strains are the direct end product of the Mutagen Lab — there is no intermediate mutagen item layer. The flow is: **craft Strain → hold Strain → convert to GS at Prestige.**

- Unlocked via the **Mutagen Lab** discovery (requires Synthesis)
- **1–3 crafting slots:**
  - **Slot 1** unlocks when the player buys the **Mutagen Lab** discovery
  - **Slot 2** unlocks when the player buys the **Mutagen Slot II** discovery (child of `strain_t3` — you only need to *unlock* `strain_t3`, not craft it)
  - **Slot 3** unlocks when the player buys the **Mutagen Slot III** discovery (child of `strain_t5` — you only need to *unlock* `strain_t5`, not craft it)
- Slots auto-craft continuously; progress **only advances when ALL inputs are present**
- Cancelling a slot mid-craft costs nothing — resources are consumed only at completion

### Strain Tiers & Recipes

| Tier | Name | Inputs | Craft Time | 1st | 2nd | 3rd | 4th+ | Unlock Discovery |
|------|------|--------|-----------|-----|-----|-----|------|-----------------|
| T1 | Strain Primer | ichor_coagulate×5, ferment_extract×5, lignin_lattice×5 | 11m 15s | +5 GS | +2 | +1 | +1 | Available at lab unlock |
| T2 | Strain Compound | growth_gel×2, gloom_dust×2, strain_primer×1 | 23m 30s | +10 GS | +5 | +2 | +1 | strain_t2 |
| T3 | Strain Serum | crystal_bloom×2, lumen_gel×2, strain_compound×1 | 32m 30s | +20 GS | +10 | +5 | +2 | strain_t3 |
| T4 | Strain Catalyst | null_strand×3, chitin_plate×1, strain_serum×1 | 48m 45s | +35 GS | +17 | +8 | +4 | strain_t4 |
| T5 | Strain Elixir | void_mesh×3, enzyme_crystal×1, strain_catalyst×1 | 63m 0s | +55 GS | +27 | +13 | +6 | strain_t5 |
| T6 | Strain Ascendant | volatile_substrate×4, void_petal×3, strain_elixir×1 | 87m 0s | +80 GS | +40 | +20 | +10 | strain_t6 |

### GS Diminishing Returns

Each tier pays out less GS per craft over time. The first craft of the highest tier always pays the most. Players should focus on higher tiers and accept the diminishing return on lower tiers as a baseline income.

---

## 6. Prestige System

### Overview
- Prestige = hard reset of the current run
- **Currency:** Genetic Strain (GS) — accumulated during run, converted at Prestige
- GS is permanent — not lost on prestige
- **Minimum for Prestige:** 10,000,000 nutrients earned this run

### GS Sources

#### 1. Run Value Table
GS awarded based on total nutrients earned this run.

| Min Run Value | GS Awarded |
|--------------|------------|
| 10,000,000 | +5 GS |
| 100,000,000 | +15 GS |
| 1,000,000,000 | +30 GS |
| 10,000,000,000 | +50 GS |
| 100,000,000,000 | +75 GS |
| 1,000,000,000,000 | +105 GS |
| 10,000,000,000,000 | +142 GS |
| 100,000,000,000,000 | +183 GS |
| 1,000,000,000,000,000 | +229 GS |

#### 2. Strain Crafts
GS from Strains is calculated from the `gs_table` per tier with diminishing returns per craft. Held Strains at Prestige contribute their GS. M13 Mutagen Yield mutation adds +5% per level.

---

## 7. Mutation Chamber

### Overview
Unlocked when **either** condition is met (whichever comes first):
- Run value exceeds **10,000,000 nutrients earned**, OR
- Player crafts their **first Strain Primer**

20 mutations total (M01–M20), unlocked sequentially using GS.

**Unlock cost sequence** (IPM-adapted, exact):
`3, 3, 6, 12, 21, 35, 56, 87, 133, 200, 298, 439, 642, 934, 1351, 1946, 2932, 4402, 6586, 9358 GS`

### Mutation List

| ID | Name | Tier | Effect | Max Lv |
|----|------|------|--------|--------|
| M01 | Mycelial Surge | A | +20% Yield Rate per level | 20 |
| M02 | Root Flow | A | +25% Pulse Speed per level | 20 |
| M03 | Pulse Rhythm | A | +25% Pulse Frequency per level | 20 |
| M04 | Spore Payload | A | +25% Pulse Capacity per level | 20 |
| M05 | Forge Speed | D | +10% Compound Creation Speed per level | 10 |
| M06 | Solution Speed | D | +10% Solution Creation Speed per level | 10 |
| M07 | Volatile Magnitude | C | +5% Volatile Node Value per level | 10 |
| M08 | Network Expansion | B | -4% Node Unlock Cost per level | 10 |
| M09 | Strain Harvest | C | +5% GS from Run Value per level | 10 |
| M10 | Spore Current | D | +20% Aura Expansion Rate per level | 10 |
| M11 | Discovery Subsidy | B | -4% Discovery Cost per level | 10 |
| M12 | Lean Compounds | B | -4% Compound Ingredient Cost per level | 10 |
| M13 | Mutagen Yield | C | +5% GS from crafted Strains per level | 10 |
| M14 | Idle Network | Idle | +30 min idle earnings per level | 10 |
| M15 | Lean Solutions | B | -4% Solution Ingredient Cost per level | 10 |
| M16 | Resource Potency | C | +5% all Resource DV per level | 10 |
| M17 | Evolution Subsidy | B | -4% Node Evolution Cost per level | 10 |
| M18 | Compound Potency | C | +5% Compound + Solution DV per level | 10 |
| M19 | Reserved | — | Coming soon | — |
| M20 | Reserved | — | Coming soon | — |

### Tier Level-Up Costs (GS)
- **Tier A:** 2, 4, 6, 9, 12, 17, 23, 31, 41, 54, 90, 90, 148, 148, 483, 483, 483, 483, 483, 4400
- **Tier B:** 13, 23, 37, 56, 80, 112, 154, 207, 276, 364
- **Tier C:** 4, 6, 9, 12, 17, 23, 31, 54, 54, 54
- **Tier D:** 3, 4, 6, 9, 12, 17, 23, 41, 41, 41

---

## 8. Discovery Tree

### Overview
34 discoveries across 5 families. Visualized as a node graph in the Discoveries panel. Each discovery requires its parent to be unlocked first.

### Family Summary

| Family | Key Discoveries | Purpose |
|--------|----------------|---------|
| Core | mycelial_insight | Root — unlocks all branches |
| Refinery | primitive_refinery, synthesis, refinery_speed_1–3, synth_speed_1–3 | Crafting speed upgrades |
| Aura / Nodes | aura_activation, aura_reach_1–7, aura_density, dense_aura_1–2, fungal_enhancement, catalytic_rooting, expansion_catalysis, node_resonance | Aura expansion and node reveals |
| Volatile | volatile_nodes, volatile_magnitude | Volatile node mechanic |
| Mutagen | mutagen_lab, strain_t2–t6, mutagen_lab_slot2–3 | Strain tiers and Mutagen Lab slots |
| Economy | excess_fertilizer, nutrient_efficiency_1–2, fertile_surge_1–2 | Nutrient production |

### Discovery Effects — Status

#### Implemented & Working
- **aura_activation** — enables aura system and node reveals
- **primitive_refinery** — unlocks Refinery tab and Slot 1
- **synthesis** — unlocks Synthesis Station
- **mutagen_lab** — unlocks Mutagen Lab and Slot 1
- **mutagen_lab_slot2 / slot3** — unlocks Mutagen Lab crafting slots
- **strain_t2 through strain_t6** — gates higher Strain tiers in the recipe picker
- **aura_reach_1 through aura_reach_7** — each expands the aura reach constant, revealing the next ring
- **volatile_nodes** — discovery exists; mechanic not yet coded *(needs implementation)*

#### Discovered But Effects NOT Wired

The following discoveries exist in `discoveries.json` and appear in the tree, but have **no handler in `buy_discovery()`**. Their effects have not been designed in detail — names suggest intent only:

| Discovery | Parent | Likely Intent (name-based, not confirmed) |
|-----------|--------|------------------------------------------|
| aura_density | aura_activation | Possibly increases aura glow density or visual radius bonus |
| dense_aura_1 | aura_density | Further aura density enhancement |
| dense_aura_2 | dense_aura_1 | Further aura density enhancement |
| node_resonance | aura_density | Possibly a node yield or connection bonus tied to aura |
| fungal_enhancement | aura_activation | Possibly a resource production multiplier |
| catalytic_rooting | fungal_enhancement | Possibly compound/solution speed or cost reduction |
| expansion_catalysis | catalytic_rooting | Possibly aura expansion rate or reach bonus |
| volatile_magnitude | volatile_nodes | Already tied to M07 mutation — bonus to Volatile Node value |
| nutrient_efficiency_1 / 2 | excess_fertilizer | Digestion return multiplier (per effect_type field) |
| fertile_surge_1 / 2 | excess_fertilizer | Periodic nutrient surge / bonus production |
| refinery_speed_1 / 2 / 3 | primitive_refinery | Compound craft speed bonus |
| synth_speed_1 / 2 / 3 | synthesis | Solution craft speed bonus |

> **Design note:** These will need a dedicated design session before implementation. Priority should be given to those in the main progression path (refinery_speed, synth_speed, nutrient_efficiency) before more exotic effects (aura_density branch).

#### Missing Data
- `aura_reach_3` through `aura_reach_7` are positioned in the UI and referenced in the display order, but have no data entries in `discoveries.json` yet.

---

## 9. UI Systems

### Panel Architecture
- All panels slide up from the bottom over the map view
- Panel height = 55% of screen height
- All panels use **explicit Control root + ScrollContainer layout** — NOT Godot Container auto-layout
- `_layout_*()` functions called on open AND via `tween_callback` after slide animation completes
- Bottom padding added to all scrollable panels (32px spacer at end of content)

### Navigation Tabs (Bottom Bar)

| Tab | Panel |
|-----|-------|
| Digest | Resource inventory and digestion controls |
| Refinery | Compounds / Solutions / Mutagen Lab tabs |
| Discoveries | Discovery tree purchase panel |
| Mutations | Mutation Chamber (unlocks at 10M nutrients or first Strain Primer) |
| Settings | Theme, debug rate, save/load, new game |

### Refinery Panel
- Three tabs: **Compounds | Solutions | Mutagens**
- Slot cards are compact tappable rows: `Slot X | Recipe name | progress bar | countdown`
- Tapping a slot card opens the recipe picker popup (dimmed CanvasLayer overlay)
- AUTO mode available for all three tabs
- Mutagen tab shows **"Mutagen GS this run"** summary row — tappable for GS breakdown popup showing per-tier diminishing returns

### Map Visuals
- **Aura ring:** 32 concentric circles fading outward + sine pulse animation (20s interval)
- **Fog of war:** annular polygon on CanvasLayer layer=2; fog radius = `_aura_current_radius × map_zoom`
- **Node icons:** 128×128 PNG at `res://assets/icons/nodes/NN_node_id.png`
- **Settings toggles:** Aura Pulse | Aura Glow | Fog of War
- **Themes:** Dark (default) | Accessible Blue

---

## 10. Implementation Status

### ✅ Completed This Week
- Aura visual system — ring, glow, pulse, settings toggles
- Fog of war — annular polygon, clean circular cutout, no seam artifact
- Node icon loading from assets (128×128 PNG, circle fallback)
- Refinery panel scroll + bottom padding on all tabs
- Settings theme change no longer blanks the panel
- Mutation Chamber background restored across all themes
- Mutagen Lab full redesign — Strains as direct end product (no t1–t6 layer)
- Strain recipes loading from `strains.json` via `solution_defs`
- Recipe picker popup — dimmed overlay, multi-input display per strain
- GS Breakdown popup — tappable summary row, diminishing returns display
- Slot live progress bar and countdown updating every tick
- Strain slot stalls correctly when ingredients are missing
- `discoveries.json` — 10 new entries added (mutagen chain, volatile, slots)
- `active_in_pass1` fixed — 18 discoveries were incorrectly set to false
- `buy_discovery` handlers wired for mutagen_lab_slot2, mutagen_lab_slot3
- `_get_pass1_discovery_display_order` updated with all new discoveries

### 🔴 Pre-Launch Required

**Missions system**
Sequential quest chain (target: 500 missions), sliding window of 4 active at a time. Completing one mission unlocks the next in sequence. Rewards Glowcaps — the free-to-earn premium currency loop. This is revenue-critical. Cannot be balanced until the game is playable and tuned. Needs a dedicated design session before any code.

**Balance tuning pass**
GS curve, Strain craft times, Discovery costs, Reach costs. All need real playthrough data. Do not tune before the game is stable and playable end-to-end.

**Volatile Nodes implementation**
The `volatile_nodes` discovery exists and is purchasable. The mechanic itself is not coded. Volatile Magnitude (M07) is already in the mutation list expecting this mechanic to exist.

**aura_reach_3 through aura_reach_7**
Tree positions exist in MainUI, display order entry exists in GameState, but no `discoveries.json` entries. Need data and implementation before the game can be completed in a full run.

**Discovery effects — unimplemented branch**
`refinery_speed_1/2/3`, `synth_speed_1/2/3`, `nutrient_efficiency_1/2`, `fertile_surge_1/2`, `aura_density`, `dense_aura_1/2`, `node_resonance`, `fungal_enhancement`, `catalytic_rooting`, `expansion_catalysis` — all visible in the tree, all purchasable, none have effects. Needs a design pass first.

### ⏸ Deferred

| Feature | Notes |
|---------|-------|
| Node Level icon system | Possibly post-launch. Will be the natural trigger for the MainUI refactor. |
| MainUI refactor | Deferred until Node Level system — see refactor note below |
| Mutagen Lab AUTO mode | Same as compounds/solutions, not yet implemented |
| M19 / M20 mutations | Reserved placeholders. May or may not be implemented. |
| Mutagen Lab slot 2/3 unlock via discovery | Currently wired but Slot 2/3 also auto-unlock on first Strain Serum/Elixir craft — decide which trigger to keep |

---

## 11. Design Principles & Key Learnings

### Development Rules
- **Design before code** — Prestige and Mutagen Lab both required full design spec before implementation
- **Finish core gameplay first** — refactoring deferred until natural trigger points
- **Balance deferred until playthrough data exists** — cannot tune numbers blind
- **New game required after any data JSON change** — save data persists old discovery states and will not pick up new entries

### Technical Patterns
- **Godot Container layout is unreliable** — use explicit `position`/`size` in `_layout_*()` functions
- **`_layout_*()`** must be called both on panel open AND via `tween_callback` after slide animation
- **Avoid `await` in bind functions** — use `ready.connect(..., CONNECT_ONE_SHOT)` to prevent race conditions
- **Coordinate space discipline** — aura formula and node reveals both operate in local space (`distance_px`). World space = local × 0.6 map scale.
- **Fog draws in screen space; aura ring draws in map_layer local space**
- **Android vs. editor divergence** — touch input, layout, and performance issues often only surface on device. Always test via ADB.

### IPM Reference
- Idle Planet Miner (IPM) is the primary design reference for cost curves and unlock sequences
- GS amounts at roughly half-scale vs. IPM; mutation unlock cost sequence adapted exactly
- Refinery slot costs, Synth slot costs, and mutation unlock sequence all adapted from IPM

---

## 12. Refactor Assessment

### Current File Sizes
- **MainUI.gd** — ~7,200 lines
- **GameState.gd** — ~3,900 lines

### Should we refactor now?

**Honest answer: MainUI is getting there, GameState is fine.**

`GameState.gd` at 3,900 lines is large but coherent — it's a single data/logic layer and navigates well with search. No refactor needed there yet.

`MainUI.gd` at 7,200 lines is starting to hurt. It currently mixes:
- Map rendering and aura/fog system
- Navigation and panel management
- Full UI build logic for 6+ panels (Digest, Refinery, Discoveries, Node panel, Mutation Chamber, Settings)
- Live update loops

**The practical impact on weekly usage** is real — sending a 7,200-line file in full is expensive. A natural split would be:

| New File | Approx Lines | Contents |
|----------|-------------|----------|
| MainUI.gd | ~1,500 | Core: map, nav bar, panel host, live tick |
| RefineryPanel.gd | ~2,500 | All three refinery tabs + popups |
| DiscoveriesPanel.gd | ~600 | Discovery tree rendering |
| DigestPanel.gd | ~500 | Digest tab |
| MutationPanel.gd | ~400 | Mutation Chamber |
| NodePanel.gd | ~400 | Node detail panel |
| SettingsPanel.gd | ~400 | Settings |

**Recommendation:** A partial refactor — splitting out `RefineryPanel.gd` first — would give the biggest context window benefit since the Refinery tab is the most actively developed panel right now and will grow further when Mutagen Lab AUTO mode is added. This doesn't require the Node Level trigger. The full MainUI refactor can still wait for that.

**This is not urgent** — if the next few sessions are light on Refinery changes, defer it. If we're heading into a heavy Mutagen Lab or Missions implementation session, do the split first.
