@tool
extends MeshInstance3D

## Génère un pavé dont les 4 arêtes VERTICALES sont arrondies (coins arrondis
## vus du dessus), avec un dessus et un dessous plats.

@export var size: Vector3 = Vector3(1, 1, 1):
	set(v):
		size = v
		_rebuild()

@export var corner_radius: float = 0.12:
	set(v):
		corner_radius = v
		_rebuild()

## Plus il y a de segments, plus le coin est lisse (rond). 1 = simple biseau plat.
@export var corner_segments: int = 6:
	set(v):
		corner_segments = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var hy: float = size.y * 0.5
	var r: float = min(corner_radius, min(hx, hz))

	var corner_centers := [
		Vector2(hx - r, hz - r),
		Vector2(-hx + r, hz - r),
		Vector2(-hx + r, -hz + r),
		Vector2(hx - r, -hz + r),
	]
	var start_angles := [0.0, PI * 0.5, PI, PI * 1.5]

	var outline: Array[Vector2] = []
	for c in range(4):
		var center: Vector2 = corner_centers[c]
		var start_angle: float = start_angles[c]
		for s in range(corner_segments + 1):
			var a: float = start_angle + (PI * 0.5) * (float(s) / float(corner_segments))
			outline.append(center + Vector2(cos(a), sin(a)) * r)

	var point_count: int = outline.size()

	for i in range(point_count):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % point_count]
		var normal: Vector3 = Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()

		st.set_normal(normal)
		st.add_vertex(Vector3(a.x, -hy, a.y))
		st.add_vertex(Vector3(b.x, -hy, b.y))
		st.add_vertex(Vector3(a.x, hy, a.y))

		st.set_normal(normal)
		st.add_vertex(Vector3(b.x, -hy, b.y))
		st.add_vertex(Vector3(b.x, hy, b.y))
		st.add_vertex(Vector3(a.x, hy, a.y))

	st.set_normal(Vector3.UP)
	for i in range(1, point_count - 1):
		st.add_vertex(Vector3(outline[0].x, hy, outline[0].y))
		st.add_vertex(Vector3(outline[i].x, hy, outline[i].y))
		st.add_vertex(Vector3(outline[i + 1].x, hy, outline[i + 1].y))

	st.set_normal(Vector3.DOWN)
	for i in range(1, point_count - 1):
		st.add_vertex(Vector3(outline[0].x, -hy, outline[0].y))
		st.add_vertex(Vector3(outline[i + 1].x, -hy, outline[i + 1].y))
		st.add_vertex(Vector3(outline[i].x, -hy, outline[i].y))

	mesh = st.commit()
