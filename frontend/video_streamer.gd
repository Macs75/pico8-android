extends Node2D
class_name PicoVideoStreamer


signal layout_reset(is_landscape: bool)
signal control_selected(control: CanvasItem)
signal bezel_layout_updated(bezel_rect: Rect2, scale: Vector2)

@export var loading: AnimatedSprite2D
@export var display: Sprite2D
@export var displayContainer: Sprite2D

var PIPE_VID = PicoBootManager.APPDATA_FOLDER + "/package/tmp/pico8.vid"
var PIPE_IN = PicoBootManager.APPDATA_FOLDER + "/package/tmp/pico8.in"

# Pipe Handles
var vid_pipe_id: int = -1
var in_pipe_id: int = -1
var _applinks_plugin = null

const TOTAL_PACKET_SIZE = 11 + 1 + (128 * 128 * 4)

# TCP Threading
var _thread: Thread
var _mutex: Mutex
var _thread_active: bool = false
var _reset_requested: bool = false
var _input_queue: Array = []
var _main_thread_input_buffer: Array = []
var _pipe_reset_complete: bool = true
var _connection_allowed: bool = false

const PIDOT_EVENT_MOUSEEV = 1;
const PIDOT_EVENT_KEYEV = 2;
const PIDOT_EVENT_CHAREV = 3;

var stream_texture: ImageTexture

var last_message_time: int = 0
const RETRY_INTERVAL: int = 200
const READ_TIMEOUT: int = 5000
var is_intent_session: bool = false
var is_pico_suspended: bool = false # Track if PICO-8 process is suspended

var selected_control: CanvasItem = null
func _on_intent_session_started():
	print("Video Streamer: Intent Session Started (Controller Mapping Updated)")
	is_intent_session = true

func hard_reset_connection():
	print("Forcing Hard TCP Reset...")
	# Signal the thread to reset the connection
	if _mutex:
		_mutex.lock()
		_reset_requested = true
		_pipe_reset_complete = false
		_mutex.unlock()

func hold_connection():
	print("Holding connection attempts...")
	if _mutex:
		_mutex.lock()
		_reset_requested = true
		_pipe_reset_complete = false
		_connection_allowed = false
		_mutex.unlock()

func allow_connection():
	print("Releasing connection hold...")
	if _mutex:
		_mutex.lock()
		_connection_allowed = true
		_mutex.unlock()

func is_pipe_reset_complete() -> bool:
	var ret = false
	if _mutex:
		_mutex.lock()
		ret = _pipe_reset_complete
		_mutex.unlock()
	return ret

static var instance: PicoVideoStreamer

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	set_process_input(true)
	
	# Apply saved orientation immediately
	apply_orientation()
	
	# Apply shader if it was set before instance was ready
	if current_shader_type != ShaderType.NONE:
		set_shader_type(current_shader_type)
	
	_setup_quit_overlay()
	
	if Engine.has_singleton("applinks"):
		_applinks_plugin = Engine.get_singleton("applinks")
		print("Video Streamer: Applinks Plugin Found")
	else:
		print("Video Streamer: Applinks Plugin NOT FOUND (Critical for Pipes)")

	# Pre-calculate PackedByteArray for fast sync check
	SYNC_SEQ_PBA = PackedByteArray(SYNC_SEQ)
	
	# Pre-allocate texture for performance (Triple Buffering)
	for i in range(3):
		var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		_buffer_images.append(img)
		
	stream_texture = ImageTexture.create_from_image(_buffer_images[0])
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = stream_texture
	
	# Initialize Bezel Overlay (Custom)
	# Defer this to ensure scene tree is fully ready or call directly
	print("Video Streamer: Setting up Bezel Overlay...")
	_setup_bezel_overlay()


	# Start TCP Thread
	_mutex = Mutex.new()
	_thread = Thread.new()
	_thread_active = true
	_thread.start(_thread_function)
	
	# Connect the single keyboard toggle button
	var keyboard_btn = get_node("Arranger/kbanchor/Keyboard Btn")
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

	# Connect to Arranger layout updates for Bezel Sync
	var arranger = get_node_or_null("Arranger")
	if arranger:
		if not arranger.layout_updated.is_connected(_on_viewport_size_changed):
			arranger.layout_updated.connect(_on_viewport_size_changed)

	if OS.is_debug_build():
		_setup_debug_fps()
	
	# Start Update Checker
	_check_for_updates()

	# Start Audio Streamer
	var audio_backend = PicoBootManager.get_audio_backend()

	if audio_backend != "sles":
		var audio_streamer_script = load("res://audio_streamer.gd")
		if audio_streamer_script:
			var audio_streamer = audio_streamer_script.new()
			add_child(audio_streamer)

	# Run Activity Log Analyzer
	# We run this deferred to not block startup if the log is huge
	print("Video Streamer: Queuing Activity Log Analysis...")
	var analyzer = load("res://activity_log_analyzer.gd")
	if analyzer:
		analyzer.call_deferred("perform_analysis")

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_options_menu()


func _exit_tree():
	_thread_active = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	
	if metrics_logging_enabled:
		_flush_logs()
		if metrics_file:
			metrics_file.close()

