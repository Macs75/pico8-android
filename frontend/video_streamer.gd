extends Node2D
class_name PicoVideoStreamer

@export var loading: AnimatedSprite2D
@export var display: Sprite2D
@export var displayContainer: Sprite2D

var HOST = "192.168.0.42" if Engine.is_embedded_in_editor() else "127.0.0.1"
var PORT = 18080

# TCP Threading
var _thread: Thread
var _mutex: Mutex
var _thread_active: bool = false
var _reset_requested: bool = false
var _input_queue: Array = []

var tcp: StreamPeerTCP

const PIDOT_EVENT_MOUSEEV = 1;
const PIDOT_EVENT_KEYEV = 2;
const PIDOT_EVENT_CHAREV = 3;

var stream_texture: ImageTexture

var last_message_time: int = 0
const RETRY_INTERVAL: int = 200
const READ_TIMEOUT: int = 5000
var is_intent_session: bool = false
func _on_intent_session_started():
	print("Video Streamer: Intent Session Started (Controller Mapping Updated)")
	is_intent_session = true

func hard_reset_connection():
	print("Forcing Hard TCP Reset...")
	# Signal the thread to reset the connection
	if _mutex:
		_mutex.lock()
		_reset_requested = true
		_mutex.unlock()

static var instance: PicoVideoStreamer
func _ready() -> void:
	instance = self
	set_process_input(true)
	
	_setup_quit_overlay()
	
	# Pre-calculate PackedByteArray for fast sync check
	SYNC_SEQ_PBA = PackedByteArray(SYNC_SEQ)
	
	# Pre-allocate texture for performance (Triple Buffering)
	for i in range(3):
		var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		_buffer_images.append(img)
		
	stream_texture = ImageTexture.create_from_image(_buffer_images[0])
	display.texture = stream_texture

	# Start TCP Thread
	_mutex = Mutex.new()
	_thread = Thread.new()
	_thread_active = true
	_thread.start(_thread_function)
	
	# Connect the single keyboard toggle button
	var keyboard_btn = get_node("Arranger/kbanchor/HBoxContainer/Keyboard Btn")
	if keyboard_btn:
		keyboard_btn.pressed.connect(_on_keyboard_toggle_pressed)
		# Set initial button label based on current state
		_update_keyboard_button_label()
		
	KBMan.subscribe(_on_external_keyboard_change)
	

	# Connect to RunCmd for Intent Session updates
	var runcmd = get_node_or_null("runcmd")
	if runcmd:
		runcmd.intent_session_started.connect(_on_intent_session_started)
		if runcmd.is_intent_session:
			is_intent_session = true

	# Listen for controller hot-plugging
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	if OS.is_debug_build():
		_setup_debug_fps()
	
	# Start Update Checker
	_check_for_updates()

func _exit_tree():
	_thread_active = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	
	if tcp:
		tcp.disconnect_from_host()

