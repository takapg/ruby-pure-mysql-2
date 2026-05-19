# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  # MySQLサーバーの簡易実装クラス
  class Server
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
      client.write(header + [seq].pack('C') + payload)
    end

    def read_packet(client)
      header = client.read(4)
      return nil unless header

      # lenは3バイトのリトルエンディアン
      len = header[0..2].unpack('C3').then { |b| b[0] + (b[1] << 8) + (b[2] << 16) }
      seq = header[3].unpack1('C')
      payload = client.read(len)
      [seq, payload]
    end

    def lenenc_str(str)
      [str.bytesize].pack('C') + str
    end

    def handle_client(client)
      send_handshake(client)
      read_packet(client)
      send_ok_packet(client, 2)

      loop do
        packet = read_packet(client)
        break unless packet

        seq, payload = packet
        command = payload[0].unpack1('C')

        handle_query(client, seq, payload) if command == 0x03
      end
    end

    def send_handshake(client)
      send_packet(client, 0, build_handshake_payload)
    end

    def build_handshake_payload
      [build_handshake_header, build_handshake_auth_data].join
    end

    def build_handshake_header
      [[10].pack('C'), "Hey-MySQL-8.0\0", [1].pack('L<'), '12345678', [0x00].pack('C')].join
    end

    def build_handshake_auth_data
      [
        [0xF7FF, 0x21, 0x0002, 0x8007, 0x15].pack('S< C S< S< C'),
        "\0" * 10,
        '1234567890123',
        "mysql_native_password\0"
      ].join
    end

    def send_ok_packet(client, sequence)
      send_packet(client, sequence, [0x00, 0x00, 0x00, 0x02, 0x00, 0x00].pack('C*'))
    end

    def handle_query(client, seq, packet_body)
      # クエリに対する応答は、受信したパケットのシーケンス番号の次から始まる
      current_seq = seq + 1
      query = packet_body[1..-1]

      if query.downcase.include?('select 1')
        # Column Count (1)
        send_packet(client, current_seq, [1].pack('C'))
        current_seq += 1

        # Column Definition
        send_packet(client, current_seq, build_column_definition_payload)
        current_seq += 1

        # EOF
        send_eof(client, current_seq)
        current_seq += 1

        # Row Data
        send_packet(client, current_seq, lenenc_str('1'))
        current_seq += 1

        # EOF
        send_eof(client, current_seq)
      else
        # 未対応のクエリに対してはエラーを返す（簡易実装）
        send_ok_packet(client, current_seq)
      end
    end

    def build_column_definition_payload
      [
        lenenc_str('def'),
        lenenc_str(''),
        lenenc_str(''),
        lenenc_str('1'),
        lenenc_str('1'),
        [0x0C, 0x21].pack('CS<'),
        [10].pack('L<'),
        [0x08, 0].pack('CS<'),
        [0, 0, 0].pack('C3')
      ].join
    end

    def send_eof(client, sequence)
      send_packet(client, sequence, [0xFE, 0x00, 0x00, 0x02, 0x00].pack('C*'))
    end
  end
end
