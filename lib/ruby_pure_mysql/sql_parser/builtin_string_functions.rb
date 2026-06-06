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

    def handle_locate(args)
      return :error unless [2, 3].include?(args.size)
      return nil if args.any?(&:nil?)

      substr, str = args[0].to_s, args[1].to_s
      pos = args[2] ? args[2].to_i : 1

      return 0 if pos < 1

      # Rubyのindexは0ベース、MySQLのLOCATEは1ベース
      # posも1ベースのため、Rubyのindexには pos - 1 を渡す
      idx = str.index(substr, pos - 1)
      idx ? idx + 1 : 0
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

    def execute_trim_operation(args, method)
      return :error unless args.size == 1

      val = args[0]
      return nil if val.nil?

      val.to_s.public_send(method)
    end
  end
end
