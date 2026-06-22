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
@export var tamano_celda: float = 0.5
@export var semilla: int = 12345  

# El objeto que va a manejar el azar controlado
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- MAPA MENTAL Y CONTROL ---
var mapa_mental: Dictionary = {}
var cola_puertas: Array[PuertaPendiente] = []
var esta_generando: bool = false 
var registro_generadas: Dictionary = {} 
var total_habitaciones_generadas: int = 0
var limite_generacion = 10000
@export var radio_generacion: float = 50.0

var jugador: CharacterBody3D = null

# Constantes de dirección
const NORTE = Vector3i(0, 0, -1)
const SUR = Vector3i(0, 0, 1)
const ESTE = Vector3i(1, 0, 0)
const OESTE = Vector3i(-1, 0, 0)

func _ready():
	
	# Le asignamos tu semilla al generador de azar
	rng.seed = semilla  
	
	# OPCIONAL: Si querés que sea totalmente aleatorio como antes si la semilla es 0
	if semilla == 0:
		rng.randomize() # Genera una semilla basada en el tiempo
	randomize()
	
	# --- NUEVO: ESCANEO AUTOMÁTICO DE TODO EL POOL EN LA CARGA ---
	print("--- Iniciando escaneo automático del Pool de Habitaciones (RAM) ---")
	for config in pool_habitaciones:
		if config:
			calcular_huella_dinamica(config, tamano_celda)
	print("--- Escaneo del Pool completado de forma transparente ---")
	
	if habitacion_inicial_prefab:
		inicializar_mapa()
	else:
		push_error("Falta la habitación inicial.")

func inicializar_mapa():
	var nodo_inicial = habitacion_inicial_prefab.instantiate()
	add_child(nodo_inicial)
	nodo_inicial.global_position = Vector3.ZERO
	
	# --- NUEVO: ESCANEO Y REGISTRO COMPLETO DEL SPAWN ---
	registrar_huella_instancia(nodo_inicial, "Spawn_Inicial")
	
	anotar_puertas_en_cola(nodo_inicial)
	
	var room_manager = get_tree().get_first_node_in_group("room_manager")
	if room_manager:
		room_manager.registrar_habitacion(nodo_inicial)
		
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
			round(vector_relativo.x / tamano_celda),
			round(vector_relativo.y / altura_piso_metros),
			round(vector_relativo.z / tamano_celda)
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
	return "2_5" 

func grilla_a_mundo(coordenada_grilla: Vector3i) -> Vector3:
	return Vector3(
		coordenada_grilla.x * tamano_celda,
		coordenada_grilla.y * altura_piso_metros,
		coordenada_grilla.z * tamano_celda
	)

func mundo_a_grilla(pos_global: Vector3) -> Vector3i:
	return Vector3i(
		round(pos_global.x / tamano_celda),
		round(pos_global.y / altura_piso_metros),
		round(pos_global.z / tamano_celda)
	)

func rotar_celda_local(celda_local: Vector3i, angulo_y_rad: float) -> Vector3i:
	var cos_a = cos(angulo_y_rad)
	var sin_a = sin(angulo_y_rad)
	var x_rotado = celda_local.x * cos_a + celda_local.z * sin_a
	var z_rotado = -celda_local.x * sin_a + celda_local.z * cos_a
	return Vector3i(round(x_rotado), celda_local.y, round(z_rotado))

func _process(delta):
	if esta_generando or cola_puertas.is_empty() or total_habitaciones_generadas >= limite_generacion:
		return
		
	if not jugador:
		jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D
		return

	# Obtenemos el vector hacia donde apunta la cámara/jugador (su frente)
	var forward_camara = -jugador.global_transform.basis.z.normalized()

	var mejor_indice = -1
	var mejor_puntaje = -1000.0
	
	for i in range(cola_puertas.size()):
		var puerta = cola_puertas[i]
		if not is_instance_valid(puerta.marker_nodo):
			cola_puertas.remove_at(i)
			return 
			
		var vector_hacia_puerta = puerta.marker_nodo.global_position - jugador.global_position
		var distancia = vector_hacia_puerta.length()
		
		if distancia <= radio_generacion:
			var direccion_normalizada = vector_hacia_puerta.normalized()
			# Producto punto: Positivo (de frente), Negativo (a la espalda)
			var alineacion = forward_camara.dot(direccion_normalizada) 
			
			# Ahora prioriza fuertemente a las que están cerca (distancia penaliza más),
			# pero usa la alineación solo como un pequeño desempate para mirar hacia adelante en un abanico amplio (180 grados).
			var puntaje = (alineacion * 0.5) - (distancia / radio_generacion * 2.0)
			
			if puntaje > mejor_puntaje:
				mejor_puntaje = puntaje
				mejor_indice = i

	if mejor_indice != -1:
		procesar_puerta_especifica(mejor_indice)

# Cambiale el nombre y agregale el parámetro 'indice'
func procesar_puerta_especifica(indice: int):
	esta_generando = true
	
	# Agarramos la puerta específica y la sacamos de la cola
	var puerta_actual = cola_puertas[indice]
	cola_puertas.remove_at(indice)
	
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
	
	# NUEVO: Le damos un respiro obligatorio a la CPU para que dibuje frames
	await get_tree().create_timer(0.05).timeout
	
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
		
	var tirada = rng.randf_range(0.0, suma_pesos)
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
			
		# Elegimos un índice al azar usando tu semilla, y sacamos ese marcador
		var indice_azar = rng.randi() % enchufes_compatibles.size()
		var marker_entrada = enchufes_compatibles[indice_azar] as Marker3D
		
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
	
	# --- NUEVO: REGISTRAR LA HABITACIÓN NUEVA EN EL ROOM MANAGER ---
	var room_manager = get_tree().get_first_node_in_group("room_manager")
	if room_manager:
		room_manager.registrar_habitacion(habitacion_nueva)
	
	total_habitaciones_generadas += 1
	print("Generada: ", config_exitosa.nombre_debug, " (Ocupa ", celdas_finales_a_ocupar.size(), " celdas) | Total: ", total_habitaciones_generadas)

