extends Node2D
class_name PicoVideoStreamer

@export var loading: AnimatedSprite2D
@export var display: Sprite2D
@export var displayContainer: Sprite2D

var HOST = "192.168.0.42" if Engine.is_embedded_in_editor() else "127.0.0.1"
var PORT = 18080

var tcp: StreamPeerTCP

const PIDOT_EVENT_MOUSEEV = 1;
const PIDOT_EVENT_KEYEV = 2;
const PIDOT_EVENT_CHAREV = 3;

var last_message_time: int = 0
const TIMEOUT_TIME: int = 1000
func reconnect():
    tcp = StreamPeerTCP.new()
    var err = tcp.connect_to_host(HOST, PORT)
    if err != OK:
        print("Failed to start connection")
    last_message_time = Time.get_ticks_msec()

static var instance: PicoVideoStreamer
func _ready() -> void:
    instance = self
    reconnect()
    
    # Connect the single keyboard toggle button
    var keyboard_btn = get_node("Arranger/HBoxContainer/Keyboard Btn")
    if keyboard_btn:
        keyboard_btn.pressed.connect(_on_keyboard_toggle_pressed)
        # Set initial button label based on current state
        _update_keyboard_button_label()
    
    # Connect the haptic toggle button
    var haptic_btn = get_node("Arranger/HBoxContainer/Haptic Btn")
    if haptic_btn:
        haptic_btn.pressed.connect(_on_haptic_toggle_pressed)
        # Set initial button label based on current state
        _update_haptic_button_label()

var buffer := []
const SYNC_SEQ = [80, 73, 67, 79, 56, 83, 89, 78, 67] # "PICO8SYNC"
const CUSTOM_BYTE_COUNT = 1
var current_custom_data := range(CUSTOM_BYTE_COUNT)
const DISPLAY_BYTES = 128 * 128 * 3
const PACKLEN = len(SYNC_SEQ) + CUSTOM_BYTE_COUNT + DISPLAY_BYTES

func set_im_from_data(rgb: Array):
    #var rgb = []
    #for i in range(len(xrgb)*0.75):
        #var reali = (2 - (i % 3)) + floor(i/3)*4
        #rgb.append(xrgb[reali])
    var image = Image.create_from_data(128, 128, false, Image.FORMAT_RGB8, rgb)
    var texture = ImageTexture.create_from_image(image)
    display.texture = texture

func find_seq(host: Array, sub: Array):
    for i in range(len(host) - len(sub) + 1):
        var success = true
        for j in range(len(sub)):
            if host[i + j] != sub[j]:
                success = false
                break
        if success:
            return i
    return -1

var last_mouse_state = [0, 0, 0]

var synched = false

func _process(delta: float) -> void:
    if not (tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED):
        loading.visible = true
    if not tcp:
        print("reconnecting - random id %08x" % randi())
        reconnect()
        return
    if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
        tcp.poll()
    elif tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
        # mouse
        var screen_pos: Vector2i = (
            (get_viewport().get_mouse_position()
            - displayContainer.global_position)
            / displayContainer.global_scale
        )
        #if screen_pos != screen_pos.clampi(0, 127):
            #screen_pos = Vector2i(255, 0)
            
        if screen_pos == screen_pos.clampi(0, 127):
            var current_mouse_state = [screen_pos.x, screen_pos.y, Input.get_mouse_button_mask() & 0xff]
            if current_mouse_state != last_mouse_state:
                # and 
                tcp.put_data([
                    PIDOT_EVENT_MOUSEEV, current_mouse_state[0], current_mouse_state[1],
                    current_mouse_state[2], 0, 0, 0, 0
                ])
                last_mouse_state = current_mouse_state
        # recv screen
        if tcp.get_available_bytes() > 0:
            last_message_time = Time.get_ticks_msec()
            var errdata = tcp.get_data(tcp.get_available_bytes())
            var err = errdata[0]
            var data = errdata[1]
            buffer.append_array(data)
            if len(buffer) > PACKLEN * 2:
                print("buffer overloaded, skipping")
                var chopCount = floor((len(buffer) / PACKLEN)) - 1
                #print(chopCount)
                buffer = buffer.slice(chopCount * PACKLEN)
            if synched and len(buffer) > len(SYNC_SEQ) and buffer.slice(0, len(SYNC_SEQ)) != SYNC_SEQ:
                print("synch fail", buffer.slice(0, len(SYNC_SEQ)), SYNC_SEQ)
                synched = false
            if not synched:
                print("resynching")
                var syncpoint = find_seq(buffer, SYNC_SEQ)
                buffer = buffer.slice(syncpoint)
                synched = true
            var im
            if len(buffer) >= PACKLEN:
                current_custom_data = buffer.slice(
                    len(SYNC_SEQ),
                    len(SYNC_SEQ) + CUSTOM_BYTE_COUNT
                )
                im = buffer.slice(
                    len(SYNC_SEQ) + CUSTOM_BYTE_COUNT,
                    len(SYNC_SEQ) + CUSTOM_BYTE_COUNT + DISPLAY_BYTES
                )
                buffer = buffer.slice(PACKLEN)
            if im != null:
                #if find_seq(im, SYNC_SEQ) != -1:
                    #print("image has sync ", find_seq(im, SYNC_SEQ))
                    #print(im)
                    #DisplayServer.clipboard_set(str(im))
                    #breakpoint
                loading.visible = false
                set_im_from_data(im)
        elif Time.get_ticks_msec() - last_message_time > TIMEOUT_TIME:
            print("timeout detected")
            reconnect()
    else:
        print("connection failed")
        tcp = null
        
