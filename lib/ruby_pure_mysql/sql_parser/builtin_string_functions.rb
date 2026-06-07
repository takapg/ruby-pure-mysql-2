# frozen_string_literal: true

require_relative 'builtin_string_utils'

module RubyPureMysql
  # 文字列操作に関する組み込み関数の評価ロジックを提供するモジュール
  module BuiltinStringFunctions
    include BuiltinStringUtils

    def handle_substring_index(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str = args[0].to_s.force_encoding('UTF-8')
      delim = args[1].to_s.force_encoding('UTF-8')
      count = args[2].to_i

      return '' if count.zero? || delim.empty?

      calculate_substring_index(str, delim, count)
    end

    def handle_replace(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str = args[0].to_s.force_encoding('UTF-8')
      from = args[1].to_s.force_encoding('UTF-8')
      to = args[2].to_s.force_encoding('UTF-8')
      return str if from.empty?

      str_down = str.downcase
      from_down = from.downcase
      result = String.new
      last_pos = 0

      while (idx = str_down.index(from_down, last_pos))
        result << str[last_pos...idx]
        result << to
        last_pos = idx + from.length
      end
      result << str[last_pos..-1]
      result
    end

    def handle_concat_ws(args)
      return :error if args.size < 2

      separator = args[0]
      return nil if separator.nil?

      args[1..].compact.join(separator.to_s)
    end

    def handle_locate(args)
      return :error unless [2, 3].include?(args.size)
      return nil if args.any?(&:nil?)

      substr = args[0].to_s.force_encoding('UTF-8')
      str = args[1].to_s.force_encoding('UTF-8')
      pos = args[2] ? args[2].to_i : 1

      calculate_locate_index(str, substr, pos)
    end

    def handle_instr(args)
      return :error unless args.size == 2
      return nil if args.any?(&:nil?)

      str = args[0].to_s.force_encoding('UTF-8')
      substr = args[1].to_s.force_encoding('UTF-8')

      calculate_locate_index(str, substr, 1)
    end

    def handle_left(args)
      prepared = prepare_string_args(args)
      return prepared if prepared == :error || prepared.nil?

      str, len = prepared
      return '' if len <= 0

      str[0, len]
    end

    def handle_right(args)
      prepared = prepare_string_args(args)
      return prepared if prepared == :error || prepared.nil?

      str, len = prepared
      return '' if len <= 0

      str[-len..] || str
    end

    def handle_lpad(args)
      execute_padding(args, :left)
    end

    def handle_rpad(args)
      execute_padding(args, :right)
    end

    def handle_trim(args)
      execute_trim_operation(args, :strip)
    end

    def handle_ltrim(args)
      execute_trim_operation(args, :lstrip)
    end

    def handle_rtrim(args)
      execute_trim_operation(args, :rstrip)
    end

    def handle_reverse(args)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_s.force_encoding('UTF-8').reverse
    end
  end
end
