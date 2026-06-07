# frozen_string_literal: true

require_relative 'builtin_string_functions'
require_relative 'builtin_math_functions'
require_relative 'builtin_basic_functions'

module RubyPureMysql
  # 組み込み関数の評価ロジックを提供するモジュール
  module BuiltinFunctions
    include BuiltinStringFunctions
    include BuiltinMathFunctions
    include BuiltinBasicFunctions

    STRING_BUILTIN_HANDLERS = {
      'replace' => :handle_replace,
      'concat_ws' => :handle_concat_ws,
      'locate' => :handle_locate,
      'left' => :handle_left,
      'right' => :handle_right,
      'lpad' => :handle_lpad,
      'rpad' => :handle_rpad,
      'reverse' => :handle_reverse
    }.freeze

    def handle_complex_builtin(name, args)
      case name
      when 'coalesce', 'ifnull', 'if', 'nullif', 'isnull' then handle_basic_builtin(name, args)
      when 'substring', 'substr' then handle_substring(args)
      when 'substring_index' then handle_substring_index(args)
      when 'length', 'char_length', 'character_length' then handle_length_functions(name, args)
      when 'lower', 'lcase', 'upper', 'ucase' then handle_case_conversion(name, args)
      when 'trim', 'ltrim', 'rtrim' then handle_trim_functions(name, args)
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
      when 'replace', 'concat_ws', 'locate', 'left', 'right', 'lpad', 'rpad', 'reverse'
        handle_string_builtin(name, args)
      else
        handle_math_builtin(name, args)
      end
    end

    def handle_string_builtin(name, args)
      handler = STRING_BUILTIN_HANDLERS[name]
      public_send(handler, args) if handler
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
