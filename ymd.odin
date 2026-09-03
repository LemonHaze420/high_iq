package high_iq

import "core:math"
import "core:os"
import rl "raylib"

u16_at :: proc(data: []u8, offset: int) -> u16 {
	if offset < 0 || offset + 2 > len(data) { return 0 }
	return u16(data[offset]) | u16(data[offset + 1]) << 8
}

i16_at :: proc(data: []u8, offset: int) -> i16 {
	return transmute(i16)u16_at(data, offset)
}

u32_at :: proc(data: []u8, offset: int) -> u32 {
	if offset < 0 || offset + 4 > len(data) { return 0 }
	return u32(data[offset]) | u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

advance_ymd_group :: proc(data: []u8, cursor: ^int, words_per_primitive: int) -> int {
	count := int(u16_at(data, cursor^))
	cursor^ += 2 + count * words_per_primitive * 2
	return count
}

write_ymd_vertex :: proc(mesh: ^rl.Mesh, output_index: ^int, data: []u8, vertex_index, normal_index: int, color: rl.Color) {
	vertex_offset := 4 + vertex_index * 8
	normal_offset := 4 + normal_index * 8
	index := output_index^
	scale := f32(1.0 / 300.0)
	mesh.vertices[index * 3 + 0] = f32(i16_at(data, vertex_offset + 0)) * scale
	mesh.vertices[index * 3 + 1] = -f32(i16_at(data, vertex_offset + 2)) * scale
	mesh.vertices[index * 3 + 2] = f32(i16_at(data, vertex_offset + 4)) * scale
	nx := f32(i16_at(data, normal_offset + 0))
	ny := -f32(i16_at(data, normal_offset + 2))
	nz := f32(i16_at(data, normal_offset + 4))
	length := f32(math.sqrt(f64(nx * nx + ny * ny + nz * nz)))
	if length < 0.001 { length = 1 }
	mesh.normals[index * 3 + 0] = nx / length
	mesh.normals[index * 3 + 1] = ny / length
	mesh.normals[index * 3 + 2] = nz / length
	mesh.colors[index * 4 + 0] = color.r
	mesh.colors[index * 4 + 1] = color.g
	mesh.colors[index * 4 + 2] = color.b
	mesh.colors[index * 4 + 3] = 255
	output_index^ += 1
}

y_md_color :: proc(data: []u8, color_base, color_index: int) -> rl.Color {
	offset := color_base + color_index * 4
	if offset + 4 > len(data) { return rl.WHITE }
	return rl.Color{data[offset], data[offset + 1], data[offset + 2], 255}
}

Ymd_Frame :: struct {
	data_offsets: [7]int,
	counts: [7]int,
	valid: bool,
}

ymd_frame_geometry :: proc(data: []u8, frame_table, frame: int) -> Ymd_Frame {
	result: Ymd_Frame
	frame_offset := int(u32_at(data, frame_table + frame * 4))
	cursor := frame_table + frame_offset
	if frame_offset <= 0 || cursor < 0 || cursor >= len(data) { return result }
	widths := [7]int{5, 7, 7, 9, 6, 9, 9}
	for group in 0..<7 {
		count := int(u16_at(data, cursor))
		cursor += 2
		result.data_offsets[group] = cursor
		result.counts[group] = count
		cursor += count * widths[group] * 2
		if cursor > len(data) { return {} }
	}
	result.valid = true
	return result
}

fill_ymd_mesh :: proc(mesh: ^rl.Mesh, data: []u8, color_base: int, frame: Ymd_Frame) {
	for index in 0..<int(mesh.vertexCount) {
		mesh.vertices[index * 3 + 0] = 0
		mesh.vertices[index * 3 + 1] = 0
		mesh.vertices[index * 3 + 2] = 0
		mesh.normals[index * 3 + 0] = 0
		mesh.normals[index * 3 + 1] = 1
		mesh.normals[index * 3 + 2] = 0
		mesh.colors[index * 4 + 0] = 0
		mesh.colors[index * 4 + 1] = 0
		mesh.colors[index * 4 + 2] = 0
		mesh.colors[index * 4 + 3] = 0
	}
	output := 0
	triangle_order := [3]int{0, 1, 2}
	for primitive in 0..<frame.counts[0] {
		offset := frame.data_offsets[0] + primitive * 10
		vertices := [3]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)), int(u16_at(data, offset + 4)),
		}
		normal := int(u16_at(data, offset + 6))
		color := y_md_color(data, color_base, int(u16_at(data, offset + 8)))
		for order in triangle_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normal, color)
		}
	}
	for primitive in 0..<frame.counts[1] {
		offset := frame.data_offsets[1] + primitive * 14
		vertices := [3]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)), int(u16_at(data, offset + 4)),
		}
		normal := int(u16_at(data, offset + 6))
		colors := [3]rl.Color{
			y_md_color(data, color_base, int(u16_at(data, offset + 8))),
			y_md_color(data, color_base, int(u16_at(data, offset + 10))),
			y_md_color(data, color_base, int(u16_at(data, offset + 12))),
		}
		for order in triangle_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normal, colors[order])
		}
	}
	for primitive in 0..<frame.counts[2] {
		offset := frame.data_offsets[2] + primitive * 14
		vertices := [3]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)), int(u16_at(data, offset + 4)),
		}
		normals := [3]int{
			int(u16_at(data, offset + 6)), int(u16_at(data, offset + 8)), int(u16_at(data, offset + 10)),
		}
		color := y_md_color(data, color_base, int(u16_at(data, offset + 12)))
		for order in triangle_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normals[order], color)
		}
	}
	for primitive in 0..<frame.counts[3] {
		offset := frame.data_offsets[3] + primitive * 18
		vertices := [3]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)), int(u16_at(data, offset + 4)),
		}
		normals := [3]int{
			int(u16_at(data, offset + 6)), int(u16_at(data, offset + 8)), int(u16_at(data, offset + 10)),
		}
		colors := [3]rl.Color{
			y_md_color(data, color_base, int(u16_at(data, offset + 12))),
			y_md_color(data, color_base, int(u16_at(data, offset + 14))),
			y_md_color(data, color_base, int(u16_at(data, offset + 16))),
		}
		for order in triangle_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normals[order], colors[order])
		}
	}
	quad_order := [6]int{0, 1, 2, 1, 3, 2}
	for primitive in 0..<frame.counts[4] {
		offset := frame.data_offsets[4] + primitive * 12
		vertices := [4]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)),
			int(u16_at(data, offset + 4)), int(u16_at(data, offset + 6)),
		}
		normal := int(u16_at(data, offset + 8))
		color := y_md_color(data, color_base, int(u16_at(data, offset + 10)))
		for order in quad_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normal, color)
		}
	}
	for primitive in 0..<frame.counts[5] {
		offset := frame.data_offsets[5] + primitive * 18
		vertices := [4]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)),
			int(u16_at(data, offset + 4)), int(u16_at(data, offset + 6)),
		}
		normal := int(u16_at(data, offset + 8))
		colors := [4]rl.Color{
			y_md_color(data, color_base, int(u16_at(data, offset + 10))),
			y_md_color(data, color_base, int(u16_at(data, offset + 12))),
			y_md_color(data, color_base, int(u16_at(data, offset + 14))),
			y_md_color(data, color_base, int(u16_at(data, offset + 16))),
		}
		for order in quad_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normal, colors[order])
		}
	}
	for primitive in 0..<frame.counts[6] {
		offset := frame.data_offsets[6] + primitive * 18
		vertices := [4]int{
			int(u16_at(data, offset)), int(u16_at(data, offset + 2)),
			int(u16_at(data, offset + 4)), int(u16_at(data, offset + 6)),
		}
		normals := [4]int{
			int(u16_at(data, offset + 8)), int(u16_at(data, offset + 10)),
			int(u16_at(data, offset + 12)), int(u16_at(data, offset + 14)),
		}
		color := y_md_color(data, color_base, int(u16_at(data, offset + 16)))
		for order in quad_order {
			write_ymd_vertex(mesh, &output, data, vertices[order], normals[order], color)
		}
	}
}

