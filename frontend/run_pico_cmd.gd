extends Node

enum ExecutionMode {PICO8, TELNETSSH}
@export var execution_mode: ExecutionMode = ExecutionMode.PICO8
@export var debug_cart_path: String = ""

var pico_pid = null

# Async Restart State Machine
enum RestartState {IDLE, REQUESTED, SENDING_CTRL_DOWN, SENDING_Q_DOWN, SENDING_Q_UP, SENDING_CTRL_UP, WAITING_FOR_EXIT}
var restart_state: RestartState = RestartState.IDLE
var pending_restart_path: String = ""
var state_timer: int = 0
var process_check_timer: int = 0
var last_received_data = ""
var last_received_time = 0

var is_intent_session: bool = false
signal intent_session_started

# Process suspension state
var is_process_suspended: bool = false

func _ready() -> void:
	if Engine.is_embedded_in_editor():
		return
	# Connect to Applinks for runtime updates (hot swap)
	if Applinks:
		if not Applinks.data_received.is_connected(_on_applinks_data_received):
			Applinks.data_received.connect(_on_applinks_data_received)
		
	# FIX PERMISSIONS
	var pkg_path = PicoBootManager.APPDATA_FOLDER + "/package"
	var busybox_path = pkg_path + "/busybox"
	var script_path = pkg_path + "/start_pico_proot.sh"
	
	print("Applying permissions to: " + pkg_path)
	OS.execute(PicoBootManager.BIN_PATH + "/chmod", ["755", busybox_path])
	OS.execute(PicoBootManager.BIN_PATH + "/chmod", ["755", script_path])
	
	match execution_mode:
		ExecutionMode.PICO8:
			# Check if we have an initial intention (cold boot)
			var initial_path = await _get_target_path()
			_launch_pico8(initial_path)
		
		ExecutionMode.TELNETSSH:
			var cmdline = 'cd ' + pkg_path + '; ln -s busybox ash; LD_LIBRARY_PATH=. ./busybox telnetd -l ./ash -F -p 2323'
			pico_pid = OS.create_process(
				PicoBootManager.BIN_PATH + "/sh",
				["-c", cmdline]
			)
			print("executing as pid " + str(pico_pid) + "\n" + cmdline)
	
	if OS.is_debug_build() and execution_mode != ExecutionMode.TELNETSSH:
		OS.create_process(
			PicoBootManager.BIN_PATH + "/sh",
			["-c", 'cd ' + PicoBootManager.APPDATA_FOLDER + '/package; ln -s busybox ash; LD_LIBRARY_PATH=. ./busybox telnetd -l ./ash -F -p 2323']
		)

func _on_applinks_data_received(data: String) -> void:
	print("Runtime AppLink received: ", data)
	
	is_intent_session = true # Mark session as controlled by external launcher
	intent_session_started.emit()
	
	if data.is_empty():
		return

	# Block re-entry if we are already in the middle of a restart logic
	if restart_state != RestartState.IDLE:
		print("Restart already in progress (State: ", restart_state, "). Ignoring concurrent intent.")
		return

	# Debounce: Ignore duplicate intents arriving within 5 seconds
	var current_time = Time.get_ticks_msec()
	if data == last_received_data and (current_time - last_received_time) < 5000:
		print("Duplicate/frequent intent ignored.")
		return
		
	last_received_data = data
	last_received_time = current_time

	# Decode the new data using our robust logic
	# Start the Async Restart Sequence
	pending_restart_path = await _decode_and_fix_path(data)
	restart_state = RestartState.REQUESTED
	print("Restart Sequence Initiated for: ", pending_restart_path)

