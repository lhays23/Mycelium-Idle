extends Node

const TICK_DT: float = 0.1

# Upgrade tuning (Phase 6 placeholder values; can move to config later)
const YIELD_STEP: float = 0.10
const NODE_SPEED_STEP: float = 0.10
const CARRY_STEP: int = 1

# Transport tuning
const BASE_MITE_SPEED: float = 150.0
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
const PASS1_DISCOVERY_IDS := ["mycelial_insight", "primitive_refinery", "aura_activation", "excess_fertilizer", "nutrient_efficiency_1"]
const DEFAULT_REFINERY_PASS1_RECIPE_IDS := ["spore_composite", "hyphal_thread", "cellulose_weave", "growth_gel"]
const DEFAULT_REFINERY_BASE_CRAFT_SEC := 4.0

var config: Dictionary = {}
var compounds_meta: Dictionary = {}
var compound_defs: Dictionary = {}
var compound_order: Array[String] = []
var solutions_meta: Dictionary = {}
var solution_defs: Dictionary = {}
var solution_order: Array[String] = []
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

var refinery_slot_costs: Array = []
var unlocked_refinery_slots: int = 0
var refinery_slots: Array = []
var paid_compound_unlocks: Dictionary = {}
var paid_solution_unlocks: Dictionary = {}
var synth_slot_costs: Array = []
var unlocked_synth_slots: int = 0
var synth_slots: Array = []

var _accum: float = 0.0

# World-space positions for transport calculations
var spore_cloud_world_pos: Vector2 = Vector2.ZERO
var node_world_positions: Dictionary = {}  # node_id -> Vector2


func _ready() -> void:
	_load_all()
	set_process(true)


func _process(dt: float) -> void:
	_accum += dt
	while _accum >= TICK_DT:
		_accum -= TICK_DT
		tick(TICK_DT)


func tick(dt: float) -> void:
	_update_node_reveals()
	_tick_node_production(dt)
	_tick_transport(dt)
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
		var yield_bonus_levels: int = max(0, yield_level - 1)
		var yield_mult: float = 1.0 + float(yield_bonus_levels) * YIELD_STEP
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


# ---------------- Transport ----------------

func register_spore_cloud_world_position(pos: Vector2) -> void:
	spore_cloud_world_pos = pos


func register_node_world_position(node_id: String, pos: Vector2) -> void:
	node_world_positions[node_id] = pos


func _tick_transport(dt: float) -> void:
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)
		var n: Dictionary = nodes[node_id] as Dictionary
		if not bool(n.get("is_connected", false)):
			var stopped_transport: Dictionary = _ensure_transport_state(n, node_id)
			stopped_transport["carrying_visual"] = false
			stopped_transport["cargo"] = {}
			n["transport"] = stopped_transport
			nodes[node_id] = n
			continue

		var transport: Dictionary = _ensure_transport_state(n, node_id)
		var trip_sec: float = max(0.25, _get_node_trip_sec(node_id))
		var leg_sec: float = max(0.01, _get_node_leg_sec(node_id))
		var pickup_sec: float = leg_sec + LOAD_UNLOAD_SEC
		var base_arrival_sec: float = pickup_sec + leg_sec

		var progress_sec: float = float(transport.get("progress_sec", 0.0))
		var pickup_checked: bool = bool(transport.get("pickup_checked", false))
		var delivery_checked: bool = bool(transport.get("delivery_checked", false))
		var cargo: Dictionary = (transport.get("cargo", {}) as Dictionary)
		var pickup_event_id: int = int(transport.get("pickup_event_id", 0))
		var delivery_event_id: int = int(transport.get("delivery_event_id", 0))
		var pickup_amount: int = int(transport.get("pickup_amount", 0))
		var delivery_amount: int = int(transport.get("delivery_amount", 0))

		progress_sec += dt

		while true:
			if not pickup_checked and progress_sec >= pickup_sec:
				cargo = _pickup_one_trip(node_id)
				pickup_amount = _cargo_total(cargo)
				if pickup_amount > 0:
					pickup_event_id += 1
				pickup_checked = true

			if not delivery_checked and progress_sec >= base_arrival_sec:
				delivery_amount = _deliver_cargo_to_base(cargo)
				if delivery_amount > 0:
					delivery_event_id += 1
				cargo = {}
				delivery_checked = true

			if progress_sec < trip_sec:
				break

			progress_sec -= trip_sec
			pickup_checked = false
			delivery_checked = false
			cargo = {}

		transport["progress_sec"] = progress_sec
		transport["pickup_checked"] = pickup_checked
		transport["delivery_checked"] = delivery_checked
		transport["cargo"] = cargo
		transport["carrying_visual"] = _cargo_total(cargo) > 0
		transport["pickup_event_id"] = pickup_event_id
		transport["delivery_event_id"] = delivery_event_id
		transport["pickup_amount"] = pickup_amount
		transport["delivery_amount"] = delivery_amount
		transport["remaining_sec"] = max(0.0, trip_sec - progress_sec)

		n["transport"] = transport
		nodes[node_id] = n


