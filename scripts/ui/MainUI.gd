extends Control

const PANEL_H_RATIO  := 0.55  # panel takes 68% of screen height
const PANEL_MARGIN   := 8.0
var   PANEL_H: float = 600.0  # set at runtime in _ready

const NODE_HIT_RADIUS := 36.0
const UI_REFRESH_DT := 0.20

const ROOT_PULSE_DOT_SIZE_PX := 10
const ROOT_PULSE_GLOW_SIZE_PX := 24

const ROOT_PULSE_IDLE_COLOR_DEFAULT   := Color(0.50, 0.62, 0.48, 0.80)
const ROOT_PULSE_ACTIVE_COLOR_DEFAULT := Color(0.88, 1.00, 0.70, 1.00)

var ROOT_PULSE_IDLE_COLOR:   Color = ROOT_PULSE_IDLE_COLOR_DEFAULT
var ROOT_PULSE_ACTIVE_COLOR: Color = ROOT_PULSE_ACTIVE_COLOR_DEFAULT
var TRANSFER_TEXT_COLOR:        Color = Color(0.90, 1.00, 0.78, 1.00)
var TRANSFER_TEXT_OUTLINE_COLOR:Color = Color(0.11, 0.17, 0.10, 0.95)
const TRANSFER_FONT_SIZE := 26
const TRANSFER_LIFT_PX := 40.0
const TRANSFER_DURATION := 0.60

# Camera / map pan & zoom
const MAP_ZOOM_MIN       := 0.25
const MAP_ZOOM_MAX       := 1.50
const MAP_ZOOM_START     := 0.60
const MAP_ZOOM_STEP      := 0.10   # scroll-wheel step
const MAP_PAN_THRESHOLD  := 8.0    # px moved before drag is considered a pan

@onready var dimmer: ColorRect = $PanelHost/Dimmer
@onready var bottom_bar: Control = $UILayer/HUD/BottomBar

# Menu panels
@onready var upgrades_panel: Control     = $PanelHost/PanelContainer/UpgradesPanel
@onready var discoveries_panel: Control  = $PanelHost/PanelContainer/DiscoveriesPanel
@onready var refinery_panel: Control     = $PanelHost/PanelContainer/RefineryPanel
@onready var digest_panel: Control       = $PanelHost/PanelContainer/DigestPanel
@onready var settings_panel: Control          = $PanelHost/PanelContainer/SettingsPanel
@onready var mutation_chamber_panel: Control  = $PanelHost/PanelContainer/MutationChamberPanel

# Node panel + header refs
@onready var node_panel: Control = $PanelHost/PanelContainer/NodePanel
@onready var node_title: Label   = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/"Header row"/Name
@onready var node_close: Button  = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/"Header row"/Close

# Bottom buttons
var btn_digest:      BaseButton = null
var btn_refinery:    BaseButton = null
var btn_discoveries: BaseButton = null
var btn_enhancements:BaseButton = null
var btn_prestige:    BaseButton = null
var btn_settings:    BaseButton = null  # top-right, not in nav bar

# Map nodes
var nodes_container: Node = null
var lines_container: Node = null
@onready var spore_cloud: Node2D = $MapLayer/SporeCloud

@onready var selection_ring: Sprite2D = $MapLayer/SelectionRing
@onready var map_layer: Node2D = $MapLayer

# Currency labels
var lbl_nutrients: Label = null
var lbl_glowcaps: Label = null
var lbl_strain: Label = null

var _tween: Tween
var _open_panel: Control = null
var _panel_container: Control = null  # shared parent of all panels
var _bar_h: float = 0.0

var _node_list: Array = []
var _node_lookup: Dictionary = {}
var _line_lookup: Dictionary = {}
var _node_cost_labels: Dictionary = {}  # node_id -> Label

var _selected_node: Node2D = null
var _selected_node_id: String = ""
var _node_pop_tween: Tween = null

var game_state: Node = null
var _ui_accum: float = 0.0

# Camera state
var _map_zoom: float = MAP_ZOOM_START
var _map_is_dragging: bool = false
var _press_started_in_popup: bool = false  # swallow release if press began during popup
var _popup_closed_this_press: bool = false  # popup closed mid-press, swallow the release
# Two-finger pinch tracking (fallback for devices without MagnifyGesture)
var _touch_points: Dictionary = {}  # index -> Vector2
var _pinch_last_dist: float = 0.0
var _map_drag_start_screen: Vector2 = Vector2.ZERO
var _map_drag_start_map_pos: Vector2 = Vector2.ZERO
var _map_drag_has_moved: bool = false

# Discovery grid pan/zoom
const DISC_ZOOM_MIN  := 0.5
const DISC_ZOOM_MAX  := 2.0
const DISC_ZOOM_START := 1.0
const DISC_ZOOM_STEP  := 0.12
var _disc_zoom: float = DISC_ZOOM_START
var _disc_drag_start_screen: Vector2 = Vector2.ZERO
var _disc_drag_start_pos: Vector2 = Vector2.ZERO
var _disc_is_dragging: bool = false
var _disc_drag_has_moved: bool = false

# DigestPanel widgets
var digest_lbl_selected: Label = null
var digest_btn_1: Button = null
var digest_btn_all: Button = null
var digest_tabs_row: HBoxContainer = null
var digest_tab_resources: Button = null
var digest_tab_compounds: Button = null
var digest_tab_solutions: Button = null
var digest_inventory_list: VBoxContainer = null
var digest_feedback: Label = null
var _digest_active_category: String = "resource"
# Digest layout children (sized explicitly in _layout_digest_panel)
var _digest_header: Label = null
var _digest_scroll: ScrollContainer = null
var _digest_bottom_bar: Control = null

# IPM-style digest interaction state
var _digest_selected_id: String = ""
var _digest_selected_value: float = 0.0
var _digest_pct: float = 1.0
var _digest_action_bar: Control = null
var _digest_slider: HSlider = null
var _digest_action_btn: Button = null
var _digest_action_lbl: Label = null
var _digest_row_refs: Dictionary = {}   # item_id -> row Control (for live updates)
var _digest_hold_timer: float = 0.0
var _digest_hold_id: String = ""
var _digest_tap_start_pos: Vector2 = Vector2.ZERO
var _digest_hold_consumed: bool = false  # true when hold triggered auto-toggle, suppress release tap
var _digest_auto_ids: Dictionary = {}   # item_id -> bool
var _digest_auto_last_amt: Dictionary = {}  # item_id -> int, amount at last tick

# Discoveries panel widgets
var discoveries_list: VBoxContainer = null
var discoveries_feedback: Label = null
var _disc_node_refs: Dictionary = {}   # discovery_id -> Control (grid node)
var _disc_popup: Control = null
var _disc_popup_dimmer: ColorRect = null
var _disc_popup_disc_id: String = ""
var _disc_popup_layer: CanvasLayer = null

# Recipe picker popup
var _recipe_popup_layer: CanvasLayer = null
var _recipe_popup: Control = null
var _recipe_popup_dimmer: ColorRect = null

# Refinery panel widgets
var refinery_list: VBoxContainer = null
var refinery_feedback: Label = null
var refinery_tabs_row: HBoxContainer = null
var refinery_tab_compounds: Button = null
var refinery_tab_solutions: Button = null
var _refinery_active_category: String = "compound"

# Settings panel widgets
var settings_list: VBoxContainer = null
var settings_feedback: Label = null
var settings_btn_save: Button = null
var settings_btn_load: Button = null
var settings_btn_new_game: Button = null
var _settings_confirm_action: String = ""
var _last_refinery_inventory_signature: String = ""
var _last_discovery_signature: String = ""

# Mutation Chamber panel widgets
var _mc_gs_lbl: Label = null
var _mc_run_lbl: Label = null
var _mc_preview_lbl: Label = null
var _mc_mutate_btn: Button = null
var _mc_mutation_list: VBoxContainer = null

# Nutrients flash
var _nutrients_base_scale: Vector2 = Vector2.ONE
var _nutrients_flash_tween: Tween = null

# Root pulse visuals
var _root_pulse_layer: Node2D = null
var _root_pulse_visuals: Dictionary = {}
var _root_pulse_dot_texture: Texture2D = null
var _root_pulse_glow_texture: Texture2D = null

# Transfer feedback
var _transfer_fx_layer: Node2D = null
var _transfer_event_seen: Dictionary = {}

# NodePanel top table widgets
var cell_res_icon: TextureRect = null
var cell_res_name: Label = null
var cell_yield: Label = null
var cell_rate: Label = null
var cell_harvested: Label = null

# NodePanel production widgets
var prod_value: Label = null

# NodePanel upgrade widgets
var upgrades_box: Control = null

var row_yield: Control = null
var yield_name: Label = null
var yield_lvl: Label = null
var yield_val: Label = null
var yield_btn: Button = null

var row_frequency: Control = null
var frequency_name: Label = null
var frequency_lvl: Label = null
var frequency_val: Label = null
var frequency_btn: Button = null

var row_travel: Control = null
var travel_name: Label = null
var travel_lvl: Label = null
var travel_val: Label = null
var travel_btn: Button = null

var row_carry: Control = null
var carry_name: Label = null
var carry_lvl: Label = null
var carry_val: Label = null
var carry_btn: Button = null


func _ready() -> void:
	set_process_input(true)
	set_process(true)

	await get_tree().process_frame
	_bar_h  = bottom_bar.size.y
	PANEL_H = get_viewport_rect().size.y * PANEL_H_RATIO

	game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		push_warning("GameState autoload not found at /root/GameState.")

	# Apply theme before building any UI
	_apply_theme()
	if ThemeManager.theme_changed.connect(_on_theme_changed) != OK:
		push_warning("MainUI: could not connect to ThemeManager.theme_changed")

	_bind_currency_labels()

	_setup_map_containers()
	_build_node_registry()
	_setup_initial_camera()
	_refresh_node_world_state()

	_register_root_transfer_positions()
	_setup_root_pulses()
	_setup_transfer_fx()

	selection_ring.visible = false

	# Dimmer excludes bottom bar
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.offset_bottom = -_bar_h
	dimmer.visible = false
	dimmer.modulate.a = 0.0
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not dimmer.gui_input.is_connected(_on_dimmer_gui_input):
		dimmer.gui_input.connect(_on_dimmer_gui_input)

	# Store the shared panel container.
	# top_level = true detaches it from the parent layout so size/position
	# are relative to the viewport root, not the parent Control.
	_panel_container = digest_panel.get_parent() as Control
	if _panel_container != null:
		var vp := get_viewport_rect().size
		_panel_container.top_level    = true
		_panel_container.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		_panel_container.size         = Vector2(vp.x, PANEL_H)
		_panel_container.position     = Vector2(0.0, vp.y)
		await get_tree().process_frame

	# Each panel must exactly fill the container — set position and size explicitly
	for p in _all_panels():
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.position = Vector2.ZERO
		p.size     = Vector2(_panel_container.size.x, _panel_container.size.y)

	# Size the digest anchor root to match its panel
	var digest_root := digest_panel.find_child("DigestAnchorRoot", true, false) as Control
	if digest_root != null:
		digest_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		digest_root.offset_left   = 0
		digest_root.offset_right  = 0
		digest_root.offset_top    = 0
		digest_root.offset_bottom = 0
		digest_root.size = Vector2(_panel_container.size.x, _panel_container.size.y)

	_layout_digest_panel()

	# Panels start hidden/closed
	for p in _all_panels():
		p.visible = false
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_panel_closed(p)

	# Wire bottom buttons
	_build_nav_bar()
	_build_settings_button()

	node_close.pressed.connect(_close_current)

	_bind_digest_panel()
	_bind_discoveries_panel()
	_bind_refinery_panel()
	_bind_settings_panel()
	_bind_nodepanel_top_table()
	_bind_nodepanel_production()
	_bind_nodepanel_upgrades()
	_bind_mutation_chamber_panel()

	if lbl_nutrients != null:
		_nutrients_base_scale = lbl_nutrients.scale

	_refresh_panel_access_ui()
	_refresh_currency_ui()
	get_tree().root.print_tree_pretty()


# ── Theme ─────────────────────────────────────────────────────────────────────

func _on_theme_changed(_theme_id: String) -> void:
	_apply_theme()
	_refresh_all_panels()


func _apply_theme() -> void:
	var tm := ThemeManager

	# ── Runtime color vars (used by pulse and transfer fx) ────────────────
	ROOT_PULSE_IDLE_COLOR   = Color(tm.c("accent_dim").r, tm.c("accent_dim").g, tm.c("accent_dim").b, 0.80)
	ROOT_PULSE_ACTIVE_COLOR = Color(tm.c("accent").r,     tm.c("accent").g,     tm.c("accent").b,     1.00)
	TRANSFER_TEXT_COLOR         = tm.c("text_primary")
	TRANSFER_TEXT_OUTLINE_COLOR = tm.c("bg_deep")

	# ── Panel container background ────────────────────────────────────────
	var panel_container: Control = get_node_or_null("PanelHost/PanelContainer")
	if panel_container != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color    = tm.c("bg_deep")
		sb.border_color = tm.c("border")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(14)
		panel_container.add_theme_stylebox_override("panel", sb)

	# ── Bottom bar ────────────────────────────────────────────────────────
	var bar: Control = get_node_or_null("UILayer/HUD/BottomBar")
	if bar != null:
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = tm.c("nav_bg")
		sb2.border_color = tm.c("border")
		sb2.border_width_top = 1
		bar.add_theme_stylebox_override("panel", sb2)

	# ── Currency labels ───────────────────────────────────────────────────
	for lbl_node in [lbl_nutrients, lbl_glowcaps, lbl_strain]:
		if lbl_node != null:
			(lbl_node as Label).add_theme_color_override("font_color", tm.c("text_primary"))

	# ── Node cost labels ─────────────────────────────────────────────────
	for node_id_variant in _node_cost_labels.keys():
		var cost_lbl: Label = _node_cost_labels[node_id_variant] as Label
		if is_instance_valid(cost_lbl):
			cost_lbl.add_theme_color_override("font_color", tm.c("accent"))
			cost_lbl.add_theme_color_override("font_outline_color", tm.c("bg_deep"))

	# ── Nav bar (redraw icons + restyle bar) ─────────────────────────────
	_apply_nav_theme()

	# ── Panel interiors ───────────────────────────────────────────────────
	_theme_panels()

	# ── NodePanel ─────────────────────────────────────────────────────────
	if node_panel != null:
		_theme_nodepanel()

	# ── Upgrade rows ──────────────────────────────────────────────────────
	_theme_upgrade_rows()


func _theme_panels() -> void:
	_theme_panel_shell(digest_panel)
	_theme_panel_shell(discoveries_panel)
	_theme_panel_shell(refinery_panel)
	_theme_panel_shell(settings_panel)
	_theme_panel_shell(node_panel)
	_theme_digest_panel()
	_theme_settings_panel()


# ── Shared: style a panel's PanelContainer / outer shell ─────────────────────
func _theme_panel_shell(panel: Control) -> void:
	if panel == null:
		return
	var tm := ThemeManager

	# Outer PanelContainer
	var sb_outer := StyleBoxFlat.new()
	sb_outer.bg_color      = tm.c("bg_deep")
	sb_outer.border_color  = tm.c("border")
	sb_outer.set_border_width_all(1)
	sb_outer.corner_radius_top_left  = 14
	sb_outer.corner_radius_top_right = 14
	panel.add_theme_stylebox_override("panel", sb_outer)

	# Bark stripe — draw as a thin colored rect at the top edge
	# We simulate this by adding a top border in a contrasting color
	var sb_bark := StyleBoxFlat.new()
	sb_bark.bg_color     = tm.c("bg_deep")
	sb_bark.border_color = tm.c("bark_stripe")
	sb_bark.border_width_top  = 3
	sb_bark.border_width_bottom = 0
	sb_bark.border_width_left   = 0
	sb_bark.border_width_right  = 0
	sb_bark.corner_radius_top_left  = 14
	sb_bark.corner_radius_top_right = 14

	# Style all Labels inside the panel
	for lbl in _find_all_type(panel, "Label"):
		var l := lbl as Label
		if l.get_meta("theme_exempt", false):
			continue
		l.add_theme_color_override("font_color", tm.c("text_secondary"))

	# Style buttons (non-tab, non-nav)
	for btn_node in _find_all_type(panel, "Button"):
		var b := btn_node as Button
		if b.get_meta("theme_exempt", false):
			continue
		_theme_action_button(b)


func _theme_action_button(btn: Button) -> void:
	var tm := ThemeManager
	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("btn_bg")
	sb.border_color = tm.c("btn_border")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hov := sb.duplicate() as StyleBoxFlat
	sb_hov.bg_color = tm.c("accent_glow")
	btn.add_theme_stylebox_override("hover", sb_hov)
	btn.add_theme_stylebox_override("pressed", sb_hov)
	btn.add_theme_color_override("font_color",          tm.c("accent"))
	btn.add_theme_color_override("font_disabled_color", tm.c("text_muted"))


func _theme_tab_button(btn: Button, active: bool) -> void:
	var tm := ThemeManager
	var sb := StyleBoxFlat.new()
	if active:
		sb.bg_color     = tm.c("tab_active_bg")
		sb.border_color = tm.c("accent_border")
		sb.border_width_bottom = 2
	else:
		sb.bg_color     = Color(0, 0, 0, 0)
		sb.border_color = tm.c("border")
		sb.set_border_width_all(0)
	sb.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", tm.c("accent") if active else tm.c("text_muted"))
	btn.add_theme_color_override("font_disabled_color", tm.c("text_muted"))


func _theme_digest_panel() -> void:
	if digest_tab_resources == null:
		return
	var active := _digest_active_category
	_theme_tab_button(digest_tab_resources, active == "resource")
	_theme_tab_button(digest_tab_compounds, active == "compound")
	_theme_tab_button(digest_tab_solutions, active == "solution")
	if digest_feedback != null:
		digest_feedback.add_theme_color_override("font_color", ThemeManager.c("text_muted"))


func _theme_settings_panel() -> void:
	var tm := ThemeManager
	# Settings buttons are already styled by _theme_panel_shell → _theme_action_button
	# Just make the feedback label use muted color
	if settings_feedback != null:
		settings_feedback.add_theme_color_override("font_color", tm.c("text_muted"))


# ── Utility: recursively find all nodes of a given class name ─────────────────
func _find_all_type(root: Node, class_name_str: String) -> Array:
	var result: Array = []
	for child in root.get_children():
		if child.get_class() == class_name_str:
			result.append(child)
		result.append_array(_find_all_type(child, class_name_str))
	return result


func _theme_nodepanel() -> void:
	var tm := ThemeManager
	if node_title != null:
		node_title.add_theme_color_override("font_color", tm.c("accent"))
	# Reduce close button size
	if node_close != null:
		node_close.custom_minimum_size = Vector2(24, 24)
		node_close.flat = true
		node_close.add_theme_font_size_override("font_size", 12)
	# Header row background
	var header_row: Control = node_panel.find_child("Header row", true, false) as Control
	if header_row != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tm.c("bg_panel")
		header_row.add_theme_stylebox_override("panel", sb)


func _theme_upgrade_rows() -> void:
	var tm := ThemeManager
	for row_ref in [row_yield, row_frequency, row_travel, row_carry]:
		if row_ref == null:
			continue
		var row := row_ref as Control
		# Card background on the row itself if it's a PanelContainer
		if row is PanelContainer:
			var sb_row := StyleBoxFlat.new()
			sb_row.bg_color     = tm.c("bg_panel")
			sb_row.border_color = tm.c("border")
			sb_row.set_border_width_all(1)
			sb_row.set_corner_radius_all(8)
			sb_row.content_margin_left   = 10
			sb_row.content_margin_right  = 8
			sb_row.content_margin_top    = 8
			sb_row.content_margin_bottom = 8
			row.add_theme_stylebox_override("panel", sb_row)
		# Label colors
		for child in row.get_children():
			if child is Label:
				(child as Label).add_theme_color_override("font_color", tm.c("text_secondary"))
		# Button — base style; affordability updated per-tick in _refresh_nodepanel_upgrades
		var btn: Button = row.find_child("BtnUpgrade", true, false) as Button
		if btn != null:
			var sb := StyleBoxFlat.new()
			sb.bg_color     = tm.c("btn_bg")
			sb.border_color = tm.c("btn_border")
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(8)
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_color_override("font_color", tm.c("accent"))


func _refresh_all_panels() -> void:
	if _open_panel == digest_panel:           _refresh_digest_panel()
	if _open_panel == discoveries_panel:      _refresh_discoveries_panel()
	if _open_panel == refinery_panel:         _refresh_refinery_panel()
	if _open_panel == settings_panel:         _refresh_settings_panel()
	if _open_panel == node_panel:             _refresh_nodepanel_all()
	if _open_panel == mutation_chamber_panel: _refresh_mutation_chamber_panel()


# ── Nav bar ───────────────────────────────────────────────────────────────────

# SVG icon paths for each button (24×24 viewBox, stroke-based)
const _NAV_ICONS := {
	"digest": "M6 3h12M9 3l-2 6H5l2 6h10l2-6h-4L13 3 M12 17 a2 2 0 1 0 0.001 0",
	"refinery": "M8 8h8v8H8z M12 3v5 M12 16v5 M3 12h5 M16 12h5 M6 6l2 2 M16 16l2 2 M6 18l2-2 M16 8l2-2",
	"discoveries": "M12 4 a2 2 0 1 0 0.001 0 M6 12 a1.5 1.5 0 1 0 0.001 0 M18 12 a1.5 1.5 0 1 0 0.001 0 M4 19 a1.5 1.5 0 1 0 0.001 0 M20 19 a1.5 1.5 0 1 0 0.001 0 M10 19 a1.5 1.5 0 1 0 0.001 0 M12 6v4l-6 2 M12 10l6 2 M6 13.5L4 17.5 M6 13.5l4 4 M18 13.5l2 4",
	"enhancements": "M12 2l3 5h4l-2.5 4 1.5 6L12 14l-6 3 1.5-6L5 7h4z M19 3l1 1 M20 7l1-1 M22 5h-1",
	"prestige": "M12 3 a9 9 0 1 0 0.001 0 M8 14l4-5 4 5 M8 18l4-5 4 5",
}

const _NAV_BUTTONS := ["digest", "refinery", "discoveries", "enhancements", "prestige"]


func _build_nav_bar() -> void:
	# Find or use the existing BottomBar container
	var bar: Control = bottom_bar
	if bar == null:
		push_warning("NavBar: BottomBar not found")
		return

	# Clear any old children from scene
	for child in bar.get_children():
		child.free()

	# HBoxContainer fills the bar
	var hbox := HBoxContainer.new()
	hbox.name = "NavHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 0)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(hbox)

	var panels := [digest_panel, refinery_panel, discoveries_panel, null, mutation_chamber_panel]

	for i in range(_NAV_BUTTONS.size()):
		var key: String = _NAV_BUTTONS[i]
		var panel: Control = panels[i]

		var btn := Button.new()
		btn.name = "NavBtn_" + key
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 56)
		btn.focus_mode = Control.FOCUS_NONE

		# Draw icon via canvas_item draw
		var icon_path: String = _NAV_ICONS.get(key, "")
		btn.set_meta("nav_icon", icon_path)
		btn.set_meta("nav_key", key)
		btn.draw.connect(_draw_nav_icon.bind(btn))
		btn.queue_redraw()

		_style_nav_button(btn, false)

		if panel != null:
			btn.pressed.connect(func(): _on_nav_pressed(btn, panel))
		else:
			btn.disabled = true
			btn.modulate.a = 0.3

		hbox.add_child(btn)

		# Store reference
		match key:
			"digest":       btn_digest       = btn
			"refinery":     btn_refinery     = btn
			"discoveries":  btn_discoveries  = btn
			"enhancements": btn_enhancements = btn
			"prestige":     btn_prestige     = btn

	_apply_nav_theme()


