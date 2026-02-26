extends CanvasLayer
class_name ListEditorBase

# Signals
signal request_close

# Core references
var _all_items: Array = []
var current_items: Array = []
var _items_per_page: int = 25
var _loaded_count: int = 0
var is_ascending: bool = true
var current_font_size: int = 0
var _last_focused_item: Control = null
var _is_dirty: bool = false
var _manual_order_cache: Array = []

var is_dragging_item: bool = false
var was_confirm_pressed: bool = false
var was_cancel_pressed: bool = false
var popup_was_visible: bool = false

var default_background_image = preload("res://icons/adaptive_top.png")

var _scroll_tween: Tween

# UI Accessors - Subclasses must provide these node paths or expected names in their scenes
@onready var panel = $Panel
@onready var margin_container = $Panel/MarginContainer
@onready var v_box = $Panel/MarginContainer/VBox
@onready var header = $Panel/MarginContainer/VBox/Header
@onready var label_title = $Panel/MarginContainer/VBox/Header/LabelTitle
@onready var sort_buttons = $Panel/MarginContainer/VBox/Header/SortButtons
@onready var label_sort = %LabelSort
@onready var option_sort = %OptionSort
@onready var btn_asc_desc = %BtnAscDesc
@onready var list_container = %ListContainer
@onready var btn_close = %BtnClose
@onready var background_art = %BackgroundArt

func _ready():
	_setup_sort_options()
	
	btn_close.pressed.connect(_on_close)
	btn_close.gui_input.connect(_on_explicit_gui_input.bind(btn_close))
	
	if option_sort:
		option_sort.item_selected.connect(_on_sort_criteria_changed)
		option_sort.gui_input.connect(_on_explicit_gui_input.bind(option_sort))
	
	if btn_asc_desc:
		btn_asc_desc.pressed.connect(_on_asc_desc_toggled)
		btn_asc_desc.gui_input.connect(_on_explicit_gui_input.bind(btn_asc_desc))
	
	# Initial layout
	_update_layout()
	_load_data()
	
	# Connect to resize after initial load
	get_tree().root.size_changed.connect(_update_layout)
	
	# Disable game input
	if PicoVideoStreamer.instance:
		print(self.name + ": Disabling PICO-8 Input (Instance found)")
		if PicoVideoStreamer.instance.has_method("set_input_blocked"):
			PicoVideoStreamer.instance.set_input_blocked(true)
		PicoVideoStreamer.instance.set_process_unhandled_input(false)
		PicoVideoStreamer.instance.set_process_input(false)
		
	set_process(true)

func _exit_tree():
	var tree = get_tree()
	if tree:
		var tmr = tree.create_timer(0.2)
		tmr.timeout.connect(func():
			# Ensure we are not re-enabling if another editor is already active
			if tree.root.has_node("FavouritesEditor") or tree.root.has_node("StatsEditor") or tree.root.has_node("SploreImporter"):
				return
				
			var streamer = PicoVideoStreamer.instance
			if is_instance_valid(streamer):
				print("ListEditorBase: Enabling PICO-8 Input (Timer expired)")
				if streamer.has_method("set_input_blocked"):
					streamer.set_input_blocked(false)
				
				streamer.set_process_unhandled_input(true)
				streamer.set_process_input(true)
		)

# ==========================================
# VIRTUAL METHODS (To be overridden)
# ==========================================

func _setup_sort_options():
	pass

func _load_items_from_source() -> Array:
	return []

func _apply_sort():
	pass

func _instantiate_item(_item_data, _index: int) -> Control:
	return null

func _get_background_image_path(_item_data) -> String:
	return ""

# ==========================================
# LAYOUT & RENDERING
# ==========================================

