extends Control
class_name RepositionableControl

var original_position: Vector2
var original_scale: Vector2
var drag_offset_start: Vector2
var is_repositionable: bool = true

var active_touches = {}
var initial_pinch_dist = 0.0
var initial_scale_modifier = 1.0

func _ready() -> void:
	original_position = position
	original_scale = scale
	
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)
		PicoVideoStreamer.instance.bezel_layout_updated.connect(_on_bezel_layout_updated)
	
	# Initial attempt to set position
	_update_position_from_layout()

func _update_position_from_layout():
	var is_landscape = _is_in_landscape_ui()
	
	# 1. User Override (Highest Priority)
	var saved_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
	if saved_pos != null:
		position = saved_pos
		var saved_scale = PicoVideoStreamer.get_control_scale(name, is_landscape)
		scale = original_scale * saved_scale
		return

	# 2. Theme Layout
	# Try to apply immediately if bezel is ready (catches startup race)
	if PicoVideoStreamer.instance:
		var rect = PicoVideoStreamer.instance.get_current_bezel_rect()
		if rect.has_area():
			_on_bezel_layout_updated(rect, Vector2.ONE)
			
	# 3. Default (Original) stays if nothing else applies

func _on_bezel_layout_updated(bezel_rect: Rect2, _unused_scale: Vector2):
	LayoutHelper.apply_layout(self, bezel_rect)
	

func _gui_input(event: InputEvent) -> void:
	if PicoVideoStreamer.display_drag_enabled and is_repositionable:
		var event_index = event.index if "index" in event else 0
		if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			if event.pressed:
				drag_offset_start = event.position
				active_touches[event_index] = event.position
				
				# Centralized Selection: Update the last touched element
				if PicoVideoStreamer.instance:
					PicoVideoStreamer.instance.selected_control = self
					PicoVideoStreamer.instance.control_selected.emit(self)
				
				accept_event()
			else:
				active_touches.erase(event_index)
				# Save position when interaction ends
				_save_layout()
				accept_event()
		elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			if active_touches.has(event_index):
				active_touches[event_index] = event.position
			
			if active_touches.size() == 1:
				# Single touch: Drag logic
				position += event.position - drag_offset_start
				
				# Clamp to parent
				var p = get_parent()
				if p is Control:
					var min_pos = Vector2.ZERO
					var max_pos = p.size - (size * scale)
					position = position.clamp(min_pos, max_pos)
				
				accept_event()
			elif active_touches.size() == 2:
				# Multi-touch: CONSUME but don't handle locally (let Arranger handle global pinch)
				accept_event()
		else:
			# Block all other GUI input (like focus, etc.)
			accept_event()
		return # Block normal input (clicks) when in drag mode
	
func _is_in_landscape_ui() -> bool:
	return LayoutHelper.is_in_landscape_ui(self)

func _save_layout():
	LayoutHelper.save_layout(self, original_scale.x)

func _on_layout_reset(target_is_landscape: bool):
	if is_visible_in_tree() and target_is_landscape == _is_in_landscape_ui():
		position = original_position
		scale = original_scale
