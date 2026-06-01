# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    HANDLER_MAP = {
      create_table: :handle_create_table,
      drop_table: :handle_drop_table,
      insert: :handle_insert,
      update: :handle_update,
      delete: :handle_delete,
      select_from: :handle_select,
      show_tables: :handle_show_tables,
      describe: :handle_describe
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
      handler = HANDLER_MAP[result[:type]]

      if handler
        send(handler, client, result)
      else
        rows = result[:result]
        # UNION (non-ALL) は暗黙的に DISTINCT であるため、重複排除を適用する
        rows = apply_distinct(rows) if result[:type] == :union
        send_result_set(client, rows, result[:columns])
      end
    end
  end
end
