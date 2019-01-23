#----------------------------------------------------------------------
#                      T R I A N G U L A T E . R B
#----------------------------------------------------------------------
#
#               Converts faces from polygons to triangles
#
#                    Copyright (c) 2009 Osbo Design
#                            http://osbo.com
#
#----------------------------------------------------------------------
# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#----------------------------------------------------------------------

require 'sketchup.rb'

#----------------------------------------------------------------------
# S T A R T
#----------------------------------------------------------------------
basename = File.basename(__FILE__)

unless file_loaded?(basename)

	UI.menu("Plugins").add_item("Triangulate") {Triangulate.new}
	file_loaded(basename)

end

#----------------------------------------------------------------------
# C L A S S
#----------------------------------------------------------------------
class Triangulate

#----------------------------------------------------------------------
# I N I T I A L I Z E
#----------------------------------------------------------------------
def initialize

	model = Sketchup.active_model

	model.start_operation("Triangulate")

	explode
	triangulate

	model.commit_operation

	UI.beep

end

#----------------------------------------------------------------------
# E X P L O D E
#----------------------------------------------------------------------
# Explodes the model, or selection, if it contains components or
# groups.
#----------------------------------------------------------------------
def explode

	model      = Sketchup.active_model
	selection  = model.selection
	entities   = model.active_entities
	components = selection.find_all {|s| s.typename == "ComponentInstance"}
	components = entities.find_all {|e| e.typename == "ComponentInstance"} if selection.empty?
	groups     = selection.find_all {|s| s.typename == "Group"}
	groups     = entities.find_all {|e| e.typename == "Group"} if selection.empty?
	count      = components.length + groups.length

	while 0 < count
		components.each { |c|
			explosion = c.explode
			explosion.each { |e|
				if ((e.typename == "ComponentInstance") || (e.typename == "Edge") || (e.typename == "Face") || (e.typename == "Group"))
					selection.add(e)
				end
			}
		}

		groups.each { |g|
			explosion = g.explode
			explosion.each { |e|
				if ((e.typename == "ComponentInstance") || (e.typename == "Edge") || (e.typename == "Face") || (e.typename == "Group"))
					selection.add(e)
				end
			}
		}

		components = selection.find_all {|s| s.typename == "ComponentInstance"}
		components = entities.find_all {|e| e.typename == "ComponentInstance"} if selection.empty?
		groups     = selection.find_all {|s| s.typename == "Group"}
		groups     = entities.find_all {|e| e.typename == "Group"} if selection.empty?
		count      = components.length + groups.length
	end

end

#----------------------------------------------------------------------
# T R I A N G U L A T E
#----------------------------------------------------------------------
# Triangulates the model, or selection, if it contains polygons larger
# than a triangle.
#----------------------------------------------------------------------
def triangulate

	model     = Sketchup.active_model
	selection = model.selection
	entities  = model.active_entities
	faces     = selection.find_all {|s| s.typename == "Face"}
	faces     = entities.find_all {|e| e.typename == "Face"} if selection.empty?

	faces.each { |f|
		if 3 < f.vertices.length
			mesh  = f.mesh(0)
			front = f.material
			back  = f.back_material

			f.erase!
			first = entities.length
			entities.add_faces_from_mesh(mesh, 7)
			last = entities.length

			count = last - first

			while 0 < count
				entity = entities[(last - count)]
				selection.add(entity)

				if entity.typename == "Face"
					entity.material      = front
					entity.back_material = back
				end

				count -= 1
			end
		end
	}

end

end