func intentar_conectar_habitaciones(puerta_origen: PuertaPendiente, celda_ocupada: Vector3i):
	print("¡Intento de bucle detectado en la celda ", celda_ocupada, "!")
	if is_instance_valid(puerta_origen.marker_nodo):
		puerta_origen.marker_nodo.queue_free()



# ================================

# Escanea una habitación de forma dinámica en tiempo de ejecución (RAM) y le asigna su huella
func calcular_huella_dinamica(config: ConfigHabitacion, tamano_cella: float):
	if not config.escena: return
	
	var prueba = config.escena.instantiate() as Node3D
	add_child(prueba)
	prueba.global_position = Vector3.ZERO
	
	var celdas_detectadas: Array[Vector3i] = []
	
	# Buscamos SOLO los colisionadores que pertenezcan al suelo
	var colisionadores: Array[CollisionShape3D] = []
	var buscar_shapes = func de_forma_recursiva(nodo: Node, funcion_interna):
		if nodo is CollisionShape3D:
			var nom_nodo = nodo.name.to_lower()
			var nom_padre = nodo.get_parent().name.to_lower() if nodo.get_parent() else ""
			
			# Filtro: Solo agrega la colisión si el nodo o su padre se llaman "suelo"
			if "suelo" in nom_nodo or "suelo" in nom_padre:
				colisionadores.append(nodo)
				
		for hijo in nodo.get_children():
			funcion_interna.call(hijo, funcion_interna)
			
	buscar_shapes.call(prueba, buscar_shapes)
	
	var rango_busqueda = 15 
	
	for x in range(-rango_busqueda, rango_busqueda + 1):
		for z in range(-rango_busqueda, rango_busqueda + 1):
			var punto_local = Vector3(x * tamano_cella, 0.0, z * tamano_cella)
			
			for cs3d in colisionadores:
				if not cs3d.shape or not cs3d.visible: continue
				
				var punto_relativo = cs3d.transform.inverse() * punto_local
				if cs3d.shape is BoxShape3D:
					var box = cs3d.shape as BoxShape3D
					var semi_extension = box.size / 2.0
					
					# Retraemos el escáner 10 centímetros hacia adentro.
					# Garantiza que el Array solo guarde el interior de la sala
					# y deje los bordes libres para que las puertas no colisionen.
					if abs(punto_relativo.x) <= (semi_extension.x - 0.1) and \
					   abs(punto_relativo.z) <= (semi_extension.z - 0.1):
						var celda = Vector3i(x, 0, z)
						if not celdas_detectadas.has(celda):
							celdas_detectadas.append(celda)
						break
						
	# Asignamos la huella al recurso directamente en la memoria RAM
	config.huella_celdas = celdas_detectadas
	
	# --- NUEVO: Log inmediato del resultado del escáner ---
	print(" - Escaneada: ", config.nombre_debug, " | Ocupa: ", celdas_detectadas.size(), " celdas")
	
	# Limpiamos la habitación de prueba inmediatamente
	prueba.queue_free()
	
	# --- NUEVO ESCÁNER PARA HABITACIONES YA INSTANCIADAS (SPAWN) ---
func registrar_huella_instancia(instancia: Node3D, nombre_registro: String):
	var colisionadores: Array[CollisionShape3D] = []
	
	# Misma lógica de búsqueda de suelos
	var buscar_shapes = func de_forma_recursiva(nodo: Node, funcion_interna):
		if nodo is CollisionShape3D:
			var nom_nodo = nodo.name.to_lower()
			var nom_padre = nodo.get_parent().name.to_lower() if nodo.get_parent() else ""
			if "suelo" in nom_nodo or "suelo" in nom_padre or "piso" in nom_nodo or "piso" in nom_padre:
				colisionadores.append(nodo)
		for hijo in nodo.get_children():
			funcion_interna.call(hijo, funcion_interna)
			
	buscar_shapes.call(instancia, buscar_shapes)

	# Rango 40 cubre piezas gigantes (hasta 40 metros desde el centro). 
	# Sobra para la sala inicial de 15x25m.
	var rango_busqueda = 40 
	var celdas_ocupadas = 0
	var celda_pivote = mundo_a_grilla(instancia.global_position)

	for x in range(-rango_busqueda, rango_busqueda + 1):
		for z in range(-rango_busqueda, rango_busqueda + 1):
			var punto_local = Vector3(x * tamano_celda, 0.0, z * tamano_celda)
			
			for cs3d in colisionadores:
				if not cs3d.shape or not cs3d.visible: continue
				
				# Usamos la transformación global para no perder el rastro de la malla real
				var punto_global_testeo = instancia.global_transform * punto_local
				var punto_relativo = cs3d.global_transform.affine_inverse() * punto_global_testeo
				
				if cs3d.shape is BoxShape3D:
					var box = cs3d.shape as BoxShape3D
					var semi_extension = box.size / 2.0
					
					# Retraemos 10cm para solo tomar el interior
					if abs(punto_relativo.x) <= (semi_extension.x - 0.1) and \
					   abs(punto_relativo.z) <= (semi_extension.z - 0.1):
						var celda = celda_pivote + Vector3i(x, 0, z)
						mapa_mental[celda] = nombre_registro
						celdas_ocupadas += 1
						break
						
	print("Huella de [", nombre_registro, "] registrada. Ocupa ", celdas_ocupadas, " celdas.")
