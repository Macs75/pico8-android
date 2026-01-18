extends Node2D
class_name PicoVideoStreamer

@export var loading: AnimatedSprite2D
@export var display: Sprite2D
@export var displayContainer: Sprite2D

var HOST = "192.168.0.42" if Engine.is_embedded_in_editor() else "127.0.0.1"
var PORT = 18080

var tcp: StreamPeerTCP

const PIDOT_EVENT_MOUSEEV = 1;
const PIDOT_EVENT_KEYEV = 2;
const PIDOT_EVENT_CHAREV = 3;

var last_message_time: int = 0
const RETRY_INTERVAL: int = 200
const READ_TIMEOUT: int = 5000
func reconnect():
	tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host(HOST, PORT)
	if err != OK:
		print("Failed to start connection. Error code: ", err)
	last_message_time = Time.get_ticks_msec()

func hard_reset_connection():
	print("Forcing Hard TCP Reset...")
	if tcp:
		tcp.disconnect_from_host()
		tcp = null
	synched = false
	last_message_time = 0 # Forces immediate reconnect in _process

static var instance: PicoVideoStreamer
func _ready() -> void:
	instance = self
	set_process_input(true)
	
	instance = self
	set_process_input(true)
	
	_setup_quit_overlay()
	
	# Try to start TCP connection
	reconnect()
	
	# Connect the single keyboard toggle button
	var keyboard_btn = get_node("Arranger/kbanchor/HBoxContainer/Keyboard Btn")
	if keyboard_btn:
		keyboard_btn.pressed.connect(_on_keyboard_toggle_pressed)
		# Set initial button label based on current state
		_update_keyboard_button_label()
		
	KBMan.subscribe(_on_external_keyboard_change)
	

	# Listen for controller hot-plugging
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

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

var buffer := []
const SYNC_SEQ = [80, 73, 67, 79, 56, 83, 89, 78, 67] # "PICO8SYNC"
const CUSTOM_BYTE_COUNT = 1
var current_custom_data := range(CUSTOM_BYTE_COUNT)
const DISPLAY_BYTES = 128 * 128 * 3
const PACKLEN = len(SYNC_SEQ) + CUSTOM_BYTE_COUNT + DISPLAY_BYTES

