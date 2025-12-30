extends CanvasLayer

func _process(delta: float) -> void:
	var orientation = DisplayServer.screen_get_orientation()
	var is_landscape = false

	if OS.has_feature("mobile"):
		if (orientation == DisplayServer.ScreenOrientation.SCREEN_LANDSCAPE or
			orientation == DisplayServer.ScreenOrientation.SCREEN_REVERSE_LANDSCAPE or
			orientation == DisplayServer.ScreenOrientation.SCREEN_SENSOR_LANDSCAPE):
			is_landscape = true
		elif (orientation == DisplayServer.ScreenOrientation.SCREEN_PORTRAIT or
			orientation == DisplayServer.ScreenOrientation.SCREEN_REVERSE_PORTRAIT or
			orientation == DisplayServer.ScreenOrientation.SCREEN_SENSOR_PORTRAIT):
			is_landscape = false
		else:
			var win_size = DisplayServer.window_get_size()
			is_landscape = win_size.x > win_size.y
	else:
		var win_size = DisplayServer.window_get_size()
		is_landscape = win_size.x > win_size.y
	
	# Only show if in landscape mode AND controls are needed (no physical controller)
	var is_controller_connected = _is_real_controller_connected()
	var should_be_visible = is_landscape and not is_controller_connected
	
	# Debug print (remove later)
	# print("LandscapeUI: landscape=", is_landscape, " controller=", is_controller_connected, " visible=", should_be_visible)
	
	visible = should_be_visible

func _is_real_controller_connected() -> bool:
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		var name = Input.get_joy_name(device_id).to_lower()
		
		# Filter out common non-gamepad devices on Android
		if ("accelerometer" in name or "gyro" in name or "sensor" in name or 
			"virtual" in name or "touch" in name or "keypad" in name or "stylus" in name or
			"uinput-fpc" in name):
			continue
			
		return true
	
	return false
