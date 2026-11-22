class_name OrbitCamera
extends Node3D
## Camara en tercera persona que sigue a un RagdollCharacter.
## El raton/stick derecho orbita; la direccion de la camara es tambien la
## direccion de apuntado de los brazos del personaje (como en Human Fall Flat).

@export var target_path: NodePath
@export var mouse_sensitivity := 0.0025
@export var joy_sensitivity := 2.6
@export var distance := 4.2
@export var height_offset := 0.55
@export var follow_speed := 10.0
@export var min_pitch := -1.25
@export var max_pitch := 1.05

var yaw := 0.0
var pitch := -0.2

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _cam: Camera3D = $SpringArm3D/Camera3D
var _target: RagdollCharacter
var _shake := 0.0


func _ready() -> void:
	add_to_group(&"orbit_camera")
	_target = get_node_or_null(target_path) as RagdollCharacter
	_arm.spring_length = distance
	_arm.collision_mask = 1  # solo el mundo, no props ni ragdolls
	yaw = global_rotation.y
	top_level = true
	if _target:
		global_position = _target.get_center() + Vector3.UP * height_offset
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_down", "look_up")
	yaw -= look.x * joy_sensitivity * delta
	pitch = clampf(pitch + look.y * joy_sensitivity * delta, min_pitch, max_pitch)

	if _target:
		var goal := _target.get_center() + Vector3.UP * height_offset
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	# sacudida de golpe
	_shake = maxf(0.0, _shake - delta * 0.6)
	_cam.h_offset = randf_range(-1.0, 1.0) * _shake
	_cam.v_offset = randf_range(-1.0, 1.0) * _shake


## Sacudir la camara (metros de desplazamiento maximo; se va calmando sola).
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 0.3)


func get_camera() -> Camera3D:
	return _cam
