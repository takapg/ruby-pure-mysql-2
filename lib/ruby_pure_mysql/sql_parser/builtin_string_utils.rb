# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作関数のための共通ユーティリティを提供するモジュール
  module BuiltinStringUtils
    def calculate_substring_index(str, delim, count)
      indices = []
      pos = 0
      while (idx = str.downcase.index(delim.downcase, pos))
        indices << idx
        pos = idx + delim.length
      end
      return str if indices.empty?

      if count.positive?
        split_pos = indices[count - 1] || str.length
        str[0, split_pos]
      else
        idx_pos = indices.size + count
        split_pos = idx_pos < 0 ? nil : indices[idx_pos]
        start_pos = split_pos ? split_pos + delim.length : 0
        str[start_pos..-1]
      end
    end

    def calculate_locate_index(str, substr, pos)
      return 0 if pos < 1

      idx = str.downcase.index(substr.downcase, pos - 1)
      idx ? idx + 1 : 0
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
