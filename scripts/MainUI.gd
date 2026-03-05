extends Control

const PANEL_H := 864.0
const PANEL_MARGIN := 8.0

const NODE_HIT_RADIUS := 110.0
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

@onready var selection_ring: Sprite2D = $MapLayer/SelectionRing

# Currency labels
var lbl_nutrients: Label = null
var lbl_glowcaps: Label = null
var lbl_strain: Label = null

var _tween: Tween
var _open_panel: Control = null
var _bar_h: float = 0.0

var _node_list: Array = []

var _selected_node: Node2D = null
var _selected_node_id: String = ""
var _node_pop_tween: Tween = null

var game_state: Node = null
var _ui_accum: float = 0.0

# DigestPanel widgets
var digest_lbl_selected: Label = null
var digest_btn_1: Button = null
var digest_btn_all: Button = null

# Nutrients flash
var _nutrients_base_scale: Vector2 = Vector2.ONE
var _nutrients_flash_tween: Tween = null

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
	_bar_h = bottom_bar.size.y

	game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		push_warning("GameState autoload not found at /root/GameState.")

	_bind_currency_labels()

	_node_list = [
		{"id": "damp_soil",    "node": n_damp,    "name": "Damp Soil"},
		{"id": "rotting_log",  "node": n_log,     "name": "Rotting Log"},
		{"id": "compost_heap", "node": n_compost, "name": "Compost Heap"},
		{"id": "root_cluster", "node": n_root,    "name": "Root Cluster"},
	]

	selection_ring.visible = false

	# Dimmer excludes bottom bar
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

	_bind_digest_panel()
	_bind_nodepanel_top_table()
	_bind_nodepanel_production()
	_bind_nodepanel_upgrades()

	if lbl_nutrients != null:
		_nutrients_base_scale = lbl_nutrients.scale

	_refresh_currency_ui()


func _process(dt: float) -> void:
	if selection_ring.visible and _selected_node != null:
		selection_ring.global_position = _selected_node.global_position

	_ui_accum += dt
	if _ui_accum >= UI_REFRESH_DT:
		_ui_accum = 0.0
		_refresh_currency_ui()
		if _open_panel == node_panel and _selected_node_id != "":
			_refresh_nodepanel_all()


# ---------------- DigestPanel ----------------

func _bind_digest_panel() -> void:
	digest_lbl_selected = digest_panel.find_child("LblDigestSelected", true, false) as Label
	digest_btn_1 = digest_panel.find_child("BtnDigest1", true, false) as Button
	digest_btn_all = digest_panel.find_child("BtnDigestAll", true, false) as Button

	if digest_btn_1 != null:
		digest_btn_1.pressed.connect(_on_digest_panel_1_pressed)
	if digest_btn_all != null:
		digest_btn_all.pressed.connect(_on_digest_panel_all_pressed)


func _on_digest_panel_1_pressed() -> void:
	_digest_selected_node_at_cloud(1)


func _on_digest_panel_all_pressed() -> void:
	_digest_selected_node_at_cloud(-1)


func _digest_selected_node_at_cloud(amount: int) -> void:
	if game_state == null:
		return
	if _selected_node_id == "":
		return
	if not game_state.has_method("digest_node_primary") or not game_state.has_method("digest_all_node_primary"):
		return

	var digested: int = 0
	if amount == -1:
		digested = int(game_state.call("digest_all_node_primary", _selected_node_id))
	else:
		digested = int(game_state.call("digest_node_primary", _selected_node_id, amount))

	if digested > 0:
		_flash_nutrients()

	_refresh_currency_ui()
	_refresh_digest_panel_selected()
	_refresh_nodepanel_all()


func _refresh_digest_panel_selected() -> void:
	if digest_lbl_selected == null:
		return
	if _selected_node_id == "":
		digest_lbl_selected.text = "Selected: None"
	else:
		digest_lbl_selected.text = "Selected: " + _selected_node_id


func _flash_nutrients() -> void:
	if lbl_nutrients == null:
		return

	if _nutrients_flash_tween != null and _nutrients_flash_tween.is_running():
		_nutrients_flash_tween.kill()
		_nutrients_flash_tween = null

	lbl_nutrients.scale = _nutrients_base_scale

	_nutrients_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_nutrients_flash_tween.tween_property(lbl_nutrients, "scale", _nutrients_base_scale * 1.12, 0.07)
	_nutrients_flash_tween.tween_property(lbl_nutrients, "scale", _nutrients_base_scale, 0.10)


# ---------------- NodePanel (Top Table) ----------------

func _bind_nodepanel_top_table() -> void:
	var grid: Control = node_panel.find_child("GridContainer", true, false) as Control
	if grid == null:
		push_warning("NodePanel: GridContainer not found.")
		return

	cell_res_icon = grid.find_child("ResIcon", true, false) as TextureRect
	cell_res_name = grid.find_child("ResName", true, false) as Label
	cell_yield = grid.find_child("Cell_Yield", true, false) as Label
	cell_rate = grid.find_child("Cell_Rate", true, false) as Label
	cell_harvested = grid.find_child("Cell_Harvested", true, false) as Label

	if cell_res_icon == null or cell_res_name == null:
		push_warning("NodePanel: ResIcon/ResName not found under GridContainer (check names).")

