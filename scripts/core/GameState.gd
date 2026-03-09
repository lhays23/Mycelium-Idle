extends Node

const TICK_DT: float = 0.1

# Upgrade tuning
const YIELD_STEP: float = 0.10       # +10% production per level above baseline
const NODE_SPEED_STEP: float = 0.10  # +10% mite speed per level above baseline
const CARRY_STEP: int = 1            # +1 carry per level above baseline

# Transport tuning
const BASE_MITE_SPEED: float = 150.0
const BASE_CARRY: int = 1
const LOAD_UNLOAD_SEC: float = 0.25
const DEFAULT_DISTANCE_PX: float = 360.0

const DIGEST_T1_TO_NUTRIENTS: float = 1.0

var resources: Dictionary = {}  # res_id -> float (base/cloud inventory)
var nodes: Dictionary = {}      # node_id -> dict
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
	_tick_node_production(dt)
	_tick_transport(dt)


# ---------------- Production ----------------

func _tick_node_production(dt: float) -> void:
	# Continuous production into node pools (no cap).
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)

		var n: Dictionary = nodes[node_id] as Dictionary
		var base_rate_total: float = float(n.get("base_rate_total", 0.0))

		var up: Dictionary = _ensure_upgrade_keys(n)
		var yield_level: int = int(up.get("yield_level", 1))

		# Lv 1 = baseline (no bonus). Bonus starts at Lv 2.
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


func _can_pickup_any(node_id: String) -> bool:
	if not nodes.has(node_id):
		return false

	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)
	var outputs: Array = (n.get("outputs", []) as Array)

	var carry_left: int = _get_node_carry_capacity(node_id)
	if carry_left <= 0:
		return false

	for o_variant in outputs:
		var od: Dictionary = o_variant as Dictionary
		var res_id: String = str(od.get("res", ""))
		if res_id == "":
			continue

		var available: int = int(floor(float(pool.get(res_id, 0.0))))
		if available > 0:
			return true

	return false


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

	# v1 simple rule: primary resource first, then secondary if carry remains.
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

		var cur_pool: float = float(pool.get(res_id, 0.0))
		pool[res_id] = max(0.0, cur_pool - float(take))
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
	var prod_primary: float = _get_node_primary_production_rate(node_id)
	var trip_sec: float = max(0.25, _get_node_trip_sec(node_id))
	var carry: int = _get_node_carry_capacity(node_id)
	var transport_capacity: float = float(carry) / trip_sec

	return min(prod_primary, transport_capacity)


func get_node_mite_visual(node_id: String) -> Dictionary:
	var out: Dictionary = {
		"route_t": 0.0,
		"carrying": false,
		"visible": true
	}

	if not nodes.has(node_id):
		out["visible"] = false
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
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


# ---------------- Digest ----------------

func _get_node_primary_res_id(node_id: String) -> String:
	if not nodes.has(node_id):
		return ""
	var n: Dictionary = nodes[node_id] as Dictionary
	var outputs: Array = (n.get("outputs", []) as Array)
	if outputs.is_empty():
		return ""
	var o0: Dictionary = outputs[0] as Dictionary
	return str(o0.get("res", ""))


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
	if amount <= 0:
		return 0
	if not nodes.has(node_id):
		return 0

	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0

	var available: int = int(floor(float(resources.get(res_id, 0.0))))
	if available <= 0:
		return 0

	var take: int = min(amount, available)

	resources[res_id] = max(0.0, float(resources.get(res_id, 0.0)) - float(take))

	if not resources.has("nutrients"):
		resources["nutrients"] = 0.0
	resources["nutrients"] = float(resources.get("nutrients", 0.0)) + float(take) * DIGEST_T1_TO_NUTRIENTS

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

	# Baseline is Lv 1. If the key exists but is 0 (older data), clamp it up to 1.
	var yl: int = int(up.get("yield_level", 1))
	var sl: int = int(up.get("node_speed_level", 1))
	var cl: int = int(up.get("carry_level", 1))

	up["yield_level"] = max(1, yl)
	up["node_speed_level"] = max(1, sl)
	up["carry_level"] = max(1, cl)

	return up


