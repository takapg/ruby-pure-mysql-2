# frozen_string_literal: true

require 'socket'
require_relative 'packet_builder'
require_relative 'constants'
require_relative 'sql_parser'
require_relative 'packet_sender'

module RubyPureMysql
  # MySQLサーバーの簡易実装クラス
  class Server
    include PacketBuilder
    include Constants
    include PacketSender

    def initialize(host: '127.0.0.1', port: 3307)
      @server = TCPServer.new(host, port)
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
        # :columns を明示的に渡す
        send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
