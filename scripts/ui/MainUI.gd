extends Control

const PANEL_H := 864.0
const PANEL_MARGIN := 8.0

const NODE_HIT_RADIUS := 110.0
const UI_REFRESH_DT := 0.20

const MITE_DOT_SIZE_PX := 10
const MITE_GLOW_SIZE_PX := 24

const MITE_OUTBOUND_COLOR := Color(0.58, 0.72, 0.56, 0.95)
const MITE_CARRY_COLOR := Color(0.88, 1.00, 0.70, 1.00)

const TRANSPORT_PICKUP_TEXT_COLOR := Color(0.97, 0.94, 0.78, 1.00)
const TRANSPORT_CHEER_TEXT_COLOR := Color(0.90, 1.00, 0.78, 1.00)
const TRANSPORT_TEXT_OUTLINE_COLOR := Color(0.11, 0.17, 0.10, 0.95)
const TRANSPORT_PICKUP_FONT_SIZE := 22
const TRANSPORT_CHEER_FONT_SIZE := 28
const TRANSPORT_PICKUP_LIFT_PX := 34.0
const TRANSPORT_CHEER_LIFT_PX := 44.0
const TRANSPORT_PICKUP_DURATION := 0.50
const TRANSPORT_CHEER_DURATION := 0.65

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
@onready var nodes_container: Node = $MapLayer/Nodes
@onready var lines_container: Node = $MapLayer/Lines
@onready var spore_cloud: Node2D = $MapLayer/SporeCloud

@onready var selection_ring: Sprite2D = $MapLayer/SelectionRing

# Currency labels
var lbl_nutrients: Label = null
var lbl_glowcaps: Label = null
var lbl_strain: Label = null

var _tween: Tween
var _open_panel: Control = null
var _bar_h: float = 0.0

var _node_list: Array = []
var _node_lookup: Dictionary = {}
var _line_lookup: Dictionary = {}

var _selected_node: Node2D = null
var _selected_node_id: String = ""
var _node_pop_tween: Tween = null

var game_state: Node = null
var _ui_accum: float = 0.0

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
var _last_refinery_inventory_signature: String = ""
var _last_discovery_signature: String = ""

# Discoveries panel widgets
var discoveries_list: VBoxContainer = null
var discoveries_feedback: Label = null

# Refinery panel widgets
var refinery_list: VBoxContainer = null
var refinery_feedback: Label = null

# Nutrients flash
var _nutrients_base_scale: Vector2 = Vector2.ONE
var _nutrients_flash_tween: Tween = null

# Mite visuals
var _mites_layer: Node2D = null
var _mite_visuals: Dictionary = {}
var _mite_dot_texture: Texture2D = null
var _mite_glow_texture: Texture2D = null

# Transport feedback
var _transport_fx_layer: Node2D = null
var _transport_event_seen: Dictionary = {}

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

	_build_node_registry()
	_refresh_node_world_state()

	_register_transport_positions()
	_setup_mites()
	_setup_transport_fx()

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
	_bind_discoveries_panel()
	_bind_refinery_panel()
	_bind_nodepanel_top_table()
	_bind_nodepanel_production()
	_bind_nodepanel_upgrades()

	if lbl_nutrients != null:
		_nutrients_base_scale = lbl_nutrients.scale

	_refresh_panel_access_ui()
	_refresh_currency_ui()
	get_tree().root.print_tree_pretty()

