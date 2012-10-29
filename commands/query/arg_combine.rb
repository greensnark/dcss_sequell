module Query
  class ArgCombine
    # Second combination: Go through the arg list and check for
    # space-split args that should be combined (such as ['killer=steam',
    # 'dragon'], which should become ['killer=steam dragon']).
    def self.apply(args)
      self.new(args).combine
    end

    def initialize(args)
      @args = args.map { |a| a.dup }
      @original_args = args
    end

    def combine
      cargs = []
      can_combine = false
      for arg in @args do
        if (!can_combine ||
            cargs.empty? ||
            arg =~ ARGSPLITTER ||
            arg_is_grouper?(arg) ||
            arg_is_grouper?(cargs.last) ||
            args_uncombinable?(cargs.last, arg))
          cargs << arg
          can_combine = true if !can_combine && arg_enables_combine?(arg)
        else
          cargs.last << " " << arg
        end
      end
      cargs
    end

    def arg_enables_combine?(arg)
      arg =~ ARGSPLITTER
    end

    def arg_is_grouper?(arg)
      [OPEN_PAREN, CLOSE_PAREN, BOOLEAN_OR].index(arg)
    end

    def args_uncombinable?(a, b)
      a =~ /^@/ || b =~ /^@/
    end
  end
end
