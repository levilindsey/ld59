class_name DrawUtils
extends Node


func _ready() -> void:
	G.print("DrawUtils._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)


static func draw_shape_outline(
		canvas: CanvasItem,
		position: Vector2,
		shape: Shape2D,
		color: Color,
		thickness: float,
) -> void:
	if shape is CircleShape2D:
		draw_circle_outline(
			canvas,
			position,
			shape.shape.radius,
			color,
			thickness,
		)
	elif shape.shape is CapsuleShape2D:
		draw_capsule_outline(
			canvas,
			position,
			shape.shape.radius,
			shape.shape.height,
			shape.is_rotated_90_degrees,
			color,
			thickness,
		)
	elif shape.shape is RectangleShape2D:
		draw_rectangle_outline(
			canvas,
			position,
			shape.shape.extents,
			shape.is_rotated_90_degrees,
			color,
			thickness,
		)
	else:
		G.fatal(
			"Invalid Shape2D provided for draw_shape_outline: %s. The " +
			"supported shapes are: CircleShape2D, CapsuleShape2D, " +
			"RectangleShape2D." % shape.shape,
		)


static func draw_circle_outline(
		canvas: CanvasItem,
		center: Vector2,
		radius: float,
		color: Color,
		border_width := 1.0,
		sector_arc_length := 4.0,
) -> void:
	var points := compute_arc_points(
		center,
		radius,
		0.0,
		2.0 * PI,
		sector_arc_length,
	)

	# Even though the points ended and began at the same position, Godot would
	# render a gap, because the "adjacent" segments aren't collinear, and thus
	# their end caps don't align. We introduce two vertices, at very slight
	# offsets, so that we can force the end caps to line up.
	points.insert(0, points[0])
	points.push_back(points[0])
	points[points.size() - 2].y -= 0.0001
	points[1].y += 0.0001

	canvas.draw_polyline(
		points,
		color,
		border_width,
	)


static func draw_arc(
		canvas: CanvasItem,
		center: Vector2,
		radius: float,
		start_angle: float,
		end_angle: float,
		color: Color,
		border_width := 1.0,
		sector_arc_length := 4.0,
) -> void:
	var points := compute_arc_points(
		center,
		radius,
		start_angle,
		end_angle,
		sector_arc_length,
	)

	canvas.draw_polyline(
		points,
		color,
		border_width,
	)


static func compute_arc_points(
		center: Vector2,
		radius: float,
		start_angle: float,
		end_angle: float,
		sector_arc_length := 4.0,
) -> PackedVector2Array:
	assert(sector_arc_length > 0.0)

	var angle_diff := end_angle - start_angle
	var sector_count := floori(absf(angle_diff) * radius / sector_arc_length)
	var delta_theta := sector_arc_length / radius
	var theta := start_angle

	if angle_diff == 0:
		return PackedVector2Array(
			[
				Vector2(cos(start_angle), sin(start_angle)) * radius + center,
			],
		)
	elif angle_diff < 0:
		delta_theta = -delta_theta

	var should_include_partial_sector_at_end := \
	absf(angle_diff) - sector_count * delta_theta > 0.01
	var vertex_count := sector_count + 1
	if should_include_partial_sector_at_end:
		vertex_count += 1

	var points := PackedVector2Array()
	points.resize(vertex_count)

	for i in sector_count + 1:
		points[i] = Vector2(cos(theta), sin(theta)) * radius + center
		theta += delta_theta

	# Handle the fence-post problem.
	if should_include_partial_sector_at_end:
		points[vertex_count - 1] = \
		Vector2(cos(end_angle), sin(end_angle)) * radius + center

	return points


static func draw_rectangle_outline(
		canvas: CanvasItem,
		center: Vector2,
		half_width_height: Vector2,
		is_rotated_90_degrees: bool,
		color: Color,
		thickness := 1.0,
) -> void:
	var x_offset: float = \
	half_width_height.y if \
	is_rotated_90_degrees else \
	half_width_height.x
	var y_offset: float = \
	half_width_height.x if \
	is_rotated_90_degrees else \
	half_width_height.y

	var polyline := PackedVector2Array()
	polyline.resize(6)

	polyline[1] = center + Vector2(-x_offset, -y_offset)
	polyline[2] = center + Vector2(x_offset, -y_offset)
	polyline[3] = center + Vector2(x_offset, y_offset)
	polyline[4] = center + Vector2(-x_offset, y_offset)

	# By having the polyline start and end in the middle of a segment, we can
	# ensure the end caps line up and don't show a gap.
	polyline[5] = lerp(polyline[4], polyline[1], 0.5)
	polyline[0] = polyline[5]

	canvas.draw_polyline(
		polyline,
		color,
		thickness,
	)


static func draw_capsule_outline(
		canvas: CanvasItem,
		center: Vector2,
		radius: float,
		height: float,
		is_rotated_90_degrees: bool,
		color: Color,
		thickness := 1.0,
		sector_arc_length := 4.0,
) -> void:
	var sector_count := ceili((PI * radius / sector_arc_length) / 2.0) * 2
	var delta_theta := PI / sector_count
	var theta := \
	PI / 2.0 if \
	is_rotated_90_degrees else \
	0.0
	var capsule_end_offset := \
	Vector2(height / 2.0, 0.0) if \
	is_rotated_90_degrees else \
	Vector2(0.0, height / 2.0)
	var end_center := center - capsule_end_offset
	var vertices := PackedVector2Array()
	var vertex_count := (sector_count + 1) * 2 + 2
	vertices.resize(vertex_count)

	for i in sector_count + 1:
		vertices[i + 1] = Vector2(cos(theta), sin(theta)) * radius + end_center
		theta += delta_theta

	end_center = center + capsule_end_offset
	theta -= delta_theta

	for i in range(sector_count + 1, (sector_count + 1) * 2):
		vertices[i + 1] = Vector2(cos(theta), sin(theta)) * radius + end_center
		theta += delta_theta

	# By having the polyline start and end in the middle of a segment, we can
	# ensure the end caps line up and don't show a gap.
	vertices[vertex_count - 1] = lerp(
		vertices[vertex_count - 2],
		vertices[1],
		0.5,
	)
	vertices[0] = vertices[vertex_count - 1]

	canvas.draw_polyline(
		vertices,
		color,
		thickness,
	)


# This applies Thales's theorem to find the points of tangency between the line
# segments from the triangular portion and the circle:
# https://en.wikipedia.org/wiki/Thales%27s_theorem
static func draw_ice_cream_cone(
		canvas: CanvasItem,
		cone_end_point: Vector2,
		circle_center: Vector2,
		circle_radius: float,
		color: Color,
		is_filled: bool,
		border_width := 1.0,
		sector_arc_length := 4.0,
) -> void:
	assert(circle_radius >= 0.0)

	var distance_from_cone_end_point_to_circle_center := \
	cone_end_point.distance_to(circle_center)

	if circle_radius <= 0.0:
		# Degenerate case: A line segment.
		canvas.draw_line(
			circle_center,
			cone_end_point,
			color,
			border_width,
			false,
		)
		return
	elif distance_from_cone_end_point_to_circle_center <= circle_radius:
		# Degenerate case: A circle (the cone-end-point lies within the
		#                  circle).
		if is_filled:
			canvas.draw_circle(
				circle_center,
				circle_radius,
				color,
			)
			return
		else:
			draw_circle_outline(
				canvas,
				circle_center,
				circle_radius,
				color,
				border_width,
				sector_arc_length,
			)
			return

	var angle_from_circle_center_to_point_of_tangency := \
	acos(circle_radius / distance_from_cone_end_point_to_circle_center)
	var angle_from_circle_center_to_cone_end_point := \
	circle_center.angle_to_point(cone_end_point)

	var start_angle := angle_from_circle_center_to_cone_end_point + \
	angle_from_circle_center_to_point_of_tangency
	var end_angle := angle_from_circle_center_to_cone_end_point - \
	angle_from_circle_center_to_point_of_tangency + 2.0 * PI

	var points := compute_arc_points(
		circle_center,
		circle_radius,
		start_angle,
		end_angle,
		sector_arc_length,
	)

	if is_filled:
		# For filled polygons, manually draw triangles from the cone tip to
		# each arc segment to avoid triangulation issues with narrow shapes.
		for i in range(points.size() - 1):
			var triangle := PackedVector2Array([
				cone_end_point,
				points[i],
				points[i + 1],
			])

			# Skip degenerate triangles with zero area.
			var area: float = abs(
				(points[i].x - cone_end_point.x) * \
				(points[i + 1].y - cone_end_point.y) - \
				(points[i + 1].x - cone_end_point.x) * \
				(points[i].y - cone_end_point.y)
			) / 2.0

			if area > 0.001:
				canvas.draw_colored_polygon(triangle, color)
	else:
		# These extra points prevent the stroke width from shrinking around
		# the cone end point when drawing outlines.
		var extra_cone_end_point_1 := \
		cone_end_point + \
		(points[points.size() - 1] - cone_end_point) * 0.000001
		var extra_cone_end_point_2 := \
		cone_end_point + \
		(points[0] - cone_end_point) * 0.000001

		points.push_back(extra_cone_end_point_1)
		points.push_back(cone_end_point)
		points.push_back(extra_cone_end_point_2)
		points.push_back(points[0])

		canvas.draw_polyline(
			points,
			color,
			border_width,
		)
