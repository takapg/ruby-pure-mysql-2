# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作関数のための共通ユーティリティを提供するモジュール
  module BuiltinStringUtils
    def calculate_substring_index(str, delim, count)
      return str if delim.empty?
      return '' if count.zero?

      down_str = str.downcase
      down_delim = delim.downcase
      positions = []
      start_pos = 0

      while (idx = down_str.index(down_delim, start_pos))
        positions << idx
        start_pos = idx + delim.length
      end

      return str if positions.empty?

      parts = []
      delims = []
      last_pos = 0
      positions.each do |pos|
        parts << str[last_pos...pos]
        delims << str[pos, delim.length]
        last_pos = pos + delim.length
      end
      parts << str[last_pos..-1]

      resolve_substring_index_parts(parts, delims, count)
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

      down_str = str.downcase
      down_from = from.downcase
      result = String.new
      start_pos = 0

      while (idx = down_str.index(down_from, start_pos))
        result << str[start_pos...idx]
        result << to
        start_pos = idx + from.length
      end
      result << str[start_pos..-1]
      result
    end

    private

    def resolve_substring_index_parts(parts, delims, count)
      if count.positive?
        result_parts = parts[0...count]
        result_delims = delims[0...count - 1]
      else
        abs_count = count.abs
        result_parts = parts[-abs_count..-1]
        result_delims = abs_count > 1 ? delims[-(abs_count - 1).. -1] : []
      end

      interleave_parts_and_delims(result_parts, result_delims)
    end

    def interleave_parts_and_delims(parts, delims)
      combined = []
      parts.each_with_index do |p, i|
        combined << p
        combined << delims[i] if i < delims.size
      end
      combined.join
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
