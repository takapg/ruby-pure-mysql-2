# frozen_string_literal: true

require 'socket'
require_relative 'packet_builder'
require_relative 'constants'
require_relative 'sql_parser'
require_relative 'packet_sender'
require_relative 'storage_engine'

module RubyPureMysql
  # MySQLサーバーの簡易実装クラス
  class Server
    include PacketBuilder
    include Constants
    include PacketSender

    def initialize(host: '127.0.0.1', port: 3307)
      @server = TCPServer.new(host, port)
      @storage_engine = StorageEngine.new
    end

    def run
      loop do
        client = @server.accept
        Thread.new do
          handle_client(client)
        rescue Errno::EPIPE
          # クライアントが切断された場合は無視
        ensure
          client.close
        end
      end
    end

    private

    def handle_client(client)
      send_handshake(client)
      read_packet(client)
      # 認証応答に対するOKパケットのシーケンス番号は2
      send_ok_packet(client, 2)

      loop do
        packet = read_packet(client)
        break unless packet

        _, payload = packet
        command = payload[0].unpack1('C')

        handle_query(client, payload) if command == COM_QUERY
      end
    end

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      RubyPureMysql.logger.info "Received Query: #{sql}"

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
      when :select_from  then handle_select(client, result)
      else send_result_set(client, result[:result], result[:columns])
      end
    end

    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless columns

      if result[:values].size != columns.size
        return send_err_packet(client, 1, 'Column count doesn\'t match value count at row 1', 1136)
      end

      @storage_engine.insert(result[:table_name], result[:values])
      send_ok_packet(client, 1)
    end

    def handle_select(client, result)
      table_columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) if table_columns.nil?

      rows = @storage_engine.select(result[:table_name])

      if result[:where]
        rows = apply_where_filter(client, result[:where], table_columns, rows)
        return unless rows
      end

      if result[:columns] == ['*']
        send_result_set(client, rows, table_columns)
      else
        handle_projection(client, result, rows, table_columns)
      end
    end

    def apply_where_filter(client, where_clause, table_columns, rows)
      col_idx = table_columns.index(where_clause[:column])
      unless col_idx
        send_err_packet(client, 1, "Unknown column '#{where_clause[:column]}' in WHERE clause", 1054)
        return nil
      end

      rows.select { |row| row[col_idx] == where_clause[:value] }
    end

    def handle_projection(client, result, rows, table_columns)
      indices = result[:columns].map { |col| table_columns.index(col) }

      if indices.include?(nil)
        send_err_packet(client, 1, 'Unknown column in field list', 1054)
        return
      end

      projected_rows = rows.map { |row| indices.map { |i| row[i] } }
      send_result_set(client, projected_rows, result[:columns])
    end

    def handle_create_table(client, result)
      if @storage_engine.create_table(result[:table_name], result[:columns]) || result[:if_not_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' already exists", 1050)
      end
    end

    def handle_drop_table(client, result)
      if @storage_engine.drop_table(result[:table_name]) || result[:if_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Unknown table '#{result[:table_name]}'", 1051)
      end
    end
  end
end
