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
      /\ASELECT\s+.+?\s+FROM/i => :parse_select_from,
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

    def self.parse_show_tables(_query)
      { type: :show_tables }
    end

    # 既存のパースメソッド（実装は省略されていますが、構造を維持します）
    def self.parse_create_table(_query); { type: :create_table }; end
    def self.parse_drop_table(_query); { type: :drop_table }; end
    def self.parse_insert(_query); { type: :insert }; end
    def self.parse_update(_query); { type: :update }; end
    def self.parse_delete(_query); { type: :delete }; end
    def self.parse_select_from(_query); { type: :select_from }; end
    def self.convert_value(val); val; end
    def self.parse_where_clause(_clause); {}; end

    private_class_method :parse_insert, :parse_select_from, :parse_create_table,
                         :parse_drop_table, :convert_value, :parse_where_clause,
                         :parse_update, :parse_delete, :parse_show_tables
  end
end
