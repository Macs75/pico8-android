extends Node
class_name PicoBootManager

static var pico_zip_path: String = ""

# Static constants that can be accessed from other scripts
static var BIN_PATH = "/system/bin"
static var APPDATA_FOLDER = "/data/data/io.wip.pico8/files"
static var PUBLIC_FOLDER = "/sdcard/Documents/pico8"

static func sanitize_uri(uri: String) -> String:
	if not uri.begins_with("content://"):
		return uri
		
	var decoded = uri.uri_decode()
	
	# Handle specific Android External Storage Provider patterns
	# primary:FOLDER -> /storage/emulated/0/FOLDER
	if "primary:" in decoded:
		# Try to isolate the path part after primary:
		var parts = decoded.split("primary:")
		if parts.size() > 1:
			return "/storage/emulated/0/" + parts[1]
			
	# Handle secondary storage volumes (SD Cards)
	# Pattern: .../tree/VOLUME_ID:PATH -> /storage/VOLUME_ID/PATH
	# Example: .../tree/55F21F50-17268D46:ROMs/pico8/.multicarts
	if ":" in decoded and "/tree/" in decoded:
		# This handles split UUIDs or simple IDs before the colon
		# We need to extract the ID before the last colon that acts as separator
		# Typical format: .../tree/<uuid>:<path>
		var tree_marker = "/tree/"
		var tree_idx = decoded.find(tree_marker)
		if tree_idx != -1:
			var relative_part = decoded.substr(tree_idx + tree_marker.length())
			# relative_part might be "55F21F50-17268D46:ROMs/pico8/..."
			# Split by FIRST colon
			var colon_idx = relative_part.find(":")
			if colon_idx != -1:
				var vol_id = relative_part.substr(0, colon_idx)
				var path = relative_part.substr(colon_idx + 1)
				return "/storage/" + vol_id + "/" + path

	# Handle general content:// to file:// cloaking (triple encoded sometimes)
	if "file%3A" in decoded or "http%3A" in decoded:
		decoded = decoded.uri_decode()
	
	decoded = decoded.uri_decode() # One more time to be safe?
	
	if "file://" in decoded:
		var parts = decoded.split("file://")
		return parts[parts.size() - 1]
		
	return decoded

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

const BOOTSTRAP_PACKAGE_VERSION = "13"

func setup():
	set_ui_state(false, false, true) # permission_ui=false, select_zip_ui=false, progress_ui=true
	
	# Add warning if no storage permission
	if not has_storage_access():
		%UnpackProgress.text += "warning: all files access is disabled\n"

	var tar_path = APPDATA_FOLDER + "/package.tar.gz"
	var tar_path_godot = "user://package.tar.gz"
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
		%UnpackProgress.text += "cleaning up old package...\n"
		if get_tree():
			await get_tree().process_frame
		
		# Remove old package folder to prevent stale files (like tmp/pulse) from interfering
		var package_folder = APPDATA_FOLDER + "/package"
		print("Removing old package folder: ", package_folder)
		OS.execute(BIN_PATH + "/rm", ["-rf", package_folder])
		
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
	
		# Copy shaders to public folder
		copy_shaders_to_public_folder()
	
		# Copy other assets (bezel, etc)
		copy_assets_to_public_folder()
	
	# Enforce Audio Backend Selection
	# Copy the correct pulse.pa based on settings
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	var audio_backend = "sles"
	if err == OK:
		audio_backend = config.get_value("settings", "audio_backend", "sles")
	
	print("Enforcing Audio Backend: ", audio_backend)
	var g_source = "user://package/pulse.pa." + audio_backend
	var g_target = "user://package/pulse.pa"
	
	if FileAccess.file_exists(g_source):
		var dir = DirAccess.open("user://package")
		if dir:
			dir.copy(g_source, g_target)
			print("Copied ", g_source, " to ", g_target)
	else:
		print("Audio backend template not found: ", g_source)

	
	# Load custom SDL mappings
	load_sdl_mappings()

	# Setup is complete, go to main scene
	get_tree().change_scene_to_file("res://main.tscn")

