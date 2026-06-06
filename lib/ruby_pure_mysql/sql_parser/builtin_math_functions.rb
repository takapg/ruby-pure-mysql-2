# frozen_string_literal: true

module RubyPureMysql
  # 算術組み込み関数の評価ロジックを提供するモジュール
  module BuiltinMathFunctions
    def handle_math_builtin(name, args)
      case name
      when 'round' then handle_round(args)
      when 'greatest' then handle_greatest(args)
      when 'least' then handle_least(args)
      when 'abs' then handle_abs(args)
      when 'floor' then handle_floor(args)
      when 'ceil', 'ceiling' then handle_ceil(args)
      else :error
      end
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
  end
end
