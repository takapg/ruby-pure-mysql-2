# frozen_string_literal: true

require_relative 'builtin_string_functions'
require_relative 'builtin_math_functions'

module RubyPureMysql
  # 組み込み関数の評価ロジックを提供するモジュール
  module BuiltinFunctions
    include BuiltinStringFunctions
    include BuiltinMathFunctions

    def handle_complex_builtin(name, args)
      case name
      when 'coalesce', 'ifnull', 'if', 'nullif', 'isnull' then handle_basic_builtin(name, args)
      when 'substring', 'substr' then handle_substring(args)
      when 'substring_index' then handle_substring_index(args)
      when 'length', 'char_length', 'character_length' then handle_length_functions(name, args)
      when 'lower', 'lcase', 'upper', 'ucase' then handle_case_conversion(name, args)
      when 'trim', 'ltrim', 'rtrim' then handle_trim_functions(name, args)
      when 'lpad' then handle_lpad(args)
      when 'rpad' then handle_rpad(args)
      else handle_other_builtin(name, args)
      end
    end

    def handle_trim_functions(name, args)
      case name
      when 'trim' then handle_trim(args)
      when 'ltrim' then handle_ltrim(args)
      when 'rtrim' then handle_rtrim(args)
      end
    end

    def handle_other_builtin(name, args)
      case name
      when 'replace' then handle_replace(args)
      when 'concat_ws' then handle_concat_ws(args)
      when 'locate' then handle_locate(args)
      when 'left' then handle_left(args)
      when 'right' then handle_right(args)
      else handle_math_builtin(name, args)
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

      mysql_truthy?(args[0]) ? args[1] : args[2]
    end

    def mysql_truthy?(val)
      return false if val.nil?
      return val if val.is_a?(TrueClass) || val.is_a?(FalseClass)

      numeric_val = val.is_a?(Numeric) ? val : val.to_s.to_f
      numeric_val != 0
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
  end
end
