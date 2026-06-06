# frozen_string_literal: true

require_relative 'builtin_string_functions'

module RubyPureMysql
  # 組み込み関数の評価ロジックを提供するモジュール
  module BuiltinFunctions
    include BuiltinStringFunctions
    def handle_complex_builtin(name, args)
      case name
      when 'coalesce', 'ifnull', 'if', 'nullif', 'isnull' then handle_basic_builtin(name, args)
      when 'substring', 'substr' then handle_substring(args)
      when 'length', 'char_length', 'character_length' then handle_length_functions(name, args)
      when 'lower', 'lcase', 'upper', 'ucase' then handle_case_conversion(name, args)
      else handle_other_builtin(name, args)
      end
    end

    def handle_other_builtin(name, args)
      case name
      when 'replace' then handle_replace(args)
      when 'round' then handle_round(args)
      when 'greatest' then handle_greatest(args)
      when 'least' then handle_least(args)
      when 'concat_ws' then handle_concat_ws(args)
      else :error
      end
    end

    def handle_basic_builtin(name, args)
      case name
      when 'coalesce' then handle_coalesce(args)
      when 'ifnull' then handle_ifnull(args)
      when 'if' then handle_if(args)
      when 'nullif' then handle_nullif(args)
      when 'isnull' then handle_isnull(args)
      end
    end

    def handle_coalesce(args)
      return :error if args.empty?

      args.find { |arg| !arg.nil? }
    end

    def handle_ifnull(args)
      return :error unless args.size == 2

      args[0].nil? ? args[1] : args[0]
    end

    def handle_if(args)
      return :error unless args.size == 3

      expr1 = args[0]
      is_true = ![nil, false, 0, '0'].include?(expr1)

      is_true ? args[1] : args[2]
    end

    def handle_nullif(args)
      return :error unless args.size == 2

      args[0] == args[1] ? nil : args[0]
    end

    def handle_isnull(args)
      return :error unless args.size == 1

      args[0].nil? ? 1 : 0
    end

    def handle_substring(args)
      return :error unless [2, 3].include?(args.size)
      return nil if args.any?(&:nil?)

      execute_substring(args[0].to_s, args[1].to_i, args[2]&.to_i)
    end

    def handle_length_functions(name, args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      str = val.to_s
      name == 'length' ? str.bytesize : str.force_encoding('UTF-8').length
    end

    def execute_substring(str, pos, len)
      return '' if pos.zero? || (len && len <= 0)

      start = pos.positive? ? pos - 1 : pos
      (len ? str[start, len] : str[start..]) || ''
    end

    def handle_case_conversion(name, args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      str = val.to_s
      %w[lower lcase].include?(name) ? str.downcase : str.upcase
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

  end
end
