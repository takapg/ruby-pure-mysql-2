# frozen_string_literal: true

require 'socket'
require_relative 'packet_builder'
require_relative 'constants'
require_relative 'sql_parser'
require_relative 'packet_sender'
require_relative 'storage_engine'
require_relative 'query_handler'

module RubyPureMysql
  # MySQLサーバーの簡易実装クラス
  class Server
    include PacketBuilder
    include Constants
    include PacketSender
    include QueryHandler

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
        rescue StandardError => e
          RubyPureMysql.logger.error "Unhandled exception in client thread: #{e.message}\n#{e.backtrace.join("\n")}"
        ensure
          client.close
        end
      end
    end

    private

    def handle_client(client)
      send_handshake(client)
      packet = read_packet(client)
      return unless packet

      # 認証応答に対するOKパケットのシーケンス番号は2
      send_ok_packet(client, 2)

      process_client_packets(client)
    end

    def process_client_packets(client)
      loop do
        begin
          packet = read_packet(client)
          break unless packet

          handle_client_packet(client, packet)
        rescue StandardError => e
          RubyPureMysql.logger.error "Error handling client: #{e.message}\n#{e.backtrace.join("\n")}"
          send_err_packet(client, 1, "Internal server error: #{e.message}", 1105)
        end
      end
    end

    def handle_client_packet(client, packet)
      _, payload = packet
      command = payload[0].unpack1('C')
      handle_query(client, payload) if command == COM_QUERY
    end
  end
end
