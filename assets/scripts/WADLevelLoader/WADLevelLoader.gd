extends Spatial

# 0.3(development release) - Godot 3 script for generate levels from WAD files
# originally created by Chaosus in 2017-2018
# MIT license

# EXPORTS

export(String) var WADPath = "e1m1.wad"

export(String) var LevelName = "E1M1"

export(int, "Map", "Geometry", "Overlay") var Mode = 0

export(SpatialMaterial) var DefaultWallMaterial = null

export(float) var Scale = 0.05

export(bool) var PrintDebugInfo = true

# CONSTANTS

const PIXELS_PER_UNIT = 64.0

const PIXELS_PER_FLAT = 64.0

const SHORT2FLOAT = 1.0 / PIXELS_PER_UNIT

const SKYTEXNAME = "F_SKY1"

const SHORTMAXVALUE = 32767

# I/O methods

func decode_32_as_string(file):
	var c1 = char(file.get_8())
	var c2 = char(file.get_8())
	var c3 = char(file.get_8())
	var c4 = char(file.get_8())
	return c1 + c2 + c3 + c4

func decode_64_as_string(file):
	var c1 = char(file.get_8())
	var c2 = char(file.get_8())
	var c3 = char(file.get_8())
	var c4 = char(file.get_8())
	var c5 = char(file.get_8())
	var c6 = char(file.get_8())
	var c7 = char(file.get_8())
	var c8 = char(file.get_8())
	return c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8

func read_lump(file):
	var lump = Lump.new()
	lump.offset = file.get_32()
	lump.size = file.get_32()
	lump.name = decode_64_as_string(file)
	return lump
 
# combine two bytes to short
func to_short(a, b):
	return wrapi((b << 8) | (a & 0xff), -32768, 32768)

# combine eight bytes to string
func combine_8_bytes_to_string(c1, c2, c3, c4, c5, c6, c7, c8):
	return char(c1) + char(c2) + char(c3) + char(c4) + char(c5) + char(c6) + char(c7) + char(c8)

# EXTRACTED TYPES

class Header:
	var type
	var lumpNum
	var dirOffset

class Lump:
	var offset
	var size
	var name

class Thing:
	var x
	var y
	var angle
	var type
	var options

# LINEDEF FLAGS
enum {
	LDF_IMPASSIBLE = 1,
	LDF_BLOCK_MONSTERS = 2,
	LDF_TWO_SIDED = 4
	LDF_UPPER_UNPEGGED = 8,
	LDF_LOWER_UNPEGGED = 16,
	LDF_SECRET = 32,
	LDF_BLOCK_SOUND = 64,
	LDF_NOT_ON_MAP = 128,
	LDF_ALREADY_ON_MAP = 256
}	

class Linedef:
	var start_vertex
	var end_vertex
	var flags
	var type
	var trigger
	var rsidenum
	var lsidenum

class Sidedef:
	var x_offset
	var y_offset
	var upper_texture
	var lower_texture
	var middle_texture
	var sector

class Vertex:
	var x
	var y
	func get_v2():
		return Vector2(x, y)
	
class Segment:
	var from
	var to
	var angle
	var linedef
	var direction
	var offset

class SubSector:
	var seg_num
	var seg_first

class Node:
	var x
	var y
	var dx
	var dy
	var y_upper_right
	var y_lower_right
	var x_lower_right
	var x_upper_right
	var y_upper_left
	var y_lower_left
	var x_lower_left
	var x_upper_left
	var node_right
	var node_left
	
class Sector:
	var floor_height
	var ceil_height
	var floor_texture
	var ceil_texture
	var light_level
	var special
	var tag

# Contains all extracted data
class Map:
	var things = []
	var linedefs = []
	var sidedefs = []
	var vertexes = []
	var segments = []
	var subsectors = []
	var nodes = []
	var sectors = []

# CUSTOM GEOMETRY TYPES

# SIDE TYPE
enum {
	ST_TOP,
	ST_MIDDLE
	ST_BOTTOM,
	ST_MAX
}

# FLAT TYPE
enum {
	FT_FLOOR
	FT_CEIL,
	FT_MAX
}

class MapObject:
	var mesh
	var material

class MapSide extends MapObject:
	var wall = null
	var upper_flat = null
	var upper_index1 = -1
	var upper_index2 = -1
	var lower_flat = null
	var lower_index1 = -1
	var lower_index2 = -1
	var peg_to_bottom = false

