# frozen_string_literal: true

require_relative 'sql_parser/evaluator'

module RubyPureMysql
  # SqlParserUtilsは、SQLパースのユーティリティメソッドを提供します。
  module SqlParserUtils
    module_function

    def split_columns(definition)
      cols = []
      buf = +''
      depth = 0
      definition.each_char { |char| depth, buf = process_char(char, depth, buf, cols) }
      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def split_insert_values(values_str)
      values_str.scan(/(?:'[^']*