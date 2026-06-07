# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作関数のための共通ユーティリティを提供するモジュール
  module BuiltinStringUtils
    def calculate_substring_index(str, delim, count)
      return str if delim.empty?

      positions = find_all_indices(str, delim)
      return str if positions.empty?

      if count.positive?
        slice_substring_index_positive(str, positions, count)
      else
        slice_substring_index_negative(str, positions, count, delim)
      end
    end

    def calculate_locate_index(str, substr, pos)
      return 0 if pos < 1

      down_str = str.downcase
      down_substr = substr.downcase
      idx = down_str.index(down_substr, pos - 1)
      idx ? idx + 1 : 0
    end

    private

    def find_all_indices(str, substr)
      positions = []
      pos = 0
      regex = Regexp.new(Regexp.escape(substr), Regexp::IGNORECASE)
      while (match = str.match(regex, pos))
        positions << match.begin(0)
        pos = match.end(0)
      end
      positions
    end

    def slice_substring_index_positive(str, positions, count)
      limit = count > positions.size ? str.length : positions[count - 1]
      str[0, limit]
    end

    def slice_substring_index_negative(str, positions, count, delim)
      idx = positions.size + count
      idx.negative? ? str : str[(positions[idx] + delim.length)..]
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
