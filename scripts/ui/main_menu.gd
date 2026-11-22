class_name MainMenu
extends Control
## Menu principal: hospedar partida, unirse por IP o jugar solo.
## Atajos por linea de comandos (tras `--`): --host, --join=IP, --port=N, --solo.

const LEVEL := "res://scenes/levels/test_arena.tscn"

static var pending_message := ""   ## motivo de volver al menu (desconexion...)

var _ip: LineEdit
var _port: SpinBox
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	if pending_message != "":
		_status.text = pending_message
		pending_message = ""
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	var args := Net.cmdline()
	if args.has("port"):
		_port.value = int(args.port)
	if args.has("host"):
		_host.call_deferred()
	elif args.has("join"):
		if args.join != "":
			_ip.text = args.join
		_join.call_deferred()
	elif args.has("solo"):
		_solo.call_deferred()


func _host() -> void:
	if Net.host(int(_port.value)) != OK:
		_status.text = Net.last_error
		return
	get_tree().change_scene_to_file(LEVEL)


func _join() -> void:
	var ip := _ip.text.strip_edges()
	if ip == "":
		_status.text = "Escribe la IP del anfitrion."
		return
	if Net.join(ip, int(_port.value)) != OK:
		_status.text = Net.last_error
		return
	_status.text = "Conectando con %s:%d..." % [ip, int(_port.value)]
	_set_busy(true)


func _solo() -> void:
	Net.leave()
	get_tree().change_scene_to_file(LEVEL)


func _on_connected() -> void:
	get_tree().change_scene_to_file(LEVEL)


func _on_failed(reason: String) -> void:
	_status.text = reason
	_set_busy(false)


func _set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.13, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Ragdoll Puzzle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	var row := HBoxContainer.new()
	var ip_label := Label.new()
	ip_label.text = "IP"
	row.add_child(ip_label)
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "IP del anfitrion"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip)
	var port_label := Label.new()
	port_label.text = "Puerto"
	row.add_child(port_label)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Net.DEFAULT_PORT
	row.add_child(_port)
	box.add_child(row)

	_add_button(box, "Hospedar partida", _host)
	_add_button(box, "Unirse", _join)
	_add_button(box, "Jugar solo", _solo)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	box.add_child(_status)

	var hint := Label.new()
	hint.text = "Para jugar por Internet, quien hospeda debe abrir el puerto UDP\n(o usar una red tipo Tailscale / ZeroTier / Radmin VPN)."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons.append(b)
