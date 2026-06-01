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
      return nil if where.nil? || where.empty?

      groups = normalize_where_groups(where)
      if compile_groups(client, columns, groups, table_map).nil?
        send_err_packet(client, 1, "Unknown column in WHERE clause", 1054)
        return false
      end
      where
    end
  end
end
