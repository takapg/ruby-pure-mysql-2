# frozen_string_literal: true

require 'socket'
require_relative 'packet_builder'
require_relative 'constants'

module RubyPureMysql
  # MySQLサーバーの簡易実装クラス
  class Server
    include PacketBuilder
    include Constants

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

    def send_packet(client, seq, payload)
      # ペイロードの長さを3バイト（リトルエンディアン）で取得
      len = payload.bytesize
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF].pack('C3')
      packet = header + [seq].pack('C') + payload

      RubyPureMysql.logger.debug "Sending packet [seq: #{seq}, len: #{len}]"
      client.write(packet)
    end

    def read_packet(client)
      header = client.read(4)
      return nil unless header

      # lenは3バイトのリトルエンディアン
      len = header[0..2].unpack('C3').then { |b| b[0] + (b[1] << 8) + (b[2] << 16) }
      seq = header[3].unpack1('C')
      payload = client.read(len)

      RubyPureMysql.logger.debug "Received packet [seq: #{seq}, len: #{len}]"
      [seq, payload]
    end

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

    def send_handshake(client)
      send_packet(client, 0, build_handshake_payload)
    end

    def send_ok_packet(client, sequence)
      # OKパケット: 0x00, affected_rows(0), last_insert_id(0), status_flags(0x0002), warnings(0)
      payload = [OK_PACKET_HEADER, 0x00, 0x00, SERVER_STATUS_AUTOCOMMIT, 0x00, 0x00].pack('C*')
      send_packet(client, sequence, payload)
    end

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      RubyPureMysql.logger.info "Received Query: #{sql}"

      if sql.downcase =~ /\Aselect\s+(\d+);?\z/
        send_result_set(client, ::Regexp.last_match(1))
      else
        send_ok_packet(client, 1)
      end
    end

    def send_result_set(client, value)
      # 1. Column Count (seq 1)
      send_packet(client, 1, [1].pack('C'))
      # 2. Column Definition (seq 2)
      send_packet(client, 2, build_column_definition_payload)
      # 3. EOF (seq 3)
      send_eof(client, 3)
      # 4. Row Data (seq 4)
      send_packet(client, 4, lenenc_str(value))
      # 5. EOF (seq 5)
      send_eof(client, 5)
    end

    def send_eof(client, sequence)
      # EOFパケット: 0xFE, warning_count(0), status_flags(0x0002)
      send_packet(client, sequence, [EOF_PACKET_HEADER, 0x00, 0x00, SERVER_STATUS_AUTOCOMMIT, 0x00].pack('C*'))
    end
  end
end
