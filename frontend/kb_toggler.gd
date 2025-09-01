extends Node2D
class_name KBMan

enum KBType {GAMING, FULL}

@export var type: KBType = KBType.FULL

# Static variable to track if full keyboard is enabled (default is false = gaming keyboard)
static var full_keyboard_enabled: bool = false

static func set_full_keyboard_enabled(enabled: bool):
    full_keyboard_enabled = enabled

static func get_current_keyboard_type():
    return KBType.FULL if full_keyboard_enabled else KBType.GAMING

func _process(delta: float) -> void:
    var current_type = get_current_keyboard_type()
    self.visible = (current_type == type)
