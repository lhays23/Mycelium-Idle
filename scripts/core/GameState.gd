extends Node

const TICK_DT: float = 0.1

# Upgrade tuning (Phase 6 placeholder values; can move to config later)
const YIELD_STEP: float = 0.10
const NODE_SPEED_STEP: float = 0.10
const CARRY_STEP: int = 1

# Transport tuning
const BASE_ROOT_PULSE_SPEED: float = 150.0
const BASE_CARRY: int = 500
const LOAD_UNLOAD_SEC: float = 0.25
const DEFAULT_DISTANCE_PX: float = 360.0

const RAW_BASE_VALUES := {
	"spores": 1.0,
	"hyphae": 2.0,
	"cellulose": 4.0,
	"mycelium": 7.0
}
const BASE_DIGEST_MODIFIER: float = 1.0
const DEFAULT_DISCOVERY_BASE_DIGESTION_MODIFIER: float = 0.8
const PASS1_DISCOVERY_IDS := ["mycelial_insight", "primitive_refinery", "synthesis", "aura_activation", "excess_fertilizer", "nutrient_efficiency_1"]
const DEFAULT_REFINERY_PASS1_RECIPE_IDS := ["spore_composite", "hyphal_thread", "cellulose_weave", "growth_gel"]
const DEFAULT_REFINERY_BASE_CRAFT_SEC := 4.0
const SAVE_VERSION: int = 1
const SAVE_FILE_PATH: String = "user://mycelium_idle_save_v1.json"
const AUTOSAVE_SEC: float = 10.0
const NODE_ROOT_TRANSFER_KEY: String = "root_transfer"
const LEGACY_NODE_TRANSPORT_KEY: String = "transport"

var config: Dictionary = {}
var compounds_meta: Dictionary = {}
var compound_defs: Dictionary = {}
var compound_order: Array[String] = []
var solutions_meta: Dictionary = {}
var solution_defs: Dictionary = {}
var solution_order: Array[String] = ["mycelial_resin", "spore_resin", "weave_serum", "root_catalyst"]
var raw_resource_order: Array[String] = []

var resource_defs: Dictionary = {}   # res_id -> metadata
var node_defs: Dictionary = {}       # node_id -> static definition
var node_order: Array[String] = []   # stable display order

var resources: Dictionary = {}       # res_id -> float (cloud inventory)
var nodes: Dictionary = {}           # node_id -> live node state
var discovery_defs: Dictionary = {}  # discovery_id -> static definition
var discovery_order: Array[String] = []
var discovery_notes: Dictionary = {}
var unlocked_discoveries: Dictionary = {}  # discovery_id -> bool
var discovery_levels: Dictionary = {}      # discovery_id -> current level
var total_nutrients_earned_run: float = 0.0
var meta_state: Dictionary = {}

var refinery_slot_costs: Array = []
var unlocked_refinery_slots: int = 0
var refinery_slots: Array = []
var paid_compound_unlocks: Dictionary = {}
var paid_solution_unlocks: Dictionary = {}
var synth_slot_costs: Array = []
var unlocked_synth_slots: int = 0
var synth_slots: Array = []

var _accum: float = 0.0
var _autosave_accum: float = 0.0

# World-space positions for transport calculations
var spore_cloud_world_pos: Vector2 = Vector2.ZERO
var node_world_positions: Dictionary = {}  # node_id -> Vector2


func _ready() -> void:
	if not load_game():
		_load_all()
	set_process(true)


func _process(dt: float) -> void:
	_accum += dt
	while _accum >= TICK_DT:
		_accum -= TICK_DT
		tick(TICK_DT)

	_autosave_accum += dt
	if _autosave_accum >= AUTOSAVE_SEC:
		_autosave_accum = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
	or what == NOTIFICATION_WM_CLOSE_REQUEST \
	or what == NOTIFICATION_EXIT_TREE:
		save_game()


func tick(dt: float) -> void:
	_update_node_reveals()
	_tick_node_production(dt)
	_tick_root_transfer(dt)
	_tick_refinery(dt)
	_tick_synth(dt)


# ---------------- Production ----------------

func _tick_node_production(dt: float) -> void:
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)
		var n: Dictionary = nodes[node_id] as Dictionary
		if not bool(n.get("is_connected", false)):
			continue

		var base_rate_total: float = float(n.get("base_rate_total", 0.0))
		var up: Dictionary = _ensure_upgrade_keys(n)
		var yield_level: int = int(up.get("yield_level", 1))
		var yield_mult: float = _get_yield_multiplier_for_level(yield_level)
		var rate_total: float = base_rate_total * yield_mult

		var outputs: Array = (n.get("outputs", []) as Array)
		if outputs.is_empty():
			continue

		var sum_w: float = 0.0
		for o_variant in outputs:
			var od: Dictionary = o_variant as Dictionary
			sum_w += float(od.get("weight", 1.0))
		if sum_w <= 0.0:
			sum_w = 1.0

		var pool: Dictionary = (n.get("pool", {}) as Dictionary)
		for o_variant in outputs:
			var od2: Dictionary = o_variant as Dictionary
			var res_id: String = str(od2.get("res", ""))
			if res_id == "":
				continue
			var w: float = float(od2.get("weight", 1.0))
			var amount_per_unit: float = float(od2.get("amount_per_unit", 1.0))
			var rate_o: float = rate_total * (w / sum_w) * amount_per_unit
			var add: float = rate_o * dt
			var current: float = float(pool.get(res_id, 0.0))
			pool[res_id] = current + add

		n["pool"] = pool
		n["upgrades"] = up
		nodes[node_id] = n


# ---------------- Root Pulse Transfer ----------------

func register_spore_cloud_world_position(pos: Vector2) -> void:
	spore_cloud_world_pos = pos


func register_node_world_position(node_id: String, pos: Vector2) -> void:
	node_world_positions[node_id] = pos


func _tick_root_transfer(dt: float) -> void:
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)
		var n: Dictionary = nodes[node_id] as Dictionary

		var transfer: Dictionary = _ensure_root_transfer_state(n, node_id)

		if not bool(n.get("is_connected", false)):
			transfer["pulse_progress_sec"] = 0.0
			transfer["in_flight"] = false
			transfer["cargo"] = {}
			transfer["active_visual"] = false
			_write_node_root_transfer_dict(n, transfer)
			nodes[node_id] = n
			continue

		var pulse_sec: float = maxf(0.05, _get_node_pulse_sec(node_id))
		var progress_sec: float = float(transfer.get("pulse_progress_sec", 0.0))
		var in_flight: bool = bool(transfer.get("in_flight", false))
		var cargo: Dictionary = (transfer.get("cargo", {}) as Dictionary)

		var delivered_this_tick: int = 0
		var remaining_dt: float = dt

		while remaining_dt > 0.0:
			if not in_flight:
				cargo = _pickup_one_root_pulse(node_id)
				if _root_pulse_cargo_total(cargo) <= 0:
					break

				in_flight = true
				progress_sec = 0.0

			var time_to_arrival: float = pulse_sec - progress_sec

			if remaining_dt >= time_to_arrival:
				progress_sec = pulse_sec
				remaining_dt -= time_to_arrival

				delivered_this_tick += _deliver_root_pulse_cargo_to_base(cargo)
				cargo = {}
				in_flight = false
				progress_sec = 0.0
			else:
				progress_sec += remaining_dt
				remaining_dt = 0.0

		if delivered_this_tick > 0:
			transfer["transfer_event_id"] = int(transfer.get("transfer_event_id", 0)) + 1
			transfer["transfer_amount"] = delivered_this_tick
		else:
			transfer["transfer_amount"] = 0

		transfer["pulse_progress_sec"] = progress_sec
		transfer["pulse_sec"] = pulse_sec
		transfer["in_flight"] = in_flight
		transfer["cargo"] = cargo
		transfer["active_visual"] = in_flight and (_root_pulse_cargo_total(cargo) > 0)

		_write_node_root_transfer_dict(n, transfer)
		nodes[node_id] = n


func _ensure_root_transfer_state(n: Dictionary, node_id: String) -> Dictionary:
	var transfer: Dictionary = _read_node_root_transfer_dict(n)

	if not transfer.has("pulse_progress_sec"):
		transfer["pulse_progress_sec"] = 0.0
	if not transfer.has("pulse_sec"):
		transfer["pulse_sec"] = _get_node_pulse_sec(node_id)
	if not transfer.has("in_flight"):
		transfer["in_flight"] = false
	if not transfer.has("cargo"):
		transfer["cargo"] = {}
	if not transfer.has("transfer_event_id"):
		transfer["transfer_event_id"] = 0
	if not transfer.has("transfer_amount"):
		transfer["transfer_amount"] = 0
	if not transfer.has("active_visual"):
		transfer["active_visual"] = false

	return transfer


func _pickup_one_root_pulse(node_id: String) -> Dictionary:
	var cargo: Dictionary = {}
	if not nodes.has(node_id):
		return cargo

	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)
	var outputs: Array = (n.get("outputs", []) as Array)
	var carry_left: int = _get_node_carry_capacity(node_id)

	if carry_left <= 0:
		return cargo

	for o_variant in outputs:
		if carry_left <= 0:
			break

		var od: Dictionary = o_variant as Dictionary
		var res_id: String = str(od.get("res", ""))
		if res_id == "":
			continue

		var available: int = int(floor(float(pool.get(res_id, 0.0))))
		if available <= 0:
			continue

		var take: int = min(carry_left, available)
		if take <= 0:
			continue

		pool[res_id] = maxf(0.0, float(pool.get(res_id, 0.0)) - float(take))
		cargo[res_id] = take
		carry_left -= take

	n["pool"] = pool
	nodes[node_id] = n
	return cargo


func _deliver_root_pulse_cargo_to_base(cargo: Dictionary) -> int:
	var delivered_total: int = 0

	for res_id_variant in cargo.keys():
		var res_id: String = str(res_id_variant)
		var amount: int = int(cargo[res_id_variant])
		if amount <= 0:
			continue

		if not resources.has(res_id):
			resources[res_id] = 0.0

		resources[res_id] = float(resources.get(res_id, 0.0)) + float(amount)
		delivered_total += amount

	return delivered_total


func _root_pulse_cargo_total(cargo: Dictionary) -> int:
	var total: int = 0
	for value_variant in cargo.values():
		total += int(value_variant)
	return total

func _get_node_pool_total(node_id: String) -> float:
	if not nodes.has(node_id):
		return 0.0

	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)

	var total: float = 0.0
	for value_variant in pool.values():
		total += float(value_variant)

	return total


func _get_node_distance(node_id: String) -> float:
	if node_world_positions.has(node_id):
		var node_pos: Vector2 = node_world_positions[node_id]
		return max(1.0, node_pos.distance_to(spore_cloud_world_pos))
	if node_defs.has(node_id):
		return max(1.0, float((node_defs[node_id] as Dictionary).get("distance_px", _get_transport_default_distance_px())))
	return _get_transport_default_distance_px()


func _get_node_speed_value(node_id: String) -> float:
	if not nodes.has(node_id):
		return _get_root_pulse_base_speed()

	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var lvl: int = int(up.get("node_speed_level", 1))

	return _get_root_pulse_base_speed() * _get_speed_multiplier_for_level(lvl)


func _get_node_carry_capacity(node_id: String) -> int:
	if not nodes.has(node_id):
		return _get_carry_capacity_for_level(1)

	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var lvl: int = int(up.get("carry_level", 1))

	return _get_carry_capacity_for_level(lvl)


func _get_node_pulse_sec(node_id: String) -> float:
	var distance_px: float = _get_node_distance(node_id)
	var speed: float = maxf(1.0, _get_node_speed_value(node_id))
	return distance_px / speed