class MapFlat extends MapObject:
	var sides = []
	var height
	var prev_height

class MapWall extends MapObject:
	var flags
	var lsides = []
	var rsides = []

class MapTriangle:
	var v1
	var v2
	var v3
	var ld1
	var ld2
	var ld3
	var leftside1
	var leftside2
	var leftside3
	var sector
	func has_ld():
		return ld1 != -1 || ld2 != -1 || ld3 != -1

class Bounds:
	var xMin
	var yMin
	var xMax
	var yMax

# VARIABLES

var map = null
var flats = []
var walls = []
var triangles = []
var map_material

# FUNCTIONS

# <finished>
func get_flat_index(sector_index, is_ceiling):
	return sector_index * FT_MAX + (FT_CEIL if is_ceiling else FT_FLOOR)

# <finished>
func get_flat(sector_index, is_ceiling):
	return flats[get_flat_index(sector_index, is_ceiling)]

# <finished>
func get_sector_linedef_count(sector_index):
	if sector_index == -1:
		return 0
	var count = 0
	var i = 0
	while i < map.linedefs.size():
		var ld = map.linedefs[i]
		var rsector = map.sidedefs[ld.rsidenum].sector if ld.rsidenum != -1 else -1
		var lsector = map.sidedefs[ld.lsidenum].sector if ld.lsidenum != -1 else -1
		if rsector == sector_index || lsector == sector_index:
			count+=1
		i+=1
	return count

# <finished>
func is_sector_degenerative(sector_index):
	return get_sector_linedef_count(sector_index) < 3

