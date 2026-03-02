extends Control

const PANEL_H := 864.0
const PANEL_MARGIN := 8.0

@onready var dimmer: ColorRect = $PanelHost/Dimmer
@onready var bottom_bar: Control = $UILayer/HUD/BottomBar

# Menu panels
@onready var upgrades_panel: Control     = $PanelHost/PanelContainer/UpgradesPanel
@onready var discoveries_panel: Control  = $PanelHost/PanelContainer/DiscoveriesPanel
@onready var refinery_panel: Control     = $PanelHost/PanelContainer/RefineryPanel
@onready var digest_panel: Control       = $PanelHost/PanelContainer/DigestPanel
@onready var settings_panel: Control     = $PanelHost/PanelContainer/SettingsPanel

# Node panel + header refs (your exact names)
@onready var node_panel: Control = $PanelHost/PanelContainer/NodePanel
@onready var node_title: Label   = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/"Header row"/Name
@onready var node_close: Button  = $PanelHost/PanelContainer/NodePanel/MarginContainer/VBoxContainer/"Header row"/Close

# Bottom buttons
@onready var btn_upgrades: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnUpgrades
@onready var btn_discoveries: BaseButton = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnDiscoveries
@onready var btn_refinery: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnRefinery
@onready var btn_digest: BaseButton      = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnDigest
@onready var btn_settings: BaseButton    = $UILayer/HUD/BottomBar/MarginContainer/HBoxContainer/BtnSettings

# Map nodes (Area2D) — names must match your scene
@onready var n_damp: Area2D    = $MapLayer/Nodes/Node_DampSoil
@onready var n_log: Area2D     = $MapLayer/Nodes/Node_RottingLog
@onready var n_compost: Area2D = $MapLayer/Nodes/Node_CompostHeap
@onready var n_root: Area2D    = $MapLayer/Nodes/Node_RootCluster

var _tween: Tween
var _open_panel: Control = null
var _bar_h: float = 0.0

func _ready() -> void:
	await get_tree().process_frame
	_bar_h = bottom_bar.size.y

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

	# Node panel close button
	node_close.pressed.connect(_close_current)

	# Wire node taps → open node panel
	_wire_node(n_damp, "Damp Soil")
	_wire_node(n_log, "Rotting Log")
	_wire_node(n_compost, "Compost Heap")
	_wire_node(n_root, "Root Cluster")

func _all_panels() -> Array[Control]:
	return [upgrades_panel, discoveries_panel, refinery_panel, digest_panel, settings_panel, node_panel]

func _wire_node(area: Area2D, display_name: String) -> void:
	area.input_event.connect(func(_viewport, event, _shape_idx):
		var pressed := false

		if event is InputEventMouseButton:
			pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			pressed = event.pressed

		if pressed:
			print("NODE CLICK:", display_name) # debug
			node_title.text = display_name
			_open(node_panel)
	)

func _toggle_panel(panel: Control) -> void:
	if _open_panel == panel:
		_close_current()
	else:
		_open(panel)

func _open(panel: Control) -> void:
	_kill_tween()

	# Snap-close other panel (simple V0 behavior)
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
	)

func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_current()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _open_panel != null:
			_close_current()
			get_viewport().set_input_as_handled()

func _set_panel_closed(panel: Control) -> void:
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = PANEL_H + PANEL_MARGIN

func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null
