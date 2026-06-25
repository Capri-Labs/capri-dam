module Reports
  module Generators
    class Base
      attr_reader :data, :snapshot

      def initialize(data, snapshot)
        @data = data
        @snapshot = snapshot
      end

      # Must return an array: [IO_Object, String (filename), String (MIME type)]
      def generate
        raise NotImplementedError, "#{self.class.name} must implement #generate"
      end

      protected

      def default_filename(extension)
        safe_name = snapshot.report_definition.name.parameterize
        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        "#{safe_name}_#{timestamp}.#{extension}"
      end
    end
  end
end