func _get_node_primary_production_rate(node_id: String) -> float:
	if not nodes.has(node_id):
		return 0.0

	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_connected", false)):
		return 0.0

	var outputs: Array = (n.get("outputs", []) as Array)
	if outputs.is_empty():
		return 0.0

	var up: Dictionary = _ensure_upgrade_keys(n)
	var yield_level: int = int(up.get("yield_level", 1))
	var yield_mult: float = _get_yield_multiplier_for_level(yield_level)

	var base_rate_total: float = float(n.get("base_rate_total", 0.0))
	var rate_total: float = base_rate_total * yield_mult

	var sum_w: float = 0.0
	for o_variant in outputs:
		var od: Dictionary = o_variant as Dictionary
		sum_w += float(od.get("weight", 1.0))
	if sum_w <= 0.0:
		sum_w = 1.0

	var o0: Dictionary = outputs[0] as Dictionary
	var w: float = float(o0.get("weight", 1.0))
	var amount_per_unit: float = float(o0.get("amount_per_unit", 1.0))

	return rate_total * (w / sum_w) * amount_per_unit


func _get_node_root_transfer_rate(node_id: String) -> float:
	var pulse_sec: float = maxf(0.05, _get_node_pulse_sec(node_id))
	var carry: int = _get_node_carry_capacity(node_id)
	return float(carry) / pulse_sec


func _get_node_primary_delivered_rate(node_id: String) -> float:
	if not nodes.has(node_id):
		return 0.0

	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_connected", false)):
		return 0.0

	var prod_primary: float = _get_node_primary_production_rate(node_id)
	var transfer_capacity: float = _get_node_root_transfer_rate(node_id)

	return minf(prod_primary, transfer_capacity)


func get_node_root_pulse_visual(node_id: String) -> Dictionary:
	var out: Dictionary = {
		"route_t": 0.0,
		"active": false,
		"visible": false
	}

	if not nodes.has(node_id):
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_connected", false)):
		return out

	var transfer: Dictionary = _ensure_root_transfer_state(n, node_id)
	var in_flight: bool = bool(transfer.get("in_flight", false))
	if not in_flight:
		return out

	var pulse_sec: float = maxf(0.05, _get_node_pulse_sec(node_id))
	var progress_sec: float = clampf(float(transfer.get("pulse_progress_sec", 0.0)), 0.0, pulse_sec)

	out["visible"] = true
	out["active"] = true
	out["route_t"] = progress_sec / pulse_sec

	return out

func get_node_root_transfer_feedback(node_id: String) -> Dictionary:
	var out: Dictionary = {
		"transfer_event_id": 0,
		"transfer_amount": 0
	}

	if not nodes.has(node_id):
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
	var transfer: Dictionary = _ensure_root_transfer_state(n, node_id)

	out["transfer_event_id"] = int(transfer.get("transfer_event_id", 0))
	out["transfer_amount"] = int(transfer.get("transfer_amount", 0))

	return out

# ---------------- Digestion ----------------

func _get_node_primary_res_id(node_id: String) -> String:
	if not nodes.has(node_id):
		return ""
	var n: Dictionary = nodes[node_id] as Dictionary
	var outputs: Array = (n.get("outputs", []) as Array)
	if outputs.is_empty():
		return ""
	return str((outputs[0] as Dictionary).get("res", ""))


func get_node_primary_res_id(node_id: String) -> String:
	return _get_node_primary_res_id(node_id)


func get_node_primary_pool_amount(node_id: String) -> int:
	if not nodes.has(node_id):
		return 0
	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0
	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)
	return int(floor(float(pool.get(res_id, 0.0))))


func get_node_primary_cloud_amount(node_id: String) -> int:
	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0
	return get_amount(res_id)


func digest_node_primary(node_id: String, amount: int) -> int:
	if amount <= 0 or not nodes.has(node_id):
		return 0
	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_unlocked", false)):
		return 0
	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0
	var available: int = int(floor(float(resources.get(res_id, 0.0))))
	if available <= 0:
		return 0
	var take: int = min(amount, available)
	resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) - float(take))
	var gained: float = float(take) * _get_resource_base_value(res_id) * get_current_digestion_modifier()
	resources["nutrients"] = float(resources.get("nutrients", 0.0)) + gained
	total_nutrients_earned_run += gained
	_update_node_reveals()
	return take


func digest_all_node_primary(node_id: String) -> int:
	if not nodes.has(node_id):
		return 0
	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0
	var available: int = int(floor(float(resources.get(res_id, 0.0))))
	return digest_node_primary(node_id, available)


func digest_inventory_item(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if item_id == "" or item_id == "nutrients" or item_id == "glowcaps" or item_id == "strain_points":
		return 0
	var available: int = int(floor(float(resources.get(item_id, 0.0))))
	if available <= 0:
		return 0
	var take: int = min(amount, available)
	resources[item_id] = max(0.0, float(resources.get(item_id, 0.0)) - float(take))
	var gained: float = float(take) * _get_resource_base_value(item_id) * get_current_digestion_modifier()
	resources["nutrients"] = float(resources.get("nutrients", 0.0)) + gained
	total_nutrients_earned_run += gained
	_update_node_reveals()
	return take


func digest_all_inventory_item(item_id: String) -> int:
	var available: int = int(floor(float(resources.get(item_id, 0.0))))
	return digest_inventory_item(item_id, available)


func get_digest_inventory_entries(category: String) -> Array:
	var out: Array = []
	var ids: Array[String] = []

	match category:
		"resource":
			ids = raw_resource_order.duplicate()
		"compound":
			ids = compound_order.duplicate()
		"solution":
			ids = solution_order.duplicate()
		_:
			ids = []

	for item_id in ids:
		if not resource_defs.has(item_id):
			continue

		var d: Dictionary = resource_defs[item_id] as Dictionary
		if str(d.get("kind", "resource")) != category:
			continue

		match category:
			"resource":
				if not _is_digest_resource_visible(item_id):
					continue
			"compound":
				if not is_compound_unlocked(item_id):
					continue
			"solution":
				if not is_solution_unlocked(item_id):
					continue

		var amount: int = get_amount(item_id)
		var base_value: float = _get_resource_base_value(item_id)
		var digest_each: float = base_value * get_current_digestion_modifier()

		out.append({
			"id": item_id,
			"name": str(d.get("name", item_id)),
			"kind": category,
			"amount": amount,
			"digest_each": digest_each,
			"digest_total": digest_each * float(amount)
		})

	return out
		
	
func _is_digest_resource_visible(item_id: String) -> bool:
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)
		var n: Dictionary = nodes[node_id] as Dictionary

		if not bool(n.get("is_unlocked", false)):
			continue

		var outputs: Array = (n.get("outputs", []) as Array)
		for output_variant in outputs:
			var od: Dictionary = output_variant as Dictionary
			if str(od.get("res", "")) == item_id:
				return true

	return false

# -----------------------------------------------------------------
# ---------------- Shared machine / unlock helpers ----------------
# -----------------------------------------------------------------

func _spend_nutrients(cost: int) -> void:
	if cost <= 0:
		return
	resources["nutrients"] = max(0.0, float(resources.get("nutrients", 0.0)) - float(cost))

func _get_config_slot_costs(config_key: String, fallback: Array) -> Array:
	var cfg_slots: Array = (config.get(config_key, []) as Array)
	if cfg_slots.is_empty():
		return fallback.duplicate(true)
	return cfg_slots.duplicate(true)


func _make_machine_slot(slot_number: int, default_craft_time_sec: float) -> Dictionary:
	return {
		"slot_number": slot_number,
		"recipe_id": "",
		"repeat_enabled": true,
		"in_progress": false,
		"progress_sec": 0.0,
		"craft_time_sec": default_craft_time_sec,
		"status": "Idle",
		"completed_count": 0
	}


func _ensure_machine_slots_initialized(
	config_key: String,
	fallback_costs: Array,
	slot_costs: Array,
	slots: Array,
	unlocked_slots: int,
	slot_factory: Callable
) -> int:
	if slot_costs.is_empty():
		var loaded_costs: Array = _get_config_slot_costs(config_key, fallback_costs)
		slot_costs.clear()
		slot_costs.append_array(loaded_costs)

	var old_slots: Array = slots.duplicate(true)
	if slots.size() != slot_costs.size():
		slots.clear()
		for i in range(slot_costs.size()):
			if i < old_slots.size():
				slots.append((old_slots[i] as Dictionary).duplicate(true))
			else:
				slots.append(slot_factory.call(i + 1))

	return clampi(unlocked_slots, 0, slot_costs.size())


func _can_unlock_progressive_slot(
	station_unlocked: bool,
	station_reason: String,
	slot_one_reason: String,
	slot_number: int,
	unlocked_slots: int,
	slot_costs: Array
) -> Dictionary:
	var out := {"ok": false, "reason": "Unavailable.", "cost": 0}

	if not station_unlocked:
		out["reason"] = station_reason
		return out

	if slot_number <= 1:
		out["reason"] = slot_one_reason
		return out

	if slot_number != unlocked_slots + 1:
		out["reason"] = "Unlock the previous slot first."
		return out

	if slot_number > slot_costs.size():
		out["reason"] = "No more slots."
		return out

	var cost := int(slot_costs[slot_number - 1])
	out["cost"] = cost

	if cost < 0:
		out["reason"] = "No cost set."
		return out

	if get_amount("nutrients") < cost:
		out["reason"] = "Not enough Nutrients."
		return out

	out["ok"] = true
	out["reason"] = ""
	return out


func _unlock_progressive_slot(slot_number: int, check: Dictionary) -> Dictionary:
	if not bool(check.get("ok", false)):
		return check

	_spend_nutrients(int(check.get("cost", 0)))
	check["new_unlocked_slots"] = slot_number
	return check


func _build_recipe_input_summary(recipe_def: Dictionary) -> String:
	var inputs: Array = recipe_def.get("inputs", []) as Array
	var input_parts: Array[String] = []

	for input_variant in inputs:
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue

		var res_name := res_id
		if resource_defs.has(res_id):
			res_name = str((resource_defs.get(res_id, {}) as Dictionary).get("name", res_id))

		var owned := get_amount(res_id)
		input_parts.append("%s %s (%s)" % [qty, res_name, owned])

	if input_parts.is_empty():
		return "—"

	return ", ".join(input_parts)


func _build_recipe_output_summary(recipe_name: String, output_qty: int) -> String:
	return "%s %s" % [output_qty, recipe_name]


func _assign_machine_recipe_to_slots(
	slot_number: int,
	recipe_id: String,
	unlocked_slots: int,
	slots: Array,
	allowed_recipe_ids: Array[String],
	craft_time_callable: Callable
) -> bool:
	if slot_number <= 0 or slot_number > unlocked_slots:
		return false

	if recipe_id != "" and not allowed_recipe_ids.has(recipe_id):
		return false

	var slot: Dictionary = (slots[slot_number - 1] as Dictionary).duplicate(true)
	slot["recipe_id"] = recipe_id
	slot["in_progress"] = false
	slot["progress_sec"] = 0.0
	slot["craft_time_sec"] = float(craft_time_callable.call(recipe_id))
	slot["status"] = "Idle" if recipe_id == "" else "Ready"
	slots[slot_number - 1] = slot
	return true


func _cycle_machine_recipe_in_slots(
	slot_number: int,
	unlocked_slots: int,
	slots: Array,
	allowed_recipe_ids: Array[String],
	craft_time_callable: Callable
) -> String:
	if slot_number <= 0 or slot_number > unlocked_slots:
		return ""

	var order: Array[String] = [""]
	for rid in allowed_recipe_ids:
		order.append(rid)

	var current: String = str((slots[slot_number - 1] as Dictionary).get("recipe_id", ""))
	var idx := order.find(current)
	if idx < 0:
		idx = 0

	var next_id := order[(idx + 1) % order.size()]
	_assign_machine_recipe_to_slots(slot_number, next_id, unlocked_slots, slots, allowed_recipe_ids, craft_time_callable)
	return next_id


