extends Node
class_name PicoBootManager

static var pico_zip_path: String = ""

# Static constants that can be accessed from other scripts
static var BIN_PATH = "/system/bin"
static var APPDATA_FOLDER = "/data/data/io.wip.pico8/files"
static var PUBLIC_FOLDER = "/sdcard/Documents/pico8"

# Centralized permission checking
func has_storage_access() -> bool:
	var permissions = OS.get_granted_permissions()
	return (
		"android.permission.MANAGE_EXTERNAL_STORAGE" in permissions or
		("android.permission.READ_EXTERNAL_STORAGE" in permissions and
		"android.permission.WRITE_EXTERNAL_STORAGE" in permissions) or
		FileAccess.file_exists("user://dont-ask-for-storage")
	)

# Centralized UI state management
func set_ui_state(permission_ui: bool = false, select_zip_ui: bool = false, progress_ui: bool = false):
	%AllFileAccessContainer.visible = permission_ui
	%SelectPicoZip.visible = select_zip_ui
	%UnpackProgressContainer.visible = progress_ui

# Centralized permission denial handling
func handle_permission_denial():
	var f = FileAccess.open("user://dont-ask-for-storage", FileAccess.WRITE)
	f.close()
	check_for_files()

func get_pico_zip() -> Variant:
	if not has_storage_access():
		print("no storage permission, cannot check for existing pico zips")
		return null
	
	var public_folder = DirAccess.open(PUBLIC_FOLDER)
	if not public_folder:
		print("could not open public folder - trying to create it")
		DirAccess.make_dir_recursive_absolute(PUBLIC_FOLDER)
		public_folder = DirAccess.open(PUBLIC_FOLDER)
		if not public_folder:
			return null
	
	var valid_pico_zips = Array(public_folder.get_files()).filter(
		func(name): return "pico-8" in name and "raspi.zip" in name
	)
	
	if valid_pico_zips:
		valid_pico_zips.sort()
		var selected_zip = PUBLIC_FOLDER + "/" + valid_pico_zips[-1]
		print("found existing pico zip: ", selected_zip)
		return selected_zip
	
	print("no valid zips found")
	return null

var android_picker

func _ready() -> void:
	# Wait for the window to be fully initialized to avoid race conditions with focus events
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Force auto_show to false to prevent Arranger from overriding visibility
	%AllFileAccessContainer.auto_show = false
	%SelectPicoZip.auto_show = false
	%UnpackProgressContainer.auto_show = false
	
	if has_storage_access():
		check_for_files()
	else:
		request_storage_permission()

const BOOTSTRAP_PACKAGE_VERSION = "2"

func setup():
	set_ui_state(false, false, true) # permission_ui=false, select_zip_ui=false, progress_ui=true
	
	# Add warning if no storage permission
	if not has_storage_access():
		%UnpackProgress.text += "warning: all files access is disabled\n"

	var tar_path = APPDATA_FOLDER + "/package.tar.gz"
	var tar_path_godot = "user://package.tar.gz"
	var pico_path = APPDATA_FOLDER + "/pico8.zip"
	var pico_path_godot = "user://pico8.zip"
	
	DirAccess.make_dir_recursive_absolute(PUBLIC_FOLDER + "/logs")
	DirAccess.make_dir_recursive_absolute(PUBLIC_FOLDER + "/data/carts/.placeholder")
	var public_folder = DirAccess.open(PUBLIC_FOLDER)
	
	var DEBUG = OS.is_debug_build()
	
	#step 1: untar package
	var need_to_untar = DEBUG
	if not DEBUG:
		var f = FileAccess.open("user://package/package_version", FileAccess.READ)
		if f:
			pass
			var data = f.get_as_text().strip_edges()
			if data != BOOTSTRAP_PACKAGE_VERSION:
				need_to_untar = true
		else:
			need_to_untar = true
	print("need to untar: ", need_to_untar)
	if need_to_untar:
		%UnpackProgress.text += "extracting bootstrap package..."
		if get_tree():
			await get_tree().process_frame
		print( # for now just gonna assume this works
			"tar copy: ",
			error_string(public_folder.copy("res://package.dat", tar_path_godot))
		)
		
		OS.execute(
			BIN_PATH + "/sh",
			["-c", " ".join([
				BIN_PATH + "/tar",
				"-xzf", tar_path, "-C", APPDATA_FOLDER + "/",
				">" + PUBLIC_FOLDER + "/logs/tar_out.txt",
				"2>" + PUBLIC_FOLDER + "/logs/tar_err.txt"
			])]
		)

		%UnpackProgress.text += "done\n"
		if get_tree():
			await get_tree().process_frame
	
	var need_to_unzip = DEBUG
	if not DEBUG:
		if not FileAccess.file_exists("user://package/rootfs/home/pico/pico-8/pico8_64"):
			need_to_unzip = true
	print("need to unzip: ", need_to_unzip)
	if need_to_unzip:
		%UnpackProgress.text += "extracting pico-8 zip..."
		if get_tree():
			await get_tree().process_frame
		
		print(
			"pico zip copy: ",
			error_string(public_folder.copy(pico_zip_path, pico_path_godot))
		)
		OS.execute(
			BIN_PATH + "/sh",
			["-c", " ".join([
				"cd", APPDATA_FOLDER + "/package;",
				BIN_PATH + "/sh",
				"unzip-pico.sh",
				">" + PUBLIC_FOLDER + "/logs/zip_out.txt",
				"2>" + PUBLIC_FOLDER + "/logs/zip_err.txt"
			])]
		)
		
		%UnpackProgress.text += "done\n"
		if get_tree():
			await get_tree().process_frame
	if %UnpackProgress.text == "":
		%UnpackProgress.text = "no setup needed"
		if get_tree():
			await get_tree().process_frame
	
	# Setup is complete, go to main scene
	get_tree().change_scene_to_file("res://main.tscn")

