extends SceneTree

# Default files to process if no arguments provided
const DEFAULT_FILES = [
	"F:/Dev/pico8-android/test-data/kalikan.p8.png",
	"F:/Dev/pico8-android/test-data/wip.pip.png"
]

func _init():
	print("--- Starting PICO-8 PNG Extraction ---")
	
	# Get command-line arguments
	# Note: Godot's --headless consumes the "--" separator, so we look for .png files directly
	var args = OS.get_cmdline_args()
	var files_to_process = []
	
	# Look for any .png files in arguments (skip first 2: godot exe and --script)
	var skip_next = false
	for i in range(args.size()):
		if skip_next:
			skip_next = false
			continue
		if args[i] == "--script":
			skip_next = true # Skip the script path
			continue
		if args[i].ends_with(".png"):
			# Convert relative path to absolute if needed
			var abs_path = args[i]
			if not abs_path.begins_with("/") and not abs_path.contains(":"):
				abs_path = ProjectSettings.globalize_path("res://" + abs_path)
			files_to_process.append(abs_path)
	
	# Use default files if no arguments provided
	if files_to_process.is_empty():
		print("No files specified, using defaults")
		files_to_process = DEFAULT_FILES
	else:
		print("Processing %d file(s) from arguments:" % files_to_process.size())
		for f in files_to_process:
			print("  - " + f)
	
	for path in files_to_process:
		process_file(path)
		
	print("--- Extraction Complete ---")
	quit()

