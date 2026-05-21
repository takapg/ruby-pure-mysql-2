# frozen_string_literal: true

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      if query.match?(/\ACREATE\s+TABLE/i)
        parse_create_table(query)
      else
        parts = query.split(/\s+UNION\s+/i).map(&:strip)
        process_parts(parts)
      end
    end

    def self.parse_create_table(query)
      match = query.match(/\ACREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid CREATE TABLE syntax' } unless match

      {
        type: :create_table,
        if_not_exists: !match[1].nil?,
        table_name: match[2],
        columns: split_columns(match[3])
      }
    end

    def self.split_columns(definition)
      cols = []
      buf = +''
      depth = 0

      definition.each_char do |ch|
        case ch
        when '('
          depth += 1
          buf << ch
        when ')'
          depth -= 1 if depth > 0
          buf << ch
        when ','
          if depth.zero?
            cols << buf.strip
            buf = +''
          else
            buf << ch
          end
        else
          buf << ch
        end
      end

      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def self.process_parts(parts)
      state = { expected: nil, columns: nil }
      rows = parts.map do |part|
        res = process_single_part(part, state)
        return res if res.key?(:error)

        res[:result]
      end
      { result: rows, columns: state[:columns] }
    end

    def self.process_single_part(part, state)
      res = validate_part(part, state[:expected])
      return res if res.key?(:error)

      state[:expected] ||= res[:size]
      state[:columns] ||= res[:columns]
      res
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
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if /\A\d+(\s*\+\s*\d+)*\z/.match?(col)

      :error
    end

    def self.evaluate_system_variable(col)
      case col.downcase
      when '@@version_comment' then 'ruby-pure-mysql-2'
      when '@@max_allowed_packet' then 67_108_864
      else :error
      end
    end

    def self.evaluate_string_literal(col)
      col.match(/\A(['"])(.*?)\1\z/)[2]
    end

    def self.evaluate_math(col)
      col.split('+').sum { |x| x.strip.to_i }
    end
    private_class_method :parse_part, :evaluate_expression, :process_parts, :validate_part,
                         :evaluate_system_variable, :evaluate_string_literal, :evaluate_math,
                         :process_single_part, :split_columns
  end
end