# <almost_finished>
func load_wad(wad_path, level_name, mode):
	var buffer
	var i
	print("Opening %s" % wad_path + "...")
	
	var file = File.new() 
	if file.open(WADPath, File.READ) != OK:
		print("Failed to open WAD file %s" % wad_path)
		return
		
	if PrintDebugInfo:
		print("READING HEADER...")	
	var header = Header.new()  
	header.type = decode_32_as_string(file)
	header.lumpNum = file.get_32()
	header.dirOffset = file.get_32()
	
	if header.type != "IWAD" && header.type != "PWAD":
		print("ERROR: ",wad_path, "is not IWAD or PWAD !")
		return
	print(wad_path," is ", header.type)
	
	map = Map.new()
	
	if PrintDebugInfo:
		print("READING LUMPS...")
	
	var lump_mapname
	var lump_things
	var lump_linedefs
	var lump_sidedefs
	var lump_vertexes
	var lump_segs
	var lump_subsectors
	var lump_nodes
	var lump_sectors
	var lump_reject
	var lump_blockmap
	
	var breakAfter = false
	var lumps_readed = false
	var first = true
	file.seek(header.dirOffset)
	for i in range(header.lumpNum):
		if breakAfter && lumps_readed:
			break
		
		var lump = read_lump(file)
		if first:
			lump_mapname = lump
			first = false
		var name = lump.name
		#print(name)
		match lump.name:
			"THINGS":
				lump_things = lump
			"LINEDEFS":
				lump_linedefs = lump
			"SIDEDEFS":
				lump_sidedefs = lump
			"VERTEXES":
				lump_vertexes = lump
			"SEGS":
				lump_segs = lump
			"SSECTORS":
				lump_subsectors = lump
			"NODES":
				lump_nodes = lump
			"SECTORS":
				lump_sectors = lump
			"REJECT":
				lump_reject = lump
			"BLOCKMAP":
				lump_blockmap = lump
				if breakAfter:
					lumps_readed = true
			level_name:
				breakAfter = true
	if PrintDebugInfo:
		print("Internal map name: " + lump_mapname.name)
	
	if PrintDebugInfo:
		print("READING THINGS...")
	file.seek(lump_things.offset)
	buffer = file.get_buffer(lump_things.size)
	i = 0
	while i < buffer.size():
		var thing = Thing.new()
		thing.x = to_short(buffer[i], buffer[i+1])
		thing.y = to_short(buffer[i+2], buffer[i+3])
		thing.angle = to_short(buffer[i+4], buffer[i+5])
		thing.type = to_short(buffer[i+6], buffer[i+7])
		thing.options = to_short(buffer[i+8], buffer[i+9])
		map.things.push_back(thing)
		i+=10
		
	if PrintDebugInfo:
		print("READING LINEDEFS...")
	file.seek(lump_linedefs.offset)
	buffer = file.get_buffer(lump_linedefs.size)
	i = 0
	while i < buffer.size():
		var linedef = Linedef.new()
		linedef.start_vertex = to_short(buffer[i],buffer[i+1])
		linedef.end_vertex = to_short(buffer[i+2],buffer[i+3])
		linedef.flags = to_short(buffer[i+4],buffer[i+5])
		linedef.type = to_short(buffer[i+6],buffer[i+7])
		linedef.trigger = to_short(buffer[i+8],buffer[i+9])
		linedef.rsidenum = to_short(buffer[i+10],buffer[i+11])
		linedef.lsidenum = to_short(buffer[i+12],buffer[i+13])
		map.linedefs.push_back(linedef)
		i+=14
	
	if PrintDebugInfo:
		print("READING SIDEDEFS...")
	file.seek(lump_sidedefs.offset)
	buffer = file.get_buffer(lump_sidedefs.size)
	i = 0
	while i < buffer.size():
		var sidedef = Sidedef.new()
		sidedef.x_offset = to_short(buffer[i], buffer[i+1])
		sidedef.y_offset = to_short(buffer[i+2], buffer[i+3])
		sidedef.upper_texture = combine_8_bytes_to_string(buffer[i+4], buffer[i+5], buffer[i+6], buffer[i+7], buffer[i+8], buffer[i+9], buffer[i+10], buffer[i+11])
		sidedef.lower_texture = combine_8_bytes_to_string(buffer[i+12], buffer[i+13], buffer[i+14], buffer[i+15], buffer[i+16], buffer[i+17], buffer[i+18], buffer[i+19])
		sidedef.middle_texture = combine_8_bytes_to_string(buffer[i+20], buffer[i+21], buffer[i+22], buffer[i+23], buffer[i+24], buffer[i+25], buffer[i+26], buffer[i+27])
		sidedef.sector = to_short(buffer[i+28], buffer[i+29])
		map.sidedefs.push_back(sidedef)
		i+=30
		
	if PrintDebugInfo:
		print("READING VERTEXES...")
	file.seek(lump_vertexes.offset)
	buffer = file.get_buffer(lump_vertexes.size)
	i = 0
	while i < buffer.size():
		var x = to_short(buffer[i], buffer[i+1]) * Scale
		var y = to_short(buffer[i+2], buffer[i+3]) * Scale
		var vertex = Vertex.new()
		vertex.x = float(x)
		vertex.y = float(y)	
		map.vertexes.push_back(vertex)
		i+=4
	
	if PrintDebugInfo:
		print("READING SUB-SECTORS...")
	file.seek(lump_subsectors.offset)
	buffer = file.get_buffer(lump_subsectors.size)
	i = 0
	while i < buffer.size():
		var subsector = SubSector.new()
		subsector.seg_num = to_short(buffer[i],buffer[i+1])
		subsector.seg_first = to_short(buffer[i+2],buffer[i+3])
		map.subsectors.push_back(subsector)
		i+=4
	
	if PrintDebugInfo:
		print("READING NODES...")
	file.seek(lump_nodes.offset)
	buffer = file.get_buffer(lump_nodes.size)
	i = 0
	while i < buffer.size():
		var node = Node.new()
		node.x = to_short(buffer[i],buffer[i+1])
		node.y = to_short(buffer[i+2],buffer[i+3])
		node.dx = to_short(buffer[i+4],buffer[i+5])
		node.dy = to_short(buffer[i+6],buffer[i+7])		
		node.y_upper_right = to_short(buffer[i+8],buffer[i+9])
		node.y_lower_right = to_short(buffer[i+10],buffer[i+11])
		node.x_lower_right = to_short(buffer[i+12],buffer[i+13])
		node.x_upper_right = to_short(buffer[i+14],buffer[i+15])
		node.y_upper_left = to_short(buffer[i+16],buffer[i+17])
		node.y_lower_left = to_short(buffer[i+18],buffer[i+19])
		node.x_lower_left = to_short(buffer[i+20],buffer[i+21])
		node.x_upper_left = to_short(buffer[i+22],buffer[i+23])
		node.node_right = to_short(buffer[i+24],buffer[i+25])
		node.node_left = to_short(buffer[i+26],buffer[i+27])
		map.nodes.push_back(node)
		i+=28
	
	if PrintDebugInfo:
		print("READING SECTORS...")
	file.seek(lump_sectors.offset)
	buffer = file.get_buffer(lump_sectors.size)
	i = 0
	while i < buffer.size():
		var sector = Sector.new()
		sector.floor_height = to_short(buffer[i],buffer[i+1])
		sector.ceil_height = to_short(buffer[i+2],buffer[i+3])
		sector.floor_texture = combine_8_bytes_to_string(buffer[i+4], buffer[i+5], buffer[i+6], buffer[i+7], buffer[i+8], buffer[i+9], buffer[i+10], buffer[i+11])
		sector.ceil_texture = combine_8_bytes_to_string(buffer[i+12], buffer[i+13], buffer[i+14], buffer[i+15], buffer[i+16], buffer[i+17], buffer[i+18], buffer[i+19])
		sector.light_level = to_short(buffer[i+20], buffer[i+21])
		sector.special = to_short(buffer[i+22], buffer[i+23])
		sector.tag = to_short(buffer[i+24], buffer[i+25])
		map.sectors.push_back(sector)
		i+=26
	file.close()
	
	if PrintDebugInfo:
		print("BUILDING GEOMETRY")
	
	map_material = SpatialMaterial.new()
	map_material.flags_unshaded = true
	map_material.flags_vertex_lighting = true
	map_material.vertex_color_use_as_albedo = true
	
	flats.resize(map.sectors.size() * 2)
	walls.resize(map.linedefs.size())
	
	match mode:
		0:
			build_map_geometry()
		1:
			build_level_geometry()
		2:
			build_map_geometry()
			build_level_geometry()
				
