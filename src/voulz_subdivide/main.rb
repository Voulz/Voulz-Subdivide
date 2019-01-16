require_relative "utils/Utils"
require_relative "Tool"

# TODO: Have to test with:
# - faces with textures
# - faces with hidden edges
# - faces with smooth edges
# - faces with soft edges
# - groups (make sure it only affects the ones visible)
# - component (option to subdivide only the selected one or all)
# - try running the tool while editing a group with different origin
module Voulz::Plugins::VoulzSubdivide
  DEBUG ||= true

  # --------------------------------------------------------
  #                       MENU ITEMS
  # --------------------------------------------------------
  unless file_loaded?(__FILE__)
    plugins_menu = UI.menu("Plugins")
    voulzmenu = plugins_menu.add_submenu("Voulz")

    voulzmenu.add_item("Subdivide") {
      puts "\n -- #{self.class} reloaded #{reload} files\n\n" if DEBUG
      Sketchup.active_model.select_tool(Tool.new)
    }

    #   menu.add_separator

    #   item = menu.add_item("Settings...") { }
    #   plugins_menu.set_validation_proc(item) {
    # 	 MF_GRAYED
    #   }
    item = voulzmenu.add_item("Subdivide Reload") {
      puts "\n -- #{self.class} reloaded #{reload} files\n\n"
    } if DEBUG
  end

  # --------------------------------------------------------
  #                     PUBLIC METHODS
  # --------------------------------------------------------

  module_function

  # Triangulate the given entities.
  # This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Geom::Transformation | nil ] tr The transformation of the current entities
  def triangulate_to_a(entities, tr = nil)
    tr ||= Geom::Transformation.new
    triangles = []
    entities.each { |ent|
      next if !ent.valid? || ent.hidden? || !ent.layer.visible?
      if ent.is_a?(Sketchup::Face)
        faces = []
        mesh = ent.mesh
        for i in 1..mesh.count_polygons
          pts = mesh.polygon_points_at(i)
          faces << pts.map { |p| p.transform(tr) } if pts.length == 3 #TODO: Check if there is the need to handle more polygons
        end
        triangles << faces
      elsif ent.respond_to?(:transformation) && ent.respond_to?(:definition)
        triangles += triangulate_to_a(ent.definition.entities, tr * ent.transformation)
      end
    }
    triangles
  end

  # Triangulate and then subdivide entities until each edge of each triangle has a maximum length of max_length.
  # This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
  # @param [ Geom::Transformation | nil ] tr The transformation of the current entities
  def subdivide_length_to_a(entities, max_length, tr = nil)
    max_length = 1 if max_length <= 0

    tr ||= Geom::Transformation.new
    triangles = []
    entities.each { |ent|
      next if !ent.valid? || ent.hidden? || !ent.layer.visible?
      if ent.is_a?(Sketchup::Face)
        faces = []
        mesh = ent.mesh
        for i in 1..mesh.count_polygons
          pts = mesh.polygon_points_at(i)
          next unless pts.length == 3 #TODO: Check if there is the need to handle more polygons
          faces += subdivide_length_face_to_a(*pts.map { |p| p.transform(tr) }, max_length)
        end
        triangles << faces
      elsif ent.respond_to?(:transformation) && ent.respond_to?(:definition)
        triangles += subdivide_length_to_a(ent.definition.entities, max_length, tr * ent.transformation)
      end
    }
    triangles
  end

  # Subdivide a triangle until each edge has a maximum length of max_length.
  # This version will output an Array Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Point3d ] p1
  # @param [ Sketchup::Point3d ] p2
  # @param [ Sketchup::Point3d ] p3
  # @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
  def subdivide_length_face_to_a(p1, p2, p3, max_length)
    pts_to_process = [[p1, p2, p3]]
    done = []
    while (pts = pts_to_process.shift)
      p1, p2, p3 = pts
      e1 = p1.vector_to(p2); l1 = Voulz::Utils.<=(e1.length, max_length)
      e2 = p2.vector_to(p3); l2 = Voulz::Utils.<=(e2.length, max_length)
      e3 = p3.vector_to(p1); l3 = Voulz::Utils.<=(e3.length, max_length)
      if l1 && l2 && l3
        #all edges smaller
        done << [p1, p2, p3]
      elsif l1 && l2
        #1 edge bigger
        mid = p3 + e3.to_a.map { |x| x / 2 }
        pts_to_process += [[p1, p2, mid], [mid, p2, p3]]
      elsif l2 && l3
        #1 edge bigger
        mid = p1 + e1.to_a.map { |x| x / 2 }
        pts_to_process += [[p1, mid, p3], [mid, p2, p3]]
      elsif l1 && l3
        #1 edge bigger
        mid = p2 + e2.to_a.map { |x| x / 2 }
        pts_to_process += [[p1, p2, mid], [p1, mid, p3]]
      elsif l1
        #2 edges bigger
        mid2 = p2 + e2.to_a.map { |x| x / 2 }
        mid3 = p3 + e3.to_a.map { |x| x / 2 }
        if p1.vector_to(mid2).length > p2.vector_to(mid3).length
          pts_to_process += [[p1, p2, mid3], [p2, mid2, mid3], [mid3, mid2, p3]]
        else
          pts_to_process += [[p1, p2, mid2], [p1, mid2, mid3], [mid3, mid2, p3]]
        end
      elsif l2
        #2 edges bigger
        mid1 = p1 + e1.to_a.map { |x| x / 2 }
        mid3 = p3 + e3.to_a.map { |x| x / 2 }
        #   pts_to_process += [[p1, mid1, mid3], [mid1, p2, p3], [mid3, mid1, p3]]
        if p2.vector_to(mid3).length > p3.vector_to(mid1).length # if a diagonal is longer than the other, create the short one
          pts_to_process += [[p1, mid1, mid3], [mid1, p3, mid3], [mid1, p2, p3]]
        else
          pts_to_process += [[p1, mid1, mid3], [mid1, p2, mid3], [mid3, p2, p3]]
        end
      elsif l3
        #2 edges bigger
        mid1 = p1 + e1.to_a.map { |x| x / 2 }
        mid2 = p2 + e2.to_a.map { |x| x / 2 }
        #   pts_to_process += [[p1, mid1, mid2], [mid2, mid1, p2], [p1, mid2, p3]]
        if p3.vector_to(mid1).length > p1.vector_to(mid2).length # if a diagonal is longer than the other, create the short one
          pts_to_process += [[mid2, mid1, p2], [p1, mid1, mid2], [p1, mid2, p3]]
        else
          pts_to_process += [[mid2, mid1, p2], [p1, mid1, p3], [p3, mid1, mid2]]
        end
      else
        # all bigger
        mid1 = p1 + e1.to_a.map { |x| x / 2 }
        mid2 = p2 + e2.to_a.map { |x| x / 2 }
        mid3 = p3 + e3.to_a.map { |x| x / 2 }
        pts_to_process += [[p1, mid1, mid3], [mid3, mid1, mid2], [mid2, mid1, p2], [mid3, mid2, p3]]
      end # end if
    end # end while
    done
  end

  # Triangulate and then subdivide entities the given number of times, independantly of their size
  # This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
  # @param [ Geom::Transformation | nil ] tr The transformation of the current entities
  def subdivide_to_a(entities, nbtimes, tr = nil)
    return triangulate_to_a(entities, tr) if nbtimes < 1

    tr ||= Geom::Transformation.new
    triangles = []
    entities.each { |ent|
      next if !ent.valid? || ent.hidden? || !ent.layer.visible?
      if ent.is_a?(Sketchup::Face)
        faces = []
        mesh = ent.mesh
        for i in 1..mesh.count_polygons
          pts = mesh.polygon_points_at(i)
          next unless pts.length == 3 #TODO: Check if there is the need to handle more polygons
          faces += subdivide_face_to_a(*pts.map { |p| p.transform(tr) }, nbtimes)
        end
        triangles << faces
      elsif ent.respond_to?(:transformation) && ent.respond_to?(:definition)
        triangles += subdivide_to_a(ent.definition.entities, nbtimes, tr * ent.transformation)
      end
    }
    triangles
  end

  # Subdivide a triangle until each edge has a maximum length of max_length.
  # This version will output an Array Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Point3d ] p1
  # @param [ Sketchup::Point3d ] p2
  # @param [ Sketchup::Point3d ] p3
  # @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
  def subdivide_face_to_a(p1, p2, p3, nbtimes)
    pts_to_process = [[p1, p2, p3]]

    while nbtimes > 0
      nbtimes -= 1
      next_pts = []
      while (pts = pts_to_process.shift)
        p1, p2, p3 = pts
        e1 = p1.vector_to(p2)
        e2 = p2.vector_to(p3)
        e3 = p3.vector_to(p1)

        mid1 = p1 + e1.to_a.map { |x| x / 2 }
        mid2 = p2 + e2.to_a.map { |x| x / 2 }
        mid3 = p3 + e3.to_a.map { |x| x / 2 }
        next_pts += [[p1, mid1, mid3], [mid3, mid1, mid2], [mid2, mid1, p2], [mid3, mid2, p3]]
      end # end while
      pts_to_process = next_pts
    end # end while

    pts_to_process
  end
end

file_loaded(__FILE__)