func _ensure_transport_state(n: Dictionary, node_id: String) -> Dictionary:
	var transport: Dictionary = (n.get("transport", {}) as Dictionary)
	if not transport.has("progress_sec"):
		transport["progress_sec"] = 0.0
	if not transport.has("pickup_checked"):
		transport["pickup_checked"] = false
	if not transport.has("delivery_checked"):
		transport["delivery_checked"] = false
	if not transport.has("cargo"):
		transport["cargo"] = {}
	if not transport.has("carrying_visual"):
		transport["carrying_visual"] = false
	if not transport.has("pickup_event_id"):
		transport["pickup_event_id"] = 0
	if not transport.has("delivery_event_id"):
		transport["delivery_event_id"] = 0
	if not transport.has("pickup_amount"):
		transport["pickup_amount"] = 0
	if not transport.has("delivery_amount"):
		transport["delivery_amount"] = 0
	transport["remaining_sec"] = max(0.0, _get_node_trip_sec(node_id) - float(transport.get("progress_sec", 0.0)))
	return transport


func _pickup_one_trip(node_id: String) -> Dictionary:
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
		pool[res_id] = max(0.0, float(pool.get(res_id, 0.0)) - float(take))
		cargo[res_id] = take
		carry_left -= take

	n["pool"] = pool
	nodes[node_id] = n
	return cargo


func _deliver_cargo_to_base(cargo: Dictionary) -> int:
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


func _cargo_total(cargo: Dictionary) -> int:
	var total: int = 0
	for value_variant in cargo.values():
		total += int(value_variant)
	return total


func _get_node_distance(node_id: String) -> float:
	if node_world_positions.has(node_id):
		var node_pos: Vector2 = node_world_positions[node_id]
		return max(1.0, node_pos.distance_to(spore_cloud_world_pos))
	if node_defs.has(node_id):
		return max(1.0, float((node_defs[node_id] as Dictionary).get("distance_px", DEFAULT_DISTANCE_PX)))
	return DEFAULT_DISTANCE_PX


func _get_node_speed_value(node_id: String) -> float:
	if not nodes.has(node_id):
		return BASE_MITE_SPEED
	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var lvl: int = int(up.get("node_speed_level", 1))
	var bonus_levels: int = max(0, lvl - 1)
	return BASE_MITE_SPEED * (1.0 + float(bonus_levels) * NODE_SPEED_STEP)


func _get_node_carry_capacity(node_id: String) -> int:
	if not nodes.has(node_id):
		return BASE_CARRY
	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var lvl: int = int(up.get("carry_level", 1))
	return max(1, BASE_CARRY + (max(0, lvl - 1) * CARRY_STEP))


func _get_node_leg_sec(node_id: String) -> float:
	var distance_px: float = _get_node_distance(node_id)
	var speed: float = max(1.0, _get_node_speed_value(node_id))
	return distance_px / speed


