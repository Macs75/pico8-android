extends Control

@onready var container = %VBoxContainer
@onready var close_btn = %ButtonClose

@onready var test_popup = %TestPopup
@onready var button_test_label = %ResultLabel
@onready var axis_test_label = %ResultLabel2
@onready var key_test_label = %ResultLabel3
@onready var close_test_btn = %CloseTestBtn
var test_device_id: int = -1
var last_event_time: int = 0

func _ready() -> void:
	# Enforce opaque background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0) # Dark Opaque
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	add_theme_stylebox_override("panel", style)

	close_btn.pressed.connect(queue_free)
	
	# Connect Test Popup Close Button
	if close_test_btn:
		close_test_btn.pressed.connect(func():
			test_popup.visible = false
			test_device_id = -1
			if PicoVideoStreamer.instance:
				PicoVideoStreamer.instance.set_input_blocked(false)
		)
	
	get_tree().root.size_changed.connect(_fit_to_screen)
	_populate_list()
	
	# Initial fit
	call_deferred("_fit_to_screen")

func _exit_tree():
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.set_input_blocked(false)

func _populate_list():
	# Clear existing children if any (except template)
	for child in container.get_children():
		if child != %RowTemplate:
			child.queue_free()
		
	# Iterate ALL connected (including user-disabled) but skip system-ignored
	var joypads = Input.get_connected_joypads()
	var visible_count = 0
	
	for device_id in joypads:
		if ControllerUtils.is_system_ignored(device_id):
			continue
			
		visible_count += 1
		var joy_name = Input.get_joy_name(device_id).to_lower()
		print("Found controller: ", joy_name)
		print("Info: ", Input.get_joy_info(device_id))
		var display_name = joy_name
		if display_name.length() > 20:
			display_name = display_name.left(20) + "..."
			
		var row = %RowTemplate.duplicate()
		row.visible = true
		
		# Setup Label
		var label = row.get_node("NameLabel")
		label.text = display_name
		
		# Setup OptionButton
		var opt = row.get_node("RoleOption")
		# Items are already set in scene, just need logic
		
		# Determine current selection
		var current_role = ControllerUtils.get_controller_role(device_id)
		
		if current_role == ControllerUtils.ROLE_AUTO:
			opt.selected = 0
		elif current_role == ControllerUtils.ROLE_P1:
			opt.selected = 1
		elif current_role == ControllerUtils.ROLE_P2:
			opt.selected = 2
		elif current_role == ControllerUtils.ROLE_DISABLED:
			opt.selected = 3
			
		opt.item_selected.connect(func(index):
			# Map Index -> Role
			var new_role = ControllerUtils.ROLE_AUTO
			if index == 0: new_role = ControllerUtils.ROLE_AUTO
			elif index == 1: new_role = ControllerUtils.ROLE_P1
			elif index == 2: new_role = ControllerUtils.ROLE_P2
			elif index == 3: new_role = ControllerUtils.ROLE_DISABLED
			
			ControllerUtils.controller_assignments[joy_name] = new_role
			
			# Trigger update in arranger immediately
			var arranger = get_tree().root.get_node_or_null("Main/Arranger")
			if arranger:
				arranger.update_controller_state()
		)
		
		# Setup Test Button
		var test_btn = row.get_node("TestBtn")
		test_btn.pressed.connect(func(): _show_test_popup(device_id))

		# Setup Export Button
		var export_btn = row.get_node("ExportBtn")
		export_btn.pressed.connect(func(): _export_mapping(device_id))

		container.add_child(row)
		
	if visible_count == 0:
		var label = Label.new()
		label.text = "No controllers connected."
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(label)

