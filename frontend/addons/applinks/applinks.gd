extends Node

signal data_received(data: String)

const CUSTOM_MANIFEST_ACTIVITY_ELEMENT = '''

	<!-- Strategy: Share Link and Share Image -->
	<!-- PICO-8 PNG Carts Share -->
	<intent-filter>
		<action android:name="android.intent.action.SEND" />
		<category android:name="android.intent.category.DEFAULT" />
		<data android:mimeType="image/png" />
		<data android:mimeType="application/octet-stream" />
		<data android:pathPattern=".*\\.p8\\.png" />
		<data android:pathSuffix=".p8.png" />
	</intent-filter>

	<!-- PICO-8 Text/Blob Carts Share -->
	<intent-filter>
		<action android:name="android.intent.action.SEND" />
		<category android:name="android.intent.category.DEFAULT" />
		<data android:mimeType="text/plain" />
		<data android:mimeType="application/pkcs8" />
		<data android:mimeType="application/octet-stream" />
		<data android:pathPattern=".*\\.p8" />
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
	<!-- PICO-8 PNG Carts View -->
	<intent-filter>
		<action android:name="android.intent.action.VIEW" />
		<category android:name="android.intent.category.DEFAULT" />
		<category android:name="android.intent.category.BROWSABLE" />
		<category android:name="android.intent.category.OPENABLE" />
		<data android:scheme="file" android:host="*" />
		<data android:scheme="content" android:host="*" />
		<data android:mimeType="image/png" />
		<data android:mimeType="application/octet-stream" />
		<data android:pathPattern=".*\\.p8\\.png" />
		<data android:pathSuffix=".p8.png" />
	</intent-filter>

	<!-- PICO-8 Text/Blob Carts View -->
	<intent-filter>
		<action android:name="android.intent.action.VIEW" />
		<category android:name="android.intent.category.DEFAULT" />
		<category android:name="android.intent.category.BROWSABLE" />
		<category android:name="android.intent.category.OPENABLE" />
		<data android:scheme="file" android:host="*" />
		<data android:scheme="content" android:host="*" />
		<data android:mimeType="text/plain" />
		<data android:mimeType="application/pkcs8" />
		<data android:mimeType="application/octet-stream" />
		<data android:pathPattern=".*\\.p8" />
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

# Pipe Wrappers (Native Plugin)
func pipe_open(path: String, mode: int) -> int:
	if applinks:
		return applinks.pipe_open(path, mode)
	return -1

func pipe_read(id: int, length: int) -> PackedByteArray:
	if applinks:
		return applinks.pipe_read(id, length)
	return PackedByteArray()

func pipe_write(id: int, data: PackedByteArray) -> bool:
	if applinks:
		return applinks.pipe_write(id, data)
	return false

func pipe_close(id: int) -> void:
	if applinks:
		applinks.pipe_close(id)

func create_shortcut(label: String, cart_path: String) -> void:
	if applinks:
		applinks.create_shortcut(label, cart_path)
