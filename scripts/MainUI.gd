extends Control

const PANEL_H := 864.0
const PANEL_MARGIN := 8.0

# Tap forgiveness in SCREEN pixels (increase if needed)
const NODE_HIT_RADIUS := 110.0

# UI refresh rate (seconds). Keeps labels responsive without updating every frame.
const UI_REFRESH_DT := 0.20

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

# Node panel table cells (your exact names)
@onready var cell_resource: Label  = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/GridContainer/Cell_Resource
@onready var cell_yield: Label     = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/GridContainer/Cell_Yield
@onready var cell_rate: Label      = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/GridContainer/Cell_Rate
@onready var cell_harvested: Label = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/GridContainer/Cell_Harvested

# Bottom buttons
@onready var btn_upgrades: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnUpgrades
@onready var btn_discoveries: BaseButton = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnDiscoveries
@onready var btn_refinery: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnRefinery
@onready var btn_digest: BaseButton      = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnDigest
@onready var btn_settings: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnSettings

# Map nodes
@onready var n_damp: Node2D    = $MapLayer/Nodes/Node_DampSoil
@onready var n_log: Node2D     = $MapLayer/Nodes/Node_RottingLog
@onready var n_compost: Node2D = $MapLayer/Nodes/Node_CompostHeap
@onready var n_root: Node2D    = $MapLayer/Nodes/Node_RootCluster

# Selection feedback (Sprite2D named SelectionRing under MapLayer)
@onready var selection_ring: Sprite2D = $MapLayer/SelectionRing

# Currency labels (resolved in _ready via find_child to avoid brittle paths)
var lbl_nutrients: Label = null
var lbl_glowcaps: Label = null
var lbl_strain: Label = null

var _tween: Tween
var _open_panel: Control = null
var _bar_h: float = 0.0

# Node tap map (stores node_id used by GameState)
var _node_list: Array = []

# Selection state
var _selected_node: Node2D = null
var _selected_node_id: String = ""
var _node_pop_tween: Tween = null

# Game state singleton (autoload)
var game_state: Node = null

# UI refresh accumulator
var _ui_accum := 0.0

func _ready() -> void:
	set_process_input(true)
	set_process(true)

	await get_tree().process_frame
	_bar_h = bottom_bar.size.y

	# Autoload access
	game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		push_warning("GameState autoload not found at /root/GameState. Currency + node stats won't update.")

	_bind_currency_labels()

	_node_list = [
		{"id": "damp_soil",    "node": n_damp,    "name": "Damp Soil"},
		{"id": "rotting_log",  "node": n_log,     "name": "Rotting Log"},
		{"id": "compost_heap", "node": n_compost, "name": "Compost Heap"},
		{"id": "root_cluster", "node": n_root,    "name": "Root Cluster"},
	]

	selection_ring.visible = false

	# Dimmer excludes bottom bar so buttons stay clickable
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.offset_bottom = -_bar_h
	dimmer.visible = false
	dimmer.modulate.a = 0.0
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not dimmer.gui_input.is_connected(_on_dimmer_gui_input):
		dimmer.gui_input.connect(_on_dimmer_gui_input)

	# Panels start hidden/closed
	for p in _all_panels():
		p.visible = false
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_panel_closed(p)

	# Wire bottom buttons
	btn_upgrades.pressed.connect(func(): _toggle_panel(upgrades_panel))
	btn_discoveries.pressed.connect(func(): _toggle_panel(discoveries_panel))
	btn_refinery.pressed.connect(func(): _toggle_panel(refinery_panel))
	btn_digest.pressed.connect(func(): _toggle_panel(digest_panel))
	btn_settings.pressed.connect(func(): _toggle_panel(settings_panel))

	node_close.pressed.connect(_close_current)

	_refresh_currency_ui()

func _process(dt: float) -> void:
	if selection_ring.visible and _selected_node != null:
		selection_ring.global_position = _selected_node.global_position

	_ui_accum += dt
	if _ui_accum >= UI_REFRESH_DT:
		_ui_accum = 0.0
		_refresh_currency_ui()
		if _open_panel == node_panel and _selected_node_id != "":
			_refresh_node_panel_row()

