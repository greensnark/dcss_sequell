require 'query/ast/term'

module Query
  module AST
    class Option < Term
      attr_reader :name, :option_arguments

      def initialize(name, arguments)
        @name = name
        @option_arguments = arguments || []
      end

      def meta?
        true
      end

      def kind
        :option
      end

      def has_args?
        !option_arguments.empty?
      end

      def merge(other)
        return self unless other
        opt = self.dup
        other.arguments.each { |arg|
          opt.option_arguments << arg
        }
        opt
      end

      def to_s
        (["-#{name}"] + option_arguments).select { |x| !x.empty? }.join(':')
      end
    end
  end
end