func process_file(path):
	print("Processing: " + path)
	
	if not FileAccess.file_exists(path):
		print("Error: File not found: " + path)
		return

	var img = Image.load_from_file(path)
	if not img:
		print("Error: Failed to load image.")
		return
		
	# Ensure RGBA8 format for consistent byte access
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	
	var width = img.get_width()
	var height = img.get_height()
	var data = img.get_data()
	
	var total_pixels = width * height
	print("Image Size: %d x %d (%d pixels)" % [width, height, total_pixels])
	
	# Extract the data
	# Standard PICO-8 Cart: 160x205 = 32800 pixels.
	# Data size is usually 32768 bytes (0x8000), so the last few pixels are unused.
	# For custom lists (Splore), the image might be larger. We extract everything.
	
	var out_buffer = PackedByteArray()
	out_buffer.resize(total_pixels)
	
	# PICO-8 Steganography Extraction
	# Bit mapping (based on C analysis):
	# Bits 0-1: Blue  (data[2])
	# Bits 2-3: Green (data[1])
	# Bits 4-5: Red   (data[0]) 
	# Bits 6-7: Alpha (data[3])
	
	for i in range(total_pixels):
		var offset = i * 4
		var r = data[offset + 0] # Red
		var g = data[offset + 1] # Green
		var b = data[offset + 2] # Blue
		var a = data[offset + 3] # Alpha
		
		# Combine bits
		# Note: Godot's PackedByteArray uses generic bytes.
		# The C logic was: (G & 3) << 2 | (R & 3) << 4 | (B & 3) | (A & 3) << 6
		# Re-ordered for clarity:
		# (B & 3)       -> Bits 0-1
		# (G & 3) << 2  -> Bits 2-3
		# (R & 3) << 4  -> Bits 4-5
		# (A & 3) << 6  -> Bits 6-7 (In C code it was `pbVar6[3] << 6` which assumes lower 2 bits of alpha byte)
		
		var byte = (b & 0x03) | ((g & 0x03) << 2) | ((r & 0x03) << 4) | ((a & 0x03) << 6)
		out_buffer[i] = byte
	
	# Integrity Check (User Request)
	# Verify SHA1 hash at 0x8006-0x8019 against first 0x8000 bytes
	if out_buffer.size() >= 0x801A:
		var stored_hash = out_buffer.slice(0x8006, 0x801A)
		# Check if stored hash is all zeros (if so, skip check)
		var is_zero_hash = true
		for b in stored_hash:
			if b != 0:
				is_zero_hash = false
				break
		
		if not is_zero_hash:
			var data_to_hash = out_buffer.slice(0, 0x8000)
			var ctx = HashingContext.new()
			ctx.start(HashingContext.HASH_SHA1)
			ctx.update(data_to_hash)
			var calculated_hash = ctx.finish()
			
			if calculated_hash != stored_hash:
				print("Error: Cartridge integrity check failed (SHA1 mismatch)!")
				print("Calculated: " + calculated_hash.hex_encode())
				print("Stored:     " + stored_hash.hex_encode())
				return # Abort processing
			else:
				print("Integrity check passed (SHA1 match).")

	# Save raw extracted data
	var out_path = path + ".bin"
	var file = FileAccess.open(out_path, FileAccess.WRITE)
	if file:
		file.store_buffer(out_buffer)
		file.close()
		print("Saved raw data to: " + out_path)
	else:
		print("Error: Could not save to " + out_path)
		
	# Analysis for Standard Carts
	# Code starts at 0x4300 (17152).
	# Header check: 0x00 should be the start of GFX.
	# Standard cart signature is not always at 0x0.
	
	if total_pixels >= 0x8000:
		var split_point = 0x4300
		var ram_data = out_buffer.slice(0, split_point)
		var code_data = out_buffer.slice(split_point, 0x8000)
		
		# Save RAM (GFX, Map, SFX, Music)
		var ram_path = path + ".ram.bin"
		var f_ram = FileAccess.open(ram_path, FileAccess.WRITE)
		if f_ram:
			f_ram.store_buffer(ram_data)
			f_ram.close()
			print("Saved RAM (GFX/SFX) to: " + ram_path)
			
		# Check for Compression Header
		# Common PICO-8 compression header: ":c:" or 0x3a 0x63 0x3a
		# PXA header: 0x00 "pxa" or 0x00 0x70 0x78 0x61
		var code_header = code_data.slice(0, 4)
		var is_c_compressed = (code_header[0] == 0x3a and code_header[1] == 0x63 and code_header[2] == 0x3a and code_header[3] == 0x00)
		var is_pxa_compressed = (code_header[0] == 0x00 and code_header[1] == 0x70 and code_header[2] == 0x78 and code_header[3] == 0x61)
		
		var final_lua_code = PackedByteArray()
		
		# Debug info
		var header_str = code_data.slice(0, 8).hex_encode()
		print("Code Section Header (hex): " + header_str)

		if is_c_compressed:
			print("Detected Compressed Code (:c:)")
			final_lua_code = decompress_mini(code_data)
		elif is_pxa_compressed:
			print("Detected PXA Compressed Code (\\0pxa)")
			final_lua_code = decompress_pxa(code_data)
		else:
			print("Detected Raw Code")
			final_lua_code = code_data

		# Save Code as Text (UTF-8 Converted)
		var code_path = path + ".lua"
		var f_code = FileAccess.open(code_path, FileAccess.WRITE)
		if f_code:
			# Convert P8SCII (PackedByteArray) to UTF-8 String
			var utf8_code = pico8_to_utf8(final_lua_code)
			# Store as raw UTF-8 bytes to avoid encoding issues
			f_code.store_buffer(utf8_code.to_utf8_buffer())
			f_code.close()
			print("Saved Lua Code (UTF-8) to: " + code_path)
		
		# Extract label from PNG (128x128 region starting at offset 16,24)
		var label_data = extract_label_from_png(img)
		
		# Save complete P8 format
		var p8_path = path + ".p8"
		write_cart_to_p8(p8_path, ram_data, final_lua_code, label_data)
		print("Saved complete P8 cart to: " + p8_path)


