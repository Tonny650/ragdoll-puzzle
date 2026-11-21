extends CanvasLayer
## HUD minimo: controles y mensajes.

@onready var _msg: Label = $Message
var _timer := 0.0


func show_message(text: String) -> void:
	_msg.text = text
	_msg.visible = true
	_timer = 4.0


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_msg.visible = false