func _thread_function():
	print("TCP Thread Started")
	# Initial connect
	reconnect_threaded()
	
	var buffer: PackedByteArray = PackedByteArray()
	
	while _thread_active:
		# check for reset request
		var do_reset = false
		if _mutex:
			_mutex.lock()
			do_reset = _reset_requested
			if do_reset:
				_reset_requested = false
			_mutex.unlock()
		
		if do_reset:
			if tcp:
				tcp.disconnect_from_host()
				tcp = null
			synched = false
			buffer.clear()
			last_message_time = 0
		
		# Connection Management
		if not (tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED):
			# Use call_deferred to update UI from thread
			loading.call_deferred("set_visible", true)
			
			if not tcp:
				if Time.get_ticks_msec() - last_message_time > RETRY_INTERVAL:
					print("reconnecting - random id %08x" % randi())
					reconnect_threaded()
			elif tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
				tcp.poll()
			else:
				# Reconnect logic for failed state
				if Time.get_ticks_msec() - last_message_time > RETRY_INTERVAL:
					reconnect_threaded()
		
		elif tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			# Loading spinner update
			loading.call_deferred("set_visible", false)
			
			# Send Input Queue
			_mutex.lock()
			var inputs = _input_queue.duplicate()
			_input_queue.clear()
			_mutex.unlock()
			
			for packet in inputs:
				tcp.put_data(packet)

			# Read Data
			var avail = tcp.get_available_bytes()
			if avail > 0:
				last_message_time = Time.get_ticks_msec()
				
				# If we have huge backlog, maybe we should skip?
				# But user asked to avoid skipping if possible. 
				# Let's try to just process everything fast.
				
				if not synched:
					var chunk = tcp.get_data(avail)
					if chunk[0] == OK:
						buffer.append_array(chunk[1])
						
						# Search for SYNC_SEQ
						var syncpoint = find_seq_pba(buffer, SYNC_SEQ_PBA)
						if syncpoint != -1:
							#print("Resync successful at index: ", syncpoint)
							if buffer.size() >= syncpoint + PACKLEN:
								var packet = buffer.slice(syncpoint, syncpoint + PACKLEN)
								_process_packet_thread(packet)
								buffer.clear() # Clear buffer completely
								synched = true
							else:
								# Keep enough buffer for next read
								if syncpoint > 0:
									buffer = buffer.slice(syncpoint)
						else:
							if buffer.size() > PACKLEN * 2:
								buffer = buffer.slice(PACKLEN) # Discard old garbage
				else:
					# Synched mode - Read frame by frame
					if avail >= PACKLEN:
						# Greedy read: If multiple frames are available, only render the latest one?
						# User asked: "can set_im_from_data be done in the new thread to maximze the refresh rate as soon as the data is available?"
						# But they also asked "avoid to skip frames like we do at line 257".
						# If we respect "avoid skipping", we must process ALL frames (rendering them one by one).
						# But if we process all frames, we might fall behind if rendering is slower than network.
						# However, updating texture is fast.
						# Let's try reading ALL available full frames in a loop
						var num_frames = int(avail / PACKLEN)
						for i in range(num_frames):
							var header_res = tcp.get_data(len(SYNC_SEQ) + CUSTOM_BYTE_COUNT)
							if header_res[0] == OK:
								var header_data = header_res[1]
								if header_data.slice(0, len(SYNC_SEQ)) == SYNC_SEQ_PBA:
									var pixel_res = tcp.get_data(DISPLAY_BYTES)
									if pixel_res[0] == OK:
										set_im_from_data_threaded(pixel_res[1])
								else:
									print("Sync lost! Entering resync mode.")
									synched = false
									buffer.append_array(header_data)
									break # Exit loop
							else:
								synched = false
								break
		
		# Check Timeout
		if last_message_time > 0 and (Time.get_ticks_msec() - last_message_time > READ_TIMEOUT):
			print("timeout detected")
			if tcp:
				tcp.disconnect_from_host()
				tcp = null
			synched = false
			buffer.clear()

		# Sleep to prevent burning CPU
		OS.delay_msec(1)

func reconnect_threaded():
	tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host(HOST, PORT)
	if err != OK:
		print("Failed to start connection. Error code: ", err)
	else:
		tcp.set_no_delay(true)
	last_message_time = Time.get_ticks_msec()

func _setup_debug_fps():
	debug_fps_label = Label.new()
	debug_fps_label.text = "FPS: WAIT"
	debug_fps_label.position = Vector2(40, 40)
	
	# High Visibility Overrides
	debug_fps_label.add_theme_color_override("font_color", Color(0, 1, 0, 1)) # Bright Green
	debug_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_fps_label.add_theme_constant_override("outline_size", 8)
	debug_fps_label.add_theme_font_size_override("font_size", 48) # Large text
	
	debug_fps_label.z_index = 4096
	
	# Add a canvas layer to ensure it stays on screen regardless of camera/zoom
	var cl = CanvasLayer.new()
	cl.layer = 128
	cl.add_child(debug_fps_label)
	add_child(cl)

func _on_joy_connection_changed(device: int, connected: bool):
	if connected:
		print("Controller connected: ", device)
		# Force hide Android keyboard to prevent input trapping
		DisplayServer.virtual_keyboard_hide()
		# Release any UI focus (like invisible text fields)
		get_viewport().gui_release_focus()
		
		var arranger = get_tree().root.get_node_or_null("Main/Arranger")
		if arranger:
			arranger.set_keyboard_active(false)
			arranger.update_controller_state()
	else:
		print("Controller disconnected: ", device)
		var arranger = get_tree().root.get_node_or_null("Main/Arranger")
		if arranger:
			arranger.update_controller_state()

func release_input_locks():
	print("Releasing Input Locks (Focus/Keyboard)")
	get_viewport().gui_release_focus()
	DisplayServer.virtual_keyboard_hide()

const SYNC_SEQ = [80, 73, 67, 79, 56, 83, 89, 78, 67, 95, 95] # "PICO8SYNC"
var SYNC_SEQ_PBA: PackedByteArray
const CUSTOM_BYTE_COUNT = 1
var current_custom_data := range(CUSTOM_BYTE_COUNT)
const DISPLAY_BYTES = 128 * 128 * 4
const PACKLEN = len(SYNC_SEQ) + CUSTOM_BYTE_COUNT + DISPLAY_BYTES

