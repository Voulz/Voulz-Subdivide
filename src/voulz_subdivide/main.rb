require_relative "utils/Utils"
require_relative "Tool"

module Voulz::Plugins
  # Get the Menu item in the Plugin Extension, or create it if necessary
  module_function def GetMenu
    @menu ||= UI.menu("Plugins").add_submenu("Voulz")
  end
end

# TODO: Have to test with:
# - faces with textures ✔
# - Problem with textures distorted in perspective
# - faces with hidden edges ✔
# - faces with smooth edges ✔
# - faces with soft edges ✔
# - groups (make sure it only affects the ones visible) ✔
# - component (make sure it only affects the ones visible) ✔
# - try a complicated mix of same group inside and outside of other groups ✔
# - try running the tool while editing a group with different origin ✔
# - check locked entities ✔
# - check if the geometry is clean ✔
# - add the new elements to the selection
# - ask if the new triangles should be hidden, and check how to do that
# - check what to do when the faces are inside groups/components that are scaled
module Voulz::Plugins::VoulzSubdivide
  # --------------------------------------------------------
  #                       MENU ITEMS
  # --------------------------------------------------------
  unless file_loaded?(__FILE__)
    menu = Voulz::Plugins.GetMenu

    cmd = UI::Command.new("Subdivide Faces") {
      puts "\n -- #{self.class} reloaded #{reload} files\n\n" if DEBUG
      Sketchup.active_model.select_tool(Tool.new)
    }
    cmd.status_bar_text = "Subdivide the selected faces."
    cmd.tooltip = cmd.status_bar_text
    # TODO: Check if better to grey out or to indicate when the tool start
    #cmd.set_validation_proc { Sketchup.active_model.selection.length == 0 ? MF_GRAYED :  MF_ENABLED }
    menu.add_item(cmd)

    item = menu.add_item("Subdivide Reload") {
      puts "\n -- #{self.class} reloaded #{reload} files\n\n"
    } if DEBUG
  end

  module_function

  # --------------------------------------------------------
  #                NON DESTRUCTIVE SUBDIVISION
  # --------------------------------------------------------

  # Triangulate the given entities.
  # This version will output an Array of Faces, each Face being an array of Triangles, each Triangle being an array of Point3d
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Geom::Transformation | nil ] tr The transformation of the current entities
  # @return [ Array<Array<Array<Point3d>>> ] Triangles
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
        next if ent.locked?
        triangles += triangulate_to_a(ent.definition.entities, tr * ent.transformation)
      end
    }
    triangles
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
        next if ent.locked?
        triangles += subdivide_to_a(ent.definition.entities, nbtimes, tr * ent.transformation)
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
        next if ent.locked?
        triangles += subdivide_length_to_a(ent.definition.entities, max_length, tr * ent.transformation)
      end
    }
    triangles
  end

  # Subdivide the face a given number of times, independantly of their size
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

  # --------------------------------------------------------
  #                  DESTRUCTIVE SUBDIVISION
  # --------------------------------------------------------

  # Triangulate the given entities.
  # WRAP IN AN OPERATION !
  # This version will directly triangulate the given entities
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  def triangulate!(entities)
    triangulate_base!(entities) #{ |face|
    #    face.mesh(7) #get the points + UV Front + UV Back + Normals
    #  }
  end

  # Triangulate and then subdivide entities the given number of times, independantly of their size
  # WRAP IN AN OPERATION !
  # This version will directly triangulate the given entities
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
  def subdivide_face!(entities, nbtimes)
    triangulate_base!(entities) { |mesh| # |face| #Replace the face by the mesh of the face
      # mesh = face.mesh(7) #get the points + UV Front + UV Back + Normals
      new_mesh = Geom::PolygonMesh.new
      mesh.points.each_with_index { |pt, _i|
        i = new_mesh.add_point(pt)
        uv = mesh.uv_at(_i, true)
        new_mesh.set_uv(i, uv, true) unless uv.nil?
        uv = mesh.uv_at(_i, false)
        new_mesh.set_uv(i, uv, false) unless uv.nil?
      }

      for i in 1..mesh.count_polygons
        #   pts = mesh.polygon_points_at(i)
        indices = mesh.polygon_at(i)
        next unless indices.length == 3 #TODO: Check if there is the need to handle more polygons
        i1, i2, i3 = indices
        p1 = mesh.point_at(i1)
        p2 = mesh.point_at(i2)
        p3 = mesh.point_at(i3)
        u1 = mesh.uv_at(i1, true)
        u2 = mesh.uv_at(i2, true)
        u3 = mesh.uv_at(i3, true)
        _u1 = mesh.uv_at(i1, false)
        _u2 = mesh.uv_at(i2, false)
        _u3 = mesh.uv_at(i3, false)
        subdivide_mesh_face(new_mesh, p1, p2, p3, u1, u2, u3, _u1, _u2, _u3, nbtimes)
      end
      new_mesh
    }
  end

  # Triangulate and then subdivide entities until each edge of each triangle has a maximum length of max_length.
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
  def subdivide_length_face!(entities, max_length)
    triangulate_base!(entities) { |mesh| # |face| #Replace the face by the mesh of the face
      # mesh = face.mesh(7) #get the points + UV Front + UV Back + Normals
      new_mesh = Geom::PolygonMesh.new
      mesh.points.each_with_index { |pt, _i|
        i = new_mesh.add_point(pt)
        uv = mesh.uv_at(_i, true)
        new_mesh.set_uv(i, uv, true) unless uv.nil?
        uv = mesh.uv_at(_i, false)
        new_mesh.set_uv(i, uv, false) unless uv.nil?
      }

      for i in 1..mesh.count_polygons
        indices = mesh.polygon_at(i)
        next unless indices.length == 3 #TODO: Check if there is the need to handle more polygons
        i1, i2, i3 = indices
        p1 = mesh.point_at(i1)
        p2 = mesh.point_at(i2)
        p3 = mesh.point_at(i3)
        u1 = mesh.uv_at(i1, true)
        u2 = mesh.uv_at(i2, true)
        u3 = mesh.uv_at(i3, true)
        _u1 = mesh.uv_at(i1, false)
        _u2 = mesh.uv_at(i2, false)
        _u3 = mesh.uv_at(i3, false)
        subdivide_length_mesh_face(new_mesh, p1, p2, p3, u1, u2, u3, _u1, _u2, _u3, max_length)
      end
      new_mesh
    }
  end

  # Base of the triangulation process. Will go through the given entities and handle properly the groups and components.
  # Pass a block with one argument, the face to process
  # WRAP IN AN OPERATION !
  # This version will directly triangulate the given entities
  # @param [ Sketchup::Entities | Array<Sketchup::Entity> ] entities Entities to be triangulated and subdivided
  # @param [ Hash | nil ] components The components hash keeping track of the ones made unique. Pass nil.
  # @param [ Proc ] block Pass a block that outputs a Geom::PolygonMesh from a Sketchup::Face
  private def triangulate_base!(entities, components = nil, &block)
    components ||= {}

    faces = []; added_groups = []
    entities.each { |ent|
      next if !ent.valid? || ent.hidden? || !ent.layer.visible?
      if ent.is_a?(Sketchup::Face)
        faces << [ent, ent.mesh(7)] # get the mesh here because it would change afterwards when the surrounding faes would be processed first
      elsif ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
        next if ent.locked? || added_groups.include?(ent)
        _def = ent.definition
        if components.include?(_def)
          if ent.respond_to?(:definition=) #comp
            ent.definition = components[_def]
          else # groups dont have :definition=
            t = ent.transformation
            ents = ent.parent.entities

            g = ents.add_instance(components[_def], t)
            g.material = ent.material
            ent.erase!
            added_groups << g # store the ones we added to not process it
            Sketchup.active_model.selection.add(g)
          end
        else
          ent.make_unique
          components[_def] = ent.definition
          triangulate_base!(ent.definition.entities, components, &block)
        end
      end
    }

    faces.each { |face, _mesh|
      next unless face.valid?
      parent = face.parent

      front_mat = face.material
      back_mat = face.back_material

      # we do not get the mesh of the face here because one of the surrounding face might have been processed first and this would change the mesh
      mesh = block ? block.call(_mesh) : _mesh

      face.erase!
      parent.entities.add_faces_from_mesh(mesh, Geom::PolygonMesh::NO_SMOOTH_OR_HIDE, front_mat, back_mat)
    }
  end

  # Subdivide the face a given number of times, independantly of their size
  # @param [ Sketchup::Point3d ] p1
  # @param [ Sketchup::Point3d ] p2
  # @param [ Sketchup::Point3d ] p3
  # @param [ Sketchup::Point3d ] uv1 Front UV of p1
  # @param [ Sketchup::Point3d ] uv2 Front UV of p2
  # @param [ Sketchup::Point3d ] uv3 Front UV of p3
  # @param [ Sketchup::Point3d ] uv1 Back UV of p1
  # @param [ Sketchup::Point3d ] uv2 Back UV of p2
  # @param [ Sketchup::Point3d ] uv3 Back UV of p3
  # @param [ Fiznum ] nbtimes The number of times the entities will need to be subdivided
  def subdivide_mesh_face(mesh, p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3, nbtimes)
    pts_to_process = [[p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3]]

    while nbtimes > 0
      nbtimes -= 1
      next_pts = []
      while (pts = pts_to_process.shift)
        p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3 = pts

        mid1 = Voulz::Utils.mid_point(p1, p2) # p1 + e1.to_a.map { |x| x / 2 }
        um1 = uv1 && uv2 ? Voulz::Utils.mid_point(uv1, uv2) : nil
        _um1 = _uv1 && _uv2 ? Voulz::Utils.mid_point(_uv1, _uv2) : nil
        mid2 = Voulz::Utils.mid_point(p2, p3) # p2 + e2.to_a.map { |x| x / 2 }
        um2 = uv2 && uv3 ? Voulz::Utils.mid_point(uv2, uv3) : nil
        _um2 = _uv2 && _uv3 ? Voulz::Utils.mid_point(_uv2, _uv3) : nil
        mid3 = Voulz::Utils.mid_point(p3, p1) # p3 + e3.to_a.map { |x| x / 2 }
        um3 = uv3 && uv1 ? Voulz::Utils.mid_point(uv3, uv1) : nil
        _um3 = _uv3 && _uv1 ? Voulz::Utils.mid_point(_uv3, _uv1) : nil
        next_pts += [[p1, mid1, mid3, uv1, um1, um3, _uv1, _um1, _um3],
                     [mid3, mid1, mid2, um3, um1, um2, _um3, _um1, _um2],
                     [mid2, mid1, p2, um2, um1, uv2, _um2, _um1, _uv2],
                     [mid3, mid2, p3, um3, um2, uv3, _um3, _um2, _uv3]]
      end # end while
      pts_to_process = next_pts
    end # end while
    pts_to_process.each { |p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3|
      _p1 = mesh.add_point(p1)
      mesh.set_uv(_p1, Geom::Point3d.new(uv1.x / uv1.z, uv1.y / uv1.z, 1), true) unless uv1.nil?
      mesh.set_uv(_p1, Geom::Point3d.new(_uv1.x / _uv1.z, _uv1.y / _uv1.z, 1), false) unless _uv1.nil?
      _p2 = mesh.add_point(p2)
      mesh.set_uv(_p2, Geom::Point3d.new(uv2.x / uv2.z, uv2.y / uv2.z, 1), true) unless uv2.nil?
      mesh.set_uv(_p2, Geom::Point3d.new(_uv2.x / _uv2.z, _uv2.y / _uv2.z, 1), false) unless _uv2.nil?
      _p3 = mesh.add_point(p3)
      mesh.set_uv(_p3, Geom::Point3d.new(uv3.x / uv3.z, uv3.y / uv3.z, 1), true) unless uv3.nil?
      mesh.set_uv(_p3, Geom::Point3d.new(_uv3.x / _uv3.z, _uv3.y / _uv3.z, 1), false) unless _uv3.nil?
      mesh.add_polygon(p1, p2, p3)
    }
    mesh
  end

  # Subdivide a triangle until each edge has a maximum length of max_length.
  # @param [ Sketchup::Point3d ] p1
  # @param [ Sketchup::Point3d ] p2
  # @param [ Sketchup::Point3d ] p3
  # @param [ Sketchup::Point3d ] uv1 Front UV of p1
  # @param [ Sketchup::Point3d ] uv2 Front UV of p2
  # @param [ Sketchup::Point3d ] uv3 Front UV of p3
  # @param [ Sketchup::Point3d ] uv1 Back UV of p1
  # @param [ Sketchup::Point3d ] uv2 Back UV of p2
  # @param [ Sketchup::Point3d ] uv3 Back UV of p3
  # @param [ Float ] max_length Maximum length the edges can have. If they have less, the triangle will be subdivided
  def subdivide_length_mesh_face(mesh, p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3, max_length)
    pts_to_process = [[p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3]]
    done = []
    while (pts = pts_to_process.shift)
      p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3 = pts
      l1 = Voulz::Utils.<=(p1.vector_to(p2).length, max_length)
      l2 = Voulz::Utils.<=(p2.vector_to(p3).length, max_length)
      l3 = Voulz::Utils.<=(p3.vector_to(p1).length, max_length)
      # e1 = p1.vector_to(p2); l1 = Voulz::Utils.<=(e1.length, max_length)
      # e2 = p2.vector_to(p3); l2 = Voulz::Utils.<=(e2.length, max_length)
      # e3 = p3.vector_to(p1); l3 = Voulz::Utils.<=(e3.length, max_length)
      if l1 && l2 && l3
        #all edges smaller
        done << [p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3]
      elsif l1 && l2
        #1 edge bigger
        #   mid = p3 + e3.to_a.map { |x| x / 2 }
        mid3 = Voulz::Utils.mid_point(p3, p1)
        um3 = uv3 && uv1 ? Voulz::Utils.mid_point(uv3, uv1) : nil
        _um3 = _uv3 && _uv1 ? Voulz::Utils.mid_point(_uv3, _uv1) : nil
        pts_to_process += [[p1, p2, mid3, uv1, uv2, um3, _uv1, _uv2, _um3],
                           [mid3, p2, p3, um3, uv2, uv3, _um3, _uv2, _uv3]]
      elsif l2 && l3
        #1 edge bigger
        #   mid = p1 + e1.to_a.map { |x| x / 2 }
        mid1 = Voulz::Utils.mid_point(p1, p2)
        um1 = uv1 && uv2 ? Voulz::Utils.mid_point(uv1, uv2) : nil
        _um1 = _uv1 && _uv2 ? Voulz::Utils.mid_point(_uv1, _uv2) : nil
        pts_to_process += [[p1, mid1, p3, uv1, um1, uv3, _uv1, _um1, _uv3],
                           [mid1, p2, p3, um1, uv2, uv3, _um1, _uv2, _uv3]]
      elsif l1 && l3
        #1 edge bigger
        #   mid = p2 + e2.to_a.map { |x| x / 2 }
        mid2 = Voulz::Utils.mid_point(p2, p3)
        um2 = uv2 && uv3 ? Voulz::Utils.mid_point(uv2, uv3) : nil
        _um2 = _uv2 && _uv3 ? Voulz::Utils.mid_point(_uv2, _uv3) : nil
        pts_to_process += [[p1, p2, mid2, uv1, uv2, um2, _uv1, _uv2, _um2],
                           [p1, mid2, p3, uv1, um2, uv3, _uv1, _um2, _uv3]]
      elsif l1
        #2 edges bigger
        #   mid2 = p2 + e2.to_a.map { |x| x / 2 }
        #   mid3 = p3 + e3.to_a.map { |x| x / 2 }
        mid2 = Voulz::Utils.mid_point(p2, p3)
        um2 = uv2 && uv3 ? Voulz::Utils.mid_point(uv2, uv3) : nil
        _um2 = _uv2 && _uv3 ? Voulz::Utils.mid_point(_uv2, _uv3) : nil

        mid3 = Voulz::Utils.mid_point(p3, p1)
        um3 = uv3 && uv1 ? Voulz::Utils.mid_point(uv3, uv1) : nil
        _um3 = _uv3 && _uv1 ? Voulz::Utils.mid_point(_uv3, _uv1) : nil

        if p1.vector_to(mid2).length > p2.vector_to(mid3).length
          pts_to_process += [[p1, p2, mid3, uv1, uv2, um3, _uv1, _uv2, _um3],
                             [p2, mid2, mid3, uv2, um2, um3, _uv2, _um2, _um3],
                             [mid3, mid2, p3, um3, um2, uv3, _um3, _um2, _uv3]]
        else
          pts_to_process += [[p1, p2, mid2, uv1, uv2, um2, _uv1, _uv2, _um2],
                             [p1, mid2, mid3, uv1, um2, um3, _uv1, _um2, _um3],
                             [mid3, mid2, p3, um3, um2, uv3, _um3, _um2, _uv3]]
        end
      elsif l2
        #2 edges bigger
        #   mid1 = p1 + e1.to_a.map { |x| x / 2 }
        #   mid3 = p3 + e3.to_a.map { |x| x / 2 }
        mid1 = Voulz::Utils.mid_point(p1, p2)
        um1 = uv1 && uv2 ? Voulz::Utils.mid_point(uv1, uv2) : nil
        _um1 = _uv1 && _uv2 ? Voulz::Utils.mid_point(_uv1, _uv2) : nil

        mid3 = Voulz::Utils.mid_point(p3, p1)
        um3 = uv3 && uv1 ? Voulz::Utils.mid_point(uv3, uv1) : nil
        _um3 = _uv3 && _uv1 ? Voulz::Utils.mid_point(_uv3, _uv1) : nil

        if p2.vector_to(mid3).length > p3.vector_to(mid1).length # if a diagonal is longer than the other, create the short one
          pts_to_process += [[p1, mid1, mid3, uv1, um1, um3, _uv1, _um1, _um3],
                             [mid1, p3, mid3, um1, uv3, um3, _um1, _uv3, _um3],
                             [mid1, p2, p3, um1, uv2, uv3, _um1, _uv2, _uv3]]
        else
          pts_to_process += [[p1, mid1, mid3, uv1, um1, um3, _uv1, _um1, _um3],
                             [mid1, p2, mid3, um1, uv2, um3, _um1, _uv2, _um3],
                             [mid3, p2, p3, um3, uv2, uv3, _um3, _uv2, _uv3]]
        end
      elsif l3
        #2 edges bigger
        #   mid1 = p1 + e1.to_a.map { |x| x / 2 }
        #   mid2 = p2 + e2.to_a.map { |x| x / 2 }
        mid1 = Voulz::Utils.mid_point(p1, p2)
        um1 = uv1 && uv2 ? Voulz::Utils.mid_point(uv1, uv2) : nil
        _um1 = _uv1 && _uv2 ? Voulz::Utils.mid_point(_uv1, _uv2) : nil

        mid2 = Voulz::Utils.mid_point(p2, p3)
        um2 = uv2 && uv3 ? Voulz::Utils.mid_point(uv2, uv3) : nil
        _um2 = _uv2 && _uv3 ? Voulz::Utils.mid_point(_uv2, _uv3) : nil

        if p3.vector_to(mid1).length > p1.vector_to(mid2).length # if a diagonal is longer than the other, create the short one
          pts_to_process += [[mid2, mid1, p2, um2, um1, uv2, _um2, _um1, _uv2],
                             [p1, mid1, mid2, uv1, um1, um2, _uv1, _um1, _um2],
                             [p1, mid2, p3, uv1, um2, uv3, _uv1, _um2, _uv3]]
        else
          pts_to_process += [[mid2, mid1, p2, um2, um1, uv2, _um2, _um1, _uv2],
                             [p1, mid1, p3, uv1, um1, uv3, _uv1, _um1, _uv3],
                             [p3, mid1, mid2, uv3, um1, um2, _uv3, _um1, _um2]]
        end
      else
        # all bigger
        #   mid1 = p1 + e1.to_a.map { |x| x / 2 }
        #   mid2 = p2 + e2.to_a.map { |x| x / 2 }
        #   mid3 = p3 + e3.to_a.map { |x| x / 2 }
        mid1 = Voulz::Utils.mid_point(p1, p2)
        um1 = uv1 && uv2 ? Voulz::Utils.mid_point(uv1, uv2) : nil
        _um1 = _uv1 && _uv2 ? Voulz::Utils.mid_point(_uv1, _uv2) : nil

        mid2 = Voulz::Utils.mid_point(p2, p3)
        um2 = uv2 && uv3 ? Voulz::Utils.mid_point(uv2, uv3) : nil
        _um2 = _uv2 && _uv3 ? Voulz::Utils.mid_point(_uv2, _uv3) : nil

        mid3 = Voulz::Utils.mid_point(p3, p1)
        um3 = uv3 && uv1 ? Voulz::Utils.mid_point(uv3, uv1) : nil
        _um3 = _uv3 && _uv1 ? Voulz::Utils.mid_point(_uv3, _uv1) : nil

        pts_to_process += [[p1, mid1, mid3, uv1, um1, um3, _uv1, _um1, _um3],
                           [mid3, mid1, mid2, um3, um1, um2, _um3, _um1, _um2],
                           [mid2, mid1, p2, um2, um1, uv2, _um2, _um1, _uv2],
                           [mid3, mid2, p3, um3, um2, uv3, _um3, _um2, _uv3]]
      end # end if
    end # end while

    done.each { |p1, p2, p3, uv1, uv2, uv3, _uv1, _uv2, _uv3|
      _p1 = mesh.add_point(p1)
      mesh.set_uv(_p1, Geom::Point3d.new(uv1.x / uv1.z, uv1.y / uv1.z, 1), true) unless uv1.nil?
      mesh.set_uv(_p1, Geom::Point3d.new(_uv1.x / _uv1.z, _uv1.y / _uv1.z, 1), false) unless _uv1.nil?
      _p2 = mesh.add_point(p2)
      mesh.set_uv(_p2, Geom::Point3d.new(uv2.x / uv2.z, uv2.y / uv2.z, 1), true) unless uv2.nil?
      mesh.set_uv(_p2, Geom::Point3d.new(_uv2.x / _uv2.z, _uv2.y / _uv2.z, 1), false) unless _uv2.nil?
      _p3 = mesh.add_point(p3)
      mesh.set_uv(_p3, Geom::Point3d.new(uv3.x / uv3.z, uv3.y / uv3.z, 1), true) unless uv3.nil?
      mesh.set_uv(_p3, Geom::Point3d.new(_uv3.x / _uv3.z, _uv3.y / _uv3.z, 1), false) unless _uv3.nil?
      mesh.add_polygon(p1, p2, p3)
    }
    mesh
  end
end

file_loaded(__FILE__)