func _toggle_machine_repeat_in_slots(slot_number: int, unlocked_slots: int, slots: Array) -> bool:
	if slot_number <= 0 or slot_number > unlocked_slots:
		return false

	var slot: Dictionary = (slots[slot_number - 1] as Dictionary).duplicate(true)
	slot["repeat_enabled"] = not bool(slot.get("repeat_enabled", true))
	slots[slot_number - 1] = slot
	return bool(slot["repeat_enabled"])


func _tick_machine_slots(
	dt: float,
	station_unlocked: bool,
	unlocked_slots: int,
	slots: Array,
	default_craft_time_sec: float,
	speed_mult: float,
	defs: Dictionary,
	can_afford_callable: Callable,
	spend_inputs_callable: Callable,
	grant_output_callable: Callable,
	craft_time_callable: Callable
) -> void:
	if not station_unlocked:
		return

	for i in range(unlocked_slots):
		var slot: Dictionary = (slots[i] as Dictionary).duplicate(true)
		var recipe_id := str(slot.get("recipe_id", ""))

		if recipe_id == "":
			slot["status"] = "Idle"
			slot["in_progress"] = false
			slot["progress_sec"] = 0.0
			slots[i] = slot
			continue

		if not defs.has(recipe_id):
			slot["status"] = "Invalid recipe"
			slot["in_progress"] = false
			slot["progress_sec"] = 0.0
			slots[i] = slot
			continue

		if not bool(slot.get("in_progress", false)):
			if bool(can_afford_callable.call(recipe_id)):
				spend_inputs_callable.call(recipe_id)
				slot["in_progress"] = true
				slot["progress_sec"] = 0.0
				slot["craft_time_sec"] = float(craft_time_callable.call(recipe_id))
				slot["status"] = "Crafting"
			else:
				slot["status"] = "Missing inputs"
				slots[i] = slot
				continue

		slot["progress_sec"] = float(slot.get("progress_sec", 0.0)) + (dt * speed_mult)

		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", default_craft_time_sec)))
		if float(slot.get("progress_sec", 0.0)) >= craft_time:
			grant_output_callable.call(recipe_id)
			slot["completed_count"] = int(slot.get("completed_count", 0)) + 1
			slot["progress_sec"] = 0.0
			slot["in_progress"] = false

			if bool(slot.get("repeat_enabled", true)):
				slot["status"] = "Ready"
			else:
				slot["status"] = "Complete"
				slot["recipe_id"] = ""

		slots[i] = slot


func _get_machine_ui_entries(
	station_unlocked: bool,
	unlocked_slots: int,
	slot_costs: Array,
	slots: Array,
	available_recipe_ids: Array[String],
	defs: Dictionary,
	default_craft_time_sec: float,
	can_unlock_slot_callable: Callable,
	get_slot_cost_callable: Callable
) -> Array:
	var out: Array = []
	if not station_unlocked:
		return out

	var recipe_names: Dictionary = {}
	for rid in available_recipe_ids:
		recipe_names[rid] = str((defs.get(rid, {}) as Dictionary).get("name", rid))

	for i in range(unlocked_slots):
		var slot: Dictionary = slots[i] as Dictionary
		var recipe_id := str(slot.get("recipe_id", ""))
		var recipe_name := "Idle"
		var input_summary := "—"
		var output_summary := "—"

		if recipe_id != "":
			recipe_name = str(recipe_names.get(recipe_id, recipe_id))
			var recipe_def: Dictionary = defs.get(recipe_id, {}) as Dictionary
			input_summary = _build_recipe_input_summary(recipe_def)
			output_summary = _build_recipe_output_summary(
				recipe_name,
				int(recipe_def.get("output_qty", 1))
			)

		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", default_craft_time_sec)))
		var progress := float(slot.get("progress_sec", 0.0))
		var pct := 0
		if recipe_id != "":
			pct = int(round(clamp(progress / craft_time, 0.0, 1.0) * 100.0))

		out.append({
			"type": "slot",
			"slot_number": i + 1,
			"recipe_id": recipe_id,
			"recipe_name": recipe_name,
			"repeat_enabled": bool(slot.get("repeat_enabled", true)),
			"status": str(slot.get("status", "Idle")),
			"progress_pct": pct,
			"progress_sec": progress,
			"craft_time_sec": craft_time,
			"completed_count": int(slot.get("completed_count", 0)),
			"input_summary": input_summary,
			"output_summary": output_summary
		})

	if unlocked_slots < slot_costs.size():
		var next_slot := unlocked_slots + 1
		var check: Dictionary = can_unlock_slot_callable.call(next_slot) as Dictionary
		out.append({
			"type": "unlock",
			"slot_number": next_slot,
			"cost": int(get_slot_cost_callable.call(next_slot)),
			"can_unlock": bool(check.get("ok", false)),
			"status": str(check.get("reason", ""))
		})

	return out


func _get_recipe_unlock_cost(defs: Dictionary, recipe_id: String) -> int:
	if not defs.has(recipe_id):
		return -1
	var d: Dictionary = defs[recipe_id] as Dictionary
	return int(d.get("unlock_cost_nutrients", -1))


func _recipe_starts_unlocked(defs: Dictionary, recipe_id: String) -> bool:
	if not defs.has(recipe_id):
		return false
	var d: Dictionary = defs[recipe_id] as Dictionary
	return bool(d.get("starts_unlocked", false))


func _recipe_is_active_in_pass1(defs: Dictionary, recipe_id: String) -> bool:
	if not defs.has(recipe_id):
		return false
	var d: Dictionary = defs[recipe_id] as Dictionary
	return bool(d.get("active_in_pass1", false))


func _get_recipe_previous_required(defs: Dictionary, recipe_id: String) -> String:
	if not defs.has(recipe_id):
		return ""
	var d: Dictionary = defs[recipe_id] as Dictionary
	var value = d.get("previous_recipe_required", null)
	if value == null:
		return ""
	return str(value).strip_edges()


func _get_recipe_discovery_requirement(defs: Dictionary, recipe_id: String) -> String:
	if not defs.has(recipe_id):
		return ""
	var d: Dictionary = defs[recipe_id] as Dictionary
	var value = d.get("discovery_requirement", null)
	if value == null:
		return ""
	return str(value).strip_edges()


func _get_recipe_display_name(defs: Dictionary, recipe_id: String) -> String:
	if defs.has(recipe_id):
		return str((defs[recipe_id] as Dictionary).get("name", recipe_id))
	return recipe_id


func _get_discovery_display_name(discovery_id: String) -> String:
	if discovery_defs.has(discovery_id):
		return str((discovery_defs[discovery_id] as Dictionary).get("name", discovery_id))
	return discovery_id


func _recipe_meets_discovery_requirement(defs: Dictionary, recipe_id: String) -> bool:
	var req := _get_recipe_discovery_requirement(defs, recipe_id)
	if req == "" or req == "null" or req == "<null>":
		return true
	return has_discovery(req)


func _is_progressive_recipe_unlocked(
	recipe_id: String,
	defs: Dictionary,
	station_unlocked: bool,
	paid_unlocks: Dictionary
) -> bool:
	if not defs.has(recipe_id):
		return false

	if not station_unlocked:
		return false

	if not _recipe_is_active_in_pass1(defs, recipe_id):
		return false

	if not _recipe_meets_discovery_requirement(defs, recipe_id):
		return false

	if _recipe_starts_unlocked(defs, recipe_id):
		return true

	return bool(paid_unlocks.get(recipe_id, false))


func _get_unlocked_recipe_ids_in_order(
	order: Array[String],
	defs: Dictionary,
	station_unlocked: bool,
	paid_unlocks: Dictionary
) -> Array[String]:
	var out: Array[String] = []

	if not station_unlocked:
		return out

	for recipe_id in order:
		if _is_progressive_recipe_unlocked(recipe_id, defs, station_unlocked, paid_unlocks):
			out.append(recipe_id)

	return out


func _get_visible_progressive_recipe_unlock_ids(
	order: Array[String],
	defs: Dictionary,
	station_unlocked: bool,
	paid_unlocks: Dictionary
) -> Array[String]:
	if not station_unlocked:
		return []

	var ordered: Array[String] = []
	for recipe_id in order:
		if not defs.has(recipe_id):
			continue

		if not _recipe_is_active_in_pass1(defs, recipe_id):
			continue

		if _is_progressive_recipe_unlocked(recipe_id, defs, station_unlocked, paid_unlocks):
			continue

		if not _recipe_meets_discovery_requirement(defs, recipe_id):
			continue

		var previous_recipe_id := _get_recipe_previous_required(defs, recipe_id)
		if previous_recipe_id != "" and previous_recipe_id != "null" and previous_recipe_id != "<null>":
			if not _is_progressive_recipe_unlocked(previous_recipe_id, defs, station_unlocked, paid_unlocks):
				continue

		var cost := _get_recipe_unlock_cost(defs, recipe_id)
		if cost < 0:
			continue

		ordered.append(recipe_id)

	if ordered.is_empty():
		return []

	return [ordered[0]]


func _can_unlock_progressive_recipe(
	recipe_id: String,
	defs: Dictionary,
	station_unlocked: bool,
	station_reason: String,
	paid_unlocks: Dictionary
) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "Unavailable.",
		"cost": 0
	}

	if not defs.has(recipe_id):
		out["reason"] = "Unknown recipe."
		return out

	if not station_unlocked:
		out["reason"] = station_reason
		return out

	if not _recipe_is_active_in_pass1(defs, recipe_id):
		out["reason"] = "Not active in this pass."
		return out

	if _is_progressive_recipe_unlocked(recipe_id, defs, station_unlocked, paid_unlocks):
		out["reason"] = "Already unlocked."
		return out

	if not _recipe_meets_discovery_requirement(defs, recipe_id):
		var discovery_id := _get_recipe_discovery_requirement(defs, recipe_id)
		out["reason"] = "Requires %s." % _get_discovery_display_name(discovery_id)
		return out

	var previous_recipe_id := _get_recipe_previous_required(defs, recipe_id)
	if previous_recipe_id != "" and previous_recipe_id != "null" and previous_recipe_id != "<null>":
		if not _is_progressive_recipe_unlocked(previous_recipe_id, defs, station_unlocked, paid_unlocks):
			out["reason"] = "Requires %s." % _get_recipe_display_name(defs, previous_recipe_id)
			return out

	var cost := _get_recipe_unlock_cost(defs, recipe_id)
	out["cost"] = cost

	if cost < 0:
		out["reason"] = "No unlock path set."
		return out

	if get_amount("nutrients") < cost:
		out["reason"] = "Not enough Nutrients."
		return out

	out["ok"] = true
	out["reason"] = ""
	return out


func _unlock_progressive_recipe(recipe_id: String, check: Dictionary, paid_unlocks: Dictionary) -> Dictionary:
	if not bool(check.get("ok", false)):
		return check

	_spend_nutrients(int(check.get("cost", 0)))
	paid_unlocks[recipe_id] = true
	check["ok"] = true
	check["reason"] = ""
	return check


func get_compound_unlock_cost(recipe_id: String) -> int:
	return _get_recipe_unlock_cost(compound_defs, recipe_id)


func is_compound_unlocked(recipe_id: String) -> bool:
	return _is_progressive_recipe_unlocked(
		recipe_id,
		compound_defs,
		is_refinery_unlocked(),
		paid_compound_unlocks
	)


func get_visible_compound_unlock_ids() -> Array[String]:
	return _get_visible_progressive_recipe_unlock_ids(
		compound_order,
		compound_defs,
		is_refinery_unlocked(),
		paid_compound_unlocks
	)


func can_unlock_compound_recipe(recipe_id: String) -> Dictionary:
	return _can_unlock_progressive_recipe(
		recipe_id,
		compound_defs,
		is_refinery_unlocked(),
		"Requires Primitive Refinery.",
		paid_compound_unlocks
	)