# Shader Externalization: Load shaders with .custom file priority
func load_external_shader(shader_name: String) -> Shader:
	var shader_dir = PicoBootManager.PUBLIC_FOLDER + "/shaders/"
	var builtin_path = "res://shaders/" + shader_name
	
	# Priority order:
	# 1. shader_name.custom.gdshader (user's custom version)
	# 2. shader_name.gdshader (base version in public folder)
	# 3. res://shaders/shader_name.gdshader (builtin fallback)
	
	var custom_name = shader_name.replace(".gdshader", ".custom.gdshader")
	var paths_to_try = [
		shader_dir + custom_name, # User custom version
		shader_dir + shader_name # Base external version
	]
	
	for external_path in paths_to_try:
		if FileAccess.file_exists(external_path):
			var shader_file = FileAccess.open(external_path, FileAccess.READ)
			if shader_file:
				var shader_code = shader_file.get_as_text()
				shader_file.close()
				
				var shader = Shader.new()
				shader.code = shader_code
				
				var is_custom = external_path.ends_with(".custom.gdshader")
				print("✓ Loaded ", "custom" if is_custom else "external", " shader: ", external_path.get_file())
				return shader
	# Fallback to builtin (no error notification, this is normal)
	print("Using builtin shader: ", shader_name)
	return load(builtin_path)

func _thread_function():
	print("Video Streamer: Pipe Thread Initiated")
	# Small initial delay to let shell script finish mkfifo
	OS.delay_msec(100)
		
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
			synched = false
			buffer.clear()
			
			# Force clean reconnection of pipes (fixes Restart with FIFO)
			if _applinks_plugin:
				if vid_pipe_id != -1:
					print("Pipe: Hard Reset - Closing Video Pipe")
					_applinks_plugin.pipe_close(vid_pipe_id)
					vid_pipe_id = -1
				
					print("Pipe: Hard Reset - Closing Input Pipe")
					_applinks_plugin.pipe_close(in_pipe_id)
					in_pipe_id = -1
			
			if _mutex:
				_mutex.lock()
				_pipe_reset_complete = true
				_mutex.unlock()
		
		var can_connect = true
		if _mutex:
			_mutex.lock()
			can_connect = _connection_allowed
			_mutex.unlock()
			
		if not can_connect:
			OS.delay_msec(50)
			continue
		
		# Connection Management (Open Pipes)
		if vid_pipe_id == -1 or in_pipe_id == -1:
			loading.call_deferred("set_visible", true)
			
			if _applinks_plugin:
				# PLUGIN MODE (Native Blocking I/O)
				# Input Pipe
				if in_pipe_id == -1:
					# Try Open (Blocking likely short if Shim opened it eager)
					print("Pipe: Attempting to connect to Input Pipe...")
					
					var pid = -1
					# Double check validity inside thread loop
					if is_instance_valid(_applinks_plugin) and _applinks_plugin:
						pid = _applinks_plugin.pipe_open(PIPE_IN, 1) # Mode 1 = WRITE
					else:
						# Plugin lost?
						_thread_active = false
						break
						
					if pid != -1:
						in_pipe_id = pid
						print("Pipe: Connected to Input Pipe (ID: ", pid, ")")
					else:
						# Open failed (not found?)
						print("Pipe: Input Pipe connection failed, retrying...")
						OS.delay_msec(500)

				# Video Pipe
				if vid_pipe_id == -1:
					print("Pipe: Attempting to connect to Video Pipe...")
					var pid = -1
					if is_instance_valid(_applinks_plugin) and _applinks_plugin:
						pid = _applinks_plugin.pipe_open(PIPE_VID, 0) # Mode 0 = READ
					else:
						_thread_active = false
						break
					
					if pid != -1:
						vid_pipe_id = pid
						print("Pipe: Connected to Video Pipe (ID: ", pid, ")")
					else:
						# Open failed
						print("Pipe: Video Pipe connection failed/blocked, retrying...")
						OS.delay_msec(500)
			
			# Check connection status
			var pipes_connected = (vid_pipe_id != -1 and in_pipe_id != -1)
			
			if not pipes_connected:
				continue
		
		# Connected
		loading.call_deferred("set_visible", false)
		
		# 1. Send Inputs
		_mutex.lock()
		var inputs = _input_queue.duplicate()
		_input_queue.clear()
		_mutex.unlock()
		
		if inputs.size() > 0:
			for packet in inputs:
				var pba = PackedByteArray(packet)
				if _applinks_plugin:
					_applinks_plugin.pipe_write(in_pipe_id, pba)
			
		# 2. Read Video
		var chunk: PackedByteArray
		if _applinks_plugin:
			chunk = _applinks_plugin.pipe_read(vid_pipe_id, TOTAL_PACKET_SIZE)

		if chunk.size() > 0:
			buffer.append_array(chunk)
			
			# Header Sync Check
			if not synched:
				var syncpoint = find_seq_pba(buffer, SYNC_SEQ_PBA)
				if syncpoint != -1:
					if buffer.size() >= syncpoint + TOTAL_PACKET_SIZE:
						var packet = buffer.slice(syncpoint, syncpoint + TOTAL_PACKET_SIZE)
						_process_packet_thread(packet)
						buffer = buffer.slice(syncpoint + TOTAL_PACKET_SIZE)
						synched = true
					else:
						# Found sync point but packet is incomplete, wait for more data
						if syncpoint > 0:
							buffer = buffer.slice(syncpoint)
				else:
					# No sync point in current buffer
					if buffer.size() > TOTAL_PACKET_SIZE * 2:
						# Buffer is too large and no sync found, prune it
						buffer = buffer.slice(TOTAL_PACKET_SIZE)
			else:
				# Synched Mode - validate header at position 0
				if buffer.size() >= TOTAL_PACKET_SIZE:
					# Manual byte-by-byte header check (most reliable)
					var header_valid = true
					for i in range(11):
						if buffer[i] != SYNC_SEQ_PBA[i]:
							header_valid = false
							break
					
					if header_valid:
						var packet = buffer.slice(0, TOTAL_PACKET_SIZE)
						_process_packet_thread(packet)
						buffer = buffer.slice(TOTAL_PACKET_SIZE)
					else:
						# Header mismatch - lost sync, rescan
						print("Pipe: Lost Sync! Rescanning...")
						synched = false
		else:
			OS.delay_msec(1)