func _build_settings_button() -> void:
	var hud: Control = get_node_or_null("UILayer/HUD")
	if hud == null:
		return

	# Remove old settings button if it somehow exists
	var old := hud.get_node_or_null("SettingsBtn")
	if old != null:
		old.free()

	var btn := Button.new()
	btn.name = "SettingsBtn"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(40, 40)

	# Anchor to top-right
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left   = -52
	btn.offset_top    = 12
	btn.offset_right  = -12
	btn.offset_bottom = 52

	btn.draw.connect(func():
		btn.set_meta("nav_key", "settings")
		_draw_icon_by_key(btn, "settings",
			btn.size.x * 0.5, btn.size.y * 0.5,
			18.0 / 24.0, ThemeManager.c("accent_dim"))
	)
	btn.queue_redraw()
	btn.pressed.connect(func(): _toggle_panel(settings_panel))
	btn_settings = btn
	hud.add_child(btn)


func _draw_nav_icon(btn: Button) -> void:
	var key: String = str(btn.get_meta("nav_key", ""))
	if key.is_empty():
		return
	var is_active := (_open_panel != null and (
		(key == "digest"       and _open_panel == digest_panel) or
		(key == "refinery"     and _open_panel == refinery_panel) or
		(key == "discoveries"  and _open_panel == discoveries_panel) or
		(key == "prestige"     and _open_panel == mutation_chamber_panel)
	))
	var col: Color = ThemeManager.c("accent") if is_active else ThemeManager.c("accent_dim")
	var cx: float  = btn.size.x * 0.5
	var cy: float  = btn.size.y * 0.48  # slightly above center to leave room for dot
	_draw_icon_by_key(btn, key, cx, cy, 22.0 / 24.0, col)

	# Active dot below icon
	if is_active:
		btn.draw_circle(Vector2(btn.size.x * 0.5, btn.size.y - 7.0), 2.5, ThemeManager.c("accent"))


func _draw_single_icon(ctrl: Control, _path: String, col: Color, icon_size: float) -> void:
	var key: String = str(ctrl.get_meta("nav_key", "settings"))
	var cx: float = ctrl.size.x * 0.5
	var cy: float = ctrl.size.y * 0.5
	_draw_icon_by_key(ctrl, key, cx, cy, icon_size / 24.0, col)


func _draw_icon_by_key(ctrl: Control, key: String, cx: float, cy: float, s: float, col: Color) -> void:
	var w := 1.5

	match key:
		"digest":
			# Funnel top bar
			ctrl.draw_line(Vector2(cx - 6*s, cy - 5*s), Vector2(cx + 6*s, cy - 5*s), col, w, true)
			# Left funnel side
			ctrl.draw_line(Vector2(cx - 6*s, cy - 5*s), Vector2(cx - 2.5*s, cy + 1*s), col, w, true)
			# Right funnel side
			ctrl.draw_line(Vector2(cx + 6*s, cy - 5*s), Vector2(cx + 2.5*s, cy + 1*s), col, w, true)
			# Bottom stem lines
			ctrl.draw_line(Vector2(cx - 2.5*s, cy + 1*s), Vector2(cx - 2.5*s, cy + 4*s), col, w, true)
			ctrl.draw_line(Vector2(cx + 2.5*s, cy + 1*s), Vector2(cx + 2.5*s, cy + 4*s), col, w, true)
			# Drop dot
			ctrl.draw_circle(Vector2(cx, cy + 6*s), 1.8*s, col)

		"refinery":
			# Center square
			ctrl.draw_rect(Rect2(cx - 3*s, cy - 3*s, 6*s, 6*s), col, false, w)
			# Cardinal spokes
			ctrl.draw_line(Vector2(cx,        cy - 8*s), Vector2(cx,        cy - 3*s), col, w, true)
			ctrl.draw_line(Vector2(cx,        cy + 3*s), Vector2(cx,        cy + 8*s), col, w, true)
			ctrl.draw_line(Vector2(cx - 8*s,  cy),       Vector2(cx - 3*s,  cy),       col, w, true)
			ctrl.draw_line(Vector2(cx + 3*s,  cy),       Vector2(cx + 8*s,  cy),       col, w, true)
			# Diagonal ticks
			ctrl.draw_line(Vector2(cx - 7*s,  cy - 7*s), Vector2(cx - 5*s,  cy - 5*s), col, w, true)
			ctrl.draw_line(Vector2(cx + 5*s,  cy + 5*s), Vector2(cx + 7*s,  cy + 7*s), col, w, true)
			ctrl.draw_line(Vector2(cx - 7*s,  cy + 7*s), Vector2(cx - 5*s,  cy + 5*s), col, w, true)
			ctrl.draw_line(Vector2(cx + 5*s,  cy - 5*s), Vector2(cx + 7*s,  cy - 7*s), col, w, true)

		"discoveries":
			# Root node (top center)
			ctrl.draw_circle(Vector2(cx,        cy - 7*s), 2*s, col)
			# Mid nodes
			ctrl.draw_circle(Vector2(cx - 5*s,  cy),       1.5*s, col)
			ctrl.draw_circle(Vector2(cx + 5*s,  cy),       1.5*s, col)
			# Leaf nodes
			ctrl.draw_circle(Vector2(cx - 7*s,  cy + 6*s), 1.5*s, col)
			ctrl.draw_circle(Vector2(cx + 7*s,  cy + 6*s), 1.5*s, col)
			ctrl.draw_circle(Vector2(cx,         cy + 7*s), 1.5*s, col)
			# Branches
			ctrl.draw_line(Vector2(cx,        cy - 5*s), Vector2(cx - 4*s,  cy - 1.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx,        cy - 5*s), Vector2(cx + 4*s,  cy - 1.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx - 5*s,  cy + 1.5*s), Vector2(cx - 6*s,  cy + 4.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx - 5*s,  cy + 1.5*s), Vector2(cx - 0.5*s, cy + 5.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx + 5*s,  cy + 1.5*s), Vector2(cx + 6*s,  cy + 4.5*s), col, w, true)

		"enhancements":
			# Gem shape
			var pts: PackedVector2Array = PackedVector2Array([
				Vector2(cx,        cy - 8*s),
				Vector2(cx + 4*s,  cy - 3*s),
				Vector2(cx + 6*s,  cy + 2*s),
				Vector2(cx,        cy + 8*s),
				Vector2(cx - 6*s,  cy + 2*s),
				Vector2(cx - 4*s,  cy - 3*s),
				Vector2(cx,        cy - 8*s),
			])
			ctrl.draw_polyline(pts, col, w, true)
			# Sparkle lines
			ctrl.draw_line(Vector2(cx + 6*s,  cy - 7*s), Vector2(cx + 7.5*s, cy - 5.5*s), col, 1.2, true)
			ctrl.draw_line(Vector2(cx + 7.5*s,cy - 7.5*s),Vector2(cx + 9*s, cy - 7.5*s), col, 1.2, true)
			ctrl.draw_line(Vector2(cx + 9*s,  cy - 5.5*s),Vector2(cx + 7.5*s,cy - 4.5*s),col, 1.2, true)

		"prestige":
			# Outer circle
			ctrl.draw_arc(Vector2(cx, cy), 8*s, 0, TAU, 48, col, w, true)
			# Double chevron up
			ctrl.draw_line(Vector2(cx - 3.5*s, cy + 3.5*s), Vector2(cx,        cy - 1.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx,          cy - 1.5*s), Vector2(cx + 3.5*s, cy + 3.5*s), col, w, true)
			ctrl.draw_line(Vector2(cx - 3.5*s, cy + 7*s),   Vector2(cx,        cy + 2*s),   col, w, true)
			ctrl.draw_line(Vector2(cx,          cy + 2*s),   Vector2(cx + 3.5*s, cy + 7*s),  col, w, true)

		"settings", _:
			# Gear — outer ring
			ctrl.draw_arc(Vector2(cx, cy), 8*s, 0, TAU, 48, col, w, true)
			# Inner circle
			ctrl.draw_arc(Vector2(cx, cy), 3*s, 0, TAU, 24, col, w, true)
			# 8 gear teeth
			for i in range(8):
				var angle := float(i) * TAU / 8.0
				var inner := Vector2(cos(angle), sin(angle)) * 8*s
				var outer_v := Vector2(cos(angle), sin(angle)) * 10.5*s
				ctrl.draw_line(Vector2(cx, cy) + inner, Vector2(cx, cy) + outer_v, col, w, true)


func _style_nav_button(btn: Button, _active: bool) -> void:
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0, 0, 0, 0)
	sb_normal.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover",  sb_normal)
	btn.add_theme_stylebox_override("pressed", sb_normal)
	btn.add_theme_stylebox_override("focus",  sb_normal)


func _on_nav_pressed(_btn: Button, panel: Control) -> void:
	_toggle_panel(panel)
	# Redraw all nav buttons to update active state
	_redraw_nav_buttons()


func _redraw_nav_buttons() -> void:
	var hbox: HBoxContainer = bottom_bar.get_node_or_null("NavHBox") as HBoxContainer
	if hbox == null:
		return
	for child in hbox.get_children():
		if child is Button:
			child.queue_redraw()


func _apply_nav_theme() -> void:
	# Style the bottom bar itself
	var bar: Control = bottom_bar
	if bar != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color      = ThemeManager.c("nav_bg")
		sb.border_color  = ThemeManager.c("border")
		sb.border_width_top = 1
		bar.add_theme_stylebox_override("panel", sb)
	_redraw_nav_buttons()


func _process(dt: float) -> void:
	if selection_ring.visible and _selected_node != null:
		selection_ring.global_position = _selected_node.global_position

	_update_root_pulse_visuals()
	_poll_root_transfer_feedback()

	# Hold-to-auto-digest timer
	if _digest_hold_id != "":
		_digest_hold_timer += dt
		if _digest_hold_timer >= 0.6:
			_toggle_digest_auto(_digest_hold_id)
			_select_digest_row(_digest_hold_id)
			_digest_hold_consumed = true
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0

	_ui_accum += dt
	if _ui_accum >= UI_REFRESH_DT:
		_ui_accum = 0.0
		_refresh_panel_access_ui()
		_refresh_currency_ui()
		_refresh_node_world_state()

		# Execute auto-digest for all enabled items
		_execute_auto_digest()

		if _open_panel == node_panel and _selected_node_id != "":
			_refresh_nodepanel_all()

		if _open_panel == digest_panel:
			_update_digest_live_values()
			if _digest_selected_id != "":
				_update_digest_action_bar()

	var new_signature := _get_refinery_inventory_signature()
	if new_signature != _last_refinery_inventory_signature:
		_last_refinery_inventory_signature = new_signature

		if _open_panel == digest_panel:
			_refresh_digest_panel()  # inventory changed, full rebuild needed

		if _open_panel == refinery_panel:
			_refresh_refinery_panel()

	var new_discovery_signature := _get_discovery_signature()
	if new_discovery_signature != _last_discovery_signature:
		_last_discovery_signature = new_discovery_signature

		_refresh_panel_access_ui()

		if _open_panel == discoveries_panel:
			_refresh_discoveries_panel()

		if _open_panel == refinery_panel:
			_refresh_refinery_panel()


func _register_root_transfer_positions() -> void:
	if game_state == null:
		return

	if game_state.has_method("register_spore_cloud_world_position"):
		game_state.call("register_spore_cloud_world_position", spore_cloud.global_position)

	if not game_state.has_method("register_node_world_position"):
		return

	for e in _node_list:
		var node_id: String  = str(e.get("id", ""))
		var node_raw = e.get("node")
		if node_id == "" or node_raw == null or not is_instance_valid(node_raw):
			continue
		var node_ref: Node2D = node_raw as Node2D
		# Use global_position so map_layer scale/offset is correctly accounted for
		game_state.call("register_node_world_position", node_id, node_ref.global_position)


func _make_circle_texture(size_px: int, soft_edge: bool) -> Texture2D:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center := Vector2((size_px - 1) * 0.5, (size_px - 1) * 0.5)
	var radius := float(size_px) * 0.5 - 1.0

	for y in range(size_px):
		for x in range(size_px):
			var p := Vector2(float(x), float(y))
			var dist := p.distance_to(center)

			if dist <= radius:
				var a := 1.0
				if soft_edge:
					a = clamp(1.0 - (dist / radius), 0.0, 1.0)
					a *= 0.90

				img.set_pixel(x, y, Color(1, 1, 1, a))

	return ImageTexture.create_from_image(img)


func _setup_root_pulses() -> void:
	if has_node("MapLayer/RootPulseLayer"):
		_root_pulse_layer = $MapLayer/RootPulseLayer
	elif has_node("MapLayer/MitesLayer"):
		_root_pulse_layer = $MapLayer/MitesLayer
		_root_pulse_layer.name = "RootPulseLayer"
	else:
		_root_pulse_layer = Node2D.new()
		_root_pulse_layer.name = "RootPulseLayer"
		$MapLayer.add_child(_root_pulse_layer)

	_root_pulse_dot_texture = _make_circle_texture(ROOT_PULSE_DOT_SIZE_PX, false)
	_root_pulse_glow_texture = _make_circle_texture(ROOT_PULSE_GLOW_SIZE_PX, true)

	for child in _root_pulse_layer.get_children():
		child.free()

	_root_pulse_visuals.clear()

	for e in _node_list:
		var node_id: String = str(e["id"])

		var root := Node2D.new()
		root.name = "RootPulse_" + node_id

		var glow := Sprite2D.new()
		glow.texture = _root_pulse_glow_texture
		glow.centered = true
		glow.modulate = Color(
			ROOT_PULSE_IDLE_COLOR.r,
			ROOT_PULSE_IDLE_COLOR.g,
			ROOT_PULSE_IDLE_COLOR.b,
			0.20
		)

		var dot := Sprite2D.new()
		dot.texture = _root_pulse_dot_texture
		dot.centered = true
		dot.modulate = ROOT_PULSE_IDLE_COLOR

		root.add_child(glow)
		root.add_child(dot)
		_root_pulse_layer.add_child(root)

		_root_pulse_visuals[node_id] = {
			"root": root,
			"glow": glow,
			"dot": dot
		}


func _update_root_pulse_visuals() -> void:
	if _root_pulse_layer == null:
		return
	if game_state == null:
		return
	if not game_state.has_method("get_node_root_pulse_visual"):
		return

	for e in _node_list:
		var node_id: String = str(e["id"])
		var node_raw = e.get("node")
		if node_raw == null or not is_instance_valid(node_raw):
			continue
		var node_ref: Node2D = node_raw as Node2D

		if not _root_pulse_visuals.has(node_id):
			continue

		var pulse: Dictionary = _root_pulse_visuals[node_id] as Dictionary
		var root_raw = pulse.get("root")
		if root_raw == null or not is_instance_valid(root_raw):
			continue
		var root: Node2D = root_raw as Node2D
		var glow_raw = pulse.get("glow")
		if glow_raw == null or not is_instance_valid(glow_raw):
			continue
		var glow: Sprite2D = glow_raw as Sprite2D
		var dot_raw = pulse.get("dot")
		if dot_raw == null or not is_instance_valid(dot_raw):
			continue
		var dot: Sprite2D = dot_raw as Sprite2D

		var info = game_state.call("get_node_root_pulse_visual", node_id)
		if typeof(info) != TYPE_DICTIONARY:
			root.visible = false
			continue

		var route_t: float = clamp(float(info.get("route_t", 0.0)), 0.0, 1.0)
		var active: bool = bool(info.get("active", false))
		var pulse_visible: bool = bool(info.get("visible", true))

		root.visible = pulse_visible
		if not pulse_visible:
			continue

		root.global_position = node_ref.global_position.lerp(spore_cloud.global_position, route_t)

		if active:
			dot.modulate = ROOT_PULSE_ACTIVE_COLOR
			glow.modulate = Color(
				ROOT_PULSE_ACTIVE_COLOR.r,
				ROOT_PULSE_ACTIVE_COLOR.g,
				ROOT_PULSE_ACTIVE_COLOR.b,
				0.36
			)
			root.scale = Vector2.ONE * 1.06
		else:
			dot.modulate = ROOT_PULSE_IDLE_COLOR
			glow.modulate = Color(
				ROOT_PULSE_IDLE_COLOR.r,
				ROOT_PULSE_IDLE_COLOR.g,
				ROOT_PULSE_IDLE_COLOR.b,
				0.18
			)
			root.scale = Vector2.ONE


func _setup_transfer_fx() -> void:
	if has_node("MapLayer/TransferFXLayer"):
		_transfer_fx_layer = $MapLayer/TransferFXLayer
	elif has_node("MapLayer/TransportFXLayer"):
		_transfer_fx_layer = $MapLayer/TransportFXLayer
		_transfer_fx_layer.name = "TransferFXLayer"
	else:
		_transfer_fx_layer = Node2D.new()
		_transfer_fx_layer.name = "TransferFXLayer"
		$MapLayer.add_child(_transfer_fx_layer)

	_transfer_event_seen.clear()

	for e in _node_list:
		var node_id: String = str(e["id"])
		var seen: Dictionary = {
			"transfer_event_id": 0
		}

		if game_state != null and game_state.has_method("get_node_root_transfer_feedback"):
			var info = game_state.call("get_node_root_transfer_feedback", node_id)
			if typeof(info) == TYPE_DICTIONARY:
				seen["transfer_event_id"] = int(info.get("transfer_event_id", 0))

		_transfer_event_seen[node_id] = seen


func _poll_root_transfer_feedback() -> void:
	if _transfer_fx_layer == null:
		return
	if game_state == null:
		return
	if not game_state.has_method("get_node_root_transfer_feedback"):
		return

	for e in _node_list:
		var node_id: String = str(e["id"])
		var info = game_state.call("get_node_root_transfer_feedback", node_id)
		if typeof(info) != TYPE_DICTIONARY:
			continue

		var seen: Dictionary = (_transfer_event_seen.get(node_id, {
			"transfer_event_id": 0
		}) as Dictionary)

		var transfer_event_id: int = int(info.get("transfer_event_id", 0))
		var transfer_amount: int = int(info.get("transfer_amount", 0))

		if transfer_event_id > int(seen.get("transfer_event_id", 0)):
			if transfer_amount > 0:
				var popup_pos: Vector2 = spore_cloud.global_position
				if _root_pulse_visuals.has(node_id):
					var pulse: Dictionary = _root_pulse_visuals[node_id] as Dictionary
					var root: Node2D = pulse.get("root", null) as Node2D
					if root != null:
						popup_pos = root.global_position

				_spawn_transfer_popup(
					popup_pos + Vector2(0, -16),
					"",
					node_id,
					transfer_amount
				)

			seen["transfer_event_id"] = transfer_event_id

		_transfer_event_seen[node_id] = seen


func _spawn_transfer_popup(world_pos: Vector2, _text: String, node_id: String, amount: int = 0) -> void:
	if _transfer_fx_layer == null:
		return

	# Container node so icon + label move together
	var container := Node2D.new()
	container.top_level = true
	_transfer_fx_layer.add_child(container)
	container.global_position = world_pos

	# Small colored circle matching the node's visual
	var spr := Sprite2D.new()
	spr.texture = _make_circle_texture(14, false)
	spr.modulate = _node_color_for_id(node_id)
	spr.position = Vector2.ZERO
	container.add_child(spr)

	# Amount label to the right of the icon
	var lbl := Label.new()
	lbl.text = "+" + _fmt_int(amount) if amount > 0 else ""
	lbl.position = Vector2(12, -8)
	lbl.add_theme_font_size_override("font_size", TRANSFER_FONT_SIZE - 4)
	lbl.add_theme_color_override("font_color", TRANSFER_TEXT_COLOR)
	lbl.add_theme_color_override("font_outline_color", TRANSFER_TEXT_OUTLINE_COLOR)
	lbl.add_theme_constant_override("outline_size", 3)
	container.add_child(lbl)

	var end_pos: Vector2 = world_pos + Vector2(0, -TRANSFER_LIFT_PX)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "global_position", end_pos, TRANSFER_DURATION)
	tween.parallel().tween_property(container, "modulate:a", 0.0, TRANSFER_DURATION)
	tween.finished.connect(func():
		if is_instance_valid(container):
			container.queue_free()
	)

# ---------------- DigestPanel ----------------

func _bind_digest_panel() -> void:
	# Hide the old MarginContainer — we build our own layout
	var margin_c: Control = digest_panel.find_child("MarginContainer", true, false) as Control
	if margin_c != null:
		margin_c.visible = false

	# Remove any previous layout root
	var existing := digest_panel.find_child("DigestRoot", true, false) as Control
	if existing != null:
		existing.queue_free()

	var tm := ThemeManager

	# ── Root container ────────────────────────────────────────────────────
	var root := Control.new()
	root.name = "DigestRoot"
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	digest_panel.add_child(root)

	# ── Header ────────────────────────────────────────────────────────────
	_digest_header = Label.new()
	_digest_header.text = "Digest"
	_digest_header.add_theme_font_size_override("font_size", 16)
	_digest_header.add_theme_color_override("font_color", tm.c("accent"))
	root.add_child(_digest_header)

	# ── Tab row ───────────────────────────────────────────────────────────
	digest_tabs_row = HBoxContainer.new()
	digest_tabs_row.add_theme_constant_override("separation", 4)
	root.add_child(digest_tabs_row)

	digest_tab_resources = _make_digest_tab("Raw",       func(): _set_digest_active_category("resource"))
	digest_tab_compounds = _make_digest_tab("Compounds", func(): _set_digest_active_category("compound"))
	digest_tab_solutions = _make_digest_tab("Solutions", func(): _set_digest_active_category("solution"))
	digest_tabs_row.add_child(digest_tab_resources)
	digest_tabs_row.add_child(digest_tab_compounds)
	digest_tabs_row.add_child(digest_tab_solutions)

	# ── Scroll ────────────────────────────────────────────────────────────
	_digest_scroll = ScrollContainer.new()
	_digest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_digest_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(_digest_scroll)

	# Hide the scrollbar visually but keep scroll functionality
	await get_tree().process_frame
	var vscroll := _digest_scroll.get_node_or_null("_v_scroll") as ScrollBar
	if vscroll != null:
		var sb_hidden := StyleBoxEmpty.new()
		vscroll.add_theme_stylebox_override("scroll", sb_hidden)
		vscroll.custom_minimum_size = Vector2(0, 0)

	digest_inventory_list = VBoxContainer.new()
	digest_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	digest_inventory_list.add_theme_constant_override("separation", 2)
	_digest_scroll.add_child(digest_inventory_list)

	# ── Bottom bar ────────────────────────────────────────────────────────
	# Use Panel (not PanelContainer) — PanelContainer forces child layout
	# which overrides the explicit position/size we set in _layout_digest_panel
	_digest_bottom_bar = Panel.new()
	var sb_bar := StyleBoxFlat.new()
	sb_bar.bg_color         = tm.c("bg_panel")
	sb_bar.border_color     = tm.c("bark_stripe")
	sb_bar.border_width_top = 2
	sb_bar.set_corner_radius_all(0)
	(_digest_bottom_bar as Panel).add_theme_stylebox_override("panel", sb_bar)
	root.add_child(_digest_bottom_bar)

	# Feedback label fills the panel container's content area
	digest_feedback = Label.new()
	digest_feedback.name = "DigestFeedback"
	digest_feedback.text = "Select a resource"
	digest_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	digest_feedback.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	digest_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	digest_feedback.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	digest_feedback.add_theme_font_size_override("font_size", 14)
	digest_feedback.add_theme_color_override("font_color", tm.c("text_muted"))
	_digest_bottom_bar.add_child(digest_feedback)

	# ── Action bar (overlays bottom bar when row selected) ────────────────
	_digest_action_bar = _build_digest_action_bar(_digest_bottom_bar)
	_digest_action_bar.visible = false

	_set_digest_active_category("resource")


