extends Node

enum ExecutionMode { PICO8, TELNETSSH }
@export var execution_mode: ExecutionMode = ExecutionMode.PICO8

var pico_pid = null

func _ready() -> void:
	if Engine.is_embedded_in_editor():
		return
		
	# FIX PERMISSIONS
	var pkg_path = PicoBootManager.APPDATA_FOLDER + "/package"
	var busybox_path = pkg_path + "/busybox"
	var script_path = pkg_path + "/start_pico_proot.sh"
	
	print("Applying permissions to: " + pkg_path)
	OS.execute(PicoBootManager.BIN_PATH + "/chmod", ["755", busybox_path])
	OS.execute(PicoBootManager.BIN_PATH + "/chmod", ["755", script_path])
	
	var cmdline = ""
	# Explicitly set HOME to the package directory to fix "Failed to get home directory" matches
	var env_setup = "export HOME=" + pkg_path + "; "
	
	match execution_mode:
		ExecutionMode.PICO8:
			cmdline = env_setup + 'cd ' + pkg_path + '; LD_LIBRARY_PATH=. ./busybox ash start_pico_proot.sh >' + PicoBootManager.PUBLIC_FOLDER + '/logs/pico_out.txt 2>' + PicoBootManager.PUBLIC_FOLDER + "/logs/pico_err.txt"
		ExecutionMode.TELNETSSH:
			cmdline =  'cd ' + pkg_path + '; ln -s busybox ash; LD_LIBRARY_PATH=. ./busybox telnetd -l ./ash -F -p 2323'
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

func _process(delta: float) -> void:
	if pico_pid and not OS.is_process_running(pico_pid):
		get_tree().quit()