func reconnect_threaded():
	pass # No-op for pipes

func _setup_debug_fps():
	debug_fps_label = Label.new()
	debug_fps_label.text = "FPS: WAIT"
	debug_fps_label.position = Vector2(40, 40)
	
	# High Visibility Overrides
	debug_fps_label.add_theme_color_override("font_color", Color(0, 1, 0, 1)) # Bright Green
	debug_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_fps_label.add_theme_constant_override("outline_size", 8)
	debug_fps_label.add_theme_font_size_override("font_size", 24) # Large text
	
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
var _ready_index: int = -1 # Index of the latest fully written frame
var _read_index: int = -1 # Index currently displayed
var fps_timer: float = 0.0
var fps_frame_count: int = 0
var fps_skip_count: int = 0
var debug_fps_label: Label = null

# Thread-safe image update using Ring Buffer (Triple Buffering - Pull Model)
func set_im_from_data_threaded(rgba: PackedByteArray):
	# Select buffer to write to
	var write_idx = _write_head
	var img = _buffer_images[write_idx]
	
	# Write data to it
	img.set_data(128, 128, false, Image.FORMAT_RGBA8, rgba)
	
	# Metrics: Calculate Jitter (Frame-to-Frame Arrival Time)
	if metrics_visible:
		var now = Time.get_ticks_usec()
		if metrics_last_packet_time > 0:
			var delta_ms = (now - metrics_last_packet_time) / 1000.0
			if _mutex:
				_mutex.lock()
				metrics_pipe_interval = delta_ms
				_mutex.unlock()
		metrics_last_packet_time = now
	
	# Mark as ready
	if _mutex:
		_mutex.lock()
		_ready_index = write_idx
		fps_frame_count += 1
		_mutex.unlock()
	
	# Advance head (Ring Buffer 0 -> 1 -> 2 -> 0)
	_write_head = (_write_head + 1) % 3

func find_seq_pba(host: PackedByteArray, sub: PackedByteArray) -> int:
	var host_len = host.size()
	var sub_len = sub.size()
	
	if host_len < sub_len or sub_len == 0:
		return -1
	
	var first = sub[0]
	var limit = host_len - sub_len
	
	for i in range(limit + 1):
		# Quick check first byte
		if host[i] == first:
			var is_match = true
			for j in range(1, sub_len):
				if host[i + j] != sub[j]:
					is_match = false
					break
			if is_match:
				return i
	return -1


var last_mouse_state = [0, 0, 0]
var synched = false

func _process(delta: float) -> void:
	# 1. POLL FOR NEW FRAMES (Pull Method)
	var latest_ready = -1
	if _mutex:
		_mutex.lock()
		latest_ready = _ready_index
		_mutex.unlock()
	
	var is_new_frame = false
	if latest_ready != -1 and latest_ready != _read_index:
		# We have a new frame ready to show!
		_read_index = latest_ready
		stream_texture.update(_buffer_images[_read_index])
		is_new_frame = true

	# 2. UPDATE FPS DEBUG
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
		# Add to local buffer (Batching)
		_main_thread_input_buffer.append([
			PIDOT_EVENT_MOUSEEV, current_mouse_state[0], current_mouse_state[1],
			current_mouse_state[2], 0, 0, 0, 0
		])
		last_mouse_state = current_mouse_state
		
	# Flush Input Buffer (Single Mutex Lock per frame)
	if _main_thread_input_buffer.size() > 0:
		if _mutex:
			_mutex.lock()
			_input_queue.append_array(_main_thread_input_buffer)
			_mutex.unlock()
		_main_thread_input_buffer.clear()
	
	# METRICS UPDATE
	if metrics_visible:
		var now = Time.get_ticks_usec()
		var frame_delta_ms = (now - metrics_last_frame_time) / 1000.0
		metrics_last_frame_time = now
		
		# Jitter calc (from thread)
		var jitter_val = 0.0
		if _mutex:
			_mutex.lock()
			jitter_val = metrics_pipe_interval
			_mutex.unlock()
		
		var disp_fps = 1000.0 / max(0.1, frame_delta_ms)
		var pipe_fps = 1000.0 / max(0.1, jitter_val) if jitter_val > 0 else 0.0
		var fps_diff = pipe_fps - disp_fps
		
		# Clamp weird spikes
		if abs(fps_diff) > 200: fps_diff = 0.0
		
		var is_stutter = 0.0 if is_new_frame else 1.0
		
		if graph_fps: graph_fps.add_value(disp_fps)
		if graph_jitter: graph_jitter.add_value(jitter_val)
		if graph_starvation: graph_starvation.add_value(is_stutter)
		if graph_fps_diff: graph_fps_diff.add_value(fps_diff)
		
		# Data Logging
		if metrics_logging_enabled and metrics_file:
			# Format: Timestamp, DisplayFPS, NetJitter, IsStutter, FPSDiff
			var line = "%d,%.2f,%.2f,%d,%.2f" % [now, disp_fps, jitter_val, int(is_stutter), fps_diff]
			
			metrics_buffer.append(line)
			if metrics_buffer.size() >= METRICS_BUFFER_SIZE:
				_flush_logs()


