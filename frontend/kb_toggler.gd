extends Node2D
class_name KBMan

enum KBType {GAMING, FULL}

@export var type: KBType = KBType.FULL

# Static variable to track if full keyboard is enabled (default is false = gaming keyboard)
static var full_keyboard_enabled: bool = false
static var _observers: Array[Callable] = []

static func subscribe(callback: Callable):
	if not _observers.has(callback):
		_observers.append(callback)

static func set_full_keyboard_enabled(enabled: bool):
	full_keyboard_enabled = enabled
	for callback in _observers:
		callback.call(enabled)

static func get_current_keyboard_type():
	return KBType.FULL if full_keyboard_enabled else KBType.GAMING

var tex_esc_normal = preload("res://assets/btn_esc_normal.png")
var tex_esc_pressed = preload("res://assets/btn_esc_pressed.png")
var tex_power_normal = preload("res://assets/btn_poweroff_normal.png")
var tex_power_pressed = preload("res://assets/btn_poweroff_pressed.png")
var _has_updated_power = false

func _ready() -> void:
	var runcmd = get_tree().root.get_node_or_null("Main/runcmd")
	if runcmd:
		if not runcmd.intent_session_started.is_connected(_on_intent_session_started):
			runcmd.intent_session_started.connect(_on_intent_session_started)
		# Check if already started (late join)
		if runcmd.is_intent_session:
			_on_intent_session_started()

func _on_intent_session_started():
	# Update Gaming Keyboard ESC
	var esc_gaming = get_node_or_null("esc")
	if esc_gaming:
		esc_gaming.set_textures(tex_power_normal, tex_power_pressed)
		esc_gaming.cap_text = ""
		if "text" in esc_gaming: esc_gaming.text = "" # Double check
	
	_has_updated_power = true

func _process(delta: float) -> void:
	var current_type = get_current_keyboard_type()
	self.visible = (current_type == type)
