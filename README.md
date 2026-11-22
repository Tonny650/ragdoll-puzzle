# Ragdoll Puzzle

Prototipo de **controlador de personaje ragdoll activo** para un juego **cooperativo en línea** de puzles
físicos, inspirado en el *feeling* de Human Fall Flat y Gang Beasts. Hecho en **Godot 4.7** (GDScript, Jolt Physics)
con personajes modelados por script en **Blender**.

![escena de pruebas](docs/screenshot.png)

## Cómo ejecutar

1. Abre la carpeta con Godot 4.7+ (estándar o .NET).
2. Pulsa **F5**: arranca el menú (`scenes/ui/main_menu.tscn`): **Hospedar partida**, **Unirse** (IP + puerto)
   o **Jugar solo**. El nivel es `scenes/levels/test_arena.tscn`.

Atajos por línea de comandos (tras `--`): `--host`, `--join=IP`, `--port=N`, `--solo`, y para probar con
mala conexión `--lag=MS` (retraso añadido) y `--loss=0.05` (pérdida de paquetes). Dos ventanas en el mismo PC:

```bash
godot --path . -- --host
godot --path . -- --join=127.0.0.1
```

## Multijugador en línea (`scripts/net/`)

Modelo de **anfitrión autoritativo** (como Human Fall Flat): solo el PC que hospeda simula la física; los
demás envían lo que quieren hacer y dibujan lo que el anfitrión les manda.

- `Net` (autoload): hospedar / unirse / salir con `ENetMultiplayerPeer` (UDP, puerto 7777), hasta 4 jugadores,
  ping, retraso y pérdida simulados. Sin sesión el juego funciona igual que en un jugador.
- `NetIntent`: la intención de un jugador (movimiento, cámara, agarres, salto, flácido y contadores de
  puñetazo / reaparición). `PlayerInputController.read_intent()` la lee del teclado/mando; en un cliente se
  envía al anfitrión 60 veces/s y allí la aplica `NetInputController`.
- `PlayerSpawner` (en el nivel): el `Player` de la escena es siempre el del anfitrión; por cada jugador que
  entra crea `Player_<id>` en el siguiente punto libre, con etiqueta J1..J4 de su color. La cámara de cada PC
  sigue a su propio personaje.
- `NetSync` (en el nivel): 30 instantáneas/s con posición y rotación de todos los cuerpos (piezas de cada
  personaje y nodos del grupo `net_body`: cajas, pelotas, balancín, puerta, ascensor, aspa). En los clientes
  esos cuerpos están congelados y se dibujan 100 ms por detrás interpolando entre instantáneas. También
  reparte eventos: chispas de golpes, placa de presión (`net_state`) y la meta.
- Para que un objeto nuevo se vea igual en todos los PCs, ponlo en el grupo `net_body`. Un mecanismo con
  estado propio va en `net_state` con `send_state_to(peer)` y un `@rpc` que lo aplique.
- **Internet**: quien hospeda debe abrir el puerto UDP en su router, o usar una red tipo Tailscale /
  ZeroTier / Radmin VPN. Pendiente para más adelante: Steam/relay, predicción del propio personaje,
  reconexión, compresión.

## Controles

| Acción | Teclado/ratón | Mando |
|---|---|---|
| Moverse | WASD / flechas | Stick izq. |
| Mirar / apuntar brazos | Ratón | Stick der. |
| Saltar | Espacio | A |
| Brazo izq. / der. (mantener = agarrar) | Clic izq. / der. | LT / RT |
| Trepar | Apunta al borde y agarra, luego mira arriba + W; suelta al estar arriba | |
| Puñetazo | F | X |
| Dejarse caer (flácido) | Q | B |
| Reaparecer | R | Back |
| Soltar el ratón | Esc | |

## Arquitectura modular (`scripts/ragdoll/`)

Un personaje es un `RagdollCharacter` (núcleo) con **habilidades como nodos hijo**. El núcleo solo construye el
cuerpo, detecta el suelo y guarda el estado compartido; cada hijo `CharacterAbility` se ejecuta en cada paso de
física **en el orden del árbol**. Quitar un nodo = el personaje pierde esa habilidad (sin `Climb` se agarra pero
no trepa; sin `Combat` no pega). Cada nodo expone sus parámetros en el inspector.