var _buffer_images: Array[Image] = []
var _write_head: int = 0
var fps_timer: float = 0.0
var fps_frame_count: int = 0
var fps_skip_count: int = 0
var debug_fps_label: Label = null

# Thread-safe image update
# Thread-safe image update using Ring Buffer (Triple Buffering)
func set_im_from_data_threaded(rgba: PackedByteArray):
	# Select next buffer
	var img = _buffer_images[_write_head]
	
	# Write data to it
	img.set_data(128, 128, false, Image.FORMAT_RGBA8, rgba)
	
	# Handover to Main Thread
	call_deferred("_update_texture", img)
	
	# Advance head (Ring Buffer 0 -> 1 -> 2 -> 0)
	_write_head = (_write_head + 1) % 3
	
	# Update FPS counter
	if _mutex:
		_mutex.lock()
		fps_frame_count += 1
		_mutex.unlock()

func _update_texture(rendering_image: Image):
	stream_texture.update(rendering_image)


func find_seq_pba(host: PackedByteArray, sub: PackedByteArray):
	# Optimized search for PackedByteArray
	var host_len = host.size()
	var sub_len = sub.size()
	if host_len < sub_len: return -1
	
	for i in range(host_len - sub_len + 1):
		# Quick check first byte
		if host[i] == sub[0]:
			if host.slice(i, i + sub_len) == sub:
				return i
	return -1
	
func find_seq(host: Array, sub: Array):
	for i in range(len(host) - len(sub) + 1):
		var success = true
		for j in range(len(sub)):
			if host[i + j] != sub[j]:
				success = false
				break
		if success:
			return i
	return -1

var last_mouse_state = [0, 0, 0]
var synched = false

func _process(delta: float) -> void:
	if debug_fps_label:
		fps_timer += delta
		if fps_timer >= 1.0:
			var current_frames = 0
			if _mutex:
				_mutex.lock()
				current_frames = fps_frame_count
				fps_frame_count = 0
				_mutex.unlock()
				
			debug_fps_label.text = "FPS: " + str(current_frames)
			fps_timer -= 1.0
			
	# Input polling and queueing
	var screen_pos: Vector2i = Vector2i.ZERO
	
	if input_mode == InputMode.MOUSE:
		screen_pos = current_screen_pos
		
		# Enforce cursor state
		if is_processing_input():
			if is_mouse_inside_display:
				if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
					Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
					Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			else:
				if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Trackpad Mode
		screen_pos = virtual_cursor_pos
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var current_mouse_state = [screen_pos.x, screen_pos.y, current_mouse_mask]
	if current_mouse_state != last_mouse_state:
		# Add to queue
		_mutex.lock()
		_input_queue.append([
			PIDOT_EVENT_MOUSEEV, current_mouse_state[0], current_mouse_state[1],
			current_mouse_state[2], 0, 0, 0, 0
		])
		_mutex.unlock()
		last_mouse_state = current_mouse_state


func _process_packet_thread(data: PackedByteArray):
	var im_start = len(SYNC_SEQ) + CUSTOM_BYTE_COUNT
	var im = data.slice(im_start, im_start + DISPLAY_BYTES)
	set_im_from_data_threaded(im)

const SDL_KEYMAP: Dictionary = preload("res://sdl_keymap.json").data

func send_key(id: int, down: bool, repeat: bool, mod: int):
	if _mutex:
		_mutex.lock()
		_input_queue.append([
			PIDOT_EVENT_KEYEV,
			id, int(down), int(repeat),
			mod & 0xff, (mod >> 8) & 0xff, 0, 0
		])
		_mutex.unlock()
			
func send_input(char: int):
	if _mutex:
		_mutex.lock()
		_input_queue.append([
			PIDOT_EVENT_CHAREV, char,
			0, 0, 0, 0, 0, 0
		])
		_mutex.unlock()

var quit_overlay: Control
# Controller Navigation
var btn_quit_yes: Button
var btn_quit_no: Button
var quit_focus_yes: bool = true

var held_keys = []


# Static variable to track haptic feedback state (default is false = haptic disabled)
static var haptic_enabled: bool = false

static func set_haptic_enabled(enabled: bool):
	haptic_enabled = enabled

static func get_haptic_enabled() -> bool:
	return haptic_enabled

static var swap_zx_enabled: bool = false
static func set_swap_zx_enabled(enabled: bool):
	swap_zx_enabled = enabled

static func get_swap_zx_enabled() -> bool:
	return swap_zx_enabled

enum InputMode {MOUSE, TRACKPAD}
static var input_mode: InputMode = InputMode.MOUSE


signal input_mode_changed(is_trackpad)