func _refresh_nodepanel_top_table() -> void:
	if _selected_node_id == "":
		return
	if game_state == null:
		return

	var res_id: String = ""
	if game_state.has_method("get_node_primary_res_id"):
		res_id = str(game_state.call("get_node_primary_res_id", _selected_node_id))

	if cell_res_name != null:
		cell_res_name.text = _pretty_res(res_id)

	if cell_res_icon != null:
		cell_res_icon.texture = _get_res_icon_texture(res_id)

	# Yield %
	if cell_yield != null and game_state.has_method("get_node_upgrade_ui"):
		var u = game_state.call("get_node_upgrade_ui", _selected_node_id)
		if typeof(u) == TYPE_DICTIONARY:
			cell_yield.text = str(u.get("yield_percent", "100%"))

	# Rate (/s) effective
	if cell_rate != null and game_state.has_method("get_node_rate_ui"):
		var rui = game_state.call("get_node_rate_ui", _selected_node_id)
		if typeof(rui) == TYPE_DICTIONARY:
			var eff: float = float(rui.get("effective_rate", 0.0))
			cell_rate.text = _fmt_rate(eff) + "/s"

	# Harvested pooled int
	if cell_harvested != null and game_state.has_method("get_node_primary_pool_amount"):
		cell_harvested.text = str(int(game_state.call("get_node_primary_pool_amount", _selected_node_id)))


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

	row_yield = upgrades_box.find_child("RowYield", true, false) as Control
	row_travel = upgrades_box.find_child("RowTravel", true, false) as Control
	row_carry = upgrades_box.find_child("RowCarry", true, false) as Control

	if row_yield != null:
		yield_name = row_yield.find_child("LblName", true, false) as Label
		yield_lvl  = row_yield.find_child("LblLevel", true, false) as Label
		yield_val  = row_yield.find_child("LblValue", true, false) as Label
		yield_btn  = row_yield.find_child("BtnUpgrade", true, false) as Button
		if yield_btn != null and not yield_btn.pressed.is_connected(_on_upgrade_yield):
			yield_btn.pressed.connect(_on_upgrade_yield)

	if row_travel != null:
		travel_name = row_travel.find_child("LblName", true, false) as Label
		travel_lvl  = row_travel.find_child("LblLevel", true, false) as Label
		travel_val  = row_travel.find_child("LblValue", true, false) as Label
		travel_btn  = row_travel.find_child("BtnUpgrade", true, false) as Button
		if travel_btn != null and not travel_btn.pressed.is_connected(_on_upgrade_travel):
			travel_btn.pressed.connect(_on_upgrade_travel)

	if row_carry != null:
		carry_name = row_carry.find_child("LblName", true, false) as Label
		carry_lvl  = row_carry.find_child("LblLevel", true, false) as Label
		carry_val  = row_carry.find_child("LblValue", true, false) as Label
		carry_btn  = row_carry.find_child("BtnUpgrade", true, false) as Button
		if carry_btn != null and not carry_btn.pressed.is_connected(_on_upgrade_carry):
			carry_btn.pressed.connect(_on_upgrade_carry)


func _on_upgrade_yield() -> void:
	_try_upgrade("yield_level")


func _on_upgrade_travel() -> void:
	_try_upgrade("node_speed_level")


func _on_upgrade_carry() -> void:
	_try_upgrade("carry_level")


func _try_upgrade(stat_key: String) -> void:
	if game_state == null:
		return
	if _selected_node_id == "":
		return
	if not game_state.has_method("upgrade_node_stat"):
		return

	var ok: bool = bool(game_state.call("upgrade_node_stat", _selected_node_id, stat_key))
	if ok:
		_flash_nutrients()
		_refresh_currency_ui()
		_refresh_nodepanel_all()


func _refresh_nodepanel_upgrades() -> void:
	if _selected_node_id == "":
		return
	if game_state == null or not game_state.has_method("get_node_upgrade_ui"):
		return

	var ui = game_state.call("get_node_upgrade_ui", _selected_node_id)
	if typeof(ui) != TYPE_DICTIONARY:
		return

	# Yield row (no duplicate Lv)
	if yield_name != null:
		yield_name.text = "Yield"
	if yield_lvl != null:
		yield_lvl.text = "Lv " + str(int(ui.get("yield_level", 1)))
	if yield_val != null:
		# show effective rate
		var eff := 0.0
		if game_state.has_method("get_node_rate_ui"):
			var rui = game_state.call("get_node_rate_ui", _selected_node_id)
			if typeof(rui) == TYPE_DICTIONARY:
				eff = float(rui.get("effective_rate", 0.0))
		yield_val.text = _fmt_rate(eff) + "/s"
	if yield_btn != null:
		yield_btn.text = "UPGRADE • " + _fmt_int(int(ui.get("yield_cost", 0)))

	# Speed row
	if travel_name != null:
		travel_name.text = "Speed"
	if travel_lvl != null:
		travel_lvl.text = "Lv " + str(int(ui.get("travel_level", 1)))
	if travel_val != null:
		travel_val.text = str(ui.get("travel_value", "5.0s/trip"))
	if travel_btn != null:
		travel_btn.text = "UPGRADE • " + _fmt_int(int(ui.get("travel_cost", 0)))

	# Carry row
	if carry_name != null:
		carry_name.text = "Carry"
	if carry_lvl != null:
		carry_lvl.text = "Lv " + str(int(ui.get("carry_level", 1)))
	if carry_val != null:
		carry_val.text = str(ui.get("carry_value", "Cap 5"))
	if carry_btn != null:
		carry_btn.text = "UPGRADE • " + _fmt_int(int(ui.get("carry_cost", 0)))


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

	if panel == digest_panel:
		_refresh_digest_panel_selected()
	if panel == node_panel:
		_refresh_nodepanel_all()

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
	)


func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_current()
		get_viewport().set_input_as_handled()


# ---------------- Node tap selection ----------------

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
			_open(node_panel)
			_refresh_nodepanel_all()
			get_viewport().set_input_as_handled()
			return


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
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = PANEL_H + PANEL_MARGIN


func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null