func _get_node_trip_sec(node_id: String) -> float:
	var leg_sec: float = _get_node_leg_sec(node_id)
	return (2.0 * leg_sec) + (2.0 * LOAD_UNLOAD_SEC)


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
	var yield_bonus_levels: int = max(0, yield_level - 1)
	var yield_mult: float = 1.0 + float(yield_bonus_levels) * YIELD_STEP
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


func _get_node_primary_delivered_rate(node_id: String) -> float:
	if not nodes.has(node_id):
		return 0.0
	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_connected", false)):
		return 0.0
	var prod_primary: float = _get_node_primary_production_rate(node_id)
	var trip_sec: float = max(0.25, _get_node_trip_sec(node_id))
	var carry: int = _get_node_carry_capacity(node_id)
	var transport_capacity: float = float(carry) / trip_sec
	return min(prod_primary, transport_capacity)


func get_node_mite_visual(node_id: String) -> Dictionary:
	var out: Dictionary = {"route_t": 0.0, "carrying": false, "visible": false}
	if not nodes.has(node_id):
		return out
	var n: Dictionary = nodes[node_id] as Dictionary
	if not bool(n.get("is_connected", false)):
		return out
	out["visible"] = true
	var transport: Dictionary = _ensure_transport_state(n, node_id)
	var trip_sec: float = max(0.25, _get_node_trip_sec(node_id))
	var leg_sec: float = max(0.01, _get_node_leg_sec(node_id))
	var pickup_sec: float = leg_sec + LOAD_UNLOAD_SEC
	var return_end_sec: float = pickup_sec + leg_sec
	var progress_sec: float = clamp(float(transport.get("progress_sec", 0.0)), 0.0, trip_sec)
	var carrying_visual: bool = bool(transport.get("carrying_visual", false))
	if progress_sec < leg_sec:
		out["route_t"] = progress_sec / leg_sec
		out["carrying"] = false
	elif progress_sec < pickup_sec:
		out["route_t"] = 1.0
		out["carrying"] = false
	elif progress_sec < return_end_sec:
		var return_t: float = (progress_sec - pickup_sec) / leg_sec
		out["route_t"] = 1.0 - return_t
		out["carrying"] = carrying_visual
	else:
		out["route_t"] = 0.0
		out["carrying"] = carrying_visual
	return out


func get_node_transport_feedback(node_id: String) -> Dictionary:
	var out: Dictionary = {
		"pickup_event_id": 0,
		"pickup_amount": 0,
		"delivery_event_id": 0,
		"delivery_amount": 0
	}
	if not nodes.has(node_id):
		return out
	var n: Dictionary = nodes[node_id] as Dictionary
	var transport: Dictionary = _ensure_transport_state(n, node_id)
	out["pickup_event_id"] = int(transport.get("pickup_event_id", 0))
	out["pickup_amount"] = int(transport.get("pickup_amount", 0))
	out["delivery_event_id"] = int(transport.get("delivery_event_id", 0))
	out["delivery_amount"] = int(transport.get("delivery_amount", 0))
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


func get_compound_unlock_cost(recipe_id: String) -> int:
	match recipe_id:
		"spore_composite":
			return 0
		"hyphal_thread":
			return 3000
		"cellulose_weave":
			return 10000
		"growth_gel":
			return 25000
		_:
			return -1


func is_compound_unlocked(recipe_id: String) -> bool:
	if not compound_defs.has(recipe_id):
		return false

	if not is_refinery_unlocked():
		return false

	match recipe_id:
		"spore_composite":
			return true
		"hyphal_thread", "cellulose_weave", "growth_gel":
			return bool(paid_compound_unlocks.get(recipe_id, false))
		_:
			return false

