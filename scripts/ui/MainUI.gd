extends Control

const PANEL_H_RATIO  := 0.68  # panel takes 68% of screen height
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
@onready var settings_panel: Control     = $PanelHost/PanelContainer/SettingsPanel

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
var _map_drag_start_screen: Vector2 = Vector2.ZERO
var _map_drag_start_map_pos: Vector2 = Vector2.ZERO
var _map_drag_has_moved: bool = false

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
var _digest_auto_ids: Dictionary = {}   # item_id -> bool
var _digest_mode: String = "manual"     # "manual" or "auto"

# Discoveries panel widgets
var discoveries_list: VBoxContainer = null
var discoveries_feedback: Label = null

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
		_panel_container.top_level = true
		_panel_container.size     = Vector2(vp.x, PANEL_H)
		_panel_container.position = Vector2(0.0, vp.y)
		await get_tree().process_frame

	# Each panel must exactly fill the container — set position and size explicitly
	for p in _all_panels():
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.position = Vector2.ZERO
		p.size     = Vector2(_panel_container.size.x, _panel_container.size.y)

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
		# Label colors
		for child in (row_ref as Control).get_children():
			if child is Label:
				(child as Label).add_theme_color_override("font_color", tm.c("text_secondary"))
		# Button style
		var btn: Button = (row_ref as Control).find_child("BtnUpgrade", true, false) as Button
		if btn != null:
			var sb := StyleBoxFlat.new()
			sb.bg_color     = tm.c("btn_bg")
			sb.border_color = tm.c("btn_border")
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(8)
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_color_override("font_color", tm.c("accent"))


func _refresh_all_panels() -> void:
	if _open_panel == digest_panel:      _refresh_digest_panel()
	if _open_panel == discoveries_panel: _refresh_discoveries_panel()
	if _open_panel == refinery_panel:    _refresh_refinery_panel()
	if _open_panel == settings_panel:    _refresh_settings_panel()
	if _open_panel == node_panel:        _refresh_nodepanel_all()


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

	var panels := [digest_panel, refinery_panel, discoveries_panel, null, null]

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
		(key == "discoveries"  and _open_panel == discoveries_panel)
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
			_select_digest_row(_digest_hold_id, "auto")
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0

	_ui_accum += dt
	if _ui_accum >= UI_REFRESH_DT:
		_ui_accum = 0.0
		_refresh_panel_access_ui()
		_refresh_currency_ui()
		_refresh_node_world_state()

		if _open_panel == node_panel and _selected_node_id != "":
			_refresh_nodepanel_all()

		if _open_panel == digest_panel:
			_update_digest_live_values()
			if _digest_selected_id != "": _update_digest_action_bar()

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
		var node_ref: Node2D = e.get("node", null) as Node2D
		if node_id == "" or node_ref == null:
			continue
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
		var node_ref: Node2D = e["node"] as Node2D

		if not _root_pulse_visuals.has(node_id):
			continue

		var pulse: Dictionary = _root_pulse_visuals[node_id] as Dictionary
		var root: Node2D = pulse["root"] as Node2D
		var glow: Sprite2D = pulse["glow"] as Sprite2D
		var dot: Sprite2D = pulse["dot"] as Sprite2D

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
	# Wipe the old scene content — we build everything in code
	var root_box: VBoxContainer = digest_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if root_box == null:
		return
	for child in root_box.get_children():
		child.queue_free()

	# ── Panel header ──────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "Digest"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", ThemeManager.c("accent"))
	root_box.add_child(header)

	# ── Tab row ───────────────────────────────────────────────────────────
	digest_tabs_row = HBoxContainer.new()
	digest_tabs_row.add_theme_constant_override("separation", 4)
	root_box.add_child(digest_tabs_row)

	digest_tab_resources = _make_digest_tab("Raw",       func(): _set_digest_active_category("resource"))
	digest_tab_compounds = _make_digest_tab("Compounds", func(): _set_digest_active_category("compound"))
	digest_tab_solutions = _make_digest_tab("Solutions", func(): _set_digest_active_category("solution"))
	digest_tabs_row.add_child(digest_tab_resources)
	digest_tabs_row.add_child(digest_tab_compounds)
	digest_tabs_row.add_child(digest_tab_solutions)

	# ── Scrollable resource list ──────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Cap scroll height so action bar always has room at bottom (~120px for bar)
	scroll.custom_minimum_size = Vector2(0, 80)
	scroll.size_flags_stretch_ratio = 1.0
	root_box.add_child(scroll)

	digest_inventory_list = VBoxContainer.new()
	digest_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	digest_inventory_list.add_theme_constant_override("separation", 4)
	scroll.add_child(digest_inventory_list)

	# ── Action bar (hidden until row selected) ────────────────────────────
	_digest_action_bar = _build_digest_action_bar(root_box)
	_digest_action_bar.visible = false

	# ── Feedback label ────────────────────────────────────────────────────
	digest_feedback = Label.new()
	digest_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	digest_feedback.add_theme_font_size_override("font_size", 12)
	digest_feedback.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
	root_box.add_child(digest_feedback)

	_set_digest_active_category("resource")


