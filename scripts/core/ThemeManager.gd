extends Node

signal theme_changed(theme_id: String)

const SAVE_KEY := "active_theme"
const DEFAULT_THEME := "forest_green"

# ── Token keys ────────────────────────────────────────────────────────────────
# These are the only names any UI code should reference.
# Add new tokens here first, then add values to every theme dict below.
const TOKENS := [
	"bg_deep",       # outermost panel / map overlay background
	"bg_panel",      # header bars, action bars, sub-panels
	"bg_row",        # selected / hovered row fill (rgba string)
	"border",        # panel borders, nav border
	"bark_stripe",   # 4px decorative stripe accent
	"accent",        # active icons, live values, highlights
	"accent_dim",    # inactive / idle icon color
	"accent_glow",   # active button fill (rgba string)
	"accent_border", # selected / active border (rgba string)
	"text_primary",  # main readable text
	"text_secondary",# resource names, labels
	"text_muted",    # tab labels, cost hints
	"nav_bg",        # nav bar background
	"tab_active_bg", # active tab fill (rgba string)
	"btn_bg",        # action button fill (rgba string)
	"btn_border",    # action button border
	"aura_fill",     # aura radial gradient fill color
	"aura_ring",     # aura outer ring color
	"aura_pulse",    # aura pulse wave color
]

# ── Theme definitions ─────────────────────────────────────────────────────────
const THEMES := {
	"forest_green": {
		"id":           "forest_green",
		"name":         "Forest Green",
		"unlocked":     true,
		"bg_deep":       Color(0.055, 0.102, 0.055),
		"bg_panel":      Color(0.071, 0.133, 0.059),
		"bg_row":        Color(0.392, 0.706, 0.196, 0.08),
		"border":        Color(0.227, 0.322, 0.157),
		"bark_stripe":   Color(0.239, 0.141, 0.063),
		"accent":        Color(0.561, 0.812, 0.376),
		"accent_dim":    Color(0.290, 0.478, 0.188),
		"accent_glow":   Color(0.392, 0.706, 0.196, 0.18),
		"accent_border": Color(0.392, 0.706, 0.196, 0.35),
		"text_primary":  Color(0.784, 0.910, 0.659),
		"text_secondary":Color(0.478, 0.667, 0.314),
		"text_muted":    Color(0.290, 0.478, 0.188),
		"nav_bg":        Color(0.039, 0.078, 0.031),
		"tab_active_bg": Color(0.392, 0.706, 0.196, 0.15),
		"btn_bg":        Color(0.392, 0.706, 0.196, 0.12),
		"btn_border":   Color(0.290, 0.604, 0.188),
		"aura_fill":  Color(0.302, 1.000, 0.816, 1.0),
		"aura_ring":  Color(0.302, 1.000, 0.816, 1.0),
		"aura_pulse":  Color(0.502, 1.000, 0.878, 1.0),
	},
	"mycelium_violet": {
		"id":           "mycelium_violet",
		"name":         "Mycelium Violet",
		"unlocked":     false,
		"bg_deep":       Color(0.055, 0.039, 0.102),
		"bg_panel":      Color(0.071, 0.055, 0.125),
		"bg_row":        Color(0.627, 0.392, 0.941, 0.08),
		"border":        Color(0.239, 0.157, 0.376),
		"bark_stripe":   Color(0.102, 0.055, 0.188),
		"accent":        Color(0.690, 0.565, 0.941),
		"accent_dim":    Color(0.353, 0.227, 0.541),
		"accent_glow":   Color(0.627, 0.392, 0.941, 0.20),
		"accent_border": Color(0.627, 0.392, 0.941, 0.40),
		"text_primary":  Color(0.816, 0.753, 0.973),
		"text_secondary":Color(0.565, 0.439, 0.784),
		"text_muted":    Color(0.353, 0.227, 0.541),
		"nav_bg":        Color(0.031, 0.024, 0.071),
		"tab_active_bg": Color(0.627, 0.392, 0.941, 0.15),
		"btn_bg":        Color(0.627, 0.392, 0.941, 0.12),
		"btn_border":   Color(0.439, 0.314, 0.753),
		"aura_fill":  Color(0.749, 0.502, 1.000, 1.0),
		"aura_ring":  Color(0.749, 0.502, 1.000, 1.0),
		"aura_pulse":  Color(0.878, 0.690, 1.000, 1.0),
	},
	"amber_spore": {
		"id":           "amber_spore",
		"name":         "Amber Spore",
		"unlocked":     false,
		"bg_deep":       Color(0.102, 0.082, 0.031),
		"bg_panel":      Color(0.125, 0.102, 0.031),
		"bg_row":        Color(0.784, 0.588, 0.157, 0.08),
		"border":        Color(0.290, 0.227, 0.094),
		"bark_stripe":   Color(0.239, 0.157, 0.063),
		"accent":        Color(0.878, 0.690, 0.314),
		"accent_dim":    Color(0.541, 0.376, 0.125),
		"accent_glow":   Color(0.784, 0.588, 0.157, 0.18),
		"accent_border": Color(0.784, 0.588, 0.157, 0.35),
		"text_primary":  Color(0.941, 0.847, 0.596),
		"text_secondary":Color(0.690, 0.533, 0.251),
		"text_muted":    Color(0.478, 0.345, 0.157),
		"nav_bg":        Color(0.071, 0.055, 0.016),
		"tab_active_bg": Color(0.784, 0.588, 0.157, 0.15),
		"btn_bg":        Color(0.784, 0.588, 0.157, 0.12),
		"btn_border":   Color(0.627, 0.471, 0.157),
		"aura_fill":  Color(1.000, 0.702, 0.278, 1.0),
		"aura_ring":  Color(1.000, 0.702, 0.278, 1.0),
		"aura_pulse":  Color(1.000, 0.816, 0.502, 1.0),
	},
	"accessible_blue": {
		"id":           "accessible_blue",
		"name":         "Accessible Blue",
		"unlocked":     true,
		"bg_deep":       Color(0.039, 0.055, 0.102),
		"bg_panel":      Color(0.055, 0.078, 0.125),
		"bg_row":        Color(0.235, 0.549, 0.941, 0.08),
		"border":        Color(0.118, 0.188, 0.376),
		"bark_stripe":   Color(0.039, 0.078, 0.157),
		"accent":        Color(0.376, 0.690, 0.973),
		"accent_dim":    Color(0.157, 0.376, 0.663),
		"accent_glow":   Color(0.235, 0.549, 0.941, 0.18),
		"accent_border": Color(0.235, 0.549, 0.941, 0.40),
		"text_primary":  Color(0.659, 0.816, 0.973),
		"text_secondary":Color(0.345, 0.533, 0.753),
		"text_muted":    Color(0.157, 0.376, 0.663),
		"nav_bg":        Color(0.024, 0.039, 0.078),
		"tab_active_bg": Color(0.235, 0.549, 0.941, 0.15),
		"btn_bg":        Color(0.235, 0.549, 0.941, 0.12),
		"btn_border":   Color(0.220, 0.439, 0.753),
		"aura_fill":  Color(0.278, 0.690, 1.000, 1.0),
		"aura_ring":  Color(0.278, 0.690, 1.000, 1.0),
		"aura_pulse":  Color(0.502, 0.816, 1.000, 1.0),
	},
}