func pico8_to_utf8(data: PackedByteArray) -> String:
	var res = ""
	
	# Complete PICO-8 character set (k_charset from pico_defs.py)
	# 0x00-0x1F: Control codes and special symbols
	var charset = [
		"", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "\t", "\n", "ᵇ", "ᶜ", "\r", "ᵉ", "ᶠ",
		"▮", "■", "□", "⁙", "⁘", "‖", "◀", "▶", "「", "」", "¥", "•", "、", "。", "゛", "゜"
	]
	
	# 0x20-0x7E: Standard ASCII printable characters (space through ~)
	for i in range(0x20, 0x7f):
		charset.append(char(i))
	
	# 0x7F:  special circle
	charset.append("○")
	
	# 0x80-0xFF: PICO-8 extended characters (128-255)
	# Icons, shapes, and Japanese hiragana/katakana
	var extended = [
		"█", "▒", "🐱", "⬇️", "░", "✽", "●", "♥", "☉", "웃", "⌂", "⬅️", "😐", "♪", "🅾️", "◆",
		"…", "➡️", "★", "⧗", "⬆️", "ˇ", "∧", "❎", "▤", "▥", "あ", "い", "う", "え", "お", "か",
		"き", "く", "け", "こ", "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と", "な", "に",
		"ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ま", "み", "む", "め", "も", "や", "ゆ", "よ",
		"ら", "り", "る", "れ", "ろ", "わ", "を", "ん", "っ", "ゃ", "ゅ", "ょ", "ア", "イ", "ウ", "エ",
		"オ", "カ", "キ", "ク", "ケ", "コ", "サ", "シ", "ス", "セ", "ソ", "タ", "チ", "ツ", "テ", "ト",
		"ナ", "ニ", "ヌ", "ネ", "ノ", "ハ", "ヒ", "フ", "ヘ", "ホ", "マ", "ミ", "ム", "メ", "モ", "ヤ",
		"ユ", "ヨ", "ラ", "リ", "ル", "レ", "ロ", "ワ", "ヲ", "ン", "ッ", "ャ", "ュ", "ョ", "◜", "◝"
	]
	charset.append_array(extended)
	
	# Ensure we have exactly 256 characters
	assert(charset.size() == 256, "PICO-8 charset must have 256 entries")
	
	# Decode each byte to corresponding P8 character
	for byte_val in data:
		res += charset[byte_val]
	
	return res


func decompress_mini(data: PackedByteArray) -> PackedByteArray:
	# Direct translation of shrinko8's old compression format decompressor
	# From pico_compress.py lines 105-138
	# Header: :c:\0 (4 bytes)
	# Size: 2 bytes (Big Endian) at offset 4
	# Compressed Data starts at offset 8
	var size_hi = data[4]
	var size_lo = data[5]
	var unc_size = (size_hi << 8) | size_lo
	
	print("Decompressed Size target: " + str(unc_size))
	
	# k_old_code_table from pico_compress.py lines 28-33
	# Note: Index 0 is empty string.
	var k_old_code_table = [
		"", "\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", # 0-12
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", # 13-25
		"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", # 26-38
		"!", "#", "%", "(", ")", "{", "}", "[", "]", "<", ">", # 39-49
		"+", "=", "/", "*", ":", ";", ".", ",", "~", "_" # 50-59
	]
	
	var code = PackedByteArray()
	var in_pos = 8 # Skip header (4) + size (2) + padding (2)
	
	while true:
		if in_pos >= data.size():
			break
			
		var ch = data[in_pos]
		in_pos += 1
		
		if ch == 0x00:
			if in_pos >= data.size():
				break
			var ch2 = data[in_pos]
			in_pos += 1
			if ch2 == 0x00:
				break # End of stream
			
			code.append(ch2)
		
		elif ch <= 0x3b: # 59 decimal
			# Lookup in k_old_code_table
			var s = k_old_code_table[ch]
			if s.length() > 0:
				code.append_array(s.to_ascii_buffer())
		
		else:
			# LZSS/LZ77 back-reference
			if in_pos >= data.size():
				break
			var ch2 = data[in_pos]
			in_pos += 1
			var count = (ch2 >> 4) + 2
			var offset = ((ch - 0x3c) << 4) + (ch2 & 0xf)
			
			# Copy from earlier in the output
			# Note: We must loop because the range matches source overlap semantics
			var start_idx = code.size() - offset
			for i in range(count):
				if start_idx + i < code.size():
					code.append(code[start_idx + i])
				else:
					code.append(0) # Should not happen
	
	return _clean_legacy_code(code)

