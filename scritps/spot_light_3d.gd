extends Node3D

@export var parpadear: bool = false
@export var malla_placa_techo: MeshInstance3D
@export var activa := true

@onready var spotlight: SpotLight3D = $SpotLight3D
@onready var audio_zumbido: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var raycast: RayCast3D = $RayCast3D

@onready var energia_normal: float = spotlight.light_energy

# --- Variables de Oclusión Acústica ---
var jugador: CharacterBody3D = null
var tiempo_desde_ultimo_calculo: float = 0.0
const INTERVALO_CALCULO_AUDIO: float = 0.15 # ~7 veces por segundo (Optimizado)

var material_emisor: StandardMaterial3D
var emision_energia_base: float = 1.0
var volumen_base_db: float = -12.0 

func _ready():
	# 1. Automatización de Rendimiento: Conectamos la visibilidad del árbol
	visibility_changed.connect(_on_visibility_changed)
	
	# 2. Inicializar Material
	if malla_placa_techo:
		var mat_original = malla_placa_techo.get_active_material(0)
		if mat_original is StandardMaterial3D:
			material_emisor = mat_original.duplicate()
			malla_placa_techo.material_override = material_emisor
			emision_energia_base = material_emisor.emission_energy_multiplier

	# 3. Registrar Jugador
	jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D

	# 4. Configuración del RayCast
	if raycast:
		raycast.exclude_parent = true
		raycast.collision_mask = 0
		raycast.set_collision_mask_value(4, true) # Capa de paredes

	# 5. Estado inicial del módulo
	if activa and is_visible_in_tree():
		activar()
	else:
		desactivar()

# Control Manual o por Script
func activar():
	activa = true
	if is_visible_in_tree():
		_inicializar_luz()

func desactivar():
	activa = false
	_cambiar_estado_luz(false)
	if raycast:
		raycast.enabled = false

# Control Automático por Oclusión (Performance del Motor)
func _on_visibility_changed():
	if not is_visible_in_tree():
		# Si el motor oculta el módulo, apagamos todo el procesamiento de inmediato
		_cambiar_estado_luz(false)
		if raycast:
			raycast.enabled = false
	else:
		# Si vuelve a ser visible y el módulo está activo, reanudamos
		if activa:
			_inicializar_luz()

func _inicializar_luz():
	if raycast and activa:
		raycast.enabled = true
		
	if parpadear and activa:
		flash()
	else:
		_cambiar_estado_luz(activa)

func flash():
	# Condición de salida limpia
	if not parpadear or not activa or not is_visible_in_tree():
		_cambiar_estado_luz(activa and is_visible_in_tree())
		return
		
	# Cambiamos el estado de forma binaria
	var estado_aleatorio = randf() > 0.5
	_cambiar_estado_luz(estado_aleatorio)
	
	# El temporizador controla el flujo de forma segura (sin colgar el hilo)
	await get_tree().create_timer(randf_range(0.0, 0.25)).timeout
	
	# Siguiente ciclo
	if parpadear and activa and is_visible_in_tree():
		flash()

func _cambiar_estado_luz(encendido: bool):
	if encendido:
		# spotlight.visible = true  <--- ELIMINAR ESTA LÍNEA
		spotlight.light_energy = energia_normal
		if material_emisor:
			material_emisor.emission_enabled = true
			material_emisor.emission_energy_multiplier = emision_energia_base
		if audio_zumbido and not audio_zumbido.playing and is_visible_in_tree():
			audio_zumbido.play()
	else:
		# spotlight.visible = false <--- ELIMINAR ESTA LÍNEA
		spotlight.light_energy = 0.0
		if material_emisor:
			material_emisor.emission_enabled = false
		if audio_zumbido and audio_zumbido.playing:
			audio_zumbido.stop()

func _physics_process(delta: float) -> void:
	# Si el módulo está inactivo o el motor lo ocultó, no gastamos ni un ciclo de CPU
	if not activa or not is_visible_in_tree() or not audio_zumbido or not audio_zumbido.playing or not jugador:
		return

	tiempo_desde_ultimo_calculo += delta
	if tiempo_desde_ultimo_calculo >= INTERVALO_CALCULO_AUDIO:
		tiempo_desde_ultimo_calculo = 0.0
		_calcular_occlusion_acustica()

func _calcular_occlusion_acustica():
	var posicion_objetivo = raycast.to_local(jugador.global_position + Vector3(0, 1.55, 0))
	raycast.target_position = posicion_objetivo
	raycast.force_raycast_update()

	if raycast.is_colliding():
		# ¡Hay una pared en el medio! Aplicamos el filtro de volumen amortiguado (Oclusión)
		# Atenuamos considerablemente el volumen restando decibelios
		var obj = raycast.get_collider()
		# print( "Nombre:", obj.name," Tipo:", obj.get_class()," Capa:", obj.collision_layer)
		audio_zumbido.volume_db = volumen_base_db - 20
	else:
		# print("SIN COLISION")
		audio_zumbido.volume_db = volumen_base_db