func unlock_compound_recipe(recipe_id: String) -> Dictionary:
	var check := can_unlock_compound_recipe(recipe_id)
	return _unlock_progressive_recipe(recipe_id, check, paid_compound_unlocks)


func get_solution_unlock_cost(recipe_id: String) -> int:
	return _get_recipe_unlock_cost(solution_defs, recipe_id)


func is_solution_unlocked(recipe_id: String) -> bool:
	return _is_progressive_recipe_unlocked(
		recipe_id,
		solution_defs,
		is_synth_unlocked(),
		paid_solution_unlocks
	)


func get_visible_solution_unlock_ids() -> Array[String]:
	return _get_visible_progressive_recipe_unlock_ids(
		solution_order,
		solution_defs,
		is_synth_unlocked(),
		paid_solution_unlocks
	)


func can_unlock_solution_recipe(recipe_id: String) -> Dictionary:
	return _can_unlock_progressive_recipe(
		recipe_id,
		solution_defs,
		is_synth_unlocked(),
		"Requires Synthesis.",
		paid_solution_unlocks
	)


func unlock_solution_recipe(recipe_id: String) -> Dictionary:
	var check := can_unlock_solution_recipe(recipe_id)
	return _unlock_progressive_recipe(recipe_id, check, paid_solution_unlocks)



func get_digest_efficiency() -> float:
	return get_current_digestion_modifier()


func is_digest_tab_unlocked(category: String) -> bool:
	match category:
		"resource":
			return true
		"compound":
			return is_refinery_unlocked()
		"solution":
			return is_synth_unlocked()
		_:
			return false

# ---------------- Upgrade config helpers ----------------

func _get_transport_cfg() -> Dictionary:
	return (config.get("transport", {}) as Dictionary)


func _get_root_pulse_base_speed() -> float:
	var tcfg: Dictionary = _get_transport_cfg()
	if tcfg.has("base_root_pulse_speed_px_per_sec"):
		return float(tcfg.get("base_root_pulse_speed_px_per_sec", BASE_ROOT_PULSE_SPEED))
	return float(tcfg.get("base_mite_speed_px_per_sec", BASE_ROOT_PULSE_SPEED))


func _get_transport_default_distance_px() -> float:
	var tcfg: Dictionary = _get_transport_cfg()
	return float(tcfg.get("default_distance_px", DEFAULT_DISTANCE_PX))


func _get_upgrade_curve_cfg(curve_key: String) -> Dictionary:
	var formulas: Dictionary = (config.get("upgrade_formulas", {}) as Dictionary)
	var cfg: Dictionary = (formulas.get(curve_key, {}) as Dictionary)

	if not cfg.is_empty():
		return cfg

	match curve_key:
		"yield_curve":
			return {
				"base": 0.0,
				"linear": YIELD_STEP,
				"quadratic": 0.0,
				"baseline_level": 1
			}
		"root_pulse_speed_curve":
			return {
				"base": 1.0,
				"linear": NODE_SPEED_STEP,
				"quadratic": 0.0,
				"baseline_level": 1
			}
		"root_pulse_capacity_curve":
			return {
				"base": float(BASE_CARRY),
				"linear": float(CARRY_STEP),
				"quadratic": 0.0,
				"baseline_level": 1
			}
		_:
			return {
				"base": 0.0,
				"linear": 0.0,
				"quadratic": 0.0,
				"baseline_level": 1
			}


func _get_upgrade_cost_cfg(stat_key: String) -> Dictionary:
	var costs: Dictionary = (config.get("upgrade_costs", {}) as Dictionary)
	var cfg: Dictionary = (costs.get(stat_key, {}) as Dictionary)

	if not cfg.is_empty():
		return cfg

	match stat_key:
		"yield_level":
			return {
				"base_cost": 25,
				"cost_mult": 1.3,
				"label": "Yield"
			}
		"node_speed_level":
			return {
				"base_cost": 35,
				"cost_mult": 1.3,
				"label": "Root Pulse Speed"
			}
		"carry_level":
			return {
				"base_cost": 50,
				"cost_mult": 1.3,
				"label": "Root Pulse Capacity"
			}
		_:
			return {
				"base_cost": 999999,
				"cost_mult": 1.0,
				"label": stat_key
			}


func _get_upgrade_label(stat_key: String) -> String:
	var cfg: Dictionary = _get_upgrade_cost_cfg(stat_key)
	return str(cfg.get("label", stat_key))


func _evaluate_upgrade_curve(curve_key: String, level: int) -> float:
	var cfg: Dictionary = _get_upgrade_curve_cfg(curve_key)
	var baseline_level: int = max(1, int(cfg.get("baseline_level", 1)))
	var x: int = max(0, level - baseline_level)

	var base: float = float(cfg.get("base", 0.0))
	var linear: float = float(cfg.get("linear", 0.0))
	var quadratic: float = float(cfg.get("quadratic", 0.0))

	return base + (linear * float(x)) + (quadratic * float(x * x))


func _get_yield_bonus_for_level(level: int) -> float:
	return maxf(0.0, _evaluate_upgrade_curve("yield_curve", level))


func _get_yield_multiplier_for_level(level: int) -> float:
	return 1.0 + _get_yield_bonus_for_level(level)


func _get_speed_multiplier_for_level(level: int) -> float:
	return maxf(0.01, _evaluate_upgrade_curve("root_pulse_speed_curve", level))


func _get_carry_capacity_for_level(level: int) -> int:
	var value: float = _evaluate_upgrade_curve("root_pulse_capacity_curve", level)
	return max(1, int(round(value)))

# ---------------- Upgrades ----------------

func _ensure_upgrade_keys(n: Dictionary) -> Dictionary:
	var up: Dictionary = (n.get("upgrades", {}) as Dictionary)
	up["yield_level"] = max(1, int(up.get("yield_level", 1)))
	up["node_speed_level"] = max(1, int(up.get("node_speed_level", 1)))
	up["carry_level"] = max(1, int(up.get("carry_level", 1)))
	return up


func _upgrade_cost(stat_key: String, level: int) -> int:
	var cfg: Dictionary = _get_upgrade_cost_cfg(stat_key)
	var base_cost: float = float(cfg.get("base_cost", 999999))
	var cost_mult: float = float(cfg.get("cost_mult", 1.0))
	return int(floor(base_cost * pow(cost_mult, float(max(0, level - 1)))))


func upgrade_node_stat(node_id: String, stat_key: String) -> bool:
	if not nodes.has(node_id):
		return false
	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_unlocked", false)):
		return false
	var up: Dictionary = _ensure_upgrade_keys(n)
	if not up.has(stat_key):
		return false
	var cur_level: int = int(up.get(stat_key, 1))
	var cost: int = _upgrade_cost(stat_key, cur_level)
	var nutrients: float = float(resources.get("nutrients", 0.0))
	if nutrients < float(cost):
		return false
	resources["nutrients"] = nutrients - float(cost)
	up[stat_key] = cur_level + 1
	n["upgrades"] = up
	nodes[node_id] = n
	return true


func get_node_upgrade_ui(node_id: String) -> Dictionary:
	var out: Dictionary = {
		"yield_label": _get_upgrade_label("yield_level"),
		"travel_label": _get_upgrade_label("node_speed_level"),
		"carry_label": _get_upgrade_label("carry_level"),
		"yield_level": 1,
		"yield_percent": "100%",
		"yield_cost": 0,
		"travel_level": 1,
		"travel_value": "0.0s/pulse",
		"travel_cost": 0,
		"carry_level": 1,
		"carry_value": "Cap 1",
		"carry_cost": 0
	}

	if not nodes.has(node_id):
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)

	var yl: int = int(up.get("yield_level", 1))
	var tl: int = int(up.get("node_speed_level", 1))
	var cl: int = int(up.get("carry_level", 1))

	var yield_percent: int = int(round(_get_yield_multiplier_for_level(yl) * 100.0))

	out["yield_level"] = yl
	out["yield_percent"] = str(yield_percent) + "%"
	out["yield_cost"] = _upgrade_cost("yield_level", yl)

	out["travel_level"] = tl
	out["travel_value"] = str(snapped(_get_node_pulse_sec(node_id), 0.1)) + "s/pulse"
	out["travel_cost"] = _upgrade_cost("node_speed_level", tl)

	out["carry_level"] = cl
	out["carry_value"] = "Cap " + str(_get_node_carry_capacity(node_id))
	out["carry_cost"] = _upgrade_cost("carry_level", cl)

	return out

func get_node_rate_ui(node_id: String) -> Dictionary:
	var out: Dictionary = {"base_rate": 0.0, "effective_rate": 0.0, "delivered_rate": 0.0}
	if not nodes.has(node_id):
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var yield_level: int = int(up.get("yield_level", 1))
	var base_rate_total: float = float(n.get("base_rate_total", 0.0))
	var yield_mult: float = _get_yield_multiplier_for_level(yield_level)
	var effective: float = base_rate_total * yield_mult

	out["base_rate"] = base_rate_total if bool(n.get("is_connected", false)) else 0.0
	out["effective_rate"] = effective if bool(n.get("is_connected", false)) else 0.0
	out["delivered_rate"] = _get_node_primary_delivered_rate(node_id)
	return out


# ---------------- Metadata / UI helpers ----------------

func get_amount(res_id: String) -> int:
	return int(floor(float(resources.get(res_id, 0.0))))


func add_amount(res_id: String, delta: int) -> void:
	resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) + float(delta))


func get_resource_name(res_id: String) -> String:
	if resource_defs.has(res_id):
		return str((resource_defs[res_id] as Dictionary).get("name", res_id.capitalize()))
	return res_id.capitalize()


func _get_resource_base_value(res_id: String) -> float:
	if resource_defs.has(res_id):
		var d: Dictionary = resource_defs[res_id] as Dictionary
		if d.has("base_value"):
			return float(d.get("base_value", 0.0))
	if RAW_BASE_VALUES.has(res_id):
		return float(RAW_BASE_VALUES[res_id])
	return 0.0


func get_resource_base_value(res_id: String) -> float:
	return _get_resource_base_value(res_id)


func get_resource_digest_value(res_id: String) -> float:
	return _get_resource_base_value(res_id) * get_current_digestion_modifier()


func get_node_display_name(node_id: String) -> String:
	if node_defs.has(node_id):
		return str((node_defs[node_id] as Dictionary).get("name", node_id))
	if nodes.has(node_id):
		return str((nodes[node_id] as Dictionary).get("name", node_id))
	return node_id


func get_node_definition(node_id: String) -> Dictionary:
	return (node_defs.get(node_id, {}) as Dictionary).duplicate(true)


func get_all_node_defs() -> Array:
	var out: Array = []
	for node_id in node_order:
		if node_defs.has(node_id):
			out.append((node_defs[node_id] as Dictionary).duplicate(true))
	return out


func get_starter_node_defs() -> Array:
	var out: Array = []
	for node_id in node_order:
		if not node_defs.has(node_id):
			continue
		var d: Dictionary = node_defs[node_id] as Dictionary
		if bool(d.get("is_starter", false)):
			out.append(d.duplicate(true))
	return out


func get_node_state_ui(node_id: String) -> Dictionary:
	if not nodes.has(node_id):
		return {"is_visible": false, "is_unlocked": false, "is_connected": false}
	var n: Dictionary = nodes[node_id] as Dictionary
	return {
		"is_visible": bool(n.get("is_visible", false)),
		"is_unlocked": bool(n.get("is_unlocked", false)),
		"is_connected": bool(n.get("is_connected", false)),
		"unlock_cost": int(n.get("unlock_cost", 0)),
		"reveal_rule": str(n.get("reveal_rule", "starter"))
	}