func set_im_from_data(rgb: Array):
	#var rgb = []
	#for i in range(len(xrgb)*0.75):
		#var reali = (2 - (i % 3)) + floor(i/3)*4
		#rgb.append(xrgb[reali])
	var image = Image.create_from_data(128, 128, false, Image.FORMAT_RGB8, rgb)
	
	if display.texture and display.texture is ImageTexture:
		(display.texture as ImageTexture).set_image(image)
	else:
		var texture = ImageTexture.create_from_image(image)
		display.texture = texture

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
	#print("status :", current_custom_data[0])
	if not (tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		loading.visible = true
	if not tcp:
		if Time.get_ticks_msec() - last_message_time > RETRY_INTERVAL:
			print("reconnecting - random id %08x" % randi())
			reconnect()
		return
	if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		tcp.poll()
	elif tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var screen_pos: Vector2i = Vector2i.ZERO
		
		if input_mode == InputMode.MOUSE:
			var local_pos = (
				(get_viewport().get_mouse_position()
				- displayContainer.global_position)
				/ displayContainer.global_scale
			)
			if displayContainer.centered:
				local_pos += Vector2(64, 64)
			screen_pos = local_pos
			
			# Hide cursor logic
			if is_processing_input():
				var is_inside = displayContainer.get_rect().has_point(displayContainer.to_local(get_global_mouse_position()))
				
				if is_inside:
					if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
						# Change shape to HAND while hiding, so the switch back to ARROW causes a refresh
						Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
						Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
				else:
					if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
						Input.set_default_cursor_shape(Input.CURSOR_ARROW)
						Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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

		var mask = 0
		if input_mode == InputMode.MOUSE:
			var g_mask = Input.get_mouse_button_mask()
			# Map Godot Mask to SDL Mask
			if g_mask & MOUSE_BUTTON_MASK_LEFT: mask |= 1
			if g_mask & MOUSE_BUTTON_MASK_MIDDLE: mask |= 2 # SDL Middle is 2
			if g_mask & MOUSE_BUTTON_MASK_RIGHT: mask |= 4 # SDL Right is 4
		else:
			# Trackpad Mode: Combine virtual mask (controller/touch buttons)
			mask |= _virtual_mouse_mask
			
		var current_mouse_state = [screen_pos.x, screen_pos.y, mask]
		if current_mouse_state != last_mouse_state:
			# and 
			tcp.put_data([
				PIDOT_EVENT_MOUSEEV, current_mouse_state[0], current_mouse_state[1],
				current_mouse_state[2], 0, 0, 0, 0
			])
			last_mouse_state = current_mouse_state
		# recv screen
		if tcp.get_available_bytes() > 0:
			last_message_time = Time.get_ticks_msec()
			var errdata = tcp.get_data(tcp.get_available_bytes())
			var err = errdata[0]
			var data = errdata[1]
			buffer.append_array(data)
			if len(buffer) > PACKLEN * 2:
				#print("buffer overloaded, skipping")
				var chopCount = floor((len(buffer) / PACKLEN)) - 1
				#print(chopCount)
				buffer = buffer.slice(chopCount * PACKLEN)
			if synched and len(buffer) > len(SYNC_SEQ) and buffer.slice(0, len(SYNC_SEQ)) != SYNC_SEQ:
				print("synch fail", buffer.slice(0, len(SYNC_SEQ)), SYNC_SEQ)
				synched = false
			if not synched:
				print("resynching")
				var syncpoint = find_seq(buffer, SYNC_SEQ)
				buffer = buffer.slice(syncpoint)
				synched = true
			var im
			if len(buffer) >= PACKLEN:
				current_custom_data = buffer.slice(
					len(SYNC_SEQ),
					len(SYNC_SEQ) + CUSTOM_BYTE_COUNT
				)
				im = buffer.slice(
					len(SYNC_SEQ) + CUSTOM_BYTE_COUNT,
					len(SYNC_SEQ) + CUSTOM_BYTE_COUNT + DISPLAY_BYTES
				)
				buffer = buffer.slice(PACKLEN)
			if im != null:
				#if find_seq(im, SYNC_SEQ) != -1:
					#print("image has sync ", find_seq(im, SYNC_SEQ))
					#print(im)
					#DisplayServer.clipboard_set(str(im))
					#breakpoint
				loading.visible = false
				set_im_from_data(im)
		elif Time.get_ticks_msec() - last_message_time > READ_TIMEOUT:
			print("timeout detected")
			reconnect()
	else:
		print("connection failed, status: ", tcp.get_status())
		tcp = null
		
const SDL_KEYMAP: Dictionary = preload("res://sdl_keymap.json").data

func send_key(id: int, down: bool, repeat: bool, mod: int):
	if tcp:
		print("sending key ", id, " as ", down)
		tcp.put_data([
			PIDOT_EVENT_KEYEV,
			id, int(down), int(repeat),
			mod & 0xff, (mod >> 8) & 0xff, 0, 0
		])
func send_input(char: int):
	if tcp:
		tcp.put_data([
			PIDOT_EVENT_CHAREV, char,
			0, 0, 0, 0, 0, 0
		])

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
static var trackpad_sensitivity: float = 0.5
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

const TAP_MAX_DURATION = 350 # ms
var _trackpad_click_pending = false
var _trackpad_tap_start_time = 0
var _trackpad_total_move = 0.0
var _virtual_mouse_mask: int = 0

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
		if event.pressed:
			touch_start_pos = event.position
			touch_last_pos = event.position
			touch_down_time = Time.get_ticks_msec()
			is_touching = true
		else:
			is_touching = false
			_check_swipe(event.position)
	
	elif event is InputEventMouseMotion:
		if input_mode == InputMode.TRACKPAD and is_touching:
			var delta = event.relative * trackpad_sensitivity
			virtual_cursor_pos += delta
			virtual_cursor_pos = virtual_cursor_pos.clamp(Vector2.ZERO, Vector2(127, 127))
			
			_trackpad_total_move += delta.length()
			if _trackpad_total_move > 15.0:
				_trackpad_click_pending = false

	#print(event)
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
		pass

	elif event is InputEventJoypadButton:
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
			JoyButton.JOY_BUTTON_A, JoyButton.JOY_BUTTON_Y: key_id = "Z" # Pico-8 O
			JoyButton.JOY_BUTTON_B, JoyButton.JOY_BUTTON_X: key_id = "X" # Pico-8 X
			JoyButton.JOY_BUTTON_START: key_id = "P" # Pause
			JoyButton.JOY_BUTTON_BACK, JoyButton.JOY_BUTTON_GUIDE: key_id = "Escape" # Menu
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
	
	# Notify arranger to shift screen
	var arranger = get_tree().root.get_node_or_null("Main/Arranger")
	if arranger:
		arranger.set_keyboard_active(true)
		
	if haptic_enabled:
		Input.vibrate_handheld(50)

func _send_trackpad_click():
	var screen_pos = Vector2i(virtual_cursor_pos)
	# DOWN
	var down_state = [screen_pos.x, screen_pos.y, 1] # 1 = Left Click
	if tcp:
		tcp.put_data([PIDOT_EVENT_MOUSEEV, down_state[0], down_state[1], down_state[2], 0, 0, 0, 0])
	
	# UP
	var up_state = [screen_pos.x, screen_pos.y, 0]
	if tcp:
		tcp.put_data([PIDOT_EVENT_MOUSEEV, up_state[0], up_state[1], up_state[2], 0, 0, 0, 0])
	
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
	
	var label = Label.new()
	label.text = "RETURN TO LAUNCHER?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 48) # Increased to 48
	vbox.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	vbox.add_child(hbox)
	
	var btn_cancel = _create_pixel_button("NO", font)
	btn_cancel.pressed.connect(func(): quit_overlay.visible = false)
	hbox.add_child(btn_cancel)
	btn_quit_no = btn_cancel
	
	var btn_quit = _create_pixel_button("YES", font)
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

func _create_pixel_button(text, font) -> Button:
	var btn = Button.new()
	btn.text = text
	# Minimal style for pixel art look
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.2, 0.3, 1)
	style_normal.set_content_margin_all(20) # Increased padding
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 0.2, 0.4, 1) # Pico-8 Redish
	style_pressed.set_content_margin_all(20) # Increased padding
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_normal)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	if font:
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 48) # Increased to 48
	return btn