#	if mode == 1 or mode == 2: # Geometry mode or Overlay mode	
#		var polycount = polygons.size()
#		for sector in sectors:
#			var geometry = ImmediateGeometry.new()
#			geometry.material_override = DefaultWallMaterial
#			for s in sector.faceset_floor.segments:
#				geometry.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
#				geometry.set_color(Color(1,1,1))
#				var height = sector.floor_height / 3 # (sector.ceil_height - sector.floor_height) / 10
#				geometry.set_uv(Vector2(0,0))
#				geometry.add_vertex(Vector3(s.v1.x, 0, s.v1.y))
#				geometry.set_uv(Vector2(1,0))
#				geometry.add_vertex(Vector3(s.v2.x, 0, s.v2.y))
#				geometry.set_uv(Vector2(0,1))
#				geometry.add_vertex(Vector3(s.v1.x, height, s.v1.y))			
#				geometry.set_uv(Vector2(1,1))
#				geometry.add_vertex(Vector3(s.v2.x, height, s.v2.y))
#				geometry.end()		
#			add_child(geometry)


# <unfinished>
func build_level_geometry():
	
	triangulate()
	finish_triangles()
	
	for i in range(map.sectors.size()):
		build_sector(i)
	
	for i in range(map.linedefs.size()):
		build_wall(i)

# <finished>
func add_point_to_rect(rect, point):
	rect.xMin = min(rect.xMin, point.x)
	rect.yMin = min(rect.yMin, point.y)
	rect.xMax = max(rect.xMax, point.x)
	rect.yMax = max(rect.yMax, point.y)
	return rect

# <finished>
func get_bbox():
	var bbox = Bounds.new()
	bbox.xMin = INF
	bbox.yMin = INF
	bbox.xMax = -INF
	bbox.yMax = -INF
	
	for v in map.vertexes:
		bbox = add_point_to_rect(bbox, v)
	
	return bbox

# <finished>
func get_taper_rect(rect, offset):
	rect.xMin += offset
	rect.yMin += offset
	rect.xMax -= offset
	rect.yMax -= offset
	return rect

class LinedefResult:
	var index
	var left_side

func find_linedef_by_vertices(v1, v2):
	var result = LinedefResult.new()
	result.index = -1
	for i in range(map.linedefs.size()):
		var ld = map.linedefs[i]
		if ld.start_vertex == v1 && ld.end_vertex == v2:
			result.left_side = true
			result.index = i
			return result
		if ld.start_vertex == v2 && ld.end_vertex == v1:
			result.left_side = false
			result.index = i
	return result
	

# <unfinished>
func triangulate():
	var bbox = get_bbox()
	bbox = get_taper_rect(bbox, -500.0)	

