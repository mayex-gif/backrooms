@tool
extends StaticBody3D

@export var largo: float = 1.0:
	set(value):
		largo = max(0.1, value)
		if is_node_ready():
			_actualizar_dimensiones()

# Exponemos el excedente total en metros
@export var excedente_zocalo: float = 0.1:
	set(value):
		excedente_zocalo = value
		if is_node_ready():
			_actualizar_dimensiones()

@onready var colision = $CollisionShape3D
@onready var mesh_pared = $MeshInstance3D
@onready var mesh_zocalo = $MeshInstance3D_Zocalo

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
