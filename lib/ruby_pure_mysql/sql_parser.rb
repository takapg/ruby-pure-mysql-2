# frozen_string_literal: true

require_relative 'sql_parser/evaluator'

module RubyPureMysql
  # SqlParserは、SQLクエリを解析して内部表現に変換するクラスです
  class SqlParser
    PARSERS = {
      /\ACREATE\s+TABLE/i => :parse_create_table,
      /\ADROP\s+TABLE/i => :parse_drop_table,
      /\AINSERT\s+INTO/i => :parse_insert,
      /\AUPDATE\s+/i => :parse_update,
      /\ADELETE\s+/i => :parse_delete,
      /\ASELECT\s+/i => :parse_select,
      /\ASHOW\s+TABLES\s*;?\s*\z/i => :parse_show_tables
    }.freeze

    def self.parse(query)
      query = query.strip
      parser = PARSERS.find { |regex, _| query =~ regex }
      return { error: 'Unsupported SQL' } unless parser

      send(parser.last, query)
    rescue StandardError => e
      { error: "Parse error: #{e.message}" }
    end

    def self.parse_select(query)
      if query =~ /\sFROM\s+/i
        # SELECT ... FROM table ...
        match = query.match(/\ASELECT\s+(.+?)\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+))?/i)
        if match
          columns = match[1].split(',').map(&:strip)
          table_name = match[2]
          where_clause = match[3] ? parse_where_clause(match[3]) : nil
          { type: :select_from, table_name: table_name, columns: columns, where: where_clause }
        else
          { error: 'Invalid SELECT FROM syntax' }
        end
      elsif query =~ /UNION/i
        # UNION の簡易対応
        parts = query.split(/UNION/i).map(&:strip)
        { type: :union, queries: parts.map { |p| parse_select(p) } }
      else
        # SELECT 1, 2, SELECT 1+1, SELECT @@version_comment など
        # カンマ区切りの式をサポート
        expr_part = query.sub(/\ASELECT\s+/i, '').gsub(/;\z/, '').strip
        expressions = expr_part.split(',').map(&:strip)
        { type: :select_expression, expressions: expressions }
      end
    end

    def self.parse_show_tables(_query)
      { type: :show_tables }
    end

    def self.parse_create_table(query)
      # CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));
      match = query.match(/\ACREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s*\((.+)\)/i)
      if match
        table_name = match[1]
        columns = match[2].split(',').map { |c| c.strip.split(/\s+/).first }
        { type: :create_table, table_name: table_name, columns: columns, if_not_exists: query.include?('IF NOT EXISTS') }
      else
        { error: 'Invalid CREATE TABLE syntax' }
      end
    end

    def self.parse_drop_table(query)
      match = query.match(/\ADROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)/i)
      if match
        { type: :drop_table, table_name: match[1], if_exists: query.include?('IF EXISTS') }
      else
        { error: 'Invalid DROP TABLE syntax' }
      end
    end

    def self.parse_insert(query)
      # INSERT INTO users VALUES (1, 'alice');
      match = query.match(/\AINSERT\s+INTO\s+([a-zA-Z0-9_]+)\s+VALUES\s*\((.+)\)/i)
      if match
        table_name = match[1]
        values = match[2].split(',').map(&:strip).map { |v| v.gsub(/['"]/, '') }
        values = values.map { |v| v =~ /\A\d+\z/ ? v.to_i : v }
        { type: :insert, table_name: table_name, values: values }
      else
        { error: 'Invalid INSERT syntax' }
      end
    end

    def self.parse_update(query)
      # UPDATE users SET name = 'charlie' WHERE id = 1;
      match = query.match(/\AUPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)\s+WHERE\s+(.+)/i)
      if match
        table_name = match[1]
        set_clause = match[2].split('=')
        col_name = set_clause[0].strip
        new_value = set_clause[1].strip.gsub(/['"]/, '')
        new_value = new_value.to_i if new_value =~ /\A\d+\z/
        
        where_clause = parse_where_clause(match[3])
        { type: :update, table_name: table_name, column: col_name, value: new_value, where: where_clause }
      else
        { error: 'Invalid UPDATE syntax' }
      end
    end

    def self.parse_delete(query)
      # DELETE FROM users WHERE id = 2;
      match = query.match(/\ADELETE\s+FROM\s+([a-zA-Z0-9_]+)\s+WHERE\s+(.+)/i)
      if match
        table_name = match[1]
        where_clause = parse_where_clause(match[2])
        { type: :delete, table_name: table_name, where: where_clause }
      else
        { error: 'Invalid DELETE syntax' }
      end
    end

    def self.parse_where_clause(clause)
      # id = 1
      match = clause.match(/([a-zA-Z0-9_]+)\s*=\s*(.+)/)
      if match
        value = match[2].strip.gsub(/['"]/, '')
        value = value.to_i if value =~ /\A\d+\z/
        { column: match[1], value: value }
      else
        {}
      end
    end

    def self.convert_value(val); val; end

    private_class_method :parse_insert, :parse_select, :parse_create_table,
                         :parse_drop_table, :convert_value, :parse_where_clause,
                         :parse_update, :parse_delete, :parse_show_tables
  end
end
