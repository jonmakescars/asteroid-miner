class_name SpriteLibrary
extends RefCounted
## Finds and loads the sprite pack: the textures, their normal maps and the lighting shader.
## The pack may sit in res://sprites/ (as its README says) or in res://asteroid-miner-sprites/sprites/.
## If sprites.json cannot be read (on Android *.json must be in the export filter), pivots default to the
## image centre, which is right for all the round bodies.

const ROOTS: Array = ["res://sprites/", "res://asteroid-miner-sprites/sprites/"]
const SHADERS: Array = ["res://shaders/sprite_lit.gdshader", "res://asteroid-miner-sprites/shaders/sprite_lit.gdshader"]
const NIGHT_SHADERS: Array = ["res://shaders/city_lights.gdshader", "res://asteroid-miner-sprites/shaders/city_lights.gdshader"]
const ATMOSPHERE_PATH := "res://data/atmospheres.json"   # tints and strengths of the atmospheric halo per body
const ATMO_FOLDERS: Array = ["bodies", "scenery", "effects"]   # where atmo_day.png / atmo_twilight.png may be in the pack
const SKY_FOLDERS: Array = ["scenery", "effects", "bodies", "backgrounds", "sky"]   # where sky_milkyway.png / sky_stars.png may be
const DISC_RADIUS_PX := 192.0   # every round body in the pack has a disc of this radius

static var _ready_once := false
static var _root := ""
static var _manifest: Dictionary = {}
static var _entries: Dictionary = {}   # key -> {texture, normal, glow, pivot}
static var _shader: Shader = null
static var _night_shader: Shader = null
static var _atmospheres: Dictionary = {}
static var _sky: Dictionary = {}   # layer name -> Texture2D (or null = not found)
static var _atmo_keys: Dictionary = {}   # layer name -> manifest key ("" = not found)


static func _setup() -> void:
	if _ready_once:
		return
	_ready_once = true
	for root: String in ROOTS:
		if ResourceLoader.exists(root + "bodies/earth.png"):
			_root = root
			break
	if _root == "":
		push_warning("Sprite pack not found (looked in %s)." % str(ROOTS))
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_root + "sprites.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		_manifest = parsed
	else:
		push_warning("sprites.json not readable; using image centres as pivots (add *.json to the export filter).")
	for path: String in SHADERS:
		if ResourceLoader.exists(path):
			_shader = load(path) as Shader
			break
	var atmo: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATMOSPHERE_PATH))
	if typeof(atmo) == TYPE_DICTIONARY:
		_atmospheres = atmo
	else:
		push_warning("%s not readable: no atmospheric halos (add *.json to the export filter)." % ATMOSPHERE_PATH)
	for path: String in NIGHT_SHADERS:
		if ResourceLoader.exists(path):
			_night_shader = load(path) as Shader
			break


## The sprite for a manifest key such as "bodies/earth": {texture, normal, glow, pivot, px_per_unit}, or {} if there is none.
static func entry(key: String) -> Dictionary:
	_setup()
	if _entries.has(key):
		return _entries[key]
	var result := {}
	if _root != "":
		var folder := key.get_base_dir()
		var name := key.get_file()
		var path := "%s%s/%s.png" % [_root, folder, name]
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			var pivot := texture.get_size() * 0.5
			var px_per_unit := 2.0
			if _manifest.has(key):
				var info: Dictionary = _manifest[key]
				var p: Array = info["pivot"]
				pivot = Vector2(float(p[0]), float(p[1]))
				px_per_unit = float(info.get("px_per_unit", 2.0))
			var normal: Texture2D = null
			var normal_path := "%s%s/%s_n.png" % [_root, folder, name]
			if ResourceLoader.exists(normal_path):
				normal = load(normal_path) as Texture2D
			var glow: Texture2D = null
			var glow_path := "%s%s/%s_glow.png" % [_root, folder, name]
			if ResourceLoader.exists(glow_path):
				glow = load(glow_path) as Texture2D
			result = {"texture": texture, "normal": normal, "glow": glow, "pivot": pivot, "px_per_unit": px_per_unit}
	_entries[key] = result
	return result


## The manifest key of a body: planets, the Sun and dwarf planets are in bodies/, the other moons in bodies/moons/.
static func body_key(id: String) -> String:
	_setup()
	if _root == "":
		return ""
	for key in ["bodies/" + id, "bodies/moons/" + id]:
		if ResourceLoader.exists("%s%s.png" % [_root, key]):
			return key
	return ""


## A new material that lights a sprite with the normal map (null when the shader is missing).
static func lit_material(normal: Texture2D) -> ShaderMaterial:
	_setup()
	if _shader == null or normal == null or not UserSettings.flag("lighting_shader"):   # (switched off in the settings: flat sprites)
		return null
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("normal_map", normal)
	material.set_shader_parameter("sun_elevation", 0.0)
	return material


## A new material for the night-side lights of a body (its *_glow.png layer): shows the layer only where the body's
## own normal map says the Sun does not light it (null when the shader is missing).
static func night_material(normal: Texture2D) -> ShaderMaterial:
	_setup()
	if _night_shader == null or normal == null or not UserSettings.flag("lighting_shader"):
		return null
	var material := ShaderMaterial.new()
	material.shader = _night_shader
	material.set_shader_parameter("normal_map", normal)
	return material


## The manifest key of a generic halo layer ("atmo_day" or "atmo_twilight"), or "" when the pack does not have it.
static func atmo_key(layer: String) -> String:
	_setup()
	if _atmo_keys.has(layer):
		return _atmo_keys[layer]
	var found := ""
	if _root != "":
		for folder: String in ATMO_FOLDERS:
			if ResourceLoader.exists("%s%s/%s.png" % [_root, folder, layer]):
				found = "%s/%s" % [folder, layer]
				break
	_atmo_keys[layer] = found
	return found


## The texture of a sky layer ("sky_milkyway" or "sky_stars"), or null when the pack does not have it.
static func sky_texture(layer: String) -> Texture2D:
	_setup()
	if _sky.has(layer):
		return _sky[layer]
	var texture: Texture2D = null
	if _root != "":
		for folder: String in SKY_FOLDERS:
			var path := "%s%s/%s.png" % [_root, folder, layer]
			if ResourceLoader.exists(path):
				texture = load(path) as Texture2D
				break
	_sky[layer] = texture
	return texture


## The halo of a body: {day: Color, twilight: Color, day_strength, twilight_strength}, or {} when it has no atmosphere.
static func atmosphere(id: String) -> Dictionary:
	_setup()
	if not _atmospheres.has(id):
		return {}
	var info: Dictionary = _atmospheres[id]
	var day: Array = info["day"]
	var twilight: Array = info["twilight"]
	return {
		"day": Color(float(day[0]), float(day[1]), float(day[2])),
		"twilight": Color(float(twilight[0]), float(twilight[1]), float(twilight[2])),
		"day_strength": float(info.get("day_strength", 1.0)),
		"twilight_strength": float(info.get("twilight_strength", 1.0)),
	}