func _process_packet_thread(data: PackedByteArray):
	var im_start = len(SYNC_SEQ) + CUSTOM_BYTE_COUNT
	var im = data.slice(im_start, im_start + DISPLAY_BYTES)
	set_im_from_data_threaded(im)


# --- METRICS SYSTEM ---
var metrics_visible: bool = false
var metrics_logging_enabled: bool = false # Log metrics to file -> Start disabled by default
var metrics_file: FileAccess = null
var metrics_buffer: PackedStringArray = []
const METRICS_BUFFER_SIZE = 120 # Flush every ~2 seconds (at 60fps)

var graph_fps: DebugGraph
var graph_jitter: DebugGraph
var graph_starvation: DebugGraph
var graph_fps_diff: DebugGraph
var metrics_last_frame_time: int = 0
var metrics_last_packet_time: int = 0
var metrics_pipe_interval: float = 0.0

func _setup_metrics_display():
	var container = VBoxContainer.new()
	container.position = Vector2(50, 150)
	container.size = Vector2(400, 550) # Increased height
	
	# FPS Graph
	graph_fps = DebugGraph.new()
	graph_fps.label_text = "Display FPS"
	graph_fps.min_value = 0
	graph_fps.max_value = 140
	graph_fps.custom_minimum_size = Vector2(400, 100)
	graph_fps.graph_color = Color.GREEN
	container.add_child(graph_fps)
	
	# Jitter Graph (Network Inter-arrival time)
	graph_jitter = DebugGraph.new()
	graph_jitter.label_text = "Pipe Interval (ms)"
	graph_jitter.min_value = 0
	graph_jitter.max_value = 33
	graph_jitter.custom_minimum_size = Vector2(400, 100)
	graph_jitter.graph_color = Color.CYAN
	container.add_child(graph_jitter)

	# Starvation Graph
	graph_starvation = DebugGraph.new()
	graph_starvation.label_text = "Stutter (1=Dup)"
	graph_starvation.min_value = 0
	graph_starvation.max_value = 1.1
	graph_starvation.custom_minimum_size = Vector2(400, 100)
	graph_starvation.graph_color = Color.RED
	container.add_child(graph_starvation)
	
	# FPS Diff Graph (Net - Display)
	graph_fps_diff = DebugGraph.new()
	graph_fps_diff.label_text = "FPS Diff (Pipe-Disp)"
	graph_fps_diff.min_value = -30 # Allow negative if Net < Disp (unlikely but possible with weird timing)
	graph_fps_diff.max_value = 30 # Positive means Net > Disp (Dropping frames)
	graph_fps_diff.custom_minimum_size = Vector2(400, 100)
	graph_fps_diff.graph_color = Color.ORANGE
	container.add_child(graph_fps_diff)
	
	var cl = CanvasLayer.new()
	cl.layer = 129
	cl.add_child(container)
	add_child(cl)
	metrics_layer = cl
	metrics_visible = true

	_start_logging()

func _start_logging():
	if metrics_logging_enabled: return
	
	# Ensure logs directory exists
	var logs_dir = PicoBootManager.PUBLIC_FOLDER + "/logs"
	if not DirAccess.dir_exists_absolute(logs_dir):
		DirAccess.make_dir_absolute(logs_dir)
	
	var path = logs_dir + "/metrics_log_%d.csv" % Time.get_unix_time_from_system()
	metrics_file = FileAccess.open(path, FileAccess.WRITE)
	if metrics_file:
		metrics_file.store_line("Timestamp,DisplayFPS,PipeInterval,IsStutter,FPSDiff")
		metrics_logging_enabled = true
		metrics_buffer.clear()
		print("Metrics logging started: ", path)
	else:
		print("Failed to start metrics logging at ", path)

func _stop_logging():
	if metrics_logging_enabled:
		_flush_logs()
		if metrics_file:
			metrics_file.close()
			metrics_file = null
		metrics_logging_enabled = false
		print("Metrics logging stopped")

func _flush_logs():
	if metrics_file and metrics_buffer.size() > 0:
		for line in metrics_buffer:
			metrics_file.store_line(line)
		metrics_buffer.clear()
		metrics_file.flush()

var metrics_layer: CanvasLayer = null

