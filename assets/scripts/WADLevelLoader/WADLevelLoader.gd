extends Spatial

# v0.1 - Godot script for generate levels from WAD files
# originally created by Chaosus in 2017

export(String) var WADPath = "e1m1.wad"

export(String) var LevelName = "E1M1"

export(float) var Scale = 0.05

export(bool) var PrintDebugInfo = true

var SurfaceMaterial

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

class Header:
	var type
	var lumpNum
	var dirOffset

class Lump:
	var offset
	var size
	var name
	
class Vertex:
	var x
	var y

class Linedef:
	var start_vertex
	var end_vertex
	var flags
	var type
	var trigger
	var right_sidedef
	var left_sidedef

class Segment:
	var from
	var to
	var angle
	var linedef
	var direction
	var offset

func read_lump(file):
	var lump = Lump.new()
	lump.offset = file.get_32()
	lump.size = file.get_32()
	lump.name = decode_64_as_string(file)
	return lump
 
func combine_bytes(a, b):
	return (b << 8) | (a & 0xff)

func _ready():
	var buffer
	var i
	
	if SurfaceMaterial == null:
		SurfaceMaterial = SpatialMaterial.new()
		SurfaceMaterial.flags_unshaded = true
		
	print("Opening %s" % WADPath + "...")
	
	var file = File.new() 
	if file.open(WADPath, File.READ) != OK:
		print("Failed to open WAD file %s" % WADPath)
		return
		
	if PrintDebugInfo:
		print("READING HEADER...")	
	var header = Header.new()  
	header.type = decode_32_as_string(file)
	header.lumpNum = file.get_32()
	header.dirOffset = file.get_32()
	
	if PrintDebugInfo:
		print("READING LUMPS...")
	
	var lump_things
	var lump_linedefs
	var lump_sidedefs
	var lump_vertexes
	var lump_segs
	var lump_ssectors
	var lump_nodes
	var lump_sectors
	var lump_reject
	var lump_blockmap
	
	var breakAfter = false
	file.seek(header.dirOffset)
	for i in range(header.lumpNum):
		var lump = read_lump(file)
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
				lump_ssectors = lump
			"NODES":
				lump_nodes = lump
			"SECTORS":
				lump_sectors = lump
			"REJECT":
				lump_reject = lump
			"BLOCKMAP":
				lump_blockmap = lump
				if breakAfter:
					break
			LevelName:
				breakAfter = true
					
	if PrintDebugInfo:
		print("READING VERTEXES...")
	file.seek(lump_vertexes.offset)
	var vertexes = []
	buffer = file.get_buffer(lump_vertexes.size)
	i = 0
	while i < buffer.size():
		var x = wrapi(combine_bytes(buffer[i], buffer[i+1]), -32768, 32768) * Scale
		var y = wrapi(combine_bytes(buffer[i+2], buffer[i+3]), -32768, 32768) * Scale
		var vertex = Vertex.new()
		vertex.x = float(x)
		vertex.y = float(y)	
		vertexes.push_back(vertex)
		i+=4
	if PrintDebugInfo:		
		print("READING LINEDEFS...")	
	file.seek(lump_linedefs.offset)
	var linedefs = []
	buffer = file.get_buffer(lump_linedefs.size)
	i = 0
	while i < buffer.size():
		var linedef = Linedef.new()
		linedef.start_vertex = combine_bytes(buffer[i],buffer[i+1])
		linedef.end_vertex = combine_bytes(buffer[i+2],buffer[i+3])
		linedef.flags = combine_bytes(buffer[i+4],buffer[i+5])
		linedef.type = combine_bytes(buffer[i+6],buffer[i+7])
		linedef.trigger = combine_bytes(buffer[i+8],buffer[i+9])
		linedef.right_sidedef = combine_bytes(buffer[i+10],buffer[i+11])
		linedef.left_sidedef = combine_bytes(buffer[i+12],buffer[i+13])
		linedefs.push_back(linedef)
		i+=14
	
	file.close()
	
	i = 0
	if PrintDebugInfo:
		print("BUILDING GEOMETRY")
	for ld in linedefs:
		var vertex1 = vertexes[ld.start_vertex]
		var vertex2 = vertexes[ld.end_vertex]
		var geometry = ImmediateGeometry.new()
		geometry.material_override = SurfaceMaterial
		geometry.begin(Mesh.PRIMITIVE_LINES)
		geometry.set_color(Color(1,1,1))
		geometry.add_vertex(Vector3(vertex1.x,0,vertex1.y))
		geometry.add_vertex(Vector3(vertex2.x,0,vertex2.y))
		geometry.end()
		add_child(geometry)
		i+=1