func get_visible_compound_unlock_ids() -> Array[String]:
	if not is_refinery_unlocked():
		return []

	var ordered: Array[String] = []
	for recipe_id_variant in compound_order:
		var recipe_id := str(recipe_id_variant)

		# Only consider real refinery pass compounds for now.
		if not compound_defs.has(recipe_id):
			continue

		# Skip already unlocked recipes.
		if is_compound_unlocked(recipe_id):
			continue

		ordered.append(recipe_id)

	# Progressive reveal:
	# only show the next locked compound unlock
	if ordered.is_empty():
		return []

	return [ordered[0]]
	
	
func can_unlock_compound_recipe(recipe_id: String) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "Unavailable.",
		"cost": 0
	}

	if not compound_defs.has(recipe_id):
		out["reason"] = "Unknown recipe."
		return out

	if not is_refinery_unlocked():
		out["reason"] = "Requires Primitive Refinery."
		return out

	if is_compound_unlocked(recipe_id):
		out["reason"] = "Already unlocked."
		return out

	var cost := get_compound_unlock_cost(recipe_id)
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


func unlock_compound_recipe(recipe_id: String) -> Dictionary:
	var check := can_unlock_compound_recipe(recipe_id)
	if not bool(check.get("ok", false)):
		return check

	var cost := int(check.get("cost", 0))
	if cost > 0:
		resources["nutrients"] = max(0.0, float(resources.get("nutrients", 0.0)) - float(cost))

	paid_compound_unlocks[recipe_id] = true
	check["ok"] = true
	check["reason"] = ""
	return check


func get_solution_unlock_cost(recipe_id: String) -> int:
	match recipe_id:
		"mycelial_resin":
			return 0
		_:
			return -1


func is_solution_unlocked(recipe_id: String) -> bool:
	if not solution_defs.has(recipe_id):
		return false

	if not is_synth_unlocked():
		return false

	match recipe_id:
		"mycelial_resin":
			return true
		_:
			return false


func can_unlock_solution_recipe(recipe_id: String) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "Unavailable.",
		"cost": 0
	}

	if not solution_defs.has(recipe_id):
		out["reason"] = "Unknown recipe."
		return out

	if not is_synth_unlocked():
		out["reason"] = "Requires Synthesis."
		return out

	if is_solution_unlocked(recipe_id):
		out["reason"] = "Already unlocked."
		return out

	var cost := get_solution_unlock_cost(recipe_id)
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


func unlock_solution_recipe(recipe_id: String) -> Dictionary:
	var check := can_unlock_solution_recipe(recipe_id)
	if not bool(check.get("ok", false)):
		return check

	var cost := int(check.get("cost", 0))
	if cost > 0:
		resources["nutrients"] = max(0.0, float(resources.get("nutrients", 0.0)) - float(cost))

	paid_solution_unlocks[recipe_id] = true
	check["ok"] = true
	check["reason"] = ""
	return check
	
	
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


# ---------------- Upgrades ----------------

func _ensure_upgrade_keys(n: Dictionary) -> Dictionary:
	var up: Dictionary = (n.get("upgrades", {}) as Dictionary)
	up["yield_level"] = max(1, int(up.get("yield_level", 1)))
	up["node_speed_level"] = max(1, int(up.get("node_speed_level", 1)))
	up["carry_level"] = max(1, int(up.get("carry_level", 1)))
	return up


func _upgrade_cost(stat_key: String, level: int) -> int:
	match stat_key:
		"yield_level":
			return int(floor(25.0 * pow(1.30, float(level - 1))))
		"node_speed_level":
			return int(floor(35.0 * pow(1.30, float(level - 1))))
		"carry_level":
			return int(floor(50.0 * pow(1.30, float(level - 1))))
		_:
			return 999999


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
		"yield_level": 1,
		"yield_percent": "100%",
		"yield_cost": 0,
		"travel_level": 1,
		"travel_value": "5.0s/trip",
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
	var bonus_levels: int = max(0, yl - 1)
	var yield_percent: int = int(round((1.0 + float(bonus_levels) * YIELD_STEP) * 100.0))
	out["yield_level"] = yl
	out["yield_percent"] = str(yield_percent) + "%"
	out["yield_cost"] = _upgrade_cost("yield_level", yl)
	out["travel_level"] = tl
	out["travel_value"] = str(snapped(_get_node_trip_sec(node_id), 0.1)) + "s/trip"
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
	var bonus_levels: int = max(0, yield_level - 1)
	var yield_mult: float = 1.0 + float(bonus_levels) * YIELD_STEP
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
	for discovery_id in PASS1_DISCOVERY_IDS:
		if not discovery_defs.has(discovery_id):
			continue
		# Visibility rules for first pass
		if discovery_id != "mycelial_insight" and not has_discovery("mycelial_insight"):
			continue
		if discovery_id == "nutrient_efficiency_1" and not has_discovery("excess_fertilizer"):
			continue
		var d: Dictionary = discovery_defs[discovery_id] as Dictionary
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


