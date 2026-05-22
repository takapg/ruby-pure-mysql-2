# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    HANDLERS = {
      show_tables:  :handle_show_tables,
      create_table: :handle_create_table,
      drop_table:   :handle_drop_table,
      insert:       :handle_insert,
      update:       :handle_update,
      delete:       :handle_delete,
      select_from:  :handle_select
    }.freeze

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      query_type = sql.split(/\s+/, 2).first&.upcase
      RubyPureMysql.logger.info "Received Query type: #{query_type}"

      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        dispatch_query(client, result)
      end
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