static func set_input_mode(trackpad: bool):
	input_mode = InputMode.TRACKPAD if trackpad else InputMode.MOUSE
	if instance:
		instance.input_mode_changed.emit(trackpad)


static func get_input_mode() -> InputMode:
	return input_mode

var virtual_cursor_pos: Vector2 = Vector2(64, 64)


static func is_system_landscape() -> bool:
	# Centralized check for landscape mode
	var size = DisplayServer.window_get_size()
	return size.x >= size.y


func vkb_setstate(id: String, down: bool, unicode: int = 0, echo = false):
	# INTENT SESSION EXIT (via specific button)
	# Must be checked BEFORE SDL_KEYMAP validation because "IntentExit" is not in the map!
	if id == "IntentExit":
		if down:
			if quit_overlay:
				quit_overlay.visible = true
				quit_focus_yes = true # Reset focus to "Yes"
				_update_quit_focus_visuals()
		return

	if id not in SDL_KEYMAP:
		return
	if (id not in held_keys) and not down:
		return
		
	if down:
		# CONTROLLER NAVIGATION for Quit Overlay
		if quit_overlay and quit_overlay.visible:
			if id == "Left":
				if quit_focus_yes:
					quit_focus_yes = false
					_update_quit_focus_visuals()
				return
			
			if id == "Right":
				if not quit_focus_yes:
					quit_focus_yes = true
					_update_quit_focus_visuals()
				return
			
			if id == "Z": # JoyButton A (Confirm)
				if quit_focus_yes:
					_quit_app()
				else:
					quit_overlay.visible = false
				return
				
			if id == "X": # JoyButton B (Cancel)
				quit_overlay.visible = false
				return
			
			# Block other inputs while overlay is open
			return
		
		# Add haptic feedback for key presses (only on key down, not key up)
		if not echo and haptic_enabled:
			Input.vibrate_handheld(35, 1)

		if id not in held_keys:
			held_keys.append(id)
			
		if input_mode == InputMode.TRACKPAD:
			if id == "X":
				_virtual_mouse_mask |= 1 # Left Click
				return
			if id == "Z":
				_virtual_mouse_mask |= 4 # Right Click (SDL Mask 4, Godot Middle Mask 4)
				return

		send_key(SDL_KEYMAP[id], true, echo, keys2sdlmod(held_keys))
		if unicode and unicode < 256:
			send_input(unicode)
	else:
		held_keys.erase(id)
		
		if input_mode == InputMode.TRACKPAD:
			if id == "X":
				_virtual_mouse_mask &= ~1
				return
			if id == "Z":
				_virtual_mouse_mask &= ~4
				return

		send_key(SDL_KEYMAP[id], false, false, keys2sdlmod(held_keys))
	

func keymod2sdl(mod: int, key: int) -> int:
	var ret = 0
	if mod & KEY_MASK_SHIFT or key == KEY_SHIFT:
		ret |= 0x0001
	if mod & KEY_MASK_CTRL or key == KEY_CTRL:
		ret |= 0x0040
	if mod & KEY_MASK_ALT or key == KEY_ALT:
		ret |= 0x0100
	return ret

func keys2sdlmod(keys: Array) -> int:
	var ret = 0
	for key in keys:
		if key == "Shift":
			ret |= 0x0001
		if key == "Ctrl":
			ret |= 0x0040
		if key == "Alt":
			ret |= 0x0100
	return ret

# Swipe detection variables
var touch_start_pos := Vector2.ZERO
var touch_last_pos := Vector2.ZERO

const SWIPE_DISTANCE_RATIO = 0.05 # Swipe must travel 5% of screen height
const SWIPE_EDGE_RATIO = 0.15 # Only trigger if starting from bottom 15%

# Trackpad refinements
static var trackpad_sensitivity: float = 0.3
static func set_trackpad_sensitivity(val: float):
	trackpad_sensitivity = val

static func get_trackpad_sensitivity() -> float:
	return trackpad_sensitivity

static var integer_scaling_enabled: bool = true
static func set_integer_scaling_enabled(enabled: bool):
	integer_scaling_enabled = enabled

static func get_integer_scaling_enabled() -> bool:
	return integer_scaling_enabled

static var always_show_controls: bool = false
static func set_always_show_controls(enabled: bool):
	always_show_controls = enabled
	
static func get_always_show_controls() -> bool:
	return always_show_controls


var current_screen_pos: Vector2i = Vector2i.ZERO
var current_mouse_mask: int = 0
var is_mouse_inside_display: bool = false

