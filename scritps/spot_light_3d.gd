extends SpotLight3D

@export var parpadear: bool = false
@export var malla_placa_techo: MeshInstance3D

@onready var energia_normal: float = light_energy
@onready var audio_zumbido: AudioStreamPlayer3D = $"../AudioStreamPlayer3D"

# --- Variables de Oclusión Acústica ---
@onready var raycast: RayCast3D = $"../RayCast3D"
var jugador: CharacterBody3D = null
var tiempo_desde_ultimo_calculo: float = 0.0
const INTERVALO_CALCULO_AUDIO: float = 0.15 # Se ejecuta ~7 veces por segundo (Optimizado)

var material_emisor: StandardMaterial3D
var emision_energia_base: float = 1.0
var volumen_base_db: float = -12.0 # Ajustado al estándar de fondo de antes

func _ready():
	# 1. Configurar Señal de Visibilidad (Punto 1)
	visibility_changed.connect(_on_visibility_changed)

	# 2. Inicializar Material
	if malla_placa_techo:
		var mat_original = malla_placa_techo.get_active_material(0)
		if mat_original is StandardMaterial3D:
			material_emisor = mat_original.duplicate()
			malla_placa_techo.material_override = material_emisor
			emision_energia_base = material_emisor.emission_energy_multiplier

	# 3. Buscar al jugador en la escena usando su grupo
	# Asegurate de agregar la palabra "jugador" en la pestaña Nodos -> Grupos de tu script de jugador
	jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D

	# 4. Configuración inicial del RayCast
	if raycast:
		raycast.enabled = true
		raycast.exclude_parent = true
		# IMPORTANTE: Configurá la máscara de colisión del raycast para que SOLO choque con el mapa (Paredes)
		raycast.collision_mask = 1 

	# 5. Iniciar ciclo eléctrico si es visible
	if is_visible_in_tree():
		_inicializar_luz()

func _inicializar_luz():
	if parpadear:
		flash()
	else:
		_cambiar_estado_luz(true)

# RESPUESTA AL PUNTO 1: Si ocultamos la luz en el editor o por mapa, matamos el audio y el raycast
func _on_visibility_changed():
	if not is_visible_in_tree():
		parpadear = false # Detiene el bucle recursivo del flash
		_cambiar_estado_luz(false)
		
		# OPTIMIZACIÓN Y LIMPIEZA VISUAL:
		if raycast:
			raycast.visible = false
			raycast.enabled = false 
		if audio_zumbido:
			audio_zumbido.visible = false # Oculta el ícono del parlante
	else:
		# Restauramos todo
		if raycast:
			raycast.visible = true
			raycast.enabled = true
		if audio_zumbido:
			audio_zumbido.visible = true
			
		_inicializar_luz()

func flash():
	if not parpadear or not is_visible_in_tree():
		_cambiar_estado_luz(is_visible_in_tree())
		return
		
	var estado_aleatorio = randf() > 0.5
	_cambiar_estado_luz(estado_aleatorio)
	
	await get_tree().create_timer(randf_range(0.05, 0.15)).timeout
	
	if parpadear and is_visible_in_tree():
		flash()

func _cambiar_estado_luz(encendido: bool):
	if encendido:
		light_energy = energia_normal
		if material_emisor:
			material_emisor.emission_enabled = true
			material_emisor.emission_energy_multiplier = emision_energia_base
		if audio_zumbido and not audio_zumbido.playing and is_visible_in_tree():
			audio_zumbido.play()
	else:
		light_energy = 0.0
		if material_emisor:
			material_emisor.emission_enabled = false
		if audio_zumbido and audio_zumbido.playing:
			audio_zumbido.stop()

# RESPUESTA AL PUNTO 2: Lógica de Oclusión Acústica por física de Rayos
func _physics_process(delta: float) -> void:
	if not is_visible_in_tree() or not audio_zumbido or not audio_zumbido.playing or not jugador:
		return

	tiempo_desde_ultimo_calculo += delta
	if tiempo_desde_ultimo_calculo >= INTERVALO_CALCULO_AUDIO:
		tiempo_desde_ultimo_calculo = 0.0
		_calcular_occlusion_acustica()

func _calcular_occlusion_acustica():
	# Convertimos la posición global del jugador al espacio local de nuestra lámpara
	# Apuntamos a la cabeza del jugador (aproximadamente a la altura de sus ojos)
	var posicion_objetivo = raycast.to_local(jugador.global_position + Vector3(0, 1.55, 0))
	raycast.target_position = posicion_objetivo
	
	# Forzamos la actualización inmediata del cálculo físico del rayo
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		# ¡Hay una pared en el medio! Aplicamos el filtro de volumen amortiguado (Oclusión)
		# Atenuamos considerablemente el volumen restando decibelios
		audio_zumbido.volume_db = lerp(audio_zumbido.volume_db, volumen_base_db - 20.0, 0.1)
	else:
		# Línea de visión directa y limpia. Sonido nítido original.
		audio_zumbido.volume_db = lerp(audio_zumbido.volume_db, volumen_base_db, 0.0)
