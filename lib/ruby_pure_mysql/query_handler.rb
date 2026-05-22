# frozen_string_literal: true

require_relative 'table_handlers'

module RubyPureMysql
  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

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
      case result[:type]
      when :create_table then handle_create_table(client, result)
      when :drop_table   then handle_drop_table(client, result)
      when :insert       then handle_insert(client, result)
      when :update       then handle_update(client, result)
      when :delete       then handle_delete(client, result)
      when :select_from  then handle_select(client, result)
      when :select_expression then handle_select_expression(client, result)
      when :union        then handle_union(client, result)
      when :show_tables  then handle_show_tables(client)
      else send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