func _update_mouse_from_event(event_pos: Vector2):
	var local_pos = (
		(event_pos - displayContainer.global_position)
		/ displayContainer.global_scale
	)
	if displayContainer.centered:
		local_pos += Vector2(64, 64)
	current_screen_pos = local_pos
	
	# Update inside state for _process to handle
	is_mouse_inside_display = displayContainer.get_rect().has_point(displayContainer.to_local(event_pos))

const TAP_MAX_DURATION = 350 # ms
var _trackpad_click_pending = false
var _trackpad_tap_start_time = 0
var _trackpad_total_move = 0.0
var _virtual_mouse_mask: int = 0:
	set(value):
		_virtual_mouse_mask = value
		# Update mask immediately when virtual mask changes
		if input_mode == InputMode.TRACKPAD:
			current_mouse_mask = _virtual_mouse_mask

# Long press detection variables
var touch_down_time: int = 0
var is_touching: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start_pos = event.position
			touch_last_pos = event.position
			touch_down_time = Time.get_ticks_msec()
			is_touching = true
			
			# Tap-to-Dismiss Keyboard
			var kb_height = DisplayServer.virtual_keyboard_get_height()
			if kb_height > 0:
				var screen_height = get_viewport().get_visible_rect().size.y
				# If tap is above the keyboard area
				if event.position.y < (screen_height - kb_height):
					DisplayServer.virtual_keyboard_hide()
			
			if input_mode == InputMode.TRACKPAD:
				_trackpad_click_pending = true
				_trackpad_tap_start_time = touch_down_time
				_trackpad_total_move = 0.0
		else:
			is_touching = false
			_check_swipe(event.position)
			
			# Trackpad Tap Logic
			if input_mode == InputMode.TRACKPAD and _trackpad_click_pending:
				var duration = Time.get_ticks_msec() - _trackpad_tap_start_time
				if duration < TAP_MAX_DURATION:
					_send_trackpad_click()
				_trackpad_click_pending = false
	
	elif event is InputEventScreenDrag:
		if input_mode == InputMode.TRACKPAD:
			var delta = event.relative * trackpad_sensitivity
			# Scale delta if needed, for now 1:1 pixel movement
			virtual_cursor_pos += delta
			virtual_cursor_pos = virtual_cursor_pos.clamp(Vector2.ZERO, Vector2(127, 127))
			
			_trackpad_total_move += delta.length()
			if _trackpad_total_move > 15.0: # Relaxed from 5.0
				_trackpad_click_pending = false
			
	# Also accept Mouse Button for robustness (and Desktop testing)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if input_mode == InputMode.MOUSE:
			_update_mouse_from_event(event.position)
			
		if event.pressed:
			touch_start_pos = event.position
			touch_last_pos = event.position
			touch_down_time = Time.get_ticks_msec()
			is_touching = true
		else:
			is_touching = false
			_check_swipe(event.position)
	
	elif event is InputEventMouseMotion:
		if input_mode == InputMode.MOUSE:
			_update_mouse_from_event(event.position)
		elif input_mode == InputMode.TRACKPAD and is_touching:
			var delta = event.relative * trackpad_sensitivity
			virtual_cursor_pos += delta
			virtual_cursor_pos = virtual_cursor_pos.clamp(Vector2.ZERO, Vector2(127, 127))
			
			_trackpad_total_move += delta.length()
			if _trackpad_total_move > 15.0:
				_trackpad_click_pending = false

	# print(event)
	if event is InputEventKey:
		# because i keep doing this lolol
		if event.keycode == KEY_ALT:
			return
		var id = OS.get_keycode_string(event.keycode)
		if id in SDL_KEYMAP:
			send_key(SDL_KEYMAP[id], event.pressed, event.echo, keymod2sdl(event.get_modifiers_mask(), event.keycode if event.pressed else 0) | keys2sdlmod(held_keys))
		if event.unicode and event.unicode < 256 and event.pressed:
			send_input(event.unicode)
			
	elif event is InputEventMouseButton:
		if input_mode == InputMode.MOUSE:
			var mask = 0
			var g_mask = event.button_mask
			# Map Godot Mask to SDL Mask
			if g_mask & MOUSE_BUTTON_MASK_LEFT: mask |= 1
			if g_mask & MOUSE_BUTTON_MASK_MIDDLE: mask |= 2
			if g_mask & MOUSE_BUTTON_MASK_RIGHT: mask |= 4
			current_mouse_mask = mask

	elif event is InputEventJoypadButton:
		# Check ignore list
		if event.device >= 0:
			var joy_name = Input.get_joy_name(event.device).to_lower()
			if joy_name in ControllerUtils.ignored_devices_by_user:
				return

		if input_mode == InputMode.TRACKPAD:
			# Controller Mouse Click Mapping
			# Map PICO-8 O (A/Y) -> Right Click (Mask 4)
			if event.button_index == JoyButton.JOY_BUTTON_A or event.button_index == JoyButton.JOY_BUTTON_Y:
				if event.pressed:
					_virtual_mouse_mask |= 4
				else:
					_virtual_mouse_mask &= ~4
				return # Consume
				
			# Map PICO-8 X (B/X) -> Left Click (Mask 1)
			if event.button_index == JoyButton.JOY_BUTTON_B or event.button_index == JoyButton.JOY_BUTTON_X:
				if event.pressed:
					_virtual_mouse_mask |= 1
				else:
					_virtual_mouse_mask &= ~1
				return # Consume
				
		var key_id = ""
		match event.button_index:
			JoyButton.JOY_BUTTON_A, JoyButton.JOY_BUTTON_Y: key_id = "X" if swap_zx_enabled else "Z" # Pico-8 O (or X if swapped)
			JoyButton.JOY_BUTTON_B, JoyButton.JOY_BUTTON_X: key_id = "Z" if swap_zx_enabled else "X" # Pico-8 X (or O if swapped)
			JoyButton.JOY_BUTTON_START, JoyButton.JOY_BUTTON_RIGHT_SHOULDER: key_id = "P" # Pause
			JoyButton.JOY_BUTTON_BACK, JoyButton.JOY_BUTTON_GUIDE:
				key_id = "IntentExit" if is_intent_session else "Escape" # Menu / Exit
			JoyButton.JOY_BUTTON_DPAD_UP: key_id = "Up"
			JoyButton.JOY_BUTTON_DPAD_DOWN: key_id = "Down"
			JoyButton.JOY_BUTTON_DPAD_LEFT: key_id = "Left"
			JoyButton.JOY_BUTTON_DPAD_RIGHT: key_id = "Right"
			JoyButton.JOY_BUTTON_LEFT_SHOULDER:
				if event.pressed:
					_toggle_options_menu()
		
		if key_id != "":
			# Only send if state actually changed to avoid spam if logic elsewhere was flawed
			# But JoypadButton events are discreet, so straight pass-through is fine.
			# We check held_keys to avoid repeat send if Godot sends duplicate events (which it shouldn't for buttons)
			# but vkb_setstate sends anyway. 
			# For buttons, we trust the event.pressed state.
			vkb_setstate(key_id, event.pressed)

	elif event is InputEventJoypadMotion:
		# Check ignore list
		if event.device >= 0:
			var joy_name = Input.get_joy_name(event.device).to_lower()
			if joy_name in ControllerUtils.ignored_devices_by_user:
				return

		var axis_threshold = 0.5
		# Handle Left Stick X (Left/Right)
		if event.axis == JoyAxis.JOY_AXIS_LEFT_X:
			if event.axis_value < -axis_threshold:
				if "Left" not in held_keys: vkb_setstate("Left", true)
			else:
				if "Left" in held_keys: vkb_setstate("Left", false)

			if event.axis_value > axis_threshold:
				if "Right" not in held_keys: vkb_setstate("Right", true)
			else:
				if "Right" in held_keys: vkb_setstate("Right", false)
		
		# Handle Left Stick Y (Up/Down)
		elif event.axis == JoyAxis.JOY_AXIS_LEFT_Y:
			if event.axis_value < -axis_threshold:
				if "Up" not in held_keys: vkb_setstate("Up", true)
			else:
				if "Up" in held_keys: vkb_setstate("Up", false)

			if event.axis_value > axis_threshold:
				if "Down" not in held_keys: vkb_setstate("Down", true)
			else:
				if "Down" in held_keys: vkb_setstate("Down", false)
		

	#if not (tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		#return;
	#if event is InputEventMouse:
		#queued_mouse_event = true

