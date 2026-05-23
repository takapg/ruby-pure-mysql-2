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

    def prepare_where_clauses(client, columns, where)
      return [] if where.nil?

      compile_where_clauses(client, columns, where)
    end

    def get_column_index(client, columns, column_name)
      col_idx = columns.index(column_name)
      if col_idx.nil?
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054)
        return nil
      end
      col_idx
    end
  end
end