func toggle_metrics():
	if not metrics_visible:
		_setup_metrics_display()
	else:
		# Toggle Off
		metrics_visible = false
		_stop_logging()
		
		if metrics_layer:
			metrics_layer.queue_free()
			metrics_layer = null
			
		graph_fps = null
		graph_jitter = null
		graph_starvation = null
		graph_fps_diff = null

const SDL_KEYMAP: Dictionary = preload("res://sdl_keymap.json").data

func send_key(id: int, down: bool, repeat: bool, mod: int):
	# Add to local buffer (Batching)
	_main_thread_input_buffer.append([
		PIDOT_EVENT_KEYEV,
		id, int(down), int(repeat),
		mod & 0xff, (mod >> 8) & 0xff, 0, 0
	])
			
func send_input(char: int):
	# Add to local buffer (Batching)
	_main_thread_input_buffer.append([
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


var input_blocked: bool = false

func set_input_blocked(blocked: bool):
	input_blocked = blocked

# --- Orientation Settings ---
enum OrientationMode {
	AUTO = 0,
	LANDSCAPE = 1,
	LANDSCAPE_REVERSED = 2,
	PORTRAIT = 3,
	PORTRAIT_REVERSED = 4
}

static var orientation_mode: OrientationMode = OrientationMode.AUTO

static func set_orientation_mode(mode: int):
	orientation_mode = mode as OrientationMode
	apply_orientation()

static func get_orientation_mode() -> int:
	return orientation_mode

static func apply_orientation():
	match orientation_mode:
		OrientationMode.AUTO:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR) # DisplayServer.SCREEN_ORIENTATION_SENSOR
		OrientationMode.LANDSCAPE:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE) # DisplayServer.SCREEN_ORIENTATION_LANDSCAPE
		OrientationMode.LANDSCAPE_REVERSED:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_REVERSE_LANDSCAPE) # DisplayServer.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
		OrientationMode.PORTRAIT:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT) # DisplayServer.SCREEN_ORIENTATION_PORTRAIT
		OrientationMode.PORTRAIT_REVERSED:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_REVERSE_PORTRAIT) # DisplayServer.SCREEN_ORIENTATION_REVERSE_PORTRAIT

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

	# If input is blocked (e.g. during controller test), ignore everything else
	if input_blocked:
		return


	if id not in SDL_KEYMAP:
		return
	if (id not in held_keys) and not down:
		return
		
	if down:
		if quit_overlay and quit_overlay.visible:
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
	
	# Hotkey for metrics (M for Metrics)
	if OS.is_debug_build() and id == "M" and down:
		toggle_metrics()
	

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
	# Layout update is now handled via Arranger.dirty -> layout_updated signal

static func get_integer_scaling_enabled() -> bool:
	return integer_scaling_enabled

static var bezel_enabled: bool = false
static func set_bezel_enabled(enabled: bool):
	bezel_enabled = enabled
	if instance and instance.bezel_overlay:
		instance.bezel_overlay.visible = enabled
		# Trigger layout update if enabling, in case it wasn't sized correctly while hidden
		if enabled:
			instance.call_deferred("_update_bezel_layout")

static func get_bezel_enabled() -> bool:
	return bezel_enabled

enum ControlsMode {
	AUTO = 0,
	FORCE = 1,
	DISABLED = 2
}

static var controls_mode: ControlsMode = ControlsMode.AUTO
static func set_controls_mode(mode: int):
	controls_mode = mode as ControlsMode
	
static func get_controls_mode() -> int:
	return controls_mode

enum ShaderType {
	NONE = 0,
	RETRO_V2 = 1,
	RETRO_V3 = 2,
	LCD3X = 3,
	LCD_GBC = 4,
	LCD_TRANSPARENCY = 5,
	DOT_MATRIX = 6,
	ZFAST_CRT = 7,
	CRT_HYLLIAN = 8,
	CRT_APERTURE = 9,
	CRT_1TAP = 10
}

static var current_shader_type: ShaderType = ShaderType.NONE
static var current_shader_opacity: float = 1.0

static func set_shader_type(shader_type: ShaderType):
	current_shader_type = shader_type
	
	if instance:
		if shader_type == ShaderType.NONE:
			# Remove shader
			instance.displayContainer.material = null
		else:
			# Load appropriate shader
			var shader_path = ""
			match shader_type:
				ShaderType.RETRO_V2:
					shader_path = "retro_v2.gdshader"
				ShaderType.RETRO_V3:
					shader_path = "retro_v3.gdshader"
				ShaderType.LCD3X:
					shader_path = "lcd3x.gdshader"
				ShaderType.LCD_GBC:
					shader_path = "lcd_gbc.gdshader"
				ShaderType.LCD_TRANSPARENCY:
					shader_path = "lcd_transparency.gdshader"
				ShaderType.DOT_MATRIX:
					shader_path = "dot_matrix.gdshader"
				ShaderType.ZFAST_CRT:
					shader_path = "zfast_crt.gdshader"
				ShaderType.CRT_HYLLIAN:
					shader_path = "crt_hyllian.gdshader"
				ShaderType.CRT_APERTURE:
					shader_path = "crt_aperture.gdshader"
				ShaderType.CRT_1TAP:
					shader_path = "crt_1tap.gdshader"
			
			if shader_path != "":
				var shader = instance.load_external_shader(shader_path)
				var mat = ShaderMaterial.new()
				mat.shader = shader
				
				# Apply current parameters
				mat.set_shader_parameter("SATURATION", current_saturation)
				mat.set_shader_parameter("STRENGTH", current_shader_opacity)
				
				# Apply to displayContainer (the sprite showing the upscaled viewport texture)
				instance.displayContainer.material = mat

