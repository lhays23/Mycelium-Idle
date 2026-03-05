extends Node

const TICK_DT: float = 0.1

# Upgrade tuning (placeholder)
const YIELD_STEP: float = 0.10          # +10% production per level above baseline
const NODE_SPEED_STEP: float = 0.10     # reserved for mites/transport later (not applied to production yet)
const CARRY_STEP: int = 1               # +1 capacity per level (transport later)

const DIGEST_T1_TO_NUTRIENTS: float = 1.0

var resources: Dictionary = {}  # res_id -> float
var nodes: Dictionary = {}      # node_id -> dict
var _accum: float = 0.0


func _ready() -> void:
	_load_all()
	set_process(true)


func _process(dt: float) -> void:
	_accum += dt
	while _accum >= TICK_DT:
		_accum -= TICK_DT
		tick(TICK_DT)


func tick(dt: float) -> void:
	# Continuous production into node pools (no cap).
	for node_id_variant in nodes.keys():
		var node_id: String = str(node_id_variant)

		var n: Dictionary = nodes[node_id] as Dictionary
		var base_rate_total: float = float(n.get("base_rate_total", 0.0))

		var up: Dictionary = _ensure_upgrade_keys(n)
		var yield_level: int = int(up.get("yield_level", 1))
		# Travel speed stored for future mite transport; do NOT apply to production now.

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


func digest_node_primary(node_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if not nodes.has(node_id):
		return 0

	var res_id: String = _get_node_primary_res_id(node_id)
	if res_id == "":
		return 0

	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)
	var available: int = int(floor(float(pool.get(res_id, 0.0))))
	if available <= 0:
		return 0

	var take: int = min(amount, available)

	var cur_f: float = float(pool.get(res_id, 0.0))
	pool[res_id] = max(0.0, cur_f - float(take))
	n["pool"] = pool
	nodes[node_id] = n

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

	var n: Dictionary = nodes[node_id] as Dictionary
	var pool: Dictionary = (n.get("pool", {}) as Dictionary)
	var available: int = int(floor(float(pool.get(res_id, 0.0))))
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
		"travel_value": "5.0s/trip", # placeholder display
		"travel_cost": 0,

		"carry_level": 1,
		"carry_value": "Cap 5",      # placeholder display
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

	# Travel display (placeholder until mites exist)
	out["travel_level"] = tl
	var trip_s: float = max(0.8, 5.0 - float(max(0, tl - 1)) * 0.4)
	out["travel_value"] = str(snapped(trip_s, 0.1)) + "s/trip"
	out["travel_cost"] = _upgrade_cost("node_speed_level", tl)

	# Carry display (placeholder until mites exist)
	out["carry_level"] = cl
	var cap: int = 5 + (cl - 1) * 1
	out["carry_value"] = "Cap " + str(cap)
	out["carry_cost"] = _upgrade_cost("carry_level", cl)

	return out


func get_node_rate_ui(node_id: String) -> Dictionary:
	# Base and effective (Yield only).
	var out: Dictionary = {
		"base_rate": 0.0,
		"effective_rate": 0.0
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
	return out


# ---------------- Currency helpers ----------------

func get_amount(res_id: String) -> int:
	return int(floor(float(resources.get(res_id, 0.0))))


# ---------------- Loading ----------------

func _load_all() -> void:
	resources.clear()
	nodes.clear()

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

			var nd: Dictionary = {
				"id": nid,
				"name": str(nsrc.get("name", nid)),
				"base_rate_total": float(nsrc.get("base_rate_total", 0.0)),
				"outputs": nsrc.get("outputs", []),
				"upgrades": upgrades,
				"pool": {}
			}
			upgrades["yield_level"] = max(1, int(upgrades.get("yield_level", 1)))
			upgrades["node_speed_level"] = max(1, int(upgrades.get("node_speed_level", 1)))
			upgrades["carry_level"] = max(1, int(upgrades.get("carry_level", 1)))
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
			"pool": {}
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