func _update_layout():
	var viewport_size = get_viewport().get_visible_rect().size
	var min_dim = min(viewport_size.x, viewport_size.y)
	
	var dynamic_font_size = int(max(12, min_dim * 0.03))
	current_font_size = dynamic_font_size
	
	# Ensure scroll follows focus -> DISABLE to allow manual smooth scroll
	list_container.get_parent().follow_focus = false
	
	# Apply dynamic margins
	var v_margin = int(viewport_size.y * 0.08)
	var h_margin = int(viewport_size.x * 0.06)
	
	margin_container.add_theme_constant_override("margin_top", v_margin)
	margin_container.add_theme_constant_override("margin_bottom", v_margin)
	margin_container.add_theme_constant_override("margin_left", h_margin)
	margin_container.add_theme_constant_override("margin_right", h_margin)
	
	# Dynamic Spacing for Font
	var spacing_val = int(dynamic_font_size * -0.25)
	var title_font = label_title.get_theme_font("font")
	if title_font is FontVariation:
		title_font.spacing_space = spacing_val
	
	# Apply to Header logic (sizes)
	label_title.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	if label_sort:
		label_sort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	if option_sort:
		option_sort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
		option_sort.get_popup().add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	if btn_asc_desc:
		btn_asc_desc.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Apply to Footer sizes
	btn_close.add_theme_font_size_override("font_size", dynamic_font_size)
	_apply_subclass_footer_sizes(dynamic_font_size)
	
	# Update existing items
	for item in list_container.get_children():
		if item.has_method("set_font_size"):
			item.set_font_size(dynamic_font_size)
		elif item is Button:
			item.add_theme_font_size_override("font_size", dynamic_font_size)
			item.custom_minimum_size.y = dynamic_font_size * 2.0
			
		if title_font is FontVariation:
			if item.has_node("%LabelName"):
				item.get_node("%LabelName").add_theme_font_override("font", title_font)
			if item.has_node("%LabelAuthor"):
				# Generic protection check
				if not (item.get("item_data") is Dictionary and item.get("item_data").get("is_stat_item", false)):
					item.get_node("%LabelAuthor").add_theme_font_override("font", title_font)

func _apply_subclass_footer_sizes(_size: int):
	pass

# ==========================================
# DATA LOADING & PAGINATION
# ==========================================

func _load_data():
	_all_items = _load_items_from_source()
	_manual_order_cache = _all_items.duplicate()
	
	_apply_sort()
	
	current_items = []
	_loaded_count = 0
	
	for child in list_container.get_children():
		child.queue_free()
		
	_load_next_page()
	
	if _all_items.size() > 0:
		call_deferred("_grab_initial_focus")

func _grab_initial_focus():
	if list_container.get_child_count() > 0:
		list_container.get_child(0).grab_focus()

func _refresh_list():
	for child in list_container.get_children():
		list_container.remove_child(child)
		child.queue_free()
	
	list_container.visible = false
	var items_to_setup = []
	
	for i in range(current_items.size()):
		var item_data = current_items[i]
		var item_node = _instantiate_item(item_data, i)
		if item_node:
			list_container.add_child(item_node)
			item_node.setup(item_data, i)
			items_to_setup.append(item_node)
			_connect_item_signals(item_node)
	
	if current_font_size > 0:
		for item_node in items_to_setup:
			if item_node.has_method("set_font_size"):
				item_node.set_font_size(current_font_size)
	
	list_container.visible = true
	_update_full_focus_chain()

func _connect_item_signals(item_node):
	if item_node.has_signal("request_move_step") and not item_node.request_move_step.is_connected(_on_item_request_move_step):
		item_node.request_move_step.connect(_on_item_request_move_step.bind(item_node))
	if not item_node.focus_entered.is_connected(_on_item_focused):
		item_node.focus_entered.connect(_on_item_focused.bind(item_node.get("item_data"), item_node))

func _load_next_page():
	var start_idx = _loaded_count
	var end_idx = mini(start_idx + _items_per_page, _all_items.size())
	
	if start_idx == 0:
		for i in range(start_idx, end_idx):
			current_items.append(_all_items[i])
		_loaded_count = end_idx
		_refresh_list()
	else:
		for child in list_container.get_children():
			if child is Button:
				list_container.remove_child(child)
				child.queue_free()
				break
		
		for i in range(start_idx, end_idx):
			var item_data = _all_items[i]
			current_items.append(item_data)
			
			var item_node = _instantiate_item(item_data, current_items.size() - 1)
			if item_node:
				list_container.add_child(item_node)
				item_node.setup(item_data, current_items.size() - 1)
				_connect_item_signals(item_node)
				
				if current_font_size > 0 and item_node.has_method("set_font_size"):
					item_node.set_font_size(current_font_size)
		
		_loaded_count = end_idx
		_update_full_focus_chain()
	
	if _loaded_count < 100 and _loaded_count < _all_items.size():
		await get_tree().create_timer(1.0).timeout
		_load_next_page()
	elif _loaded_count < _all_items.size():
		_add_load_more_button()

