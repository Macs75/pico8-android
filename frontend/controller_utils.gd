extends Node
class_name ControllerUtils

static func is_real_controller_connected() -> bool:
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		var joy_name = Input.get_joy_name(device_id).to_lower()
		# Filter out common non-gamepad devices on Android
		if ("accelerometer" in joy_name or "gyro" in joy_name or "sensor" in joy_name or
			"virtual" in joy_name or "touch" in joy_name or "keypad" in joy_name or "stylus" in joy_name or
			"uinput-fpc" in joy_name):
			continue
		print("Controller name: ", joy_name)
		return true
	
	return false