func try_unlock_node(node_id: String) -> bool:
	if not nodes.has(node_id):
		return false
	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_visible", false)):
		return false
	if bool(n.get("is_unlocked", false)):
		return true
	var cost: int = int(n.get("unlock_cost", 0))
	var nutrients: float = float(resources.get("nutrients", 0.0))
	if nutrients < float(cost):
		return false
	resources["nutrients"] = nutrients - float(cost)
	n["is_unlocked"] = true
	n["is_connected"] = true
	nodes[node_id] = n
	return true


func get_total_nutrients_earned_run() -> int:
	return int(floor(total_nutrients_earned_run))


func _update_node_reveals() -> void:
	if not is_aura_active():
		return
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)
		var n: Dictionary = nodes[node_id] as Dictionary
		if bool(n.get("is_visible", false)):
			continue
		if str(n.get("reveal_rule", "")) != "aura":
			continue
		var reveal_total: int = int(n.get("reveal_total_nutrients", 0))
		if total_nutrients_earned_run >= float(reveal_total):
			n["is_visible"] = true
			nodes[node_id] = n


# ---------------- Discovery state / effects ----------------

func get_connected_node_count() -> int:
	var count := 0
	for node_id_variant in nodes.keys():
		var n: Dictionary = nodes[str(node_id_variant)] as Dictionary
		if bool(n.get("is_connected", false)):
			count += 1
	return count


func can_show_discoveries_tab() -> bool:
	return get_connected_node_count() >= 2


func get_discovery_def(discovery_id: String) -> Dictionary:
	return (discovery_defs.get(discovery_id, {}) as Dictionary).duplicate(true)


func get_discovery_level(discovery_id: String) -> int:
	return int(discovery_levels.get(discovery_id, 0))


func has_discovery(discovery_id: String) -> bool:
	return bool(unlocked_discoveries.get(discovery_id, false))


func is_discovery_unlocked(discovery_id: String) -> bool:
	return has_discovery(discovery_id)


func is_refinery_unlocked() -> bool:
	return has_discovery("primitive_refinery")


func is_aura_active() -> bool:
	return has_discovery("aura_activation")


func is_excess_fertilizer_unlocked() -> bool:
	return has_discovery("excess_fertilizer")


func get_current_digestion_modifier() -> float:
	var base_mod: float = float(discovery_notes.get("base_digestion_modifier", DEFAULT_DISCOVERY_BASE_DIGESTION_MODIFIER))
	for discovery_id in discovery_order:
		if get_discovery_level(discovery_id) <= 0:
			continue
		var d: Dictionary = discovery_defs.get(discovery_id, {}) as Dictionary
		if str(d.get("effect_type", "")) == "digestion_return_additive":
			base_mod += float(d.get("effect_per_level", 0.0)) * float(get_discovery_level(discovery_id))
	return base_mod


func get_current_refinery_speed_multiplier() -> float:
	var bonus := 0.0
	for discovery_id in discovery_order:
		if get_discovery_level(discovery_id) <= 0:
			continue
		var d: Dictionary = discovery_defs.get(discovery_id, {}) as Dictionary
		if str(d.get("effect_type", "")) == "refinery_speed_mult":
			bonus += float(d.get("effect_per_level", 0.0)) * float(get_discovery_level(discovery_id))
	return 1.0 + bonus


func get_current_synth_speed_multiplier() -> float:
	var bonus := 0.0
	for discovery_id in discovery_order:
		if get_discovery_level(discovery_id) <= 0:
			continue
		var d: Dictionary = discovery_defs.get(discovery_id, {}) as Dictionary
		if str(d.get("effect_type", "")) == "synth_speed_mult":
			bonus += float(d.get("effect_per_level", 0.0)) * float(get_discovery_level(discovery_id))
	return 1.0 + bonus


func _get_discovery_base_costs(discovery_id: String) -> Array:
	if not discovery_defs.has(discovery_id):
		return []
	return ((discovery_defs[discovery_id] as Dictionary).get("costs", []) as Array).duplicate(true)


func get_discovery_costs_for_next_level(discovery_id: String) -> Array:
	if not discovery_defs.has(discovery_id):
		return []
	var d: Dictionary = discovery_defs[discovery_id] as Dictionary
	var costs: Array = _get_discovery_base_costs(discovery_id)
	var current_level: int = get_discovery_level(discovery_id)
	var mult: float = float(d.get("repeat_cost_mult", 1.0))
	if current_level <= 0 or mult <= 1.0:
		return costs
	var scaled: Array = []
	for c_variant in costs:
		var c: Dictionary = (c_variant as Dictionary).duplicate(true)
		var qty: int = int(c.get("qty", 0))
		c["qty"] = int(ceil(float(qty) * pow(mult, float(current_level))))
		scaled.append(c)
	return scaled


func _can_afford_costs(costs: Array) -> bool:
	for c_variant in costs:
		var c: Dictionary = c_variant as Dictionary
		var res_id: String = str(c.get("id", ""))
		var qty: int = int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		if get_amount(res_id) < qty:
			return false
	return true


func _spend_costs(costs: Array) -> void:
	for c_variant in costs:
		var c: Dictionary = c_variant as Dictionary
		var res_id: String = str(c.get("id", ""))
		var qty: int = int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) - float(qty))


func can_buy_discovery(discovery_id: String) -> Dictionary:
	var out := {"ok": false, "reason": "Unknown discovery.", "can_afford": false, "available": false}
	if not discovery_defs.has(discovery_id):
		return out
	var d: Dictionary = discovery_defs[discovery_id] as Dictionary
	var current_level: int = get_discovery_level(discovery_id)
	var max_level: int = int(d.get("max_level", 1))
	var repeatable: bool = bool(d.get("repeatable", false))
	if has_discovery(discovery_id) and (not repeatable or current_level >= max_level):
		out["reason"] = "Already complete."
		return out
	if not bool(d.get("active_in_pass1", false)):
		out["reason"] = "Not active in this pass."
		return out
	if not can_show_discoveries_tab():
		out["reason"] = "Connect a second node first."
		return out
	var req_nodes: int = int(d.get("requires_connected_nodes", 0))
	if get_connected_node_count() < req_nodes:
		out["reason"] = "Requires %s connected nodes." % req_nodes
		return out
	var parent_variant = d.get("parent", null)
	var parent_id := ""
	if parent_variant != null:
		parent_id = str(parent_variant)
	if parent_id != "" and not has_discovery(parent_id):
		var parent_name := parent_id
		if discovery_defs.has(parent_id):
			parent_name = str((discovery_defs[parent_id] as Dictionary).get("name", parent_id))
		out["reason"] = "Requires %s." % parent_name
		return out
	var costs: Array = get_discovery_costs_for_next_level(discovery_id)
	out["available"] = true
	out["can_afford"] = _can_afford_costs(costs)
	if not bool(out["can_afford"]):
		out["reason"] = "Not enough materials."
		return out
	out["ok"] = true
	out["reason"] = ""
	return out


func buy_discovery(discovery_id: String) -> Dictionary:
	var check := can_buy_discovery(discovery_id)
	if not bool(check.get("ok", false)):
		return check
	var d: Dictionary = discovery_defs[discovery_id] as Dictionary
	var costs: Array = get_discovery_costs_for_next_level(discovery_id)
	_spend_costs(costs)
	var new_level: int = get_discovery_level(discovery_id) + 1
	discovery_levels[discovery_id] = new_level
	unlocked_discoveries[discovery_id] = true
	if discovery_id == "primitive_refinery":
		_ensure_refinery_slots_initialized()
		unlocked_refinery_slots = max(unlocked_refinery_slots, 1)
	elif discovery_id == "synthesis":
		_ensure_synth_slots_initialized()
		unlocked_synth_slots = max(unlocked_synth_slots, 1)
	elif discovery_id == "aura_activation":
		_update_node_reveals()
	check["ok"] = true
	check["reason"] = ""
	check["new_level"] = new_level
	return check


func _get_discovery_effect_text(d: Dictionary) -> String:
	var effect_type: String = str(d.get("effect_type", ""))
	match effect_type:
		"unlock_center":
			return "Unlocks the first discovery branches."
		"unlock_refinery_tab_and_slot_1":
			return "Unlocks the Refinery tab and Slot 1."
		"unlock_aura_branch":
			return "Reveals the aura mechanic and enables aura-based node reveals."
		"spawn_temporary_bonus_nodes":
			return "Enables temporary bonus resource nodes."
		"digestion_return_additive":
			return "+%s digestion return per level." % str(int(round(float(d.get("effect_per_level", 0.0)) * 100.0)))
		_:
			return effect_type.replace("_", " ").capitalize()


func _format_discovery_costs(costs: Array) -> String:
	var parts: Array[String] = []
	for c_variant in costs:
		var c: Dictionary = c_variant as Dictionary
		var res_id: String = str(c.get("id", ""))
		var qty: int = int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		parts.append("%s %s" % [str(qty), get_resource_name(res_id)])
	return ", ".join(parts)


func get_discovery_ui_entries() -> Array:
	var out: Array = []
	if not can_show_discoveries_tab():
		return out

	var ordered_ids: Array[String] = _get_pass1_discovery_display_order()

	for discovery_id in ordered_ids:

		if not discovery_defs.has(discovery_id):
			continue

		var d: Dictionary = discovery_defs[discovery_id] as Dictionary

		if not _is_discovery_visible_in_panel(discovery_id, d):
			continue

		if discovery_id != "mycelial_insight" and not has_discovery("mycelial_insight"):
			continue

		if discovery_id == "nutrient_efficiency_1" and not has_discovery("excess_fertilizer"):
			continue

		var level: int = get_discovery_level(discovery_id)
		var costs: Array = get_discovery_costs_for_next_level(discovery_id)
		var check: Dictionary = can_buy_discovery(discovery_id)
		var max_level: int = int(d.get("max_level", 1))

		out.append({
			"id": discovery_id,
			"name": str(d.get("name", discovery_id)),
			"family": str(d.get("family", "")),
			"tier": int(d.get("tier", 0)),
			"repeatable": bool(d.get("repeatable", false)),
			"level": level,
			"max_level": max_level,
			"effect_text": _get_discovery_effect_text(d),
			"cost_text": _format_discovery_costs(costs),
			"available": bool(check.get("available", false)),
			"can_afford": bool(check.get("can_afford", false)),
			"can_buy": bool(check.get("ok", false)),
			"status_text": str(check.get("reason", "")),
			"complete": has_discovery(discovery_id) and (not bool(d.get("repeatable", false)) or level >= max_level)
		})

	return out


func get_current_run_discovery_progress() -> Dictionary:
	return {
		"unlocked_discoveries": unlocked_discoveries.duplicate(true),
		"discovery_levels": discovery_levels.duplicate(true)
	}

func _get_pass1_discovery_display_order() -> Array[String]:
	return [
		"mycelial_insight",
		"primitive_refinery",
		"synthesis",
		"aura_activation",
		"excess_fertilizer",
		"nutrient_efficiency_1"
	]

func _is_discovery_visible_in_panel(discovery_id: String, d: Dictionary) -> bool:
	if not bool(d.get("active_in_pass1", false)):
		return false

	# Already completed discoveries should always remain visible
	if has_discovery(discovery_id):
		return true

	# Treat missing / null / empty parent as "no parent requirement"
	var requires_value = d.get("requires_discovery", null)
	if requires_value == null:
		return true

	var requires_discovery := str(requires_value).strip_edges()
	if requires_discovery == "" or requires_discovery == "null" or requires_discovery == "<null>":
		return true

	# Otherwise only show after the parent discovery is completed
	return has_discovery(requires_discovery)


# ------------------------------------------
# ---------------- Refinery ----------------
# ------------------------------------------

func _ensure_refinery_slots_initialized() -> void:
	var fallback_costs: Array = [0, 50000, 250000, 2500000, 250000000, 10000000000]
	unlocked_refinery_slots = _ensure_machine_slots_initialized(
		"refinery_slots",
		fallback_costs,
		refinery_slot_costs,
		refinery_slots,
		unlocked_refinery_slots,
		Callable(self, "_make_empty_refinery_slot")
	)


