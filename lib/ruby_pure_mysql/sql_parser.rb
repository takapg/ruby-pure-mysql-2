# frozen_string_literal: true

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      # UNIONで分割して各パートを処理
      parts = query.split(/UNION/i).map(&:strip)
      rows = parts.map do |part|
        match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
        return { error: 'Invalid SQL' } unless match

        expression = match[1]
        columns = expression.split(',').map(&:strip)

        columns.map do |col|
          return { error: 'Unsupported expression' } unless /\A\d+(\s*\+\s*\d+)*\z/.match?(col)
          col.split('+').map(&:strip).map(&:to_i).sum
        end
      end

      { result: rows }
    end
  end
end
