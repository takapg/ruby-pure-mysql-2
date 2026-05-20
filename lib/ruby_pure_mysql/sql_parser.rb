# frozen_string_literal: true

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      parts = query.split(/\s+UNION\s+/i).map(&:strip)
      process_parts(parts)
    end

    def self.process_parts(parts)
      rows = []
      expected_columns = nil
      column_names = nil
      parts.each do |part|
        res = validate_part(part, expected_columns)
        return res if res.key?(:error)

        expected_columns ||= res[:size]
        column_names ||= res[:columns]
        rows << res[:result]
      end
      { result: rows, columns: column_names }
    end

    def self.validate_part(part, expected_columns)
      result = parse_part(part)
      return result if result.key?(:error)
      if expected_columns && result[:result].size != expected_columns
        return { error: 'The used SELECT statements have a different number of columns' }
      end

      { result: result[:result], columns: result[:columns], size: result[:result].size }
    end

    def self.parse_part(part)
      match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      columns = match[1].split(',').map(&:strip)
      values = columns.map { |col| evaluate_expression(col) }

      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values, columns: columns }
    end

    def self.evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')

      # システム変数対応
      if col.start_with?('@@')
        return case col.downcase
               when '@@version_comment' then 'ruby-pure-mysql-2'
               when '@@max_allowed_packet' then 67108864
               else :error
               end
      end

      if (match = col.match(/\A(['"])(.*?)\1\z/))
        return match[2]
      end
      return :error unless /\A\d+(\s*\+\s*\d+)*\z/.match?(col)

      col.split('+').sum { |x| x.strip.to_i }
    end
    private_class_method :parse_part, :evaluate_expression, :process_parts, :validate_part
  end
end
