@tool
extends StaticBody3D

@export var largo: float = 1.0:
	set(value):
		largo = max(0.1, value)
		if is_node_ready():
			_actualizar_dimensiones()

@export var excedente_zocalo: float = 0.1:
	set(value):
		excedente_zocalo = value
		if is_node_ready():
			_actualizar_dimensiones()

@onready var colision = $CollisionShape3D
@onready var mesh_pared = $MeshInstance3D
@onready var mesh_zocalo = $MeshInstance3D_Zocalo
@onready var oclusor_nodo = $OccluderInstance3D

func _ready():
	_actualizar_dimensiones()

func _actualizar_dimensiones():
	# 1. Ajustar la colisión y la pared al largo exacto solicitado
	if colision.shape is BoxShape3D:
		colision.shape.size.x = largo
		
	if mesh_pared.mesh is BoxMesh:
		mesh_pared.mesh.size.x = largo
		
	# 2. EL TRUCO CLAVE: Sumar el excedente fijo, no multiplicar
	if mesh_zocalo.mesh is BoxMesh:
		mesh_zocalo.mesh.size.x = largo + excedente_zocalo

	# 3. ESCALAR EL OCLUSOR (Nuevo)
	# Verificamos si existe el nodo y si tiene un recurso oclusor asignado
	if oclusor_nodo and oclusor_nodo.occluder:
		# Funciona tanto si elegiste un plano (Quad) como una caja (Box) para ocluir
		if oclusor_nodo.occluder is QuadOccluder3D or oclusor_nodo.occluder is BoxOccluder3D:
			oclusor_nodo.occluder.size.x = largo