func _layout_digest_panel() -> void:
	var root := digest_panel.find_child("DigestRoot", true, false) as Control
	if root == null or _panel_container == null:
		return
	# Always use _panel_container — digest_panel.size reflects the scene's
	# baked size (full viewport), not the runtime panel height
	var W: float = _panel_container.size.x
	var H: float = _panel_container.size.y
	if W <= 0 or H <= 0:
		return

	root.position = Vector2.ZERO
	root.size     = Vector2(W, H)

	const HDR_H := 28.0
	const TAB_H := 36.0
	const BAR_H := 116.0
	const GAP   := 4.0

	if _digest_header != null:
		_digest_header.position = Vector2(0, 0)
		_digest_header.size     = Vector2(W, HDR_H)

	if digest_tabs_row != null:
		digest_tabs_row.position = Vector2(0, HDR_H + GAP)
		digest_tabs_row.size     = Vector2(W, TAB_H)

	var scroll_top := HDR_H + GAP + TAB_H + GAP
	if _digest_scroll != null:
		_digest_scroll.position = Vector2(0, scroll_top)
		_digest_scroll.size     = Vector2(W, H - scroll_top - BAR_H)

	if _digest_bottom_bar != null:
		_digest_bottom_bar.position = Vector2(0, H - BAR_H)
		_digest_bottom_bar.size     = Vector2(W, BAR_H)
		# PanelContainer children don't auto-resize when size is set directly
		# Force the feedback label to fill the content area
		if digest_feedback != null and is_instance_valid(digest_feedback):
			var margin := 12.0
			digest_feedback.position = Vector2(margin, margin)
			digest_feedback.size     = Vector2(W - margin * 2.0, BAR_H - margin * 2.0)
		if _digest_action_bar != null and is_instance_valid(_digest_action_bar):
			_digest_action_bar.position = Vector2(0, 0)
			_digest_action_bar.size     = Vector2(W, BAR_H)
		var root2 := digest_panel.find_child("DigestRoot", true, false) as Control


func _make_digest_tab(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	return btn


func _build_digest_action_bar(parent: Control) -> Control:
	var tm := ThemeManager
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color         = tm.c("bg_panel")
	sb.border_color     = tm.c("bark_stripe")
	sb.border_width_top = 2
	sb.set_corner_radius_all(0)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	bar.add_child(vbox)

	# ── Mode label ────────────────────────────────────────────────────────
	_digest_action_lbl = Label.new()
	_digest_action_lbl.name = "ActionLbl"
	_digest_action_lbl.add_theme_font_size_override("font_size", 13)
	_digest_action_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	vbox.add_child(_digest_action_lbl)

	# ── Main row: [Slider] [Amount+Value] [Digest btn] ────────────────────
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	vbox.add_child(main_row)

	_digest_slider = HSlider.new()
	_digest_slider.name = "DigestSlider"
	_digest_slider.min_value = 0.0
	_digest_slider.max_value = 1.0
	_digest_slider.step = 0.01
	_digest_slider.value = 1.0
	_digest_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_digest_slider.custom_minimum_size = Vector2(0, 28)
	_digest_slider.value_changed.connect(_on_digest_slider_changed)
	main_row.add_child(_digest_slider)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 2)
	right_col.custom_minimum_size = Vector2(80, 0)
	main_row.add_child(right_col)

	var lbl_amount := Label.new()
	lbl_amount.name = "LblSelectedAmt"
	lbl_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_amount.add_theme_font_size_override("font_size", 13)
	lbl_amount.add_theme_color_override("font_color", tm.c("accent"))
	right_col.add_child(lbl_amount)

	var lbl_value := Label.new()
	lbl_value.name = "LblSelectedVal"
	lbl_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_value.add_theme_font_size_override("font_size", 11)
	lbl_value.add_theme_color_override("font_color", tm.c("text_muted"))
	right_col.add_child(lbl_value)

	_digest_action_btn = Button.new()
	_digest_action_btn.name = "DigestBtn"
	_digest_action_btn.text = "Digest"
	_digest_action_btn.custom_minimum_size = Vector2(72, 0)
	_digest_action_btn.pressed.connect(_on_digest_action_pressed)
	_theme_action_button(_digest_action_btn)
	main_row.add_child(_digest_action_btn)

	parent.add_child(bar)
	return bar


func _set_digest_active_category(category: String) -> void:
	_digest_active_category = category
	_digest_selected_id = ""
	if _digest_action_bar != null:
		_digest_action_bar.visible = false
	_refresh_digest_panel()


func _clear_digest_rows() -> void:
	if digest_inventory_list == null:
		return
	for child in digest_inventory_list.get_children():
		child.queue_free()
	_digest_row_refs.clear()


func _refresh_digest_tab_buttons() -> void:
	if digest_tab_resources == null:
		return
	var compounds_unlocked := false
	var solutions_unlocked := false
	if game_state != null:
		if game_state.has_method("is_refinery_unlocked"):
			compounds_unlocked = bool(game_state.call("is_refinery_unlocked"))
		if game_state.has_method("is_synth_unlocked"):
			solutions_unlocked = bool(game_state.call("is_synth_unlocked"))

	digest_tab_compounds.disabled = not compounds_unlocked
	digest_tab_solutions.disabled = not solutions_unlocked

	if not compounds_unlocked and _digest_active_category == "compound":
		_digest_active_category = "resource"
	if not solutions_unlocked and _digest_active_category == "solution":
		_digest_active_category = "resource"

	_theme_tab_button(digest_tab_resources, _digest_active_category == "resource")
	_theme_tab_button(digest_tab_compounds, _digest_active_category == "compound")
	_theme_tab_button(digest_tab_solutions, _digest_active_category == "solution")


func _refresh_digest_panel() -> void:
	if digest_inventory_list == null:
		return
	_refresh_digest_tab_buttons()
	_clear_digest_rows()

	if digest_feedback != null:
		digest_feedback.text = "Select a resource" if _digest_selected_id == "" else ""

	if _digest_active_category == "compound":
		if game_state == null or not bool(game_state.call("is_refinery_unlocked")):
			if digest_feedback != null:
				digest_feedback.text = "Unlock Primitive Refinery to digest compounds."
			return
	elif _digest_active_category == "solution":
		if game_state == null or not bool(game_state.call("is_synth_unlocked")):
			if digest_feedback != null:
				digest_feedback.text = "Unlock Synthesis to digest solutions."
			return

	if game_state == null or not game_state.has_method("get_digest_inventory_entries"):
		return

	var entries_variant = game_state.call("get_digest_inventory_entries", _digest_active_category)
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No %s to digest." % _digest_active_category
		empty.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
		empty.add_theme_font_size_override("font_size", 13)
		digest_inventory_list.add_child(empty)
		return

	for entry_variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		var row := _make_digest_row(entry)
		digest_inventory_list.add_child(row)
		_digest_row_refs[str(entry.get("id", ""))] = row

	# Re-highlight selected row if still valid
	if _digest_selected_id != "" and _digest_row_refs.has(_digest_selected_id):
		_highlight_digest_row(_digest_selected_id)


func _make_digest_row(entry: Dictionary) -> Control:
	var item_id: String = str(entry.get("id", ""))
	var name_str: String = str(entry.get("name", ""))
	var amount: int      = int(entry.get("amount", 0))
	var dv: float        = float(entry.get("digest_each", 0.0))

	# Pill container
	var row := PanelContainer.new()
	row.name = "Row_" + item_id
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_row := StyleBoxFlat.new()
	sb_row.bg_color = ThemeManager.c("bg_panel")
	sb_row.border_color = ThemeManager.c("border")
	sb_row.set_border_width_all(1)
	sb_row.set_corner_radius_all(10)
	sb_row.content_margin_left   = 10
	sb_row.content_margin_right  = 10
	sb_row.content_margin_top    = 8
	sb_row.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb_row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# Colored resource dot
	var dot_tex := _make_circle_texture(16, false)
	var dot := TextureRect.new()
	dot.texture = dot_tex
	dot.modulate = _node_color_for_id(item_id)
	dot.custom_minimum_size = Vector2(16, 16)
	dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(dot)

	# Name
	var lbl_name := Label.new()
	lbl_name.text = name_str
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_name.add_theme_font_size_override("font_size", 14)
	lbl_name.add_theme_color_override("font_color", ThemeManager.c("text_primary"))
	hbox.add_child(lbl_name)

	# Amount (live-updating)
	var lbl_amt := Label.new()
	lbl_amt.name = "LblAmt"
	lbl_amt.text = _fmt_int(amount)
	lbl_amt.add_theme_font_size_override("font_size", 13)
	lbl_amt.add_theme_color_override("font_color",
		ThemeManager.c("accent") if _digest_auto_ids.get(item_id, false)
		else ThemeManager.c("text_secondary"))
	hbox.add_child(lbl_amt)

	# Value per unit
	var lbl_val := Label.new()
	lbl_val.text = "×%s" % _fmt_int(int(dv))
	lbl_val.add_theme_font_size_override("font_size", 12)
	lbl_val.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
	hbox.add_child(lbl_val)

	# Auto badge (hidden unless auto active)
	var auto_lbl := Label.new()
	auto_lbl.name = "AutoLbl"
	auto_lbl.text = "AUTO"
	auto_lbl.add_theme_font_size_override("font_size", 10)
	auto_lbl.add_theme_color_override("font_color", ThemeManager.c("accent"))
	auto_lbl.visible = _digest_auto_ids.get(item_id, false)
	hbox.add_child(auto_lbl)

	# Tap → select; hold → toggle auto
	# Use MOUSE_FILTER_PASS so ScrollContainer handles scroll,
	# we hit-test rows manually in _unhandled_input instead
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	# Selected highlight
	if item_id == _digest_selected_id:
		sb_row.bg_color     = ThemeManager.c("bg_row")
		sb_row.border_color = ThemeManager.c("accent_border")

	return row


func _highlight_digest_row(item_id: String) -> void:
	for rid in _digest_row_refs:
		var row: Control = _digest_row_refs[rid] as Control
		if not is_instance_valid(row):
			continue
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.content_margin_left   = 10
		sb.content_margin_right  = 10
		sb.content_margin_top    = 8
		sb.content_margin_bottom = 8
		sb.set_border_width_all(1)
		if rid == item_id:
			sb.bg_color     = ThemeManager.c("bg_row")
			sb.border_color = ThemeManager.c("accent_border")
		else:
			sb.bg_color     = ThemeManager.c("bg_panel")
			sb.border_color = ThemeManager.c("border")
		row.add_theme_stylebox_override("panel", sb)


func _on_digest_row_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_digest_hold_timer    = 0.0
			_digest_hold_id       = item_id
			_digest_hold_consumed = false
		else:
			get_viewport().set_input_as_handled()
			var press_id := _digest_hold_id if _digest_hold_id != "" else item_id
			if _digest_hold_consumed:
				_digest_hold_consumed = false
			elif _digest_hold_timer < 0.6:
				if _digest_selected_id == press_id:
					_digest_selected_id = ""
					_highlight_digest_row("")
					if _digest_action_bar != null:
						_digest_action_bar.visible = false
				else:
					_select_digest_row(press_id)
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0
	elif event is InputEventScreenTouch:
		if event.pressed:
			_digest_hold_timer    = 0.0
			_digest_hold_id       = item_id
			_digest_hold_consumed = false
		else:
			get_viewport().set_input_as_handled()
			var press_id := _digest_hold_id if _digest_hold_id != "" else item_id
			if _digest_hold_consumed:
				_digest_hold_consumed = false
			elif _digest_hold_timer < 0.6:
				if _digest_selected_id == press_id:
					_digest_selected_id = ""
					_highlight_digest_row("")
					if _digest_action_bar != null:
						_digest_action_bar.visible = false
				else:
					_select_digest_row(press_id)
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0



func _select_digest_row(item_id: String) -> void:
	_digest_selected_id = item_id
	_highlight_digest_row(item_id)
	_digest_pct = float(_digest_auto_ids.get(item_id + "_pct", 1.0))
	if _digest_slider != null:
		_digest_slider.value = _digest_pct

	# Get current value for this item
	_digest_selected_value = 0.0
	if game_state != null and game_state.has_method("get_digest_inventory_entries"):
		var entries_v = game_state.call("get_digest_inventory_entries", _digest_active_category)
		if typeof(entries_v) == TYPE_ARRAY:
			for ev in (entries_v as Array):
				var e := ev as Dictionary
				if str(e.get("id", "")) == item_id:
					_digest_selected_value = float(e.get("digest_each", 0.0))
					break

	_update_digest_action_bar()
	if _digest_action_bar != null:
		_digest_action_bar.visible = true


func _update_digest_action_bar() -> void:
	if _digest_action_bar == null or _digest_selected_id == "":
		return

	var is_auto: bool = _digest_auto_ids.get(_digest_selected_id, false)
	var amount: int = 0
	if game_state != null and game_state.has_method("get_amount"):
		amount = int(game_state.call("get_amount", _digest_selected_id))
	var selected_amt: int   = int(floor(amount * _digest_pct))
	var nutrient_yield: int = int(round(selected_amt * _digest_selected_value))
	var res_name := _pretty_res(_digest_selected_id)
	var pct_int := int(_digest_pct * 100)

	# Resource name + auto hint
	if _digest_action_lbl != null:
		if is_auto:
			_digest_action_lbl.text = "%s  —  Auto-digesting %d%% of incoming" % [res_name, pct_int]
		else:
			_digest_action_lbl.text = "%s  •  %s → %s nutrients" % [res_name, _fmt_int(selected_amt), _fmt_int(nutrient_yield)]

	# Amount label
	var lbl_amt: Label = _digest_action_bar.find_child("LblSelectedAmt", true, false) as Label
	if lbl_amt != null:
		lbl_amt.text = "%d%%" % pct_int if is_auto else _fmt_int(selected_amt)

	# Value label
	var lbl_val: Label = _digest_action_bar.find_child("LblSelectedVal", true, false) as Label
	if lbl_val != null:
		lbl_val.text = "of incoming" if is_auto else "%s nutrients" % _fmt_int(nutrient_yield)

	# Button: reflects auto state, not mode
	if _digest_action_btn != null:
		if is_auto:
			_digest_action_btn.text = "Auto ON"
		else:
			_digest_action_btn.text = "Digest"


func _on_digest_slider_changed(value: float) -> void:
	_digest_pct = clampf(value, 0.0, 1.0)
	# If this item has auto-digest enabled, persist the pct
	if _digest_selected_id != "" and _digest_auto_ids.get(_digest_selected_id, false):
		_digest_auto_ids[_digest_selected_id + "_pct"] = _digest_pct
	_update_digest_action_bar()


func _execute_auto_digest() -> void:
	if game_state == null or _digest_auto_ids.is_empty():
		return
	for item_id_v in _digest_auto_ids.keys():
		var item_id := str(item_id_v)
		if item_id.ends_with("_pct"):
			continue
		if not _digest_auto_ids.get(item_id, false):
			continue
		var pct: float = float(_digest_auto_ids.get(item_id + "_pct", 1.0))
		if pct <= 0.0:
			continue
		var current_amt: int = int(game_state.call("get_amount", item_id))
		var last_amt: int    = int(_digest_auto_last_amt.get(item_id, current_amt))
		# Only digest new arrivals since last tick
		var incoming: int = max(0, current_amt - last_amt)
		var digest_amt: int = int(floor(incoming * pct))
		if digest_amt > 0 and game_state.has_method("digest_inventory_item"):
			game_state.call("digest_inventory_item", item_id, digest_amt)
		# Record current amount as baseline for next tick
		_digest_auto_last_amt[item_id] = current_amt


func _toggle_digest_auto(item_id: String) -> void:
	var was_auto: bool = _digest_auto_ids.get(item_id, false)
	_digest_auto_ids[item_id] = not was_auto
	if not was_auto:
		# Enabling — seed baseline so we only digest future incoming, not existing stock
		if game_state != null and game_state.has_method("get_amount"):
			_digest_auto_last_amt[item_id] = int(game_state.call("get_amount", item_id))
	else:
		# Disabling — clear the baseline
		_digest_auto_last_amt.erase(item_id)
	# Refresh just this row's AUTO badge and amount color
	var row: Control = _digest_row_refs.get(item_id, null) as Control
	if row != null and is_instance_valid(row):
		var auto_lbl: Label = row.find_child("AutoLbl", true, false) as Label
		if auto_lbl != null:
			auto_lbl.visible = not was_auto
		var lbl_amt: Label = row.find_child("LblAmt", true, false) as Label
		if lbl_amt != null:
			lbl_amt.add_theme_color_override("font_color",
				ThemeManager.c("accent") if not was_auto else ThemeManager.c("text_secondary"))


func _on_digest_action_pressed() -> void:
	if _digest_selected_id == "" or game_state == null:
		return

	var is_auto: bool = _digest_auto_ids.get(_digest_selected_id, false)

	if is_auto:
		# Button reads "Auto ON" → tap turns it off
		_toggle_digest_auto(_digest_selected_id)
		_digest_auto_ids[_digest_selected_id + "_pct"] = _digest_pct
		_update_digest_action_bar()
		return

	# Button reads "Digest" → manual digest at current slider %
	var amount: int = int(game_state.call("get_amount", _digest_selected_id))
	var digest_amt: int = int(floor(amount * _digest_pct))
	if digest_amt <= 0:
		if digest_feedback != null:
			digest_feedback.text = "Nothing to digest."
		return
	var digested: int = 0
	if game_state.has_method("digest_inventory_item"):
		digested = int(game_state.call("digest_inventory_item", _digest_selected_id, digest_amt))
	if digested > 0:
		_flash_nutrients()
		if digest_feedback != null:
			digest_feedback.text = "Digested %s %s → %s nutrients." % [
				_fmt_int(digested),
				_pretty_res(_digest_selected_id),
				_fmt_int(int(round(digested * _digest_selected_value)))
			]
	else:
		if digest_feedback != null:
			digest_feedback.text = "Nothing to digest."
	_refresh_currency_ui()
	_update_digest_live_values()
	_update_digest_action_bar()


func _update_digest_live_values() -> void:
	# Update amount labels in existing rows without full rebuild
	if game_state == null:
		return
	for item_id_v in _digest_row_refs.keys():
		var item_id := str(item_id_v)
		var row: Control = _digest_row_refs[item_id] as Control
		if not is_instance_valid(row):
			continue
		var lbl_amt: Label = row.find_child("LblAmt", true, false) as Label
		if lbl_amt != null and game_state.has_method("get_amount"):
			var amt: int = int(game_state.call("get_amount", item_id))
			lbl_amt.text = _fmt_int(amt)


func _on_digest_panel_1_pressed() -> void:
	pass

func _on_digest_panel_all_pressed() -> void:
	pass

func _digest_selected_node_at_cloud(_amount: int) -> void:
	pass

func _make_digest_entry_row(_entry: Dictionary) -> Control:
	return Control.new()

func _on_digest_inventory_amount_pressed(_item_id: String, _amount: int) -> void:
	pass





func _flash_nutrients() -> void:
	if lbl_nutrients == null:
		return

	if _nutrients_flash_tween != null:
		_nutrients_flash_tween.kill()

	lbl_nutrients.scale = _nutrients_base_scale * 1.15

	_nutrients_flash_tween = create_tween()
	_nutrients_flash_tween.tween_property(lbl_nutrients, "scale", _nutrients_base_scale, 0.18)


# ---------------- Signatures ----------------

func _get_refinery_inventory_signature() -> String:
	var parts: Array[String] = []
	if game_state == null:
		return ""

	var compound_defs: Dictionary = game_state.get("compound_defs")
	for compound_id_variant in compound_defs.keys():
		var compound_id := str(compound_id_variant)
		parts.append("%s:%s" % [compound_id, int(game_state.get_amount(compound_id))])

	var solution_defs: Dictionary = game_state.get("solution_defs")
	for solution_id_variant in solution_defs.keys():
		var solution_id := str(solution_id_variant)
		parts.append("%s:%s" % [solution_id, int(game_state.get_amount(solution_id))])

	parts.sort()
	return "|".join(parts)


func _get_discovery_signature() -> String:
	var parts: Array[String] = []
	if game_state == null:
		return ""

	var resource_defs: Dictionary = game_state.get("resource_defs")
	for item_id_variant in resource_defs.keys():
		var item_id := str(item_id_variant)
		parts.append("%s:%s" % [item_id, int(game_state.get_amount(item_id))])

	var unlocked_discoveries: Dictionary = game_state.get("unlocked_discoveries")
	for discovery_id_variant in unlocked_discoveries.keys():
		var discovery_id := str(discovery_id_variant)
		parts.append("u:%s:%s" % [discovery_id, str(bool(unlocked_discoveries[discovery_id]))])

	var discovery_levels: Dictionary = game_state.get("discovery_levels")
	for discovery_id_variant in discovery_levels.keys():
		var discovery_id := str(discovery_id_variant)
		parts.append("lvl:%s:%s" % [discovery_id, int(discovery_levels[discovery_id])])

	parts.sort()
	return "|".join(parts)


# ---------------- DiscoveriesPanel ----------------

func _bind_discoveries_panel() -> void:
	var root_box: VBoxContainer = discoveries_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if root_box == null:
		return
	for child in root_box.get_children():
		child.queue_free()

	# Ensure the panel and root box fill the container vertically
	discoveries_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical          = Control.SIZE_EXPAND_FILL
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Header
	var header := Label.new()
	header.text = "Discoveries"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", ThemeManager.c("accent"))
	root_box.add_child(header)

	# Feedback label
	discoveries_feedback = Label.new()
	discoveries_feedback.name = "DiscoveriesFeedback"
	discoveries_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discoveries_feedback.add_theme_font_size_override("font_size", 12)
	discoveries_feedback.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
	root_box.add_child(discoveries_feedback)

	# Grid canvas — drawn in code using a Control
	var grid := Control.new()
	grid.name = "DiscoveryGrid"
	grid.custom_minimum_size = Vector2(0, 420)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(grid)
	discoveries_list = root_box  # reuse var so refresh finds the panel


func _refresh_panel_access_ui() -> void:
	var can_show_discoveries := false
	var can_show_refinery    := false
	var can_show_chamber     := false
	if game_state != null:
		if game_state.has_method("can_show_discoveries_tab"):
			can_show_discoveries = bool(game_state.call("can_show_discoveries_tab"))
		if game_state.has_method("is_refinery_unlocked"):
			can_show_refinery = bool(game_state.call("is_refinery_unlocked"))
		if game_state.has_method("is_mutation_chamber_unlocked"):
			can_show_chamber = bool(game_state.call("is_mutation_chamber_unlocked"))

	if btn_discoveries != null:
		btn_discoveries.modulate.a = 1.0 if can_show_discoveries else 0.3
		btn_discoveries.disabled   = not can_show_discoveries
	if btn_refinery != null:
		btn_refinery.modulate.a = 1.0 if can_show_refinery else 0.3
		btn_refinery.disabled   = not can_show_refinery
	if btn_prestige != null:
		btn_prestige.visible    = can_show_chamber
		btn_prestige.disabled   = not can_show_chamber
		btn_prestige.modulate.a = 1.0 if can_show_chamber else 0.0

	if not can_show_refinery and _open_panel == refinery_panel:
		_close_current()

	_redraw_nav_buttons()


func _clear_discoveries_rows() -> void:
	_disc_node_refs.clear()
	if discoveries_panel == null:
		return
	var grid: Control = discoveries_panel.find_child("DiscoveryGrid", true, false) as Control
	if grid == null:
		return
	for child in grid.get_children():
		child.queue_free()