func _bind_currency_labels() -> void:
	var cs := find_child("CurrencyStack", true, false)
	if cs == null:
		push_warning("CurrencyStack not found; currency UI will not update.")
		return

	lbl_nutrients = _find_row_value_label(cs, "RowNutrients")
	lbl_glowcaps = _find_row_value_label(cs, "RowPremium")
	lbl_strain = _find_row_value_label(cs, "RowPrestige")

	if lbl_nutrients == null or lbl_glowcaps == null or lbl_strain == null:
		push_warning("Currency Value labels not found. Check names: RowNutrients/RowPremium/RowPrestige + child 'Value'.")

func _find_row_value_label(cs: Node, row_name: String) -> Label:
	var row := cs.find_child(row_name, true, false)
	if row == null:
		return null
	var val := row.find_child("Value", true, false)
	if val is Label:
		return val
	return null

func _all_panels() -> Array[Control]:
	return [upgrades_panel, discoveries_panel, refinery_panel, digest_panel, settings_panel, node_panel]

func _toggle_panel(panel: Control) -> void:
	if _open_panel == panel:
		_close_current()
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

	var open_bottom := -_bar_h
	var open_top := -(PANEL_H + _bar_h)

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(dimmer, "modulate:a", 1.0, 0.12)
	_tween.parallel().tween_property(panel, "offset_bottom", open_bottom, 0.18)
	_tween.parallel().tween_property(panel, "offset_top", open_top, 0.18)

func _close_current() -> void:
	if _open_panel == null:
		return

	_kill_tween()
	var panel := _open_panel

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(dimmer, "modulate:a", 0.0, 0.10)
	_tween.parallel().tween_property(panel, "offset_top", PANEL_MARGIN, 0.14)
	_tween.parallel().tween_property(panel, "offset_bottom", PANEL_H + PANEL_MARGIN, 0.14)

	_tween.finished.connect(func():
		panel.visible = false
		_open_panel = null
		dimmer.visible = false
		dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if panel == node_panel:
			_clear_node_selection()
	)

func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_current()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _open_panel != null:
			_close_current()
			get_viewport().set_input_as_handled()
		return

	if _open_panel != null:
		return

	var pressed := false
	var screen_pos := Vector2.ZERO

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		screen_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		screen_pos = event.position

	if not pressed:
		return

	var vp_h := get_viewport_rect().size.y
	if screen_pos.y >= vp_h - _bar_h:
		return

	var canvas_xform := get_viewport().get_canvas_transform()

	for e in _node_list:
		var node: Node2D = e["node"]
		var node_screen := canvas_xform * node.global_position
		if node_screen.distance_to(screen_pos) <= NODE_HIT_RADIUS:
			node_title.text = e["name"]
			_selected_node_id = str(e["id"])
			_select_node(node)
			_refresh_node_panel_row()
			_open(node_panel)
			get_viewport().set_input_as_handled()
			return

func _select_node(node: Node2D) -> void:
	_selected_node = node
	selection_ring.visible = true
	selection_ring.global_position = node.global_position
	_play_node_pop(node)

func _clear_node_selection() -> void:
	_selected_node = null
	_selected_node_id = ""
	selection_ring.visible = false

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

func _refresh_currency_ui() -> void:
	if game_state == null or not game_state.has_method("get_amount"):
		return
	if lbl_nutrients == null or lbl_glowcaps == null or lbl_strain == null:
		return

	lbl_nutrients.text = _fmt_int(int(game_state.call("get_amount", "nutrients")))
	lbl_glowcaps.text  = _fmt_int(int(game_state.call("get_amount", "glowcaps")))
	lbl_strain.text    = _fmt_int(int(game_state.call("get_amount", "strain_points")))

func _refresh_node_panel_row() -> void:
	if game_state == null or not game_state.has_method("get_node_display_row"):
		return
	if _selected_node_id == "":
		return

	var row = game_state.call("get_node_display_row", _selected_node_id)
	if typeof(row) != TYPE_DICTIONARY:
		return

	var res_id := str(row.get("resource", ""))
	cell_resource.text = _pretty_res(res_id)
	cell_yield.text = str(row.get("yield_percent", "100%"))
	cell_rate.text = str(row.get("rate_text", "0.00/s"))
	cell_harvested.text = str(row.get("harvested_text", "0/0"))

func _pretty_res(res_id: String) -> String:
	match res_id:
		"spores": return "Spores"
		"hyphae": return "Hyphae"
		"cellulose": return "Cellulose"
		"mycelium": return "Mycelium"
		"nutrients": return "Nutrients"
		"glowcaps": return "Glowcaps"
		"strain_points": return "Strain Points"
		_: return res_id.capitalize()

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
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = PANEL_H + PANEL_MARGIN

func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null
