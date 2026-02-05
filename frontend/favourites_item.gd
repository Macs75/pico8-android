extends PanelContainer

var item_data
var list_index: int = -1
var _current_font_size: int = 0

# Signal to notify parent of drop
signal item_dropped(source_idx: int, target_idx: int)
# Signal to request live reorder
signal item_reorder_requested(source_item, target_item)
# Signal to request auto-scroll
signal scroll_request(direction: float)

func setup(data, idx: int):
	item_data = data
	list_index = idx
	
	%LabelName.text = data.name.capitalize()
	%LabelAuthor.text = data.author
	
	if not has_node("Content/DragHandle"):
		return
	
	# Make the drag handle darker/distinct
	$Content/DragHandle.modulate = Color(0.5, 0.5, 0.5)

var is_grabbed: bool = false
var _grabbed_by_controller: bool = false

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		if is_grabbed:
			is_grabbed = false
			_grabbed_by_controller = false
			_update_style(has_focus())


# Input Repeat Logic
var _repeat_timer: float = 0.0
var _repeat_interval: float = 0.1
var _repeat_delay: float = 0.4
var _last_input_dir: int = 0

func _process(delta):
	# If a native drag is in progress (e.g. Touch/Mouse), let Godot handle signals.
	# Don't let the controller poller reset the state.
	if get_viewport().gui_is_dragging():
		_long_press_checking = false
		return
		
	# Long Press Checker
	if _long_press_checking:
		# Check if the Item itself has moved (indicates Scrolling)
		if global_position.distance_to(_item_start_global_pos) > 10.0:
			_long_press_checking = false
			
		elif (Time.get_ticks_msec() - _long_press_start_time) > LONG_PRESS_DURATION_MS:
			_long_press_checking = false
			# Trigger Drag!
			var result = _create_drag_data()
			var data = result[0]
			var preview = result[1]
			
			if has_method("force_drag"):
				force_drag(data, preview)
			else:
				print("FavouritesItem: force_drag not available")
	
	# Controller Input Processing
	if has_focus():
		var holding_a = _is_action_held()
		
		# --- 1. Visual Grip State ---
		if holding_a:
			if not is_grabbed:
				is_grabbed = true
				_grabbed_by_controller = true
				_update_style(true)
		else:
			if is_grabbed and _grabbed_by_controller:
				is_grabbed = false
				_grabbed_by_controller = false
				_update_style(true)
				
		# --- 2. Repeat Move Logic ---
		# Only move if holding A (Reorder Mode)
		if holding_a:
			var input_dir = 0
			if Input.is_action_pressed("ui_up"):
				input_dir = -1
			elif Input.is_action_pressed("ui_down"):
				input_dir = 1
				
			if input_dir != 0:
				if input_dir != _last_input_dir:
					# New press: Immediate action + Reset Timer
					request_move_step.emit(input_dir)
					_repeat_timer = _repeat_delay
					_last_input_dir = input_dir
				else:
					# Holding same dir: Decrement timer
					_repeat_timer -= delta
					if _repeat_timer <= 0:
						request_move_step.emit(input_dir)
						_repeat_timer = _repeat_interval
			else:
				_last_input_dir = 0
				_repeat_timer = 0
				
	elif is_grabbed and _grabbed_by_controller:
		# Lost focus while holding?
		is_grabbed = false
		_grabbed_by_controller = false
		_update_style(false)

func _get_drag_data(at_position: Vector2):
	# only allow drag if touching the handle
	var handle = $Content/DragHandle
	var global_touch_pos = get_global_transform() * at_position
	if not handle.get_global_rect().has_point(global_touch_pos):
		return null
	
	var result = _create_drag_data()
	set_drag_preview(result[1])
	return result[0]

func _create_drag_data():
	# Mark as grabbed for styling
	is_grabbed = true
	_update_style(has_focus())
		
	# Create a visual preview
	var blue_highlight = Color(0.3, 0.6, 1.0)
	
	var preview_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	
	# Scale margins based on font size (approx 0.3x font size for horizontal, 0.15x vertical)
	# or fallback to 10 if font size is 0 (unlikely)
	var margin_h = 10
	var margin_v = 5
	if _current_font_size > 0:
		margin_h = int(_current_font_size * 0.4)
		margin_v = int(_current_font_size * 0.15)
		# Set minimum height to match list item
		preview_panel.custom_minimum_size.y = _current_font_size * 2.5
	
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = blue_highlight
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	preview_panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	var handle_label = Label.new()
	handle_label.text = "↕️"
	handle_label.add_theme_font_override("font", preload("res://assets/font/NotoEmoji-Regular.ttf"))
	handle_label.add_theme_color_override("font_color", blue_highlight)
	
	var preview = Label.new()
	preview.text = item_data.name
	preview.add_theme_color_override("font_color", blue_highlight)
	
	if _current_font_size > 0:
		preview.add_theme_font_size_override("font_size", _current_font_size)
		handle_label.add_theme_font_size_override("font_size", int(_current_font_size * 1.2))
		
	hbox.add_child(handle_label)
	hbox.add_child(preview)
	
	preview_panel.add_child(hbox)
	
	# Return [data, preview]
	return [ {"source_idx": list_index, "source_item": self}, preview_panel]