var waiting_for_focus = false

func request_storage_permission():
	set_ui_state(true, false, false) # permission_ui=true, select_zip_ui=false, progress_ui=false
	%GrantButton.pressed.connect(grant_permission)
	%DenyButton.pressed.connect(handle_permission_denial)

func grant_permission():
	OS.request_permissions()
	waiting_for_focus = true

func _notification(what: int) -> void:
	if waiting_for_focus and what == NOTIFICATION_APPLICATION_FOCUS_IN:
		waiting_for_focus = false
		check_for_files()

func check_for_files():
	set_ui_state() # Hide all UIs first (all parameters default to false)
	
	var picozip = get_pico_zip()
	print("Pico zip: ", picozip)
	if picozip:
		pico_zip_path = picozip
		setup()
	else:
		set_ui_state(false, true, false) # permission_ui=false, select_zip_ui=true, progress_ui=false
		%OpenPickerButton.pressed.connect(open_picker)
		%Label.text = "pico8 zip not found"

func open_picker():
	if Engine.has_singleton("GodotFilePicker"):
		android_picker = Engine.get_singleton("GodotFilePicker")
		android_picker.file_picked.connect(picker_callback)
		android_picker.openFilePicker("application/zip")
	else:
		%Label.text = "no singleton"
	#var filters = PackedStringArray(["*.zip;ZIP Files;application/zip"])
	#var current_directory = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	#DisplayServer.file_dialog_show("title", current_directory, "filename", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, picker_callback)

#func picker_callback(status: bool, selected_paths: PackedStringArray, selected_filter_index: int):
	#if status:
		#check_pico_zip(selected_paths[0])
	#else:
		#%Label.text = "nothing selected"

func picker_callback(path: String, mime: String):
	check_pico_zip(path)

const REQUIRED_FILES = ["pico-8/pico8_64", "pico-8/pico8.dat", "pico-8/readme_raspi.txt"]

func check_pico_zip(path: String):
	var zipname = path.split("/")[-1]
	var zipper = ZIPReader.new()
	var err = zipper.open(path)
	if err != OK:
		%Label.text = "error reading: " + error_string(err).to_lower()
		return
	var files = zipper.get_files()
	for f in REQUIRED_FILES:
		if f not in files:
			%Label.text = zipname + ": not a pico-8 raspberry pi file"
			return
	%Label.text = "yep that's a pico pi file"
	
	var target_name = zipname
	if not ("pico-8" in zipname and "raspi.zip" in zipname):
		target_name = "pico-8_unknown_version_raspi.zip"
	
	# Ensure public folder exists
	OS.execute("/system/bin/mkdir", ["-p", PUBLIC_FOLDER])
	
	var target_path = PUBLIC_FOLDER + "/" + target_name
	print("copying ", path, " -> ", target_path)
	
	# Check if file already exists and try to remove it first
	if FileAccess.file_exists(target_path):
		print("target file already exists, attempting to remove it")
		var diraccess = DirAccess.open(PUBLIC_FOLDER)
		if diraccess:
			var remove_err = diraccess.remove(target_name)
			if remove_err != OK:
				%Label.text = "error removing existing file: " + error_string(remove_err).to_lower()
				return
			print("successfully removed existing file")
	
	var diraccess = DirAccess.open("user://")
	err = diraccess.copy(path, target_path)
	if err != OK:
		%Label.text = "error copying: " + error_string(err).to_lower()
		return
	
	check_for_files()