func _clean_legacy_code(data: PackedByteArray) -> PackedByteArray:
	# Zepto8 Cleanup: Truncate at first null byte
	# PackedByteArray doesn't have find(), so we loop or search via converting to string?
	# Converting full array to string risks Unicode errors if high bits are used.
	# We'll just loop manually for 0. It's safe.
	var null_idx = -1
	for i in range(data.size()):
		if data[i] == 0:
			null_idx = i
			break
			
	if null_idx != -1:
		data = data.slice(0, null_idx)
	
	# Zepto8 Cleanup: Remove specific PICO-8 legacy shim garbage
	# Check last 150 bytes (junk is ~60 bytes)
	# The junk pattern is purely ASCII, so get_string_from_ascii is safe for checking the TAIL.
	var check_len = min(150, data.size())
	if check_len > 0:
		var tail = data.slice(data.size() - check_len).get_string_from_ascii()
		var regex = RegEx.new()
		regex.compile("if\\(_update60\\)_update=function\\(\\)_update60\\([)_update_buttons(]*\\)_update60\\(\\)end$")
		var match = regex.search(tail)
		if match:
			# Found junk at the end. Truncate.
			var junk_start_in_tail = match.get_start()
			var valid_len = data.size() - (tail.length() - junk_start_in_tail)
			data = data.slice(0, valid_len)
			
	return data


func decompress_pxa(data: PackedByteArray) -> PackedByteArray:
	var pxa = PxaReader.new(data)
	return pxa.decompress()

class PxaReader:
	var src_buf: PackedByteArray
	var src_pos: int = 0
	var bit: int = 1
	var out: PackedByteArray
	var mtf: PackedByteArray
	
	const PXA_MIN_BLOCK_LEN = 3
	const BLOCK_LEN_CHAIN_BITS = 3
	const TINY_LITERAL_BITS = 4
	
	func _init(data: PackedByteArray):
		src_buf = data
		mtf = []
		for i in range(256):
			mtf.append(i)
		
	func decompress() -> PackedByteArray:
		# Header: 8 bytes
		var header = []
		for i in range(8):
			header.append(src_buf[src_pos])
			src_pos += 1
		
		# Zepto8 Lines 206-207
		var raw_len = header[4] * 256 + header[5]
		var comp_len = header[6] * 256 + header[7]
		
		print("PXA Header: Raw Len: %d, Comp Len: %d" % [raw_len, comp_len])
		
		out = PackedByteArray()
		out.resize(raw_len)
		
		var dest_pos = 0
		src_pos = 8
		bit = 1
		
		while dest_pos < raw_len:
			# Zepto8 Line 227: if (get_bits(1))
			if get_bits(1) == 1:
				# Literal
				var nbits = 4
				# Zepto8 Line 230: while (get_bits(1)) ++nbits;
				while get_bits(1) == 1:
					nbits += 1
				
				# Zepto8 Line 232: int n = get_bits(nbits) + (1 << nbits) - 16;
				var n = get_bits(nbits) + (1 << nbits) - 16
				
				# Zepto8 Line 233: uint8_t ch = mtf.get(n);
				var ch = mtf[n]
				# Rotate to front
				mtf.remove_at(n)
				mtf.insert(0, ch)
				
				out[dest_pos] = ch
				dest_pos += 1
			else:
				# Block
				# Zepto8 Line 241: int nbits = get_bits(1) ? get_bits(1) ? 5 : 10 : 15;
				var nbits = 15
				if get_bits(1) == 1:
					if get_bits(1) == 1:
						nbits = 5
					else:
						nbits = 10
				
				# Zepto8 Line 242: int offset = get_bits(nbits) + 1;
				var offset = get_bits(nbits) + 1
				
				# Zepto8 Line 244: if (nbits == 10 && offset == 1)
				if nbits == 10 and offset == 1:
					# Raw Block
					var ch = get_bits(8)
					while ch != 0:
						out[dest_pos] = ch
						dest_pos += 1
						ch = get_bits(8)
				else:
					# LZSS Copy
					var length = 3
					# Zepto8 Line 259: do len += (n = get_bits(3)); while (n == 7);
					while true:
						var n = get_bits(3)
						length += n
						if n != 7:
							break
					
					var copy_src = dest_pos - offset
					for i in range(length):
						if dest_pos < raw_len:
							if copy_src + i >= 0:
								out[dest_pos] = out[copy_src + i]
							else:
								out[dest_pos] = 0 # Safety for invalid streams
							dest_pos += 1

		return out

	# Zepto8-compatible Bit Reader (LSB first for multi-bit values)
	func get_bits(count: int) -> int:
		var val = 0
		for i in range(count):
			if getbit() == 1:
				val |= (1 << i)
		return val

	func getbit() -> int:
		if src_pos >= src_buf.size():
			return 0
		var val = 1 if (src_buf[src_pos] & bit) != 0 else 0
		bit = bit << 1
		if bit == 256:
			bit = 1
			src_pos += 1
		return val

