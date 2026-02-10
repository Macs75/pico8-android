extends Node
class_name AudioStreamer

# Audio Settings
const MIX_RATE = 22050 # Optimized rate
const BUFFER_SIZE_SECONDS = 0.1
const TARGET_BUFFER_LENGTH = 0.1
const TCP_HOST = "127.0.0.1"
const TCP_PORT = 18081
const BYTES_PER_SAMPLE = 2 # 16-bit mono = 2 bytes * 1 channel
const READ_CHUNK_SIZE = 4096

var playback: AudioStreamGeneratorPlayback
var player: AudioStreamPlayer
var tcp: StreamPeerTCP
var connection_status: int = StreamPeerTCP.STATUS_NONE

var _buffer: PackedByteArray = PackedByteArray()

func _ready():
	_setup_audio()
	_connect_tcp()

func _setup_audio():
	player = AudioStreamPlayer.new()
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = BUFFER_SIZE_SECONDS
	player.stream = generator
	add_child(player)
	player.play()
	playback = player.get_stream_playback()

func _connect_tcp():
	tcp = StreamPeerTCP.new()
	print("AudioStreamer: Attempting connection to ", TCP_HOST, ":", TCP_PORT)
	var err = tcp.connect_to_host(TCP_HOST, TCP_PORT)
	if err != OK:
		print("AudioStreamer: Failed to connect to host. Error Code: ", err)
	else:
		print("AudioStreamer: Connection initiated...")

var last_connect_attempt_time = 0
const RECONNECT_DELAY_MS = 50 # Try every 50ms (20 times per second)

func _process(_delta):
	tcp.poll()
	var status = tcp.get_status()
	
	if status != connection_status:
		connection_status = status
		match status:
			StreamPeerTCP.STATUS_CONNECTING:
				# print("AudioStreamer: Connecting...")
				pass
			StreamPeerTCP.STATUS_CONNECTED:
				print("AudioStreamer: Connected!")
				tcp.set_no_delay(true)
			StreamPeerTCP.STATUS_ERROR:
				print("AudioStreamer: Connection Error!")
			StreamPeerTCP.STATUS_NONE:
				print("AudioStreamer: Disconnected.")

	if status == StreamPeerTCP.STATUS_CONNECTED:
		_read_data()
		_playback_audio()
	elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		var now = Time.get_ticks_msec()
		if now - last_connect_attempt_time > RECONNECT_DELAY_MS:
			last_connect_attempt_time = now
			_connect_tcp()

func _read_data():
	var available_bytes = tcp.get_available_bytes()
	if available_bytes > 0:
		var data = tcp.get_data(available_bytes)
		if data[0] == OK:
			var bytes = data[1]
			_buffer.append_array(bytes)
			
			# Latency Control: If buffer gets too big (more than 0.15s), drop oldest data
			# 0.15s * MIX_RATE * BYTES_PER_SAMPLE
			var max_buffer_bytes = int(0.15 * MIX_RATE * BYTES_PER_SAMPLE)
			if _buffer.size() > max_buffer_bytes:
				# Keep only the newest portion to catch up
				var keep_bytes = int(0.1 * MIX_RATE * BYTES_PER_SAMPLE)
				var drop_count = _buffer.size() - keep_bytes
				# Ensure alignment to sample size (2 bytes)
				drop_count = drop_count - (drop_count % BYTES_PER_SAMPLE)
				
				if drop_count > 0:
					_buffer = _buffer.slice(drop_count)
					# print("AudioStreamer: Dropped ", drop_count, " bytes to reduce latency")

func _playback_audio():
	if not playback: return
	
	var frames_available = playback.get_frames_available()
	if frames_available <= 0: return

	# Convert bytes to Vector2 frames
	# 1 frame = 2 bytes (1 sample) -> Stereo Output (Sample, Sample)
	
	# Only push if we have enough data (or push whatever we have?)
	var buffer_frames = int(_buffer.size() / BYTES_PER_SAMPLE)
	var push_count = min(buffer_frames, frames_available)
	
	if push_count > 0:
		#print("Pushing audio frames: ", push_count)
		var frames = PackedVector2Array()
		frames.resize(push_count)
		
		# Efficiently decode bytes to Audio Frames
		for i in range(push_count):
			var idx = i * 2 # 2 bytes per sample (Mono)
			# s16le decoding
			var sample_val = _buffer.decode_s16(idx)
			
			# Normalize short (-32768..32767) to float (-1.0..1.0)
			var val = sample_val / 32768.0
			
			# Create stereo frame from mono source
			frames[i] = Vector2(val, val)
			
		playback.push_buffer(frames)
		
		# Remove consumed bytes
		var consumed_bytes = push_count * BYTES_PER_SAMPLE
		_buffer = _buffer.slice(consumed_bytes)
