# frozen_string_literal: true

require_relative 'table_handler_utils'
require_relative 'table_handlers/ddl_handlers'
require_relative 'table_handlers/dml_handlers'
require_relative 'table_handlers/query_handlers'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils
    include DdlHandlers
    include DmlHandlers
    include QueryHandlers

    def prepare_where_clauses(client, columns, where, table_map = {})
      return [] if where.nil?

      compile_where_clauses(client, columns, where, table_map)
    end
  end
end
