
require "sketchup.rb"
require "extensions.rb"

module Voulz
  module Plugins
    module VoulzSubdivide
      DEBUG ||= false
      PLUGIN_NAME ||= "Voulz Subdivide".freeze
      PLUGIN_VERSION ||= "0.1.0a".freeze

      # Resource paths
      file = __FILE__.dup
      file.force_encoding("UTF-8") if file.respond_to?(:force_encoding)
      FILENAMESPACE = File.basename(file, ".*")
      PATH_ROOT = File.dirname(file).freeze
      PATH = File.join(PATH_ROOT, FILENAMESPACE).freeze

      unless file_loaded?(__FILE__)
        @ex = SketchupExtension.new(PLUGIN_NAME, File.join(PATH, "main"))
        @ex.description = "Sketchup Plugin to triangulate and subdivide faces. Can be used to subdivide until reaching a maximum edge length or to subdivide a certain number of times."
        @ex.version = PLUGIN_VERSION
        @ex.copyright = "Voulz © 2019"
        @ex.creator = "Voulz"
        Sketchup.register_extension(@ex, true)
      end

		  # --------------------------------------------------------
  #                   MODULE FUNCTIONS
  # --------------------------------------------------------

      module_function

		# Reload ann the files within the folder. Call with : 
		# Voulz::Plugins::VoulzSubdivide.reload
      def reload
        original_verbose = $VERBOSE
        $VERBOSE = nil
        Dir.glob(File.join(__dir__, "voulz_subdivide", "**/*.rb")).each { |file|
          load(file)
          #   puts "reload #{file} : #{load(file)}"
        }.size
      ensure
        $VERBOSE = original_verbose
      end
    end # module VoulzExporter
  end # module Plugins
end # module Voulz

file_loaded(__FILE__)
