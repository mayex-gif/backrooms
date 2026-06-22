@tool
extends Node3D

## Arrastrá acá el recurso ConfigHabitacion que querés rellenar automáticamente
@export var recurso_config: Resource
## Ejecutá el escaneo tildando esta casilla en el Inspector
@export var ejecutar_escaneo: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			comenzar_escaneo()
		ejecutar_escaneo = false

## Tamaño de la celda del sistema (Tu resolución de grilla)
@export var tamano_celda: float = 0.5

func comenzar_escaneo():
	if not recurso_config:
		push_error("Por favor, asigná un recurso ConfigHabitacion en el Inspector.")
		return
		
	print("--- Iniciando escaneo automático de huella ---")
	var celdas_detectadas: Array[Vector3i] = []
	
	# 1. Buscamos todas las colisiones físicas reales que pusiste en la habitación
	var colisionadores = obtener_todos_los_collision_shapes(self)
	if colisionadores.is_empty():
		push_error("No se encontraron nodos CollisionShape3D en la habitación.")
		return
		
	# 2. Definimos un área de búsqueda aproximada basada en el tamaño del modelo
	# Escaneamos un área de 30x30 metros alrededor del centro local por seguridad
	var rango_busqueda = 6 # Cantidad de celdas hacia cada lado
	
	for x in range(-rango_busqueda, rango_busqueda + 1):
		for z in range(-rango_busqueda, rango_busqueda + 1):
			# Calculamos el centro de la celda local en metros reales
			var punto_testeo_local = Vector3(x * tamano_celda, 0.0, z * tamano_celda)
			
			# Comprobamos si este casillero colisiona con alguna de tus formas primitivas
			if verificar_punto_dentro_de_habitacion(punto_testeo_local, colisionadores):
				# Guardamos la coordenada entera local libre de decimales
				celdas_detectadas.append(Vector3i(x, 0, z))

	# 3. Guardamos los datos directamente en tu recurso personalizado
	recurso_config.huella_celdas = celdas_detectadas
	
	# Forzamos a Godot a guardar el recurso en el disco para que no se pierda al cerrar
	ResourceSaver.save(recurso_config, recurso_config.resource_path)
	
	print("¡Escaneo completado con éxito!")
	print("Celdas registradas en el recurso: ", celdas_detectadas)


func obtener_todos_los_collision_shapes(nodo: Node) -> Array[CollisionShape3D]:
	var lista: Array[CollisionShape3D] = []
	if nodo is CollisionShape3D:
		lista.append(nodo)
	for hijo in nodo.get_children():
		lista.append_array(obtener_todos_los_collision_shapes(hijo))
	return lista


func verificar_punto_dentro_de_habitacion(punto_local: Vector3, colisionadores: Array[CollisionShape3D]) -> bool:
	for cs3d in colisionadores:
		if not cs3d.shape or not cs3d.visible: continue
		
		# Convertimos el punto de testeo a la posición relativa de cada colisionador hijo
		var punto_relativo_al_shape = cs3d.transform.inverse() * punto_local
		
		# Si usás BoxShape3D (cubos primitivos), la matemática de la caja es exacta e instantánea
		if cs3d.shape is BoxShape3D:
			var box = cs3d.shape as BoxShape3D
			var semi_extension = box.size / 2.0
			
			if abs(punto_relativo_al_shape.x) <= semi_extension.x and \
			   abs(punto_relativo_al_shape.z) <= semi_extension.z:
				return true
				
	return false