func _refresh_discoveries_panel() -> void:
	if discoveries_panel == null or game_state == null:
		return
	_clear_discoveries_rows()

	if discoveries_feedback != null:
		if not game_state.has_method("can_show_discoveries_tab") or not bool(game_state.call("can_show_discoveries_tab")):
			discoveries_feedback.text = "Connect a second node to unlock Discoveries."
			return
		discoveries_feedback.text = ""

	if not game_state.has_method("get_discovery_ui_entries"):
		return
	var entries_v = game_state.call("get_discovery_ui_entries")
	if typeof(entries_v) != TYPE_ARRAY:
		return
	var entries: Array = entries_v as Array

	# Build lookup by id
	var by_id: Dictionary = {}
	for ev in entries:
		var e := ev as Dictionary
		by_id[str(e.get("id", ""))] = e

	var grid: Control = discoveries_panel.find_child("DiscoveryGrid", true, false) as Control
	if grid == null:
		return

	# ── Grid layout (positions relative to grid Control) ──────────────────
	# Grid is 412px wide. Center x = 206. Node size = 88×88.
	# Layout:
	#   aura_activation          — top center
	#   primitive_refinery       — middle left
	#   mycelial_insight         — middle center  (root)
	#   [synthesis               — middle far left, off aura branch not used yet]
	#   excess_fertilizer        — middle right (or bottom center per design)
	#   nutrient_efficiency_1    — below excess_fertilizer
	#
	# Branches: root→aura (up), root→refinery (left), root→excess (right/down)
	#            excess→nutrient_eff (down), refinery→synthesis (left)

	var cx: float = 206.0
	var node_w := 88.0
	var node_h := 88.0

	var positions: Dictionary = {
		"mycelial_insight":      Vector2(cx - node_w * 0.5,  160),
		"aura_activation":       Vector2(cx - node_w * 0.5,  30),
		"primitive_refinery":    Vector2(cx - node_w * 1.5 - 20, 160),
		"synthesis":             Vector2(cx - node_w * 2.5 - 40, 160),
		"excess_fertilizer":     Vector2(cx + node_w * 0.5 + 20, 160),
		"nutrient_efficiency_1": Vector2(cx + node_w * 0.5 + 20, 290),
	}

	# Connection lines (drawn as ColorRect strips or Line2D)
	var connections: Array = [
		["mycelial_insight", "aura_activation"],
		["mycelial_insight", "primitive_refinery"],
		["mycelial_insight", "excess_fertilizer"],
		["primitive_refinery", "synthesis"],
		["excess_fertilizer", "nutrient_efficiency_1"],
	]

	for conn in connections:
		var id_a: String = conn[0]
		var id_b: String = conn[1]
		if not positions.has(id_a) or not positions.has(id_b):
			continue
		var pos_a: Vector2 = positions[id_a] as Vector2
		var pos_b: Vector2 = positions[id_b] as Vector2
		var center_a := pos_a + Vector2(node_w * 0.5, node_h * 0.5)
		var center_b := pos_b + Vector2(node_w * 0.5, node_h * 0.5)
		var line := _make_disc_connector(center_a, center_b, by_id, id_a, id_b)
		grid.add_child(line)

	# Discovery nodes
	for disc_id in positions.keys():
		var pos: Vector2 = positions[disc_id] as Vector2
		var entry: Dictionary = by_id.get(disc_id, {}) as Dictionary
		var node := _make_disc_node(disc_id, entry, Vector2(node_w, node_h))
		node.position = pos
		grid.add_child(node)
		_disc_node_refs[disc_id] = node


func _make_disc_connector(from: Vector2, to: Vector2, by_id: Dictionary, id_a: String, id_b: String) -> Node2D:
	var entry_a: Dictionary = by_id.get(id_a, {}) as Dictionary
	var _entry_b: Dictionary = by_id.get(id_b, {}) as Dictionary
	var unlocked_a: bool = bool(entry_a.get("complete", false)) or (int(entry_a.get("level", 0)) > 0)
	var col: Color = ThemeManager.c("accent_dim") if unlocked_a else ThemeManager.c("border")

	var line := Line2D.new()
	line.default_color = col
	line.width = 2.0
	line.add_point(from)
	line.add_point(to)
	return line


func _make_disc_node(disc_id: String, entry: Dictionary, node_size: Vector2) -> Control:
	var tm := ThemeManager
	var level: int    = int(entry.get("level", 0))
	var complete: bool = bool(entry.get("complete", false))
	var can_buy: bool  = bool(entry.get("can_buy", false))
	var available: bool = bool(entry.get("available", false))
	var name_str: String = str(entry.get("name", disc_id))
	var is_root: bool = disc_id == "mycelial_insight"

	# State: unlocked > can_buy > available > locked
	var state: String = "locked"
	if complete or level > 0:
		state = "unlocked"
	elif can_buy:
		state = "ready"
	elif available:
		state = "available"

	# Outer container
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = node_size
	btn.size = node_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# Background panel
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	match state:
		"unlocked":
			sb.bg_color     = tm.c("accent_glow")
			sb.border_color = tm.c("accent")
		"ready":
			sb.bg_color     = tm.c("bg_panel")
			sb.border_color = tm.c("accent")
		"available":
			sb.bg_color     = tm.c("bg_panel")
			sb.border_color = tm.c("border")
		_:  # locked
			sb.bg_color     = tm.c("bg_deep")
			sb.border_color = tm.c("border")
	if is_root and state == "unlocked":
		sb.border_color = tm.c("accent")

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover",  sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus",  sb)

	# Content vbox
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	btn.add_child(vbox)

	# Icon (drawn via custom draw — use a simple Control)
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size = Vector2(32, 32)
	icon_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon_col: Color = tm.c("accent") if state == "unlocked" or state == "ready" else tm.c("text_muted")
	icon_ctrl.draw.connect(_draw_disc_icon.bind(icon_ctrl, disc_id, icon_col))
	vbox.add_child(icon_ctrl)

	# Name label
	var lbl := Label.new()
	lbl.text = name_str
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	var text_col: Color
	match state:
		"unlocked": text_col = tm.c("accent")
		"ready":    text_col = tm.c("text_primary")
		_:          text_col = tm.c("text_muted")
	lbl.add_theme_color_override("font_color", text_col)
	vbox.add_child(lbl)

	# Level badge for repeatables
	var max_level: int = int(entry.get("max_level", 1))
	if max_level > 1:
		var lv_lbl := Label.new()
		lv_lbl.text = "Lv %d/%d" % [level, max_level]
		lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv_lbl.add_theme_font_size_override("font_size", 9)
		lv_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(lv_lbl)

	# Connect button
	if not entry.is_empty():
		btn.pressed.connect(_on_disc_node_pressed.bind(disc_id, entry))
	else:
		btn.modulate.a = 0.25  # not yet visible in data

	return btn


func _draw_disc_icon(ctrl: Control, disc_id: String, col: Color) -> void:
	var cx := ctrl.size.x * 0.5
	var cy := ctrl.size.y * 0.5
	var s  := 10.0
	var w  := 1.5
	match disc_id:
		"mycelial_insight":
			# Spore burst — central circle + radiating lines
			ctrl.draw_circle(Vector2(cx, cy), s * 0.5, col)
			for i in range(6):
				var angle := float(i) * TAU / 6.0
				var inner := Vector2(cos(angle), sin(angle)) * s * 0.7
				var outer_v := Vector2(cos(angle), sin(angle)) * s * 1.3
				ctrl.draw_line(Vector2(cx, cy) + inner, Vector2(cx, cy) + outer_v, col, w, true)
		"aura_activation":
			# Concentric arcs
			ctrl.draw_arc(Vector2(cx, cy), s * 0.5, 0, TAU, 32, col, w, true)
			ctrl.draw_arc(Vector2(cx, cy), s * 1.0, -PI * 0.6, PI * 0.6, 24, col, w, true)
			ctrl.draw_arc(Vector2(cx, cy), s * 1.4, -PI * 0.35, PI * 0.35, 16, col, w, true)
		"primitive_refinery":
			# Flask shape
			ctrl.draw_line(Vector2(cx - s*0.4, cy - s), Vector2(cx + s*0.4, cy - s), col, w, true)
			ctrl.draw_line(Vector2(cx - s*0.4, cy - s), Vector2(cx - s*0.8, cy + s*0.5), col, w, true)
			ctrl.draw_line(Vector2(cx + s*0.4, cy - s), Vector2(cx + s*0.8, cy + s*0.5), col, w, true)
			ctrl.draw_arc(Vector2(cx, cy + s*0.5), s * 0.8, 0, TAU, 32, col, w, true)
			ctrl.draw_circle(Vector2(cx, cy + s*0.5), s * 0.3, col)
		"synthesis":
			# Interlocked circles
			ctrl.draw_arc(Vector2(cx - s*0.4, cy), s * 0.7, 0, TAU, 32, col, w, true)
			ctrl.draw_arc(Vector2(cx + s*0.4, cy), s * 0.7, 0, TAU, 32, col, w, true)
		"excess_fertilizer":
			# Upward arrows (growth)
			ctrl.draw_line(Vector2(cx, cy + s), Vector2(cx, cy - s), col, w, true)
			ctrl.draw_line(Vector2(cx, cy - s), Vector2(cx - s*0.4, cy - s*0.4), col, w, true)
			ctrl.draw_line(Vector2(cx, cy - s), Vector2(cx + s*0.4, cy - s*0.4), col, w, true)
			ctrl.draw_line(Vector2(cx - s*0.6, cy + s*0.3), Vector2(cx - s*0.6, cy - s*0.5), col, w, true)
			ctrl.draw_line(Vector2(cx + s*0.6, cy + s*0.3), Vector2(cx + s*0.6, cy - s*0.5), col, w, true)
		"nutrient_efficiency_1":
			# Diamond / crystal
			var pts := PackedVector2Array([
				Vector2(cx, cy - s),
				Vector2(cx + s*0.7, cy),
				Vector2(cx, cy + s),
				Vector2(cx - s*0.7, cy),
				Vector2(cx, cy - s),
			])
			ctrl.draw_polyline(pts, col, w, true)
			ctrl.draw_line(Vector2(cx - s*0.7, cy), Vector2(cx + s*0.7, cy), col, w * 0.5, true)
		_:
			ctrl.draw_circle(Vector2(cx, cy), s * 0.8, col)


func _on_disc_node_pressed(disc_id: String, entry: Dictionary) -> void:
	_show_disc_popup(disc_id, entry)


# ── Discovery popup ───────────────────────────────────────────────────────────

func _show_disc_popup(disc_id: String, entry: Dictionary) -> void:
	_close_disc_popup()
	_disc_popup_disc_id = disc_id
	var vp := get_viewport_rect().size
	var tm := ThemeManager

	# ── CanvasLayer ensures popup renders above ALL other UI ─────────────
	_disc_popup_layer = CanvasLayer.new()
	_disc_popup_layer.layer = 128  # well above default (0) and panel container
	add_child(_disc_popup_layer)

	# ── Dimmer ────────────────────────────────────────────────────────────
	_disc_popup_dimmer = ColorRect.new()
	_disc_popup_dimmer.size      = vp
	_disc_popup_dimmer.position  = Vector2.ZERO
	_disc_popup_dimmer.color     = Color(0, 0, 0, 0)
	_disc_popup_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_disc_popup_dimmer.gui_input.connect(_on_disc_popup_dimmer_input)
	_disc_popup_layer.add_child(_disc_popup_dimmer)

	# ── Popup card ────────────────────────────────────────────────────────
	var popup := PanelContainer.new()
	popup.z_index   = 11
	popup.custom_minimum_size = Vector2(320, 0)

	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("border")
	sb.set_border_width_all(1)
	sb.border_color = tm.c("bark_stripe")
	sb.border_width_top = 3
	sb.set_corner_radius_all(16)
	sb.content_margin_left   = 20
	sb.content_margin_right  = 20
	sb.content_margin_top    = 18
	sb.content_margin_bottom = 20
	popup.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	# ── Header row (name + X) ─────────────────────────────────────────────
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.text = str(entry.get("name", disc_id))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", tm.c("accent"))
	header_row.add_child(name_lbl)

	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.draw.connect(func():
		var c: Color = tm.c("text_muted")
		var cx2 := close_btn.size.x * 0.5
		var cy2 := close_btn.size.y * 0.5
		var r := 6.0
		close_btn.draw_line(Vector2(cx2-r, cy2-r), Vector2(cx2+r, cy2+r), c, 1.5, true)
		close_btn.draw_line(Vector2(cx2+r, cy2-r), Vector2(cx2-r, cy2+r), c, 1.5, true)
	)
	close_btn.pressed.connect(_close_disc_popup)
	header_row.add_child(close_btn)

	# ── Divider ───────────────────────────────────────────────────────────
	var div := HSeparator.new()
	var sb_div := StyleBoxFlat.new()
	sb_div.bg_color = tm.c("border")
	sb_div.content_margin_top = 0
	sb_div.content_margin_bottom = 0
	div.add_theme_stylebox_override("separator", sb_div)
	vbox.add_child(div)

	# ── Description ───────────────────────────────────────────────────────
	var desc_lbl := Label.new()
	desc_lbl.text = str(entry.get("effect_text", "No description available."))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", tm.c("text_secondary"))
	vbox.add_child(desc_lbl)

	# ── Cost row ──────────────────────────────────────────────────────────
	var complete: bool = bool(entry.get("complete", false))
	var level: int     = int(entry.get("level", 0))
	var max_level: int = int(entry.get("max_level", 1))

	if complete and max_level <= 1:
		var done_lbl := Label.new()
		done_lbl.text = "✓ Already unlocked"
		done_lbl.add_theme_font_size_override("font_size", 13)
		done_lbl.add_theme_color_override("font_color", tm.c("accent"))
		vbox.add_child(done_lbl)
	else:
		# Cost header
		var cost_header := Label.new()
		cost_header.text = "Cost" if level == 0 else "Cost (Lv %d → %d)" % [level, level + 1]
		cost_header.add_theme_font_size_override("font_size", 12)
		cost_header.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(cost_header)

		# Cost resource rows
		var costs_v = game_state.call("get_discovery_costs_for_next_level", disc_id) if game_state != null else []
		if typeof(costs_v) == TYPE_ARRAY:
			var costs: Array = costs_v as Array
			for cost_v in costs:
				var cost: Dictionary = cost_v as Dictionary
				var res_id: String  = str(cost.get("id", ""))
				var qty: int        = int(cost.get("qty", 0))
				var have: int       = int(game_state.call("get_amount", res_id)) if game_state != null else 0
				var can_afford: bool = have >= qty

				var cost_row := HBoxContainer.new()
				cost_row.add_theme_constant_override("separation", 8)
				vbox.add_child(cost_row)

				# Colored dot
				var dot_tex := _make_circle_texture(14, false)
				var dot := TextureRect.new()
				dot.texture = dot_tex
				dot.modulate = _node_color_for_id(res_id)
				dot.custom_minimum_size = Vector2(14, 14)
				dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				cost_row.add_child(dot)

				# Resource name
				var res_name := _pretty_res(res_id)
				var res_lbl := Label.new()
				res_lbl.text = res_name
				res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				res_lbl.add_theme_font_size_override("font_size", 13)
				res_lbl.add_theme_color_override("font_color", tm.c("text_secondary"))
				cost_row.add_child(res_lbl)

				# Amount (have / need)
				var amt_lbl := Label.new()
				amt_lbl.text = "%s / %s" % [_fmt_int(have), _fmt_int(qty)]
				amt_lbl.add_theme_font_size_override("font_size", 13)
				amt_lbl.add_theme_color_override("font_color",
					tm.c("accent") if can_afford else tm.c("text_muted"))
				cost_row.add_child(amt_lbl)

	# ── Discover button ───────────────────────────────────────────────────
	var can_buy: bool = bool(entry.get("can_buy", false))

	if not complete or max_level > 1:
		var disc_btn := Button.new()
		disc_btn.text = "Discover" if level == 0 else "Upgrade"
		disc_btn.disabled = not can_buy
		disc_btn.focus_mode = Control.FOCUS_NONE
		_theme_action_button(disc_btn)
		disc_btn.pressed.connect(func():
			_on_discovery_buy_pressed(disc_id)
		)
		vbox.add_child(disc_btn)

	_disc_popup = popup
	_disc_popup_layer.add_child(popup)

	# Center popup after one frame, clamped to screen
	await get_tree().process_frame
	if is_instance_valid(popup):
		var px := (vp.x - popup.size.x) * 0.5
		var py := (vp.y - popup.size.y) * 0.5
		# Clamp so popup never goes off screen
		px = clampf(px, 8.0, vp.x - popup.size.x - 8.0)
		py = clampf(py, 8.0, vp.y - popup.size.y - 8.0)
		popup.position = Vector2(px, py)

	# Fade in dimmer
	var tw := create_tween()
	tw.tween_property(_disc_popup_dimmer, "color:a", 0.55, 0.15)


func _close_disc_popup() -> void:
	if _disc_popup_layer != null and is_instance_valid(_disc_popup_layer):
		_disc_popup_layer.queue_free()
		_disc_popup_layer = null
	_disc_popup        = null
	_disc_popup_dimmer = null
	_disc_popup_disc_id = ""
	_popup_closed_this_press = true


func _on_disc_popup_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_disc_popup()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_close_disc_popup()
		get_viewport().set_input_as_handled()



func _on_discovery_buy_pressed(discovery_id: String) -> void:
	if game_state == null or not game_state.has_method("buy_discovery"):
		return

	var result = game_state.call("buy_discovery", discovery_id)
	var ok := false
	var reason := "Unable to buy discovery."

	if typeof(result) == TYPE_DICTIONARY:
		ok = bool((result as Dictionary).get("ok", false))
		reason = str((result as Dictionary).get("reason", reason))

	if discoveries_feedback != null:
		if ok:
			discoveries_feedback.text = "Unlocked %s" % discovery_id
		else:
			discoveries_feedback.text = reason

	_refresh_panel_access_ui()
	_refresh_currency_ui()
	_refresh_node_world_state()
	_refresh_discoveries_panel()

	if ok:
		if _open_panel == refinery_panel:
			_refresh_refinery_panel()
		if _open_panel == digest_panel:
			_refresh_digest_panel()
		_last_refinery_inventory_signature = _get_refinery_inventory_signature()
		_last_discovery_signature = _get_discovery_signature()

		# Close popup — grid will have refreshed showing unlocked state
		_close_disc_popup()
	else:
		# Purchase failed — update popup button state if open
		if _disc_popup != null and is_instance_valid(_disc_popup) and _disc_popup_disc_id == discovery_id:
			if discoveries_feedback != null:
				discoveries_feedback.text = reason


# ---------------- RefineryPanel ----------------

func _bind_refinery_panel() -> void:
	refinery_list = refinery_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if refinery_list == null:
		return

	refinery_tabs_row = HBoxContainer.new()
	refinery_tabs_row.name = "RefineryTabsRow"
	refinery_tabs_row.add_theme_constant_override("separation", 8)
	refinery_list.add_child(refinery_tabs_row)

	refinery_tab_compounds = Button.new()
	refinery_tab_compounds.text = "Compounds"
	refinery_tab_compounds.pressed.connect(func(): _set_refinery_active_category("compound"))
	refinery_tabs_row.add_child(refinery_tab_compounds)

	refinery_tab_solutions = Button.new()
	refinery_tab_solutions.text = "Solutions"
	refinery_tab_solutions.pressed.connect(func(): _set_refinery_active_category("solution"))
	refinery_tabs_row.add_child(refinery_tab_solutions)

	refinery_feedback = Label.new()
	refinery_feedback.name = "RefineryFeedback"
	refinery_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refinery_feedback.text = ""
	refinery_list.add_child(refinery_feedback)

	_set_refinery_active_category("compound")


func _clear_refinery_rows() -> void:
	if refinery_list == null:
		return
	for child in refinery_list.get_children():
		if child == refinery_feedback or child == refinery_tabs_row:
			continue
		child.queue_free()
		child.queue_free()


func _refresh_refinery_tab_buttons() -> void:
	if refinery_tab_compounds == null or refinery_tab_solutions == null:
		return

	var compounds_unlocked := false
	var solutions_unlocked := false
	if game_state != null:
		if game_state.has_method("is_refinery_unlocked"):
			compounds_unlocked = bool(game_state.call("is_refinery_unlocked"))
		if game_state.has_method("is_synth_unlocked"):
			solutions_unlocked = bool(game_state.call("is_synth_unlocked"))

	refinery_tab_compounds.disabled = not compounds_unlocked
	refinery_tab_solutions.disabled = not solutions_unlocked

	if not solutions_unlocked and _refinery_active_category == "solution":
		_refinery_active_category = "compound"

	var ractive := _refinery_active_category
	_theme_tab_button(refinery_tab_compounds, ractive == "compound")
	_theme_tab_button(refinery_tab_solutions, ractive == "solution")


func _set_refinery_active_category(category: String) -> void:
	_refinery_active_category = category
	_refresh_refinery_panel()


func _refresh_refinery_panel() -> void:
	if refinery_list == null or game_state == null:
		return

	_refresh_refinery_tab_buttons()
	_clear_refinery_rows()

	if refinery_feedback != null:
		refinery_feedback.text = ""

	if _refinery_active_category == "compound":
		if not game_state.has_method("is_refinery_unlocked") or not bool(game_state.call("is_refinery_unlocked")):
			if refinery_feedback != null:
				refinery_feedback.text = "Requires Primitive Refinery."
			return

		var visible_unlock_ids: Array = []
		if game_state.has_method("get_visible_compound_unlock_ids"):
			visible_unlock_ids = game_state.call("get_visible_compound_unlock_ids")

		if not visible_unlock_ids.is_empty():
			var recipe_header := Label.new()
			recipe_header.text = "Recipe Unlock"
			refinery_list.add_child(recipe_header)

			for recipe_id_variant in visible_unlock_ids:
				var recipe_id := str(recipe_id_variant)
				refinery_list.add_child(_make_refinery_recipe_unlock_card(recipe_id))

		var spacer := HSeparator.new()
		refinery_list.add_child(spacer)

		if not game_state.has_method("get_refinery_ui_entries"):
			return

		var entries = game_state.call("get_refinery_ui_entries")
		if typeof(entries) != TYPE_ARRAY:
			return

		for entry_variant in entries:
			var entry: Dictionary = entry_variant as Dictionary
			if str(entry.get("type", "")) == "slot":
				refinery_list.add_child(_make_refinery_slot_card(entry))
			else:
				refinery_list.add_child(_make_refinery_unlock_card(entry))
		return

	if _refinery_active_category == "solution":
		if not game_state.has_method("is_synth_unlocked") or not bool(game_state.call("is_synth_unlocked")):
			if refinery_feedback != null:
				refinery_feedback.text = "Requires Synthesis."
			return

		var visible_solution_unlock_ids: Array = []
		if game_state.has_method("get_visible_solution_unlock_ids"):
			visible_solution_unlock_ids = game_state.call("get_visible_solution_unlock_ids")

		if not visible_solution_unlock_ids.is_empty():
			var recipe_header := Label.new()
			recipe_header.text = "Solution Unlock"
			refinery_list.add_child(recipe_header)

			for recipe_id_variant in visible_solution_unlock_ids:
				var recipe_id := str(recipe_id_variant)
				refinery_list.add_child(_make_synth_recipe_unlock_card(recipe_id))

		var spacer2 := HSeparator.new()
		refinery_list.add_child(spacer2)

		if game_state.has_method("get_synth_ui_entries"):
			var synth_entries = game_state.call("get_synth_ui_entries")
			if typeof(synth_entries) == TYPE_ARRAY:
				for entry_variant in synth_entries:
					var entry: Dictionary = entry_variant as Dictionary
					if str(entry.get("type", "")) == "slot":
						refinery_list.add_child(_make_synthesis_slot_card(entry))
					else:
						refinery_list.add_child(_make_synth_unlock_card(entry))
				return

		var placeholder := Label.new()
		placeholder.text = "Synthesis logic not wired yet."
		refinery_list.add_child(placeholder)


func _make_refinery_progress_bar(pct: int, width: int = 10) -> String:
	var clamped := clampi(pct, 0, 100)
	var filled := int(round((float(clamped) / 100.0) * width))
	filled = clampi(filled, 0, width)
	return "█".repeat(filled) + "░".repeat(width - filled)


func _refinery_recipe_cycle_label(recipe_name: String) -> String:
	if recipe_name == "" or recipe_name == "Idle":
		return "Set Recipe"
	return "Change"


func _make_refinery_card_shell() -> PanelContainer:
	var tm := ThemeManager
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("border")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	return card


func _make_refinery_slot_card(entry: Dictionary) -> Control:
	return _make_slot_row(entry, "compound")


