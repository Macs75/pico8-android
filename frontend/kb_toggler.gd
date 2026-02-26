extends RepositionableControl
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
var managed_names = ["kb_pocketchip_left", "kb_pocketchip_right", "kb_pocketchip"]

var drag_overlay: Control

func _ready() -> void:
	super._ready() # Initialize RepositionableControl
	
	if name in managed_names:
		drag_overlay = Control.new()
		drag_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(drag_overlay)
	
	var runcmd = get_tree().root.get_node_or_null("Main/runcmd")
	if runcmd:
		if not runcmd.intent_session_started.is_connected(_on_intent_session_started):
			runcmd.intent_session_started.connect(_on_intent_session_started)
		# Check if already started (late join)
		if runcmd.is_intent_session:
			_on_intent_session_started()
			
	# Subscribe to keyboard state changes
	KBMan.subscribe(_on_kb_state_updated)
	# Initial visibility update
	_on_kb_state_updated(KBMan.full_keyboard_enabled)

func _on_kb_state_updated(_full_enabled: bool):
	visible = (get_current_keyboard_type() == type)

func _on_intent_session_started():
	# Update Gaming Keyboard ESC
	var esc_gaming = get_node_or_null("esc")
	if esc_gaming:
		esc_gaming.set_textures(tex_power_normal, tex_power_pressed)
		esc_gaming.cap_text = ""
		if "text" in esc_gaming: esc_gaming.text = "" # Double check
	
	_has_updated_power = true

func _on_layout_reset(target_is_landscape: bool):
	# Only reset if we are currently visible and match the orientation
	if not is_visible_in_tree():
		return
		
	if target_is_landscape == _is_in_landscape_ui():
		# Special Case: Pocketchips are centrally managed by their parents
		if name in managed_names:
			scale = original_scale # Must manually restore scale since we bypass super()
			var p = get_parent()
			if p and p.has_method("_on_resize") or p.name == "kbanchor":
				# Parent is responsible for repositioning these
				return
		
		super._on_layout_reset(target_is_landscape)

func _process(_delta: float) -> void:
	# Intercept clicks during layout customization using an overlay
	# We use an overlay because Godot input routing depends entirely on node tree order, not z-index.
	if PicoVideoStreamer.display_drag_enabled and is_repositionable:
		self.mouse_filter = Control.MOUSE_FILTER_STOP
		if drag_overlay:
			drag_overlay.mouse_filter = Control.MOUSE_FILTER_PASS # Catches input before keys, bubbles to parent
			drag_overlay.mouse_default_cursor_shape = Control.CURSOR_CROSS
	else:
		self.mouse_filter = Control.MOUSE_FILTER_PASS
		self.mouse_default_cursor_shape = Control.CURSOR_ARROW
		if drag_overlay:
			drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
