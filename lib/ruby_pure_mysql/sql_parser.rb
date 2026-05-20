# frozen_string_literal: true

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      parts = query.split(/UNION/i).map(&:strip)
      rows = []
      expected_columns = nil

      parts.each do |part|
        result = parse_part(part)
        return result if result.key?(:error)

        expected_columns ||= result[:result].size
        if result[:result].size != expected_columns
          return { error: 'The used SELECT statements have a different number of columns' }
        end

        rows << result[:result]
      end

      { result: rows }
    end

    def self.parse_part(part)
      match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      columns = match[1].split(',').map(&:strip)
      values = columns.map { |col| evaluate_expression(col) }

      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values }
    end

    def self.evaluate_expression(col)
      return :error unless /\A\d+(\s*\+\s*\d+)*\z/.match?(col)

      col.split('+').map(&:strip).map(&:to_i).sum
    end
    private_class_method :parse_part, :evaluate_expression
  end
end