func _process(dt: float) -> void:
	if selection_ring.visible and _selected_node != null:
		selection_ring.global_position = _selected_node.global_position

	_update_mite_visuals()
	_poll_transport_feedback()

	_ui_accum += dt
	if _ui_accum >= UI_REFRESH_DT:
		_ui_accum = 0.0
		_refresh_panel_access_ui()
		_refresh_currency_ui()
		_refresh_node_world_state()

		if _open_panel == node_panel and _selected_node_id != "":
			_refresh_nodepanel_all()

	var new_signature := _get_refinery_inventory_signature()
	if new_signature != _last_refinery_inventory_signature:
		_last_refinery_inventory_signature = new_signature

		if _open_panel == digest_panel:
			_refresh_digest_panel()

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
							
			
func _register_transport_positions() -> void:
	if game_state == null:
		return

	if game_state.has_method("register_spore_cloud_world_position"):
		game_state.call("register_spore_cloud_world_position", spore_cloud.global_position)

	if not game_state.has_method("register_node_world_position"):
		return

	for e in _node_list:
		var node_id: String = str(e.get("id", ""))
		var node_ref: Node2D = e.get("node", null) as Node2D
		if node_id == "" or node_ref == null:
			continue
		game_state.call("register_node_world_position", node_id, node_ref.global_position)


func _setup_mites() -> void:
	if has_node("MapLayer/MitesLayer"):
		_mites_layer = $MapLayer/MitesLayer
	else:
		_mites_layer = Node2D.new()
		_mites_layer.name = "MitesLayer"
		$MapLayer.add_child(_mites_layer)

	_mite_dot_texture = _make_circle_texture(MITE_DOT_SIZE_PX, false)
	_mite_glow_texture = _make_circle_texture(MITE_GLOW_SIZE_PX, true)

	_mite_visuals.clear()

	for e in _node_list:
		var node_id: String = str(e["id"])

		var root := Node2D.new()
		root.name = "Mite_" + node_id

		var glow := Sprite2D.new()
		glow.texture = _mite_glow_texture
		glow.centered = true
		glow.modulate = Color(
			MITE_OUTBOUND_COLOR.r,
			MITE_OUTBOUND_COLOR.g,
			MITE_OUTBOUND_COLOR.b,
			0.24
		)

		var dot := Sprite2D.new()
		dot.texture = _mite_dot_texture
		dot.centered = true
		dot.modulate = MITE_OUTBOUND_COLOR

		root.add_child(glow)
		root.add_child(dot)
		_mites_layer.add_child(root)

		_mite_visuals[node_id] = {
			"root": root,
			"glow": glow,
			"dot": dot
		}


func _update_mite_visuals() -> void:
	if _mites_layer == null:
		return
	if game_state == null:
		return
	if not game_state.has_method("get_node_mite_visual"):
		return

	for e in _node_list:
		var node_id: String = str(e["id"])
		var node_ref: Node2D = e["node"] as Node2D

		if not _mite_visuals.has(node_id):
			continue

		var mite: Dictionary = _mite_visuals[node_id] as Dictionary
		var root: Node2D = mite["root"] as Node2D
		var glow: Sprite2D = mite["glow"] as Sprite2D
		var dot: Sprite2D = mite["dot"] as Sprite2D

		var info = game_state.call("get_node_mite_visual", node_id)
		if typeof(info) != TYPE_DICTIONARY:
			root.visible = false
			continue

		var route_t: float = clamp(float(info.get("route_t", 0.0)), 0.0, 1.0)
		var carrying: bool = bool(info.get("carrying", false))
		var mite_visible: bool = bool(info.get("visible", true))

		root.visible = mite_visible
		if not mite_visible:
			continue

		root.global_position = spore_cloud.global_position.lerp(node_ref.global_position, route_t)

		if carrying:
			dot.modulate = MITE_CARRY_COLOR
			glow.modulate = Color(
				MITE_CARRY_COLOR.r,
				MITE_CARRY_COLOR.g,
				MITE_CARRY_COLOR.b,
				0.38
			)
			root.scale = Vector2.ONE * 1.08
		else:
			dot.modulate = MITE_OUTBOUND_COLOR
			glow.modulate = Color(
				MITE_OUTBOUND_COLOR.r,
				MITE_OUTBOUND_COLOR.g,
				MITE_OUTBOUND_COLOR.b,
				0.24
			)
			root.scale = Vector2.ONE


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


