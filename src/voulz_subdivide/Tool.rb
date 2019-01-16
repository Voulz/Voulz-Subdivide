module Voulz::Plugins::VoulzSubdivide
  class Tool

    # --------------------------------------------------------
    #                       VARIABLES
    # --------------------------------------------------------

    @@default = {input: -1, inputTxt: "-1"}
    @@last ||= @@default.clone

    @entities = []
    @result = []
    @stats = nil

    def activate
      @entities = Sketchup.active_model.selection.to_a

      unless @entities.length == 0
        @stats = get_stats(@entities)
        #if the previous input value doesn't feel safe, use the default instead
        @@last = @@default.clone unless safe_input_scale(@@last[:input])
        process_last_input
      end
      set_status_text
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      @entities.clear unless @entities.nil?
      @result.clear unless @result.nil?
      @stats = nil
      view.invalidate
    end

    def onUserText(text, view)
      #TODO: find a way to tell the user that the value he/she is entering might be too small
      length = Sketchup.parse_length(text)
      #make sure negative values stays the given integers. if units are mm, Sketchup.parse_length("-1") will give `-0.03937007874015748`
      if length && length < 0
        length = text.to_i
        text = length.to_s
      end
      unless length.nil?
        unless safe_input_scale(length)
          #if the input feels like it will create too many subdivisions, tell the user
          if UI.messagebox("The value `#{text}` you entered will create a big number of triangles, do you want to continue?", MB_YESNO) == IDNO
            Sketchup.vcb_value = @@last[:inputTxt]
            return
          end
        end
        prev = @@last[:input]
        @@last[:input] = length
        if process_last_input #if worked
          @@last[:inputTxt] = text
        else
          @@last[:input] = prev
        end
        view.invalidate
      end
      Sketchup.vcb_value = @@last[:inputTxt]
    end

    def resume(view)
      view.invalidate
      set_status_text
    end

    def draw(view)
      # Have to put that here in the case of face-me components
      # process_input unless @entities.length == 0
      set_status_text

      if @result.nil? || @result.length == 0
        view.drawing_color = Sketchup::Color.new(0, 0, 0, 128)
        view.draw2d(GL_QUADS, [[0, 0, 0], [view.vpwidth, 0, 0], [view.vpwidth, view.vpheight, 0], [0, view.vpheight, 0]])
        options = {
          font: "Arial",
          size: 20,
          align: TextAlignCenter,
          color: "white",
        }
        view.draw_text([view.vpwidth / 2.0, view.vpheight / 2.0, 0], "Please select faces and groups to subdvide prior to use the tool.", options)
      else
        view.line_width = 3
        view.drawing_color = "red"
        #   view.draw(GL_TRIANGLES, trs.flatten) unless trs.nil? || trs.empty?
        @result.each { |triangle|
          #  face.each { |triangle|
          view.draw(GL_LINE_LOOP, triangle)
          #  }
        }
      end
    end

    # --------------------------------------------------------
    #                       MENU ITEMS
    # --------------------------------------------------------

    private

    # Check if the given input seems fine or feels like it will produce too many triangles
    # @param [ Float ] input Input value. If <0, subdivide the number of times given, =0, just triangulate, >0 subdivide by given length
    # @return [ Boolean ] Returns false if the input feels like it will produce too many triangles
    def safe_input_scale(input)
      return false if @entities.length == 0
      input = input.to_f
      return false if input.nil?
      input = input.to_i if input <= 0

      if input > 0
        # triangulate + subdivide based on max length
        avg = (@stats[:average] / input).to_i # average number of division of edge, really simple computation not close to reality
        nb_faces = avg * @stats[:nb]
        return nb_faces < 1000
      elsif input < 0
        nb_faces = @stats[:nb] ** 4 #4 triangles per triangle
        for i in 1..input.abs
          nb_faces += nb_faces ** 4
        end
        return nb_faces < 1000 #should be fine if only 3 or less subdivisions
        #   return input > -4 #should be fine if only 3 or less subdivisions
      else
        return true
      end
    end

    # Set the status text
    def set_status_text
      if @result.nil? || @result.length == 0
        Sketchup.status_text = "Please select faces and groups to subdvide prior to use the tool."
      else
        Sketchup.status_text = "Enter a positive number for a maximum edge length (ex: 12.5) or a negative number for a number of subdivision iteration (ex: -2)"
      end
      Sketchup.vcb_label = "Subdivisions:"
      Sketchup.vcb_value = @@last[:inputTxt]
    end

    # Process the last input given (from the @@last variable)
    def process_last_input
      return false if @entities.length == 0
      input = @@last[:input].to_f
      return false if input.nil?
      input = input.to_i if input <= 0

      Sketchup.status_text = "Processing"
      if input > 0
        # triangulate + subdivide based on max length
        @result = Voulz::Plugins::VoulzSubdivide.subdivide_length_to_a(@entities, input)
      elsif input < 0
        # triangulate + subdivide based on the number of times we want it subdivided
        @result = Voulz::Plugins::VoulzSubdivide.subdivide_to_a(@entities, input.abs)
      else
        # do not subdivide but still triangulate
        @result = Voulz::Plugins::VoulzSubdivide.triangulate_to_a(@entities)
      end
      @result.flatten!(1)
      set_status_text
    end

    # Gets the stats of the selected Entities
    def get_stats(entities, tr = nil)
      tr ||= Geom::Transformation.new
      stats = {nb: 0, sum: 0, maxlength: 0}
      entities.each { |ent|
        next if !ent.valid? || ent.hidden? || !ent.layer.visible?
        if ent.is_a?(Sketchup::Face)
          mesh = ent.mesh
          for i in 1..mesh.count_polygons
            pts = mesh.polygon_points_at(i)
            next unless pts.length == 3 #TODO: Check if there is the need to handle more polygons
            pts.map! { |p| p.transform(tr) }
            stats[:nb] += 1
            length = pts[0].vector_to(pts[1]).length + pts[1].vector_to(pts[2]).length + pts[2].vector_to(pts[0]).length
            stats[:sum] += length
            stats[:maxlength] = length if length > stats[:maxlength]
          end
        elsif ent.respond_to?(:transformation) && ent.respond_to?(:definition)
          _stats = get_stats(ent.definition.entities, tr * ent.transformation)
          stats[:nb] += _stats[:nb]
          stats[:sum] += _stats[:sum]
          stats[:maxlength] = _stats[:maxlength] if _stats[:maxlength] > stats[:maxlength]
        end
      }
      stats[:average] = stats[:sum] / stats[:nb]
      stats
    end
  end # class Tool
end # module Voulz::Plugins::VoulzSubdivide