static func get_shader_type() -> ShaderType:
	return current_shader_type

static func set_shader_opacity(opacity: float):
	current_shader_opacity = clamp(opacity, 0.0, 1.0)
	
	if instance and instance.displayContainer.material:
		var mat = instance.displayContainer.material as ShaderMaterial
		if mat and mat.shader:
			mat.set_shader_parameter("STRENGTH", current_shader_opacity)

static func get_shader_opacity() -> float:
	return current_shader_opacity

# Saturation control
static var current_saturation: float = 1.0

static func set_saturation(saturation: float):
	current_saturation = clamp(saturation, 0.0, 2.0)
	
	# Apply to current shader material if it exists
	if instance and instance.displayContainer.material:
		var mat = instance.displayContainer.material as ShaderMaterial
		if mat and mat.shader:
			mat.set_shader_parameter("SATURATION", current_saturation)

static func get_saturation() -> float:
	return current_saturation

# Button hue control (-180 to +180 degrees)
static var current_button_hue: float = 0.0
static var current_button_saturation: float = 1.0
static var current_button_lightness: float = 1.0

static func set_button_hue(hue: float):
	current_button_hue = clamp(hue, -180.0, 180.0)
	_apply_button_hue()

static func get_button_hue() -> float:
	return current_button_hue

static func set_button_saturation(saturation: float):
	current_button_saturation = clamp(saturation, 0.0, 2.0)
	_apply_button_hue()

static func get_button_saturation() -> float:
	return current_button_saturation

static func set_button_lightness(lightness: float):
	current_button_lightness = clamp(lightness, 0.0, 2.0)
	_apply_button_hue()

static func get_button_lightness() -> float:
	return current_button_lightness