func _setup_transport_fx() -> void:
	if has_node("MapLayer/TransportFXLayer"):
		_transport_fx_layer = $MapLayer/TransportFXLayer
	else:
		_transport_fx_layer = Node2D.new()
		_transport_fx_layer.name = "TransportFXLayer"
		$MapLayer.add_child(_transport_fx_layer)

	_transport_event_seen.clear()

	for e in _node_list:
		var node_id: String = str(e["id"])
		var seen: Dictionary = {
			"pickup_event_id": 0,
			"delivery_event_id": 0
		}

		if game_state != null and game_state.has_method("get_node_transport_feedback"):
			var info = game_state.call("get_node_transport_feedback", node_id)
			if typeof(info) == TYPE_DICTIONARY:
				seen["pickup_event_id"] = int(info.get("pickup_event_id", 0))
				seen["delivery_event_id"] = int(info.get("delivery_event_id", 0))

		_transport_event_seen[node_id] = seen


func _poll_transport_feedback() -> void:
	if _transport_fx_layer == null:
		return
	if game_state == null:
		return
	if not game_state.has_method("get_node_transport_feedback"):
		return

	for e in _node_list:
		var node_id: String = str(e["id"])
		var node_ref: Node2D = e["node"] as Node2D
		var info = game_state.call("get_node_transport_feedback", node_id)
		if typeof(info) != TYPE_DICTIONARY:
			continue

		var seen: Dictionary = (_transport_event_seen.get(node_id, {
			"pickup_event_id": 0,
			"delivery_event_id": 0
		}) as Dictionary)

		var pickup_event_id: int = int(info.get("pickup_event_id", 0))
		var pickup_amount: int = int(info.get("pickup_amount", 0))
		if pickup_event_id > int(seen.get("pickup_event_id", 0)):
			if pickup_amount > 0:
				_spawn_transport_popup(
					node_ref.global_position + Vector2(0, -18),
					"Pickup +" + str(pickup_amount),
					TRANSPORT_PICKUP_TEXT_COLOR,
					TRANSPORT_PICKUP_FONT_SIZE,
					TRANSPORT_PICKUP_LIFT_PX,
					TRANSPORT_PICKUP_DURATION,
					false
				)
			seen["pickup_event_id"] = pickup_event_id

		var delivery_event_id: int = int(info.get("delivery_event_id", 0))
		var delivery_amount: int = int(info.get("delivery_amount", 0))
		if delivery_event_id > int(seen.get("delivery_event_id", 0)):
			if delivery_amount > 0:
				var cheer_pos: Vector2 = spore_cloud.global_position
				if _mite_visuals.has(node_id):
					var mite: Dictionary = _mite_visuals[node_id] as Dictionary
					var root: Node2D = mite.get("root", null) as Node2D
					if root != null:
						cheer_pos = root.global_position

				_spawn_transport_popup(
					cheer_pos + Vector2(0, -16),
					"Yay! +" + str(delivery_amount),
					TRANSPORT_CHEER_TEXT_COLOR,
					TRANSPORT_CHEER_FONT_SIZE,
					TRANSPORT_CHEER_LIFT_PX,
					TRANSPORT_CHEER_DURATION,
					true
				)
			seen["delivery_event_id"] = delivery_event_id

		_transport_event_seen[node_id] = seen


func _spawn_transport_popup(
	world_pos: Vector2,
	text: String,
	text_color: Color,
	font_size: int,
	lift_px: float,
	duration: float,
	is_cheer: bool
) -> void:
	if _transport_fx_layer == null:
		return

	var label := Label.new()
	label.top_level = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.modulate = Color(1, 1, 1, 1)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_outline_color", TRANSPORT_TEXT_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", 4 if is_cheer else 3)

	_transport_fx_layer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.global_position = world_pos - (label.size * 0.5)
	label.scale = Vector2.ONE * (0.95 if is_cheer else 1.0)

	var end_pos: Vector2 = label.global_position + Vector2(0, -lift_px)
	var end_scale: Vector2 = Vector2.ONE * (1.12 if is_cheer else 1.04)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position", end_pos, duration)
	tween.parallel().tween_property(label, "scale", end_scale, duration * 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, duration)
	tween.finished.connect(func():
		if is_instance_valid(label):
			label.queue_free()
	)


