extends TextureRect

func send_ev(key: String, down: bool):
	PicoVideoStreamer.instance.vkb_setstate(key, down)

const center_offset = Vector2(5.5, 6)
const SHIFT = Vector2(10, 10)
const ORIGIN = Vector2(0, -1)

func constrain(ax: float, shift: float, origin: float):
	if ax <= origin+shift*0.5:
		return 0
	elif ax >= origin+shift*1.5:
		return 2
	else:
		return 1

var current_dir = Vector2i.ONE
func dir2keys(dir: Vector2i):
	var keys = []
	if dir.x == 0: keys.append("Left")
	if dir.x == 2: keys.append("Right")
	if dir.y == 0: keys.append("Up")
	if dir.y == 2: keys.append("Down")
	return keys
func update_dir(new_dir: Vector2i):
	if new_dir == current_dir:
		return
	var old_keys = dir2keys(current_dir)
	var new_keys = dir2keys(new_dir)
	for k in old_keys:
		if k not in new_keys:
			send_ev(k, false)
	for k in new_keys:
		if k not in old_keys:
			send_ev(k, true)
	current_dir = new_dir

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventScreenTouch:
		if event is InputEventScreenTouch and not event.pressed:
			update_dir(Vector2i.ONE)
			%Stick.position = ORIGIN + SHIFT
		else:
			var topleft: Vector2 = event.position - center_offset
			var dir := Vector2i(
				constrain(topleft.x, SHIFT.x, ORIGIN.x),
				constrain(topleft.y, SHIFT.y, ORIGIN.y),
			)
			update_dir(dir)
			var snapped = ORIGIN + Vector2(dir)*SHIFT
			%Stick.position = snapped + round(((topleft - snapped) / 10).limit_length(1))
	#if event is InputEventScreenTouch or event is InputEventMouseButton:
		#if event.pressed:
			#if key_state == KeyState.RELEASED:
				#if can_lock and (event.double_tap if (event is InputEventScreenTouch) else event.double_click):
					#key_state = KeyState.LOCKED
				#else:
					#key_state = KeyState.HELD
					#repeat_timer = Time.get_ticks_msec() + REPEAT_TIME_FIRST
				#send_ev(true)
			#elif key_state == KeyState.LOCKED:
				#key_state = KeyState.HELD
				#repeat_timer = INF
		#elif key_state == KeyState.HELD:
			#key_state = KeyState.RELEASED
			#send_ev(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		update_dir(Vector2i.ONE)
