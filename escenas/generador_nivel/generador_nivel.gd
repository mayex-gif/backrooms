extends Node3D

# --- CLASE AUXILIAR PARA LA COLA FIFO ---
class PuertaPendiente:
	var celda_origen: Vector3i      # Celda donde está la habitación que la creó
	var direccion: Vector3i         # Hacia dónde apunta (Ej: Vector3i(0, 0, -1) es Norte)
	var tamano: String              # "1", "1_5", "2_5", "5", "7_5", etc.
	var marker_nodo: Marker3D       # Referencia al nodo físico para poder borrarlo
	
	func _init(p_celda: Vector3i, p_dir: Vector3i, p_tamano: String, p_marker: Marker3D):
		celda_origen = p_celda
		direccion = p_dir
		tamano = p_tamano
		marker_nodo = p_marker

# --- VARIABLES CONFIGURABLES ---
@export var habitacion_inicial_prefab: PackedScene
@export var pool_habitaciones: Array[ConfigHabitacion] 
@export var altura_piso_metros: float = 4.0            

# --- MAPA MENTAL Y CONTROL ---
var mapa_mental: Dictionary = {}
var cola_puertas: Array[PuertaPendiente] = []
var esta_generando: bool = false 
var registro_generadas: Dictionary = {} 
var total_habitaciones_generadas: int = 0

# Constantes de dirección
const NORTE = Vector3i(0, 0, -1)
const SUR = Vector3i(0, 0, 1)
const ESTE = Vector3i(1, 0, 0)
const OESTE = Vector3i(-1, 0, 0)

func _ready():
	randomize()
	if habitacion_inicial_prefab:
		inicializar_mapa()
	else:
		push_error("Falta la habitación inicial.")

func inicializar_mapa():
	var nodo_inicial = habitacion_inicial_prefab.instantiate()
	add_child(nodo_inicial)
	nodo_inicial.global_position = Vector3.ZERO
	
	mapa_mental[Vector3i(0, 0, 0)] = "Spawn_Inicial"
	anotar_puertas_en_cola(nodo_inicial)
	print("Mapa mental iniciado. Puertas en cola para procesar: ", cola_puertas.size())

func anotar_puertas_en_cola(instancia_habitacion: Node3D):
	var nodo_conexiones = instancia_habitacion.get_node_or_null("Conexiones")
	if not nodo_conexiones: return
	
	var celda_centro_habitacion = mundo_a_grilla(instancia_habitacion.global_position)
	
	for marker in nodo_conexiones.get_children():
		var m3d = marker as Marker3D
		if not m3d: continue
		
		var dir_grilla = calcular_direccion_cardinal(m3d.global_transform.basis.z)
		var tamano_puerta = obtener_tamano_por_nombre(m3d.name)
		
		# SEGURO ANTI-DESFASE: Retrocedemos un pelito hacia adentro para no caer en el limbo del 0.5
		var punto_seguro_interior = m3d.global_position - (Vector3(dir_grilla) * 0.2)
		var vector_relativo = punto_seguro_interior - instancia_habitacion.global_position
		
		var celda_relativa = Vector3i(
			round(vector_relativo.x / 2.5),
			round(vector_relativo.y / altura_piso_metros),
			round(vector_relativo.z / 2.5)
		)
		
		var celda_exacta = celda_centro_habitacion + celda_relativa
		var nueva_puerta = PuertaPendiente.new(celda_exacta, dir_grilla, tamano_puerta, m3d)
		cola_puertas.append(nueva_puerta)

func calcular_direccion_cardinal(forward_vector: Vector3) -> Vector3i:
	if abs(forward_vector.x) > abs(forward_vector.z):
		return ESTE if forward_vector.x > 0 else OESTE
	else:
		return SUR if forward_vector.z > 0 else NORTE

func obtener_tamano_por_nombre(nombre_nodo: String) -> String:
	var lista_tamanos = ["7_5", "7", "5", "2_5", "1_5", "1"]
	for t in lista_tamanos:
		if nombre_nodo.begins_with(t):
			return t
	return "1_5" 

func grilla_a_mundo(coordenada_grilla: Vector3i) -> Vector3:
	return Vector3(
		coordenada_grilla.x * 2.5,
		coordenada_grilla.y * altura_piso_metros,
		coordenada_grilla.z * 2.5
	)

func mundo_a_grilla(pos_global: Vector3) -> Vector3i:
	return Vector3i(
		round(pos_global.x / 2.5),
		round(pos_global.y / altura_piso_metros),
		round(pos_global.z / 2.5)
	)

func rotar_celda_local(celda_local: Vector3i, angulo_y_rad: float) -> Vector3i:
	var cos_a = cos(angulo_y_rad)
	var sin_a = sin(angulo_y_rad)
	var x_rotado = celda_local.x * cos_a + celda_local.z * sin_a
	var z_rotado = -celda_local.x * sin_a + celda_local.z * cos_a
	return Vector3i(round(x_rotado), celda_local.y, round(z_rotado))