func _make_slot_row(entry: Dictionary, category: String) -> Control:
	var tm := ThemeManager
	var slot_number: int  = int(entry.get("slot_number", 0))
	var recipe_name: String = str(entry.get("recipe_name", "Idle"))
	var is_idle: bool      = recipe_name == "" or recipe_name == "Idle"
	var pct: int           = int(entry.get("progress_pct", 0))
	var completed: int     = int(entry.get("completed_count", 0))
	var repeat_on: bool    = bool(entry.get("repeat_enabled", true))

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("border")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	row.add_child(vbox)

	# ── Top line: slot label + recipe name + completed badge ──────────────
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)

	var slot_lbl := Label.new()
	slot_lbl.text = "Slot %d" % slot_number
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	top.add_child(slot_lbl)

	var recipe_lbl := Label.new()
	recipe_lbl.text = "Idle" if is_idle else recipe_name
	recipe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_lbl.add_theme_font_size_override("font_size", 13)
	recipe_lbl.add_theme_color_override("font_color",
		tm.c("text_muted") if is_idle else tm.c("text_primary"))
	top.add_child(recipe_lbl)

	if not is_idle:
		if repeat_on:
			var auto_lbl := Label.new()
			auto_lbl.text = "AUTO"
			auto_lbl.add_theme_font_size_override("font_size", 10)
			auto_lbl.add_theme_color_override("font_color", tm.c("accent_dim"))
			top.add_child(auto_lbl)

		if completed > 0:
			var badge := Label.new()
			badge.text = "×%d" % completed
			badge.add_theme_font_size_override("font_size", 11)
			badge.add_theme_color_override("font_color", tm.c("text_muted"))
			top.add_child(badge)

	# ── Progress bar (only when active) ──────────────────────────────────
	if not is_idle:
		var track := PanelContainer.new()
		var sb_t := StyleBoxFlat.new()
		sb_t.bg_color = tm.c("bg_deep")
		sb_t.set_corner_radius_all(3)
		sb_t.content_margin_top    = 0
		sb_t.content_margin_bottom = 0
		track.add_theme_stylebox_override("panel", sb_t)
		track.custom_minimum_size = Vector2(0, 5)
		vbox.add_child(track)

		var fill := Control.new()
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.custom_minimum_size   = Vector2(0, 5)
		var fill_pct := pct
		fill.draw.connect(func():
			var w := fill.size.x * clampf(float(fill_pct) / 100.0, 0.0, 1.0)
			if w > 0:
				var sb_f := StyleBoxFlat.new()
				sb_f.bg_color = tm.c("accent") if fill_pct >= 100 else tm.c("accent_dim")
				sb_f.set_corner_radius_all(3)
				fill.draw_style_box(sb_f, Rect2(0, 0, w, fill.size.y))
		)
		track.add_child(fill)

	# ── Tap row to open slot popup ────────────────────────────────────────
	row.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) or \
		   (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
			_show_slot_popup(entry.duplicate(true), category)
			get_viewport().set_input_as_handled()
	)

	return row
func _make_refinery_recipe_unlock_card(recipe_id: String) -> Control:
	var tm := ThemeManager
	var card := _make_refinery_card_shell()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var compound_defs: Dictionary = game_state.get("compound_defs")
	var recipe_def: Dictionary = compound_defs.get(recipe_id, {}) as Dictionary
	var recipe_name := str(recipe_def.get("name", recipe_id))

	var hdr_row := HBoxContainer.new()
	vbox.add_child(hdr_row)

	var name_lbl := Label.new()
	name_lbl.text = recipe_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	hdr_row.add_child(name_lbl)

	var cost_value := -1
	if game_state.has_method("get_compound_unlock_cost"):
		cost_value = int(game_state.call("get_compound_unlock_cost", recipe_id))

	var cost_lbl := Label.new()
	cost_lbl.text = "%s nutrients" % _fmt_int(cost_value) if cost_value > 0 else "—"
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	hdr_row.add_child(cost_lbl)

	var check: Dictionary = {}
	var can_unlock := false
	if game_state.has_method("can_unlock_compound_recipe"):
		check = game_state.call("can_unlock_compound_recipe", recipe_id) as Dictionary
		can_unlock = bool(check.get("ok", false))

	var reason := str(check.get("reason", ""))
	if reason != "" and not can_unlock and reason != "Already unlocked.":
		var reason_lbl := Label.new()
		reason_lbl.text = reason
		reason_lbl.add_theme_font_size_override("font_size", 11)
		reason_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(reason_lbl)

	var btn := Button.new()
	btn.text = "Unlock Recipe"
	btn.disabled = not can_unlock
	btn.pressed.connect(func() -> void: _on_refinery_unlock_compound_pressed(recipe_id))
	_theme_action_button(btn)
	vbox.add_child(btn)

	return card


func _make_synthesis_slot_card(entry: Dictionary) -> Control:
	return _make_slot_row(entry, "solution")


func _make_synth_unlock_card(entry: Dictionary) -> Control:
	var tm := ThemeManager
	var card := _make_refinery_card_shell()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var name_lbl := Label.new()
	name_lbl.text = "Synth Slot %d" % int(entry.get("slot_number", 0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	hdr.add_child(name_lbl)
	var cost_lbl := Label.new()
	cost_lbl.text = "%s nutrients" % _fmt_int(int(entry.get("cost", 0)))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	hdr.add_child(cost_lbl)

	var reason := str(entry.get("status", ""))
	if reason != "":
		var reason_lbl := Label.new()
		reason_lbl.text = reason
		reason_lbl.add_theme_font_size_override("font_size", 11)
		reason_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(reason_lbl)

	var btn := Button.new()
	btn.text = "Unlock Slot"
	btn.disabled = not bool(entry.get("can_unlock", false))
	var slot_number: int = int(entry.get("slot_number", 0))
	btn.pressed.connect(func(): _on_synth_unlock_slot_pressed(slot_number))
	_theme_action_button(btn)
	vbox.add_child(btn)
	return card


func _make_refinery_unlock_card(entry: Dictionary) -> Control:
	var tm := ThemeManager
	var card := _make_refinery_card_shell()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var name_lbl := Label.new()
	name_lbl.text = "Refinery Slot %d" % int(entry.get("slot_number", 0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	hdr.add_child(name_lbl)
	var cost_lbl := Label.new()
	cost_lbl.text = "%s nutrients" % _fmt_int(int(entry.get("cost", 0)))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	hdr.add_child(cost_lbl)

	var reason := str(entry.get("status", ""))
	if reason != "":
		var reason_lbl := Label.new()
		reason_lbl.text = reason
		reason_lbl.add_theme_font_size_override("font_size", 11)
		reason_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(reason_lbl)

	var btn := Button.new()
	btn.text = "Unlock Slot"
	btn.disabled = not bool(entry.get("can_unlock", false))
	var slot_number: int = int(entry.get("slot_number", 0))
	btn.pressed.connect(func(): _on_refinery_unlock_slot_pressed(slot_number))
	_theme_action_button(btn)
	vbox.add_child(btn)
	return card


func _make_synth_recipe_unlock_card(recipe_id: String) -> Control:
	var tm := ThemeManager
	var card := _make_refinery_card_shell()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var solution_defs: Dictionary = game_state.get("solution_defs")
	var recipe_def: Dictionary = solution_defs.get(recipe_id, {}) as Dictionary
	var recipe_name := str(recipe_def.get("name", recipe_id))

	var hdr_row := HBoxContainer.new()
	vbox.add_child(hdr_row)

	var name_lbl := Label.new()
	name_lbl.text = recipe_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	hdr_row.add_child(name_lbl)

	var cost_value := -1
	if game_state.has_method("get_solution_unlock_cost"):
		cost_value = int(game_state.call("get_solution_unlock_cost", recipe_id))

	var cost_lbl := Label.new()
	cost_lbl.text = "%s nutrients" % _fmt_int(cost_value) if cost_value > 0 else "—"
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	hdr_row.add_child(cost_lbl)

	var check: Dictionary = {}
	var can_unlock := false
	if game_state.has_method("can_unlock_solution_recipe"):
		check = game_state.call("can_unlock_solution_recipe", recipe_id) as Dictionary
		can_unlock = bool(check.get("ok", false))

	var reason := str(check.get("reason", ""))
	if reason != "" and not can_unlock and reason != "Already unlocked.":
		var reason_lbl := Label.new()
		reason_lbl.text = reason
		reason_lbl.add_theme_font_size_override("font_size", 11)
		reason_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		vbox.add_child(reason_lbl)

	var btn := Button.new()
	btn.text = "Unlock Recipe"
	btn.disabled = not can_unlock
	btn.pressed.connect(func() -> void: _on_refinery_unlock_solution_pressed(recipe_id))
	_theme_action_button(btn)
	vbox.add_child(btn)
	return card


func _on_refinery_cycle_recipe_pressed(slot_number: int) -> void:
	_show_recipe_picker_popup(slot_number, "compound")



func _on_refinery_toggle_repeat_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("toggle_refinery_repeat"):
		return
	var enabled: bool = bool(game_state.call("toggle_refinery_repeat", slot_number))
	if refinery_feedback != null:
		refinery_feedback.text = "Slot %s repeat: %s" % [slot_number, "On" if enabled else "Off"]
	_refresh_refinery_panel()


func _on_refinery_clear_recipe_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("clear_refinery_recipe"):
		return
	game_state.call("clear_refinery_recipe", slot_number)
	if refinery_feedback != null:
		refinery_feedback.text = "Cleared Slot %s." % slot_number
	_refresh_refinery_panel()


func _on_refinery_unlock_compound_pressed(recipe_id: String) -> void:
	if game_state == null or not game_state.has_method("unlock_compound_recipe"):
		return

	var result = game_state.call("unlock_compound_recipe", recipe_id)
	var ok := false
	var reason := "Unable to unlock recipe."

	if typeof(result) == TYPE_DICTIONARY:
		ok = bool((result as Dictionary).get("ok", false))
		reason = str((result as Dictionary).get("reason", reason))

	if refinery_feedback != null:
		if ok:
			var compound_defs: Dictionary = game_state.get("compound_defs")
			var recipe_def: Dictionary = compound_defs.get(recipe_id, {}) as Dictionary
			var recipe_name := str(recipe_def.get("name", recipe_id))
			refinery_feedback.text = "Unlocked %s." % recipe_name
		else:
			refinery_feedback.text = reason

	_refresh_currency_ui()
	_refresh_refinery_panel()

	if _open_panel == digest_panel:
		_refresh_digest_panel()


func _on_refinery_unlock_solution_pressed(recipe_id: String) -> void:
	if game_state == null or not game_state.has_method("unlock_solution_recipe"):
		return

	var result = game_state.call("unlock_solution_recipe", recipe_id)
	var ok := false
	var reason := "Unable to unlock recipe."

	if typeof(result) == TYPE_DICTIONARY:
		ok = bool((result as Dictionary).get("ok", false))
		reason = str((result as Dictionary).get("reason", reason))

	if refinery_feedback != null:
		if ok:
			var solution_defs: Dictionary = game_state.get("solution_defs")
			var recipe_def: Dictionary = solution_defs.get(recipe_id, {}) as Dictionary
			var recipe_name := str(recipe_def.get("name", recipe_id))
			refinery_feedback.text = "Unlocked %s." % recipe_name
		else:
			refinery_feedback.text = reason

	_refresh_currency_ui()
	_refresh_refinery_panel()

	if _open_panel == digest_panel:
		_refresh_digest_panel()


func _on_synthesis_cycle_recipe_pressed(slot_number: int) -> void:
	_show_recipe_picker_popup(slot_number, "solution")


func _show_slot_popup(entry: Dictionary, category: String) -> void:
	# Slot management popup: shows current recipe + progress, Auto toggle, Clear, Change Recipe
	_close_recipe_picker_popup()
	if game_state == null:
		return

	var vp := get_viewport_rect().size
	var tm := ThemeManager
	var slot_number: int   = int(entry.get("slot_number", 0))
	var recipe_name: String = str(entry.get("recipe_name", "Idle"))
	var is_idle: bool       = recipe_name == "" or recipe_name == "Idle"
	var pct: int            = int(entry.get("progress_pct", 0))
	var repeat_on: bool     = bool(entry.get("repeat_enabled", true))
	var completed: int      = int(entry.get("completed_count", 0))
	var is_compound: bool   = category == "compound"

	_recipe_popup_layer = CanvasLayer.new()
	_recipe_popup_layer.layer = 128
	add_child(_recipe_popup_layer)

	_recipe_popup_dimmer = ColorRect.new()
	_recipe_popup_dimmer.size     = vp
	_recipe_popup_dimmer.position = Vector2.ZERO
	_recipe_popup_dimmer.color    = Color(0, 0, 0, 0.55)
	_recipe_popup_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_recipe_popup_dimmer.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) or \
		   (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
			_close_recipe_picker_popup()
			get_viewport().set_input_as_handled()
	)
	_recipe_popup_layer.add_child(_recipe_popup_dimmer)

	var popup := PanelContainer.new()
	popup.z_index = 11
	popup.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("bark_stripe")
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(16)
	sb.content_margin_left   = 16
	sb.content_margin_right  = 16
	sb.content_margin_top    = 14
	sb.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", sb)
	_recipe_popup_layer.add_child(popup)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	popup.add_child(outer)

	# Header row
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)
	var title := Label.new()
	title.text = "%s Slot %d" % ["Compound" if is_compound else "Synth", slot_number]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", tm.c("accent"))
	hdr.add_child(title)
	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.draw.connect(func():
		var col: Color = tm.c("text_muted")
		var cx2 := close_btn.size.x * 0.5
		var cy2 := close_btn.size.y * 0.5
		var r := 5.0
		close_btn.draw_line(Vector2(cx2-r, cy2-r), Vector2(cx2+r, cy2+r), col, 1.5, true)
		close_btn.draw_line(Vector2(cx2+r, cy2-r), Vector2(cx2-r, cy2+r), col, 1.5, true)
	)
	close_btn.pressed.connect(_close_recipe_picker_popup)
	hdr.add_child(close_btn)

	# Divider
	var div := HSeparator.new()
	var sb_div := StyleBoxFlat.new()
	sb_div.bg_color = tm.c("border")
	div.add_theme_stylebox_override("separator", sb_div)
	outer.add_child(div)

	# Current recipe + progress
	var recipe_row := HBoxContainer.new()
	outer.add_child(recipe_row)
	var recipe_lbl := Label.new()
	recipe_lbl.text = "Idle" if is_idle else recipe_name
	recipe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_lbl.add_theme_font_size_override("font_size", 14)
	recipe_lbl.add_theme_color_override("font_color",
		tm.c("text_muted") if is_idle else tm.c("text_primary"))
	recipe_row.add_child(recipe_lbl)
	if completed > 0:
		var badge := Label.new()
		badge.text = "×%d" % completed
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", tm.c("text_muted"))
		recipe_row.add_child(badge)

	if not is_idle:
		# Progress bar
		var track := PanelContainer.new()
		var sb_t := StyleBoxFlat.new()
		sb_t.bg_color = tm.c("bg_deep")
		sb_t.set_corner_radius_all(4)
		track.add_theme_stylebox_override("panel", sb_t)
		track.custom_minimum_size = Vector2(0, 8)
		outer.add_child(track)
		var fill := Control.new()
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.custom_minimum_size   = Vector2(0, 8)
		var fill_pct := pct
		fill.draw.connect(func():
			var w := fill.size.x * clampf(float(fill_pct) / 100.0, 0.0, 1.0)
			if w > 0:
				var sb_f := StyleBoxFlat.new()
				sb_f.bg_color = tm.c("accent") if fill_pct >= 100 else tm.c("accent_dim")
				sb_f.set_corner_radius_all(4)
				fill.draw_style_box(sb_f, Rect2(0, 0, w, fill.size.y))
		)
		track.add_child(fill)

		# I/O summary
		var input_lbl := Label.new()
		input_lbl.text = "In: %s" % str(entry.get("input_summary", "—"))
		input_lbl.add_theme_font_size_override("font_size", 11)
		input_lbl.add_theme_color_override("font_color", tm.c("text_secondary"))
		outer.add_child(input_lbl)
		var output_lbl := Label.new()
		output_lbl.text = "Out: %s" % str(entry.get("output_summary", "—"))
		output_lbl.add_theme_font_size_override("font_size", 11)
		output_lbl.add_theme_color_override("font_color", tm.c("accent_dim"))
		outer.add_child(output_lbl)

		# Status
		var status_lbl := Label.new()
		status_lbl.text = "%s  %d%%" % [str(entry.get("status", "Idle")), pct]
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		outer.add_child(status_lbl)

	# Divider
	var div2 := HSeparator.new()
	div2.add_theme_stylebox_override("separator", sb_div)
	outer.add_child(div2)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	outer.add_child(btn_row)

	var change_btn := Button.new()
	change_btn.text = "Set Recipe" if is_idle else "Change"
	change_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_theme_action_button(change_btn)
	change_btn.pressed.connect(func():
		_close_recipe_picker_popup()
		_show_recipe_picker_popup(slot_number, category)
	)
	btn_row.add_child(change_btn)

	if not is_idle:
		var repeat_btn := Button.new()
		repeat_btn.text = "Auto: %s" % ("ON" if repeat_on else "OFF")
		repeat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_theme_action_button(repeat_btn)
		if repeat_on:
			repeat_btn.add_theme_color_override("font_color", tm.c("accent"))
		repeat_btn.pressed.connect(func():
			if is_compound:
				game_state.call("toggle_refinery_repeat", slot_number)
			else:
				game_state.call("toggle_synth_repeat", slot_number)
			_close_recipe_picker_popup()
			_refresh_refinery_panel()
		)
		btn_row.add_child(repeat_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_theme_action_button(clear_btn)
		clear_btn.pressed.connect(func():
			if is_compound:
				game_state.call("clear_refinery_recipe", slot_number)
			else:
				game_state.call("clear_synth_recipe", slot_number)
			_close_recipe_picker_popup()
			_refresh_refinery_panel()
		)
		btn_row.add_child(clear_btn)

	_recipe_popup = popup
	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.position = Vector2(
			(vp.x - popup.size.x) * 0.5,
			(vp.y - popup.size.y) * 0.5
		)


func _show_recipe_picker_popup(slot_number: int, category: String) -> void:
	_close_recipe_picker_popup()
	if game_state == null:
		return

	var vp := get_viewport_rect().size
	var tm := ThemeManager

	# Gather recipe options
	var recipe_ids: Array = []
	var defs: Dictionary = {}
	if category == "compound":
		recipe_ids = game_state.call("get_available_compound_recipe_ids")
		defs = game_state.get("compound_defs") as Dictionary
	else:
		recipe_ids = game_state.call("get_available_solution_recipe_ids")
		defs = game_state.get("solution_defs") as Dictionary

	# ── CanvasLayer ───────────────────────────────────────────────────────
	_recipe_popup_layer = CanvasLayer.new()
	_recipe_popup_layer.layer = 128
	add_child(_recipe_popup_layer)

	# ── Dimmer ────────────────────────────────────────────────────────────
	_recipe_popup_dimmer = ColorRect.new()
	_recipe_popup_dimmer.size     = vp
	_recipe_popup_dimmer.position = Vector2.ZERO
	_recipe_popup_dimmer.color    = Color(0, 0, 0, 0.55)
	_recipe_popup_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_recipe_popup_dimmer.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) or \
		   (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
			_close_recipe_picker_popup()
			get_viewport().set_input_as_handled()
	)
	_recipe_popup_layer.add_child(_recipe_popup_dimmer)

	# ── Popup card ────────────────────────────────────────────────────────
	var popup := PanelContainer.new()
	popup.z_index = 11
	popup.custom_minimum_size = Vector2(340, 0)

	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("bark_stripe")
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(16)
	sb.content_margin_left   = 16
	sb.content_margin_right  = 16
	sb.content_margin_top    = 14
	sb.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", sb)
	_recipe_popup_layer.add_child(popup)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	popup.add_child(outer)

	# Header
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)

	var title := Label.new()
	var label_text := "Compound" if category == "compound" else "Solution"
	title.text = "Set Recipe — Slot %d" % slot_number
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", tm.c("accent"))
	hdr.add_child(title)

	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.draw.connect(func():
		var col: Color = tm.c("text_muted")
		var cx2 := close_btn.size.x * 0.5
		var cy2 := close_btn.size.y * 0.5
		var r := 5.0
		close_btn.draw_line(Vector2(cx2-r, cy2-r), Vector2(cx2+r, cy2+r), col, 1.5, true)
		close_btn.draw_line(Vector2(cx2+r, cy2-r), Vector2(cx2-r, cy2+r), col, 1.5, true)
	)
	close_btn.pressed.connect(_close_recipe_picker_popup)
	hdr.add_child(close_btn)

	# Divider
	var div := HSeparator.new()
	var sb_div := StyleBoxFlat.new()
	sb_div.bg_color = tm.c("border")
	div.add_theme_stylebox_override("separator", sb_div)
	outer.add_child(div)

	# Recipe list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(float(recipe_ids.size()) * 72.0, 400.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if recipe_ids.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No %s recipes unlocked yet." % label_text.to_lower()
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		list.add_child(empty_lbl)
	else:
		for id_v in recipe_ids:
			var rid: String = str(id_v)
			var def: Dictionary = defs.get(rid, {}) as Dictionary
			var rname: String = str(def.get("name", rid))
			var inputs: Array = def.get("inputs", []) as Array
			var output_qty: int = int(def.get("output_qty", 1))
			var output_name: String = str(def.get("output_name", rname))

			# Build input summary
			var input_parts: Array = []
			for inp_v in inputs:
				var inp: Dictionary = inp_v as Dictionary
				var iname: String = _pretty_res(str(inp.get("id", "")))
				var iqty: int = int(inp.get("qty", 0))
				input_parts.append("%d %s" % [iqty, iname])
			var input_str: String = " + ".join(input_parts) if not input_parts.is_empty() else "—"

			# Row card
			var row_card := PanelContainer.new()
			row_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sb_row := StyleBoxFlat.new()
			sb_row.bg_color     = tm.c("bg_row")
			sb_row.border_color = tm.c("border")
			sb_row.set_border_width_all(1)
			sb_row.set_corner_radius_all(8)
			sb_row.content_margin_left   = 10
			sb_row.content_margin_right  = 10
			sb_row.content_margin_top    = 8
			sb_row.content_margin_bottom = 8
			row_card.add_theme_stylebox_override("panel", sb_row)
			row_card.mouse_filter = Control.MOUSE_FILTER_STOP

			var row_vbox := VBoxContainer.new()
			row_vbox.add_theme_constant_override("separation", 3)
			row_card.add_child(row_vbox)

			var row_hdr := HBoxContainer.new()
			row_vbox.add_child(row_hdr)

			var name_lbl := Label.new()
			name_lbl.text = rname
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
			row_hdr.add_child(name_lbl)

			var output_lbl := Label.new()
			output_lbl.text = "→ %d %s" % [output_qty, output_name]
			output_lbl.add_theme_font_size_override("font_size", 11)
			output_lbl.add_theme_color_override("font_color", tm.c("accent_dim"))
			row_hdr.add_child(output_lbl)

			var input_lbl := Label.new()
			input_lbl.text = input_str
			input_lbl.add_theme_font_size_override("font_size", 11)
			input_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
			row_vbox.add_child(input_lbl)

			# Tap to select
			var capture_rid := rid
			var capture_cat := category
			var capture_slot := slot_number
			row_card.gui_input.connect(func(ev: InputEvent):
				if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) or \
				   (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
					_on_recipe_picker_selected(capture_slot, capture_rid, capture_cat)
					get_viewport().set_input_as_handled()
			)

			list.add_child(row_card)

	_recipe_popup = popup

	# Center after layout
	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.position = Vector2(
			(vp.x - popup.size.x) * 0.5,
			(vp.y - popup.size.y) * 0.5
		)


func _close_recipe_picker_popup() -> void:
	if _recipe_popup_layer != null and is_instance_valid(_recipe_popup_layer):
		_recipe_popup_layer.queue_free()
		_recipe_popup_layer = null
	_recipe_popup        = null
	_recipe_popup_dimmer = null
	_popup_closed_this_press = true


func _on_recipe_picker_selected(slot_number: int, recipe_id: String, category: String) -> void:
	_close_recipe_picker_popup()
	if game_state == null:
		return
	if category == "compound":
		game_state.call("assign_refinery_recipe", slot_number, recipe_id)
	else:
		game_state.call("assign_synth_recipe", slot_number, recipe_id)
	_refresh_refinery_panel()


func _on_synthesis_toggle_repeat_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("toggle_synth_repeat"):
		return

	var enabled: bool = bool(game_state.call("toggle_synth_repeat", slot_number))

	if refinery_feedback != null:
		refinery_feedback.text = "Synthesis slot %s repeat: %s" % [slot_number, "On" if enabled else "Off"]
	_refresh_refinery_panel()


func _on_synthesis_clear_recipe_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("clear_synth_recipe"):
		return

	game_state.call("clear_synth_recipe", slot_number)

	if refinery_feedback != null:
		refinery_feedback.text = "Cleared synthesis slot %s." % slot_number
	_refresh_refinery_panel()


func _on_refinery_unlock_slot_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("unlock_refinery_slot"):
		return
	var result = game_state.call("unlock_refinery_slot", slot_number)
	if refinery_feedback != null:
		if typeof(result) == TYPE_DICTIONARY and bool((result as Dictionary).get("ok", false)):
			refinery_feedback.text = "Unlocked Refinery Slot %s" % slot_number
		else:
			refinery_feedback.text = str((result as Dictionary).get("reason", "Unable to unlock slot."))
	_refresh_currency_ui()
	_refresh_refinery_panel()

func _on_synth_unlock_slot_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("unlock_synth_slot"):
		return

	var result = game_state.call("unlock_synth_slot", slot_number)

	if refinery_feedback != null:
		if typeof(result) == TYPE_DICTIONARY and bool((result as Dictionary).get("ok", false)):
			refinery_feedback.text = "Unlocked Synthesis Slot %s" % slot_number
		else:
			refinery_feedback.text = str((result as Dictionary).get("reason", "Unable to unlock slot."))

	_refresh_currency_ui()
	_refresh_refinery_panel()


# ---------------- SettingsPanel ----------------

func _bind_settings_panel() -> void:
	var root_box: VBoxContainer = settings_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if root_box == null:
		return
	for child in root_box.get_children():
		child.queue_free()

	# Ensure fill
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical       = Control.SIZE_EXPAND_FILL
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)

	var tm := ThemeManager

	# ── Header ────────────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "Settings"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", tm.c("accent"))
	root_box.add_child(header)

	# ── Theme section ─────────────────────────────────────────────────────
	var theme_header := Label.new()
	theme_header.text = "Theme"
	theme_header.add_theme_font_size_override("font_size", 12)
	theme_header.add_theme_color_override("font_color", tm.c("text_muted"))
	root_box.add_child(theme_header)

	var themes: Array = ThemeManager.get_theme_list()
	for theme_info_v in themes:
		var theme_info: Dictionary = theme_info_v as Dictionary
		var tid: String   = str(theme_info.get("id", ""))
		var tname: String = str(theme_info.get("name", tid))
		var unlocked: bool = bool(theme_info.get("unlocked", false))
		var is_active: bool = tid == ThemeManager.active_id()

		var row := _make_settings_theme_row(tid, tname, unlocked, is_active)
		root_box.add_child(row)

	# ── Divider ───────────────────────────────────────────────────────────
	var div := HSeparator.new()
	var sb_div := StyleBoxFlat.new()
	sb_div.bg_color = tm.c("border")
	div.add_theme_stylebox_override("separator", sb_div)
	root_box.add_child(div)

	# ── Debug: rate multiplier ────────────────────────────────────────────
	var debug_header := Label.new()
	debug_header.text = "Debug"
	debug_header.add_theme_font_size_override("font_size", 12)
	debug_header.add_theme_color_override("font_color", tm.c("text_muted"))
	root_box.add_child(debug_header)

	var rate_row := HBoxContainer.new()
	rate_row.add_theme_constant_override("separation", 10)
	root_box.add_child(rate_row)

	var rate_lbl := Label.new()
	rate_lbl.text = "Rate ×"
	rate_lbl.add_theme_font_size_override("font_size", 13)
	rate_lbl.add_theme_color_override("font_color", tm.c("text_secondary"))
	rate_row.add_child(rate_lbl)

	var rate_slider := HSlider.new()
	rate_slider.min_value = 1.0
	rate_slider.max_value = 100.0
	rate_slider.step = 1.0
	var cur_mult: float = 1.0
	if game_state != null and "debug_rate_mult" in game_state:
		cur_mult = float(game_state.get("debug_rate_mult"))
	rate_slider.value = cur_mult
	rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_row.add_child(rate_slider)

	var rate_val_lbl := Label.new()
	rate_val_lbl.name = "RateValLbl"
	rate_val_lbl.text = "×%d" % int(rate_slider.value)
	rate_val_lbl.custom_minimum_size = Vector2(40, 0)
	rate_val_lbl.add_theme_font_size_override("font_size", 13)
	rate_val_lbl.add_theme_color_override("font_color", tm.c("accent"))
	rate_row.add_child(rate_val_lbl)

	rate_slider.value_changed.connect(func(v: float):
		if game_state != null:
			game_state.set("debug_rate_mult", v)
		rate_val_lbl.text = "×%d" % int(v)
	)

	var div2 := HSeparator.new()
	var sb_div2 := StyleBoxFlat.new()
	sb_div2.bg_color = tm.c("border")
	div2.add_theme_stylebox_override("separator", sb_div2)
	root_box.add_child(div2)

	# ── Save / load section ───────────────────────────────────────────────
	var save_header := Label.new()
	save_header.text = "Save data"
	save_header.add_theme_font_size_override("font_size", 12)
	save_header.add_theme_color_override("font_color", tm.c("text_muted"))
	root_box.add_child(save_header)

	settings_feedback = Label.new()
	settings_feedback.name = "SettingsFeedback"
	settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_feedback.add_theme_font_size_override("font_size", 13)
	settings_feedback.add_theme_color_override("font_color", tm.c("text_muted"))
	settings_feedback.text = "Manage save data for this run."
	root_box.add_child(settings_feedback)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	root_box.add_child(btn_row)

	settings_btn_save = Button.new()
	settings_btn_save.text = "Save Now"
	settings_btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn_save.pressed.connect(_on_settings_save_pressed)
	_theme_action_button(settings_btn_save)
	btn_row.add_child(settings_btn_save)

	settings_btn_load = Button.new()
	settings_btn_load.text = "Load Save"
	settings_btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn_load.pressed.connect(_on_settings_load_pressed)
	_theme_action_button(settings_btn_load)
	btn_row.add_child(settings_btn_load)

	settings_btn_new_game = Button.new()
	settings_btn_new_game.text = "New Game"
	settings_btn_new_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn_new_game.pressed.connect(_on_settings_new_game_pressed)
	_theme_action_button(settings_btn_new_game)
	root_box.add_child(settings_btn_new_game)

	_refresh_settings_panel()