func load_sdl_mappings():
	var mapping_file = PUBLIC_FOLDER + "/pico8_sdl_controllers.txt"
	if FileAccess.file_exists(mapping_file):
		print("Loading SDL mappings from: ", mapping_file)
		var f = FileAccess.open(mapping_file, FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line = f.get_line().strip_edges()
				if line.begins_with("#") or line == "":
					continue
				# Basic validation: SDL strings typically have commas
				if "," in line:
					Input.add_joy_mapping(line, true)
					print("Applied mapping: ", line)
			f.close()
	else:
		print("No external SDL mapping file found at: ", mapping_file)

func copy_assets_to_public_folder():
	# 1. Default Bezel
	var bezel_target = PUBLIC_FOLDER + "/bezel.png"
	if not FileAccess.file_exists(bezel_target):
		var src_path = "res://assets/bezel.png"
		print("Attempting to load default bezel resource: ", src_path)
		
		# Use load() instead of FileAccess because exported assets are packed
		if ResourceLoader.exists(src_path):
			var texture = load(src_path)
			if texture and texture is Texture2D:
				var image = texture.get_image()
				if image:
					var err = image.save_png(bezel_target)
					if err == OK:
						print("Successfully exported default bezel to: ", bezel_target)
					else:
						print("Failed to save bezel png: ", error_string(err))
				else:
					print("Failed to get image data from texture")
			else:
				print("Failed to load texture resource")
		else:
			print("Default bezel resource not found at: ", src_path)
	else:
		print("Bezel already exists, skipping default copy.")


func copy_shaders_to_public_folder():
	var shader_dir = PUBLIC_FOLDER + "/shaders"
	DirAccess.make_dir_recursive_absolute(shader_dir)
	
	# List of shaders to copy
	var shaders = [
		"retro_v2.gdshader",
		"retro_v3.gdshader",
		"dot_matrix.gdshader",
		"lcd_gbc.gdshader",
		"lcd_transparency.gdshader",
		"crt_1tap.gdshader",
		"crt_aperture.gdshader",
		"crt_hyllian.gdshader",
		"hue_shift.gdshader",
		"lcd3x.gdshader",
		"zfast_crt.gdshader"
	]
	
	# Always overwrite base shaders (users modify .custom files)
	for shader_name in shaders:
		var src_path = "res://shaders/" + shader_name
		var dst_path = shader_dir + "/" + shader_name
		
		if FileAccess.file_exists(src_path):
			var shader_code = FileAccess.get_file_as_string(src_path)
			
			# Prepend warning header
			var warning = """/*
 * ⚠️ WARNING: THIS FILE WILL BE OVERWRITTEN ON APP UPDATES! ⚠️
 * 
 * To customize this shader:
 * 1. Copy this file
 * 2. Rename it to: %s
 * 3. Edit the .custom file instead
 * 
 * The app loads .custom files with priority, so your changes
 * will be preserved across updates.
 */

""" % shader_name.replace(".gdshader", ".custom.gdshader")
			
			var final_content = warning + shader_code
			
			var dst_file = FileAccess.open(dst_path, FileAccess.WRITE)
			if dst_file:
				dst_file.store_string(final_content)
				dst_file.close()
	
	# Create README if it doesn't exist
	var readme_path = shader_dir + "/README.txt"
	if not FileAccess.file_exists(readme_path):
		var readme_content = """To customize a shader:
1. Copy the shader file (e.g., crt_aperture.gdshader)
2. Rename it with .custom suffix (e.g., crt_aperture.custom.gdshader)
3. Edit the .custom file with a text editor
4. Changes apply immediately when you switch shaders!

The app will load .custom versions if they exist, otherwise use the base shader.
If you break a shader, just delete the .custom file to reset to default.

Shader files are located in: /sdcard/Documents/pico8/shaders/
Error logs are saved to: /sdcard/Documents/pico8/logs/shader_errors.log
"""
		var readme_file = FileAccess.open(readme_path, FileAccess.WRITE)
		if readme_file:
			readme_file.store_string(readme_content)
			readme_file.close()
	
	print("Shaders copied to: ", shader_dir)

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
