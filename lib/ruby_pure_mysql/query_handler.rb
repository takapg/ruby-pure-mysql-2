# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    HANDLERS = {
      create_table: :handle_create_table,
      drop_table: :handle_drop_table,
      insert: :handle_insert,
      update: :handle_update,
      delete: :handle_delete,
      select_from: :handle_select,
      show_tables: :handle_show_tables
    }.freeze

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip

      return handle_show_tables_query(client) if sql.upcase.start_with?('SHOW TABLES')

      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        dispatch_query(client, result)
      end
    end

    def handle_show_tables_query(client)
      dispatch_query(client, { type: :show_tables })
    end

    def dispatch_query(client, result)
      handler = HANDLERS[result[:type]]
      if handler
        send(handler, client, result)
      else
        send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