func _launch_pico8(target_path: String) -> void:
	# Ensure clean slate (in case force kill was needed or cold boot)
	if pico_pid:
		_kill_all_pico_processes()
		pico_pid = null
	
	# Reset suspension state
	is_process_suspended = false
	
	var pkg_path = PicoBootManager.APPDATA_FOLDER + "/package"
	var env_setup = "export HOME=" + pkg_path + "; "
	var run_arg = " -splore"
	var extra_bind_export = ""
	
	if not target_path.is_empty():
		var fname_lower = target_path.get_file().to_lower()
		if fname_lower == "splore.p8" or fname_lower == "splore.p8.png":
			run_arg = " -splore"
		elif target_path.begins_with(PicoBootManager.PUBLIC_FOLDER):
			run_arg = " -run " + target_path.replace(PicoBootManager.PUBLIC_FOLDER, "/home/public")
		else:
			# External path: bind the parent directory to /home/custom_mount
			# properly escape single quotes for shell context: ' becomes '\''
			var parent_dir = target_path.get_base_dir().replace("'", "'\\''")
			
			# VALIDATE PATH EXISTENCE
			# Android External Storage paths often arrive valid but unreadable if permissions are missing
			# Or if they are symbolic links (like /Roms/) that apps can't see.
			var dir_access = DirAccess.open(parent_dir)
			if not dir_access:
				print("ERROR: Cannot access external bind directory: ", parent_dir)
				print("Attempting to proceed, but bind will likely fail.")
				# Fallback? No, we can't guess where the file is if the path is wrong.
			else:
				print("External bind directory validated: ", parent_dir)
			
			var filename = _escape_filename_for_shell(target_path.get_file())
			extra_bind_export = "export PROOT_EXTRA_BIND='--bind=" + parent_dir + ":/home/custom_mount'; "
			run_arg = " -run /home/custom_mount/" + filename
	
	var cmdline = env_setup + extra_bind_export + 'cd ' + pkg_path + '; LD_LIBRARY_PATH=. ./busybox ash start_pico_proot.sh' + run_arg + ' >' + PicoBootManager.PUBLIC_FOLDER + '/logs/pico_out.txt 2>' + PicoBootManager.PUBLIC_FOLDER + "/logs/pico_err.txt"
	
	pico_pid = OS.create_process(
		PicoBootManager.BIN_PATH + "/sh",
		["-c", cmdline]
	)
	print("executing as pid " + str(pico_pid) + "\n" + cmdline)


func _escape_filename_for_shell(path: String) -> String:
	# Escapes dangerous shell characters by prepending backslash for unquoted context
	# Backslash MUST be replaced first to avoid double escaping
	var res = path.replace("\\", "\\\\")
	
	var chars = [";", "&", "|", "$", "\"", "'", "(", ")", "<", ">", "`", " "]
	for c in chars:
		res = res.replace(c, "\\" + c)
	return res

func _download_file(url: String) -> String:
	print("Attempting to download: ", url)
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var filename = url.get_file()
	if filename.is_empty() or not "." in filename:
		filename = "downloaded_cart.p8.png" # Fallback name
	
	# Decode URL encoding in filename just in case
	filename = filename.uri_decode()
	
	var target_dir = PicoBootManager.PUBLIC_FOLDER + "/data/carts"
	var target_path = target_dir + "/" + filename
	
	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(target_dir)

	http_request.download_file = target_path
	var error = http_request.request(url)
	if error != OK:
		print("An error occurred in the HTTP request.")
		http_request.queue_free()
		return ""
	
	var result = await http_request.request_completed
	# result is [result, response_code, headers, body]
	var response_code = result[1]
	
	http_request.queue_free()
	
	if response_code != 200:
		print("Download failed with response code: ", response_code)
		return ""
		
	print("Download successful: ", target_path)
	return target_path

