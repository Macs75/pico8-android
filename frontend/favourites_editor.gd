extends Control

var item_scene = preload("res://favourites_item.tscn")
const FavouritesManagerScript = preload("res://favourites_manager.gd")
var current_items: Array = []
var is_ascending: bool = true
var current_font_size: int = 0

func _ready():
	%BtnCancel.pressed.connect(_on_cancel)
	%BtnSave.pressed.connect(_on_save)
	
	%OptionSort.item_selected.connect(_on_sort_criteria_changed)
	%OptionSort.gui_input.connect(_on_explicit_gui_input.bind(%OptionSort))
	
	%BtnAscDesc.pressed.connect(_on_asc_desc_toggled)
	%BtnAscDesc.gui_input.connect(_on_explicit_gui_input.bind(%BtnAscDesc))
	
	# Footer Connections (Controller Support)
	%BtnCancel.gui_input.connect(_on_explicit_gui_input.bind(%BtnCancel))
	%BtnSave.gui_input.connect(_on_explicit_gui_input.bind(%BtnSave))
	
	# Connect to resize
	get_tree().root.size_changed.connect(_update_layout)
	
	_load_data()
	
	# Initial layout
	call_deferred("_update_layout")
	
	# Disable game input
	if PicoVideoStreamer.instance:
		print("FavouritesEditor: Disabling PICO-8 Input (Instance found)")
		# Use internal blocked flag for safer blocking
		if PicoVideoStreamer.instance.has_method("set_input_blocked"):
			PicoVideoStreamer.instance.set_input_blocked(true)

		PicoVideoStreamer.instance.set_process_unhandled_input(false)
		PicoVideoStreamer.instance.set_process_input(false)
	else:
		print("FavouritesEditor: ERROR - PicoVideoStreamer.instance is NULL! Cannot disable input.")

		
	# Enable processing for Controller Polling (Popup) and Auto-Scroll (Restricted)
	set_process(true)

func _exit_tree():
	# Re-enable game input with a delay to prevent the closing event (B button release) 
	# from leaking into PICO-8. We use a timer connected to a lambda to ensure it runs
	# even after this node is freed.
	var tree = get_tree()
	if tree:
		var tmr = tree.create_timer(0.2)
		tmr.timeout.connect(func():
			# Check if a new FavouritesEditor has been opened in the meantime
			if tree.root.has_node("FavouritesEditor"):
				print("FavouritesEditor: New instance detected, keeping input disabled.")
				return
				
			var streamer = PicoVideoStreamer.instance
			if is_instance_valid(streamer):
				print("FavouritesEditor: Enabling PICO-8 Input (Timer expired)")
				if streamer.has_method("set_input_blocked"):
					streamer.set_input_blocked(false)
				
				streamer.set_process_unhandled_input(true)
				streamer.set_process_input(true)
		)

func _update_layout():
	var viewport_size = get_viewport_rect().size
	var min_dim = min(viewport_size.x, viewport_size.y)
	
	var dynamic_font_size = int(max(24, min_dim * 0.05))
	current_font_size = dynamic_font_size
	
	# Ensure scroll follows focus
	%ListContainer.get_parent().follow_focus = true
	
	# Apply dynamic margins
	var v_margin = int(viewport_size.y * 0.08)
	var h_margin = int(viewport_size.x * 0.06)
	
	var margin_container = $Panel/MarginContainer
	margin_container.add_theme_constant_override("margin_top", v_margin)
	margin_container.add_theme_constant_override("margin_bottom", v_margin)
	margin_container.add_theme_constant_override("margin_left", h_margin)
	margin_container.add_theme_constant_override("margin_right", h_margin)
	
	# Apply to Header
	$Panel/MarginContainer/VBox/Header/LabelTitle.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	$Panel/MarginContainer/VBox/Header/SortButtons/LabelSort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%OptionSort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%OptionSort.get_popup().add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%BtnAscDesc.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Apply to Footer
	%BtnCancel.add_theme_font_size_override("font_size", dynamic_font_size)
	%BtnSave.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Update items
	for item in %ListContainer.get_children():
		if item.has_method("set_font_size"):
			item.set_font_size(dynamic_font_size)

func _load_data():
	# Load raw items
	current_items = FavouritesManagerScript.load_favourites()
	_refresh_list()
	
	# Initial focus on first item if available
	if current_items.size() > 0:
		call_deferred("_grab_initial_focus")