# ---------------- Refinery ----------------

func _ensure_refinery_slots_initialized() -> void:
	if refinery_slot_costs.is_empty():
		var cfg_slots: Array = (config.get("refinery_slots", []) as Array)
		if cfg_slots.is_empty():
			refinery_slot_costs = [0, 50000, 250000, 2500000, 250000000, 10000000000]
		else:
			refinery_slot_costs = cfg_slots.duplicate(true)
	if refinery_slots.size() != refinery_slot_costs.size():
		refinery_slots.clear()
		for i in range(refinery_slot_costs.size()):
			refinery_slots.append(_make_empty_refinery_slot(i + 1))


func _make_empty_refinery_slot(slot_number: int) -> Dictionary:
	return {
		"slot_number": slot_number,
		"recipe_id": "",
		"repeat_enabled": true,
		"in_progress": false,
		"progress_sec": 0.0,
		"craft_time_sec": _get_refinery_default_craft_time_sec(),
		"status": "Idle",
		"completed_count": 0
	}


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
	var out := {"ok": false, "reason": "Unavailable.", "cost": 0}
	if not is_refinery_unlocked():
		out["reason"] = "Requires Primitive Refinery."
		return out
	_ensure_refinery_slots_initialized()
	if slot_number <= 1:
		out["reason"] = "Slot 1 is granted by Primitive Refinery."
		return out
	if slot_number != unlocked_refinery_slots + 1:
		out["reason"] = "Unlock the previous slot first."
		return out
	if slot_number > refinery_slot_costs.size():
		out["reason"] = "No more slots."
		return out
	var cost := get_refinery_slot_cost(slot_number)
	out["cost"] = cost
	if get_amount("nutrients") < cost:
		out["reason"] = "Not enough Nutrients."
		return out
	out["ok"] = true
	out["reason"] = ""
	return out


func unlock_refinery_slot(slot_number: int) -> Dictionary:
	var check := can_unlock_refinery_slot(slot_number)
	if not bool(check.get("ok", false)):
		return check
	resources["nutrients"] = max(0.0, float(resources.get("nutrients", 0.0)) - float(check.get("cost", 0)))
	unlocked_refinery_slots = max(unlocked_refinery_slots, slot_number)
	check["new_unlocked_slots"] = unlocked_refinery_slots
	return check


func get_available_compound_recipe_ids() -> Array[String]:
	if not is_refinery_unlocked():
		return []

	var out: Array[String] = []
	for recipe_id in _get_refinery_pass1_recipe_ids():
		if is_compound_unlocked(recipe_id):
			out.append(recipe_id)
	return out
	

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
	if slot_number <= 0 or slot_number > unlocked_refinery_slots:
		return false
	var allowed := get_available_compound_recipe_ids()
	if recipe_id != "" and not allowed.has(recipe_id):
		return false
	var slot: Dictionary = (refinery_slots[slot_number - 1] as Dictionary).duplicate(true)
	slot["recipe_id"] = recipe_id
	slot["in_progress"] = false
	slot["progress_sec"] = 0.0
	slot["craft_time_sec"] = _get_compound_recipe_craft_time_sec(recipe_id)
	slot["status"] = "Idle" if recipe_id == "" else "Ready"
	refinery_slots[slot_number - 1] = slot
	return true


