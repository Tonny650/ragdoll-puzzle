class_name KnockoutAbility
extends CharacterAbility
## Fuerza muscular y KO (Gang Beasts): un golpe fuerte en la cabeza deja el
## cuerpo flacido (`strength` = 0) y luego se recupera solo. Q = dejarse caer.
## Sin este nodo el personaje siempre tiene fuerza 1 y no se le puede noquear.

@export var recover_time := 1.6           ## segundos en recuperar la fuerza tras un KO
@export var knockout_speed := 7.5         ## velocidad relativa de impacto en la cabeza que noquea
@export var knockout_duration := 3.0

var _ko_timer := 0.0


func setup() -> void:
	var head := character.get_head()
	head.contact_monitor = true
	head.max_contacts_reported = 4
	head.body_entered.connect(_on_head_hit)


func physics_step(delta: float) -> void:
	var c := character
	if _ko_timer > 0.0:
		_ko_timer -= delta
		c.strength = 0.0
		if _ko_timer <= 0.0:
			c.recovered.emit()
		return
	var target := 0.0 if c.want_limp else 1.0
	c.strength = move_toward(c.strength, target, delta / maxf(recover_time, 0.01) if target > c.strength else delta * 8.0)


func knock_out(duration: float = -1.0) -> void:
	if _ko_timer <= 0.0:
		character.knocked_out.emit()
	_ko_timer = maxf(_ko_timer, duration if duration > 0.0 else knockout_duration)
	character.release(Side.LEFT)
	character.release(Side.RIGHT)


func is_knocked_out() -> bool:
	return _ko_timer > 0.0


func reset() -> void:
	_ko_timer = 0.0


func _on_head_hit(other: Node) -> void:
	if not enabled:
		return
	if other.has_meta("ragdoll_owner") and other.get_meta("ragdoll_owner") == character:
		return
	var other_vel := Vector3.ZERO
	if other is RigidBody3D:
		other_vel = (other as RigidBody3D).linear_velocity
	elif other.has_method("get_platform_velocity"):
		other_vel = other.get_platform_velocity()
	var rel := (character.get_head().linear_velocity - other_vel).length()
	if rel >= knockout_speed:
		knock_out()
