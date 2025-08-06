extends Node2D
class_name KBMan

enum KBType {GAMING, FULL}

@export var type: KBType = KBType.FULL

static func get_correct():
    var gaming = (
        PicoVideoStreamer.instance.current_custom_data[0] & 0x2
        and not PicoVideoStreamer.instance.current_custom_data[0] & 0x4
    )
    return (KBType.GAMING if gaming else KBType.FULL)

func _process(delta: float) -> void:
    var correct = get_correct()

    self.visible = (correct == type)