# Callback function for keyboard toggle button
func _on_keyboard_toggle_pressed():
	var current_state = KBMan.get_current_keyboard_type()
	var new_state = KBMan.KBType.FULL if current_state == KBMan.KBType.GAMING else KBMan.KBType.GAMING
	KBMan.set_full_keyboard_enabled(new_state == KBMan.KBType.FULL)
	# Label update is handled by observer

func _on_external_keyboard_change(_enabled: bool):
	_update_keyboard_button_label()

func _update_keyboard_button_label():
	var keyboard_btn = get_node("Arranger/kbanchor/HBoxContainer/Keyboard Btn")
	if not keyboard_btn:
		return
	var current_type = KBMan.get_current_keyboard_type()
	keyboard_btn.text = "fULL kEYBOARD" if current_type == KBMan.KBType.GAMING else "gAMING kEYBOARD"


func _check_swipe(end_pos: Vector2):
	# Check if start pos is at the bottom of the screen
	var screen_height = get_viewport().get_visible_rect().size.y
	if touch_start_pos.y < (screen_height * (1.0 - SWIPE_EDGE_RATIO)):
		return

	var direction = touch_start_pos - end_pos
	
	var threshold_pixels = screen_height * SWIPE_DISTANCE_RATIO
	
	# Up means start.y > end.y (screen coords, y increases downwards) -> direction.y > 0
	if direction.y > threshold_pixels:
		# Ensure it's mostly vertical (horizontal movement is less than vertical movement)
		if abs(direction.x) < direction.y:
			_trigger_keyboard()