func _decode_and_fix_path(uri: String) -> String:
	# Attempt to unwrap content:// URIs that cloak file:// paths
	# (e.g. content://com.android.providers.media.../file%3A%2F%2F...)	
	# if it starts with "/" already decoded by the intent plugin, no need to redo
	if not uri.begins_with("/"):
		var decoded_path = uri.uri_decode()
			
		# triple encoded
		if "file%3A" in decoded_path or "http%3A" in decoded_path or "http%3A" in decoded_path:
			decoded_path = decoded_path.uri_decode()

		decoded_path = decoded_path.uri_decode()
		print("Decoded URI: ", decoded_path)

		# Handle HTTP/HTTPS URLs asynchronously
		if decoded_path.begins_with("http://") or decoded_path.begins_with("https://"):
			return await _download_file(decoded_path)

		var file_prefix = "file://"
		var search_idx = decoded_path.find(file_prefix)
		if search_idx != -1:
			uri = decoded_path.substr(search_idx + file_prefix.length())
	
	print("Final Target Path: ", uri)
	return uri

func _get_target_path() -> String:
	var uri = ""
	if Applinks:
		var data = Applinks.get_data()
		if not data.is_empty():
			uri = data
			is_intent_session = true # Mark session as controlled by external launcher
			intent_session_started.emit()
		print("AppLinks returned: ", uri)

	if not uri.is_empty():
		return await _decode_and_fix_path(uri)

	# 2. Fallback to Editor Debug Property
	return debug_cart_path

func _kill_all_pico_processes() -> void:
	# Build a kill command that targets all related processes safely
	# Use both pkill (pattern) and killall (exact name) for maximum coverage
	var kill_cmd = "pkill -9 -f start_pico_proot.sh; " + \
				   "pkill -9 -f proot; killall -9 proot; " + \
				   "pkill -9 -f qemu; killall -9 qemu-i386-static; " + \
				   "pkill -9 -f pico8_64; killall -9 pico8_64; " + \
				   "pkill -9 -f pulseaudio; killall -9 pulseaudio; "
				   # Note: Avoid 'pkill -f pico8' as it hits the java app io.wip.pico8
	
	OS.execute(PicoBootManager.BIN_PATH + "/sh", ["-c", kill_cmd], [])
	print("Executed cleanup kill command: " + kill_cmd)

func _process(_delta: float) -> void:
	match restart_state:
		RestartState.IDLE:
			# Normal monitoring - Throttled to 1s
			if Time.get_ticks_msec() > process_check_timer:
				process_check_timer = Time.get_ticks_msec() + 1000
				if pico_pid and not OS.is_process_running(pico_pid):
					# print("PICO-8 Process died! (PID: " + str(pico_pid) + ")")
					get_tree().quit()
				
		RestartState.REQUESTED:
			# Step 1: Send Ctrl Down
			if PicoVideoStreamer.instance and PicoVideoStreamer.instance.tcp:
				print("Sending Graceful Quit (Ctrl+Q) Sequence...")
				# Key 224 (Ctrl), Down=True
				PicoVideoStreamer.instance.send_key(224, true, false, 0) # No mod needed for mod key itself
				restart_state = RestartState.SENDING_CTRL_DOWN
				state_timer = Time.get_ticks_msec()
			else:
				print("No TCP connection. Skipping graceful quit.")
				restart_state = RestartState.WAITING_FOR_EXIT
				state_timer = Time.get_ticks_msec() - 5000 # Skip wait
		
		RestartState.SENDING_CTRL_DOWN:
			# Step 2: Wait 50ms, then Q Down
			if (Time.get_ticks_msec() - state_timer) > 50:
				if PicoVideoStreamer.instance and PicoVideoStreamer.instance.tcp:
					# Key 20 (Q), Down=True, Mod=64 (Ctrl)
					PicoVideoStreamer.instance.send_key(20, true, false, 64)
				restart_state = RestartState.SENDING_Q_DOWN
				state_timer = Time.get_ticks_msec()

		RestartState.SENDING_Q_DOWN:
			# Step 3: Wait 100ms, then Q Up
			if (Time.get_ticks_msec() - state_timer) > 100:
				if PicoVideoStreamer.instance and PicoVideoStreamer.instance.tcp:
					PicoVideoStreamer.instance.send_key(20, false, false, 64)
				restart_state = RestartState.SENDING_Q_UP
				state_timer = Time.get_ticks_msec()

		RestartState.SENDING_Q_UP:
			# Step 4: Wait 50ms, then Ctrl Up
			if (Time.get_ticks_msec() - state_timer) > 50:
				if PicoVideoStreamer.instance and PicoVideoStreamer.instance.tcp:
					PicoVideoStreamer.instance.send_key(224, false, false, 0)
				restart_state = RestartState.WAITING_FOR_EXIT
				state_timer = Time.get_ticks_msec()

		RestartState.WAITING_FOR_EXIT:
			# Step 5: Wait for process to die
			if not pico_pid or not OS.is_process_running(pico_pid):
				print("Process quit gracefully!")
				_complete_restart()
			elif (Time.get_ticks_msec() - state_timer) > 3000:
				print("Graceful quit timed out. Proceeding anyway.")
				# _kill_all_pico_processes() # Disabled per user request
				_complete_restart()

