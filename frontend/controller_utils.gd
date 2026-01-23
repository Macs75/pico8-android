extends Node
class_name ControllerUtils

static var ignored_devices: Array[String] = [
	"accelerometer",
	"gyro",
	"sensor",
	"virtual",
	"touch",
	"keypad",
	"stylus",
	"uinput-fpc"
]

static var ignored_devices_by_user: Array[String] = []

static func is_real_controller_connected() -> bool:
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		var joy_name = Input.get_joy_name(device_id).to_lower()
		var is_ignored = false
		
		# System Ignored
		for ignored in ignored_devices:
			if ignored in joy_name:
				is_ignored = true
				break
		
		if is_ignored:
			continue
			
		# User Ignored
		if joy_name in ignored_devices_by_user:
			continue
			
		print("Controller name: ", joy_name)
		return true
	
	return false

static func get_real_controllers() -> Array:
	var real_joypads = []
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		var joy_name = Input.get_joy_name(device_id).to_lower()
		var is_ignored = false
		
		for ignored in ignored_devices:
			if ignored in joy_name:
				is_ignored = true
				break
		
		if not is_ignored:
			real_joypads.append(device_id)
			
	return real_joypads