# ---------------- DigestPanel ----------------

func _bind_digest_panel() -> void:
	var root_box: VBoxContainer = digest_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if root_box == null:
		return

	var title_lbl: Label = digest_panel.find_child("LblDigestTitle", true, false) as Label
	digest_lbl_selected = digest_panel.find_child("LblDigestSelected", true, false) as Label
	digest_btn_1 = digest_panel.find_child("BtnDigest1", true, false) as Button
	digest_btn_all = digest_panel.find_child("BtnDigestAll", true, false) as Button

	if title_lbl != null:
		title_lbl.text = "Digest Inventory"
	if digest_lbl_selected != null:
		digest_lbl_selected.visible = false
	if digest_btn_1 != null:
		digest_btn_1.visible = false
	if digest_btn_all != null:
		digest_btn_all.visible = false

	digest_tabs_row = HBoxContainer.new()
	digest_tabs_row.name = "DigestTabsRow"
	digest_tabs_row.add_theme_constant_override("separation", 8)
	root_box.add_child(digest_tabs_row)
	root_box.move_child(digest_tabs_row, root_box.get_child_count() - 1)

	digest_tab_resources = Button.new()
	digest_tab_resources.text = "Resources"
	digest_tab_resources.pressed.connect(func(): _set_digest_active_category("resource"))
	digest_tabs_row.add_child(digest_tab_resources)

	digest_tab_compounds = Button.new()
	digest_tab_compounds.text = "Compounds"
	digest_tab_compounds.pressed.connect(func(): _set_digest_active_category("compound"))
	digest_tabs_row.add_child(digest_tab_compounds)

	digest_tab_solutions = Button.new()
	digest_tab_solutions.text = "Solutions"
	digest_tab_solutions.pressed.connect(func(): _set_digest_active_category("solution"))
	digest_tabs_row.add_child(digest_tab_solutions)

	digest_feedback = Label.new()
	digest_feedback.name = "DigestFeedback"
	digest_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	digest_feedback.text = ""
	root_box.add_child(digest_feedback)

	digest_inventory_list = VBoxContainer.new()
	digest_inventory_list.name = "DigestInventoryList"
	digest_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	digest_inventory_list.add_theme_constant_override("separation", 6)
	root_box.add_child(digest_inventory_list)

	_set_digest_active_category("resource")


func _set_digest_active_category(category: String) -> void:
	_digest_active_category = category
	_refresh_digest_panel()


func _clear_digest_rows() -> void:
	if digest_inventory_list == null:
		return
	for child in digest_inventory_list.get_children():
		child.queue_free()


func _refresh_digest_tab_buttons() -> void:
	if digest_tab_resources == null or digest_tab_compounds == null or digest_tab_solutions == null:
		return
	var compounds_unlocked: bool = false
	var solutions_unlocked: bool = false
	if game_state != null:
		if game_state.has_method("is_refinery_unlocked"):
			compounds_unlocked = bool(game_state.call("is_refinery_unlocked"))
		if game_state.has_method("is_synth_unlocked"):
			solutions_unlocked = bool(game_state.call("is_synth_unlocked"))

	digest_tab_resources.disabled = false
	digest_tab_compounds.disabled = not compounds_unlocked
	digest_tab_solutions.disabled = not solutions_unlocked

	if not compounds_unlocked and _digest_active_category == "compound":
		_digest_active_category = "resource"
	if not solutions_unlocked and _digest_active_category == "solution":
		_digest_active_category = "resource"

	digest_tab_resources.modulate = Color.WHITE if _digest_active_category == "resource" else Color(0.86, 0.86, 0.86, 1.0)
	digest_tab_compounds.modulate = Color.WHITE if _digest_active_category == "compound" else Color(0.86, 0.86, 0.86, 1.0)
	digest_tab_solutions.modulate = Color.WHITE if _digest_active_category == "solution" else Color(0.86, 0.86, 0.86, 1.0)