# PICO-8 P8 Format Export Functions
# Memory layout constants
const K_MEM_SPRITES_ADDR = 0x0000
const K_MEM_MAP_ADDR = 0x2000
const K_MEM_FLAG_ADDR = 0x3000
const K_MEM_MUSIC_ADDR = 0x3100
const K_MEM_SFX_ADDR = 0x3200

func extract_label_from_png(img: Image) -> Array:
	"""Extract 128x128 label image from PNG starting at offset 16,24"""
	var label = []
	var label_offset_x = 16
	var label_offset_y = 24
	var label_size = 128
	
	# Read pixels directly from the Image
	for y in range(label_size):
		var row = []
		for x in range(label_size):
			var pixel = img.get_pixel(label_offset_x + x, label_offset_y + y)
			# Convert pixel to RGB (0-255)
			var r = int(pixel.r * 255)
			var g = int(pixel.g * 255)
			var b = int(pixel.b * 255)
			# Map to PICO-8 palette index
			var color_idx = find_closest_pico8_color(r, g, b)
			row.append(color_idx)
		label.append(row)
	return label

func find_closest_pico8_color(r: int, g: int, b: int) -> int:
	"""Find PICO-8 palette color using 6-bit RGB (masking bottom 2 bits)"""
	# PICO-8 palette uses 6-bit RGB (values are multiples of 4)
	# Quantize to 6-bit by clearing bottom 2 bits
	var r6 = r & ~3
	var g6 = g & ~3
	var b6 = b & ~3
	
	# PICO-8 32-color palette (16 main + 16 alternate), RGB values in 6-bit
	const PALETTE_6BPP = [
		# Main 16 colors (0-15)
		[0x00, 0x00, 0x00], [0x1C, 0x28, 0x50], [0x7C, 0x24, 0x50], [0x00, 0x84, 0x50],
		[0xA8, 0x50, 0x34], [0x5C, 0x54, 0x4C], [0xC0, 0xC0, 0xC4], [0xFC, 0xF0, 0xE8],
		[0xFC, 0x00, 0x4C], [0xFC, 0xA0, 0x00], [0xFC, 0xEC, 0x24], [0x00, 0xE4, 0x34],
		[0x28, 0xAC, 0xFC], [0x80, 0x74, 0x9C], [0xFC, 0x74, 0xA8], [0xFC, 0xCC, 0xA8],
		# Alternate 16 colors (16-31) - quantized to 6-bit from shrinko8
		[0x28, 0x18, 0x14], [0x10, 0x1C, 0x34], [0x40, 0x20, 0x34], [0x10, 0x50, 0x58],
		[0x74, 0x2C, 0x28], [0x48, 0x30, 0x38], [0xA0, 0x88, 0x78], [0xF0, 0xEC, 0x7C],
		[0xBC, 0x10, 0x50], [0xFF, 0x6C, 0x24], [0xA8, 0xE4, 0x2C], [0x00, 0xB4, 0x40],
		[0x04, 0x58, 0xB4], [0x74, 0x44, 0x64], [0xFF, 0x6C, 0x58], [0xFF, 0x9C, 0x80]
	]
	
	# Try exact match first (for 6-bit quantized values)
	for i in range(32):
		if PALETTE_6BPP[i][0] == r6 and PALETTE_6BPP[i][1] == g6 and PALETTE_6BPP[i][2] == b6:
			return i
	
	# If no exact match, find nearest
	var best_idx = 0
	var best_dist = 999999
	
	for i in range(32):
		var dr = PALETTE_6BPP[i][0] - r6
		var dg = PALETTE_6BPP[i][1] - g6
		var db = PALETTE_6BPP[i][2] - b6
		var dist = dr * dr + dg * dg + db * db
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	
	return best_idx

