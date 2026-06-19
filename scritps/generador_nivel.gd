extends Node3D

@export var habitacion_inicial_prefab: PackedScene
@export var pool_habitaciones: Array[ConfigHabitacion]

@export var jugador: Node3D 
@export var distancia_generacion: float = 50.0 

var registro_generadas: Dictionary = {}
var esta_generando: bool = false
var puertas_abiertas: Array[Marker3D] = []

# --- NUEVO: CONTADOR GLOBAL ---
var total_habitaciones_generadas: int = 1 # Empieza en 1 por el spawn inicial

func _ready():
	randomize()
	if not jugador:
		push_error("CRÍTICO: No asignaste el Jugador en el Inspector.")
		return
		
	if habitacion_inicial_prefab:
		var habitacion_inicial = habitacion_inicial_prefab.instantiate()
		add_child(habitacion_inicial)
		habitacion_inicial.global_position = Vector3.ZERO
		registrar_puertas_nuevas(habitacion_inicial)
		
		# Imprimimos la primera
		print("--- INICIANDO GENERACIÓN ---")
		print("Habitaciones construidas: ", total_habitaciones_generadas)
	
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_chequear_distancias)
	add_child(timer)

func registrar_puertas_nuevas(habitacion: Node3D):
	var nodo_conexiones = habitacion.get_node_or_null("Conexiones")
	if nodo_conexiones:
		for marker in nodo_conexiones.get_children():
			puertas_abiertas.append(marker as Marker3D)

func _chequear_distancias():
	if esta_generando or puertas_abiertas.is_empty(): return
	
	puertas_abiertas.shuffle()
	
	for i in range(puertas_abiertas.size() - 1, -1, -1):
		var marker = puertas_abiertas[i]
		
		if not is_instance_valid(marker):
			puertas_abiertas.remove_at(i)
			continue
			
		var distancia = jugador.global_position.distance_to(marker.global_position)
		if distancia < distancia_generacion:
			conectar_nueva_habitacion(marker)
			break

func elegir_siguiente_habitacion() -> ConfigHabitacion:
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

# --- NUEVO: LECTOR DE TAMAÑOS ---
# Esta función extrae el tamaño real ignorando los números extra como "_1"
func obtener_tamano_puerta(nombre_nodo: String) -> String:
	# Importante: El orden importa. Primero los más largos ("7_5" antes que "7")
	var tamanos_validos = ["7_5", "7", "5", "2_5", "1"]
	for t in tamanos_validos:
		if nombre_nodo.begins_with(t):
			return t
	return "" # Por defecto


# --- ACTUALIZADO: SISTEMA DE REINTENTOS Y ENCHUFES ---
func conectar_nueva_habitacion(marker_salida_anterior: Marker3D):
	esta_generando = true
	
	var tamano_requerido = obtener_tamano_puerta(marker_salida_anterior.name)
	var habitacion_nueva = null
	var marker_entrada_final = null
	var config_exitosa = null
	
	# EL BUCLE DE REINTENTOS: Intenta hasta 10 veces encontrar una pieza que encaje
	for intento in range(10):
		var config = elegir_siguiente_habitacion()
		if not config: continue
			
		var prueba = config.escena.instantiate()
		var nodo_conexiones = prueba.get_node_or_null("Conexiones")
		
		if not nodo_conexiones:
			prueba.queue_free()
			continue
			
		# 1. FILTRO DE TAMAÑO: ¿Esta pieza tiene una puerta del tamaño que busco?
		var enchufes_compatibles = []
		for marker in nodo_conexiones.get_children():
			if obtener_tamano_puerta(marker.name) == tamano_requerido:
				enchufes_compatibles.append(marker)
				
		if enchufes_compatibles.is_empty():
			prueba.queue_free()
			continue # Esta carta no nos sirve, el loop da otra vuelta y saca otra
			
		# Si tiene la puerta correcta, la elegimos
		var marker_entrada = enchufes_compatibles.pick_random() as Marker3D
		
		add_child(prueba)
		
		# 2. ALINEACIÓN
		var rotacion_objetivo_y = marker_salida_anterior.global_rotation.y + PI
		prueba.global_rotation.y += (rotacion_objetivo_y - marker_entrada.global_rotation.y)
		prueba.global_position += (marker_salida_anterior.global_position - marker_entrada.global_position)
		
		# 3. ANTI-COLISIONES
		var choco = false
		var detector = prueba.get_node_or_null("DetectorEspacio")
		if detector:
			detector.force_update_transform()
			await get_tree().physics_frame
			await get_tree().physics_frame
			
			if detector.has_overlapping_areas():
				choco = true
				
		if choco:
			prueba.queue_free()
			continue # Chocó con una pared. La destruimos y el loop saca otra carta.
		else:
			# ¡ÉXITO TOTAL! Pasó todos los filtros. Nos quedamos con esta.
			habitacion_nueva = prueba
			marker_entrada_final = marker_entrada
			config_exitosa = config
			break # Cortamos el loop de reintentos
			
			
	# --- FIN DEL BUCLE DE REINTENTOS ---
	
	if not habitacion_nueva:
		# Si intentó 10 veces y no encontró nada que encaje (o que no choque), abandona la rama.
		print("-> Abandono: Ninguna pieza compatible o libre de choques para puerta ", tamano_requerido)
		marker_salida_anterior.queue_free()
		esta_generando = false
		return
		
	# Sumamos al registro la que efectivamente se construyó
	registro_generadas[config_exitosa.nombre_debug] = registro_generadas.get(config_exitosa.nombre_debug, 0) + 1
	
	# Destruimos los enchufes usados
	marker_entrada_final.queue_free()
	marker_salida_anterior.queue_free()
	
	# Sumamos al contador global e imprimimos
	total_habitaciones_generadas += 1
	print("Nueva habitación: ", config_exitosa.nombre_debug, " | Total construidas: ", total_habitaciones_generadas)
	
	registrar_puertas_nuevas(habitacion_nueva)
	
	await get_tree().create_timer(0.1).timeout
	esta_generando = false