# <finished>
func get_sector_by_linedef(ld_index, left_side, only_non_degenerative):
	if ld_index == -1:
		return -1
	
	var ld = map.linedefs[ld_index]
	var sidedef_index = ld.lsidenum if left_side else ld.rsidenum
	
	if sidedef_index == -1:
		return -1
		
	var sector_index = map.sidedefs[sidedef_index].sector
	if sector_index == -1:
		return -1
	
	if only_non_degenerative:
		if is_sector_degenerative(sector_index):
			return -1
	
	return sector_index

# <finished>
func get_sector_by_triangle(triangle):
	var sector_index = 0
	sector_index = get_sector_by_linedef(triangle.ld3, triangle.leftside3, true)
	if sector_index != -1:
		return sector_index
	
	sector_index = get_sector_by_linedef(triangle.ld2, triangle.leftside2, true );
	if sector_index != -1:
		return sector_index;
	
	sector_index = get_sector_by_linedef(triangle.ld1, triangle.leftside1, true );
	if sector_index != -1:
		return sector_index;
	
	return -1

# <finished>
func find_triangle_by_vertices(triangle_indices, v1, v2):
	for i in triangle_indices:
		var t = triangles[i]
		
		# CW winding
		if (t.v1 == v1 && t.v2 == v2) || (t.v2 == v1 && t.v3 == v2) || (t.v3 == v1 && t.v1 == v2):
			return i
		
		# CCW winding
		if (t.v1 == v2 && t.v2 == v1) || (t.v2 == v2 && t.v3 == v1) || (t.v3 == v2 && t.v1 == v1):
			return i
	return -1

# <need_test>
func find_sector_by_triangle(triangle_index):
	var availablelist = []
	var checklist = []
	
	for i in range(triangles.size()):
		if i != triangle_index:
			availablelist.push_back(i)
	
	checklist.push_back(triangle_index)
	
	var max_iterations = 32
	var iteration = 0
	
	while availablelist.size() > 0:
		for i in checklist:
			var t = triangles[i]
			if t.has_ld():
				return get_sector_by_triangle(t)
	
		var neightbourlist = [] # to PoolIntArray
		for i in checklist:
			var t = triangles[i]
			for j in range(3):
				var index1 = t.v1 if j == 0 else t.v2 if j == 1 else t.v3
				var index2 = t.v2 if j == 0 else t.v3 if j == 1 else t.v1
				var n = find_triangle_by_vertices(availablelist, index1, index2)
				if n != -1:
					neightbourlist.push_back(n)
					availablelist.remove(n)
		checklist = neightbourlist
		iteration+=1
		if iteration >= max_iterations:
			break
	
	return -1
	
# <unfinished>
func finish_triangles():
	
#	for i in range(0, map.linedefs.size()): # pointSet.Triangles[ i ];
#		var ld = map.linedefs[i]
#		var triangle = MapTriangle.new()
#
#		triangle.v1 = 0
#		triangle.v2 = 0
#		triangle.v3 = 0
#
#		var ld1 = find_linedef_by_vertices(triangle.v1, triangle.v2)
#		var ld2 = find_linedef_by_vertices(triangle.v2, triangle.v3)
#		var ld3 = find_linedef_by_vertices(triangle.v3, triangle.v1)
#
#		triangle.ld1 = ld1.index
#		triangle.ld2 = ld2.index
#		triangle.ld3 = ld3.index
#
#		triangle.leftside1 = ld1.left_side
#		triangle.leftside2 = ld2.left_side
#		triangle.leftside3 = ld3.left_side
#
#		triangle.sector = get_sector_by_triangle(triangle)
#		triangles.push_back(triangle)
#		print(str(i))
	
	for i in range(triangles.size()):
		var t = triangles[i]
		if t.sector == -1:
			t.sector = find_sector_by_triangle(i)
			triangles[i] = t
			
	pass

# <finished>
func build_sector(sector_index):
	if is_sector_degenerative(sector_index):
		return
	var sector = map.sectors[sector_index]
	
	var sector_triangles = []
	var vertex_indices = []
	
	# choose sector triangles
	for t in triangles:
		if t.sector == sector_index:
			sector_triangles.push_back(t)
			vertex_indices.push_back(t.v1)
			vertex_indices.push_back(t.v2)
			vertex_indices.push_back(t.v3)
	
	# build sector vertices array
	var sector_vertices = []
	for i in range(vertex_indices.size()):
		sector_vertices.push_back(SHORT2FLOAT * map.vertices[vertex_indices[i]].get_v2())
	
	# map triangle indexes from global array to local
	for i in range(sector_triangles.size()):
		var t = sector_triangles[i]
		t.v1 = vertex_indices.find(t.v1)
		t.v2 = vertex_indices.find(t.v2)
		t.v3 = vertex_indices.find(t.v3)
		sector_triangles[i] = t
	
	# create floor and ceiling flats
	build_sector_flat(sector_index, vertex_indices, sector_vertices, sector_triangles, false)
	build_sector_flat(sector_index, vertex_indices, sector_vertices, sector_triangles, true)