func write_cart_to_p8(path: String, ram_data: PackedByteArray, lua_code: PackedByteArray, label_data: Array):
	"""Write a complete PICO-8 .p8 file with all sections"""
	var lines = []
	
	# Header
	lines.append("pico-8 cartridge // http://www.pico-8.com")
	lines.append("version 43")
	
	# __lua__ section - stored separately to write directly
	var utf8_code = pico8_to_utf8(lua_code)
	
	# __gfx__ section (sprites/graphics)
	var gfx_section = extract_gfx_section(ram_data)
	if gfx_section != "":
		lines.append("__gfx__")
		lines.append(gfx_section)
	
	# __label__ section (from PNG, not RAM)
	var label_section = extract_label_section(label_data)
	if label_section != "":
		lines.append("__label__")
		lines.append(label_section)
	
	# __gff__ section (sprite flags)
	var gff_section = extract_gff_section(ram_data)
	if gff_section != "":
		lines.append("__gff__")
		lines.append(gff_section)
	
	# __map__ section
	var map_section = extract_map_section(ram_data)
	if map_section != "":
		lines.append("__map__")
		lines.append(map_section)
	
	# __sfx__ section
	var sfx_section = extract_sfx_section(ram_data)
	if sfx_section != "":
		lines.append("__sfx__")
		lines.append(sfx_section)
	
	# __music__ section
	var music_section = extract_music_section(ram_data)
	if music_section != "":
		lines.append("__music__")
		lines.append(music_section)
	
	# Write to file with sections directly (lua_code already contains newlines)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		# Write header
		file.store_string(lines[0] + "\n") # "pico-8 cartridge..."
		file.store_string(lines[1] + "\n") # "version 43"
		file.store_string("\n")
		
		# Write __lua__ section header and code (code already has internal newlines)
		file.store_string("__lua__\n")
		file.store_string(utf8_code)
		file.store_string("\n")
		
		# Write remaining sections (starting from index 2 which is after version)
		for i in range(2, lines.size()):
			file.store_string(lines[i] + "\n")
		
		file.close()