func _trigger_keyboard():
	# Show Android Keyboard
	DisplayServer.virtual_keyboard_show('')
	
# Update Checker
func _check_for_updates():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	var current_time = Time.get_unix_time_from_system()
	
	# 1. First Run Check
	# If the "updates" section doesn't exist, this is likely the first run (or first run with this feature).
	# We skip the check to not annoy the user immediately after install.
	if err != OK or not config.has_section("updates"):
		print("First run detected (or config missing). Skipping update check.")
		config.set_value("updates", "last_check", current_time)
		config.save("user://settings.cfg")
		return
		
	var last_check = config.get_value("updates", "last_check", 0)
	
	# 2. Daily Frequency Check (86400 seconds)
	if (current_time - last_check) < 86400:
		print("Skipping update check (checked recently)")
		return
	
	# 3. Internet Connectivity Check (Simple)
	# IP.resolve_hostname returns an empty string/IP if failed? 
	# Actually blocking resolve might freeze main thread. 
	# Best way is to rely on HTTPRequest failure, but request "no check if no internet".
	# We can check if we have a valid IP interface.
	var has_network = false
	for iface in IP.get_local_interfaces():
		# identifying valid non-localhost interface
		if iface.friendly != "lo" and iface.addresses.size() > 0:
			has_network = true
			break
			
	if not has_network:
		print("No active network interface. Skipping update check.")
		return
		
	print("Checking for updates...")
	
	# Update check time immediately
	config.set_value("updates", "last_check", current_time)
	config.save("user://settings.cfg")
	
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_update_request_completed.bind(http))
	http.request("https://api.github.com/repos/Macs75/pico8-android/releases/latest")

func _on_update_request_completed(result, response_code, headers, body, http_node):
	http_node.queue_free()
	
	if response_code != 200:
		print("Update check failed. Response code: ", response_code)
		return
		
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	if error != OK:
		print("JSON Parse Error: ", json.get_error_message())
		return
		
	var data = json.data
	if not data.has("tag_name"):
		print("Invalid JSON response (no tag_name)")
		return
		
	var remote_tag = data["tag_name"] # e.g. "v0.0.8"
	var current_version = ProjectSettings.get_setting("application/config/version")
	if not current_version:
		current_version = "0.0.0"
	
	print("Update Check: Local v", current_version, " vs Remote ", remote_tag)
	
	# Compare versions (Simple string compare or more complex semantic check)
	# Assuming remote_tag starts with "v", strip it
	var remote_ver_str = remote_tag.replace("v", "")
	
	if _is_version_newer(current_version, remote_ver_str):
		# Check ignore list
		var config = ConfigFile.new()
		config.load("user://settings.cfg")
		var ignored = config.get_value("updates", "ignored_tag", "")
		
		# Reset ignore if a NEWER update comes out (different tag)
		if ignored != "" and ignored != remote_tag:
			config.set_value("updates", "ignored_tag", "")
			config.save("user://settings.cfg")
			ignored = ""
		
		if ignored == remote_tag:
			print("Update ", remote_tag, " is ignored by user.")
			return
			
		print("New update found!")
		call_deferred("_show_update_dialog", remote_tag, data.get("html_url", ""))

func _is_version_newer(current: String, remote: String) -> bool:
	var v_curr = current.split(".")
	var v_remote = remote.split(".")
	
	for i in range(min(v_curr.size(), v_remote.size())):
		if int(v_remote[i]) > int(v_curr[i]):
			return true
		if int(v_remote[i]) < int(v_curr[i]):
			return false
			
	# If equal so far, longer one is newer? (e.g. 1.0.1 > 1.0)
	return v_remote.size() > v_curr.size()