func _grab_initial_focus():
	if %ListContainer.get_child_count() > 0:
		%ListContainer.get_child(0).grab_focus()

func _refresh_list():
	# Clear existing children immediately to ensure get_children() later 
	# only returns the new nodes
	for child in %ListContainer.get_children():
		%ListContainer.remove_child(child)
		child.queue_free()
		
	# Populate new list
	for i in range(current_items.size()):
		var item_data = current_items[i]
		var item_node = item_scene.instantiate()
		%ListContainer.add_child(item_node)
		
		# Set data and index
		item_node.setup(item_data, i)
		# Connect drag drop signal
		if not item_node.item_dropped.is_connected(_on_item_dropped_reorder):
			item_node.item_dropped.connect(_on_item_dropped_reorder)
			
		# Connect live reorder signal
		if not item_node.item_reorder_requested.is_connected(_on_item_reorder_requested):
			item_node.item_reorder_requested.connect(_on_item_reorder_requested)
			
		# Connect controller reorder step signal
		if item_node.has_signal("request_move_step"):
			item_node.request_move_step.connect(_on_item_request_move_step.bind(item_node))
			
		# Connect focus signal for background art
		if not item_node.focus_entered.is_connected(_on_item_focused):
			item_node.focus_entered.connect(_on_item_focused.bind(item_data))
			
		# Apply current font size if available
		if current_font_size > 0:
			item_node.set_font_size(current_font_size)
			
	_setup_focus_chain()

func _on_item_focused(item_data):
	var path = ""
	var base_path = FavouritesManagerScript.PICO8_DATA_PATH
	
	# Priority 1: BBS Carts (Col 1 + .p8.png)
	if not item_data.cart_id.is_empty():
		# to support offline multicarts: default is to use /bbs/carts else if the name is numeric we bind the relative path from pico8 folder
		# this may break in the future if the bbs folder structure changes
		var subfolder = "carts"
		if item_data.cart_id.is_valid_int():
			if item_data.cart_id.length() >= 5:
				subfolder = item_data.cart_id[0]
			else:
				subfolder = "0"
		path = base_path + "/bbs/" + subfolder + "/" + item_data.cart_id + ".p8.png"
	# Priority 2: Local Carts (Col 5, exact filename)
	elif not item_data.filename.is_empty():
		path = base_path + "/carts/" + item_data.filename
	
	if not path.is_empty() and FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			if %BackgroundArt:
				%BackgroundArt.texture = tex
		else:
			if %BackgroundArt: %BackgroundArt.texture = null
	else:
		# Clear if no image found
		if %BackgroundArt: %BackgroundArt.texture = null

func _setup_focus_chain():
	var items = %ListContainer.get_children()
	var count = items.size()
	
	# 1. Header connections
	# Sort Option
	%OptionSort.focus_neighbor_right = %BtnAscDesc.get_path()
	%OptionSort.focus_neighbor_left = %BtnSave.get_path() # From Save (Loop)
	if count > 0:
		%OptionSort.focus_neighbor_bottom = items[0].get_path()
	else:
		%OptionSort.focus_neighbor_bottom = %BtnCancel.get_path()
		
	# Asc/Desc
	%BtnAscDesc.focus_neighbor_left = %OptionSort.get_path()
	if count > 0:
		%BtnAscDesc.focus_neighbor_right = items[0].get_path() # Cycle logic: Sort -> Asc/Desc -> List
		%BtnAscDesc.focus_neighbor_bottom = items[0].get_path()
	else:
		%BtnAscDesc.focus_neighbor_right = %BtnCancel.get_path()
		%BtnAscDesc.focus_neighbor_bottom = %BtnCancel.get_path()

	# 2. List connections
	for i in range(count):
		var item = items[i]
		var prev = items[i - 1] if i > 0 else null
		var next = items[i + 1] if i < count - 1 else null
		
		# Up
		if prev:
			item.focus_neighbor_top = prev.get_path()
		else:
			item.focus_neighbor_top = %OptionSort.get_path()
			
		# Down
		if next:
			item.focus_neighbor_bottom = next.get_path()
		else:
			item.focus_neighbor_bottom = %BtnCancel.get_path()
			
		# Left/Right Cycle
		# List.Left -> Asc/Desc
		item.focus_neighbor_left = %BtnAscDesc.get_path()
		# List.Right -> Cancel
		item.focus_neighbor_right = %BtnCancel.get_path()
		
	# 3. Footer connections
	# Cancel
	%BtnCancel.focus_neighbor_top = items[count - 1].get_path() if count > 0 else %OptionSort.get_path()
	%BtnCancel.focus_neighbor_bottom = %BtnSave.get_path() # Custom Down behavior
	
	# Left/Right Cycle: List -> Cancel -> Save
	%BtnCancel.focus_neighbor_left = items[count - 1].get_path() if count > 0 else %BtnAscDesc.get_path()
	%BtnCancel.focus_neighbor_right = %BtnSave.get_path()
	
	# Save
	%BtnSave.focus_neighbor_top = %BtnCancel.get_path() # Up goes back to Cancel? "Pressing down again it should go to Save from there" - implying stacking.
	%BtnSave.focus_neighbor_left = %BtnCancel.get_path()
	%BtnSave.focus_neighbor_right = %OptionSort.get_path() # Loop back to start