func _add_load_more_button():
	var load_more_btn = Button.new()
	load_more_btn.text = "⬇ Load More (%d remaining)" % (_all_items.size() - _loaded_count)
	
	if current_font_size > 0:
		load_more_btn.add_theme_font_size_override("font_size", current_font_size)
		load_more_btn.custom_minimum_size.y = current_font_size * 2.0
	else:
		load_more_btn.custom_minimum_size.y = 60
	
	load_more_btn.pressed.connect(_on_load_more_pressed)
	list_container.add_child(load_more_btn)

func _on_load_more_pressed():
	for child in list_container.get_children():
		if child is Button:
			child.queue_free()
			break
	_load_next_page()

# ==========================================
# INTERACTION & SCROLLING
# ==========================================

func _on_item_focused(item_data, item_node):
	_last_focused_item = item_node
	
	if _should_auto_scroll():
		_ensure_node_visible(item_node, false)
	
	_set_item_background(item_data)

func _set_item_background(item_data) -> void:
	var path = _get_background_image_path(item_data)
	if not path.is_empty() and FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img and background_art:
			background_art.texture = ImageTexture.create_from_image(img)
		elif background_art:
			background_art.texture = default_background_image
	elif background_art:
		background_art.texture = default_background_image

func _ensure_node_visible(node: Control, wait_for_layout: bool = true):
	if wait_for_layout:
		await get_tree().process_frame
	
	if not is_instance_valid(node): return
	
	node.grab_focus()
	
	var scroll: ScrollContainer = list_container.get_parent()
	var top = node.position.y
	var bottom = top + node.size.y
	var scroll_pos = scroll.scroll_vertical
	var view_height = scroll.size.y
	
	var margin = node.size.y * 0.5
	var target_pos = scroll_pos
	
	if top < scroll_pos:
		target_pos = int(max(0, top - margin))
	elif bottom > scroll_pos + view_height:
		target_pos = int(bottom - view_height + margin)
		
	if target_pos != scroll_pos:
		if _scroll_tween:
			_scroll_tween.kill()
		
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(scroll, "scroll_vertical", target_pos, 0.2) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)

func _notification(what):
	if what == NOTIFICATION_DRAG_BEGIN:
		is_dragging_item = true
		call_deferred("_nudge_scroll_to_break_panning")
	elif what == NOTIFICATION_DRAG_END:
		is_dragging_item = false
		_sync_data_from_visual_order()
		call_deferred("_inject_click_to_cancel_scroll")

func _inject_click_to_cancel_scroll():
	var mouse_pos = get_viewport().get_mouse_position()
	
	var press_event = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = mouse_pos
	press_event.global_position = mouse_pos
	Input.parse_input_event(press_event)
	
	var release_event = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = mouse_pos
	release_event.global_position = mouse_pos
	Input.parse_input_event(release_event)

func _nudge_scroll_to_break_panning():
	var scroll = list_container.get_parent()
	if scroll is ScrollContainer:
		var current = scroll.scroll_vertical
		scroll.scroll_vertical = current + 1
		scroll.scroll_vertical = current

func _process(delta):
	if is_dragging_item:
		var viewport_rect = get_viewport().get_visible_rect()
		var mouse_pos = get_viewport().get_mouse_position()
		var scroll_zone = viewport_rect.size.y * 0.15
		var scroll_speed = 500.0 * delta
		var scroll_container = list_container.get_parent()
		
		if mouse_pos.y < scroll_zone:
			scroll_container.scroll_vertical -= int(scroll_speed)
		elif mouse_pos.y > (viewport_rect.size.y - scroll_zone):
			scroll_container.scroll_vertical += int(scroll_speed)

	var is_popup_visible = option_sort.get_popup().visible if option_sort else false
	if is_popup_visible:
		var joy_confirm_button = false
		var joy_cancel_button = false
		if Input.get_connected_joypads().size() > 0:
			var swap_zx = PicoVideoStreamer.get_swap_zx_enabled()
			if swap_zx:
				joy_confirm_button = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_B)
				joy_cancel_button = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A)
			else:
				joy_confirm_button = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A)
				joy_cancel_button = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_B)
			
		if not popup_was_visible and joy_confirm_button:
			was_confirm_pressed = true
			
		if joy_confirm_button and not was_confirm_pressed:
			var ev = InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			Input.parse_input_event(ev)
			
			var ev_release = InputEventKey.new()
			ev_release.keycode = KEY_ENTER
			ev_release.pressed = false
			Input.parse_input_event(ev_release)
			
		if joy_cancel_button and not was_cancel_pressed:
			option_sort.get_popup().hide()
			
		was_confirm_pressed = joy_confirm_button
		was_cancel_pressed = joy_cancel_button
		
	popup_was_visible = is_popup_visible
	
	var focus_owner = get_viewport().gui_get_focus_owner()
	var focus_item = focus_owner if (focus_owner and focus_owner.has_method("setup")) else null
	
	if focus_item:
		var holding_a = _get_polling_action_held()
		if holding_a:
			var move_dir = 0
			if Input.is_action_pressed("ui_up") or _is_joy_dpad_pressed(JoyButton.JOY_BUTTON_DPAD_UP):
				move_dir = -1
			elif Input.is_action_pressed("ui_down") or _is_joy_dpad_pressed(JoyButton.JOY_BUTTON_DPAD_DOWN):
				move_dir = 1
				
			if move_dir != 0:
				if _can_trigger_repeat():
					_on_item_request_move_step(move_dir, focus_item)