func _upgrade_cost(stat_key: String, level: int) -> int:
	# Placeholder curve: cost to buy NEXT level, based on current level.
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

	# Yield percent: Lv 1 = 100%, Lv 2 = 110%, etc.
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
	var out: Dictionary = {
		"base_rate": 0.0,       # production into pool (base)
		"effective_rate": 0.0,  # production into pool (after Yield)
		"delivered_rate": 0.0   # delivered/sec to cloud for primary resource
	}
	if not nodes.has(node_id):
		return out

	var n: Dictionary = nodes[node_id] as Dictionary
	var up: Dictionary = _ensure_upgrade_keys(n)
	var yield_level: int = int(up.get("yield_level", 1))

	var base_rate_total: float = float(n.get("base_rate_total", 0.0))
	var bonus_levels: int = max(0, yield_level - 1)
	var yield_mult: float = 1.0 + float(bonus_levels) * YIELD_STEP
	var effective: float = base_rate_total * yield_mult

	out["base_rate"] = base_rate_total
	out["effective_rate"] = effective
	out["delivered_rate"] = _get_node_primary_delivered_rate(node_id)
	return out


# ---------------- Currency helpers ----------------

func get_amount(res_id: String) -> int:
	return int(floor(float(resources.get(res_id, 0.0))))


# ---------------- Loading ----------------

func _load_all() -> void:
	resources.clear()
	nodes.clear()
	node_world_positions.clear()
	spore_cloud_world_pos = Vector2.ZERO

	var res_data = _load_json("res://data/resources.json")
	if res_data == null:
		_seed_defaults()
		return

	var res_dict: Dictionary = res_data as Dictionary
	var res_list: Array = (res_dict.get("resources", []) as Array)
	for r_variant in res_list:
		var r: Dictionary = r_variant as Dictionary
		var id: String = str(r.get("id", ""))
		if id != "":
			resources[id] = 0.0

	# seed starting amounts
	resources["nutrients"] = 12500.0
	resources["glowcaps"] = 0.0
	resources["strain_points"] = 0.0

	var nodes_data = _load_json("res://data/nodes.json")
	if nodes_data != null:
		var ndict: Dictionary = nodes_data as Dictionary
		var nlist: Array = (ndict.get("nodes", []) as Array)
		for n_variant in nlist:
			var nsrc: Dictionary = n_variant as Dictionary
			var nid: String = str(nsrc.get("id", ""))
			if nid == "":
				continue

			var upgrades_src = nsrc.get("upgrades", null)
			var upgrades: Dictionary
			if upgrades_src == null:
				upgrades = {"yield_level": 1, "node_speed_level": 1, "carry_level": 1}
			else:
				upgrades = upgrades_src as Dictionary
				if not upgrades.has("yield_level"):
					upgrades["yield_level"] = 1
				if not upgrades.has("node_speed_level"):
					upgrades["node_speed_level"] = 1
				if not upgrades.has("carry_level"):
					upgrades["carry_level"] = 1

			upgrades["yield_level"] = max(1, int(upgrades.get("yield_level", 1)))
			upgrades["node_speed_level"] = max(1, int(upgrades.get("node_speed_level", 1)))
			upgrades["carry_level"] = max(1, int(upgrades.get("carry_level", 1)))

			var nd: Dictionary = {
				"id": nid,
				"name": str(nsrc.get("name", nid)),
				"base_rate_total": float(nsrc.get("base_rate_total", 0.0)),
				"outputs": nsrc.get("outputs", []),
				"upgrades": upgrades,
				"pool": {},
				"transport": {}
			}
			nodes[nid] = nd


func _seed_defaults() -> void:
	resources = {
		"nutrients": 12500.0,
		"glowcaps": 0.0,
		"strain_points": 0.0,
		"spores": 0.0,
		"hyphae": 0.0,
		"cellulose": 0.0,
		"mycelium": 0.0
	}

	nodes = {
		"damp_soil": {
			"id": "damp_soil",
			"name": "Damp Soil",
			"base_rate_total": 0.25,
			"outputs": [{"res": "spores", "weight": 1.0, "amount_per_unit": 1.0}],
			"upgrades": {"yield_level": 1, "node_speed_level": 1, "carry_level": 1},
			"pool": {},
			"transport": {}
		}
	}


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
		push_warning("JSON parse failed: " + path)
		return null

	return parser.data
