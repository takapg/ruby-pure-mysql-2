# frozen_string_literal: true

module RubyPureMysql
  # 文字列操作に関する組み込み関数の評価ロジックを提供するモジュール
  module BuiltinStringFunctions
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
  end
end