static func _apply_button_hue():
	if not instance:
		print("Button hue: no instance")
		return
	
	# Get button nodes
	var root = instance.get_tree().root
	
	var portrait_buttons = [
		root.get_node_or_null("Main/Arranger/kbanchor/kb_gaming/X"),
		root.get_node_or_null("Main/Arranger/kbanchor/kb_gaming/O"),
		root.get_node_or_null("Main/Arranger/kbanchor/kb_gaming/Escape"),
		root.get_node_or_null("Main/Arranger/kbanchor/kb_gaming/Pause"),
	]
	
	var landscape_buttons = [
		root.get_node_or_null("Main/LandscapeUI/Control/RightPad/X"),
		root.get_node_or_null("Main/LandscapeUI/Control/RightPad/O"),
		root.get_node_or_null("Main/LandscapeUI/Control/SystemButtons/Escape"),
		root.get_node_or_null("Main/LandscapeUI/Control/SystemButtons/Pause"),
	]
	
	# Load the hue shift shader
	var hue_shader = instance.load_external_shader("hue_shift.gdshader") if instance else load("res://shaders/hue_shift.gdshader")
	if not hue_shader:
		print("Button hue: failed to load shader")
		return
	
	var _buttons_found = 0
	for button in portrait_buttons + landscape_buttons:
		if not button:
			continue
		
		_buttons_found += 1
		
		# At 0°, remove shader to restore original colors
		if current_button_hue == 0.0 and current_button_saturation == 1.0 and current_button_lightness == 1.0:
			button.material = null
			button.self_modulate = Color.WHITE
		else:
			# Create shader material if needed
			var mat: ShaderMaterial
			if not button.material or not (button.material is ShaderMaterial):
				mat = ShaderMaterial.new()
				mat.shader = hue_shader
				button.material = mat
			else:
				mat = button.material as ShaderMaterial
			
			# Set the shader parameters
			mat.set_shader_parameter("hue_shift", current_button_hue)
			mat.set_shader_parameter("saturation_mult", current_button_saturation)
			mat.set_shader_parameter("lightness_mult", current_button_lightness)

	
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
		# Check Blocked State (e.g. Controller Test Mode)
		if input_blocked:
			return
			
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
		# Check ignore list (System & User Disabled)
		if ControllerUtils.is_system_ignored(event.device):
			return
		
		var role = ControllerUtils.get_controller_role(event.device)
		if role == ControllerUtils.ROLE_DISABLED:
			return

		var is_p2 = false
		
		if role == ControllerUtils.ROLE_P2:
			is_p2 = true
		elif role == ControllerUtils.ROLE_P1:
			is_p2 = false
		else: # AUTO
			# Fallback to Index Logic for Auto controllers
			# We need to know where this controller sits in the "real" list
			var real_joypads = ControllerUtils.get_real_controllers()
			# Logic remains: If Index == 1 -> P2.
			var idx = real_joypads.find(event.device)
			if idx == 1:
				is_p2 = true
				
		if input_mode == InputMode.TRACKPAD and not is_p2:
			# Controller Mouse Click Mapping (P1 Only)
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
		
		if is_p2:
			# Player 2 Mapping (ESDF + Tab/Q)
			match event.button_index:
				JoyButton.JOY_BUTTON_A, JoyButton.JOY_BUTTON_Y: key_id = "Tab"
				JoyButton.JOY_BUTTON_B, JoyButton.JOY_BUTTON_X: key_id = "Q"
				JoyButton.JOY_BUTTON_START, JoyButton.JOY_BUTTON_RIGHT_SHOULDER: key_id = "P" # Pause
				JoyButton.JOY_BUTTON_BACK, JoyButton.JOY_BUTTON_GUIDE:
					key_id = "IntentExit" if is_intent_session else "Escape" # Menu / Exit
				JoyButton.JOY_BUTTON_DPAD_UP: key_id = "E"
				JoyButton.JOY_BUTTON_DPAD_DOWN: key_id = "D"
				JoyButton.JOY_BUTTON_DPAD_LEFT: key_id = "S"
				JoyButton.JOY_BUTTON_DPAD_RIGHT: key_id = "F"
				JoyButton.JOY_BUTTON_LEFT_SHOULDER:
					if event.pressed:
						_toggle_options_menu()
		else:
			# Player 1 Mapping (Standard)
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
		# Check ignore list (System & User Disabled)
		if ControllerUtils.is_system_ignored(event.device):
			return
		
		var role = ControllerUtils.get_controller_role(event.device)
		if role == ControllerUtils.ROLE_DISABLED:
			return

		var is_p2 = false
		
		if role == ControllerUtils.ROLE_P2:
			is_p2 = true
		elif role == ControllerUtils.ROLE_P1:
			is_p2 = false
		else: # AUTO
			# Fallback to Index Logic
			var real_joypads = ControllerUtils.get_real_controllers()
			var idx = real_joypads.find(event.device)
			if idx == 1:
				is_p2 = true
		
		# Map Axes
		var key_left = "S" if is_p2 else "Left"
		var key_right = "F" if is_p2 else "Right"
		var key_up = "E" if is_p2 else "Up"
		var key_down = "D" if is_p2 else "Down"

		var axis_threshold = 0.5
		# Handle Left Stick X (Left/Right)
		if event.axis == JoyAxis.JOY_AXIS_LEFT_X:
			if event.axis_value < -axis_threshold:
				if key_left not in held_keys: vkb_setstate(key_left, true)
			else:
				if key_left in held_keys:
					# Only release if D-PAD is NOT also holding it
					if not Input.is_joy_button_pressed(event.device, JoyButton.JOY_BUTTON_DPAD_LEFT):
						vkb_setstate(key_left, false)

			if event.axis_value > axis_threshold:
				if key_right not in held_keys: vkb_setstate(key_right, true)
			else:
				if key_right in held_keys:
					if not Input.is_joy_button_pressed(event.device, JoyButton.JOY_BUTTON_DPAD_RIGHT):
						vkb_setstate(key_right, false)
		
		# Handle Left Stick Y (Up/Down)
		elif event.axis == JoyAxis.JOY_AXIS_LEFT_Y:
			if event.axis_value < -axis_threshold:
				if key_up not in held_keys: vkb_setstate(key_up, true)
			else:
				if key_up in held_keys:
					if not Input.is_joy_button_pressed(event.device, JoyButton.JOY_BUTTON_DPAD_UP):
						vkb_setstate(key_up, false)

			if event.axis_value > axis_threshold:
				if key_down not in held_keys: vkb_setstate(key_down, true)
			else:
				if key_down in held_keys:
					if not Input.is_joy_button_pressed(event.device, JoyButton.JOY_BUTTON_DPAD_DOWN):
						vkb_setstate(key_down, false)
		

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
	var keyboard_btn = get_node("Arranger/kbanchor/Keyboard Btn")
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
	# 2. Create Dialog using UIUtils
	quit_overlay = UIUtils.create_confirm_dialog(
		self,
		"Quit Confirmation", # Title (UIUtils might ignore or style)
		"RETURN TO LAUNCHER?", # Text
		"YES", # Confirm Label
		"NO", # Cancel Label
		true,
		_quit_app, # Confirm Callback
		func(): quit_overlay.visible = false # Cancel Callback
	)
	
	# Default hidden
	quit_overlay.visible = false
	

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

# --- Bezel Support ---
var bezel_overlay: BezelOverlay

func _setup_bezel_overlay():
	if bezel_overlay:
		print("Video Streamer: Bezel overlay already exists, skipping setup.")
		return
		
	bezel_overlay = BezelOverlay.new()
	bezel_overlay.name = "BezelOverlay"
	bezel_overlay.visible = bezel_enabled # Set initial visibility
	# Add as sibling of displayContainer so it renders ON TOP but is independent of shaders
	# displayContainer is where the game is.
	# Actually, we want it to be a child of this node (PicoVideoStreamer)
	# But z-ordered above displayContainer?
	# displayContainer is an @export var, likely a child.
	add_child(bezel_overlay)
	print("Video Streamer: BezelOverlay added to scene tree.")
	
	# Connect to resize for layout updates
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Force initial layout update immediately (Synchronous) to prevent startup flicker
	_update_bezel_layout()

func _on_viewport_size_changed():
	_update_bezel_layout()