func _export_mapping(device_id: int):
	var guid = Input.get_joy_guid(device_id)
	var joy_name = Input.get_joy_name(device_id)
	var path = PicoBootManager.PUBLIC_FOLDER + "/pico8_sdl_controllers.txt"
	
	print("Attempting export for: ", joy_name, " [", guid, "]")
	
	var f = null
	if FileAccess.file_exists(path):
		var content = FileAccess.get_file_as_string(path)
		if guid in content:
			print("Mapping for GUID ", guid, " already exists in ", path)
			return
		f = FileAccess.open(path, FileAccess.WRITE)
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_line("# Pico8 SDL Controllers mapping file")
		f.store_line("# Created by Pico8 Android")
		f.store_line("# Button Name   Description")
		f.store_line("# a             Bottom face button (Xbox A, PlayStation Cross)")
		f.store_line("# b             Right face button (Xbox B, PlayStation Circle)")
		f.store_line("# x             Left face button (Xbox X, PlayStation Square)")
		f.store_line("# y             Top face button (Xbox Y, PlayStation Triangle)")
		f.store_line("# dpup          D-pad up button (Xbox D-pad Up, PlayStation D-pad Up)")
		f.store_line("# dpdown        D-pad down button (Xbox D-pad Down, PlayStation D-pad Down)")
		f.store_line("# dpleft        D-pad left button (Xbox D-pad Left, PlayStation D-pad Left)")
		f.store_line("# dpright       D-pad right button (Xbox D-pad Right, PlayStation D-pad Right)")
		f.store_line("# start         Start/Options button (Xbox Start, PlayStation Options)")
		f.store_line("# back          Back/Select button (Xbox Back, PlayStation Share/Create)")
		f.store_line("# guide         Guide button (Xbox Guide, PlayStation PS button)")
		f.store_line("# leftshoulder  Left shoulder button (Xbox LB, PlayStation L1)")
		f.store_line("# rightshoulder Right shoulder button (Xbox RB, PlayStation R1)")
		f.store_line("# lefttrigger   Left trigger button (Xbox LT, PlayStation L2)")
		f.store_line("# righttrigger  Right trigger button (Xbox RT, PlayStation R2)")
		f.store_line("# leftstick     Left stick button (Xbox LS, PlayStation L3)")
		f.store_line("# rightstick    Right stick button (Xbox RS, PlayStation R3)")
		f.store_line("# leftx         Left stick X axis (Xbox Left Stick X, PlayStation Left Stick X)")
		f.store_line("# lefty         Left stick Y axis (Xbox Left Stick Y, PlayStation Left Stick Y)")
		f.store_line("# rightx        Right stick X axis (Xbox Right Stick X, PlayStation Right Stick X)")
		f.store_line("# righty        Right stick Y axis (Xbox Right Stick Y, PlayStation Right Stick Y)")
		f.store_line("# ")
		f.store_line("# A button name is associated with a physical button index. Ex. a:b0 Bottom face button action to button b0 of the controller.")
		f.store_line("# Analog controls (a0-a3) are associated with a physical axis index. Ex.leftx:a0 Left stick X axis action to axis a0 of the controller.")
		f.store_line("# Triggers can be analog or digital depending on your controller. Analog usually have reference a4 and a5. Digital triggers are mapped as buttons.")
		f.store_line("# You don't have to map all buttons if you don't need to use them. If a button is not mapped, it will not send action if pressed.")
		f.store_line("# Use the test utility to find the button and axis indices for your controller.")
		f.store_line("# An example of button and axis mapping for a controller is: a:b0,b:b1,back:b4,dpdown:b12,dpleft:b13,dpright:b14,dpup:b11,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3")
		f.store_line("# The complete configuration for a controller is: [GUID],[CONTROLLER NAME],[BUTTONS MAPPING HERE],platform:Android,")
		f.store_line("# Example: 10000000000000000000000000000001,Random Controller,a:b0,b:b1,back:b4,dpdown:b12,dpleft:b13,dpright:b14,dpup:b11,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Android,")
		f.store_line("# ")
		f.store_line("# ")

	if f:
		f.seek_end() # Append
		f.store_line("# " + joy_name)
		f.store_line("# uncomment the line below (remove #) and fill in the mapping for your controller")
		f.store_line("#%s,%s,[MAPPING HERE],platform:Android," % [guid, joy_name])
		f.close()
		print("Exported mapping template to: ", path)
	else:
		print("Failed to open mapping file for writing: ", path)