load_ymd_model :: proc(path: string) -> Ymd_Model {
	result: Ymd_Model
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil || len(data) < 16 { return result }
	vertex_count := int(u16_at(data, 0))
	metadata := 4 + vertex_count * 8
	if vertex_count <= 0 || metadata + 8 > len(data) { delete(data); return result }
	color_count := int(u16_at(data, metadata))
	color_base := metadata + 4
	frame_table := color_base + color_count * 4
	first_frame_offset := int(u32_at(data, frame_table))
	if first_frame_offset <= 0 || frame_table + first_frame_offset >= len(data) {
		delete(data)
		return result
	}
	result.frame_count = i32(first_frame_offset / 4)
	max_triangles := 0
	first_valid := -1
	for frame_index in 0..<int(result.frame_count) {
		frame := ymd_frame_geometry(data, frame_table, frame_index)
		if !frame.valid { continue }
		if first_valid < 0 { first_valid = frame_index }
		triangles := frame.counts[0] + frame.counts[1] + frame.counts[2] +
			frame.counts[3] + (frame.counts[4] + frame.counts[5] + frame.counts[6]) * 2
		max_triangles = max(max_triangles, triangles)
	}
	if first_valid < 0 || max_triangles == 0 { delete(data); return result }
	result.animation_start = 0
	result.animation_length = result.frame_count
	result.triangle_count = i32(max_triangles)
	mesh: rl.Mesh
	mesh.vertexCount = i32(max_triangles * 3)
	mesh.triangleCount = i32(max_triangles)
	mesh.vertices = ([^]f32)(rl.MemAlloc(u32(max_triangles * 9 * size_of(f32))))
	mesh.normals = ([^]f32)(rl.MemAlloc(u32(max_triangles * 9 * size_of(f32))))
	mesh.colors = ([^]u8)(rl.MemAlloc(u32(max_triangles * 12)))
	fill_ymd_mesh(&mesh, data, color_base, ymd_frame_geometry(data, frame_table, first_valid))
	rl.UploadMesh(&mesh, true)
	result.model = rl.LoadModelFromMesh(mesh)
	result.data = data
	result.current_frame = -1
	result.valid = result.model.meshCount > 0
	return result
}