func _update_bezel_layout():
	if bezel_overlay:
		bezel_overlay.update_layout(get_display_rect())
		
		# Emit signal if bezel is legally loaded and ready
		if bezel_overlay.is_bezel_loaded:
			bezel_layout_updated.emit(bezel_overlay.get_global_rect(), Vector2.ONE) # Scale is calculated by consumer

# Transform a point from Theme Coordinates to Global Screen Coordinates
# theme_pos: The (x,y) in the layout.json
# theme_bezel_size: The [w,h] of the bezel image in layout.json
# actual_bezel_rect: The current global Rect2 of the BezelOverlay
static func transform_theme_pos(theme_pos: Vector2, theme_bezel_size: Vector2, actual_bezel_rect: Rect2) -> Vector2:
	if theme_bezel_size.x == 0 or theme_bezel_size.y == 0:
		return Vector2.ZERO
		
	var scale_x = actual_bezel_rect.size.x / theme_bezel_size.x
	var scale_y = actual_bezel_rect.size.y / theme_bezel_size.y
	
	var offset = theme_pos * Vector2(scale_x, scale_y)
	return actual_bezel_rect.position + offset

# Helper to get the screen-space rect of the game display
func get_display_rect() -> Rect2:
	if not displayContainer:
		return Rect2()
		
	# Use GLOBAL scale and position to get the actual on-screen size
	var size_tex = Vector2(128, 128)
	var final_scale = displayContainer.global_scale
	var size_screen = size_tex * final_scale
	
	var pos_top_left = Vector2.ZERO
	
	if displayContainer.centered:
		pos_top_left = displayContainer.global_position - (size_screen / 2.0)
	else:
		pos_top_left = displayContainer.global_position
		

	var local_pos = to_local(pos_top_left)
	
	
	return Rect2(local_pos, size_screen)

# Display Repositioning
static var display_drag_enabled: bool = false
static var display_drag_offset_portrait: Vector2 = Vector2.ZERO
static var display_drag_offset_landscape: Vector2 = Vector2.ZERO
static var display_scale_portrait: float = 1.0
static var display_scale_landscape: float = 1.0

static var control_layout_portrait: Dictionary = {}
static var control_layout_landscape: Dictionary = {}

static func set_display_drag_enabled(enabled: bool):
	display_drag_enabled = enabled
	# Force Arranger update if instance exists
	if instance:
		var arranger = instance.get_node_or_null("/root/Main/Arranger")
		if arranger:
			arranger.dirty = true
			if arranger.has_method("_update_reset_button_visibility"):
				arranger._update_reset_button_visibility()

static func set_display_drag_offset(offset: Vector2, is_landscape: bool):
	if is_landscape:
		display_drag_offset_landscape = offset
	else:
		display_drag_offset_portrait = offset
		
	if instance:
		var arranger = instance.get_node_or_null("Arranger")
		if arranger:
			arranger.dirty = true
		
static func get_display_drag_offset(is_landscape: bool) -> Vector2:
	return display_drag_offset_landscape if is_landscape else display_drag_offset_portrait

static func set_display_scale_modifier(new_scale: float, is_landscape: bool):
	if is_landscape:
		display_scale_landscape = new_scale
	else:
		display_scale_portrait = new_scale
	
	if instance:
		var arranger = instance.get_node_or_null("Arranger")
		if arranger: arranger.dirty = true

static func get_display_scale_modifier(is_landscape: bool) -> float:
	return display_scale_landscape if is_landscape else display_scale_portrait

static func set_control_layout_data(control_name: String, pos: Vector2, new_scale: float, is_landscape: bool):
	var data = {"pos": pos, "scale": new_scale}
	if is_landscape:
		control_layout_landscape[control_name] = data
	else:
		control_layout_portrait[control_name] = data

static func get_control_layout_data(control_name: String, is_landscape: bool) -> Variant:
	if is_landscape:
		return control_layout_landscape.get(control_name, null)
	else:
		return control_layout_portrait.get(control_name, null)

static func get_control_pos(control_name: String, is_landscape: bool) -> Variant:
	var data = get_control_layout_data(control_name, is_landscape)
	if data == null: return null
	if data is Vector2: return data # Legacy support
	return data.get("pos", null)
	
func get_current_bezel_rect() -> Rect2:
	if bezel_overlay and bezel_overlay.is_bezel_loaded:
		return bezel_overlay.get_global_rect()
	return Rect2()

static func get_control_scale(control_name: String, is_landscape: bool) -> float:
	var data = get_control_layout_data(control_name, is_landscape)
	if data == null or data is Vector2: return 1.0
	return data.get("scale", 1.0)

static func reset_display_layout(is_landscape: bool):
	print("Resetting Display Layout for: ", "Landscape" if is_landscape else "Portrait")
	if is_landscape:
		display_drag_offset_landscape = Vector2.ZERO
		display_scale_landscape = 1.0
		control_layout_landscape.clear()
	else:
		display_drag_offset_portrait = Vector2.ZERO
		display_scale_portrait = 1.0
		control_layout_portrait.clear()

	# Force Arranger update
	if instance:
		instance.emit_signal("layout_reset", is_landscape)
		
		var arranger = instance.get_node_or_null("/root/Main/Arranger")
		if arranger:
			arranger.dirty = true
			if arranger.has_method("_update_reset_button_visibility"):
				arranger._update_reset_button_visibility()
			arranger.dirty = true
