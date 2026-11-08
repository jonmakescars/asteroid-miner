class_name GameState
extends RefCounted
## State that has to survive switching between screens (scenes). Static variables live as long as
## the game runs, so no autoload is needed. Screens call GameState values before changing scene
## and restore from them when they open.

static var has_mission_state := false
static var time_jd := 0.0
static var paused := true
static var warp_index := 0
static var frame_index := 0
static var target_index := 0
static var message := ""
static var plan: Dictionary = {}
static var legs: Array = []
