# frozen_string_literal: true

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      # SELECT <式>; を解析 (大文字小文字無視)
      match = query.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      expression = match[1]
      parts = expression.split(',').map(&:strip)

      results = parts.map do |part|
        # 簡易的な算術演算（数字と+のみ）に対応
        if /\A\d+(\s*\+\s*\d+)*\z/.match?(part)
          part.split('+').map(&:strip).map(&:to_i).sum
        else
          return { error: 'Unsupported expression' }
        end
      end

      { result: results }
    end
  end
end