func clear_refinery_recipe(slot_number: int) -> void:
	assign_refinery_recipe(slot_number, "")


func cycle_refinery_recipe(slot_number: int) -> String:
	_ensure_refinery_slots_initialized()
	if slot_number <= 0 or slot_number > unlocked_refinery_slots:
		return ""
	var allowed := get_available_compound_recipe_ids()
	var order: Array[String] = [""]
	for rid in allowed:
		order.append(rid)
	var current: String = str((refinery_slots[slot_number - 1] as Dictionary).get("recipe_id", ""))
	var idx := order.find(current)
	if idx < 0:
		idx = 0
	var next_id := order[(idx + 1) % order.size()]
	assign_refinery_recipe(slot_number, next_id)
	return next_id


func toggle_refinery_repeat(slot_number: int) -> bool:
	_ensure_refinery_slots_initialized()
	if slot_number <= 0 or slot_number > unlocked_refinery_slots:
		return false
	var slot: Dictionary = (refinery_slots[slot_number - 1] as Dictionary).duplicate(true)
	slot["repeat_enabled"] = not bool(slot.get("repeat_enabled", true))
	refinery_slots[slot_number - 1] = slot
	return bool(slot["repeat_enabled"])


func _tick_refinery(dt: float) -> void:
	if not is_refinery_unlocked():
		return
	_ensure_refinery_slots_initialized()
	var speed_mult: float = maxf(0.01, float(get_current_refinery_speed_multiplier()))
	for i in range(unlocked_refinery_slots):
		var slot: Dictionary = (refinery_slots[i] as Dictionary).duplicate(true)
		var recipe_id := str(slot.get("recipe_id", ""))
		if recipe_id == "":
			slot["status"] = "Idle"
			slot["in_progress"] = false
			slot["progress_sec"] = 0.0
			refinery_slots[i] = slot
			continue
		if not bool(slot.get("in_progress", false)):
			if _can_afford_compound_inputs(recipe_id):
				_spend_compound_inputs(recipe_id)
				slot["in_progress"] = true
				slot["progress_sec"] = 0.0
				slot["craft_time_sec"] = _get_compound_recipe_craft_time_sec(recipe_id)
				slot["status"] = "Crafting"
			else:
				slot["status"] = "Missing inputs"
				refinery_slots[i] = slot
				continue
		slot["progress_sec"] = float(slot.get("progress_sec", 0.0)) + (dt * speed_mult)
		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", _get_refinery_default_craft_time_sec())))
		if float(slot.get("progress_sec", 0.0)) >= craft_time:
			_grant_compound_output(recipe_id)
			slot["completed_count"] = int(slot.get("completed_count", 0)) + 1
			slot["progress_sec"] = 0.0
			slot["in_progress"] = false
			if bool(slot.get("repeat_enabled", true)):
				slot["status"] = "Ready"
			else:
				slot["status"] = "Complete"
				slot["recipe_id"] = ""
		refinery_slots[i] = slot


func get_refinery_ui_entries() -> Array:
	var out: Array = []
	if not is_refinery_unlocked():
		return out
	_ensure_refinery_slots_initialized()
	var recipe_names: Dictionary = {}
	for rid in get_available_compound_recipe_ids():
		recipe_names[rid] = str((compound_defs.get(rid, {}) as Dictionary).get("name", rid))
	for i in range(unlocked_refinery_slots):
		var slot: Dictionary = refinery_slots[i] as Dictionary
		var recipe_id := str(slot.get("recipe_id", ""))
		var recipe_name := "Idle"
		var input_summary := "—"
		var output_summary := "—"
		if recipe_id != "":
			recipe_name = str(recipe_names.get(recipe_id, recipe_id))
			var recipe_def: Dictionary = compound_defs.get(recipe_id, {}) as Dictionary
			var inputs: Array = recipe_def.get("inputs", []) as Array
			var output_qty: int = int(recipe_def.get("output_qty", 1))
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
			if not input_parts.is_empty():
				input_summary = ", ".join(input_parts)
			output_summary = "%s %s" % [output_qty, recipe_name]
		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", _get_refinery_default_craft_time_sec())))
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
	if unlocked_refinery_slots < refinery_slot_costs.size():
		var next_slot := unlocked_refinery_slots + 1
		var check := can_unlock_refinery_slot(next_slot)
		out.append({
			"type": "unlock",
			"slot_number": next_slot,
			"cost": get_refinery_slot_cost(next_slot),
			"can_unlock": bool(check.get("ok", false)),
			"status": str(check.get("reason", ""))
		})
	return out
	
	
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


