class_name CharacterAbility
extends Node
## Base de todas las piezas modulares de un RagdollCharacter (habilidades y
## controladores). Se anaden como hijos directos del personaje y se ejecutan
## cada paso de fisica EN EL ORDEN DEL ARBOL, despues de que el nucleo detecte
## el suelo. Quitar el nodo = el personaje pierde esa habilidad.
##
## Para crear una habilidad nueva: extender esta clase, sobrescribir
## `physics_step()` (y `setup()` si necesita preparar algo) y anadir el nodo
## al personaje en el lugar adecuado del orden.

enum Side { LEFT = 0, RIGHT = 1 }

@export var enabled := true

var character: RagdollCharacter


## Se llama una vez, con el cuerpo ya construido.
func setup() -> void:
	pass


## Se llama cada paso de fisica si `enabled`.
func physics_step(_delta: float) -> void:
	pass


## Se llama al reaparecer: volver al estado inicial (soltar agarres, etc.).
func reset() -> void:
	pass


## Brazos: prioridad con la que esta habilidad quiere controlar el brazo `side`
## este paso (-1 = no lo quiere). El nodo Arms elige la mayor y llama a drive_arm.
func arm_claim_priority(_side: int) -> int:
	return -1


func drive_arm(_side: int, _delta: float) -> void:
	pass