func _make_settings_theme_row(tid: String, tname: String, unlocked: bool, is_active: bool) -> Control:
	var tm := ThemeManager

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP if unlocked else Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	if is_active:
		sb.bg_color     = tm.c("accent_glow")
		sb.border_color = tm.c("accent")
	else:
		sb.bg_color     = tm.c("bg_panel")
		sb.border_color = tm.c("border")
	row.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# Color swatch
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.color = _theme_swatch_color(tid)
	var swatch_wrap := Control.new()
	swatch_wrap.custom_minimum_size = Vector2(16, 16)
	hbox.add_child(swatch)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = tname
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	var name_col: Color
	if is_active:
		name_col = tm.c("accent")
	elif unlocked:
		name_col = tm.c("text_primary")
	else:
		name_col = tm.c("text_muted")
	name_lbl.add_theme_color_override("font_color", name_col)
	hbox.add_child(name_lbl)

	# Status label
	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 11)
	if is_active:
		status_lbl.text = "Active"
		status_lbl.add_theme_color_override("font_color", tm.c("accent"))
	elif not unlocked:
		status_lbl.text = "Locked"
		status_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	else:
		status_lbl.text = ""
	hbox.add_child(status_lbl)

	# Tap to switch
	if unlocked and not is_active:
		row.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_settings_theme_selected(tid)
			elif event is InputEventScreenTouch and event.pressed:
				_on_settings_theme_selected(tid)
		)

	if not unlocked:
		row.modulate.a = 0.4

	return row


func _theme_swatch_color(tid: String) -> Color:
	match tid:
		"forest_green":    return Color(0.561, 0.812, 0.376)
		"mycelium_violet": return Color(0.690, 0.565, 0.941)
		"amber_spore":     return Color(0.878, 0.690, 0.314)
		"accessible_blue": return Color(0.376, 0.690, 0.973)
		_: return Color.WHITE


func _on_settings_theme_selected(tid: String) -> void:
	if ThemeManager.set_theme(tid):
		# Rebuild settings panel so active state updates
		_bind_settings_panel()
		if settings_feedback != null:
			settings_feedback.text = "Theme changed."


func _refresh_settings_panel() -> void:
	if settings_btn_load != null:
		var has_save := false
		if game_state != null and game_state.has_method("has_save_data"):
			has_save = bool(game_state.call("has_save_data"))
		settings_btn_load.disabled = not has_save

	if settings_btn_new_game != null:
		settings_btn_new_game.text = "Confirm New Game" if _settings_confirm_action == "new_game" else "New Game"

	if settings_feedback != null and settings_feedback.text == "":
		settings_feedback.text = "Manage save data for this run."


func _clear_settings_confirmation() -> void:
	_settings_confirm_action = ""
	_refresh_settings_panel()


func _handle_runtime_state_reload() -> void:
	_selected_node = null
	_selected_node_id = ""
	selection_ring.visible = false

	_register_root_transfer_positions()
	_setup_root_pulses()
	_setup_transfer_fx()

	_refresh_panel_access_ui()
	_refresh_currency_ui()
	_refresh_node_world_state()
	_refresh_digest_panel()
	_refresh_discoveries_panel()
	_refresh_refinery_panel()
	_refresh_settings_panel()

	_last_refinery_inventory_signature = _get_refinery_inventory_signature()
	_last_discovery_signature = _get_discovery_signature()


func _on_settings_save_pressed() -> void:
	_clear_settings_confirmation()

	if game_state == null or not game_state.has_method("save_game"):
		return

	var ok: bool = bool(game_state.call("save_game"))
	if settings_feedback != null:
		settings_feedback.text = "Game saved." if ok else "Save failed."
	_refresh_settings_panel()


func _on_settings_load_pressed() -> void:
	_clear_settings_confirmation()

	if game_state == null or not game_state.has_method("load_game"):
		return

	var ok: bool = bool(game_state.call("load_game"))
	if ok:
		_handle_runtime_state_reload()

	if settings_feedback != null:
		settings_feedback.text = "Save loaded." if ok else "No valid save found."
	_refresh_settings_panel()


func _on_settings_new_game_pressed() -> void:
	if _settings_confirm_action != "new_game":
		_settings_confirm_action = "new_game"
		if settings_feedback != null:
			settings_feedback.text = "Press New Game again to confirm. Current run progress will be erased."
		_refresh_settings_panel()
		return

	_clear_settings_confirmation()

	if game_state == null or not game_state.has_method("start_new_run"):
		return

	game_state.call("start_new_run")
	_handle_runtime_state_reload()

	if settings_feedback != null:
		settings_feedback.text = "Started a new game."
	_refresh_settings_panel()


# ---------------- NodePanel (Top Table) ----------------

func _bind_nodepanel_top_table() -> void:
	_build_nodepanel_layout()


func _build_nodepanel_layout() -> void:
	var tm := ThemeManager
	# Force NodePanel to fill its parent — scene may have stale baked size
	node_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	node_panel.offset_left   = 0
	node_panel.offset_right  = 0
	node_panel.offset_top    = 0
	node_panel.offset_bottom = 0

	# Also force MarginContainer to fill and clip
	var margin_c: Control = node_panel.find_child("MarginContainer", true, false) as Control
	if margin_c != null:
		margin_c.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin_c.clip_children = CanvasItem.CLIP_CHILDREN_ONLY

	# Find the scene VBoxContainer and wipe its children except the header row
	var scene_vbox: Control = node_panel.find_child("VBoxContainer", true, false) as Control
	if scene_vbox == null:
		return

	# Hide all existing scene children we're replacing
	for child in scene_vbox.get_children():
		var n := child.name
		if n != "Header row":
			child.visible = false

	# ── Icon + meta row ───────────────────────────────────────────────────
	# Icon moves to top-left, larger (78×78 = 52 * 1.5)
	var icon_row := HBoxContainer.new()
	icon_row.name = "NP_IconRow"
	icon_row.add_theme_constant_override("separation", 10)
	scene_vbox.add_child(icon_row)

	var np_icon_lpad := Control.new()
	np_icon_lpad.custom_minimum_size = Vector2(10, 0)
	icon_row.add_child(np_icon_lpad)
	_np_icon_ctrl = Control.new()
	_np_icon_ctrl.custom_minimum_size = Vector2(78, 78)   # +50%
	_np_icon_ctrl.draw.connect(_draw_node_icon_placeholder)
	icon_row.add_child(_np_icon_ctrl)

	var meta_col := VBoxContainer.new()
	meta_col.add_theme_constant_override("separation", 3)
	meta_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_row.add_child(meta_col)

	_np_meta_lbl = Label.new()
	_np_meta_lbl.add_theme_font_size_override("font_size", 9)   # -2px from 11
	_np_meta_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	meta_col.add_child(_np_meta_lbl)

	_np_status_lbl = Label.new()
	_np_status_lbl.add_theme_font_size_override("font_size", 9)  # -2px from 11
	_np_status_lbl.add_theme_color_override("font_color", tm.c("accent_dim"))
	meta_col.add_child(_np_status_lbl)

	# Node name padded + right-aligned (top row handled by scene "Header row")
	# Apply padding and right-align + reduced font to the scene node_title
	if node_title != null:
		node_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		node_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node_title.add_theme_font_size_override("font_size", 14)  # -2px from 16
		node_title.custom_minimum_size = Vector2(0, 0)

	# ── Resource section ──────────────────────────────────────────────────
	# Move Split/Rate/Stored closer to Resource (smaller column widths)
	const COL_SPLIT  := 52
	const COL_RATE   := 56
	const COL_STORED := 52

	var res_hdr := HBoxContainer.new()
	res_hdr.add_theme_constant_override("separation", 10)
	scene_vbox.add_child(res_hdr)

	var res_hdr_lpad := Control.new()
	res_hdr_lpad.custom_minimum_size = Vector2(10, 0)
	res_hdr.add_child(res_hdr_lpad)

	for data in [["Resource", 0], ["Split", COL_SPLIT], ["Rate", COL_RATE], ["Stored", COL_STORED]]:
		var hl := Label.new()
		hl.text = data[0]
		hl.add_theme_font_size_override("font_size", 14)  # +4px from 10
		hl.add_theme_color_override("font_color", tm.c("text_muted"))
		if int(data[1]) == 0:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			hl.custom_minimum_size   = Vector2(int(data[1]), 0)
			hl.size_flags_horizontal = Control.SIZE_SHRINK_END
			hl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		res_hdr.add_child(hl)
	# Right pad after Stored header to match data row right pad
	var res_hdr_rpad := Control.new()
	res_hdr_rpad.custom_minimum_size = Vector2(20, 0)
	res_hdr.add_child(res_hdr_rpad)

	_np_res_container = VBoxContainer.new()
	_np_res_container.name = "NP_ResContainer"
	_np_res_container.add_theme_constant_override("separation", 0)
	scene_vbox.add_child(_np_res_container)

	# ── Divider ───────────────────────────────────────────────────────────
	var div_ctrl := Control.new()
	div_ctrl.custom_minimum_size = Vector2(0, 1)
	div_ctrl.draw.connect(func():
		div_ctrl.draw_rect(Rect2(0, 0, div_ctrl.size.x, 1), tm.c("border"))
	)
	scene_vbox.add_child(div_ctrl)

	# ── Upgrade rows ──────────────────────────────────────────────────────
	_np_upgrade_rows.clear()
	var upg_box := VBoxContainer.new()
	upg_box.name = "NP_UpgradeBox"
	upg_box.add_theme_constant_override("separation", 5)
	scene_vbox.add_child(upg_box)

	const ICON_PATHS := {
		"yield":     "M12 4v8M9 7l3-3 3 3",
		"frequency": "M12 3a9 9 0 1 0 0.001 0 M12 8v4l3 3",
		"speed":     "M5 12h14M15 7l5 5-5 5",
		"capacity":  "M4 9h16v11H4z M9 9V7a3 3 0 0 1 6 0v2",
	}
	const UPG_KEYS := [
		["yield",     "yield_label",     "yield_level",     "yield_value",     "yield_cost",     "_on_upgrade_yield"],
		["frequency", "frequency_label", "frequency_level", "frequency_value", "frequency_cost", "_on_upgrade_frequency"],
		["speed",     "speed_label",     "speed_level",     "speed_value",     "speed_cost",     "_on_upgrade_travel"],
		["capacity",  "carry_label",     "carry_level",     "carry_value",     "carry_cost",     "_on_upgrade_carry"],
	]

	for upg_data in UPG_KEYS:
		var key: String     = upg_data[0]
		var handler: String = upg_data[5]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size   = Vector2(0, 60)   # height
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.clip_children = CanvasItem.CLIP_CHILDREN_ONLY

		# Icon with left padding
		var icon_pad := Control.new()
		icon_pad.custom_minimum_size = Vector2(10, 0)
		row.add_child(icon_pad)
		var icon_box := Control.new()
		icon_box.custom_minimum_size = Vector2(42, 42)
		var icon_path: String = ICON_PATHS.get(key, "")
		icon_box.draw.connect(_draw_upg_icon.bind(icon_box, icon_path))
		row.add_child(icon_box)

		# Name + level + value (all on left, stacked)
		var name_col := VBoxContainer.new()
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.add_theme_constant_override("separation", 1)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
		name_col.add_child(name_lbl)
		var lv_lbl := Label.new()
		lv_lbl.add_theme_font_size_override("font_size", 10)
		lv_lbl.add_theme_color_override("font_color", tm.c("text_muted"))
		name_col.add_child(lv_lbl)
		# Value sits under level on the left
		var val_lbl := Label.new()
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", tm.c("accent_dim"))
		name_col.add_child(val_lbl)
		row.add_child(name_col)

		# Upgrade button — right side, fixed width
		var btn := Button.new()
		btn.custom_minimum_size   = Vector2(100, 28)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(Callable(self, handler))
		btn.clip_text = true
		row.add_child(btn)
		# Right padding after button
		var btn_pad := Control.new()
		btn_pad.custom_minimum_size = Vector2(20, 0)
		row.add_child(btn_pad)

		upg_box.add_child(row)
		_np_upgrade_rows.append({
			"name_lbl": name_lbl,
			"lv_lbl":   lv_lbl,
			"val_lbl":  val_lbl,
			"btn":      btn,
			"label_key": upg_data[1],
			"level_key": upg_data[2],
			"value_key": upg_data[3],
			"cost_key":  upg_data[4],
		})

	# ── No production footer (removed per design) ─────────────────────────
	prod_value = null


func _draw_node_icon_placeholder() -> void:
	if _np_icon_ctrl == null:
		return
	var tm := ThemeManager
	var cx := _np_icon_ctrl.size.x * 0.5
	var cy := _np_icon_ctrl.size.y * 0.5
	var r  := minf(cx, cy) - 2.0
	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("border")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	_np_icon_ctrl.draw_style_box(sb, Rect2(0, 0, _np_icon_ctrl.size.x, _np_icon_ctrl.size.y))
	_np_icon_ctrl.draw_arc(Vector2(cx, cy), r * 0.55, 0, TAU, 32, tm.c("border"), 1.0, true)
	_np_icon_ctrl.draw_circle(Vector2(cx, cy), r * 0.18, tm.c("accent_dim"))
	for i in range(6):
		var angle := float(i) * TAU / 6.0
		var inner := Vector2(cos(angle), sin(angle)) * r * 0.55
		var outer_v := Vector2(cos(angle), sin(angle)) * r * 0.8
		_np_icon_ctrl.draw_line(Vector2(cx, cy) + inner, Vector2(cx, cy) + outer_v, tm.c("accent_dim"), 1.0, true)


func _draw_upg_icon(ctrl: Control, path: String) -> void:
	var tm := ThemeManager
	var cx := ctrl.size.x * 0.5
	var cy := ctrl.size.y * 0.5
	var s  := 0.55
	# Draw icon bg
	var sb := StyleBoxFlat.new()
	sb.bg_color     = tm.c("bg_panel")
	sb.border_color = tm.c("border")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	ctrl.draw_style_box(sb, Rect2(0, 0, ctrl.size.x, ctrl.size.y))
	# Draw icon lines based on path key
	var col: Color = tm.c("accent_dim")
	var w   := 1.3
	if path == "M12 4v8M9 7l3-3 3 3":  # yield - up arrow
		ctrl.draw_line(Vector2(cx, cy + 5*s), Vector2(cx, cy - 5*s), col, w, true)
		ctrl.draw_line(Vector2(cx, cy - 5*s), Vector2(cx - 3*s, cy - 2*s), col, w, true)
		ctrl.draw_line(Vector2(cx, cy - 5*s), Vector2(cx + 3*s, cy - 2*s), col, w, true)
	elif path.begins_with("M12 3a9"):  # frequency - clock
		ctrl.draw_arc(Vector2(cx, cy), 5*s, 0, TAU, 32, col, w, true)
		ctrl.draw_line(Vector2(cx, cy), Vector2(cx, cy - 3*s), col, w, true)
		ctrl.draw_line(Vector2(cx, cy), Vector2(cx + 2*s, cy + 1*s), col, w, true)
	elif path.begins_with("M5 12"):  # speed - arrow right
		ctrl.draw_line(Vector2(cx - 5*s, cy), Vector2(cx + 5*s, cy), col, w, true)
		ctrl.draw_line(Vector2(cx + 5*s, cy), Vector2(cx + 2*s, cy - 3*s), col, w, true)
		ctrl.draw_line(Vector2(cx + 5*s, cy), Vector2(cx + 2*s, cy + 3*s), col, w, true)
	else:  # capacity - box with lock
		ctrl.draw_rect(Rect2(cx - 4*s, cy - 2*s, 8*s, 6*s), col, false, w)
		ctrl.draw_arc(Vector2(cx, cy - 2*s), 2.5*s, PI, TAU, 16, col, w, true)


var _resource_row_labels: Array = []
var _resource_rows_node_id: String = ""

# Rebuilt node panel layout
var _np_icon_ctrl: Control = null         # 52×52 icon placeholder
var _np_meta_lbl: Label = null            # "Ring 1 · Node 1"
var _np_status_lbl: Label = null          # "Connected" / "Locked"
var _np_res_container: VBoxContainer = null
var _np_upgrade_rows: Array = []          # [{icon,name,lv,val,btn}]

func _get_or_create_resource_rows() -> VBoxContainer:
	return _np_res_container


func _refresh_nodepanel_top_table() -> void:
	if _selected_node_id == "" or game_state == null:
		return
	if _np_res_container == null:
		return

	# Update meta labels
	if game_state.has_method("get_node_definition"):
		var def_v = game_state.call("get_node_definition", _selected_node_id)
		if typeof(def_v) == TYPE_DICTIONARY:
			var def := def_v as Dictionary
			var ring: int = int(def.get("ring", 0))
			var num: int  = int(def.get("number", 0))
			if _np_meta_lbl != null:
				_np_meta_lbl.text = "Ring %d · Node %d" % [ring, num]

	var state := _get_node_world_state(_selected_node_id)
	if _np_status_lbl != null:
		var connected: bool = bool(state.get("is_connected", false))
		var unlocked: bool  = bool(state.get("is_unlocked", false))
		if connected:
			_np_status_lbl.text = "Connected"
			_np_status_lbl.add_theme_color_override("font_color", ThemeManager.c("accent"))
		elif unlocked:
			_np_status_lbl.text = "Unlocked"
			_np_status_lbl.add_theme_color_override("font_color", ThemeManager.c("text_secondary"))
		else:
			_np_status_lbl.text = "Locked"
			_np_status_lbl.add_theme_color_override("font_color", ThemeManager.c("text_muted"))

	# Rebuild resource rows only when node changes
	if _resource_rows_node_id != _selected_node_id:
		_resource_rows_node_id = _selected_node_id
		_build_resource_rows(_np_res_container)

	_update_resource_row_values()
	if _np_icon_ctrl != null:
		_np_icon_ctrl.queue_redraw()


