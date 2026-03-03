# Mycelium Idle — V0 Static UI Mock Checklist (Godot) — Progress Update (2026-03-02)

**Goal:** Build a *playable-looking* UI prototype in Godot (no economy/simulation yet).  
**Ship spec chosen:** v1 Ship Spec.

Legend:
- [x] Done
- [ ] Todo
- [~] In progress / partially done

---

## 0) Project Setup (Godot)
- [x] Create new Godot project (Godot 4.6.1)
- [x] Set portrait baseline + stretch:
  - Viewport: **1080×1920**
  - Stretch: **canvas_items + expand**
- [~] Configure safe-area / notch handling (placeholder OK) *(later, for Android testing)*
- [x] Folder structure created under `res://`:
  - [x] `scenes/`
  - [x] `ui/`
  - [x] `art/placeholder/`
  - [x] `scripts/`
  - [~] `data/` *(later)*
- [~] Input actions:
  - [x] `ui_cancel` (default Esc/back equivalent)
  - [ ] `ui_back` *(optional later; Android back mapping)*

---

## 1) Scene Skeleton
- [x] Create `Main.tscn` (root **Control**, Full Rect)
- [x] Set `Main.tscn` as Main Scene
- [x] Layers created:
  - [x] `MapLayer` (Node2D)
  - [x] `UILayer` (CanvasLayer)
  - [x] `PanelHost` (CanvasLayer)
- [~] Theme / typography polish *(later; using defaults for V0)*

---

## 2) Main Screen Layout (V0 target)
### 2.1 Top HUD
- [x] Nutrients display placeholder (e.g., “Nutrients: 12,500”)
- [~] Quick resource bar (icons + counts) *(planned; not built yet)*
- [x] Keep HUD clean (minimal text, consistent spacing)

### 2.2 Map (Top-down view)
- [x] Cozy green background (placeholder PNG imported + assigned)
- [x] Spore Cloud centered (placeholder PNG imported + assigned)
- [x] 4 unlocked nodes placed (icon-only):
  - [x] Damp Soil
  - [x] Rotting Log
  - [x] Compost Heap
  - [x] Root Cluster
- [x] Mycelium connection lines (Line2D) from Spore Cloud → nodes
- [~] Node interaction states *(later: tap feedback + selected ring)*

### 2.3 Bottom Menu Bar
- [x] Bottom bar container
- [x] Buttons created (text placeholders for now):
  - [x] Upgrades
  - [x] Discoveries
  - [x] Refinery
  - [x] Digest
  - [x] Settings
- [ ] Icons for menu buttons *(planned)*
- [ ] Active tab highlight *(planned after icons)*

---

## 3) Transparent Slide-up Panels (IPM-style)
**Intent:** tapping a bottom icon opens a semi-transparent bottom sheet. Background stays visible; bottom bar remains clickable.

### Shared panel behavior
- [x] Panel slide-up animation (tween)
- [x] Semi-transparent dim overlay behind panel
- [x] **Dimmer excludes bottom bar** so buttons remain clickable
- [x] Tap outside closes
- [x] Esc closes
- [x] Single-panel-open-at-a-time behavior

### Panels (placeholders)
- [x] Upgrades panel placeholder
- [x] Discoveries panel placeholder
- [x] Refinery panel placeholder
- [x] Digest panel placeholder
- [x] Settings panel placeholder

---

## 4) Node Panel (Tap a node)
- [x] NodePanel created (bottom sheet)
- [x] Header row: Name + Close button
- [x] Table via GridContainer (4 columns) + 1 placeholder row
- [x] HelpText label added
- [x] Node tap opens NodePanel (manual hit-test via screen-space distance; reliable)

---

## 5) V0 Interaction & Polish
- [x] Bottom sheets work reliably (don’t block bottom bar)
- [x] Node tap handling (NodePanel opens reliably)
- [ ] Touch target tuning (final pass)
- [ ] Consistent typography pass (2–3 sizes)
- [ ] Optional click SFX hooks

---

## 6) V0 Acceptance Criteria
- [x] App launches and looks like “the game” (map + HUD + bottom menu)
- [x] Bottom menu buttons open transparent panels
- [x] Dimmer tap closes panels; Esc closes panels
- [x] Tap nodes opens Node Panel
- [~] No overlapping UI in portrait baseline *(desktop window shows extra gray area; OK for now)*

---

## Notes / Decisions Log
- Main root `Control` Mouse Filter set to **Ignore** (prevents full-screen UI from consuming map taps).
- Node tap resolved: NodePanel opens reliably via manual hit-test in `_input` (screen-space distance to node positions).
- Placeholder art imported from generated pack:
  - `background_1080x1920.png`, `spore_cloud_512.png`, plus node icons.