func _show_update_dialog(tag: String, url: String):
	PicoVideoStreamer.instance.set_process_unhandled_input(false)
	PicoVideoStreamer.instance.set_process_input(false)
	
	var dialog = load("res://update_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.setup(tag, url)
	
	dialog.closed.connect(func():
		PicoVideoStreamer.instance.set_process_unhandled_input(true)
		PicoVideoStreamer.instance.set_process_input(true)
	)

	if haptic_enabled:
		Input.vibrate_handheld(50)

func _send_trackpad_click():
	var screen_pos = Vector2i(virtual_cursor_pos)
	# DOWN
	var down_state = [screen_pos.x, screen_pos.y, 1] # 1 = Left Click
	if _mutex:
		_mutex.lock()
		_input_queue.append([PIDOT_EVENT_MOUSEEV, down_state[0], down_state[1], down_state[2], 0, 0, 0, 0])
		# UP
		var up_state = [screen_pos.x, screen_pos.y, 0]
		_input_queue.append([PIDOT_EVENT_MOUSEEV, up_state[0], up_state[1], up_state[2], 0, 0, 0, 0])
		_mutex.unlock()
		last_mouse_state = up_state
	
func _quit_app():
	get_tree().quit()

func _setup_quit_overlay():
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)
	
	quit_overlay = Control.new()
	quit_overlay.name = "QuitOverlay"
	quit_overlay.visible = false
	quit_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(quit_overlay)
	

	# Dimmer
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # Block input
	quit_overlay.add_child(bg)
	
	# Robust Centering Container
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quit_overlay.add_child(center_container)
	
	# Panel
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = Color(1, 1, 1, 1)
	style.expand_margin_top = 10
	style.expand_margin_bottom = 10
	style.expand_margin_left = 10
	style.expand_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	center_container.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	# Add padding around the VBox content
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	margin_container.add_theme_constant_override("margin_left", 40)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_child(vbox)
	panel.add_child(margin_container)
	
	# Font setup
	var font = load("res://assets/font/atlas-0.png")
	
	# Calculate dynamic font size (5% of screen height, clamped)
	var screen_size = get_viewport().get_visible_rect().size
	var dynamic_font_size = 32 # Default fallback
	if screen_size.y > 0:
		dynamic_font_size = clamp(int(min(screen_size.x, screen_size.y) * 0.04), 16, 64)
	
	var label = Label.new()
	label.text = "RETURN TO LAUNCHER?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD # Enable wrap for small screens
	if font:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", dynamic_font_size)
	vbox.add_child(label)
	
	# Constraint width to 80% of screen
	if screen_size.x > 0:
		panel.custom_minimum_size.x = min(600, screen_size.x * 0.8)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", int(dynamic_font_size * 1.25))
	vbox.add_child(hbox)
	
	var btn_cancel = _create_pixel_button("NO", font, dynamic_font_size)
	btn_cancel.pressed.connect(func(): quit_overlay.visible = false)
	hbox.add_child(btn_cancel)
	btn_quit_no = btn_cancel
	
	var btn_quit = _create_pixel_button("YES", font, dynamic_font_size)
	btn_quit.pressed.connect(_quit_app)
	hbox.add_child(btn_quit)
	btn_quit_yes = btn_quit
	
	_update_quit_focus_visuals()

func _toggle_options_menu():
	var menu = get_node_or_null("OptionsMenu")
	if menu:
		if menu.is_open:
			menu.close_menu()
		else:
			menu.open_menu()

func _update_quit_focus_visuals():
	if not btn_quit_yes or not btn_quit_no: return
	
	# Focus Color (Redish)
	var col_focus = Color(1, 0.2, 0.4, 1)
	# Normal Color (Dark Blue)
	var col_normal = Color(0.2, 0.2, 0.3, 1)
	
	var style_yes = btn_quit_yes.get_theme_stylebox("normal")
	if style_yes is StyleBoxFlat:
		style_yes.bg_color = col_focus if quit_focus_yes else col_normal
		
	var style_no = btn_quit_no.get_theme_stylebox("normal")
	if style_no is StyleBoxFlat:
		style_no.bg_color = col_focus if not quit_focus_yes else col_normal


func _create_pixel_button(text, font, size = 32) -> Button:
	var btn = Button.new()
	btn.text = text
	if font:
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", size)
	
	# Minimal style for pixel art look
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.2, 0.3, 1)
	
	# Dynamic Padding: Slim vertical, Wide horizontal
	var pad_v = int(size * 0.2)
	var pad_h = int(size * 0.8)
	
	style_normal.content_margin_top = pad_v
	style_normal.content_margin_bottom = pad_v
	style_normal.content_margin_left = pad_h
	style_normal.content_margin_right = pad_h
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 0.2, 0.4, 1) # Pico-8 Redish
	style_pressed.content_margin_top = pad_v
	style_pressed.content_margin_bottom = pad_v
	style_pressed.content_margin_left = pad_h
	style_pressed.content_margin_right = pad_h
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_normal)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_normal)
	
	return btn