func _on_item_request_move_step(direction: int, item_node):
	var idx = item_node.get_index()
	var target_idx = idx + direction
	
	# Check bounds
	if target_idx < 0 or target_idx >= current_items.size():
		return
		
	# Update Array
	var moved_data = current_items.pop_at(idx)
	current_items.insert(target_idx, moved_data)
	
	# Update Visual Tree
	%ListContainer.move_child(item_node, target_idx)
	
	# Update indices to support mixed usage (Drag/Drop + Controller)
	for i in range(%ListContainer.get_child_count()):
		%ListContainer.get_child(i).list_index = i
	
	# Switch to Manual sort mode
	%OptionSort.selected = 0
	
	# Re-setup neighbors because tree order changed
	_setup_focus_chain()
	
	# Ensure focus stays
	item_node.grab_focus()

func _on_item_dropped_reorder(source_idx: int, target_idx: int):
	if source_idx == target_idx:
		return
		
	var moved_item = current_items.pop_at(source_idx)
	
	# Adjust target index if source was before target
	if source_idx < target_idx:
		target_idx -= 1
		
	current_items.insert(target_idx, moved_item)
	
	# Switch to Manual sort mode visual
	%OptionSort.selected = 0
	
	_refresh_list()
	# Restore focus if needed? Drag usually implies mouse, so probably fine.

func _on_item_reorder_requested(source_item, target_item):
	var source_idx = source_item.get_index()
	var target_idx = target_item.get_index()
	
	if source_idx == target_idx:
		return
		
	# Move in visual tree - this creates the "live" effect
	%ListContainer.move_child(source_item, target_idx)

	var moved_item_data = current_items.pop_at(source_idx)
	current_items.insert(target_idx, moved_item_data)
	
	# For now, just update the sort mode to manual
	%OptionSort.selected = 0

var is_dragging_item: bool = false
var was_joy_a_pressed: bool = false
var was_joy_b_pressed: bool = false
var popup_was_visible: bool = false

func _notification(what):
	if what == NOTIFICATION_DRAG_BEGIN:
		# Disable manual scrolling during drag to prevent interference
		%ListContainer.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
		is_dragging_item = true
	elif what == NOTIFICATION_DRAG_END:
		# Re-enable manual scrolling
		%ListContainer.get_parent().mouse_filter = Control.MOUSE_FILTER_STOP
		is_dragging_item = false

