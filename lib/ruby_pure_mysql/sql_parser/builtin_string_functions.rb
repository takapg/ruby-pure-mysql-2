# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作に関する組み込み関数の評価ロジックを提供するモジュール
  module BuiltinStringFunctions
    def handle_substring_index(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str = args[0].to_s
      delim = args[1].to_s
      count = args[2].to_i

      return '' if count.zero? || delim.empty?

      calculate_substring_index(str, delim, count)
    end

    def handle_replace(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str, from, to = args.map(&:to_s)
      return str if from.empty?

      str.gsub(from, to)
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
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str = args[0].to_s.force_encoding('UTF-8')
      len = args[1].to_i
      pad = args[2].to_s.force_encoding('UTF-8')

      return nil if len < 0
      return str[0, len] if str.length >= len
      return nil if pad.empty?

      padding_len = len - str.length
      padding = (pad * padding_len)[0, padding_len]
      "#{padding}#{str}"
    end

    def handle_rpad(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      str = args[0].to_s.force_encoding('UTF-8')
      len = args[1].to_i
      pad = args[2].to_s.force_encoding('UTF-8')

      return nil if len < 0
      return str[0, len] if str.length >= len
      return nil if pad.empty?

      padding_len = len - str.length
      padding = (pad * padding_len)[0, padding_len]
      "#{str}#{padding}"
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

    private

    def calculate_substring_index(str, delim, count)
      parts = str.split(delim, -1)
      count.positive? ? parts.first(count).join(delim) : parts.last(count.abs).join(delim)
    end

    def calculate_locate_index(str, substr, pos)
      return 0 if pos < 1

      idx = str.index(substr, pos - 1)
      idx ? idx + 1 : 0
    end

    def execute_trim_operation(args, method)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_s.public_send(method)
    end

    def prepare_string_args(args)
      return :error unless args.size == 2
      return nil if args.any?(&:nil?)

      [args[0].to_s.force_encoding('UTF-8'), args[1].to_i]
    end
  end
end