func _get_polling_action_held() -> bool:
	var button_to_check = JoyButton.JOY_BUTTON_A
	if PicoVideoStreamer.get_swap_zx_enabled():
		button_to_check = JoyButton.JOY_BUTTON_B
	return Input.is_action_pressed("ui_accept") or _is_joy_button_pressed(button_to_check)

func _is_joy_button_pressed(btn: int) -> bool:
	if Input.get_connected_joypads().size() > 0:
		return Input.is_joy_button_pressed(0, btn)
	return false

func _is_joy_dpad_pressed(btn: int) -> bool:
	if Input.get_connected_joypads().size() > 0:
		return Input.is_joy_button_pressed(0, btn)
	return false

var _repeat_timer: float = 0.0
var _INITIAL_DELAY = 0.2
var _REPEAT_RATE = 0.05
var _is_repeating = false

func _can_trigger_repeat() -> bool:
	_repeat_timer += get_process_delta_time()
	var threshold = _REPEAT_RATE if _is_repeating else _INITIAL_DELAY
	if _repeat_timer >= threshold:
		_repeat_timer = 0.0
		_is_repeating = true
		return true
	return false

func _input(event):
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.is_released() or (event is InputEventJoypadMotion and abs(event.axis_value) < 0.2):
			if not (Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down") or _is_joy_dpad_pressed(JoyButton.JOY_BUTTON_DPAD_UP) or _is_joy_dpad_pressed(JoyButton.JOY_BUTTON_DPAD_DOWN)):
				_repeat_timer = 0.0
				_is_repeating = false

func _should_auto_scroll() -> bool:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if Input.is_action_just_pressed(action) or Input.is_action_pressed(action):
			return true
	
	if Input.get_connected_joypads().size() > 0:
		var joy_id = 0
		var axes_active = abs(Input.get_joy_axis(joy_id, JoyAxis.JOY_AXIS_LEFT_Y)) > 0.5
		var dpad_active = Input.is_joy_button_pressed(joy_id, JoyButton.JOY_BUTTON_DPAD_UP) or Input.is_joy_button_pressed(joy_id, JoyButton.JOY_BUTTON_DPAD_DOWN)
		if axes_active or dpad_active:
			return true
	return false

# ==========================================
# FOCUS MANAGEMENT (List internals)
# ==========================================

func _on_explicit_gui_input(event: InputEvent, node: Control):
	if _is_action_held(event):
		if node is OptionButton:
			node.show_popup()
			get_viewport().set_input_as_handled()
		elif node is Button:
			node.pressed.emit()
			get_viewport().set_input_as_handled()

func _is_action_held(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		if event.pressed and (event.button_index == JoyButton.JOY_BUTTON_A or event.button_index == JoyButton.JOY_BUTTON_B):
			return true
	return false

func _update_full_focus_chain():
	_setup_static_focus_connections()
	var count = list_container.get_child_count()
	if count == 0:
		_update_boundary_focus()
		return
		
	for i in range(count):
		_update_focus_for_index(i)

func _setup_static_focus_connections():
	if option_sort and btn_asc_desc:
		option_sort.focus_neighbor_right = btn_asc_desc.get_path()
		btn_asc_desc.focus_neighbor_left = option_sort.get_path()
	_apply_subclass_static_focus()

func _apply_subclass_static_focus():
	pass

func _update_surgical_focus_range(idx_a: int, idx_b: int):
	var min_idx = clampi(mini(idx_a, idx_b) - 1, 0, list_container.get_child_count() - 1)
	var max_idx = clampi(maxi(idx_a, idx_b) + 1, 0, list_container.get_child_count() - 1)
	
	for i in range(min_idx, max_idx + 1):
		_update_focus_for_index(i)

func _update_focus_for_index(idx: int):
	var items = list_container.get_children()
	var count = items.size()
	if idx < 0 or idx >= count: return
	
	var item = items[idx]
	var prev = items[idx - 1] if idx > 0 else null
	var next = items[idx + 1] if idx < count - 1 else null
	
	item.focus_neighbor_top = prev.get_path() if prev else (option_sort.get_path() if option_sort else btn_close.get_path())
	item.focus_neighbor_bottom = next.get_path() if next else btn_close.get_path()
	item.focus_neighbor_left = btn_asc_desc.get_path() if btn_asc_desc else btn_close.get_path()
	item.focus_neighbor_right = btn_close.get_path()
	
	if idx == 0:
		if option_sort:
			option_sort.focus_neighbor_bottom = item.get_path()
		if btn_asc_desc:
			btn_asc_desc.focus_neighbor_right = item.get_path()
			btn_asc_desc.focus_neighbor_bottom = item.get_path()
	
	if idx == count - 1:
		_update_boundary_focus(item)

func _update_boundary_focus(last_item: Control = null):
	var items = list_container.get_children()
	var count = items.size()
	
	if count == 0:
		_apply_empty_list_boundary_focus()
		return

	if not last_item:
		last_item = items[count - 1]
		
	_apply_subclass_boundary_focus(last_item)
	last_item.focus_neighbor_bottom = btn_close.get_path()

func _apply_empty_list_boundary_focus():
	pass

func _apply_subclass_boundary_focus(_last_item: Control):
	pass

# ==========================================
# DATA REORDERING
# ==========================================

func _sync_data_from_visual_order():
	var new_current_items: Array = []
	for child in list_container.get_children():
		if child.has_method("setup") and child.get("item_data"):
			new_current_items.append(child.item_data)
	
	current_items = new_current_items
	
	for i in range(current_items.size()):
		_all_items[i] = current_items[i]
	
	if option_sort and option_sort.selected == 0:
		_manual_order_cache = _all_items.duplicate()
	
	_update_list_indices()

func _update_list_indices():
	var item_idx = 0
	for i in range(list_container.get_child_count()):
		var child = list_container.get_child(i)
		if child.has_method("setup"):
			child.list_index = item_idx
			item_idx += 1

func _on_item_request_move_step(direction: int, item_node):
	var source_idx = item_node.list_index
	var target_idx = source_idx + direction
	
	if target_idx < 0 or target_idx >= current_items.size():
		return
		
	list_container.move_child(item_node, target_idx)
	_sync_data_from_visual_order()
	
	if option_sort:
		option_sort.selected = 0
	
	_update_surgical_focus_range(source_idx, target_idx)
	_ensure_node_visible(item_node)

# ==========================================
# UI ACTIONS
# ==========================================

func _on_close():
	if _is_dirty:
		if PicoVideoStreamer.instance:
			var runcmd = PicoVideoStreamer.instance.get_node_or_null("runcmd")
			if runcmd and runcmd.has_method("restart_pico8"):
				runcmd.restart_pico8()
			
	request_close.emit()
	queue_free()

func _on_sort_criteria_changed(_index: int):
	if is_instance_valid(option_sort):
		var sort_text = option_sort.get_item_text(option_sort.selected)
		if sort_text in ["Launches", "Play Time"]:
			is_ascending = false
			btn_asc_desc.text = "⬇️"
		elif sort_text in ["Name", "Author"]:
			is_ascending = true
			btn_asc_desc.text = "⬆️"

	_apply_sort()
	_rebuild_sorted_list()

func _on_asc_desc_toggled():
	is_ascending = !is_ascending
	btn_asc_desc.text = "⬆️" if is_ascending else "⬇️"
	_apply_sort()
	_rebuild_sorted_list()

func _rebuild_sorted_list():
	current_items.clear()
	var max_items = mini(_loaded_count, _all_items.size())
	if max_items == 0 and _all_items.size() > 0:
		max_items = mini(_items_per_page, _all_items.size())
		
	for i in range(max_items):
		current_items.append(_all_items[i])
		
	_loaded_count = max_items
	_refresh_list()
	
	if _loaded_count < _all_items.size():
		_add_load_more_button()