const SDL_KEYMAP: Dictionary = preload("res://sdl_keymap.json").data

func send_key(id: int, down: bool, repeat: bool, mod: int):
    if tcp:
        print("sending key ", id, " as ", down)
        tcp.put_data([
            PIDOT_EVENT_KEYEV,
            id, int(down), int(repeat),
            mod & 0xff, (mod >> 8) & 0xff, 0, 0
        ])
func send_input(char: int):
    if tcp:
        tcp.put_data([
            PIDOT_EVENT_CHAREV, char,
            0, 0, 0, 0, 0, 0
        ])

var held_keys = []


# Static variable to track haptic feedback state (default is true = haptic enabled)
static var haptic_enabled: bool = true

static func set_haptic_enabled(enabled: bool):
    haptic_enabled = enabled

static func get_haptic_enabled() -> bool:
    return haptic_enabled


func vkb_setstate(id: String, down: bool, unicode: int = 0, echo: bool = false):
    if id not in SDL_KEYMAP:
        return
    if (id not in held_keys) and not down:
        return
    if down:
        # Add haptic feedback for key presses (only on key down, not key up)
        if not echo and haptic_enabled:
            Input.vibrate_handheld(35, 1)

        if id not in held_keys:
            held_keys.append(id)
        send_key(SDL_KEYMAP[id], true, echo, keys2sdlmod(held_keys))
        if unicode and unicode < 256:
            send_input(unicode)
    else:
        held_keys.erase(id)
        send_key(SDL_KEYMAP[id], false, false, keys2sdlmod(held_keys))
    

func keymod2sdl(mod: int, key: int) -> int:
    var ret = 0
    if mod & KEY_MASK_SHIFT or key == KEY_SHIFT:
        ret |= 0x0001
    if mod & KEY_MASK_CTRL or key == KEY_CTRL:
        ret |= 0x0040
    if mod & KEY_MASK_ALT or key == KEY_ALT:
        ret |= 0x0100
    return ret

func keys2sdlmod(keys: Array) -> int:
    var ret = 0
    for key in keys:
        if key == "Shift":
            ret |= 0x0001
        if key == "Ctrl":
            ret |= 0x0040
        if key == "Alt":
            ret |= 0x0100
    return ret

func _input(event: InputEvent) -> void:
    #print(event)
    if event is InputEventKey:
        # because i keep doing this lolol
        if event.keycode == KEY_ALT:
            return
        var id = OS.get_keycode_string(event.keycode)
        if id in SDL_KEYMAP:
            send_key(SDL_KEYMAP[id], event.pressed, event.echo, keymod2sdl(event.get_modifiers_mask(), event.keycode if event.pressed else 0) | keys2sdlmod(held_keys))
        if event.unicode and event.unicode < 256 and event.pressed:
            send_input(event.unicode)
    #if not (tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED):
        #return;
    #if event is InputEventMouse:
        #queued_mouse_event = true

# Callback function for keyboard toggle button
func _on_keyboard_toggle_pressed():
    var current_state = KBMan.get_current_keyboard_type()
    var new_state = KBMan.KBType.FULL if current_state == KBMan.KBType.GAMING else KBMan.KBType.GAMING
    KBMan.set_full_keyboard_enabled(new_state == KBMan.KBType.FULL)
    _update_keyboard_button_label()

func _update_keyboard_button_label():
    var keyboard_btn = get_node("Arranger/HBoxContainer/Keyboard Btn")
    if not keyboard_btn:
        return
    var current_type = KBMan.get_current_keyboard_type()
    keyboard_btn.text = "fULL kEYBOARD" if current_type == KBMan.KBType.GAMING else "gAMING kEYBOARD"

# Callback function for haptic toggle button
func _on_haptic_toggle_pressed():
    var current_state = get_haptic_enabled()
    set_haptic_enabled(not current_state)
    _update_haptic_button_label()

func _update_haptic_button_label():
    var haptic_btn = get_node("Arranger/HBoxContainer/Haptic Btn")
    if not haptic_btn:
        return
    var current_state = get_haptic_enabled()
    haptic_btn.text = "hAPTIC: oN" if current_state else "hAPTIC: oFF"
