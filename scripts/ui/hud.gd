extends CanvasLayer
## HUD minimo: controles, mensajes y, en red, jugadores conectados y ping.

@onready var _msg: Label = $Message
var _timer := 0.0
var _net_label: Label


func _ready() -> void:
	if Net.is_online():
		_net_label = Label.new()
		_net_label.anchor_left = 1.0
		_net_label.anchor_right = 1.0
		_net_label.offset_left = -420
		_net_label.offset_right = -16
		_net_label.offset_top = 8
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_net_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_net_label.add_theme_constant_override("outline_size", 6)
		add_child(_net_label)
	Net.session_ended.connect(_on_session_ended)


func show_message(text: String) -> void:
	_msg.text = text
	_msg.visible = true
	_timer = 4.0


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_msg.visible = false
	if _net_label:
		var sp := get_parent().get_node_or_null("PlayerSpawner") as PlayerSpawner
		var n := sp.peer_count() if sp else 1
		if Net.is_host():
			_net_label.text = "Anfitrion · %d jugador(es)" % n
		else:
			_net_label.text = "Conectado · %d jugador(es) · ping %d ms" % [n, Net.ping_ms()]


func _on_session_ended(reason: String) -> void:
	# volver al menu con el motivo
	MainMenu.pending_message = reason
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu.tscn")