func _can_drop_data(at_position: Vector2, data) -> bool:
	# Check for auto-scroll
	var global_pos = get_global_transform() * at_position
	var viewport_height = get_viewport_rect().size.y
	var scroll_zone = viewport_height * 0.15 # Top/Bottom 15%
	
	if global_pos.y < scroll_zone:
		scroll_request.emit(-1.0) # Scroll Up
	elif global_pos.y > (viewport_height - scroll_zone):
		scroll_request.emit(1.0) # Scroll Down
		
	# Only accept drops from other items in the same list
	if data is Dictionary and data.has("source_item") and data.source_item != self:
		# Live reorder request
		item_reorder_requested.emit(data.source_item, self)
		return true
	return false

func _drop_data(_at_position: Vector2, data):
	var source_idx = data.source_idx
	# Emit signal to parent to handle the actual array reordering
	item_dropped.emit(source_idx, list_index)

func set_font_size(font_size: int):
	_current_font_size = font_size
	%LabelName.add_theme_font_size_override("font_size", font_size)
	%LabelAuthor.add_theme_font_size_override("font_size", int(font_size * 0.8)) # Slightly smaller for author
	$Content/DragHandle.add_theme_font_size_override("font_size", int(font_size * 1.2)) # Larger handle
	
	# Increase minimum height for better touch targets
	custom_minimum_size.y = font_size * 2.5

# --- Focus & Input Logic ---
signal request_move_step(direction: int)

func _ready():
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	
	# Default style
	_update_style(false)
	
	# Calculate Move Threshold based on DPI (approx 0.2 inches)
	var dpi = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96.0 # Fallback
	_long_press_move_threshold = dpi * 0.2

func _on_focus_entered():
	_update_style(true)
	
func _on_focus_exited():
	is_grabbed = false
	_update_style(false)

func _update_style(focused: bool):
	var style = get_theme_stylebox("panel", "PanelContainer")
	if not style:
		style = StyleBoxFlat.new()
		# Provide a default background if none exists
		style.bg_color = Color(0.1, 0.1, 0.1, 0.0)
	
	# Duplicate to not affect other items
	style = style.duplicate()
	
	# Determine Colors based on state
	var border_color = Color(0, 0, 0, 0) # Transparent by default
	var text_color = Color(0.6, 0.6, 0.6, 1) # Default Author Gray
	var name_color = Color(1, 1, 1, 1) # Default Name White
	var handle_color = Color(0.5, 0.5, 0.5, 1) # Default Handle
	
	var is_active = false
	
	if is_grabbed:
		# BLUE for Grabbed
		border_color = Color(0.3, 0.6, 1.0) # Blue
		text_color = border_color
		name_color = border_color
		handle_color = border_color
		is_active = true
	elif focused:
		# Green for Focused
		border_color = Color(0.6, 1.0, 0.6) # Pale Green
		text_color = border_color
		name_color = border_color
		handle_color = border_color
		is_active = true
		
	if is_active:
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = border_color
		
		%LabelName.add_theme_color_override("font_color", name_color)
		%LabelAuthor.add_theme_color_override("font_color", text_color)
		if has_node("Content/DragHandle"):
			$Content/DragHandle.add_theme_color_override("font_color", handle_color)
			# Change Icon based on state
			if is_grabbed:
				$Content/DragHandle.add_theme_font_override("font", preload("res://assets/font/NotoEmoji-Regular.ttf"))
				$Content/DragHandle.text = "↕️"
			else:
				$Content/DragHandle.remove_theme_font_override("font")
				$Content/DragHandle.text = " ☰ "
	else:
		# Reset
		style.border_width_bottom = 0
		style.border_width_top = 0
		style.border_width_left = 0
		style.border_width_right = 0
		
		%LabelName.remove_theme_color_override("font_color")
		%LabelAuthor.add_theme_color_override("font_color", text_color)
		if has_node("Content/DragHandle"):
			$Content/DragHandle.remove_theme_color_override("font_color")
			$Content/DragHandle.text = " ☰ "
			
	add_theme_stylebox_override("panel", style)


var _long_press_start_time: int = 0
var _long_press_checking: bool = false
var _long_press_start_pos: Vector2 = Vector2.ZERO
var _item_start_global_pos: Vector2 = Vector2.ZERO
const LONG_PRESS_DURATION_MS = 700
var _long_press_move_threshold: float = 20.0 # Default fallback

func _gui_input(event: InputEvent):
	# Long Press Logic (Touch)
	if event is InputEventScreenTouch:
		if event.pressed:
			_long_press_checking = true
			_long_press_start_time = Time.get_ticks_msec()
			_long_press_start_pos = event.position
			_item_start_global_pos = global_position # Track item position to detect scrolling
		else:
			_long_press_checking = false
			
	elif event is InputEventScreenDrag:
		if _long_press_checking:
			# Cancel if finger moved too much (local relative)
			if event.position.distance_to(_long_press_start_pos) > _long_press_move_threshold:
				_long_press_checking = false

	# Controller Focus
	if has_focus():
		# Reorder Logic: Hold A + Up/Down
		if _is_action_held():
			if event.is_action_pressed("ui_up"):
				accept_event()
			elif event.is_action_pressed("ui_down"):
				accept_event()

func _is_action_held() -> bool:
	# Check generic UI actions
	if Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_select"):
		return true
		
	# Explicitly check Controller Face Button Bottom (A / Cross)
	# Check all connected joypads? usually 0 is fine, or check generic
	if Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A):
		return true
		
	return false
