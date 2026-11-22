class_name KnockoutAbility
extends CharacterAbility
## Fuerza muscular y KO (Gang Beasts): un golpe fuerte en la cabeza deja el
## cuerpo flacido (`strength` = 0) y luego se recupera solo. Q = dejarse caer.
## Dos formas de caer KO:
## - Puñetazos: cada golpe en la cabeza suma daño (segun su velocidad); al
##   llegar a `knockout_damage` cae KO. El daño se va curando con el tiempo.
## - Impacto muy fuerte en la cabeza (`knockout_speed`): KO directo.
## Sin este nodo el personaje siempre tiene fuerza 1 y no se le puede noquear.

@export var recover_time := 1.6           ## segundos en recuperar la fuerza tras un KO
@export var knockout_speed := 7.5         ## velocidad relativa de impacto en la cabeza que noquea
@export var knockout_duration := 3.0
@export var knockout_damage := 10.0       ## daño acumulado de puñetazos que noquea
@export var punch_min_speed := 1.5        ## golpes mas lentos no hacen daño
@export var damage_recovery := 1.0        ## daño que se cura por segundo
@export var punch_knockback := 2.5        ## impulso que recibe la cabeza al encajar un puñetazo
@export var recover_grace := 2.0          ## tras levantarse, segundos sin poder ser noqueado otra vez

signal hurt(damage: float, total: float)

var damage := 0.0
var _grace := 0.0

var _ko_timer := 0.0


func setup() -> void:
	var head := character.get_head()
	head.contact_monitor = true
	head.max_contacts_reported = 4
	head.body_entered.connect(_on_head_hit)


func physics_step(delta: float) -> void:
	var c := character
	damage = maxf(0.0, damage - damage_recovery * delta)
	_grace = maxf(0.0, _grace - delta)
	if _ko_timer > 0.0:
		_ko_timer -= delta
		c.strength = 0.0
		if _ko_timer <= 0.0:
			_grace = recover_grace
			c.recovered.emit()
		return
	var target := 0.0 if c.want_limp else 1.0
	c.strength = move_toward(c.strength, target, delta / maxf(recover_time, 0.01) if target > c.strength else delta * 8.0)


func knock_out(duration: float = -1.0) -> void:
	if _ko_timer <= 0.0:
		character.knocked_out.emit()
	damage = 0.0
	_ko_timer = maxf(_ko_timer, duration if duration > 0.0 else knockout_duration)
	character.release(Side.LEFT)
	character.release(Side.RIGHT)


func is_knocked_out() -> bool:
	return _ko_timer > 0.0


func reset() -> void:
	_ko_timer = 0.0
	_grace = 0.0
	damage = 0.0


func _on_head_hit(other: Node) -> void:
	if not enabled or _grace > 0.0:
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
		return
	if _ko_timer > 0.0 or rel < punch_min_speed or not _is_punch(other):
		return
	damage += rel
	hurt.emit(rel, damage)
	var push := other_vel
	push.y = 0.0
	if push.length_squared() > 1e-4:
		character.get_head().apply_central_impulse(push.normalized() * punch_knockback)
	if damage >= knockout_damage:
		knock_out()


## `other` es el brazo de otro personaje en pleno puñetazo.
func _is_punch(other: Node) -> bool:
	if not other.has_meta("ragdoll_owner"):
		return false
	var owner_char = other.get_meta("ragdoll_owner")
	if not (owner_char is RagdollCharacter):
		return false
	var combat := (owner_char as RagdollCharacter).get_ability(CombatAbility) as CombatAbility
	return combat != null and combat.is_punching_with(other)
