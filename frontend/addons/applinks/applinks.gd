extends Node

signal data_received(data: String)

const CUSTOM_MANIFEST_ACTIVITY_ELEMENT = '''

	<!-- Strategy: Share Link and Share Image -->
	<intent-filter>
		<action android:name="android.intent.action.SEND" />
		<category android:name="android.intent.category.DEFAULT" />
		<data android:mimeType="application/octet-stream" />
		<data android:mimeType="application/pkcs8" />
		<data android:mimeType="text/plain" />
		<data android:mimeType="image/png" />
		<data android:pathPattern=".*\\.p8\\.png" />
		<data android:pathPattern=".*\\.p8" />
		<data android:pathSuffix=".p8.png" />
		<data android:pathSuffix=".p8" />
	</intent-filter>

	<!-- Strategy: Deep Links (Lexaloffle BBS) -->
	<intent-filter>
		<action android:name="android.intent.action.VIEW" />
		<category android:name="android.intent.category.DEFAULT" />
		<category android:name="android.intent.category.BROWSABLE" />
		<data android:scheme="https" android:host="www.lexaloffle.com" />
		<data android:scheme="https" android:host="lexaloffle.com" />
		<data android:pathPattern=".*\\.p8\\.png" />
		<data android:pathPattern=".*\\.p8" />
		<data android:pathSuffix=".p8.png" />
		<data android:pathSuffix=".p8" />
	</intent-filter>
	
	<!-- Strategy: File Handling (Downloads/Local)-->
	<intent-filter>
		<action android:name="android.intent.action.VIEW" />
		<category android:name="android.intent.category.DEFAULT" />
		<category android:name="android.intent.category.BROWSABLE" />
		<category android:name="android.intent.category.OPENABLE" />
		<data android:scheme="file" />
		<data android:scheme="content" />
		<data android:mimeType="application/octet-stream" />
		<data android:mimeType="application/pkcs8" />
		<data android:mimeType="text/plain" />
		<data android:mimeType="image/png" />
		<data android:pathPattern=".*\\.p8\\.png" />
		<data android:pathPattern=".*\\.p8" />
		<data android:pathSuffix=".p8.png" />
		<data android:pathSuffix=".p8" />
	</intent-filter>
'''
const SINGLETON_NAME = "Applinks"
const PLUGIN_NAME = "applinks"

var applinks

func _ready() -> void:
	if Engine.has_singleton(PLUGIN_NAME):
		applinks = Engine.get_singleton(PLUGIN_NAME)
		applinks.connect("audio_route_changed", _on_audio_route_changed)
		var is_connected = applinks.isExternalAudioConnected()
		_on_audio_route_changed(is_connected, "initial")
	elif OS.has_feature("android"):
		printerr("Couldn't find plugin " + PLUGIN_NAME)


var last_data = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and OS.has_feature("android"):
		var url := get_data()
		if not url.is_empty() and url != last_data:
			last_data = url
			data_received.emit(url)


func get_data() -> String:
	if applinks == null:
		printerr("Couldn't find plugin " + PLUGIN_NAME)
		return ""
	var data = applinks.getData();
	return data if data != null else ""

func open_app_settings() -> void:
	if applinks:
		applinks.open_app_settings()
	else:
		printerr("Applinks singleton is null")

func _on_audio_route_changed(is_external: bool, device_name: String = ""):
	if is_external:
		print("Audio output switched to Headphones/Bluetooth: ", device_name)
	else:
		print("Audio output switched to System Speakers")
