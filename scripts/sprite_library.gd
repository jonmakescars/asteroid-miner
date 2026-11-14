class_name SpriteLibrary
extends RefCounted
## Finds and loads the sprite pack: the textures, their normal maps and the lighting shader.
## The pack may sit in res://sprites/ (as its README says) or in res://asteroid-miner-sprites/sprites/.
## If sprites.json cannot be read (on Android *.json must be in the export filter), pivots default to the
## image centre, which is right for all the round bodies.

const ROOTS: Array = ["res://sprites/", "res://asteroid-miner-sprites/sprites/"]
const SHADERS: Array = ["res://shaders/sprite_lit.gdshader", "res://asteroid-miner-sprites/shaders/sprite_lit.gdshader"]
const DISC_RADIUS_PX := 192.0   # every round body in the pack has a disc of this radius

static var _ready_once := false
static var _root := ""
static var _manifest: Dictionary = {}
static var _entries: Dictionary = {}   # key -> {texture, normal, glow, pivot}
static var _shader: Shader = null


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
	if _shader == null or normal == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("normal_map", normal)
	material.set_shader_parameter("sun_elevation", 0.0)
	return material
