extends Node

const TICK_DT: float = 0.1

# Upgrade tuning (Phase 6 placeholder values; can move to config later)
const YIELD_STEP: float = 0.10
const NODE_SPEED_STEP: float = 0.10
const CARRY_STEP: int = 1

# Transport tuning
const BASE_MITE_SPEED: float = 150.0
const BASE_CARRY: int = 1
const LOAD_UNLOAD_SEC: float = 0.25
const DEFAULT_DISTANCE_PX: float = 360.0

const RAW_BASE_VALUES := {
	"spores": 1.0,
	"hyphae": 2.0,
	"cellulose": 4.0,
	"mycelium": 7.0
}
const BASE_DIGEST_MODIFIER: float = 1.0

var resource_defs: Dictionary = {}   # res_id -> metadata
var node_defs: Dictionary = {}       # node_id -> static definition
var node_order: Array[String] = []   # stable display order

var resources: Dictionary = {}       # res_id -> float (cloud inventory)
var nodes: Dictionary = {}           # node_id -> live node state
var total_nutrients_earned_run: float = 0.0
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
	var gained: float = float(take) * _get_resource_base_value(res_id) * BASE_DIGEST_MODIFIER
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
	return _get_resource_base_value(res_id) * BASE_DIGEST_MODIFIER


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


# ---------------- Loading ----------------

func _load_all() -> void:
	resource_defs.clear()
	node_defs.clear()
	node_order.clear()
	resources.clear()
	nodes.clear()
	node_world_positions.clear()
	spore_cloud_world_pos = Vector2.ZERO
	total_nutrients_earned_run = 0.0

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

	# seed starting amounts
	resources["nutrients"] = 12500.0
	resources["glowcaps"] = 0.0
	resources["strain_points"] = 0.0

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