func _build_resource_rows(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.free()
	_resource_row_labels.clear()

	var tm := ThemeManager
	var def: Dictionary = {}
	if game_state.has_method("get_node_definition"):
		var d = game_state.call("get_node_definition", _selected_node_id)
		if typeof(d) == TYPE_DICTIONARY:
			def = d

	var outputs: Array = (def.get("outputs", []) as Array)
	if outputs.is_empty():
		var res_id: String = ""
		if game_state.has_method("get_node_primary_res_id"):
			res_id = str(game_state.call("get_node_primary_res_id", _selected_node_id))
		if res_id != "":
			outputs = [{"res": res_id, "weight": 1.0}]

	var sum_w: float = 0.0
	for o in outputs:
		sum_w += float((o as Dictionary).get("weight", 1.0))
	if sum_w <= 0.0: sum_w = 1.0

	for o_variant in outputs:
		var o: Dictionary = o_variant as Dictionary
		var res_id: String = str(o.get("res", ""))
		if res_id == "": continue
		var weight: float = float(o.get("weight", 1.0))
		var pct: int = int(round(weight / sum_w * 100.0))

		# Row matches header column widths exactly
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var res_row_lpad := Control.new()
		res_row_lpad.custom_minimum_size = Vector2(10, 0)
		row.add_child(res_row_lpad)
		var name_box := HBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_theme_constant_override("separation", 6)
		var dot_tex := _make_circle_texture(10, false)
		var dot := TextureRect.new()
		dot.texture = dot_tex
		dot.modulate = _node_color_for_id(res_id)
		dot.custom_minimum_size = Vector2(10, 10)
		dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		name_box.add_child(dot)
		var lbl_name := Label.new()
		lbl_name.text = _pretty_res(res_id)
		lbl_name.add_theme_font_size_override("font_size", 13)
		lbl_name.add_theme_color_override("font_color", tm.c("text_primary"))
		name_box.add_child(lbl_name)
		row.add_child(name_box)

		# Split — 32px fixed, +4px font
		var lbl_pct := Label.new()
		lbl_pct.text = "%d%%" % pct
		lbl_pct.custom_minimum_size   = Vector2(52, 0)
		lbl_pct.size_flags_horizontal = Control.SIZE_SHRINK_END
		lbl_pct.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_pct.clip_text             = true
		lbl_pct.add_theme_font_size_override("font_size", 14)
		lbl_pct.add_theme_color_override("font_color", tm.c("text_muted"))
		row.add_child(lbl_pct)

		# Rate — 46px fixed, +4px font
		var lbl_rate := Label.new()
		lbl_rate.text = "—"
		lbl_rate.custom_minimum_size   = Vector2(56, 0)
		lbl_rate.size_flags_horizontal = Control.SIZE_SHRINK_END
		lbl_rate.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_rate.clip_text             = true
		lbl_rate.add_theme_font_size_override("font_size", 14)
		lbl_rate.add_theme_color_override("font_color", tm.c("accent"))
		row.add_child(lbl_rate)

		# Stored — 42px fixed, +4px font
		var lbl_pool := Label.new()
		lbl_pool.text = "0"
		lbl_pool.custom_minimum_size   = Vector2(52, 0)
		lbl_pool.size_flags_horizontal = Control.SIZE_SHRINK_END
		lbl_pool.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_pool.clip_text             = true
		lbl_pool.add_theme_font_size_override("font_size", 14)
		lbl_pool.add_theme_color_override("font_color", tm.c("text_secondary"))
		row.add_child(lbl_pool)
		var pool_rpad := Control.new()
		pool_rpad.custom_minimum_size = Vector2(20, 0)
		row.add_child(pool_rpad)

		container.add_child(row)
		_resource_row_labels.append({
			"res_id":   res_id,
			"weight":   weight,
			"sum_w":    sum_w,
			"rate_lbl": lbl_rate,
			"pool_lbl": lbl_pool,
		})


func _update_resource_row_values() -> void:
	if _resource_row_labels.is_empty() or game_state == null:
		return

	# Get the node's pool dictionary directly from node state
	var pool_amounts: Dictionary = {}
	if game_state.has_method("get_node_definition"):
		# Read pool from the live node state
		var nodes_dict = game_state.get("nodes")
		if typeof(nodes_dict) == TYPE_DICTIONARY and nodes_dict.has(_selected_node_id):
			var n: Dictionary = nodes_dict[_selected_node_id] as Dictionary
			pool_amounts = (n.get("pool", {}) as Dictionary)

	var yield_rate: float = 0.0
	if game_state.has_method("get_node_rate_ui"):
		var rui = game_state.call("get_node_rate_ui", _selected_node_id)
		if typeof(rui) == TYPE_DICTIONARY:
			yield_rate = float(rui.get("effective_rate", 0.0))

	for entry in _resource_row_labels:
		var res_id: String   = str(entry.get("res_id", ""))
		var weight: float    = float(entry.get("weight", 1.0))
		var sum_w: float     = float(entry.get("sum_w", 1.0))
		var rate_lbl: Label  = entry.get("rate_lbl", null) as Label
		var pool_lbl: Label  = entry.get("pool_lbl", null) as Label

		var res_rate: float = yield_rate * (weight / sum_w)
		var pool_val: int   = int(float(pool_amounts.get(res_id, 0.0)))

		if rate_lbl != null and is_instance_valid(rate_lbl):
			rate_lbl.text = _fmt_rate(res_rate)
		if pool_lbl != null and is_instance_valid(pool_lbl):
			pool_lbl.text = _fmt_num(pool_val)


func _get_res_icon_texture(res_id: String) -> Texture2D:
	# Swap these to your real paths when ready.
	var path := ""
	match res_id:
		"spores": path = "res://assets/icons/mini_spore_64.png"
		"hyphae": path = "res://assets/icons/hyphae.png"
		"cellulose": path = "res://assets/icons/cellulose.png"
		"mycelium": path = "res://assets/icons/mycelium.png"
		_: path = ""

	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ---------------- NodePanel (Production line) ----------------

func _bind_nodepanel_production() -> void:
	pass  # prod_value assigned in _build_nodepanel_layout


func _bind_nodepanel_upgrades() -> void:
	pass  # upgrade rows built in _build_nodepanel_layout


func _refresh_nodepanel_production() -> void:
	pass  # Production footer removed from node panel layout


# ---------------- NodePanel (Upgrades) ----------------

func _on_upgrade_yield() -> void:
	_try_upgrade("yield_level")

func _on_upgrade_frequency() -> void:
	_try_upgrade("frequency_level")

func _on_upgrade_travel() -> void:
	_try_upgrade("speed_level")

func _on_upgrade_carry() -> void:
	_try_upgrade("carry_level")


func _try_upgrade(stat_key: String) -> void:
	if game_state == null or _selected_node_id == "":
		return
	if not game_state.has_method("upgrade_node_stat"):
		return
	var ok: bool = bool(game_state.call("upgrade_node_stat", _selected_node_id, stat_key))
	if ok:
		_flash_nutrients()
		_refresh_panel_access_ui()
	_refresh_currency_ui()
	_refresh_nodepanel_all()
	_refresh_digest_panel()
	# Release focus so button doesn't stay highlighted after press
	for entry in _np_upgrade_rows:
		var btn: Button = entry.get("btn", null) as Button
		if btn != null and is_instance_valid(btn):
			btn.release_focus()


func _refresh_nodepanel_upgrades() -> void:
	if _selected_node_id == "" or game_state == null:
		return
	if not game_state.has_method("get_node_upgrade_ui"):
		return

	var ui = game_state.call("get_node_upgrade_ui", _selected_node_id)
	if typeof(ui) != TYPE_DICTIONARY:
		return

	var nutrients: int = int(game_state.call("get_amount", "nutrients")) if game_state.has_method("get_amount") else 0
	var tm := ThemeManager

	for entry in _np_upgrade_rows:
		var name_lbl: Label  = entry.get("name_lbl", null) as Label
		var lv_lbl:   Label  = entry.get("lv_lbl",   null) as Label
		var val_lbl:  Label  = entry.get("val_lbl",  null) as Label
		var btn:      Button = entry.get("btn",       null) as Button
		var label_key: String = str(entry.get("label_key", ""))
		var level_key: String = str(entry.get("level_key", ""))
		var value_key: String = str(entry.get("value_key", ""))
		var cost_key:  String = str(entry.get("cost_key",  ""))

		var label: String = str(ui.get(label_key, ""))
		var level: int    = int(ui.get(level_key, 1))
		var value: String = str(ui.get(value_key, "—"))
		var cost:  int    = int(ui.get(cost_key,  0))
		var can_afford: bool = cost > 0 and nutrients >= cost

		if name_lbl != null:
			name_lbl.text = label
		if lv_lbl != null:
			lv_lbl.text = "Lv %d" % level
		if val_lbl != null:
			val_lbl.text = value

		if btn != null:
			btn.text = _fmt_cost(cost)
			btn.disabled = cost <= 0 or not can_afford
			btn.button_pressed = false
			btn.add_theme_font_size_override("font_size", 13)
			var sb_btn := StyleBoxFlat.new()
			sb_btn.set_corner_radius_all(6)
			sb_btn.set_border_width_all(1)
			if cost <= 0:
				sb_btn.bg_color     = tm.c("bg_deep")
				sb_btn.border_color = tm.c("border")
				btn.add_theme_color_override("font_color", tm.c("text_muted"))
			elif can_afford:
				sb_btn.bg_color     = tm.c("btn_bg")
				sb_btn.border_color = tm.c("btn_border")
				btn.add_theme_color_override("font_color", tm.c("accent"))
			else:
				sb_btn.bg_color     = tm.c("bg_deep")
				sb_btn.border_color = tm.c("border")
				btn.add_theme_color_override("font_color", tm.c("text_muted"))
			btn.add_theme_stylebox_override("normal",   sb_btn)
			btn.add_theme_stylebox_override("hover",    sb_btn)
			btn.add_theme_stylebox_override("pressed",  sb_btn)
			btn.add_theme_stylebox_override("focus",    sb_btn)
			btn.add_theme_stylebox_override("disabled", sb_btn)
			btn.release_focus()


func _refresh_nodepanel_all() -> void:
	_refresh_nodepanel_top_table()
	_refresh_nodepanel_production()
	_refresh_nodepanel_upgrades()


# ---------------- Currency binding ----------------

func _bind_currency_labels() -> void:
	var cs := find_child("CurrencyStack", true, false)
	if cs == null:
		push_warning("CurrencyStack not found; currency UI will not update.")
		return

	lbl_nutrients = _find_row_value_label(cs, "RowNutrients")
	lbl_glowcaps = _find_row_value_label(cs, "RowPremium")
	lbl_strain = _find_row_value_label(cs, "RowPrestige")


func _find_row_value_label(cs: Node, row_name: String) -> Label:
	var row := cs.find_child(row_name, true, false)
	if row == null:
		return null
	var val := row.find_child("Value", true, false)
	if val is Label:
		return val
	return null


# ---------------- Panel open/close ----------------

func _all_panels() -> Array[Control]:
	return [upgrades_panel, discoveries_panel, refinery_panel, digest_panel, settings_panel, node_panel, mutation_chamber_panel]


func _toggle_panel(panel: Control) -> void:
	if _open_panel == panel:
		_close_current()
	elif _open_panel != null:
		# Switch directly — no close animation, just swap
		if _open_panel == node_panel:
			_resource_rows_node_id = ""
		_open_panel.visible = false
		_set_panel_closed(_open_panel)
		_kill_tween()
		_open_panel = null
		_open(panel)
	else:
		_open(panel)


func _open(panel: Control) -> void:
	_kill_tween()

	if _open_panel != null:
		_open_panel.visible = false
		_set_panel_closed(_open_panel)

	_open_panel = panel

	dimmer.visible = true
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP

	panel.visible = true
	_set_panel_closed(panel)

	_redraw_nav_buttons()

	if panel == digest_panel:
		_layout_digest_panel()
		_refresh_digest_panel()
	if panel == discoveries_panel:
		_disc_reset_view()
		_refresh_discoveries_panel()
	if panel == refinery_panel:
		_refresh_refinery_panel()
	if panel == settings_panel:
		_refresh_settings_panel()
	if panel == node_panel:
		_refresh_nodepanel_all()
	if panel == mutation_chamber_panel:
		_refresh_mutation_chamber_panel()

	var vp_h       := get_viewport_rect().size.y
	var open_y     := vp_h - PANEL_H - _bar_h
	var pc         := _panel_container if _panel_container != null else panel

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(dimmer, "modulate:a", 1.0, 0.12)
	_tween.parallel().tween_property(pc, "position:y", open_y, 0.18)
	if panel == digest_panel:
		_tween.tween_callback(_layout_digest_panel)



func _close_current() -> void:
	if _open_panel == null:
		return

	_kill_tween()
	var panel := _open_panel
	var vp_h  := get_viewport_rect().size.y
	var pc    := _panel_container if _panel_container != null else panel

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(dimmer, "modulate:a", 0.0, 0.10)
	_tween.parallel().tween_property(pc, "position:y", vp_h, 0.14)

	_tween.finished.connect(func():
		panel.visible = false
		if panel == node_panel:
			_resource_rows_node_id = ""
		_open_panel = null
		dimmer.visible = false
		dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_redraw_nav_buttons()
	)


func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_current()
		get_viewport().set_input_as_handled()


# ---------------- Node tap selection ----------------

func _unhandled_input(_event: InputEvent) -> void:
	pass  # digest row tap handled in _input below


func _digest_handle_input(event: InputEvent) -> void:
	# Called from _input — handles digest row tap/hold independently of ScrollContainer.
	# We track touch ourselves: press starts a potential tap, drag beyond threshold cancels it.
	if _open_panel != digest_panel or digest_inventory_list == null:
		return

	var is_press   := false
	var is_release := false
	var is_drag    := false
	var ev_pos     := Vector2.ZERO

	if event is InputEventScreenTouch:
		var et := event as InputEventScreenTouch
		if et.index != 0:
			return  # only track primary finger for row selection
		ev_pos     = et.position
		is_press   = et.pressed
		is_release = not et.pressed
	elif event is InputEventScreenDrag:
		var ed := event as InputEventScreenDrag
		if ed.index != 0:
			return
		ev_pos  = ed.position
		is_drag = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		ev_pos     = (event as InputEventMouseButton).position
		is_press   = (event as InputEventMouseButton).pressed
		is_release = not is_press
	else:
		return

	if is_press:
		# Find hit row
		var hit_id := ""
		for item_id in _digest_row_refs:
			var row: Control = _digest_row_refs[item_id] as Control
			if row != null and is_instance_valid(row) and row.visible:
				if row.get_global_rect().has_point(ev_pos):
					hit_id = str(item_id)
					break
		if hit_id != "":
			_digest_hold_timer    = 0.0
			_digest_hold_id       = hit_id
			_digest_hold_consumed = false
			_digest_tap_start_pos = ev_pos

	elif is_drag and _digest_hold_id != "":
		# Cancel tap if finger moved more than threshold
		if ev_pos.distance_to(_digest_tap_start_pos) > 12.0:
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0

	elif is_release and _digest_hold_id != "":
		var press_id := _digest_hold_id
		if _digest_hold_consumed:
			_digest_hold_consumed = false
		elif _digest_hold_timer < 0.6:
			if _digest_selected_id == press_id:
				_digest_selected_id = ""
				_highlight_digest_row("")
				if _digest_action_bar != null:
					_digest_action_bar.visible = false
				if digest_feedback != null:
					digest_feedback.text = "Select a resource"
			else:
				_select_digest_row(press_id)
		_digest_hold_id    = ""
		_digest_hold_timer = 0.0


func _input(event: InputEvent) -> void:
	# Digest row tap/hold — must be in _input (fires before gui_input/accept_event)
	_digest_handle_input(event)

	# ESC always closes the open panel
	if event.is_action_pressed("ui_cancel"):
		if _open_panel != null:
			_close_current()
			get_viewport().set_input_as_handled()
		return

	# Block map interaction while a panel is showing
	# EXCEPT: allow node taps (press_end) to pass through so clicking a node
	# while a menu panel is open closes that panel and opens the node panel.
	if _open_panel != null and _open_panel != node_panel:
		# Block everything — we'll re-check after classifying the event type
		pass  # handled below after is_press_start/is_motion are declared

	# ── Pinch-to-zoom (native mobile gesture) ──────────────────────────────
	if event is InputEventMagnifyGesture:
		if _open_panel == null:
			_map_apply_zoom(event.factor, event.position)
			get_viewport().set_input_as_handled()
		elif _open_panel == discoveries_panel:
			_disc_apply_zoom(event.factor, event.position)
			get_viewport().set_input_as_handled()
		return

	# ── Manual two-finger pinch (fallback for Android without MagnifyGesture) ──
	if event is InputEventScreenTouch:
		var et := event as InputEventScreenTouch
		if et.pressed:
			_touch_points[et.index] = et.position
		else:
			_touch_points.erase(et.index)
		if _touch_points.size() == 2:
			var pts := _touch_points.values()
			_pinch_last_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
		else:
			_pinch_last_dist = 0.0

	if event is InputEventScreenDrag:
		var ed := event as InputEventScreenDrag
		_touch_points[ed.index] = ed.position
		if _touch_points.size() == 2:
			var pts := _touch_points.values()
			var new_dist: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _pinch_last_dist > 0.0 and new_dist > 0.0:
				var factor := new_dist / _pinch_last_dist
				var center := ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
				if _open_panel == null:
					_map_apply_zoom(factor, center)
					get_viewport().set_input_as_handled()
				elif _open_panel == discoveries_panel:
					_disc_apply_zoom(factor, center)
					get_viewport().set_input_as_handled()
			_pinch_last_dist = new_dist

	# ── Scroll-wheel zoom (desktop / testing) ──────────────────────────────
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _open_panel == null:
				_map_apply_zoom(1.0 + MAP_ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
			elif _open_panel == discoveries_panel:
				_disc_apply_zoom(1.0 + DISC_ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _open_panel == null:
				_map_apply_zoom(1.0 / (1.0 + MAP_ZOOM_STEP), event.position)
				get_viewport().set_input_as_handled()
			elif _open_panel == discoveries_panel:
				_disc_apply_zoom(1.0 / (1.0 + DISC_ZOOM_STEP), event.position)
				get_viewport().set_input_as_handled()
			return

	# ── Classify the event ─────────────────────────────────────────────────
	var is_press_start := false
	var is_press_end   := false
	var is_motion      := false
	var ev_pos         := Vector2.ZERO

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		ev_pos = event.position
		if event.pressed: is_press_start = true
		else:             is_press_end   = true
	elif event is InputEventScreenTouch:
		ev_pos = event.position
		if event.pressed: is_press_start = true
		else:             is_press_end   = true
	elif event is InputEventMouseMotion:
		ev_pos    = event.position
		is_motion = true
	elif event is InputEventScreenDrag:
		ev_pos    = event.position
		is_motion = true

	# Now that event type is known: block pan/zoom/press-start when panel is open,
	# but allow press-end through so a tap on a node can switch panels.
	if _open_panel != null and _open_panel != node_panel:
		if _open_panel == discoveries_panel:
			# Route drag to disc grid pan
			if is_press_start:
				var grid := _disc_get_grid()
				if grid != null:
					_disc_drag_start_screen = ev_pos
					_disc_drag_start_pos    = grid.position
					_disc_is_dragging       = true
					_disc_drag_has_moved    = false
				return
			if is_motion and _disc_is_dragging:
				var grid := _disc_get_grid()
				if grid != null:
					var delta := ev_pos - _disc_drag_start_screen
					if delta.length() > MAP_PAN_THRESHOLD:
						_disc_drag_has_moved = true
					if _disc_drag_has_moved:
						grid.position = _disc_drag_start_pos + delta
						get_viewport().set_input_as_handled()
				return
			if is_press_end:
				_disc_is_dragging = false
				return
		elif is_press_start or is_motion:
			return

	# Ignore taps that land in the bottom bar
	var vp_h := get_viewport_rect().size.y
	if (is_press_start or is_press_end) and ev_pos.y >= vp_h - _bar_h:
		return

	# ── Press start: begin drag tracking ──────────────────────────────────
	if is_press_start:
		# Record whether a popup was open when this press began
		_press_started_in_popup = (_disc_popup_layer != null and is_instance_valid(_disc_popup_layer)) or \
								  (_recipe_popup_layer != null and is_instance_valid(_recipe_popup_layer))
		_map_drag_start_screen  = ev_pos
		_map_drag_start_map_pos = map_layer.position
		_map_is_dragging        = true
		_map_drag_has_moved     = false
		return

	# ── Motion: pan if we've exceeded the threshold ───────────────────────
	if is_motion and _map_is_dragging:
		var delta := ev_pos - _map_drag_start_screen
		if delta.length() > MAP_PAN_THRESHOLD:
			_map_drag_has_moved = true
		if _map_drag_has_moved:
			map_layer.position = _map_drag_start_map_pos + delta
			get_viewport().set_input_as_handled()
		return

	# ── Press end: tap fires node-select; drag does nothing extra ─────────
	if is_press_end:
		_press_started_in_popup = false
		# Block if any popup is currently open or was closed during this press
		if _popup_closed_this_press or \
		   (_disc_popup_layer != null and is_instance_valid(_disc_popup_layer)) or \
		   (_recipe_popup_layer != null and is_instance_valid(_recipe_popup_layer)):
			_popup_closed_this_press = false
			_map_is_dragging = false
			return
		_popup_closed_this_press = false
		# If a menu panel was open, press_start was blocked so _map_is_dragging
		# is false — treat this press_end as a tap directly.
		var came_from_panel := (_open_panel != null and _open_panel != node_panel)
		if (came_from_panel) or (_map_is_dragging and not _map_drag_has_moved):
			_try_select_node(ev_pos)
		_map_is_dragging = false
		return


# ── Camera helpers ────────────────────────────────────────────────────────────

func _setup_initial_camera() -> void:
	_map_zoom             = MAP_ZOOM_START
	map_layer.scale       = Vector2(_map_zoom, _map_zoom)

	# Place SporeCloud at 45% down the viewport so ring-1 nodes are comfortably visible
	var vp_size := get_viewport_rect().size
	var target  := Vector2(vp_size.x * 0.50, vp_size.y * 0.45)
	map_layer.position = target - spore_cloud.position * _map_zoom


func _map_apply_zoom(factor: float, screen_pivot: Vector2) -> void:
	var old_zoom := _map_zoom
	_map_zoom = clamp(_map_zoom * factor, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	if is_equal_approx(_map_zoom, old_zoom):
		return

	# Keep the world-point under screen_pivot fixed while scaling
	var pivot_local := (screen_pivot - map_layer.position) / old_zoom
	map_layer.scale    = Vector2(_map_zoom, _map_zoom)
	map_layer.position = screen_pivot - pivot_local * _map_zoom


func _disc_get_grid() -> Control:
	if discoveries_panel == null:
		return null
	return discoveries_panel.find_child("DiscoveryGrid", true, false) as Control


func _disc_reset_view() -> void:
	_disc_zoom = DISC_ZOOM_START
	var grid := _disc_get_grid()
	if grid == null:
		return
	grid.scale    = Vector2.ONE
	grid.position = Vector2.ZERO


func _disc_apply_zoom(factor: float, screen_pivot: Vector2) -> void:
	var grid := _disc_get_grid()
	if grid == null:
		return
	# Convert screen pivot to grid-local space
	var panel_rect := _panel_container.get_global_rect() if _panel_container != null else Rect2()
	var local_pivot := screen_pivot - panel_rect.position - grid.position
	var old_zoom := _disc_zoom
	_disc_zoom = clamp(_disc_zoom * factor, DISC_ZOOM_MIN, DISC_ZOOM_MAX)
	if is_equal_approx(_disc_zoom, old_zoom):
		return
	var scale_ratio := _disc_zoom / old_zoom
	grid.scale    = Vector2(_disc_zoom, _disc_zoom)
	grid.position = screen_pivot - panel_rect.position - local_pivot * scale_ratio


# ── Node tap selection (extracted from old _input) ────────────────────────────

func _try_select_node(screen_pos: Vector2) -> void:
	# Block node taps whenever any popup layer is active
	if (_disc_popup_layer != null and is_instance_valid(_disc_popup_layer)) or \
	   (_recipe_popup_layer != null and is_instance_valid(_recipe_popup_layer)):
		return

	var canvas_xform := get_viewport().get_canvas_transform()

	# If a panel is open, block any tap that lands inside the panel's screen rect
	if _open_panel != null:
		var panel_rect := _open_panel.get_global_rect()
		if panel_rect.has_point(screen_pos):
			return

	for e in _node_list:
		var node_raw = e.get("node")
		if node_raw == null or not is_instance_valid(node_raw):
			continue
		var node: Node2D    = node_raw as Node2D
		var node_id: String = str(e["id"])
		var state           := _get_node_world_state(node_id)

		if not bool(state.get("is_visible", true)):
			continue

		var node_screen := canvas_xform * node.global_position
		if node_screen.distance_to(screen_pos) > NODE_HIT_RADIUS:
			continue

		if not bool(state.get("is_unlocked", true)):
			# Attempt purchase — no panel opened regardless of outcome
			if game_state != null and game_state.has_method("try_unlock_node"):
				var unlocked: bool = bool(game_state.call("try_unlock_node", node_id))
				if unlocked:
					_refresh_panel_access_ui()
					_refresh_currency_ui()
					_refresh_node_world_state()
					_update_node_cost_labels()
			get_viewport().set_input_as_handled()
			return

		# Unlocked node — close any open menu panel then open node panel
		# Exception: if this node's panel is already open, close it (toggle)
		if _open_panel == node_panel and _selected_node_id == node_id:
			_close_current()
			get_viewport().set_input_as_handled()
			return

		if _open_panel != null and _open_panel != node_panel:
			_open_panel.visible = false
			_set_panel_closed(_open_panel)
			_open_panel = null
			_kill_tween()
			dimmer.visible = false
			dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		node_title.text   = str(e["name"])
		_selected_node_id = node_id
		_select_node(node)
		_open(node_panel)
		_refresh_nodepanel_all()
		get_viewport().set_input_as_handled()
		return


func _setup_map_containers() -> void:
	var map: Node2D = get_node_or_null("MapLayer") as Node2D
	if map == null:
		push_warning("MapLayer not found.")
		return
	nodes_container = map.get_node_or_null("Nodes") as Node
	if nodes_container == null:
		nodes_container = Node2D.new()
		nodes_container.name = "Nodes"
		map.add_child(nodes_container)
	lines_container = map.get_node_or_null("Lines") as Node
	if lines_container == null:
		lines_container = Node2D.new()
		lines_container.name = "Lines"
		map.add_child(lines_container)
		map.move_child(lines_container, nodes_container.get_index())


func _build_node_registry() -> void:
	_node_list.clear()
	_node_lookup.clear()
	_line_lookup.clear()

	if game_state == null or not game_state.has_method("get_all_node_defs"):
		return

	var defs = game_state.call("get_all_node_defs")
	if typeof(defs) != TYPE_ARRAY:
		return

	# Clear any previously spawned runtime nodes (keeps static scene children intact)
	# Use a collect-then-free pattern so we don't modify the array while iterating,
	# and use free() not queue_free() so they're gone before get_node_or_null runs below.
	var to_free: Array = []
	for child in nodes_container.get_children():
		if child.get_meta("runtime_spawned", false):
			to_free.append(child)
	for child in to_free:
		child.free()

	for def_variant in defs:
		var def: Dictionary = def_variant as Dictionary
		var node_id: String  = str(def.get("id", ""))
		var node_name: String = str(def.get("name", node_id))
		if node_id == "":
			continue

		# ── Compute world position from ring distance + angle ──────────────
		var distance_px: float = float(def.get("distance_px", 100.0))
		var angle_deg: float   = float(def.get("angle_deg",   0.0))
		var angle_rad: float   = deg_to_rad(angle_deg)
		var local_pos: Vector2 = Vector2(
			cos(angle_rad) * distance_px,
			sin(angle_rad) * distance_px
		)
		# Position is relative to SporeCloud which sits at the origin of nodes_container
		var world_pos: Vector2 = spore_cloud.position + local_pos

		# ── Spawn or reuse scene node ──────────────────────────────────────
		# First, check if a static scene node already exists with this id's name
		var legacy_name: String = "Node_" + node_id.to_pascal_case()
		var node_ref: Node2D = nodes_container.get_node_or_null(legacy_name) as Node2D

		if node_ref == null:
			# Runtime-spawn a simple Node2D with a visual Sprite placeholder
			node_ref = Node2D.new()
			node_ref.name = legacy_name
			node_ref.set_meta("runtime_spawned", true)
			node_ref.position = world_pos
			_add_node_visual(node_ref, node_id, node_name)
			nodes_container.add_child(node_ref)
		else:
			# Reposition the static scene node to the data-driven position
			node_ref.position = world_pos

		var entry := {"id": node_id, "name": node_name, "node": node_ref}
		_node_list.append(entry)
		_node_lookup[node_id] = entry


func _add_node_visual(parent: Node2D, node_id: String, node_name: String) -> void:
	# Create a simple visual circle for the node using a generated texture
	var spr := Sprite2D.new()
	spr.name = node_name.replace(" ", "")
	spr.texture = _make_circle_texture(48, false)
	spr.modulate = _node_color_for_id(node_id)
	spr.centered = true
	parent.add_child(spr)

	# Collision shape for tap detection
	var area := Area2D.new()
	area.name = "ClickArea"
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 44.0
	col.shape = shape
	area.add_child(col)
	parent.add_child(area)


func _node_color_for_id(node_id: String) -> Color:
	# Deterministic pastel color from node id hash
	var h: int = node_id.hash()
	var hue: float = fmod(abs(float(h)) / 2147483647.0, 1.0)
	return Color.from_hsv(hue, 0.55, 0.85, 1.0)


func _get_node_world_state(node_id: String) -> Dictionary:
	if game_state != null and game_state.has_method("get_node_state_ui"):
		var state = game_state.call("get_node_state_ui", node_id)
		if typeof(state) == TYPE_DICTIONARY:
			return state
	return {
		"is_visible": true,
		"is_unlocked": true,
		"is_connected": true
	}


func _refresh_node_world_state() -> void:
	for e in _node_list:
		var node_id: String = str(e.get("id", ""))
		var node_raw = e.get("node")
		if node_raw == null or not is_instance_valid(node_raw):
			continue
		var node_ref: Node2D = node_raw as Node2D

		var state := _get_node_world_state(node_id)
		var node_visible: bool = bool(state.get("is_visible", true))
		var node_unlocked: bool = bool(state.get("is_unlocked", true))
		var node_connected: bool = bool(state.get("is_connected", true))

		node_ref.visible = node_visible
		if node_visible:
			node_ref.modulate = Color(1, 1, 1, 1.0 if node_unlocked else 0.40)

		if _line_lookup.has(node_id):
			var line_ref: CanvasItem = _line_lookup[node_id] as CanvasItem
			if line_ref != null:
				line_ref.visible = node_visible and node_connected

		if _selected_node_id == node_id and (not node_visible or not node_unlocked):
			selection_ring.visible = false
			if _open_panel == node_panel:
				_close_current()

	_update_node_cost_labels()


func _update_node_cost_labels() -> void:
	for e in _node_list:
		var node_id: String  = str(e.get("id", ""))
		var node_raw = e.get("node")
		if node_raw == null or not is_instance_valid(node_raw):
			continue
		var node_ref: Node2D = node_raw as Node2D

		var state        := _get_node_world_state(node_id)
		var node_vis     := bool(state.get("is_visible", false))
		var node_lock    := bool(state.get("is_unlocked", false))

		# Show cost label only when visible + locked
		if node_vis and not node_lock:
			var cost: int = int(state.get("unlock_cost", 0))
			var lbl: Label = _node_cost_labels.get(node_id, null) as Label

			if lbl == null or not is_instance_valid(lbl):
				lbl = Label.new()
				lbl.name = "CostLabel_" + node_id
				# No top_level — parented to map_layer so it moves with the map
				lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", 12)
				lbl.add_theme_color_override("font_color", ThemeManager.c("accent"))
				lbl.add_theme_color_override("font_outline_color", ThemeManager.c("bg_deep"))
				lbl.add_theme_constant_override("outline_size", 3)
				map_layer.add_child(lbl)
				_node_cost_labels[node_id] = lbl

			lbl.text = _fmt_int(cost)
			# Position in map_layer local space (node_ref.position is already local to map_layer)
			lbl.position = node_ref.position + Vector2(-lbl.size.x * 0.5, -48)
			lbl.visible = true
		else:
			var lbl: Label = _node_cost_labels.get(node_id, null) as Label
			if lbl != null and is_instance_valid(lbl):
				lbl.visible = false


func _select_node(node: Node2D) -> void:
	_selected_node = node
	selection_ring.visible = true
	selection_ring.global_position = node.global_position
	_play_node_pop(node)


func _play_node_pop(node: Node2D) -> void:
	if _node_pop_tween and _node_pop_tween.is_running():
		_node_pop_tween.kill()

	var spr: Sprite2D = null
	for c in node.get_children():
		if c is Sprite2D:
			spr = c
			break
	if spr == null:
		return

	var base_scale := spr.scale
	_node_pop_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_node_pop_tween.tween_property(spr, "scale", base_scale * 1.10, 0.08)
	_node_pop_tween.tween_property(spr, "scale", base_scale, 0.10)


# ── Mutation Chamber Panel ────────────────────────────────────────────────────

func _bind_mutation_chamber_panel() -> void:
	if mutation_chamber_panel == null:
		return

	# Hide the scene-built MarginContainer (same pattern as other panels)
	var margin_c: Control = mutation_chamber_panel.find_child("MarginContainer", true, false) as Control
	if margin_c != null:
		margin_c.visible = false

	var tm := ThemeManager

	# ── Outer root fills the panel ────────────────────────────────────────────
	var root := VBoxContainer.new()
	root.name = "MCRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	mutation_chamber_panel.add_child(root)

	# ── Header + GS area (padded) ─────────────────────────────────────────────
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   16)
	pad.add_theme_constant_override("margin_right",  16)
	pad.add_theme_constant_override("margin_top",    14)
	pad.add_theme_constant_override("margin_bottom", 8)
	root.add_child(pad)

	var pad_vbox := VBoxContainer.new()
	pad_vbox.add_theme_constant_override("separation", 8)
	pad.add_child(pad_vbox)

	# Title
	var header := Label.new()
	header.text = "Mutation Chamber"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", tm.c("accent"))
	pad_vbox.add_child(header)

	# GS balance row
	var gs_row := HBoxContainer.new()
	gs_row.add_theme_constant_override("separation", 8)
	pad_vbox.add_child(gs_row)

	var lbl_gs_title := Label.new()
	lbl_gs_title.text = "Genetic Strain:"
	lbl_gs_title.add_theme_font_size_override("font_size", 14)
	lbl_gs_title.add_theme_color_override("font_color", tm.c("text_secondary"))
	gs_row.add_child(lbl_gs_title)

	_mc_gs_lbl = Label.new()
	_mc_gs_lbl.name = "LblGSBalance"
	_mc_gs_lbl.text = "0 GS"
	_mc_gs_lbl.add_theme_font_size_override("font_size", 16)
	_mc_gs_lbl.add_theme_color_override("font_color", tm.c("accent"))
	gs_row.add_child(_mc_gs_lbl)

	# ── Mutate card ───────────────────────────────────────────────────────────
	var mutate_card := PanelContainer.new()
	mutate_card.name = "MutateCard"
	var sb_card := StyleBoxFlat.new()
	sb_card.bg_color     = tm.c("bg_panel")
	sb_card.border_color = tm.c("accent_border")
	sb_card.set_border_width_all(1)
	sb_card.set_corner_radius_all(10)
	sb_card.content_margin_left   = 12
	sb_card.content_margin_right  = 12
	sb_card.content_margin_top    = 10
	sb_card.content_margin_bottom = 10
	mutate_card.add_theme_stylebox_override("panel", sb_card)
	pad_vbox.add_child(mutate_card)

	var mutate_vbox := VBoxContainer.new()
	mutate_vbox.add_theme_constant_override("separation", 6)
	mutate_card.add_child(mutate_vbox)

	_mc_run_lbl = Label.new()
	_mc_run_lbl.name = "LblRunValue"
	_mc_run_lbl.text = "Run value: —"
	_mc_run_lbl.add_theme_font_size_override("font_size", 12)
	_mc_run_lbl.add_theme_color_override("font_color", tm.c("text_secondary"))
	mutate_vbox.add_child(_mc_run_lbl)

	_mc_preview_lbl = Label.new()
	_mc_preview_lbl.name = "LblGSPreview"
	_mc_preview_lbl.text = "Reach 10M nutrients to Mutate"
	_mc_preview_lbl.add_theme_font_size_override("font_size", 13)
	_mc_preview_lbl.add_theme_color_override("font_color", tm.c("text_primary"))
	mutate_vbox.add_child(_mc_preview_lbl)

	_mc_mutate_btn = Button.new()
	_mc_mutate_btn.name = "BtnMutate"
	_mc_mutate_btn.text = "MUTATE"
	_mc_mutate_btn.custom_minimum_size = Vector2(0, 40)
	_mc_mutate_btn.disabled = true
	_mc_mutate_btn.focus_mode = Control.FOCUS_NONE
	_theme_action_button(_mc_mutate_btn)
	_mc_mutate_btn.pressed.connect(_on_mutate_pressed)
	mutate_vbox.add_child(_mc_mutate_btn)

	# Separator
	pad_vbox.add_child(HSeparator.new())

	# Mutations header
	var mut_hdr := Label.new()
	mut_hdr.text = "MUTATIONS"
	mut_hdr.add_theme_font_size_override("font_size", 11)
	mut_hdr.add_theme_color_override("font_color", tm.c("text_muted"))
	pad_vbox.add_child(mut_hdr)

	# ── Scroll area fills the rest ────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_mc_mutation_list = VBoxContainer.new()
	_mc_mutation_list.name = "MutationList"
	_mc_mutation_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mc_mutation_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_mc_mutation_list)

	# Suppress scrollbar visual
	await get_tree().process_frame
	if is_instance_valid(scroll):
		var vscroll := scroll.get_node_or_null("_v_scroll") as ScrollBar
		if vscroll != null:
			var sb_hidden := StyleBoxEmpty.new()
			vscroll.add_theme_stylebox_override("scroll", sb_hidden)
			vscroll.custom_minimum_size = Vector2(0, 0)


func _refresh_mutation_chamber_panel() -> void:
	if mutation_chamber_panel == null or game_state == null:
		return
	if not game_state.has_method("get_mutation_chamber_ui"):
		return

	var data_v = game_state.call("get_mutation_chamber_ui")
	if typeof(data_v) != TYPE_DICTIONARY:
		return
	var data: Dictionary = data_v as Dictionary

	# GS balance
	if _mc_gs_lbl != null:
		_mc_gs_lbl.text = "%s GS" % _fmt_int(int(data.get("gs_balance", 0)))

	# Run value + preview
	if _mc_run_lbl != null:
		_mc_run_lbl.text = "Run value: %s nutrients" % _fmt_num(int(data.get("run_value", 0)))

	if _mc_preview_lbl != null:
		var gs_p: int = int(data.get("gs_preview", 0))
		if gs_p > 0:
			_mc_preview_lbl.text = "+%d GS on Mutate" % gs_p
		else:
			_mc_preview_lbl.text = "Reach 10M nutrients to Mutate"

	if _mc_mutate_btn != null:
		_mc_mutate_btn.disabled = not bool(data.get("can_prestige", false))

	# Rebuild mutation list
	if _mc_mutation_list == null:
		return
	for child in _mc_mutation_list.get_children():
		child.queue_free()

	var mutations: Array = data.get("mutations", []) as Array
	var unlock_cost: int = int(data.get("unlock_cost", 0))

	# Starters section
	_mc_add_section_header(_mc_mutation_list, "Starter Mutations")
	for mut_v in mutations:
		var m: Dictionary = mut_v as Dictionary
		if str(m.get("id", "")) in ["M01", "M02", "M03"]:
			_mc_mutation_list.add_child(_make_mutation_row(m, unlock_cost))

	# Chain section
	_mc_add_section_header(_mc_mutation_list, "Mutation Chain")
	for mut_v in mutations:
		var m: Dictionary = mut_v as Dictionary
		var mid: String = str(m.get("id", ""))
		if mid in ["M01", "M02", "M03"]:
			continue
		# Hide unowned reserved slots
		if bool(m.get("is_reserved", false)) and not bool(m.get("is_owned", false)):
			continue
		_mc_mutation_list.add_child(_make_mutation_row(m, unlock_cost))


func _mc_add_section_header(parent: VBoxContainer, text: String) -> void:
	var tm := ThemeManager
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top",    10)
	m.add_theme_constant_override("margin_bottom",  2)
	m.add_theme_constant_override("margin_left",   16)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", tm.c("text_muted"))
	m.add_child(lbl)
	parent.add_child(m)


func _make_mutation_row(m: Dictionary, unlock_cost: int) -> Control:
	var tm := ThemeManager
	var mid: String       = str(m.get("id", ""))
	var is_owned: bool    = bool(m.get("is_owned", false))
	var is_avail: bool    = bool(m.get("is_available_to_unlock", false))
	var is_reserved: bool = bool(m.get("is_reserved", false))
	var level: int        = int(m.get("level", 0))
	var can_unlock: bool  = bool(m.get("can_unlock", false))
	var levelup_cost: int = int(m.get("levelup_cost", -1))
	var can_levelup: bool = bool(m.get("can_levelup", false))

	# Padding wrapper
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",  16)
	pad.add_theme_constant_override("margin_right", 16)

	# Card
	var card := PanelContainer.new()
	card.name = "MutRow_" + mid
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	if is_owned:
		sb.bg_color     = tm.c("bg_row")
		sb.border_color = tm.c("accent_border")
	elif is_avail:
		sb.bg_color     = tm.c("bg_panel")
		sb.border_color = tm.c("accent_dim")
	else:
		sb.bg_color     = tm.c("bg_deep")
		sb.border_color = tm.c("border")
	card.add_theme_stylebox_override("panel", sb)
	pad.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# Left: name + description
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl_name := Label.new()
	lbl_name.text = "%s  %s" % [mid, str(m.get("name", mid))]
	lbl_name.add_theme_font_size_override("font_size", 14)
	lbl_name.add_theme_color_override("font_color",
		tm.c("accent") if is_owned else (tm.c("text_primary") if is_avail else tm.c("text_muted")))
	info_col.add_child(lbl_name)

	var lbl_desc := Label.new()
	lbl_desc.text = str(m.get("desc", ""))
	lbl_desc.add_theme_font_size_override("font_size", 11)
	lbl_desc.add_theme_color_override("font_color", tm.c("text_muted"))
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(lbl_desc)
	hbox.add_child(info_col)

	# Right: level badge + action button
	var action_col := VBoxContainer.new()
	action_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	action_col.alignment = BoxContainer.ALIGNMENT_CENTER

	if is_owned:
		var lbl_lv := Label.new()
		lbl_lv.text = "Lv %d" % level
		lbl_lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_lv.add_theme_font_size_override("font_size", 12)
		lbl_lv.add_theme_color_override("font_color", tm.c("accent_dim"))
		action_col.add_child(lbl_lv)

	if not is_reserved:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(90, 28)
		btn.clip_text = true

		if is_owned:
			if levelup_cost > 0:
				btn.text = "Lv+  %s" % _fmt_num(levelup_cost)
				btn.disabled = not can_levelup
				if not btn.disabled:
					btn.pressed.connect(func(): _on_mutation_levelup_pressed(mid))
			else:
				btn.text = "MAX"
				btn.disabled = true
		elif is_avail:
			btn.text = "Unlock\n%s GS" % _fmt_int(unlock_cost)
			btn.disabled = not can_unlock
			if not btn.disabled:
				btn.pressed.connect(func(): _on_mutation_unlock_pressed(mid))
		else:
			btn.text = "Locked"
			btn.disabled = true

		_theme_action_button(btn)
		action_col.add_child(btn)

	hbox.add_child(action_col)
	return pad


func _on_mutation_unlock_pressed(mutation_id: String) -> void:
	if game_state == null or not game_state.has_method("buy_mutation_unlock"):
		return
	if bool(game_state.call("buy_mutation_unlock", mutation_id)):
		_refresh_mutation_chamber_panel()
		_refresh_currency_ui()


func _on_mutation_levelup_pressed(mutation_id: String) -> void:
	if game_state == null or not game_state.has_method("buy_mutation_levelup"):
		return
	if bool(game_state.call("buy_mutation_levelup", mutation_id)):
		_refresh_mutation_chamber_panel()
		_refresh_currency_ui()


func _on_mutate_pressed() -> void:
	if game_state == null or not game_state.has_method("do_mutate"):
		return

	var gs_awarded: int = int(game_state.call("do_mutate"))
	if gs_awarded < 0:
		return

	# Clear stale refs immediately — _process runs before the await
	_root_pulse_visuals.clear()
	_node_list.clear()
	_node_lookup.clear()

	# Free stale cost labels from the previous run
	for node_id_v in _node_cost_labels.keys():
		var lbl = _node_cost_labels[node_id_v]
		if lbl != null and is_instance_valid(lbl):
			lbl.queue_free()
	_node_cost_labels.clear()

	_close_current()
	_last_refinery_inventory_signature = ""
	_last_discovery_signature = ""

	# Rebuild visual registry first, THEN refresh state against the new GameState
	_build_node_registry()
	_refresh_node_world_state()
	_register_root_transfer_positions()
	_setup_root_pulses()
	_setup_transfer_fx()
	_refresh_currency_ui()
	_refresh_panel_access_ui()
	_redraw_nav_buttons()

	# Re-open chamber so player can spend GS immediately
	await get_tree().process_frame
	if is_instance_valid(mutation_chamber_panel):
		_toggle_panel(mutation_chamber_panel)


# ---------------- Currency UI ----------------

func _refresh_currency_ui() -> void:
	if game_state == null or not game_state.has_method("get_amount"):
		return
	if lbl_nutrients == null or lbl_glowcaps == null or lbl_strain == null:
		return

	lbl_nutrients.text = _fmt_int(int(game_state.call("get_amount", "nutrients")))
	lbl_glowcaps.text  = _fmt_int(int(game_state.call("get_amount", "glowcaps")))
	lbl_strain.text    = _fmt_int(int(game_state.call("get_amount", "strain_points")))


# ---------------- Formatting helpers ----------------

func _get_node_name(node_id: String) -> String:
	if game_state != null and game_state.has_method("get_node_display_name"):
		return str(game_state.call("get_node_display_name", node_id))

	for e in _node_list:
		if str(e["id"]) == node_id:
			return str(e["name"])
	return node_id


func _pretty_res(res_id: String) -> String:
	if game_state != null and game_state.has_method("get_resource_name"):
		var pretty := str(game_state.call("get_resource_name", res_id))
		if pretty != "":
			return pretty

	match res_id:
		"spores": return "Spores"
		"hyphae": return "Hyphae"
		"cellulose": return "Cellulose"
		"mycelium": return "Mycelium"
		"nutrients": return "Nutrients"
		"glowcaps": return "Glowcaps"
		"strain_points": return "Strain Points"
		_: return res_id.capitalize()


func _fmt_rate(r: float) -> String:
	if r >= 10.0:
		return str(snapped(r, 0.1))
	return str(snapped(r, 0.01))


func _fmt_int(v: int) -> String:
	var s := str(v)
	var n := s.length()
	if n <= 3:
		return s

	var out := ""
	var count := 0
	for i in range(n - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i != 0:
			out = "," + out
			count = 0
	return out


func _fmt_cost(v: int) -> String:
	if v <= 0:
		return "MAX"
	return _fmt_num(v)


func _fmt_num(v: int) -> String:
	# Like _fmt_cost but never returns MAX — use for stored/pool values
	if v < 1000:
		return str(v)
	if v < 1_000_000:
		var k := v / 1000.0
		return ("%.0fK" if k >= 100 else ("%.1fK" if k >= 10 else "%.2fK")) % k
	if v < 1_000_000_000:
		var m := v / 1_000_000.0
		return ("%.0fM" if m >= 100 else ("%.1fM" if m >= 10 else "%.2fM")) % m
	var b := v / 1_000_000_000.0
	return ("%.0fB" if b >= 100 else ("%.1fB" if b >= 10 else "%.2fB")) % b


func _set_panel_closed(panel: Control) -> void:
	# Push the shared container off-screen below; individual panels fill it
	if _panel_container != null:
		_panel_container.position.y = get_viewport_rect().size.y
	else:
		panel.position.y = get_viewport_rect().size.y


func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null