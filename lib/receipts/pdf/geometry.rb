module Receipts
  module PDF
    module Geometry
      module_function

      # [top, right, bottom, left] from a number, [vertical, horizontal], [top, horizontal, bottom] or [top, right, bottom, left]
      def expand_box(value)
        values = Array(value)
        case values.size
        when 1 then values * 4
        when 2 then [values[0], values[1], values[0], values[1]]
        when 3 then [values[0], values[1], values[2], values[1]]
        else values.first(4)
        end
      end

      # Offset that aligns content of the used width within the available width.
      # Position is :left, :center, :right or an offset.
      def align_offset(position, available, used)
        case position
        when :center then (available - used) / 2.0
        when :right then available - used
        when Numeric then position
        else 0
        end
      end
    end
  end
end
