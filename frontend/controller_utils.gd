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

const ROLE_AUTO = -1
const ROLE_P1 = 0
const ROLE_P2 = 1
const ROLE_DISABLED = 2

# Name -> Role ID
static var controller_assignments: Dictionary = {}
# Backwards compatibility / simplified view
static var ignored_devices_by_user: Array[String] = []

static func get_controller_role(device_id: int) -> int:
	var joy_name = Input.get_joy_name(device_id).to_lower()
	
	# Check explicit assignment
	if joy_name in controller_assignments:
		return controller_assignments[joy_name]
		
	# Check legacy ignored list
	if joy_name in ignored_devices_by_user:
		return ROLE_DISABLED
		
	return ROLE_AUTO

static func is_controller_enabled(device_id: int) -> bool:
	return get_controller_role(device_id) != ROLE_DISABLED

static func is_real_controller_connected() -> bool:
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		if is_system_ignored(device_id): continue
		if is_controller_enabled(device_id):
			return true
	return false

static func is_system_ignored(device_id: int) -> bool:
	var joy_name = Input.get_joy_name(device_id).to_lower()
	for ignored in ignored_devices:
		if ignored in joy_name:
			return true
	return false

static func get_real_controllers() -> Array:
	var joypads = Input.get_connected_joypads()

	
	var p1_list = []
	var p2_list = []
	var auto_list = []
	
	for device_id in joypads:
		if is_system_ignored(device_id): continue
		
		var role = get_controller_role(device_id)
		if role == ROLE_DISABLED: continue
		
		if role == ROLE_P1: p1_list.append(device_id)
		elif role == ROLE_P2: p2_list.append(device_id)
		else: auto_list.append(device_id)
	
	# Construct final ordered list: P1s -> Autos -> P2s? 
	# Actually, usually P1s take slot 0. Autos take next available. P2s take slot 1?
	# But get_real_controllers just returns a list.
	# Let's return them in a logical connection order, but assignments respected if we use index.
	# But mostly we will use get_controller_role() in logic now.
	# Returning sorted list: P1 -> Auto -> P2
	return p1_list + auto_list + p2_list