func extract_gfx_section(ram_data: PackedByteArray) -> String:
	"""Extract __gfx__ section: 128x128 pixels, 4 bits per pixel"""
	var lines = []
	var last_non_empty = -1
	
	# GFX data is at 0x0000-0x2000 (8192 bytes)
	# Each byte contains 2 pixels (nybbles)
	# 128 pixels per row = 64 bytes per row
	# 128 rows total
	
	for y in range(128):
		var line = ""
		var row_offset = K_MEM_SPRITES_ADDR + y * 64
		var is_empty = true
		
		for x in range(128):
			var byte_offset = row_offset + (x >> 1)
			if byte_offset < ram_data.size():
				var byte_val = ram_data[byte_offset]
				var nybble = (byte_val >> ((x & 1) * 4)) & 0xF
				line += "%x" % nybble
				if nybble != 0:
					is_empty = false
			else:
				line += "0"
		
		lines.append(line)
		if not is_empty:
			last_non_empty = y
	
	# Return only up to last non-empty line
	if last_non_empty >= 0:
		return "\n".join(lines.slice(0, last_non_empty + 1))
	return ""

func extract_gff_section(ram_data: PackedByteArray) -> String:
	"""Extract __gff__ section: sprite flags, 2 rows of 128 bytes"""
	var lines = []
	var has_data = false
	
	# GFF data is at 0x3000-0x3100 (256 bytes)
	# 2 rows of 128 flags each
	
	for y in range(2):
		var line = ""
		var row_offset = K_MEM_FLAG_ADDR + y * 128
		
		for x in range(128):
			var byte_offset = row_offset + x
			if byte_offset < ram_data.size():
				var byte_val = ram_data[byte_offset]
				line += "%02x" % byte_val
				if byte_val != 0:
					has_data = true
			else:
				line += "00"
		
		lines.append(line)
	
	if has_data:
		# Trim trailing empty line if second row is all zeros
		if lines.size() == 2 and lines[1].replace("0", "") == "":
			lines.resize(1)
		return "\n".join(lines)
	return ""

func extract_label_section(label_data: Array) -> String:
	"""Extract __label__ section: 128x128 image using extended nybbles"""
	if label_data.size() == 0:
		return ""
	
	var lines = []
	var has_data = false
	
	# Label uses "extended nybbles": 0-15 = '0'-'f', 16-31 = 'g'-'v'
	for y in range(128):
		if y >= label_data.size():
			break
		var line = ""
		var row = label_data[y]
		for x in range(128):
			if x >= row.size():
				line += "0"
			else:
				var color_idx = row[x]
				if color_idx < 16:
					line += "%x" % color_idx
				else:
					# Extended nybble: 16='g', 17='h', ... 31='v'
					line += char(ord('g') + (color_idx - 16))
				if color_idx != 0:
					has_data = true
		lines.append(line)
	
	if has_data:
		return "\n".join(lines)
	return ""

func extract_map_section(ram_data: PackedByteArray) -> String:
	"""Extract __map__ section: up to 32 rows of 128 tiles"""
	var lines = []
	var last_non_empty = -1
	
	# Map data is at 0x2000-0x3000 (4096 bytes)
	# Usually only first 32 rows are used
	# Each tile is 1 byte, 128 tiles per row
	
	for y in range(32): # Check up to 32 rows (0x20) - standard map size
		var line = ""
		var row_offset = K_MEM_MAP_ADDR + y * 128
		var is_empty = true
		
		for x in range(128):
			var byte_offset = row_offset + x
			if byte_offset < ram_data.size():
				var byte_val = ram_data[byte_offset]
				line += "%02x" % byte_val
				if byte_val != 0:
					is_empty = false
			else:
				line += "00"
		
		lines.append(line)
		if not is_empty:
			last_non_empty = y
	
	# Return only up to last non-empty line
	if last_non_empty >= 0:
		return "\n".join(lines.slice(0, last_non_empty + 1))
	return ""