func _make_digest_tab(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	return btn


func _build_digest_action_bar(parent: VBoxContainer) -> Control:
	# Outer bar — PanelContainer for background
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical   = Control.SIZE_SHRINK_END
	bar.custom_minimum_size   = Vector2(0, 110)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.c("bg_panel")
	sb.border_color = ThemeManager.c("border")
	sb.border_width_top = 2
	sb.border_color = ThemeManager.c("bark_stripe")
	sb.set_corner_radius_all(10)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	bar.add_child(vbox)

	# ── Mode label (resource name + tap/hold hint) ────────────────────────
	_digest_action_lbl = Label.new()
	_digest_action_lbl.name = "ActionLbl"
	_digest_action_lbl.add_theme_font_size_override("font_size", 13)
	_digest_action_lbl.add_theme_color_override("font_color", ThemeManager.c("text_primary"))
	vbox.add_child(_digest_action_lbl)

	# ── Main row: [Slider] [Amount+Value VBox] [Digest btn] ───────────────
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	vbox.add_child(main_row)

	# Slider — takes most of the width
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

	# Right column: amount on top, value below
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 2)
	right_col.custom_minimum_size = Vector2(80, 0)
	main_row.add_child(right_col)

	var lbl_amount := Label.new()
	lbl_amount.name = "LblSelectedAmt"
	lbl_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_amount.add_theme_font_size_override("font_size", 13)
	lbl_amount.add_theme_color_override("font_color", ThemeManager.c("accent"))
	right_col.add_child(lbl_amount)

	var lbl_value := Label.new()
	lbl_value.name = "LblSelectedVal"
	lbl_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_value.add_theme_font_size_override("font_size", 11)
	lbl_value.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
	right_col.add_child(lbl_value)

	# Digest button — right of the right column
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
		digest_feedback.text = ""

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
	# Must explicitly allow input — PanelContainer defaults to IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_digest_row_input.bind(item_id))

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
			_digest_hold_timer = 0.0
			_digest_hold_id    = item_id
		else:
			if _digest_hold_id == item_id and _digest_hold_timer < 0.6:
				# Short tap
				if _digest_selected_id == item_id and _digest_mode == "manual":
					# Tap same row again in same mode → deselect
					_digest_selected_id = ""
					_highlight_digest_row("")
					if _digest_action_bar != null:
						_digest_action_bar.visible = false
				else:
					_select_digest_row(item_id, "manual")
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0
	elif event is InputEventScreenTouch:
		if event.pressed:
			_digest_hold_timer = 0.0
			_digest_hold_id    = item_id
		else:
			if _digest_hold_id == item_id and _digest_hold_timer < 0.6:
				if _digest_selected_id == item_id and _digest_mode == "manual":
					_digest_selected_id = ""
					_highlight_digest_row("")
					if _digest_action_bar != null:
						_digest_action_bar.visible = false
				else:
					_select_digest_row(item_id, "manual")
			_digest_hold_id    = ""
			_digest_hold_timer = 0.0


func _select_digest_row(item_id: String, mode: String = "manual") -> void:
	_digest_selected_id = item_id
	_digest_mode = mode
	_highlight_digest_row(item_id)
	_digest_pct = 1.0 if mode == "manual" else _digest_auto_ids.get(item_id + "_pct", 1.0)
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

	var amount: int = 0
	if game_state != null and game_state.has_method("get_amount"):
		amount = int(game_state.call("get_amount", _digest_selected_id))

	var selected_amt: int   = int(floor(amount * _digest_pct))
	var nutrient_yield: int = int(round(selected_amt * _digest_selected_value))
	var res_name := _pretty_res(_digest_selected_id)
	var pct_int := int(_digest_pct * 100)

	# Mode label
	if _digest_action_lbl != null:
		if _digest_mode == "auto":
			_digest_action_lbl.text = "%s  —  Auto-digest %d%% of incoming" % [res_name, pct_int]
		else:
			_digest_action_lbl.text = res_name

	# Amount label (top-right)
	var lbl_amt: Label = _digest_action_bar.find_child("LblSelectedAmt", true, false) as Label
	if lbl_amt != null:
		if _digest_mode == "auto":
			lbl_amt.text = "%d%%" % pct_int
		else:
			lbl_amt.text = _fmt_int(selected_amt)

	# Value label (bottom-right, under amount)
	var lbl_val: Label = _digest_action_bar.find_child("LblSelectedVal", true, false) as Label
	if lbl_val != null:
		if _digest_mode == "auto":
			lbl_val.text = "of new stock"
		else:
			lbl_val.text = "%s nutrients" % _fmt_int(nutrient_yield)

	# Digest button
	if _digest_action_btn != null:
		if _digest_mode == "auto":
			var is_auto: bool = _digest_auto_ids.get(_digest_selected_id, false)
			_digest_action_btn.text = "Auto ON" if is_auto else "Enable"
		else:
			_digest_action_btn.text = "Digest"