func _make_empty_refinery_slot(slot_number: int) -> Dictionary:
	return _make_machine_slot(slot_number, _get_refinery_default_craft_time_sec())


func _get_refinery_default_craft_time_sec() -> float:
	var refinery_cfg: Dictionary = (config.get("refinery", {}) as Dictionary)
	return float(refinery_cfg.get("default_craft_time_sec", DEFAULT_REFINERY_BASE_CRAFT_SEC))


func _get_refinery_pass1_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	var refinery_cfg: Dictionary = (config.get("refinery", {}) as Dictionary)
	var ids: Array = (refinery_cfg.get("pass1_recipe_ids", []) as Array)
	if ids.is_empty():
		ids = DEFAULT_REFINERY_PASS1_RECIPE_IDS
	for id_variant in ids:
		var rid := str(id_variant)
		if rid != "" and compound_defs.has(rid):
			out.append(rid)
	return out


func get_unlocked_refinery_slot_count() -> int:
	return unlocked_refinery_slots


func get_refinery_slot_cost(slot_number: int) -> int:
	_ensure_refinery_slots_initialized()
	if slot_number <= 0 or slot_number > refinery_slot_costs.size():
		return -1
	return int(refinery_slot_costs[slot_number - 1])


func can_unlock_refinery_slot(slot_number: int) -> Dictionary:
	_ensure_refinery_slots_initialized()
	return _can_unlock_progressive_slot(
		is_refinery_unlocked(),
		"Requires Primitive Refinery.",
		"Slot 1 is granted by Primitive Refinery.",
		slot_number,
		unlocked_refinery_slots,
		refinery_slot_costs
	)


func unlock_refinery_slot(slot_number: int) -> Dictionary:
	var check := can_unlock_refinery_slot(slot_number)
	if not bool(check.get("ok", false)):
		return check

	check = _unlock_progressive_slot(slot_number, check)
	unlocked_refinery_slots = max(unlocked_refinery_slots, slot_number)
	return check


func get_available_compound_recipe_ids() -> Array[String]:
	return _get_unlocked_recipe_ids_in_order(
		compound_order,
		compound_defs,
		is_refinery_unlocked(),
		paid_compound_unlocks
	)


func get_compound_def(recipe_id: String) -> Dictionary:
	return (compound_defs.get(recipe_id, {}) as Dictionary).duplicate(true)


func _get_compound_recipe_inputs(recipe_id: String) -> Array:
	if not compound_defs.has(recipe_id):
		return []
	return ((compound_defs[recipe_id] as Dictionary).get("inputs", []) as Array).duplicate(true)


func _get_compound_recipe_output_qty(recipe_id: String) -> int:
	if not compound_defs.has(recipe_id):
		return 0
	return int((compound_defs[recipe_id] as Dictionary).get("output_qty", 1))


func _get_compound_recipe_craft_time_sec(recipe_id: String) -> float:
	if compound_defs.has(recipe_id):
		var d: Dictionary = compound_defs[recipe_id] as Dictionary
		if d.has("craft_time_sec"):
			return float(d.get("craft_time_sec", _get_refinery_default_craft_time_sec()))
	return _get_refinery_default_craft_time_sec()


func _can_afford_compound_inputs(recipe_id: String) -> bool:
	for input_variant in _get_compound_recipe_inputs(recipe_id):
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		if get_amount(res_id) < qty:
			return false
	return true


func _spend_compound_inputs(recipe_id: String) -> void:
	for input_variant in _get_compound_recipe_inputs(recipe_id):
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) - float(qty))


func _grant_compound_output(recipe_id: String) -> void:
	var qty := _get_compound_recipe_output_qty(recipe_id)
	if qty <= 0:
		return
	if not resources.has(recipe_id):
		resources[recipe_id] = 0.0
	resources[recipe_id] = float(resources.get(recipe_id, 0.0)) + float(qty)


func assign_refinery_recipe(slot_number: int, recipe_id: String) -> bool:
	_ensure_refinery_slots_initialized()
	return _assign_machine_recipe_to_slots(
		slot_number,
		recipe_id,
		unlocked_refinery_slots,
		refinery_slots,
		get_available_compound_recipe_ids(),
		Callable(self, "_get_compound_recipe_craft_time_sec")
	)


func clear_refinery_recipe(slot_number: int) -> void:
	assign_refinery_recipe(slot_number, "")


func cycle_refinery_recipe(slot_number: int) -> String:
	_ensure_refinery_slots_initialized()
	return _cycle_machine_recipe_in_slots(
		slot_number,
		unlocked_refinery_slots,
		refinery_slots,
		get_available_compound_recipe_ids(),
		Callable(self, "_get_compound_recipe_craft_time_sec")
	)


func toggle_refinery_repeat(slot_number: int) -> bool:
	_ensure_refinery_slots_initialized()
	return _toggle_machine_repeat_in_slots(slot_number, unlocked_refinery_slots, refinery_slots)


func _tick_refinery(dt: float) -> void:
	_ensure_refinery_slots_initialized()
	_tick_machine_slots(
		dt,
		is_refinery_unlocked(),
		unlocked_refinery_slots,
		refinery_slots,
		_get_refinery_default_craft_time_sec(),
		get_current_refinery_speed_multiplier(),
		compound_defs,
		Callable(self, "_can_afford_compound_inputs"),
		Callable(self, "_spend_compound_inputs"),
		Callable(self, "_grant_compound_output"),
		Callable(self, "_get_compound_recipe_craft_time_sec")
	)


func get_refinery_ui_entries() -> Array:
	_ensure_refinery_slots_initialized()
	return _get_machine_ui_entries(
		is_refinery_unlocked(),
		unlocked_refinery_slots,
		refinery_slot_costs,
		refinery_slots,
		get_available_compound_recipe_ids(),
		compound_defs,
		_get_refinery_default_craft_time_sec(),
		Callable(self, "can_unlock_refinery_slot"),
		Callable(self, "get_refinery_slot_cost")
	)






func _register_compounds_as_resources() -> void:
	for recipe_id in compound_order:
		var d: Dictionary = compound_defs[recipe_id] as Dictionary
		var base_value: float = _compute_compound_base_value(recipe_id, {})
		resource_defs[recipe_id] = {
			"id": recipe_id,
			"name": str(d.get("name", recipe_id)),
			"kind": "compound",
			"format": "compact_int",
			"base_value": base_value
		}
		if not resources.has(recipe_id):
			resources[recipe_id] = 0.0


func _register_solutions_as_resources() -> void:
	for recipe_id in solution_order:
		var d: Dictionary = solution_defs[recipe_id] as Dictionary
		var base_value: float = _compute_solution_base_value(recipe_id, {})
		resource_defs[recipe_id] = {
			"id": recipe_id,
			"name": str(d.get("name", recipe_id)),
			"kind": "solution",
			"format": "compact_int",
			"base_value": base_value
		}
		if not resources.has(recipe_id):
			resources[recipe_id] = 0.0


func _compute_material_base_value(material_id: String, seen: Dictionary = {}) -> float:
	if resource_defs.has(material_id):
		var d: Dictionary = resource_defs[material_id] as Dictionary
		if d.has("base_value"):
			return float(d.get("base_value", 0.0))
	if RAW_BASE_VALUES.has(material_id):
		return float(RAW_BASE_VALUES[material_id])
	if compound_defs.has(material_id):
		return _compute_compound_base_value(material_id, seen)
	if solution_defs.has(material_id):
		return _compute_solution_base_value(material_id, seen)
	return 0.0


func _compute_compound_base_value(recipe_id: String, seen: Dictionary) -> float:
	if seen.has(recipe_id):
		return 0.0
	if not compound_defs.has(recipe_id):
		return 0.0
	seen[recipe_id] = true
	var d: Dictionary = compound_defs[recipe_id] as Dictionary
	var total: float = 0.0
	for input_variant in (d.get("inputs", []) as Array):
		var c: Dictionary = input_variant as Dictionary
		total += _compute_material_base_value(str(c.get("id", "")), seen.duplicate(true)) * float(c.get("qty", 0))
	var mult: float = float((compounds_meta.get("rules", {}) as Dictionary).get("base_value_multiplier", 1.35))
	return total * mult


func _compute_solution_base_value(recipe_id: String, seen: Dictionary) -> float:
	if seen.has(recipe_id):
		return 0.0
	if not solution_defs.has(recipe_id):
		return 0.0
	seen[recipe_id] = true
	var d: Dictionary = solution_defs[recipe_id] as Dictionary
	var total: float = 0.0
	for input_variant in (d.get("inputs", []) as Array):
		var c: Dictionary = input_variant as Dictionary
		total += _compute_material_base_value(str(c.get("id", "")), seen.duplicate(true)) * float(c.get("qty", 0))
	var mult: float = float((solutions_meta.get("rules", {}) as Dictionary).get("value_multiplier", 1.45))
	return total * mult


# -------------------------------------------
# ---------------- Synthesis ----------------
# -------------------------------------------

func is_synth_unlocked() -> bool:
	return bool(unlocked_discoveries.get("synthesis", false))


func get_unlocked_synth_slot_count() -> int:
	return unlocked_synth_slots


func _make_empty_synth_slot(slot_number: int) -> Dictionary:
	return _make_machine_slot(slot_number, _get_synth_default_craft_time_sec())


func get_available_solution_recipe_ids() -> Array[String]:
	return _get_unlocked_recipe_ids_in_order(
		solution_order,
		solution_defs,
		is_synth_unlocked(),
		paid_solution_unlocks
	)


func _ensure_synth_slots_initialized() -> void:
	var fallback_costs: Array = [0, 50000, 250000, 2500000, 250000000, 10000000000]
	unlocked_synth_slots = _ensure_machine_slots_initialized(
		"synth_slots",
		fallback_costs,
		synth_slot_costs,
		synth_slots,
		unlocked_synth_slots,
		Callable(self, "_make_empty_synth_slot")
	)


func _get_synth_default_craft_time_sec() -> float:
	var synth_cfg: Dictionary = {}
	if config.has("synthesis"):
		synth_cfg = (config.get("synthesis", {}) as Dictionary)
	elif config.has("synth"):
		synth_cfg = (config.get("synth", {}) as Dictionary)
	return float(synth_cfg.get("default_craft_time_sec", 8.0))


func get_synth_slot_cost(slot_number: int) -> int:
	_ensure_synth_slots_initialized()
	if slot_number <= 0 or slot_number > synth_slot_costs.size():
		return -1
	return int(synth_slot_costs[slot_number - 1])


func can_unlock_synth_slot(slot_number: int) -> Dictionary:
	_ensure_synth_slots_initialized()
	return _can_unlock_progressive_slot(
		is_synth_unlocked(),
		"Requires Synthesis.",
		"Slot 1 is granted by Synthesis.",
		slot_number,
		unlocked_synth_slots,
		synth_slot_costs
	)


func unlock_synth_slot(slot_number: int) -> Dictionary:
	var check := can_unlock_synth_slot(slot_number)
	if not bool(check.get("ok", false)):
		return check

	check = _unlock_progressive_slot(slot_number, check)
	unlocked_synth_slots = max(unlocked_synth_slots, slot_number)
	return check


func _get_solution_recipe_inputs(recipe_id: String) -> Array:
	if not solution_defs.has(recipe_id):
		return []
	return ((solution_defs[recipe_id] as Dictionary).get("inputs", []) as Array).duplicate(true)


func _get_solution_recipe_output_qty(recipe_id: String) -> int:
	if not solution_defs.has(recipe_id):
		return 0
	return int((solution_defs[recipe_id] as Dictionary).get("output_qty", 1))