# <unfinished>
func create_material(texture_name, is_transparent):
	var material = SpatialMaterial.new()
	return material

# <unfinished>
func build_sector_flat(sector_index, vertex_indices, sector_vertices, sector_triangles, is_ceiling):
	var sector = map.sectors[sector_index]
	var texture_name = sector.ceil_texture if is_ceiling else sector.floor_texture
	var is_sky = texture_name == SKYTEXNAME
	var brightness = sector.light_level / SHORTMAXVALUE
	var color = Color(brightness, brightness, brightness, 1.0)
	var uv_tiling = PIXELS_PER_UNIT / PIXELS_PER_FLAT
	var material = create_material(texture_name, false)
	var height = SHORT2FLOAT * (sector.ceil_height if is_ceiling else sector.floor_height)
	var mesh = ImmediateGeometry.new()
	mesh.name = "sector_" + str(sector_index) + "_" + ("ceiling" if is_ceiling else "floor")
	
	var flat_vertices = []
	var flat_colors = []
	var flat_triangle_indices = []
	var flat_uv = []
	
	var center = Vector3()
	for v in sector_vertices:
		center += Vector3(v.x, 0.0, v.y)
	center /= float(sector_vertices.size())
	center.y = height
	
	if is_nan(center.x) || is_nan(center.z):
		pass
	
	for v in sector_vertices:
		flat_vertices.push_back(Vector3(v.x, height, v.y) - center)
		flat_colors.push_back(color)
		flat_uv.push_back = v * uv_tiling
	
	for i in range(sector_triangles.size()):
		var t = sector_triangles[i]
		if is_ceiling:
			flat_triangle_indices[i * 3] = t.v1
			flat_triangle_indices[i * 3 + 1] = t.v2
			flat_triangle_indices[i * 3 + 2] = t.v3
		else:
			flat_triangle_indices[i * 3] = t.v1
			flat_triangle_indices[i * 3 + 1] = t.v3
			flat_triangle_indices[i * 3 + 2] = t.v2
	
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(flat_vertices.size()):
		mesh.set_color(flat_colors[i])
		mesh.set_uv(flat_uv[i])
		mesh.add_vertex(flat_vertices[i])
	mesh.end()
	
	add_child(mesh)
	
	var flat_index = get_flat_index(sector_index, is_ceiling)
	var flat = MapFlat.new()
	flat.mesh = mesh
	flat.material = material
	flats[flat_index] = flat
	
	
