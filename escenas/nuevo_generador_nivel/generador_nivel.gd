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
var esta_generando: bool = false # DECLARADA
var registro_generadas: Dictionary = {} # Para la ruleta

var total_habitaciones_generadas = 0
var limite_generacion = 200

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
	anotar_puertas_en_cola(Vector3i(0, 0, 0), nodo_inicial)
	print("Mapa mental iniciado. Puertas en cola para procesar: ", cola_puertas.size())

func anotar_puertas_en_cola(celda_actual: Vector3i, instancia_habitacion: Node3D):
	var nodo_conexiones = instancia_habitacion.get_node_or_null("Conexiones")
	if not nodo_conexiones: return
	
	for marker in nodo_conexiones.get_children():
		var m3d = marker as Marker3D
		if not m3d: continue
		
		var dir_grilla = calcular_direccion_cardinal(m3d.global_transform.basis.z)
		var tamano_puerta = obtener_tamano_por_nombre(m3d.name)
		
		# Le pasamos el m3d a la clase para guardarlo
		var nueva_puerta = PuertaPendiente.new(celda_actual, dir_grilla, tamano_puerta, m3d)
		cola_puertas.append(nueva_puerta)

func calcular_direccion_cardinal(forward_vector: Vector3) -> Vector3i:
	if abs(forward_vector.x) > abs(forward_vector.z):
		return ESTE if forward_vector.x > 0 else OESTE
	else:
		return SUR if forward_vector.z > 0 else NORTE

func obtener_tamano_por_nombre(nombre_nodo: String) -> String:
	#var lista_tamanos = ["7_5", "7", "5", "2_5", "1"]
	var lista_tamanos = ["7_5", "7", "5", "2_5", "1_5", "1"]
	for t in lista_tamanos:
		if nombre_nodo.begins_with(t):
			return t
	return "2_5" 

func grilla_a_mundo(coordenada_grilla: Vector3i) -> Vector3:
	return Vector3(
		coordenada_grilla.x * 2.5,
		coordenada_grilla.y * altura_piso_metros,
		coordenada_grilla.z * 2.5
	)

func _process(delta):
	# Agregamos el límite a la condición
	if not esta_generando and cola_puertas.size() > 0 and total_habitaciones_generadas < limite_generacion:
		procesar_siguiente_puerta()
	elif total_habitaciones_generadas >= limite_generacion:
		# Apagamos el _process para que deje de consumir recursos
		set_process(false)
		print("--- LÍMITE DE", limite_generacion, " HABITACIONES ALCANZADO ---")

func procesar_siguiente_puerta():
	esta_generando = true
	var puerta_actual = cola_puertas.pop_front()
	var celda_destino = puerta_actual.celda_origen + puerta_actual.direccion
	
	if mapa_mental.has(celda_destino):
		intentar_conectar_habitaciones(puerta_actual, celda_destino)
	else:
		generar_nueva_habitacion_en_celda(puerta_actual, celda_destino)
		
	await get_tree().physics_frame
	await get_tree().physics_frame
	esta_generando = false

# --- LA RULETA (Adaptada para filtrar por tamaño) ---
func elegir_siguiente_habitacion(tamano_requerido: String) -> ConfigHabitacion:
	# Acá deberíamos filtrar por tamaño, pero por ahora devolvemos una aleatoria válida
	# para no complejizar en este paso. (Lo puliremos cuando rotemos la pieza).
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
	
	# BUCLE DE REINTENTOS: Intenta 10 veces buscar una pieza del tamaño correcto
	for intento in range(10):
		var config = elegir_siguiente_habitacion("") # Sacamos una carta al azar
		if not config: continue
			
		var prueba = config.escena.instantiate()
		var nodo_conexiones = prueba.get_node_or_null("Conexiones")
		
		if not nodo_conexiones:
			prueba.queue_free()
			continue
			
		# FILTRO: Buscamos si esta pieza tiene un enchufe del mismo tamaño que nuestra puerta
		var enchufes_compatibles = []
		for marker in nodo_conexiones.get_children():
			if obtener_tamano_por_nombre(marker.name) == puerta_origen.tamano:
				enchufes_compatibles.append(marker)
				
		if enchufes_compatibles.is_empty():
			prueba.queue_free()
			continue # No nos sirve, probamos con otra
			
		# ¡Encontramos una que encaja!
		habitacion_nueva = prueba
		marker_entrada_final = enchufes_compatibles.pick_random() as Marker3D
		config_exitosa = config
		break # Cortamos el bucle

	# Si después de 10 intentos no encontró nada, abandonamos la rama
	if not habitacion_nueva:
		if is_instance_valid(puerta_origen.marker_nodo):
			puerta_origen.marker_nodo.queue_free()
		return

	# La agregamos al mundo
	add_child(habitacion_nueva)
	
	# 1. LA UBICAMOS EN LA GRILLA
	habitacion_nueva.global_position = grilla_a_mundo(celda_destino)
	
	# 2. LA ROTAMOS MATEMÁTICAMENTE
	# Calculamos el ángulo para que mire exactamente hacia la puerta de origen
	if is_instance_valid(puerta_origen.marker_nodo):
		var rotacion_objetivo = puerta_origen.marker_nodo.global_rotation.y + PI
		habitacion_nueva.global_rotation.y += (rotacion_objetivo - marker_entrada_final.global_rotation.y)
	
	# Actualizamos registros
	mapa_mental[celda_destino] = config_exitosa.nombre_debug
	
	# Borramos los enchufes usados para que queden abiertos los pasillos
	if is_instance_valid(puerta_origen.marker_nodo):
		puerta_origen.marker_nodo.queue_free()
	marker_entrada_final.queue_free()
	
	# Sumamos las nuevas puertas a la cola
	anotar_puertas_en_cola(celda_destino, habitacion_nueva)
	
	total_habitaciones_generadas += 1
	print("Generada: ", config_exitosa.nombre_debug, " en ", celda_destino, " | Total: ", total_habitaciones_generadas)


func intentar_conectar_habitaciones(puerta_origen: PuertaPendiente, celda_ocupada: Vector3i):
	print("¡Intento de bucle detectado en la celda ", celda_ocupada, "!")
	# Si no se puede conectar, borramos el marker de origen para cerrar la pared
	if is_instance_valid(puerta_origen.marker_nodo):
		puerta_origen.marker_nodo.queue_free()