func _on_digest_slider_changed(value: float) -> void:
	_digest_pct = clampf(value, 0.0, 1.0)
	_update_digest_action_bar()


func _toggle_digest_auto(item_id: String) -> void:
	var was_auto: bool = _digest_auto_ids.get(item_id, false)
	_digest_auto_ids[item_id] = not was_auto
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

	if _digest_mode == "auto":
		# Toggle auto and save the pct
		_toggle_digest_auto(_digest_selected_id)
		_digest_auto_ids[_digest_selected_id + "_pct"] = _digest_pct
		_update_digest_action_bar()
		return

	# Manual digest
	var amount: int = int(game_state.call("get_amount", _digest_selected_id))
	var digest_amt: int = max(1, int(floor(amount * _digest_pct)))
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
	discoveries_list = discoveries_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if discoveries_list == null:
		return

	discoveries_feedback = Label.new()
	discoveries_feedback.name = "DiscoveriesFeedback"
	discoveries_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discoveries_feedback.text = ""
	discoveries_list.add_child(discoveries_feedback)


func _refresh_panel_access_ui() -> void:
	var can_show_discoveries := false
	var can_show_refinery    := false
	if game_state != null:
		if game_state.has_method("can_show_discoveries_tab"):
			can_show_discoveries = bool(game_state.call("can_show_discoveries_tab"))
		if game_state.has_method("is_refinery_unlocked"):
			can_show_refinery = bool(game_state.call("is_refinery_unlocked"))

	if btn_discoveries != null:
		btn_discoveries.modulate.a = 1.0 if can_show_discoveries else 0.3
		btn_discoveries.disabled   = not can_show_discoveries
	if btn_refinery != null:
		btn_refinery.modulate.a = 1.0 if can_show_refinery else 0.3
		btn_refinery.disabled   = not can_show_refinery

	if not can_show_refinery and _open_panel == refinery_panel:
		_close_current()

	_redraw_nav_buttons()


func _clear_discoveries_rows() -> void:
	if discoveries_list == null:
		return
	for child in discoveries_list.get_children():
		if child == discoveries_feedback:
			continue
		child.queue_free()


func _refresh_discoveries_panel() -> void:
	if discoveries_list == null or game_state == null:
		return
	_clear_discoveries_rows()
	if discoveries_feedback != null and discoveries_feedback.get_parent() == null:
		discoveries_list.add_child(discoveries_feedback)
	if discoveries_feedback != null and discoveries_feedback.text == "":
		discoveries_feedback.text = "Spend physical resources to unlock discoveries for this run."

	if not game_state.has_method("can_show_discoveries_tab") or not bool(game_state.call("can_show_discoveries_tab")):
		if discoveries_feedback != null:
			discoveries_feedback.text = "Connect a second node to unlock Discoveries."
		return

	if not game_state.has_method("get_discovery_ui_entries"):
		return
	var entries = game_state.call("get_discovery_ui_entries")
	if typeof(entries) != TYPE_ARRAY:
		return
	for entry_variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		discoveries_list.add_child(_make_discovery_card(entry))


