extends Node

@export var rect: Control

func _process(delta: float) -> void:
    var screensize := DisplayServer.window_get_size()
    var maxScale: int = max(1, floor(min(
        screensize.x / rect.size.x, screensize.y / rect.size.y
    )))
    self.scale = Vector2(maxScale, maxScale)
    var extraSpace = Vector2(screensize) - (rect.size * maxScale)
    self.position = Vector2i(Vector2(extraSpace.x / 2, extraSpace.y / 2) - rect.position * maxScale)
