# frozen_string_literal: true

module RubyPureMysql
  # 算術組み込み関数の評価ロジックを提供するモジュール
  module BuiltinMathFunctions
    MATH_FUNCTIONS = {
      'round' => :handle_round,
      'greatest' => :handle_greatest,
      'least' => :handle_least,
      'abs' => :handle_abs,
      'floor' => :handle_floor,
      'ceil' => :handle_ceil,
      'ceiling' => :handle_ceil,
      'truncate' => :handle_truncate
    }.freeze

    def handle_math_builtin(name, args)
      handler = MATH_FUNCTIONS[name]
      handler ? public_send(handler, args) : :error
    end

    def handle_round(args)
      return :error unless [1, 2].include?(args.size)

      return nil if args.any?(&:nil?)

      val = args[0].to_f
      precision = args[1] ? args[1].to_i : 0
      val.round(precision)
    end

    def handle_greatest(args)
      return :error if args.size < 2

      return nil if args.any?(&:nil?)

      # rubocop:disable Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
      args.all? { |arg| arg.is_a?(Numeric) } ? args.max : args.map(&:to_s).max
      # rubocop:enable Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
    end

    def handle_least(args)
      return :error if args.size < 2

      return nil if args.any?(&:nil?)

      # rubocop:disable Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
      args.all? { |arg| arg.is_a?(Numeric) } ? args.min : args.map(&:to_s).min
      # rubocop:enable Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
    end

    def handle_abs(args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      num = val.is_a?(Numeric) ? val : val.to_f
      num.abs
    end

    def handle_floor(args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_f.floor
    end

    def handle_ceil(args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_f.ceil
    end

    def handle_truncate(args)
      return :error unless args.size == 2
      return nil if args.any?(&:nil?)

      val = args[0].to_f
      d = args[1].to_i
      multiplier = 10.0**d
      (val * multiplier).to_i / multiplier
    end
  end
end