func extract_sfx_section(ram_data: PackedByteArray) -> String:
	"""Extract __sfx__ section: up to 64 sound effects"""
	var lines = []
	var last_non_default = -1
	
	# SFX data is at 0x3200-0x4300 (4352 bytes)
	# Each SFX is 68 bytes:
	#   - 4 bytes info (editor speed, loop start, loop end, mode)
	#   - 64 bytes notes (32 notes × 2 bytes)
	
	for sfx_idx in range(64):
		var sfx_offset = K_MEM_SFX_ADDR + sfx_idx * 68
		
		# Read 4 info bytes
		var info = ""
		for i in range(4):
			var byte_offset = sfx_offset + 64 + i
			if byte_offset < ram_data.size():
				info += "%02x" % ram_data[byte_offset]
			else:
				info += "00"
		
		# Read 32 notes (2 bytes each = 16 bits per note)
		# Encoded as 5 nybbles per note
		var notes = ""
		var is_default = true
		
		for note_idx in range(32):
			var note_offset = sfx_offset + note_idx * 2
			if note_offset + 1 < ram_data.size():
				var note_low = ram_data[note_offset]
				var note_high = ram_data[note_offset + 1]
				var note_val = note_low | (note_high << 8)
				
				# Decode note into 5 nybbles
				var pitch_low = note_val & 0xF
				var pitch_high = (note_val >> 4) & 0x3
				var waveform_low = (note_val >> 6) & 0x7
				var waveform_high = (note_val >> 15) & 0x1
				var volume = (note_val >> 9) & 0x7
				var effect = (note_val >> 12) & 0x7
				
				var waveform = waveform_low | (waveform_high << 3)
				
				notes += "%01x%01x%01x%01x%01x" % [pitch_high, pitch_low, waveform, volume, effect]
				
				if note_val != 0:
					is_default = false
			else:
				notes += "00000"
		
		# Check if this SFX is non-default
		var is_sfx_0 = (sfx_idx == 0 and info == "00010000")
		var is_other_default = (sfx_idx > 0 and info == "00100000")
		
		if not is_default or not (is_sfx_0 or is_other_default):
			last_non_default = sfx_idx
		
		lines.append(info + notes)
	
	# Return only up to last non-default SFX
	if last_non_default >= 0:
		return "\n".join(lines.slice(0, last_non_default + 1))
	return ""

func extract_music_section(ram_data: PackedByteArray) -> String:
	"""Extract __music__ section: up to 64 music patterns"""
	var lines = []
	var last_non_default = -1
	
	# Music data is at 0x3100-0x3200 (256 bytes)
	# Each pattern is 4 bytes (one per channel)
	# Each byte: bit 7 = loop flag, bits 0-6 = SFX number
	
	for pattern_idx in range(64):
		var pattern_offset = K_MEM_MUSIC_ADDR + pattern_idx * 4
		
		# Read 4 channel bytes
		var channels = []
		var flags_val = 0
		var is_default = true
		
		for ch in range(4):
			var byte_offset = pattern_offset + ch
			if byte_offset < ram_data.size():
				var ch_byte = ram_data[byte_offset]
				channels.append(ch_byte)
				
				# Extract loop flag (bit 7)
				if (ch_byte & 0x80) != 0:
					flags_val |= (1 << ch)
				
				# Check if not default (default is 0x41, 0x42, 0x43, 0x44)
				if ch_byte != (0x41 + ch):
					is_default = false
			else:
				channels.append(0x41 + ch)
		
		# Format: flags(2 hex) + space + 4 channel IDs (8 hex, 2 per channel, without high bit)
		var flags_str = "%02x" % flags_val
		var ids_str = ""
		for ch_byte in channels:
			ids_str += "%02x" % (ch_byte & 0x7F)
		
		var line = flags_str + " " + ids_str
		
		if not is_default:
			last_non_default = pattern_idx
		
		lines.append(line)
	
	# Return only up to last non-default pattern
	if last_non_default >= 0:
		return "\n".join(lines.slice(0, last_non_default + 1))
	return ""
