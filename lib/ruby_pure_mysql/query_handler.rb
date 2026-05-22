# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    QUERY_DISPATCHER = {
      create_table: :handle_create_table,
      drop_table:   :handle_drop_table,
      insert:       :handle_insert,
      update:       :handle_update,
      delete:       :handle_delete,
      select_from:  :handle_select,
      show_tables:  :handle_show_tables
    }.freeze

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        dispatch_query(client, result)
      end
    end

    def dispatch_query(client, result)
      method_name = QUERY_DISPATCHER[result[:type]]
      if method_name
        send(method_name, client, result)
      else
        send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