func _make_digest_entry_row(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "%s • %s" % [str(entry.get("name", "")), _fmt_int(int(entry.get("amount", 0)))]
	box.add_child(title)

	var details := Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var digest_each: float = float(entry.get("digest_each", 0.0))
	var digest_total: float = float(entry.get("digest_total", 0.0))
	details.text = "Digest each: %s Nutrients • Total: %s" % [_fmt_int(int(round(digest_each))), _fmt_int(int(round(digest_total)))]
	details.modulate = Color(0.88, 0.92, 0.88, 1.0)
	box.add_child(details)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var btn_one := Button.new()
	btn_one.text = "Digest 1"
	var item_id: String = str(entry.get("id", ""))
	btn_one.pressed.connect(func(): _on_digest_inventory_amount_pressed(item_id, 1))
	row.add_child(btn_one)

	var btn_all := Button.new()
	btn_all.text = "Digest All"
	btn_all.pressed.connect(func(): _on_digest_inventory_amount_pressed(item_id, -1))
	row.add_child(btn_all)

	return box


func _on_digest_inventory_amount_pressed(item_id: String, amount: int) -> void:
	if game_state == null:
		return
	var digested: int = 0
	if amount < 0:
		if game_state.has_method("digest_all_inventory_item"):
			digested = int(game_state.call("digest_all_inventory_item", item_id))
	else:
		if game_state.has_method("digest_inventory_item"):
			digested = int(game_state.call("digest_inventory_item", item_id, amount))
	if digested > 0:
		_flash_nutrients()
		if digest_feedback != null:
			digest_feedback.text = "Digested %s %s." % [_fmt_int(digested), _pretty_res(item_id)]
	else:
		if digest_feedback != null:
			digest_feedback.text = "Nothing to digest."
	_refresh_panel_access_ui()
	_refresh_currency_ui()
	_refresh_digest_panel()
	_refresh_nodepanel_all()


func _on_digest_panel_1_pressed() -> void:
	pass


func _on_digest_panel_all_pressed() -> void:
	pass


func _digest_selected_node_at_cloud(amount: int) -> void:
	pass


func _refresh_digest_panel() -> void:
	if digest_inventory_list == null:
		return
	_refresh_digest_tab_buttons()
	_clear_digest_rows()

	if digest_feedback != null and digest_feedback.text == "":
		digest_feedback.text = "Digest owned inventory into Nutrients."

	if _digest_active_category == "compound":
		if game_state == null or not game_state.has_method("is_refinery_unlocked") or not bool(game_state.call("is_refinery_unlocked")):
			if digest_feedback != null:
				digest_feedback.text = "Unlock Primitive Refinery to digest compounds."
			return
	elif _digest_active_category == "solution":
		if game_state == null or not game_state.has_method("is_synth_unlocked") or not bool(game_state.call("is_synth_unlocked")):
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
		empty.text = "No %s available." % (_digest_active_category + "s")
		empty.modulate = Color(0.82, 0.82, 0.82, 1.0)
		digest_inventory_list.add_child(empty)
		return

	for entry_variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		digest_inventory_list.add_child(_make_digest_entry_row(entry))


func _flash_nutrients() -> void:
	if lbl_nutrients == null:
		return

	if _nutrients_flash_tween != null:
		_nutrients_flash_tween.kill()

	lbl_nutrients.scale = _nutrients_base_scale * 1.15

	_nutrients_flash_tween = create_tween()
	_nutrients_flash_tween.tween_property(
		lbl_nutrients,
		"scale",
		_nutrients_base_scale,
		0.18
	)
	
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
	var can_show_refinery := false
	if game_state != null:
		if game_state.has_method("can_show_discoveries_tab"):
			can_show_discoveries = bool(game_state.call("can_show_discoveries_tab"))
		if game_state.has_method("is_refinery_unlocked"):
			can_show_refinery = bool(game_state.call("is_refinery_unlocked"))
	btn_discoveries.visible = can_show_discoveries
	btn_discoveries.disabled = not can_show_discoveries
	btn_refinery.visible = can_show_refinery
	btn_refinery.disabled = not can_show_refinery
	if not can_show_refinery and _open_panel == refinery_panel:
		_close_current()


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
	effect.modulate = Color(0.88, 0.92, 0.88, 1.0)
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

		var new_signature := _get_refinery_inventory_signature()
		_last_refinery_inventory_signature = new_signature
		

# ---------------- RefineryPanel ----------------

func _bind_refinery_panel() -> void:
	refinery_list = refinery_panel.find_child("VBoxContainer", true, false) as VBoxContainer
	if refinery_list == null:
		return
	refinery_feedback = Label.new()
	refinery_feedback.name = "RefineryFeedback"
	refinery_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refinery_feedback.text = ""
	refinery_list.add_child(refinery_feedback)


func _clear_refinery_rows() -> void:
	if refinery_list == null:
		return
	for child in refinery_list.get_children():
		if child == refinery_feedback:
			continue
		child.queue_free()


func _get_refinery_inventory_signature() -> String:
	var parts: Array[String] = []

	for compound_id in GameState.compound_defs.keys():
		parts.append("%s:%s" % [compound_id, int(GameState.resources.get(compound_id, 0))])

	for solution_id in GameState.solution_defs.keys():
		parts.append("%s:%s" % [solution_id, int(GameState.resources.get(solution_id, 0))])

	parts.sort()
	return "|".join(parts)


func _get_discovery_signature() -> String:
	var parts: Array[String] = []

	if game_state == null:
		return ""

	# Resource amounts affect whether discovery buttons can be afforded.
	var resource_defs: Dictionary = game_state.get("resource_defs")
	for item_id_variant in resource_defs.keys():
		var item_id := str(item_id_variant)
		parts.append("%s:%s" % [item_id, int(game_state.get_amount(item_id))])

	# Unlocked discoveries affect visibility / completion / downstream systems.
	var unlocked_discoveries: Dictionary = game_state.get("unlocked_discoveries")
	for discovery_id_variant in unlocked_discoveries.keys():
		var discovery_id := str(discovery_id_variant)
		parts.append("u:%s:%s" % [discovery_id, str(bool(unlocked_discoveries[discovery_id]))])

	# Discovery levels matter for repeatables / completion state / effects.
	var discovery_levels: Dictionary = game_state.get("discovery_levels")
	for discovery_id_variant in discovery_levels.keys():
		var discovery_id := str(discovery_id_variant)
		parts.append("lvl:%s:%s" % [discovery_id, int(discovery_levels[discovery_id])])

	parts.sort()
	return "|".join(parts)
	
	

func _refresh_refinery_panel() -> void:
	if refinery_list == null or game_state == null:
		return

	_clear_refinery_rows()

	if refinery_feedback != null and refinery_feedback.get_parent() == null:
		refinery_list.add_child(refinery_feedback)

	if refinery_feedback != null and refinery_feedback.text == "":
		refinery_feedback.text = "Assign recipes to refinery slots. Slots repeat automatically while ingredients are available."

	if not game_state.has_method("is_refinery_unlocked") or not bool(game_state.call("is_refinery_unlocked")):
		if refinery_feedback != null:
			refinery_feedback.text = "Requires Primitive Refinery."
		return

	# Recipe unlock section
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
	slot_header.text = "Refinery Slots"
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

	var unlocked := false
	if game_state.has_method("is_compound_unlocked"):
		unlocked = bool(game_state.call("is_compound_unlocked", recipe_id))

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

	# Rate (/s) = delivered/sec once transport exists
	if cell_rate != null and game_state.has_method("get_node_rate_ui"):
		var rui = game_state.call("get_node_rate_ui", _selected_node_id)
		if typeof(rui) == TYPE_DICTIONARY:
			var delivered: float = float(rui.get("delivered_rate", 0.0))
			cell_rate.text = _fmt_rate(delivered) + "/s"

	# Harvested = node pool backlog
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
		_refresh_panel_access_ui()
		_refresh_currency_ui()
		_refresh_nodepanel_all()
		_refresh_digest_panel()


func _refresh_nodepanel_upgrades() -> void:
	if _selected_node_id == "":
		return
	if game_state == null or not game_state.has_method("get_node_upgrade_ui"):
		return

	var ui = game_state.call("get_node_upgrade_ui", _selected_node_id)
	if typeof(ui) != TYPE_DICTIONARY:
		return

	# Yield row
	if yield_name != null:
		yield_name.text = "Yield"
	if yield_lvl != null:
		yield_lvl.text = "Lv " + str(int(ui.get("yield_level", 1)))
	if yield_val != null:
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
		carry_val.text = str(ui.get("carry_value", "Cap 1"))
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
		_refresh_digest_panel()
	if panel == discoveries_panel:
		_refresh_discoveries_panel()
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
		var node_id: String = str(e["id"])
		var state := _get_node_world_state(node_id)
		if not bool(state.get("is_visible", true)):
			continue

		var node_screen := canvas_xform * node.global_position
		if node_screen.distance_to(screen_pos) > NODE_HIT_RADIUS:
			continue

		if not bool(state.get("is_unlocked", true)):
			if game_state != null and game_state.has_method("try_unlock_node"):
				var unlocked: bool = bool(game_state.call("try_unlock_node", node_id))
				if unlocked:
					_refresh_panel_access_ui()
					_refresh_currency_ui()
					_refresh_node_world_state()
					node_title.text = str(e["name"])
					_selected_node_id = node_id
					_select_node(node)
					_open(node_panel)
					_refresh_nodepanel_all()
					get_viewport().set_input_as_handled()
					return
			continue

		node_title.text = str(e["name"])
		_selected_node_id = node_id
		_select_node(node)
		_open(node_panel)
		_refresh_nodepanel_all()
		get_viewport().set_input_as_handled()
		return


func _build_node_registry() -> void:
	_node_list.clear()
	_node_lookup.clear()
	_line_lookup.clear()

	if game_state == null or not game_state.has_method("get_all_node_defs"):
		return

	var defs = game_state.call("get_all_node_defs")
	if typeof(defs) != TYPE_ARRAY:
		return

	for def_variant in defs:
		var def: Dictionary = def_variant as Dictionary
		var node_id: String = str(def.get("id", ""))
		var node_name: String = str(def.get("name", node_id))
		var scene_node_name: String = str(def.get("scene_node_name", ""))
		if node_id == "" or scene_node_name == "":
			continue

		var node_ref := nodes_container.get_node_or_null(scene_node_name) as Node2D
		if node_ref == null:
			continue

		var entry := {
			"id": node_id,
			"name": node_name,
			"node": node_ref
		}
		_node_list.append(entry)
		_node_lookup[node_id] = entry

		var line_node_name: String = str(def.get("line_node_name", ""))
		if line_node_name != "":
			var line_ref := lines_container.get_node_or_null(line_node_name) as CanvasItem
			if line_ref != null:
				_line_lookup[node_id] = line_ref


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
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = PANEL_H + PANEL_MARGIN


func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null
