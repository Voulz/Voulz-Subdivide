require "sketchup.rb"

module Voulz
  module Utils
    EPSILON ||= 0.00000001
    M_EPSILON ||= -EPSILON

    module_function

    # ---------- FLOAT UTILS ----------
    # Check if a is almost equal to b
    def ==(a, b)
      (a - b).abs < EPSILON
    end

    # Check if a > b with tolerance
    def >(a, b)
      a - b >= EPSILON
    end

    # Check if a < b with tolerance
    def <(a, b)
      b - a >= EPSILON
    end

    # Check if a >= b with tolerance
    def >=(a, b)
      a - b >= M_EPSILON
    end

    # Check if a <= b with tolerance
    def <=(a, b)
      b - a >= M_EPSILON
    end

    # Check a <=> b with tolerance
    def <=>(a, b)
      sub = a - b
      sub <= M_EPSILON ?
        -1 : sub >= EPSILON ? 1 : 0
    end

    # ---------- OTHER UTILS ----------

    def dump_var(v, _puts = true, monoline = false, _indent = 2)
      str = ""
      sep = monoline ? " " : "\n"
      indent = monoline ? " " : " " * _indent
      pre_indent = monoline || _indent < 3 ? "" : " " * (_indent - 2)

      if v.is_a?(Array)
        types = {}
        v.each { |val|
          s = val.is_a?(Hash) ? "#{val.keys}" : val.class
          if types.has_key?(s)
            types[s] += 1
          else
            types[s] = 1
          end
        }
        str = "Array <#{sep}#{types.map { |k, val| "#{indent}#{k}[#{val}]" }[0..5].join(sep)}#{sep}#{pre_indent}> [#{v.length}]"
      elsif v.is_a?(Hash)
        vals = v.map { |var, val|
          klass = val.class
          if val.is_a?(Array)
            val = dump_var(val, false, true)
          elsif val.is_a?(String)
            val = "`#{val}`"
          end

          "#{indent}#{var} :  #{val}  <#{klass}>"
        }
        str = "#{v.class} {#{sep}" + (vals[0..9] + (vals.length > 10 ? ["#{indent}..."] : [])).join((monoline ? "," : "") + sep) + "#{sep}#{pre_indent}}"
      elsif v.respond_to?(:class) && v.respond_to?(:instance_variables)
        str = "#{v.class} {#{sep}" + (v.instance_variables.map { |var|
          val = v.instance_variable_get(var)
          klass = val.class
          if val.is_a?(Array)
            val = dump_var(val, false, true)
          elsif val.is_a?(Hash)
            val = dump_var(val, false, false, _indent + 2)
          elsif val.is_a?(String)
            val = "`#{val}`"
          end
          "#{indent}#{var} :  #{val}  <#{klass}>"
        } + get_methods(v).map { |m|
          "#{indent}:#{m}  [#{v.method(m).parameters.map { |req, name|
            req == :req ? ":#{name}" : "<:#{name}>"
          }.join(", ")}]"
        }).join(sep) + "#{sep}#{pre_indent}}"
      else
        str = v
      end
      if _puts
        puts "#{str}"
        str = nil
      end
      str
    end

    def get_methods(obj, remove_object_methods = true, try_remove_properties = true)
      arr = obj.methods
      arr -= Object.methods if remove_object_methods
      if try_remove_properties && obj.respond_to?(:instance_variables)
        props = []
        obj.instance_variables.each { |var|
          props << var.to_s[1..-1].to_sym
          props << (var.to_s[1..-1] + "=").to_sym
          props << (var.to_s[1..-1] + "?").to_sym
        }
        arr -= props
      end
      arr
    end
  end #module Utils
end #module Voulz