# ── Runtime state ─────────────────────────────────────────────────────────────
var _active_id: String = DEFAULT_THEME
var _cache: Dictionary = {}  # flat token -> Color for fast lookup


func _ready() -> void:
	_rebuild_cache(DEFAULT_THEME)


# ── Public API ────────────────────────────────────────────────────────────────

## Returns the Color for a token in the active theme.
## Falls back to magenta so missing tokens are obvious during dev.
func get_color(token: String) -> Color:
	if _cache.has(token):
		return _cache[token] as Color
	push_warning("ThemeManager: unknown token '%s'" % token)
	return Color.MAGENTA


## Convenience — same as get_color but shorter to type.
func c(token: String) -> Color:
	return get_color(token)


## Switch to a theme by id. Emits theme_changed if the theme is available.
func set_theme(theme_id: String) -> bool:
	if not THEMES.has(theme_id):
		push_warning("ThemeManager: unknown theme '%s'" % theme_id)
		return false
	var t: Dictionary = THEMES[theme_id] as Dictionary
	if not bool(t.get("unlocked", false)):
		push_warning("ThemeManager: theme '%s' is not unlocked" % theme_id)
		return false
	_active_id = theme_id
	_rebuild_cache(theme_id)
	theme_changed.emit(theme_id)
	return true


## Unlock a theme (called when the player earns it).
func unlock_theme(theme_id: String) -> void:
	if THEMES.has(theme_id):
		(THEMES[theme_id] as Dictionary)["unlocked"] = true


## Returns the active theme id.
func active_id() -> String:
	return _active_id


## Returns an Array of Dictionaries describing all themes (for settings UI).
## Each dict has: id, name, unlocked.
func get_theme_list() -> Array:
	var out: Array = []
	for tid in THEMES:
		var t: Dictionary = THEMES[tid] as Dictionary
		out.append({
			"id":       str(t.get("id", tid)),
			"name":     str(t.get("name", tid)),
			"unlocked": bool(t.get("unlocked", false)),
		})
	return out


## Serialize for save file.
func to_save_dict() -> Dictionary:
	# Persist unlocked state + active id
	var unlocked: Array = []
	for tid in THEMES:
		if bool((THEMES[tid] as Dictionary).get("unlocked", false)):
			unlocked.append(tid)
	return {"active_id": _active_id, "unlocked": unlocked}


## Restore from save file.
func from_save_dict(d: Dictionary) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var unlocked = d.get("unlocked", [])
	if typeof(unlocked) == TYPE_ARRAY:
		for tid_variant in unlocked:
			var tid := str(tid_variant)
			if THEMES.has(tid):
				(THEMES[tid] as Dictionary)["unlocked"] = true
	var saved_id := str(d.get("active_id", DEFAULT_THEME))
	if THEMES.has(saved_id) and bool((THEMES[saved_id] as Dictionary).get("unlocked", false)):
		_active_id = saved_id
	_rebuild_cache(_active_id)


# ── Internal ──────────────────────────────────────────────────────────────────
func _rebuild_cache(theme_id: String) -> void:
	_cache.clear()
	if not THEMES.has(theme_id):
		return
	var t: Dictionary = THEMES[theme_id] as Dictionary
	for token in TOKENS:
		if t.has(token):
			_cache[token] = t[token]