```
Player (RagdollCharacter)     body = data/bodies/humanoid.tres, visual_scene = character_nocto.glb
├─ PlayerInput    controllers/player_input.gd  ← en los NPC: AIBrain (controllers/ai_brain.gd)
├─ Knockout       fuerza muscular, KO por golpe en la cabeza, Q = flácido
├─ StandSupport   muelle que sostiene en pie + salto
├─ Balance        torso/pelvis erguidos, cabeza mirando a la mira
├─ Locomotion     caminar y fase del paso
├─ Legs           pose de piernas (paso, aire, trepar)
├─ Combat         puñetazos
├─ Arms           árbitro de brazos: Combat (30) > Climb (20) > Grab (10) > relajados
├─ Climb          trepar (necesita Grab)
└─ Grab           agarrar con cada mano
```

- **Controladores** (`PlayerInput`, `AIBrain`): solo rellenan la *intención* del personaje (`move_input`,
  `facing_yaw`, `aim_pitch`, `want_grab`, `want_jump`, `want_limp`, `want_punch`). Para otro tipo de IA o un
  segundo jugador basta con un controlador nuevo.
- **Brazos**: varias habilidades quieren mover los brazos; cada una responde `arm_claim_priority(side)` y `Arms`
  deja actuar a la de mayor prioridad (`drive_arm`).
- **Músculos** (`ragdoll_muscles.gd`): funciones PD compartidas (`pd_toward`, `pd_aim`, `upright_torque`).
- **Cuerpo como recurso** (`body/`): `RagdollBodyDef` con las piezas (`RagdollPartDef`: posición, masa, forma)
  y articulaciones (`RagdollJointDef`). Para un personaje con otras proporciones, duplica
  `data/bodies/humanoid.tres`, ajústalo y asígnalo en `body`. Los nombres de las 11 piezas son obligatorios.

**Crear una habilidad nueva**: un script que `extends CharacterAbility`, sobrescribe `physics_step(delta)`
(y opcionalmente `setup()`, `reset()`, `arm_claim_priority()`/`drive_arm()`), y se añade como hijo del
personaje en su lugar del orden. Accede al cuerpo con `character.get_torso()`, `character.bodies[...]`, etc.

## Cómo funciona el ragdoll

- **Cuerpo 100% físico**: 11 `RigidBody3D` (pelvis, torso, cabeza, brazos, antebrazos, muslos, espinillas)
  unidos con `ConeTwistJoint3D`. No hay `AnimationPlayer` ni `CharacterBody3D`.
- **Músculos PD**: cada parte recibe un torque proporcional-derivativo hacia una pose objetivo relativa a su
  padre (con el torque opuesto aplicado al padre, acción-reacción). Se escala con el tensor de inercia real.
- **Equilibrio**: torso y pelvis tienen un "músculo de equilibrio" que los mantiene verticales y orientados
  hacia donde mira la cámara, y un muelle vertical sostiene la pelvis a `stand_height` cuando hay suelo.
- **Caminar**: fuerza horizontal en pelvis/torso hacia la velocidad deseada + ciclo de pasos procedural
  (seno) en las piernas y balanceo de brazos. La fuerza nunca empuja contra paredes fijas (se detectan con
  rayos a la altura de cadera y pecho), para que la fricción no deje al personaje pegado a un muro.
- **Brazos independientes (HFF)**: cada botón levanta un brazo hacia la dirección de la cámara; si la mano toca
  un cuerpo se crea un `Generic6DOFJoint3D` (rótula) entre la mano y el objeto. La mano solo se cierra cuando el
  brazo ya apunta hacia la mira (así no se agarra a media pared mientras sube), y una compensación de gravedad
  evita que los brazos extendidos se cuelguen.
- **Trepar**: agarrado a algo fijo (o muy pesado) y mirando arriba, los brazos izan el cuerpo; empujando hacia
  delante el torso se dobla sobre el borde y la cadera pasa por encima. Al cruzar el borde las rodillas suben
  al pecho, cadera y piernas resbalan sobre la arista y los pies que cuelgan reciben ayuda para subir. Si se
  suelta a mitad del cruce, durante `finish_time` el personaje sigue hasta apoyar los dos pies arriba (si no,
  quedaba sentado en la arista). Ajustable en los nodos `Climb` y `Legs`.
- **Estabilidad**: toda amortiguación muscular se limita para no frenar más del 70 % del giro en un paso de
  física (35 % sobre el cuerpo padre). Sin ese límite, piezas de poca inercia (giro vertical de pelvis/torso)
  temblaban a 15–20 rad/s.