func _make_discovery_card(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	var level: int = int(entry.get("level", 0))
	var max_level: int = int(entry.get("max_level", 1))
	var repeatable: bool = bool(entry.get("repeatable", false))
	var title_text: String = str(entry.get("name", ""))
	if repeatable:
		title_text += "  Lv %s/%s" % [level, max_level]
	title.text = title_text
	box.add_child(title)

	var effect := Label.new()
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.text = str(entry.get("effect_text", ""))
	effect.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
	box.add_child(effect)

	var cost := Label.new()
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.text = "Cost: " + str(entry.get("cost_text", "—"))
	box.add_child(cost)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status_text := str(entry.get("status_text", ""))
	if bool(entry.get("complete", false)):
		status_text = "Complete"
	elif bool(entry.get("can_buy", false)):
		status_text = "Ready"
	status.text = status_text
	row.add_child(status)

	var buy_btn := Button.new()
	buy_btn.text = "Buy" if not repeatable else "Buy Lv"
	buy_btn.disabled = not bool(entry.get("can_buy", false))
	var discovery_id: String = str(entry.get("id", ""))
	buy_btn.pressed.connect(func(): _on_discovery_buy_pressed(discovery_id))
	row.add_child(buy_btn)

	return box


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

	if refinery_tabs_row != null and refinery_tabs_row.get_parent() == null:
		refinery_list.add_child(refinery_tabs_row)
	if refinery_feedback != null and refinery_feedback.get_parent() == null:
		refinery_list.add_child(refinery_feedback)

	if refinery_feedback != null and refinery_feedback.text == "":
		refinery_feedback.text = "Assign recipes to refinery slots. Slots repeat automatically while ingredients are available."

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

		var slot_header := Label.new()
		slot_header.text = "Compounds"
		refinery_list.add_child(slot_header)

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

		var slot_header2 := Label.new()
		slot_header2.text = "Solutions"
		refinery_list.add_child(slot_header2)

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
		return "Cycle Recipe (Idle)"
	return "Cycle Recipe (%s)" % recipe_name


func _make_refinery_slot_card(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Refinery Slot %s" % str(entry.get("slot_number", 0))
	box.add_child(title)

	var recipe_name := str(entry.get("recipe_name", "Idle"))
	var recipe := Label.new()
	recipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe.text = "Recipe: %s" % recipe_name
	box.add_child(recipe)

	var input_label := Label.new()
	input_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_label.text = "Input: %s" % str(entry.get("input_summary", "—"))
	box.add_child(input_label)

	var output_label := Label.new()
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_label.text = "Output: %s" % str(entry.get("output_summary", "—"))
	box.add_child(output_label)

	var pct := int(entry.get("progress_pct", 0))
	var progress_bar := Label.new()
	progress_bar.text = "Progress: %s %s%%" % [_make_refinery_progress_bar(pct), pct]
	box.add_child(progress_bar)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Status: %s • Completed %s" % [
		str(entry.get("status", "Idle")),
		str(entry.get("completed_count", 0))
	]
	box.add_child(status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var cycle_btn := Button.new()
	cycle_btn.text = _refinery_recipe_cycle_label(recipe_name)
	var slot_number: int = int(entry.get("slot_number", 0))
	cycle_btn.pressed.connect(func(): _on_refinery_cycle_recipe_pressed(slot_number))
	row.add_child(cycle_btn)

	var repeat_btn := Button.new()
	repeat_btn.text = "Repeat: %s" % ("On" if bool(entry.get("repeat_enabled", true)) else "Off")
	repeat_btn.pressed.connect(func(): _on_refinery_toggle_repeat_pressed(slot_number))
	row.add_child(repeat_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(func(): _on_refinery_clear_recipe_pressed(slot_number))
	row.add_child(clear_btn)

	return box


func _make_refinery_recipe_unlock_card(recipe_id: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var compound_defs: Dictionary = game_state.get("compound_defs")
	var recipe_def: Dictionary = compound_defs.get(recipe_id, {}) as Dictionary
	var recipe_name := str(recipe_def.get("name", recipe_id))

	var title := Label.new()
	title.text = recipe_name
	box.add_child(title)

	var cost_value := -1
	if game_state.has_method("get_compound_unlock_cost"):
		cost_value = int(game_state.call("get_compound_unlock_cost", recipe_id))

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var check := {}
	if game_state.has_method("can_unlock_compound_recipe"):
		check = game_state.call("can_unlock_compound_recipe", recipe_id) as Dictionary

	if cost_value <= 0:
		status.text = "Cost: --"
	else:
		status.text = "Cost: %s Nutrients" % _fmt_int(cost_value)

	if not check.is_empty():
		var reason := str(check.get("reason", ""))
		if reason != "":
			if bool(check.get("ok", false)):
				status.text += " • Ready"
			elif reason != "Already unlocked.":
				status.text += " • %s" % reason

	box.add_child(status)

	var btn := Button.new()
	if cost_value > 0:
		btn.text = "Unlock (%s)" % _fmt_int(cost_value)
	else:
		btn.text = "Unlock"

	var can_unlock := false
	if game_state.has_method("can_unlock_compound_recipe"):
		var check2: Dictionary = game_state.call("can_unlock_compound_recipe", recipe_id) as Dictionary
		can_unlock = bool(check2.get("ok", false))

	btn.disabled = not can_unlock
	btn.pressed.connect(func() -> void:
		_on_refinery_unlock_compound_pressed(recipe_id)
	)
	box.add_child(btn)

	return box


func _make_synthesis_slot_card(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Synthesis Slot %s" % str(entry.get("slot_number", 0))
	box.add_child(title)

	var recipe_name := str(entry.get("recipe_name", "Idle"))
	var recipe := Label.new()
	recipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe.text = "Recipe: %s" % recipe_name
	box.add_child(recipe)

	var input_label := Label.new()
	input_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_label.text = "Input: %s" % str(entry.get("input_summary", "—"))
	box.add_child(input_label)

	var output_label := Label.new()
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_label.text = "Output: %s" % str(entry.get("output_summary", "—"))
	box.add_child(output_label)

	var pct := int(entry.get("progress_pct", 0))
	var progress_bar := Label.new()
	progress_bar.text = "Progress: %s %s%%" % [_make_refinery_progress_bar(pct), pct]
	box.add_child(progress_bar)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Status: %s • Completed %s" % [
		str(entry.get("status", "Idle")),
		str(entry.get("completed_count", 0))
	]
	box.add_child(status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var slot_number: int = int(entry.get("slot_number", 0))

	var cycle_btn := Button.new()
	cycle_btn.text = _refinery_recipe_cycle_label(recipe_name)
	cycle_btn.pressed.connect(func(): _on_synthesis_cycle_recipe_pressed(slot_number))
	row.add_child(cycle_btn)

	var repeat_btn := Button.new()
	repeat_btn.text = "Repeat: %s" % ("On" if bool(entry.get("repeat_enabled", true)) else "Off")
	repeat_btn.pressed.connect(func(): _on_synthesis_toggle_repeat_pressed(slot_number))
	row.add_child(repeat_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(func(): _on_synthesis_clear_recipe_pressed(slot_number))
	row.add_child(clear_btn)

	return box


func _make_synth_unlock_card(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Unlock Synthesis Slot %s" % str(entry.get("slot_number", 0))
	box.add_child(title)

	var cost := Label.new()
	cost.text = "Cost: %s Nutrients" % _fmt_int(int(entry.get("cost", 0)))
	box.add_child(cost)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = str(entry.get("status", ""))
	box.add_child(status)

	var btn := Button.new()
	btn.text = "Unlock Slot"
	btn.disabled = not bool(entry.get("can_unlock", false))
	var slot_number: int = int(entry.get("slot_number", 0))
	btn.pressed.connect(func(): _on_synth_unlock_slot_pressed(slot_number))
	box.add_child(btn)

	return box


func _make_refinery_unlock_card(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Unlock Refinery Slot %s" % str(entry.get("slot_number", 0))
	box.add_child(title)

	var cost := Label.new()
	cost.text = "Cost: %s Nutrients" % _fmt_int(int(entry.get("cost", 0)))
	box.add_child(cost)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = str(entry.get("status", ""))
	box.add_child(status)

	var btn := Button.new()
	btn.text = "Unlock Slot"
	btn.disabled = not bool(entry.get("can_unlock", false))
	var slot_number: int = int(entry.get("slot_number", 0))
	btn.pressed.connect(func(): _on_refinery_unlock_slot_pressed(slot_number))
	box.add_child(btn)

	return box


func _make_synth_recipe_unlock_card(recipe_id: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var solution_defs: Dictionary = game_state.get("solution_defs")
	var recipe_def: Dictionary = solution_defs.get(recipe_id, {}) as Dictionary
	var recipe_name := str(recipe_def.get("name", recipe_id))

	var title := Label.new()
	title.text = recipe_name
	box.add_child(title)

	var cost_value := -1
	if game_state.has_method("get_solution_unlock_cost"):
		cost_value = int(game_state.call("get_solution_unlock_cost", recipe_id))

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var check := {}
	if game_state.has_method("can_unlock_solution_recipe"):
		check = game_state.call("can_unlock_solution_recipe", recipe_id) as Dictionary

	if cost_value <= 0:
		status.text = "Cost: --"
	else:
		status.text = "Cost: %s Nutrients" % _fmt_int(cost_value)

	if not check.is_empty():
		var reason := str(check.get("reason", ""))
		if reason != "":
			if bool(check.get("ok", false)):
				status.text += " • Ready"
			elif reason != "Already unlocked.":
				status.text += " • %s" % reason

	box.add_child(status)

	var btn := Button.new()
	if cost_value > 0:
		btn.text = "Unlock (%s)" % _fmt_int(cost_value)
	else:
		btn.text = "Unlock"

	var can_unlock := false
	if game_state.has_method("can_unlock_solution_recipe"):
		var check2: Dictionary = game_state.call("can_unlock_solution_recipe", recipe_id) as Dictionary
		can_unlock = bool(check2.get("ok", false))

	btn.disabled = not can_unlock
	btn.pressed.connect(func() -> void:
		_on_refinery_unlock_solution_pressed(recipe_id)
	)

	box.add_child(btn)

	return box


func _on_refinery_cycle_recipe_pressed(slot_number: int) -> void:
	if game_state == null or not game_state.has_method("cycle_refinery_recipe"):
		return

	var recipe_id: String = str(game_state.call("cycle_refinery_recipe", slot_number))
	var recipe_name := "Idle"

	if recipe_id != "":
		var compound_defs: Dictionary = game_state.get("compound_defs")
		var recipe_def: Dictionary = compound_defs.get(recipe_id, {}) as Dictionary
		recipe_name = str(recipe_def.get("name", recipe_id))

	if refinery_feedback != null:
		refinery_feedback.text = "Slot %s recipe: %s" % [slot_number, recipe_name]
	_refresh_refinery_panel()


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
	if game_state == null or not game_state.has_method("cycle_synth_recipe"):
		return

	var recipe_id: String = str(game_state.call("cycle_synth_recipe", slot_number))
	var recipe_name := "Idle"

	if recipe_id != "":
		var solution_defs: Dictionary = game_state.get("solution_defs")
		var recipe_def: Dictionary = solution_defs.get(recipe_id, {}) as Dictionary
		recipe_name = str(recipe_def.get("name", recipe_id))

	if refinery_feedback != null:
		refinery_feedback.text = "Synthesis slot %s recipe: %s" % [slot_number, recipe_name]
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
	settings_list = settings_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if settings_list == null:
		return

	settings_feedback = Label.new()
	settings_feedback.name = "SettingsFeedback"
	settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_feedback.text = "Manage save data for this run."
	settings_list.add_child(settings_feedback)

	settings_btn_save = Button.new()
	settings_btn_save.text = "Save Now"
	settings_btn_save.pressed.connect(_on_settings_save_pressed)
	settings_list.add_child(settings_btn_save)

	settings_btn_load = Button.new()
	settings_btn_load.text = "Load Save"
	settings_btn_load.pressed.connect(_on_settings_load_pressed)
	settings_list.add_child(settings_btn_load)

	settings_btn_new_game = Button.new()
	settings_btn_new_game.text = "New Game"
	settings_btn_new_game.pressed.connect(_on_settings_new_game_pressed)
	settings_list.add_child(settings_btn_new_game)

	_refresh_settings_panel()


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
	# Dynamic resource rows are built in _refresh_nodepanel_top_table.
	# We only need to hide the static grid since we'll build rows in code.
	var grid: Control = node_panel.find_child("GridContainer", true, false) as Control
	if grid != null:
		grid.visible = false


var _resource_rows_container: VBoxContainer = null
var _resource_row_labels: Array = []   # Array of {pool: Label, rate: Label} per output
var _resource_rows_node_id: String = ""  # which node the rows were built for

func _get_or_create_resource_rows() -> VBoxContainer:
	if is_instance_valid(_resource_rows_container):
		return _resource_rows_container
	# Insert a VBoxContainer right after the GridContainer (or header)
	var vbox: Control = node_panel.find_child("VBoxContainer", true, false) as Control
	if vbox == null:
		return null
	var container := VBoxContainer.new()
	container.name = "ResourceRows"
	# Find grid position and insert after it
	var grid: Control = node_panel.find_child("GridContainer", true, false) as Control
	var insert_pos: int = 0
	if grid != null:
		insert_pos = grid.get_index() + 1
	vbox.add_child(container)
	vbox.move_child(container, insert_pos)
	_resource_rows_container = container
	return container


func _refresh_nodepanel_top_table() -> void:
	if _selected_node_id == "" or game_state == null:
		return

	var container := _get_or_create_resource_rows()
	if container == null:
		return

	# Only rebuild row structure when the selected node changes
	if _resource_rows_node_id != _selected_node_id:
		_resource_rows_node_id = _selected_node_id
		_build_resource_rows(container)

	# Always update the live values (pool, rate) without rebuilding
	_update_resource_row_values()


func _build_resource_rows(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.free()
	_resource_row_labels.clear()

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

	# Header row
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)

	for hdr_data in [["Resource", 0, HORIZONTAL_ALIGNMENT_LEFT], ["Split", 42, HORIZONTAL_ALIGNMENT_RIGHT], ["Rate/s", 54, HORIZONTAL_ALIGNMENT_RIGHT], ["Pool", 54, HORIZONTAL_ALIGNMENT_RIGHT]]:
		var hl := Label.new()
		hl.text = hdr_data[0]
		hl.add_theme_font_size_override("font_size", 11)
		hl.add_theme_color_override("font_color", ThemeManager.c("text_muted"))
		hl.custom_minimum_size = Vector2(int(hdr_data[1]), 0)
		hl.horizontal_alignment = hdr_data[2]
		if int(hdr_data[1]) == 0:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(hl)
	container.add_child(hdr)

	for o_variant in outputs:
		var o: Dictionary = o_variant as Dictionary
		var res_id: String = str(o.get("res", ""))
		if res_id == "": continue
		var weight: float = float(o.get("weight", 1.0))
		var pct: int = int(round(weight / sum_w * 100.0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var dot_tex := _make_circle_texture(12, false)
		var dot := TextureRect.new()
		dot.texture = dot_tex
		dot.modulate = _node_color_for_id(res_id)
		dot.custom_minimum_size = Vector2(12, 12)
		dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(dot)

		var lbl_name := Label.new()
		lbl_name.text = _pretty_res(res_id)
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl_name)

		var lbl_pct := Label.new()
		lbl_pct.text = str(pct) + "%"
		lbl_pct.custom_minimum_size = Vector2(42, 0)
		lbl_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_pct.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl_pct)

		var lbl_rate := Label.new()
		lbl_rate.text = "—"
		lbl_rate.custom_minimum_size = Vector2(54, 0)
		lbl_rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_rate.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl_rate)

		var lbl_pool := Label.new()
		lbl_pool.text = "0"
		lbl_pool.custom_minimum_size = Vector2(54, 0)
		lbl_pool.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_pool.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl_pool)

		container.add_child(row)
		_resource_row_labels.append({
			"res_id": res_id,
			"weight": weight,
			"sum_w": sum_w,
			"rate_lbl": lbl_rate,
			"pool_lbl": lbl_pool
		})


func _update_resource_row_values() -> void:
	if _resource_row_labels.is_empty() or game_state == null:
		return

	var pool_amounts: Dictionary = {}
	if game_state.has_method("get_node_pool_amounts"):
		var pa = game_state.call("get_node_pool_amounts", _selected_node_id)
		if typeof(pa) == TYPE_DICTIONARY:
			pool_amounts = pa

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
		var pool_val: int   = int(pool_amounts.get(res_id, 0))

		if rate_lbl != null and is_instance_valid(rate_lbl):
			rate_lbl.text = _fmt_rate(res_rate)
		if pool_lbl != null and is_instance_valid(pool_lbl):
			pool_lbl.text = _fmt_int(pool_val)


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
	var prod_row: Control = node_panel.find_child("RowProduction", true, false) as Control
	if prod_row == null:
		return
	prod_value = prod_row.find_child("LblProdValue", true, false) as Label


func _refresh_nodepanel_production() -> void:
	if prod_value == null:
		return
	if _selected_node_id == "":
		return
	if game_state == null or not game_state.has_method("get_node_rate_ui"):
		return

	var rui = game_state.call("get_node_rate_ui", _selected_node_id)
	if typeof(rui) != TYPE_DICTIONARY:
		return

	var base_r: float = float(rui.get("base_rate", 0.0))
	var eff_r: float = float(rui.get("effective_rate", 0.0))
	prod_value.text = _fmt_rate(base_r) + "/s → " + _fmt_rate(eff_r) + "/s"


# ---------------- NodePanel (Upgrades) ----------------

func _bind_nodepanel_upgrades() -> void:
	upgrades_box = node_panel.find_child("UpgradesBox", true, false) as Control
	if upgrades_box == null:
		push_warning("NodePanel: UpgradesBox not found.")
		return

	row_yield     = upgrades_box.find_child("RowYield",     true, false) as Control
	row_frequency = upgrades_box.find_child("RowFrequency", true, false) as Control
	row_travel    = upgrades_box.find_child("RowTravel",    true, false) as Control
	row_carry     = upgrades_box.find_child("RowCarry",     true, false) as Control

	if row_yield != null:
		yield_name = row_yield.find_child("LblName",    true, false) as Label
		yield_lvl  = row_yield.find_child("LblLevel",   true, false) as Label
		yield_val  = row_yield.find_child("LblValue",   true, false) as Label
		yield_btn  = row_yield.find_child("BtnUpgrade", true, false) as Button
		if yield_btn != null and not yield_btn.pressed.is_connected(_on_upgrade_yield):
			yield_btn.pressed.connect(_on_upgrade_yield)

	if row_frequency != null:
		frequency_name = row_frequency.find_child("LblName",    true, false) as Label
		frequency_lvl  = row_frequency.find_child("LblLevel",   true, false) as Label
		frequency_val  = row_frequency.find_child("LblValue",   true, false) as Label
		frequency_btn  = row_frequency.find_child("BtnUpgrade", true, false) as Button
		if frequency_btn != null and not frequency_btn.pressed.is_connected(_on_upgrade_frequency):
			frequency_btn.pressed.connect(_on_upgrade_frequency)

	if row_travel != null:
		travel_name = row_travel.find_child("LblName",    true, false) as Label
		travel_lvl  = row_travel.find_child("LblLevel",   true, false) as Label
		travel_val  = row_travel.find_child("LblValue",   true, false) as Label
		travel_btn  = row_travel.find_child("BtnUpgrade", true, false) as Button
		if travel_btn != null and not travel_btn.pressed.is_connected(_on_upgrade_travel):
			travel_btn.pressed.connect(_on_upgrade_travel)

	if row_carry != null:
		carry_name = row_carry.find_child("LblName",    true, false) as Label
		carry_lvl  = row_carry.find_child("LblLevel",   true, false) as Label
		carry_val  = row_carry.find_child("LblValue",   true, false) as Label
		carry_btn  = row_carry.find_child("BtnUpgrade", true, false) as Button
		if carry_btn != null and not carry_btn.pressed.is_connected(_on_upgrade_carry):
			carry_btn.pressed.connect(_on_upgrade_carry)


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


func _refresh_nodepanel_upgrades() -> void:
	if _selected_node_id == "" or game_state == null:
		return
	if not game_state.has_method("get_node_upgrade_ui"):
		return

	var ui = game_state.call("get_node_upgrade_ui", _selected_node_id)
	if typeof(ui) != TYPE_DICTIONARY:
		return

	# Yield row
	if yield_name != null: yield_name.text = str(ui.get("yield_label", "Yield Rate"))
	if yield_lvl  != null: yield_lvl.text  = "Lv " + str(int(ui.get("yield_level", 1)))
	if yield_val  != null: yield_val.text  = str(ui.get("yield_value", "0.25/s"))
	if yield_btn  != null: yield_btn.text  = "UPGRADE  " + _fmt_int(int(ui.get("yield_cost", 0)))

	# Frequency row
	if frequency_name != null: frequency_name.text = str(ui.get("frequency_label", "Pulse Frequency"))
	if frequency_lvl  != null: frequency_lvl.text  = "Lv " + str(int(ui.get("frequency_level", 1)))
	if frequency_val  != null: frequency_val.text  = str(ui.get("frequency_value", "1.0/s"))
	if frequency_btn  != null: frequency_btn.text  = "UPGRADE  " + _fmt_int(int(ui.get("frequency_cost", 0)))

	# Speed row
	if travel_name != null: travel_name.text = str(ui.get("speed_label", "Pulse Speed"))
	if travel_lvl  != null: travel_lvl.text  = "Lv " + str(int(ui.get("speed_level", 1)))
	if travel_val  != null: travel_val.text  = str(ui.get("speed_value", "1.0×"))
	if travel_btn  != null: travel_btn.text  = "UPGRADE  " + _fmt_int(int(ui.get("speed_cost", 0)))

	# Carry row
	if carry_name != null: carry_name.text = str(ui.get("carry_label", "Pulse Capacity"))
	if carry_lvl  != null: carry_lvl.text  = "Lv " + str(int(ui.get("carry_level", 1)))
	if carry_val  != null: carry_val.text  = str(ui.get("carry_value", "5"))
	if carry_btn  != null: carry_btn.text  = "UPGRADE  " + _fmt_int(int(ui.get("carry_cost", 0)))


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
	return [upgrades_panel, discoveries_panel, refinery_panel, digest_panel, settings_panel, node_panel]


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
		_refresh_digest_panel()
	if panel == discoveries_panel:
		_refresh_discoveries_panel()
	if panel == refinery_panel:
		_refresh_refinery_panel()
	if panel == settings_panel:
		_refresh_settings_panel()
	if panel == node_panel:
		_refresh_nodepanel_all()

	var vp_h       := get_viewport_rect().size.y
	var open_y     := vp_h - PANEL_H - _bar_h
	var pc         := _panel_container if _panel_container != null else panel

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(dimmer, "modulate:a", 1.0, 0.12)
	_tween.parallel().tween_property(pc, "position:y", open_y, 0.18)


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

func _input(event: InputEvent) -> void:
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
		return

	# ── Scroll-wheel zoom (desktop / testing) ──────────────────────────────
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _open_panel == null:
				_map_apply_zoom(1.0 + MAP_ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _open_panel == null:
				_map_apply_zoom(1.0 / (1.0 + MAP_ZOOM_STEP), event.position)
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
		if is_press_start or is_motion:
			return

	# Ignore taps that land in the bottom bar
	var vp_h := get_viewport_rect().size.y
	if (is_press_start or is_press_end) and ev_pos.y >= vp_h - _bar_h:
		return

	# ── Press start: begin drag tracking ──────────────────────────────────
	if is_press_start:
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


# ── Node tap selection (extracted from old _input) ────────────────────────────

func _try_select_node(screen_pos: Vector2) -> void:
	var canvas_xform := get_viewport().get_canvas_transform()

	# If a panel is open, block any tap that lands inside the panel's screen rect
	if _open_panel != null:
		var panel_rect := _open_panel.get_global_rect()
		if panel_rect.has_point(screen_pos):
			return

	for e in _node_list:
		var node: Node2D    = e["node"]
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
	for child in nodes_container.get_children():
		if child.get_meta("runtime_spawned", false):
			child.queue_free()

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
		var node_ref: Node2D = e.get("node", null) as Node2D
		if node_ref == null:
			continue

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
		var node_ref: Node2D = e.get("node", null) as Node2D
		if node_ref == null:
			continue

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
				lbl.top_level = true
				lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", 12)
				lbl.add_theme_color_override("font_color", ThemeManager.c("accent"))
				lbl.add_theme_color_override("font_outline_color", ThemeManager.c("bg_deep"))
				lbl.add_theme_constant_override("outline_size", 3)
				nodes_container.add_child(lbl)
				_node_cost_labels[node_id] = lbl

			lbl.text = _fmt_int(cost)
			# Position above the node sprite
			lbl.global_position = node_ref.global_position + Vector2(-lbl.size.x * 0.5, -36)
			lbl.visible = true
		else:
			# Hide cost label when unlocked or not visible
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