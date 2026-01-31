extends Control

var original_position: Vector2
var drag_offset_start: Vector2
var is_repositionable: bool = true

func _ready() -> void:
	original_position = position
	
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)
	
	# Attempt to load saved position
	var is_landscape = _is_in_landscape_ui()
	var saved_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
	if saved_pos != null:
		position = saved_pos

func _gui_input(event: InputEvent) -> void:
	if PicoVideoStreamer.display_drag_enabled and is_repositionable:
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if event.pressed:
				drag_offset_start = event.position
				accept_event()
			else:
				# Save position when drag ends
				_save_position()
				accept_event()
		elif event is InputEventScreenDrag or event is InputEventMouseMotion:
			if event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
				position += event.position - drag_offset_start
				
				# Clamp to parent
				var p = get_parent()
				if p is Control:
					var min_pos = Vector2.ZERO
					var max_pos = p.size - size
					position = position.clamp(min_pos, max_pos)
				
				accept_event()
		else:
			# Block all other GUI input (like focus, etc.)
			accept_event()
		return # Block normal input (clicks) when in drag mode
	
func _is_in_landscape_ui() -> bool:
	# heuristic: check if we are inside LandscapeUI node path
	var p = get_parent()
	while p:
		if p.name == "LandscapeUI":
			return true
		p = p.get_parent()
	return false

func _save_position():
	PicoVideoStreamer.set_control_pos(name, position, _is_in_landscape_ui())

func _on_layout_reset(target_is_landscape: bool):
	if target_is_landscape == _is_in_landscape_ui():
		position = original_position