- **Combate (Gang Beasts)**: puñetazo de boxeo en tres fases: carga (puño a la guardia, hombro atrás),
  golpe recto con el brazo estirado y giro del torso, y vuelta a la guardia (el brazo se frena en seco,
  `arm_brake`). Tras golpear los dos puños quedan en guardia `guard_time` s, así los golpes seguidos
  (alternando brazo) parecen una combinación. Solo la fase de golpe hace daño. Si hay un rival a tiro delante (`aim_assist_range`,
  `aim_assist_angle`), el puño apunta a su cabeza y el torso se lanza un poco hacia él (`punch_lunge`).
  Cada puñetazo en la cabeza suma `punch_damage`, echa la cabeza y el torso hacia atrás (`punch_knockback`) y
  afloja los músculos un instante (`stagger_time`, `stagger_strength`) para que se tambalee. Con
  `knockout_damage` acumulado cae KO; el daño se cura solo tras `damage_recovery_delay` s sin encajar golpes.
  Un impacto muy fuerte en la cabeza (`knockout_speed`) noquea de golpe. KO = fuerza muscular 0 durante
  `knockout_duration` → ragdoll flácido, y luego se levanta solo, con `recover_grace` s sin poder volver a caer.
  Cada golpe lanza chispas y un sonido seco (sintetizado en `scripts/fx/hit_fx.gd`) y, si participa el
  jugador, sacude la cámara.
- **NPC**: el mismo núcleo con `AIBrain` en vez de `PlayerInput`. Con `target_path` persigue al objetivo hasta
  `punch_distance` y le golpea cada `punch_cooldown` segundos.

## Escenario de pruebas (`scenes/levels/test_arena.tscn`)

- Rampa, escaleras y torre con **ascensor** (movimiento y pendientes).
- **Muro escalable** de 1,5 m y 2,6 m (agarrar + trepar).
- **Puzle**: lleva la caja metálica (15 kg) a la placa de presión → se abre la puerta → entra en la zona verde.
- **Balancín** con `HingeJoint3D`, **aspa giratoria** que derriba, torre de cajas, pelotas y tablón.
- **Muñeco quieto** para empujar/agarrar y **ring de sparring** con un muñeco que te persigue y golpea.

## Personajes (Blender)

`art_source/build_characters.py` genera los personajes con la API de Blender y los exporta a
`assets/characters/*.glb`. Cada parte del cuerpo es un objeto separado cuyo origen coincide con el centro del
cuerpo rígido en Godot (las dimensiones deben coincidir con `data/bodies/humanoid.tres`).

```bash
blender -b --factory-startup --python art_source/build_characters.py
```

- **Nocto** (jugador): personaje gominola con gorro de lana y mochila.
- **Dummy** (NPC): muñeco de entrenamiento con correas cruzadas.

Los `.blend` resultantes quedan en `art_source/` (con `.gdignore` para que Godot no los importe).

## Pruebas automáticas

- `tests/test_ragdoll.tscn`: estar de pie, caminar, saltar, KO + recuperación, levantar brazos (alineación
  promedio con la mira), agarrar y
  arrastrar la caja, y soltar.
- `tests/test_climb.tscn`: apuntar al borde de la repisa de 1,5 m, agarrarlo, mirar arriba, izarse, pasar el
  borde y quedar de pie arriba.
- `tests/test_wall_release.tscn`: saltar contra el muro alto, agarrarse por debajo del borde, soltar las manos
  sin soltar W y comprobar que cae al suelo (antes la fricción lo dejaba pegado a la pared).
- `tests/test_mantle_release.tscn`: soltar manos y W justo al cruzar el borde y comprobar que acaba de pie
  arriba con los dos pies apoyados.
- `tests/test_combat.tscn`: noquear a DummyIdle a puñetazos, KO flácido y recuperación, dejarse caer con Q,
  la IA de sparring noquea al jugador y el periodo de gracia tras levantarse.

```bash
godot --headless res://tests/test_ragdoll.tscn
godot --headless res://tests/test_climb.tscn
godot --headless res://tests/test_wall_release.tscn
godot --headless res://tests/test_mantle_release.tscn
godot --headless res://tests/test_combat.tscn
```

Imprime líneas `ASSERT ok|fail <nombre>`.

Prueba de red (dos procesos en este PC, anfitrión y cliente): el cliente entra, su W mueve su personaje en
el anfitrión y lo ve en el mismo sitio, una caja empujada llega al mismo sitio en ambos, su puñetazo llega y
al salir desaparece. Admite mala conexión simulada:

```bash
tests/run_net_test.sh /ruta/a/godot
tests/run_net_test.sh /ruta/a/godot --lag=150 --loss=0.05
```