# <finished>
func build_wall(ld_index):
	
	var ld = map.linedefs[ld_index]	
		
	var v1 = ld.start_vertex
	var v2 = ld.end_vertex
		
	var twoSided = ld.flags & LDF_TWO_SIDED
	var topUnpegged = ld.flags & LDF_UPPER_UNPEGGED
	var bottomUnpegged = ld.flags & LDF_LOWER_UNPEGGED
	
	var wall = MapWall.new()
	wall.flags = ld.flags
	
	if twoSided:		
		var rsd = map.sidedefs[ld.rsidenum]
		var lsd = map.sidedefs[ld.lsidenum]
		
		var rs = map.sectors[rsd.sector]
		var ls = map.sectors[lsd.sector]
		
		var rfloorh = SHORT2FLOAT * rs.floor_height
		var rceilh = SHORT2FLOAT * rs.ceil_height
		
		var lfloorh = SHORT2FLOAT * ls.floor_height
		var lceilh = SHORT2FLOAT * ls.ceil_height
	
		var upperFloor = get_flat(lsd.sector, false) if rfloorh < lfloorh else get_flat(rsd.sector, false)
		var lowerCeiling = get_flat(lsd.sector, true) if lceilh < rceilh else get_flat(rsd.sector, true)
		
		# VALIDATE SIDEDEF TEXTURES
		
		if rfloorh != lfloorh:
			if rsd.lower_texture == "-":
				rsd.lower_texture = lsd.lower_texture
			elif lsd.lower_texture == "-":
				lsd.lower_texture = rsd.lower_texture
		
		if rceilh != lceilh:
			if rsd.upper_texture == "-":
				rsd.upper_texture = lsd.upper_texture
			elif lsd.upper_texture == "-":
				lsd.upper_texture = rsd.upper_texture
		
		# TOP WALL
		
		if rceilh > lceilh:
			build_wall_side(ld.rsidenum, ld.start_vertex, ld.end_vertex, 
			lceilh, rceilh,
			ST_TOP, twoSided, !topUnpegged, wall, false,
			get_flat(rsd.sector, true), get_flat(lsd.sector, true))
		elif lceilh > rceilh:
			build_wall_side(ld.lsidenum, ld.end_vertex, ld.start_vertex,
			rceilh, lceilh,
			ST_TOP, twoSided, !topUnpegged, wall, true,
			get_flat(lsd.sector, true), get_flat(rsd.sector, true))
			
		# MIDDLE WALL
		
		if rsd.middle_texture != "-":
			build_wall_side(ld.rsidenum, ld.start_vertex, ld.end_vertex,
			upperFloor.height, lowerCeiling.height, ST_MIDDLE, twoSided, bottomUnpegged,
			wall, false, lowerCeiling, upperFloor)
		
		if lsd.middle_texture != "-":
			build_wall_side(ld.lsidenum, ld.end_vertex, ld.start_vertex,
			upperFloor.height, lowerCeiling.height, ST_MIDDLE, twoSided, bottomUnpegged,
			wall, true, lowerCeiling, upperFloor)
		
		# BOTTOM WALL
			if rfloorh < lfloorh:
				build_wall_side(ld.rsidenum, ld.start_vertex, ld.end_vertex,
				rfloorh, lfloorh, ST_BOTTOM, twoSided, bottomUnpegged, wall, false,
				get_flat(lsd.sector, false), get_flat(rsd.sector, false))
			elif lfloorh < rfloorh:
				build_wall_side(ld.lsidenum, ld.end_vertex, ld.start_vertex,
				lfloorh, rfloorh, ST_BOTTOM, twoSided, bottomUnpegged, wall, true,
				get_flat(rsd.sector, false), get_flat(lsd.sector, false))
	else: # ONE_SIDED
		var isLeftSide = false
		var sd_index = ld.rsidenum
		if sd_index == -1:
			isLeftSide = true
			sd_index =ld.lsidenum
			# SWAP
			var temp = v1
			v1 = v2
			v2 = temp
		var sd = map.sidedefs[sd_index]
		var s  = map.sectors[sd.sector]
		
		var floorh = SHORT2FLOAT * s.floor_height
		var ceilh = SHORT2FLOAT * s.ceil_height
		
		build_wall_side(ld.rsidenum, v1, v2, floorh, ceilh, ST_MIDDLE, twoSided, bottomUnpegged, wall, isLeftSide,
		get_flat(sd.sector, true), get_flat(sd.sector, false))

# <unfinished>
func build_wall_side(sd_index, v_index1, v_index2, floor_h, ceil_h, type, two_sided, peg_to_bottom, wall, is_left_side, upper_flat, lower_flat):
	
	if sd_index == -1:
		return
		
	var v1 = SHORT2FLOAT * map.vertexes[v_index1].get_v2()
	var v2 = SHORT2FLOAT * map.vertexes[v_index2].get_v2()
	var sd = map.sidedefs[sd_index]

# <almost_finished>
func build_map_geometry():
	var i = 0
	var map_spatial = Spatial.new()
	map_spatial.name = "Map"
	add_child(map_spatial)
	for ld in map.linedefs:
		var v1 = ld.start_vertex
		var v2 = ld.end_vertex
		
		var vertex1 = map.vertexes[v1]
		var vertex2 = map.vertexes[v2]
		var geometry = ImmediateGeometry.new()
		geometry.name = "mapline_" + str(i) 
		geometry.material_override = map_material
		geometry.begin(Mesh.PRIMITIVE_LINES)
		if ld.type != 0:
			geometry.set_color(ColorN("yellow"))
		else:
			geometry.set_color(ColorN("red"))
		geometry.add_vertex(Vector3(vertex1.x, 0, vertex1.y))
		geometry.add_vertex(Vector3(vertex2.x, 0, vertex2.y))
		geometry.end()			
		map_spatial.add_child(geometry)
		i+=1
func _ready():	
	load_wad(WADPath, LevelName, Mode)