func _show_test_popup(device_id: int):
	test_device_id = device_id
	test_popup.visible = true
	button_test_label.text = "Waiting..."
	axis_test_label.text = ""
	key_test_label.text = ""
	last_event_time = 0
	
	# Adjust font sizes for small screens
	var screen_size = get_viewport().get_visible_rect().size
	var font_size = clamp(int(min(screen_size.x, screen_size.y) * 0.05), 12, 24)
	
	button_test_label.add_theme_font_size_override("font_size", font_size)
	axis_test_label.add_theme_font_size_override("font_size", font_size)
	key_test_label.add_theme_font_size_override("font_size", font_size)
	
	# Also resize static headers
	var header = test_popup.get_node_or_null("VBoxContainer/Header")
	if header: header.add_theme_font_size_override("font_size", font_size)
	
	var subheader = test_popup.get_node_or_null("VBoxContainer/SubHeader")
	if subheader: subheader.add_theme_font_size_override("font_size", int(font_size * 0.8))
	
	# Force re-scale to fit new content size
	call_deferred("_fit_to_screen")
	
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.set_input_blocked(true)
	# Helper label is static in scene now

func _input(event):
	if test_popup and is_instance_valid(test_popup) and test_popup.visible:
		if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse:
			return
			
		# Allow InputEventKey from ANY device to pass through for debugging (to catch virtual keyboard inputs)
		# For limits/buttons, we still restrict to the selected device to avoid noise
		var is_key_event = event is InputEventKey
		if event.device == test_device_id or is_key_event:
			if last_event_time == 0:
				button_test_label.text = ""
			# Calculate and print delta
			var now = Time.get_ticks_msec()
			var delta = now - last_event_time
						
			# Helper to safely name ID
			var _get_dev_name = func(id):
				if id in Input.get_connected_joypads():
					var n = Input.get_joy_name(id)
					if n.length() > 15: return n.left(15) + ".."
					return n
				return "Non-Joypad"

			if event is InputEventJoypadButton and event.pressed:
				last_event_time = now
				button_test_label.text = "JoyBtn %d->b%d [ID: %d - %s]" % [event.button_index, event.button_index, event.device, _get_dev_name.call(event.device)]
				if delta > 100:
					axis_test_label.text = ""
					key_test_label.text = ""
			if event is InputEventJoypadMotion:
				if abs(event.axis_value) > 0.5:
					last_event_time = now
					axis_test_label.text = "JoyAxis %d->a%d [ID: %d - %s]" % [event.axis, event.axis, event.device, _get_dev_name.call(event.device)]
					if delta > 100:
						button_test_label.text = ""
						key_test_label.text = ""
			if event is InputEventKey:
				last_event_time = now
				key_test_label.text = "Key %d->%s [ID:%d - %s]" % [event.keycode, OS.get_keycode_string(event.keycode), event.device, _get_dev_name.call(event.device)]
				if delta > 100:
					button_test_label.text = ""
					axis_test_label.text = ""
		
				
func set_scale_factor(factor: float):
	scale = Vector2(factor, factor)
	call_deferred("_fit_to_screen")

func _fit_to_screen():
	# Clamp scale to fit screen
	var screen_size = get_viewport().get_visible_rect().size
	var current_size = size * scale
	
	# Margin 20px
	var max_w = screen_size.x - 40
	var max_h = screen_size.y - 40
	
	if current_size.x > max_w or current_size.y > max_h:
		var ratio_w = max_w / size.x
		var ratio_h = max_h / size.y
		var new_scale = min(scale.x, min(ratio_w, ratio_h))
		scale = Vector2(new_scale, new_scale)
		
	# Center it
	position = (screen_size - size * scale) / 2.0