func _get_solution_recipe_craft_time_sec(recipe_id: String) -> float:
	if solution_defs.has(recipe_id):
		var d: Dictionary = solution_defs[recipe_id] as Dictionary
		if d.has("craft_time_sec"):
			return float(d.get("craft_time_sec", _get_synth_default_craft_time_sec()))
	return _get_synth_default_craft_time_sec()


func _can_afford_solution_inputs(recipe_id: String) -> bool:
	for input_variant in _get_solution_recipe_inputs(recipe_id):
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		if get_amount(res_id) < qty:
			return false
	return true


func _spend_solution_inputs(recipe_id: String) -> void:
	for input_variant in _get_solution_recipe_inputs(recipe_id):
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) - float(qty))


func _grant_solution_output(recipe_id: String) -> void:
	var qty := _get_solution_recipe_output_qty(recipe_id)
	if qty <= 0:
		return
	if not resources.has(recipe_id):
		resources[recipe_id] = 0.0
	resources[recipe_id] = float(resources.get(recipe_id, 0.0)) + float(qty)


func assign_synth_recipe(slot_number: int, recipe_id: String) -> bool:
	_ensure_synth_slots_initialized()
	return _assign_machine_recipe_to_slots(
		slot_number,
		recipe_id,
		unlocked_synth_slots,
		synth_slots,
		get_available_solution_recipe_ids(),
		Callable(self, "_get_solution_recipe_craft_time_sec")
	)


func cycle_synth_recipe(slot_number: int) -> String:
	_ensure_synth_slots_initialized()
	return _cycle_machine_recipe_in_slots(
		slot_number,
		unlocked_synth_slots,
		synth_slots,
		get_available_solution_recipe_ids(),
		Callable(self, "_get_solution_recipe_craft_time_sec")
	)


func toggle_synth_repeat(slot_number: int) -> bool:
	_ensure_synth_slots_initialized()
	return _toggle_machine_repeat_in_slots(slot_number, unlocked_synth_slots, synth_slots)


func clear_synth_recipe(slot_number: int) -> void:
	assign_synth_recipe(slot_number, "")


func _tick_synth(dt: float) -> void:
	_ensure_synth_slots_initialized()
	_tick_machine_slots(
		dt,
		is_synth_unlocked(),
		unlocked_synth_slots,
		synth_slots,
		_get_synth_default_craft_time_sec(),
		get_current_synth_speed_multiplier(),
		solution_defs,
		Callable(self, "_can_afford_solution_inputs"),
		Callable(self, "_spend_solution_inputs"),
		Callable(self, "_grant_solution_output"),
		Callable(self, "_get_solution_recipe_craft_time_sec")
	)


func get_synth_ui_entries() -> Array:
	_ensure_synth_slots_initialized()
	return _get_machine_ui_entries(
		is_synth_unlocked(),
		unlocked_synth_slots,
		synth_slot_costs,
		synth_slots,
		get_available_solution_recipe_ids(),
		solution_defs,
		_get_synth_default_craft_time_sec(),
		Callable(self, "can_unlock_synth_slot"),
		Callable(self, "get_synth_slot_cost")
	)

# ---------------- Root transfer state helpers ----------------

func _read_node_root_transfer_dict(n: Dictionary) -> Dictionary:
	if n.has(NODE_ROOT_TRANSFER_KEY) and typeof(n.get(NODE_ROOT_TRANSFER_KEY, {})) == TYPE_DICTIONARY:
		return (n.get(NODE_ROOT_TRANSFER_KEY, {}) as Dictionary)

	if n.has(LEGACY_NODE_TRANSPORT_KEY) and typeof(n.get(LEGACY_NODE_TRANSPORT_KEY, {})) == TYPE_DICTIONARY:
		return (n.get(LEGACY_NODE_TRANSPORT_KEY, {}) as Dictionary)

	return {}


func _write_node_root_transfer_dict(n: Dictionary, transfer: Dictionary) -> void:
	n[NODE_ROOT_TRANSFER_KEY] = transfer.duplicate(true)

	# Keep legacy shadow key for one stabilization pass so older assumptions don't break.
	n[LEGACY_NODE_TRANSPORT_KEY] = transfer.duplicate(true)


# ---------------- Save / Load ----------------

func _build_default_meta_state() -> Dictionary:
	return {
		"strain_points": 0,
		"prestige_count": 0,
		"permanent_unlocks": {}
	}


func _sync_meta_state_into_resources() -> void:
	resources["strain_points"] = float(meta_state.get("strain_points", 0))


func _build_saved_node_state(node_id: String) -> Dictionary:
	if not nodes.has(node_id):
		return {}

	var n: Dictionary = nodes[node_id] as Dictionary
	var root_transfer: Dictionary = _read_node_root_transfer_dict(n)

	return {
		"pool": (n.get("pool", {}) as Dictionary).duplicate(true),
		"root_transfer": root_transfer.duplicate(true),
		"transport": root_transfer.duplicate(true),
		"upgrades": (n.get("upgrades", {}) as Dictionary).duplicate(true),
		"is_visible": bool(n.get("is_visible", false)),
		"is_unlocked": bool(n.get("is_unlocked", false)),
		"is_connected": bool(n.get("is_connected", false))
	}


func _build_run_save_data() -> Dictionary:
	var saved_resources: Dictionary = resources.duplicate(true)
	saved_resources.erase("strain_points")

	var saved_nodes: Dictionary = {}
	for node_id in node_order:
		saved_nodes[node_id] = _build_saved_node_state(node_id)

	return {
		"resources": saved_resources,
		"nodes": saved_nodes,
		"unlocked_discoveries": unlocked_discoveries.duplicate(true),
		"discovery_levels": discovery_levels.duplicate(true),
		"total_nutrients_earned_run": total_nutrients_earned_run,
		"paid_compound_unlocks": paid_compound_unlocks.duplicate(true),
		"paid_solution_unlocks": paid_solution_unlocks.duplicate(true),
		"unlocked_refinery_slots": unlocked_refinery_slots,
		"refinery_slots": refinery_slots.duplicate(true),
		"unlocked_synth_slots": unlocked_synth_slots,
		"synth_slots": synth_slots.duplicate(true)
	}


func _build_meta_save_data() -> Dictionary:
	return meta_state.duplicate(true)


func _build_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"run_state": _build_run_save_data(),
		"meta_state": _build_meta_save_data()
	}


func has_save_data() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)


func save_game() -> bool:
	var f := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if f == null:
		return false

	f.store_string(JSON.stringify(_build_save_data(), "\t"))
	f.close()
	_autosave_accum = 0.0
	return true


func _apply_meta_state(loaded_meta: Dictionary) -> void:
	meta_state = _build_default_meta_state()

	if loaded_meta.is_empty():
		return

	meta_state["strain_points"] = max(0, int(loaded_meta.get("strain_points", meta_state.get("strain_points", 0))))
	meta_state["prestige_count"] = max(0, int(loaded_meta.get("prestige_count", meta_state.get("prestige_count", 0))))

	var permanent_unlocks_variant = loaded_meta.get("permanent_unlocks", {})
	if typeof(permanent_unlocks_variant) == TYPE_DICTIONARY:
		meta_state["permanent_unlocks"] = (permanent_unlocks_variant as Dictionary).duplicate(true)


func _normalize_loaded_machine_slot(
	slot_variant,
	slot_number: int,
	default_craft_time_sec: float,
	defs: Dictionary
) -> Dictionary:
	var slot := _make_machine_slot(slot_number, default_craft_time_sec)

	if typeof(slot_variant) != TYPE_DICTIONARY:
		return slot

	var src: Dictionary = slot_variant as Dictionary
	var recipe_id := str(src.get("recipe_id", ""))
	if recipe_id != "" and not defs.has(recipe_id):
		recipe_id = ""

	slot["recipe_id"] = recipe_id
	slot["repeat_enabled"] = bool(src.get("repeat_enabled", true))
	slot["in_progress"] = bool(src.get("in_progress", false))
	slot["progress_sec"] = maxf(0.0, float(src.get("progress_sec", 0.0)))
	slot["craft_time_sec"] = maxf(0.1, float(src.get("craft_time_sec", default_craft_time_sec)))
	slot["status"] = str(src.get("status", "Idle" if recipe_id == "" else "Ready"))
	slot["completed_count"] = max(0, int(src.get("completed_count", 0)))

	if recipe_id == "":
		slot["in_progress"] = false
		slot["progress_sec"] = 0.0
		slot["status"] = "Idle"

	return slot


func _apply_loaded_machine_slots(
	loaded_slots_variant,
	slots: Array,
	default_craft_time_sec: float,
	defs: Dictionary
) -> void:
	if typeof(loaded_slots_variant) != TYPE_ARRAY:
		return

	var loaded_slots: Array = loaded_slots_variant as Array
	for i in range(min(slots.size(), loaded_slots.size())):
		slots[i] = _normalize_loaded_machine_slot(
			loaded_slots[i],
			i + 1,
			default_craft_time_sec,
			defs
		)


func _apply_loaded_nodes(loaded_nodes: Dictionary) -> void:
	for node_id_variant in loaded_nodes.keys():
		var node_id := str(node_id_variant)
		if not nodes.has(node_id):
			continue

		var saved_node_variant = loaded_nodes[node_id_variant]
		if typeof(saved_node_variant) != TYPE_DICTIONARY:
			continue

		var saved_node: Dictionary = saved_node_variant as Dictionary
		var current: Dictionary = (nodes[node_id] as Dictionary).duplicate(true)

		if saved_node.has("pool") and typeof(saved_node.get("pool", {})) == TYPE_DICTIONARY:
			current["pool"] = (saved_node.get("pool", {}) as Dictionary).duplicate(true)

		var loaded_root_transfer: Dictionary = {}
		if saved_node.has("root_transfer") and typeof(saved_node.get("root_transfer", {})) == TYPE_DICTIONARY:
			loaded_root_transfer = (saved_node.get("root_transfer", {}) as Dictionary).duplicate(true)
		elif saved_node.has("transport") and typeof(saved_node.get("transport", {})) == TYPE_DICTIONARY:
			loaded_root_transfer = (saved_node.get("transport", {}) as Dictionary).duplicate(true)

		_write_node_root_transfer_dict(current, loaded_root_transfer)

		if saved_node.has("upgrades") and typeof(saved_node.get("upgrades", {})) == TYPE_DICTIONARY:
			var temp := {"upgrades": (saved_node.get("upgrades", {}) as Dictionary).duplicate(true)}
			current["upgrades"] = _ensure_upgrade_keys(temp)

		current["is_visible"] = bool(saved_node.get("is_visible", current.get("is_visible", false)))
		current["is_unlocked"] = bool(saved_node.get("is_unlocked", current.get("is_unlocked", false)))
		current["is_connected"] = bool(saved_node.get("is_connected", current.get("is_connected", false)))

		_write_node_root_transfer_dict(current, _ensure_root_transfer_state(current, node_id))
		nodes[node_id] = current


