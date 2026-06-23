extends Node

# Control de desarrollo: si está en false, bloquea el Nivel 0 hasta ganar el piloto
@export var modo_desarrollador: bool = true 

# Preparamos los archivos de los niveles en memoria RAM
var escena_piloto = preload("res://escenas/NivelPiloto.tscn")
var escena_nivel0 = preload("res://escenas/Nivel0.tscn")

@onready var camara_dron = $CamaraDron
@onready var capa_menu = $HUB/CapaMenu
@onready var contenedor_niveles = $Niveles

@onready var boton_piloto = $HUB/CapaMenu/BotonNivelPiloto
@onready var boton_nivel0 = $HUB/CapaMenu/BotonNivel0

var jugador: CharacterBody3D = null
var camara_jugador: Camera3D = null

func _ready():
	# Forzamos que el mouse se vea al estar en el menú principal
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Conectamos las señales de los botones por código para asegurar su funcionamiento
	boton_piloto.pressed.connect(_on_boton_piloto_pressed)
	boton_nivel0.pressed.connect(_on_boton_nivel0_pressed)
	
	# Lógica de bloqueo/desbloqueo de nivel
	if not modo_desarrollador:
		boton_nivel0.disabled = true
		boton_nivel0.text = "Nivel 0 (Bloqueado)"
	else:
		boton_nivel0.disabled = false

func _on_boton_piloto_pressed():
	# Forzamos que el reloj global se ponga a las 14:00 antes de la transición
	TiempoGlobal.hora = 12.0
	
	# Llamamos a la función de carga que ya tenías
	_iniciar_transicion_de_nivel(escena_piloto)

func _on_boton_nivel0_pressed():
	_iniciar_transicion_de_nivel(escena_nivel0)

func _iniciar_transicion_de_nivel(nivel_a_cargar: PackedScene):
	# 1. Escondemos el menú de inmediato para liberar la visual de la cámara
	capa_menu.visible = false
	
	# 2. Instanciamos el nivel seleccionado dentro del contenedor vacío
	var instancia = nivel_a_cargar.instantiate()
	contenedor_niveles.add_child(instancia)
	
	# 3. Le damos un cuadro al motor para que procese el _ready del nivel e instancie al jugador
	await get_tree().process_frame
		
	# 4. Buscamos al personaje en el mundo a través del grupo "jugador"
	jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D
	
	if jugador:
		var spawn_point = instancia.get_node_or_null("SpawnPoint")
		if spawn_point:
			jugador.global_position = spawn_point.global_position
		
		camara_jugador = jugador.get_node("Cabeza/Camera3D") # Ajustá el nombre exacto de tu nodo cámara
		
		# 1. Igualamos el FOV de la lente para evitar el salto de zoom
		camara_dron.fov = camara_jugador.fov
		
		# Ponemos al jugador en pausa inducida para que no camine durante la cinemática
		#jugador.set_physics_process(false)
		jugador.set_process_input(false)
		if "puede_moverse" in jugador:
			jugador.puede_moverse = false

	# 5. Si ambas cámaras existen, ejecutamos el vuelo del dron
	if camara_dron and camara_jugador:
		var tween = create_tween()
		tween.set_parallel(true)
		
		tween.tween_property(camara_dron, "global_position", camara_jugador.global_position, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(camara_dron, "global_rotation", camara_jugador.global_rotation, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		# Al terminar la trayectoria, activamos el gameplay
		tween.chain().tween_callback(terminar_transicion)
	else:
		# Salvaguarda por si no se encuentra alguna cámara
		terminar_transicion()

func terminar_transicion():
	if camara_jugador:
		camara_jugador.current = true
		
	if camara_dron:
		camara_dron.queue_free()
	
	# Escondemos y capturamos el mouse para la jugabilidad en primera persona
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Despertamos las funciones del jugador
	if jugador:
		# Forzamos al jugador a estar tocando el suelo justo antes de activar las físicas
		# Esto evita que el CharacterBody3D "caiga" al activarse
		#jugador.jugador.global_position.y -= 0.1
		
		jugador.set_physics_process(true)
		jugador.set_process_input(true)
		if "puede_moverse" in jugador:
			jugador.puede_moverse = true
