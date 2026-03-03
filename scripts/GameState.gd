extends Node

# v1 seed: numbers-only production into node pools (no mites/transport yet).
# Data-driven via res://data/*.json

# --- Tunables (safe defaults) ---
const TICK_DT := 0.1

# Simple v1 upgrade effects (tune later):
# yield_mult = 1 + yield_level * 0.10
# node_speed_mult = 1 + node_speed_level * 0.10
const YIELD_STEP := 0.10
const NODE_SPEED_STEP := 0.10

# --- Runtime state ---
var resources: Dictionary = {}     # res_id -> amount (float)
var nodes: Dictionary = {}         # node_id -> dict (name, base_rate_total, outputs, pool_cap, pool, upgrades)
var _accum := 0.0

func _ready() -> void:
	_load_all()
	set_process(true)

func _process(dt: float) -> void:
	_accum += dt
	while _accum >= TICK_DT:
		_accum -= TICK_DT
		tick(TICK_DT)

func tick(dt: float) -> void:
	# Continuous production into node pools.
	for node_id in nodes.keys():
		var n = nodes[node_id]

		var base_rate_total: float = float(n.get("base_rate_total", 0.0))

		var up = n.get("upgrades", {})
		var yield_level: int = int(up.get("yield_level", 0))
		var node_speed_level: int = int(up.get("node_speed_level", 0))

		var yield_mult := 1.0 + float(yield_level) * YIELD_STEP
		var node_speed_mult := 1.0 + float(node_speed_level) * NODE_SPEED_STEP
		var prod_mult := yield_mult * node_speed_mult

		var rate_total := base_rate_total * prod_mult

		var outputs = n.get("outputs", [])
		if outputs.is_empty():
			continue

		var sum_w := 0.0
		for o in outputs:
			sum_w += float(o.get("weight", 1.0))
		if sum_w <= 0.0:
			sum_w = 1.0

		# Pool bookkeeping
		var pool = n.get("pool", {})
		var cap: float = float(n.get("pool_cap", 0.0))

		for o in outputs:
			var res_id: String = str(o.get("res", ""))
			if res_id == "":
				continue

			var w: float = float(o.get("weight", 1.0))
			var amount_per_unit: float = float(o.get("amount_per_unit", 1.0))
			var rate_o := rate_total * (w / sum_w) * amount_per_unit
			var add := rate_o * dt

			var current := float(pool.get(res_id, 0.0))
			var next := current + add
			if cap > 0.0:
				next = min(next, cap)
			pool[res_id] = next

		n["pool"] = pool
		nodes[node_id] = n
		print("Damp Soil spores:", nodes["damp_soil"]["pool"].get("spores", 0.0))

# --- Query helpers for UI ---
func get_amount(res_id: String) -> int:
	return int(floor(float(resources.get(res_id, 0.0))))

func get_node_display_row(node_id: String) -> Dictionary:
	# Returns a single-row summary for the NodePanel (v1 can expand to multi-row).
	var out := {
		"resource": "",
		"yield_percent": "100%",
		"rate_text": "0.00/s",
		"harvested_text": "0/0"
	}

	if not nodes.has(node_id):
		return out

	var n = nodes[node_id]
	var up = n.get("upgrades", {})
	var yield_level: int = int(up.get("yield_level", 0))
	var node_speed_level: int = int(up.get("node_speed_level", 0))

	var yield_mult := 1.0 + float(yield_level) * YIELD_STEP
	var node_speed_mult := 1.0 + float(node_speed_level) * NODE_SPEED_STEP
	var prod_mult := yield_mult * node_speed_mult

	var base_rate_total: float = float(n.get("base_rate_total", 0.0))
	var rate_total := base_rate_total * prod_mult

	var outputs = n.get("outputs", [])
	if outputs.is_empty():
		return out

	var o0 = outputs[0]
	var res_id: String = str(o0.get("res", ""))
	out["resource"] = res_id

	# For now, "Rate" shows production into pool (transport comes later).
	out["yield_percent"] = str(int(round(yield_mult * 100.0))) + "%"
	out["rate_text"] = _fmt_rate(rate_total) + "/s"

	var pool = n.get("pool", {})
	var cap: int = int(n.get("pool_cap", 0))
	var cur: int = int(floor(float(pool.get(res_id, 0.0))))
	out["harvested_text"] = str(cur) + "/" + str(cap)

	return out

func _fmt_rate(r: float) -> String:
	# Keep it compact for UI
	if r >= 10.0:
		return str(snapped(r, 0.1))
	return str(snapped(r, 0.01))

# --- Loading ---
func _load_all() -> void:
	resources.clear()
	nodes.clear()

	var res_data = _load_json("res://data/resources.json")
	if res_data == null:
		_seed_defaults()
		return

	for r in res_data.get("resources", []):
		var id: String = str(r.get("id", ""))
		if id != "":
			resources[id] = 0.0

	# seed starting amounts for a nicer demo
	resources["nutrients"] = 12500.0
	resources["glowcaps"] = 0.0
	resources["strain_points"] = 0.0

	var nodes_data = _load_json("res://data/nodes.json")
	if nodes_data != null:
		for n in nodes_data.get("nodes", []):
			var nid: String = str(n.get("id", ""))
			if nid == "":
				continue

			var nd := {
				"id": nid,
				"name": str(n.get("name", nid)),
				"base_rate_total": float(n.get("base_rate_total", 0.0)),
				"pool_cap": int(n.get("pool_cap", 0)),
				"outputs": n.get("outputs", []),
				"upgrades": n.get("upgrades", {"yield_level": 0, "node_speed_level": 0}),
				"pool": {}
			}
			nodes[nid] = nd

func _seed_defaults() -> void:
	# Fallback if files missing
	resources = {
		"nutrients": 12500.0, "glowcaps": 0.0, "strain_points": 0.0,
		"spores": 0.0, "hyphae": 0.0, "cellulose": 0.0, "mycelium": 0.0
	}
	nodes = {
		"damp_soil": {
			"id": "damp_soil", "name": "Damp Soil",
			"base_rate_total": 0.25, "pool_cap": 50,
			"outputs": [{"res": "spores", "weight": 1.0, "amount_per_unit": 1.0}],
			"upgrades": {"yield_level": 0, "node_speed_level": 0},
			"pool": {}
		},
	}

func _load_json(path: String):
	if not FileAccess.file_exists(path):
		return null

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null

	var txt := f.get_as_text()
	f.close()

	var parser := JSON.new()
	var err := parser.parse(txt)
	if err != OK:
		push_warning("JSON parse failed: " + path)
		return null

	return parser.data
