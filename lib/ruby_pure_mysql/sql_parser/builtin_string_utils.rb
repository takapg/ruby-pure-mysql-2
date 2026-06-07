# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作関数のための共通ユーティリティを提供するモジュール
  module BuiltinStringUtils
    def calculate_substring_index(str, delim, count)
      return str if delim.empty?

      positions = collect_delimiter_positions(str, delim)
      return str if positions.empty?

      extract_by_count(str, positions, delim, count)
    end

    def calculate_locate_index(str, substr, pos)
      return 0 if pos < 1

      down_str = str.downcase
      down_substr = substr.downcase
      idx = down_str.index(down_substr, pos - 1)
      idx ? idx + 1 : 0
    end

    private

    def collect_delimiter_positions(str, delim)
      positions = []
      curr = 0
      down_str = str.downcase
      down_delim = delim.downcase

      while (idx = down_str.index(down_delim, curr))
        positions << idx
        curr = idx + down_delim.length
      end
      positions
    end

    def extract_by_count(str, positions, delim, count)
      if count.positive?
        end_pos = positions[count - 1] || str.length
        str[0...end_pos]
      else
        return str if count.abs > positions.size

        start_pos = positions[count] + delim.length
        str[start_pos..]
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

      val.to_s.public_send(method)
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