func _process(delta):
	if not esta_generando and cola_puertas.size() > 0 and total_habitaciones_generadas < 100:
		procesar_siguiente_puerta()
	elif total_habitaciones_generadas >= 100:
		set_process(false)
		print("--- LÍMITE DE 100 HABITACIONES ALCANZADO ---")

func procesar_siguiente_puerta():
	esta_generando = true
	var puerta_actual = cola_puertas.pop_front()
	
	if not is_instance_valid(puerta_actual.marker_nodo):
		esta_generando = false
		return
		
	var celda_destino = puerta_actual.celda_origen + puerta_actual.direccion
	
	if mapa_mental.has(celda_destino):
		intentar_conectar_habitaciones(puerta_actual, celda_destino)
	else:
		generar_nueva_habitacion_en_celda(puerta_actual, celda_destino)
		
	await get_tree().physics_frame
	await get_tree().physics_frame
	esta_generando = false

func elegir_siguiente_habitacion(tamano_requerido: String) -> ConfigHabitacion:
	var opciones_validas: Array[ConfigHabitacion] = []
	var suma_pesos: float = 0.0
	
	for config in pool_habitaciones:
		var veces = registro_generadas.get(config.nombre_debug, 0)
		if config.limite_maximo == 0 or veces < config.limite_maximo:
			opciones_validas.append(config)
			suma_pesos += config.peso_probabilidad
			
	if opciones_validas.is_empty(): return null
		
	var tirada = randf_range(0.0, suma_pesos)
	var peso_acumulado: float = 0.0
	
	for config in opciones_validas:
		peso_acumulado += config.peso_probabilidad
		if tirada <= peso_acumulado:
			return config
	return null

func generar_nueva_habitacion_en_celda(puerta_origen: PuertaPendiente, celda_destino: Vector3i):
	var habitacion_nueva = null
	var marker_entrada_final = null
	var config_exitosa = null
	var celdas_finales_a_ocupar = []
	
	for intento in range(10):
		var config = elegir_siguiente_habitacion(puerta_origen.tamano)
		if not config: continue
			
		var prueba = config.escena.instantiate()
		var nodo_conexiones = prueba.get_node_or_null("Conexiones")
		
		if not nodo_conexiones:
			prueba.queue_free()
			continue
			
		var enchufes_compatibles = []
		for marker in nodo_conexiones.get_children():
			if obtener_tamano_por_nombre(marker.name) == puerta_origen.tamano:
				enchufes_compatibles.append(marker)
				
		if enchufes_compatibles.is_empty():
			prueba.queue_free()
			continue 
			
		var marker_entrada = enchufes_compatibles.pick_random() as Marker3D
		add_child(prueba)
		
		if is_instance_valid(puerta_origen.marker_nodo):
			var rotacion_objetivo = puerta_origen.marker_nodo.global_rotation.y + PI
			prueba.global_rotation.y += (rotacion_objetivo - marker_entrada.global_rotation.y)
			
			var offset = puerta_origen.marker_nodo.global_position - marker_entrada.global_position
			prueba.global_position += offset
			
		var celda_pivote_real = mundo_a_grilla(prueba.global_position)
		var choco = false
		var celdas_a_ocupar_temporal = []
		
		for celda_local in config.huella_celdas:
			var celda_rotada = rotar_celda_local(celda_local, prueba.global_rotation.y)
			var celda_global = celda_pivote_real + celda_rotada
			
			if mapa_mental.has(celda_global):
				choco = true
				break
			celdas_a_ocupar_temporal.append(celda_global)
			
		if choco:
			prueba.queue_free()
			continue 
			
		habitacion_nueva = prueba
		marker_entrada_final = marker_entrada
		config_exitosa = config
		celdas_finales_a_ocupar = celdas_a_ocupar_temporal
		break 

	if not habitacion_nueva:
		if is_instance_valid(puerta_origen.marker_nodo):
			puerta_origen.marker_nodo.queue_free()
		return

	for celda_ocupada in celdas_finales_a_ocupar:
		mapa_mental[celda_ocupada] = config_exitosa.nombre_debug

	registro_generadas[config_exitosa.nombre_debug] = registro_generadas.get(config_exitosa.nombre_debug, 0) + 1

	if is_instance_valid(puerta_origen.marker_nodo):
		puerta_origen.marker_nodo.queue_free()
	marker_entrada_final.queue_free()
	
	anotar_puertas_en_cola(habitacion_nueva)
	
	total_habitaciones_generadas += 1
	print("Generada: ", config_exitosa.nombre_debug, " (Ocupa ", celdas_finales_a_ocupar.size(), " celdas) | Total: ", total_habitaciones_generadas)

func intentar_conectar_habitaciones(puerta_origen: PuertaPendiente, celda_ocupada: Vector3i):
	print("¡Intento de bucle detectado en la celda ", celda_ocupada, "!")
	if is_instance_valid(puerta_origen.marker_nodo):
		puerta_origen.marker_nodo.queue_free()
