# DEV LOG — Mycelium Idle (Godot) — v0 UI Mock
Date: 2026-03-02

## Summary
Started a new Godot 4.6.1 project for **Mycelium Idle** and built the V0 static UI mock foundation:
- Portrait baseline configuration
- Layered scene structure (Map, UI, PanelHost)
- IPM-style transparent bottom sheets with dimmer that **does not block the bottom bar**
- Imported placeholder art and laid out the initial map (Spore Cloud + 4 starter nodes + mycelium lines)
- Added a NodePanel UI (header + table placeholders)

---

## Work Completed (Chronological)

### 1) Project setup
- Created Godot project: `Mycelium Idle` (Godot 4.6.1)
- Set portrait baseline:
  - Viewport: 1080×1920
  - Stretch: canvas_items + expand
- Created folder structure under `res://`:
  - `art/placeholder/`, `scenes/`, `scripts/`, `ui/`

### 2) Scene foundation
- Created and saved `res://scenes/Main.tscn` (Control root, Full Rect)
- Set `Main.tscn` as Main Scene
- Built core layers:
  - `MapLayer` (Node2D)
  - `UILayer` (CanvasLayer)
  - `PanelHost` (CanvasLayer)

### 3) HUD + Bottom menu
- Added TopBar with placeholder nutrients text
- Added BottomBar with 5 placeholder menu buttons:
  - Upgrades / Discoveries / Refinery / Digest / Settings

### 4) IPM-style panels (bottom sheets)
- Created `PanelHost/Dimmer` and a panel container
- Built 5 placeholder panels:
  - UpgradesPanel, DiscoveriesPanel, RefineryPanel, DigestPanel, SettingsPanel
- Implemented slide-up / close behavior in `MainUI.gd`:
  - Smooth tween animation
  - Tap outside closes
  - Esc closes
  - Only one panel open at a time
- Fixed critical input issue:
  - Dimmer and PanelHost can block bottom bar if they cover full screen
  - Implemented dimmer clipping so it stops above the BottomBar
  - Ensured UILayer renders above PanelHost
- Set Main root Mouse Filter to Ignore to prevent full-screen UI from consuming map taps

### 5) Placeholder art + map composition (V0)
- Generated and imported placeholder art pack:
  - background_1080x1920.png
  - spore_cloud_512.png
  - 4 node icons (damp soil, rotting log, compost heap, root cluster)
- Built map layout:
  - Background Sprite2D assigned
  - SporeCloud Sprite2D centered
  - 4 nodes placed using Area2D + Sprite2D + CollisionShape2D
  - Mycelium lines drawn via Line2D from SporeCloud → nodes

### 6) Node panel UI
- Created `NodePanel` bottom sheet:
  - Header row with Name label + Close button
  - GridContainer table (4 columns) + one placeholder data row
  - HelpText label

### 7) Node tapping (resolved)
- Area2D `input_event` did not fire reliably in the current UI layering.
- Implemented **manual node hit-testing** in `_input` using **screen-space distance** to node positions.
- Result: tapping any node reliably opens the NodePanel.

---

## Next Steps
1) Add basic node feedback (tap highlight / selected ring)
3) Convert node into reusable `NodeIcon.tscn` (later when adding more nodes)
4) Add auto-line endpoint updates (later)
5) Add quick resource bar icons in HUD (optional V0 polish)