update_ymd_model :: proc(model: ^Ymd_Model, requested_frame: i32) {
	if !model.valid || model.frame_count <= 0 { return }
	frame_index := requested_frame % model.frame_count
	if frame_index < 0 { frame_index += model.frame_count }
	if frame_index == model.current_frame { return }
	vertex_count := int(u16_at(model.data, 0))
	metadata := 4 + vertex_count * 8
	color_base := metadata + 4
	frame_table := color_base + int(u16_at(model.data, metadata)) * 4
	frame := ymd_frame_geometry(model.data, frame_table, int(frame_index))
	if !frame.valid { return }
	mesh := &model.model.meshes[0]
	fill_ymd_mesh(mesh, model.data, color_base, frame)
	rl.UpdateMeshBuffer(mesh^, 0, mesh.vertices, mesh.vertexCount * 3 * size_of(f32), 0)
	rl.UpdateMeshBuffer(mesh^, 2, mesh.normals, mesh.vertexCount * 3 * size_of(f32), 0)
	rl.UpdateMeshBuffer(mesh^, 3, mesh.colors, mesh.vertexCount * 4, 0)
	model.current_frame = frame_index
}

make_cube_model :: proc(texture: rl.Texture2D) -> rl.Model {
	faces := [6][4]rl.Vector3{
		{{-0.5, 0.5, -0.5}, {-0.5, 0.5, 0.5}, {0.5, 0.5, 0.5}, {0.5, 0.5, -0.5}},
		{{-0.5, -0.5, 0.5}, {-0.5, -0.5, -0.5}, {0.5, -0.5, -0.5}, {0.5, -0.5, 0.5}},
		{{-0.5, -0.5, -0.5}, {-0.5, 0.5, -0.5}, {0.5, 0.5, -0.5}, {0.5, -0.5, -0.5}},
		{{0.5, -0.5, 0.5}, {0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5}, {-0.5, -0.5, 0.5}},
		{{-0.5, -0.5, 0.5}, {-0.5, 0.5, 0.5}, {-0.5, 0.5, -0.5}, {-0.5, -0.5, -0.5}},
		{{0.5, -0.5, -0.5}, {0.5, 0.5, -0.5}, {0.5, 0.5, 0.5}, {0.5, -0.5, 0.5}},
	}
	normals := [6]rl.Vector3{{0, 1, 0}, {0, -1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}}
	shades := [6]u8{255, 88, 168, 210, 132, 224}
	mesh: rl.Mesh
	mesh.vertexCount = 36
	mesh.triangleCount = 12
	mesh.vertices = ([^]f32)(rl.MemAlloc(36 * 3 * size_of(f32)))
	mesh.normals = ([^]f32)(rl.MemAlloc(36 * 3 * size_of(f32)))
	mesh.colors = ([^]u8)(rl.MemAlloc(36 * 4))
	mesh.texcoords = ([^]f32)(rl.MemAlloc(36 * 2 * size_of(f32)))
	output := 0
	face_order := [6]int{0, 1, 2, 0, 2, 3}
	uvs := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	for face in 0..<6 {
		for corner in face_order {
			vertex := faces[face][corner]
			mesh.vertices[output * 3 + 0] = vertex.x
			mesh.vertices[output * 3 + 1] = vertex.y
			mesh.vertices[output * 3 + 2] = vertex.z
			mesh.normals[output * 3 + 0] = normals[face].x
			mesh.normals[output * 3 + 1] = normals[face].y
			mesh.normals[output * 3 + 2] = normals[face].z
			uv := uvs[corner]
			mesh.texcoords[output * 2 + 0] = uv.x
			mesh.texcoords[output * 2 + 1] = uv.y
			mesh.colors[output * 4 + 0] = shades[face]
			mesh.colors[output * 4 + 1] = shades[face]
			mesh.colors[output * 4 + 2] = shades[face]
			mesh.colors[output * 4 + 3] = 255
			output += 1
		}
	}
	rl.UploadMesh(&mesh, false)
	model := rl.LoadModelFromMesh(mesh)
	rl.SetMaterialTexture(&model.materials[0], .ALBEDO, texture)
	return model
}
make_marker_model :: proc(texture: rl.Texture2D) -> rl.Model {
	model := rl.LoadModelFromMesh(rl.GenMeshPlane(0.96, 0.96, 1, 1))
	rl.SetMaterialTexture(&model.materials[0], .ALBEDO, texture)
	return model
}

unload_ymd_model :: proc(model: ^Ymd_Model) {
	if model.valid { rl.UnloadModel(model.model) }
	if model.data != nil { delete(model.data) }
	model^ = {}
}