# ---------------- Synthesis ----------------

func is_synth_unlocked() -> bool:
	return bool(unlocked_discoveries.get("synthesis", false))


func _get_synth_pass1_recipe_ids() -> Array[String]:
	if solution_defs.has("mycelial_resin"):
		return ["mycelial_resin"]
	if not solution_order.is_empty():
		return [solution_order[0]]
	return []


func get_available_solution_recipe_ids() -> Array[String]:
	if not is_synth_unlocked():
		return []

	var out: Array[String] = []
	for recipe_id in _get_synth_pass1_recipe_ids():
		if is_solution_unlocked(recipe_id):
			out.append(recipe_id)
	return out


func _ensure_synth_slots_initialized() -> void:
	if synth_slot_costs.is_empty():
		synth_slot_costs = [0]
	if unlocked_synth_slots <= 0:
		unlocked_synth_slots = 1
	if synth_slots.size() != synth_slot_costs.size():
		synth_slots.clear()
		for i in range(synth_slot_costs.size()):
			synth_slots.append({
				"slot_number": i + 1,
				"recipe_id": "",
				"in_progress": false,
				"progress_sec": 0.0,
				"craft_time_sec": _get_synth_default_craft_time_sec(),
				"repeat_enabled": true,
				"status": "Idle",
				"completed_count": 0
			})


func _get_synth_default_craft_time_sec() -> float:
	return 8.0


func cycle_synth_recipe(slot_number: int) -> String:
	if not is_synth_unlocked():
		return ""

	_ensure_synth_slots_initialized()

	var idx := slot_number - 1
	if idx < 0 or idx >= synth_slots.size():
		return ""

	var ids := get_available_solution_recipe_ids()
	if ids.is_empty():
		synth_slots[idx]["recipe_id"] = ""
		synth_slots[idx]["progress_sec"] = 0.0
		synth_slots[idx]["status"] = "Idle"
		return ""

	var current_id := str((synth_slots[idx] as Dictionary).get("recipe_id", ""))
	var current_pos := ids.find(current_id)
	if current_pos < 0:
		synth_slots[idx]["recipe_id"] = ids[0]
	else:
		current_pos += 1
		if current_pos >= ids.size():
			current_pos = -1

		if current_pos == -1:
			synth_slots[idx]["recipe_id"] = ""
		else:
			synth_slots[idx]["recipe_id"] = ids[current_pos]

	synth_slots[idx]["progress_sec"] = 0.0
	synth_slots[idx]["status"] = "Idle"

	return str((synth_slots[idx] as Dictionary).get("recipe_id", ""))


func toggle_synth_repeat(slot_number: int) -> bool:
	_ensure_synth_slots_initialized()
	var idx := slot_number - 1
	if idx < 0 or idx >= synth_slots.size():
		return false
	var slot: Dictionary = (synth_slots[idx] as Dictionary).duplicate(true)
	slot["repeat_enabled"] = not bool(slot.get("repeat_enabled", true))
	synth_slots[idx] = slot
	return bool(slot["repeat_enabled"])


func clear_synth_recipe(slot_number: int) -> void:
	_ensure_synth_slots_initialized()
	var idx := slot_number - 1
	if idx < 0 or idx >= synth_slots.size():
		return
	var slot: Dictionary = synth_slots[idx] as Dictionary
	slot["recipe_id"] = ""
	slot["progress_sec"] = 0.0
	slot["status"] = "Idle"
	synth_slots[idx] = slot


