@tool
extends EditorPlugin

const applinks_script_path = "res://addons/applinks/applinks.gd"
const applinks_script = preload(applinks_script_path)

# A class member to hold the editor export plugin during its lifecycle.
var export_plugin : AndroidExportPlugin

func _enter_tree():
	# Initialization of the plugin goes here.
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)
	add_autoload_singleton(applinks_script.SINGLETON_NAME, applinks_script_path)


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_autoload_singleton(applinks_script.SINGLETON_NAME)
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	# TODO: Update to your plugin's name.
	var _plugin_name = "applinks"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false


	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		else:
			return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])


	func _get_android_manifest_activity_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		return applinks_script.CUSTOM_MANIFEST_ACTIVITY_ELEMENT


	func _get_name():
		return applinks_script.PLUGIN_NAME
