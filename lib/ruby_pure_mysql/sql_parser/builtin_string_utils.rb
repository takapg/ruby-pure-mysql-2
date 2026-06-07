# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作関数のための共通ユーティリティを提供するモジュール
  module BuiltinStringUtils
    def calculate_substring_index(str, delim, count)
      return str if delim.empty?
      return '' if count.zero?

      search_str = str.downcase
      search_delim = delim.downcase
      positions = []
      start_pos = 0

      while (idx = search_str.index(search_delim, start_pos))
        positions << idx
        start_pos = idx + search_delim.length
      end

      return str if positions.empty?

      parts = []
      last_pos = 0
      positions.each do |pos|
        parts << str[last_pos...pos]
        parts << str[pos, delim.length]
        last_pos = pos + delim.length
      end
      parts << str[last_pos..-1]

      extract_substring_parts(parts, count)
    end

    def calculate_locate_index(str, substr, pos)
      return 0 if pos < 1

      down_str = str.downcase
      down_substr = substr.downcase
      idx = down_str.index(down_substr, pos - 1)
      idx ? idx + 1 : 0
    end

    def calculate_replace_value(str, from, to)
      return str if from.empty?

      result = String.new
      start_pos = 0
      search_str = str.downcase
      search_from = from.downcase

      while (idx = search_str.index(search_from, start_pos))
        result << str[start_pos...idx]
        result << to
        start_pos = idx + from.length
      end
      result << str[start_pos..-1]
      result
    end

    private

    def extract_substring_parts(parts, count)
      if count.positive?
        parts[0...((count * 2) - 1)].join
      else
        parts[-((count.abs * 2) - 1)..].join
      end
    end

    def execute_padding(args, direction)
      params = prepare_padding_params(args)
      return params if params == :error || params.nil?

      str, len, padstr = params
      return nil if len.negative?
      return str[0, len] if str.length >= len
      return '' if padstr.empty?

      direction == :left ? str.rjust(len, padstr) : str.ljust(len, padstr)
    end

    def execute_trim_operation(args, method)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_s.force_encoding('UTF-8').public_send(method)
    end

    def prepare_string_args(args)
      return :error unless args.size == 2
      return nil if args.any?(&:nil?)

      [args[0].to_s.force_encoding('UTF-8'), args[1].to_i]
    end

    def prepare_padding_params(args)
      return :error unless args.size == 3
      return nil if args.any?(&:nil?)

      [
        args[0].to_s.force_encoding('UTF-8'),
        args[1].to_i,
        args[2].to_s.force_encoding('UTF-8')
      ]
    end
  end
end