func _can_pay_recipe_inputs(inputs: Array) -> bool:
	for input_variant in inputs:
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id == "" or qty <= 0:
			continue
		if get_amount(res_id) < qty:
			return false
	return true


func _pay_recipe_inputs(inputs: Array) -> void:
	for input_variant in inputs:
		var c: Dictionary = input_variant as Dictionary
		var res_id := str(c.get("id", ""))
		var qty := int(c.get("qty", 0))
		if res_id != "" and qty > 0:
			add_amount(res_id, -qty)


func _tick_synth(dt: float) -> void:
	if not is_synth_unlocked():
		return

	_ensure_synth_slots_initialized()

	for i in range(unlocked_synth_slots):
		var slot: Dictionary = synth_slots[i] as Dictionary
		var recipe_id := str(slot.get("recipe_id", ""))

		if recipe_id == "":
			slot["status"] = "Idle"
			slot["progress_sec"] = 0.0
			synth_slots[i] = slot
			continue

		if not solution_defs.has(recipe_id):
			slot["status"] = "Invalid recipe"
			slot["progress_sec"] = 0.0
			synth_slots[i] = slot
			continue

		var recipe_def: Dictionary = solution_defs[recipe_id] as Dictionary
		var inputs: Array = recipe_def.get("inputs", []) as Array
		var output_qty: int = int(recipe_def.get("output_qty", 1))
		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", _get_synth_default_craft_time_sec())))
		slot["craft_time_sec"] = craft_time

		if not _can_pay_recipe_inputs(inputs):
			slot["status"] = "Missing inputs"
			slot["progress_sec"] = 0.0
			synth_slots[i] = slot
			continue

		slot["status"] = "Crafting"
		slot["progress_sec"] = float(slot.get("progress_sec", 0.0)) + dt

		if float(slot["progress_sec"]) >= craft_time:
			_pay_recipe_inputs(inputs)
			if not resources.has(recipe_id):
				resources[recipe_id] = 0.0
			resources[recipe_id] = float(resources.get(recipe_id, 0.0)) + float(output_qty)
			slot["progress_sec"] = 0.0
			slot["completed_count"] = int(slot.get("completed_count", 0)) + output_qty

			if bool(slot.get("repeat_enabled", true)):
				slot["status"] = "Ready"
			else:
				slot["status"] = "Complete"
				slot["recipe_id"] = ""

		synth_slots[i] = slot


func get_synth_ui_entries() -> Array:
	var out: Array = []
	if not is_synth_unlocked():
		return out

	_ensure_synth_slots_initialized()

	var recipe_names: Dictionary = {}
	for rid in get_available_solution_recipe_ids():
		recipe_names[rid] = str((solution_defs.get(rid, {}) as Dictionary).get("name", rid))

	for i in range(unlocked_synth_slots):
		var slot: Dictionary = synth_slots[i] as Dictionary
		var recipe_id := str(slot.get("recipe_id", ""))
		var recipe_name := "Idle"
		var input_summary := "—"
		var output_summary := "—"

		if recipe_id != "":
			recipe_name = str(recipe_names.get(recipe_id, recipe_id))

			var recipe_def: Dictionary = solution_defs.get(recipe_id, {}) as Dictionary
			var inputs: Array = recipe_def.get("inputs", []) as Array
			var output_qty: int = int(recipe_def.get("output_qty", 1))

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

			if not input_parts.is_empty():
				input_summary = ", ".join(input_parts)

			output_summary = "%s %s" % [output_qty, recipe_name]

		var craft_time: float = maxf(0.1, float(slot.get("craft_time_sec", _get_synth_default_craft_time_sec())))
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

	return out

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
	paid_compound_unlocks.clear()
	paid_solution_unlocks.clear()
	synth_slot_costs.clear()
	synth_slots.clear()
	unlocked_synth_slots = 0

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
