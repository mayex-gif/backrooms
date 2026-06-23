extends CharacterBody3D

# --- Variables de Movimiento ---
var velocidad_actual = 2.0
const VELOCIDAD_CAMINAR = 1#6.0 #1.0
const VELOCIDAD_CORRER = 2#10.0 #2.0 # Aumentada un poco para notar más la diferencia de ritmo
const VELOCIDAD_AGACHAR = 0.75
var puede_moverse: bool = false

# --- Parámetros de Head Bobbing (Ajustables desde el Inspector) ---
@export var BOB_FRECUENCIA_CAMINAR = 7.5
@export var BOB_AMPLITUD_CAMINAR = 0.03
@export var BOB_FRECUENCIA_CORRER = 7.5
@export var BOB_AMPLITUD_CORRER = 0.06
@export var BOB_FRECUENCIA_AGACHAR = 1.5
@export var BOB_AMPLITUD_AGACHAR = 0.02

# Variable interna para acumular el tiempo del balanceo
var bob_tiempo: float = 0.0

# --- Configuración de Cámara y Nodos ---
@export var MOUSE_SENSITIVITY: float = 0.003
@onready var cabeza: Node3D = $Cabeza
@onready var colision: CollisionShape3D = $CollisionShape3D

# Altura base de los ojos que cambiará según si está agachado o parado
var altura_ojos_base: float = 1.55

# --- Estados ---
var agachar: bool = false
var gravedad: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- AUDIO ---
@onready var audio_pasos = $AudioPasos # Referencia al nodo que acabamos de crear
var paso_reproducido: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	colision.shape.height = 1.66
	colision.position.y = 0.83 
	cabeza.position.y = altura_ojos_base

func _input(event: InputEvent) -> void:
	# Si no puede moverse, no aplicamos físicas ni leemos las teclas
	if not puede_moverse:
		return
		
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		cabeza.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if Input.is_action_just_pressed("agachar"):
		agachar = !agachar
	
	if Input.is_action_just_pressed("linterna"): # Acordate de mapear "linterna" (ej: tecla F) en el Mapa de Entrada
		$Cabeza/Camera3D/Linterna/SpotLight3D.visible = not $Cabeza/Camera3D/Linterna/SpotLight3D.visible

func _physics_process(delta: float) -> void:
	# Si no puede moverse, no aplicamos físicas ni leemos las teclas
	if not puede_moverse:
		return
		
	# 1. Sistema de Físicas de Agachado y definición de Altura Base
	if agachar:
		velocidad_actual = VELOCIDAD_AGACHAR
		altura_ojos_base = 1.0
		colision.shape.height = lerp(colision.shape.height, 0.9, 10.0 * delta)
		colision.position.y = lerp(colision.position.y, 0.45, 10.0 * delta)
	else:
		if Input.is_key_pressed(KEY_SHIFT):
			velocidad_actual = VELOCIDAD_CORRER
		else:
			velocidad_actual = VELOCIDAD_CAMINAR
		altura_ojos_base = 1.55
		colision.shape.height = lerp(colision.shape.height, 1.66, 10.0 * delta)
		colision.position.y = lerp(colision.position.y, 0.83, 10.0 * delta)
	# 2. Aplicar Gravedad
	if not is_on_floor():
		velocity.y -= gravedad * delta
	# 3. Procesar Movimiento WASD
	var input_dir := Input.get_vector("izquierda", "derecha", "adelante", "atras")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * velocidad_actual
		velocity.z = direction.z * velocidad_actual
	else:
		velocity.x = move_toward(velocity.x, 0, velocidad_actual)
		velocity.z = move_toward(velocity.z, 0, velocidad_actual)
	move_and_slide()
	# 4. Cálculo del Head Bobbing (Solo si está en el suelo y moviéndose)
	var velocidad_plana = Vector3(velocity.x, 0, velocity.z).length()
	if is_on_floor() and velocidad_plana > 0.1:
		# Elegimos la frecuencia y amplitud según el estado actual
		var freq = BOB_FRECUENCIA_CAMINAR
		var amp = BOB_AMPLITUD_CAMINAR
		if agachar:
			freq = BOB_FRECUENCIA_AGACHAR
			amp = BOB_AMPLITUD_AGACHAR
		elif velocidad_actual == VELOCIDAD_CORRER:
			freq = BOB_FRECUENCIA_CORRER
			amp = BOB_AMPLITUD_CORRER
		# Avanzamos el tiempo del bob de acuerdo al movimiento real
		bob_tiempo += delta * velocidad_plana * freq
		# Calculamos el desfase del bobbing
		var transformacion_bob = Vector3.ZERO
		transformacion_bob.y = sin(bob_tiempo) * amp
		transformacion_bob.x = cos(bob_tiempo / 2) * amp # El eje X va a la mitad de velocidad para hacer el '8'
		# Aplicamos el movimiento sumándolo de forma fluida a la altura base actual
		cabeza.position.y = lerp(cabeza.position.y, altura_ojos_base + transformacion_bob.y, 15.0 * delta)
		cabeza.position.x = lerp(cabeza.position.x, transformacion_bob.x, 15.0 * delta)
	else:
		# Si se queda quieto o está en el aire, la cámara vuelve suavemente al centro neutro
		bob_tiempo = 0.0
		cabeza.position.y = lerp(cabeza.position.y, altura_ojos_base, 15.0 * delta)
		cabeza.position.x = lerp(cabeza.position.x, 0.0, 15.0 * delta)
	# --- MAGIA DE AUDIO: Sincronizar pasos con el piso ---
	# Usamos la misma condición de velocidad para no hacer ruido si se mueve un milímetro
	if is_on_floor() and velocidad_plana > 0.01:
		# CORRECCIÓN: Leemos exactamente la misma fase de la onda que usa la cabeza
		var onda_paso = sin(bob_tiempo) 
		# Cuando la onda baja a su punto mínimo (la cabeza baja), el pie pisa fuerte
		if onda_paso < -0.8 and not paso_reproducido:
			# Variar el tono para que suene orgánico y no repetitivo
			audio_pasos.pitch_scale = randf_range(0.85, 1.15)
			audio_pasos.play()
			paso_reproducido = true
		# Cuando la onda sube y pasa el centro, "recargamos" el paso para el otro pie
		elif onda_paso > 0.0:
			paso_reproducido = false
	else:
		# Si se detiene o salta, cortamos el ciclo
		paso_reproducido = false