func _complete_restart() -> void:
	# Force cleanup of any lingering processes (even if graceful quit worked, clean up zombies)
	_kill_all_pico_processes()
	pico_pid = null

	# Cleanup temp files that might block restart (PID files, sockets, pipes)
	# Removing the whole tmp dir content to ensure pulseaudio
	var pkg_path = PicoBootManager.APPDATA_FOLDER + "/package"
	var rm_cmd = "rm -rf " + pkg_path + "/tmp/* " + pkg_path + "/ptmp/*"
	OS.execute(PicoBootManager.BIN_PATH + "/sh", ["-c", rm_cmd], [])

	# Force TCP reset on streamer side to ensure immediate pickup
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.hard_reset_connection()

	# Final Step: Launch new process
	print("Launching new PICO-8 instance: ", pending_restart_path)
	_launch_pico8(pending_restart_path)
	restart_state = RestartState.IDLE

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			suspend_pico_process()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			resume_pico_process()

func suspend_pico_process() -> void:
	# Only suspend if we have a valid PID (meaning PICO-8 should be running)
	if not pico_pid or pico_pid <= 0 or is_process_suspended:
		return
	
	if not OS.is_process_running(pico_pid):
		return
	
	# Notify video streamer to pause timeout monitoring
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.is_pico_suspended = true
	
	# Suspend proot and pico8_64
	# Note: NOT suspending pulseaudio to avoid audio state issues on resume
	var suspend_cmd = "pkill -STOP proot; pkill -STOP pico8_64"
	var result = OS.execute(
		PicoBootManager.BIN_PATH + "/sh",
		["-c", suspend_cmd],
		[],
		false
	)
	
	if result == OK:
		is_process_suspended = true
		print("PICO-8 process tree suspended")
	else:
		print("Failed to suspend PICO-8 process tree")

func resume_pico_process() -> void:
	# Only resume if we have a valid PID and process is currently suspended
	if not pico_pid or pico_pid <= 0 or not is_process_suspended:
		return
	
	if not OS.is_process_running(pico_pid):
		is_process_suspended = false
		return
	
	# Notify video streamer to resume timeout monitoring
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.is_pico_suspended = false
		# Reset the timeout timer so we don't get false timeout immediately
		PicoVideoStreamer.instance.last_message_time = Time.get_ticks_msec()
	
	# Resume proot and pico8_64
	# Note: NOT resuming pulseaudio since we didn't suspend it
	var resume_cmd = "pkill -CONT proot; pkill -CONT pico8_64"
	var result = OS.execute(
		PicoBootManager.BIN_PATH + "/sh",
		["-c", resume_cmd],
		[],
		false
	)
	
	if result == OK:
		is_process_suspended = false
		print("PICO-8 process tree resumed")
	else:
		print("Failed to resume PICO-8 process tree")