func _apply_run_state(loaded_run: Dictionary) -> void:
	if loaded_run.is_empty():
		_sync_meta_state_into_resources()
		return

	var loaded_resources_variant = loaded_run.get("resources", {})
	if typeof(loaded_resources_variant) == TYPE_DICTIONARY:
		var loaded_resources: Dictionary = loaded_resources_variant as Dictionary
		for res_id_variant in loaded_resources.keys():
			var res_id := str(res_id_variant)
			var value := float(loaded_resources[res_id_variant])

			if resources.has(res_id) or resource_defs.has(res_id) or res_id == "nutrients" or res_id == "glowcaps":
				resources[res_id] = value

	total_nutrients_earned_run = float(loaded_run.get("total_nutrients_earned_run", 0.0))

	var loaded_unlocked_discoveries_variant = loaded_run.get("unlocked_discoveries", {})
	if typeof(loaded_unlocked_discoveries_variant) == TYPE_DICTIONARY:
		var loaded_unlocked_discoveries: Dictionary = loaded_unlocked_discoveries_variant as Dictionary
		for discovery_id_variant in loaded_unlocked_discoveries.keys():
			var discovery_id := str(discovery_id_variant)
			if unlocked_discoveries.has(discovery_id):
				unlocked_discoveries[discovery_id] = bool(loaded_unlocked_discoveries[discovery_id_variant])

	var loaded_discovery_levels_variant = loaded_run.get("discovery_levels", {})
	if typeof(loaded_discovery_levels_variant) == TYPE_DICTIONARY:
		var loaded_discovery_levels: Dictionary = loaded_discovery_levels_variant as Dictionary
		for discovery_id_variant in loaded_discovery_levels.keys():
			var discovery_id := str(discovery_id_variant)
			if discovery_levels.has(discovery_id):
				discovery_levels[discovery_id] = max(0, int(loaded_discovery_levels[discovery_id_variant]))

	var loaded_paid_compounds_variant = loaded_run.get("paid_compound_unlocks", {})
	if typeof(loaded_paid_compounds_variant) == TYPE_DICTIONARY:
		var loaded_paid_compounds: Dictionary = loaded_paid_compounds_variant as Dictionary
		for recipe_id_variant in loaded_paid_compounds.keys():
			var recipe_id := str(recipe_id_variant)
			if compound_defs.has(recipe_id):
				paid_compound_unlocks[recipe_id] = bool(loaded_paid_compounds[recipe_id_variant])

	var loaded_paid_solutions_variant = loaded_run.get("paid_solution_unlocks", {})
	if typeof(loaded_paid_solutions_variant) == TYPE_DICTIONARY:
		var loaded_paid_solutions: Dictionary = loaded_paid_solutions_variant as Dictionary
		for recipe_id_variant in loaded_paid_solutions.keys():
			var recipe_id := str(recipe_id_variant)
			if solution_defs.has(recipe_id):
				paid_solution_unlocks[recipe_id] = bool(loaded_paid_solutions[recipe_id_variant])

	var loaded_nodes_variant = loaded_run.get("nodes", {})
	if typeof(loaded_nodes_variant) == TYPE_DICTIONARY:
		_apply_loaded_nodes(loaded_nodes_variant as Dictionary)

	_ensure_refinery_slots_initialized()
	unlocked_refinery_slots = clampi(
		int(loaded_run.get("unlocked_refinery_slots", unlocked_refinery_slots)),
		0,
		refinery_slot_costs.size()
	)
	_apply_loaded_machine_slots(
		loaded_run.get("refinery_slots", []),
		refinery_slots,
		_get_refinery_default_craft_time_sec(),
		compound_defs
	)

	_ensure_synth_slots_initialized()
	unlocked_synth_slots = clampi(
		int(loaded_run.get("unlocked_synth_slots", unlocked_synth_slots)),
		0,
		synth_slot_costs.size()
	)
	_apply_loaded_machine_slots(
		loaded_run.get("synth_slots", []),
		synth_slots,
		_get_synth_default_craft_time_sec(),
		solution_defs
	)

	_sync_meta_state_into_resources()
	_update_node_reveals()


func load_game() -> bool:
	if not has_save_data():
		return false

	var save_data = _load_json(SAVE_FILE_PATH)
	if typeof(save_data) != TYPE_DICTIONARY:
		return false

	var root: Dictionary = save_data as Dictionary
	_load_all()
	_apply_meta_state((root.get("meta_state", {}) as Dictionary))
	_apply_run_state((root.get("run_state", {}) as Dictionary))
	_autosave_accum = 0.0
	return true


func start_new_run() -> void:
	var preserved_meta := _build_meta_save_data()
	_load_all()
	_apply_meta_state(preserved_meta)
	_sync_meta_state_into_resources()
	save_game()


func reset_all_progress() -> void:
	_load_all()
	save_game()


# ---------------- Loading ----------------

func _load_all() -> void:
	config.clear()
	compounds_meta.clear()
	compound_defs.clear()
	compound_order.clear()
	solutions_meta.clear()
	solution_defs.clear()
	solution_order.clear()
	raw_resource_order.clear()
	resource_defs.clear()
	node_defs.clear()
	node_order.clear()
	discovery_defs.clear()
	discovery_order.clear()
	discovery_notes.clear()
	unlocked_discoveries.clear()
	discovery_levels.clear()
	meta_state.clear()
	resources.clear()
	nodes.clear()
	node_world_positions.clear()
	spore_cloud_world_pos = Vector2.ZERO
	total_nutrients_earned_run = 0.0
	refinery_slot_costs.clear()
	refinery_slots.clear()
	unlocked_refinery_slots = 0
	paid_compound_unlocks.clear()
	paid_solution_unlocks.clear()
	synth_slot_costs.clear()
	synth_slots.clear()
	unlocked_synth_slots = 0
	_autosave_accum = 0.0

	var config_data = _load_json("res://data/config.json")
	if config_data is Dictionary:
		config = (config_data as Dictionary).duplicate(true)
	else:
		config = {}

	var discoveries_data = _load_json("res://data/discoveries.json")
	if discoveries_data is Dictionary:
		discovery_notes = ((discoveries_data as Dictionary).get("notes", {}) as Dictionary).duplicate(true)
		var dlist: Array = ((discoveries_data as Dictionary).get("discoveries", []) as Array)
		for d_variant in dlist:
			var dsrc: Dictionary = d_variant as Dictionary
			var did: String = str(dsrc.get("id", ""))
			if did == "":
				continue
			discovery_order.append(did)
			discovery_defs[did] = dsrc.duplicate(true)
			unlocked_discoveries[did] = false
			discovery_levels[did] = 0

	var res_data = _load_json("res://data/resources.json")
	if res_data is Dictionary:
		var res_list: Array = ((res_data as Dictionary).get("resources", []) as Array)
		for r_variant in res_list:
			var r: Dictionary = r_variant as Dictionary
			var res_id: String = str(r.get("id", ""))
			if res_id == "":
				continue
			resource_defs[res_id] = r.duplicate(true)
			resources[res_id] = 0.0
			var kind: String = str(r.get("kind", "resource"))
			if kind == "resource":
				raw_resource_order.append(res_id)

	var compounds_data = _load_json("res://data/compounds.json")
	if compounds_data is Dictionary:
		compounds_meta = (compounds_data as Dictionary).duplicate(true)
		for c_variant in ((compounds_data as Dictionary).get("compounds", []) as Array):
			var csrc: Dictionary = c_variant as Dictionary
			var cid := str(csrc.get("id", ""))
			if cid == "":
				continue
			compound_order.append(cid)
			compound_defs[cid] = csrc.duplicate(true)

	var solutions_data = _load_json("res://data/solutions.json")
	if solutions_data is Dictionary:
		solutions_meta = (solutions_data as Dictionary).duplicate(true)
		for s_variant in ((solutions_data as Dictionary).get("solutions", []) as Array):
			var ssrc: Dictionary = s_variant as Dictionary
			var sid: String = str(ssrc.get("id", ""))
			if sid == "":
				continue
			solution_order.append(sid)
			solution_defs[sid] = ssrc.duplicate(true)

	# seed starting amounts
	var starts: Dictionary = (config.get("starting_resources", {}) as Dictionary)
	resources["nutrients"] = float(starts.get("nutrients", 12500.0))
	resources["glowcaps"] = float(starts.get("glowcaps", 0.0))
	resources["strain_points"] = float(starts.get("strain_points", 0.0))

	meta_state = _build_default_meta_state()
	_register_compounds_as_resources()
	_register_solutions_as_resources()
	_ensure_refinery_slots_initialized()
	_ensure_synth_slots_initialized()

	var nodes_data = _load_json("res://data/nodes.json")
	if nodes_data is Dictionary:
		var nlist: Array = ((nodes_data as Dictionary).get("nodes", []) as Array)
		for n_variant in nlist:
			var nsrc: Dictionary = n_variant as Dictionary
			var nid: String = str(nsrc.get("id", ""))
			if nid == "":
				continue
			node_order.append(nid)
			var static_def: Dictionary = nsrc.duplicate(true)
			node_defs[nid] = static_def
			nodes[nid] = _build_runtime_node(static_def)
	else:
		_seed_defaults()

	_sync_meta_state_into_resources()

func _build_runtime_node(static_def: Dictionary) -> Dictionary:
	var up_src = static_def.get("upgrades", null)
	var upgrades: Dictionary
	if up_src == null:
		upgrades = {"yield_level": 1, "node_speed_level": 1, "carry_level": 1}
	else:
		upgrades = (up_src as Dictionary).duplicate(true)

	var runtime: Dictionary = {
		"id": str(static_def.get("id", "")),
		"name": str(static_def.get("name", "")),
		"scene_node_name": str(static_def.get("scene_node_name", "")),
		"line_node_name": str(static_def.get("line_node_name", "")),
		"primary_resource": str(static_def.get("primary_resource", "")),
		"secondary_resource": str(static_def.get("secondary_resource", "")),
		"unlock_cost": int(static_def.get("unlock_cost", 0)),
		"distance_px": float(static_def.get("distance_px", DEFAULT_DISTANCE_PX)),
		"ring": int(static_def.get("ring", 1)),
		"reveal_rule": str(static_def.get("reveal_rule", "starter")),
		"reveal_total_nutrients": int(static_def.get("reveal_total_nutrients", 0)),
		"base_rate_total": float(static_def.get("base_rate_total", 0.0)),
		"pool_cap": int(static_def.get("pool_cap", 50)),
		"outputs": static_def.get("outputs", []),
		"upgrades": upgrades,
		"pool": {},
		"root_transfer": {},
		"transport": {},
		"is_visible": bool(static_def.get("starts_visible", true)),
		"is_unlocked": bool(static_def.get("starts_unlocked", true)),
		"is_connected": bool(static_def.get("starts_connected", true))
	}

	runtime["upgrades"] = _ensure_upgrade_keys(runtime)
	return runtime
	

func _seed_defaults() -> void:
	resource_defs = {
		"nutrients": {"id": "nutrients", "name": "Nutrients"},
		"glowcaps": {"id": "glowcaps", "name": "Glowcaps"},
		"strain_points": {"id": "strain_points", "name": "Strain Points"},
		"spores": {"id": "spores", "name": "Spores", "base_value": 1},
		"hyphae": {"id": "hyphae", "name": "Hyphae", "base_value": 2},
		"cellulose": {"id": "cellulose", "name": "Cellulose", "base_value": 4},
		"mycelium": {"id": "mycelium", "name": "Mycelium", "base_value": 7}
	}
	resources = {
		"nutrients": 12500.0,
		"glowcaps": 0.0,
		"strain_points": 0.0,
		"spores": 0.0,
		"hyphae": 0.0,
		"cellulose": 0.0,
		"mycelium": 0.0
	}
	_ensure_refinery_slots_initialized()
	var damp_def := {
		"id": "damp_soil",
		"name": "Damp Soil",
		"scene_node_name": "Node_DampSoil",
		"line_node_name": "Line_DampSoil",
		"primary_resource": "spores",
		"unlock_cost": 75,
		"distance_px": 360,
		"ring": 1,
		"reveal_rule": "starter",
		"reveal_total_nutrients": 0,
		"starts_visible": true,
		"starts_unlocked": true,
		"starts_connected": true,
		"base_rate_total": 0.25,
		"outputs": [{"res": "spores", "weight": 1.0, "amount_per_unit": 1.0}],
		"upgrades": {"yield_level": 1, "node_speed_level": 1, "carry_level": 1}
	}
	node_defs["damp_soil"] = damp_def
	node_order = ["damp_soil"]
	nodes["damp_soil"] = _build_runtime_node(damp_def)


func _load_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	var err: int = parser.parse(txt)
	if err != OK:
		push_warning("JSON parse failed: " + path + " line %d" % parser.get_error_line())
		push_warning(parser.get_error_message())
		return null
	return parser.data