func _process(delta):
	# 1. Auto-Scroll Logic (Only when dragging)
	if is_dragging_item:
		var viewport_rect = get_viewport_rect()
		var mouse_pos = get_viewport().get_mouse_position()
		var scroll_zone = viewport_rect.size.y * 0.15
		var scroll_speed = 500.0 * delta
		
		var scroll_container = %ListContainer.get_parent()
		
		if mouse_pos.y < scroll_zone:
			scroll_container.scroll_vertical -= int(scroll_speed)
		elif mouse_pos.y > (viewport_rect.size.y - scroll_zone):
			scroll_container.scroll_vertical += int(scroll_speed)

	# 2. Popup Controller Logic (Polling because Popup blocks _input)
	var is_popup_visible = %OptionSort.get_popup().visible
	
	if is_popup_visible:
		var joy_a = false
		var joy_b = false
		
		# Check Joypads (Iterate or just check 0)
		if Input.get_connected_joypads().size() > 0:
			joy_a = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A)
			joy_b = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_B)
			
		# Open Debounce: If popup just appeared and A is held (used to open it),
		# ignore it until released.
		if not popup_was_visible and joy_a:
			was_joy_a_pressed = true
			
		# Just Pressed A -> Select (Enter)
		if joy_a and not was_joy_a_pressed:
			var ev = InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			Input.parse_input_event(ev)
			
			# Release immediately to prevent stuck "ui_accept" action
			var ev_release = InputEventKey.new()
			ev_release.keycode = KEY_ENTER
			ev_release.pressed = false
			Input.parse_input_event(ev_release)
			
		# Just Pressed B -> Cancel (Hide)
		if joy_b and not was_joy_b_pressed:
			%OptionSort.get_popup().hide()
			
		was_joy_a_pressed = joy_a
		was_joy_b_pressed = joy_b
		
	popup_was_visible = is_popup_visible

func _input(event: InputEvent) -> void:
	# Keep input if a popup is open (let the popup handle it via polling/internal)
	if %OptionSort.get_popup().visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
		return
		
	if event is InputEventJoypadButton:
		if event.pressed and (event.button_index == JoyButton.JOY_BUTTON_B):
			_on_cancel()
			get_viewport().set_input_as_handled()
			return

	# Smart Focus Regain: If no focus, directional input grabs first visible item
	if not get_viewport().gui_get_focus_owner():
		if _is_directional_input(event):
			_regain_focus()
			get_viewport().set_input_as_handled()

func _is_directional_input(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")

func _regain_focus():
	var scroll_container = %ListContainer.get_parent()
	var scroll_rect = scroll_container.get_global_rect()
	
	# Try to find first visible item in list
	for item in %ListContainer.get_children():
		var item_rect = item.get_global_rect()
		# Check if item is roughly inside the scroll view (simple y-overlap check)
		if item_rect.position.y + item_rect.size.y > scroll_rect.position.y and \
		   item_rect.position.y < scroll_rect.position.y + scroll_rect.size.y:
			item.grab_focus()
			return
			
	# Fallback if no list items visible or empty list
	if %OptionSort.is_visible_in_tree():
		%OptionSort.grab_focus()
	elif %BtnCancel.is_visible_in_tree():
		%BtnCancel.grab_focus()

func _on_sort_criteria_changed(index: int):
	# 0=Manual, 1=Name, 2=Author
	if index != 0:
		_apply_sort()

func _on_asc_desc_toggled():
	is_ascending = not is_ascending
	%BtnAscDesc.text = "⬇️" if not is_ascending else "⬆️"
	_apply_sort()

func _apply_sort():
	var criteria = %OptionSort.selected
	if criteria == 0: return
	
	current_items.sort_custom(func(a, b):
		var a_val = a.name if criteria == 1 else a.author
		var b_val = b.name if criteria == 1 else b.author
		
		# Handle nulls
		if a_val == null: a_val = ""
		if b_val == null: b_val = ""
		
		if is_ascending:
			return a_val.nocasecmp_to(b_val) < 0
		else:
			return a_val.nocasecmp_to(b_val) > 0
	)
	
	_refresh_list()

func _on_save():
	var success = FavouritesManagerScript.save_favourites(current_items)
	if success:
		# Restart PICO-8 to apply changes
		var runcmd = get_tree().current_scene.find_child("runcmd")
		if runcmd and runcmd.has_method("restart_pico8"):
			runcmd.restart_pico8()
		else:
			print("Could not find runcmd to restart PICO-8")
			
		queue_free()
	else:
		OS.alert("Failed to save favourites!", "Error")

func _on_cancel():
	queue_free()

func _on_explicit_gui_input(event: InputEvent, control: Control):
	if _is_action_held(event):
		if control is OptionButton:
			control.show_popup()
			# popup handling is automatic usually
			get_viewport().set_input_as_handled()
		elif control is Button:
			control.pressed.emit()
			get_viewport().set_input_as_handled()

func _is_action_held(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		return true
		
	if event is InputEventJoypadButton:
		if event.pressed and (event.button_index == JoyButton.JOY_BUTTON_A or event.button_index == JoyButton.JOY_BUTTON_B):
			return true
			
	return false
