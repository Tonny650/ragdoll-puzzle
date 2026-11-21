class_name PressurePlate
extends Area3D
## Placa de presion: se activa cuando la masa de los objetos (capa "props") encima
## supera `required_mass`. El personaje no cuenta: hay que llevar una caja.

signal activated
signal deactivated

@export var required_mass := 8.0
@export var plate_mesh_path: NodePath
@export var idle_color := Color(0.85, 0.2, 0.15)
@export var active_color := Color(0.2, 0.85, 0.3)

var is_active := false
var _mat: StandardMaterial3D
var _plate: Node3D
var _rest_y := 0.0


func _ready() -> void:
	_plate = get_node_or_null(plate_mesh_path) as Node3D
	if _plate is MeshInstance3D:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = idle_color
		(_plate as MeshInstance3D).material_override = _mat
		_rest_y = _plate.position.y


func _physics_process(_delta: float) -> void:
	var mass := 0.0
	for b in get_overlapping_bodies():
		if b is RigidBody3D:
			mass += (b as RigidBody3D).mass
	var now := mass >= required_mass
	if now != is_active:
		is_active = now
		if _mat:
			_mat.albedo_color = active_color if now else idle_color
		if _plate:
			_plate.position.y = _rest_y - (0.04 if now else 0.0)
		if now:
			activated.emit()
		else:
			deactivated.emit()
