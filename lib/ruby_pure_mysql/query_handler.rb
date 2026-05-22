# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    DISPATCH_MAP = {
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
      # query_type = sql.split(/\s+/, 2).first&.upcase
      # TODO: semantic_logger を導入後、trace に変更する
      # RubyPureMysql.logger.info "Received Query type: #{query_type}"

      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        dispatch_query(client, result)
      end
    end

    def dispatch_query(client, result)
      handler = DISPATCH_MAP[result[:type]]
      if handler
        send(handler, client, result)
      else
        send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
