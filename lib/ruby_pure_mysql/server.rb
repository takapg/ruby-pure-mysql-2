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

        _, payload = packet
        command = payload[0].unpack1('C')

        handle_query(client, payload) if command == 0x03
      end
    end

    def send_handshake(client)
      send_packet(client, 0, build_handshake_payload)
    end

    def build_handshake_payload
      [10].pack('C') + "8.0.0\0" + [1].pack('L<') + '12345678' + [0x00].pack('C') +
        [0xF7FF].pack('S<') + [0x21].pack('C') + [0x0002].pack('S<') +
        [0x8007].pack('S<') + [0x15].pack('C') + "\0" * 10 + '1234567890123' +
        "mysql_native_password\0"
    end

    def send_ok_packet(client, sequence)
      send_packet(client, sequence, [0x00, 0x00, 0x00, 0x02, 0x00, 0x00].pack('C*'))
    end

    def handle_query(client, _packet_body)
      send_column_definition(client)
      send_eof(client, 5)
      send_row_data(client)
      send_eof(client, 7)
    end

    def send_column_definition(client)
      send_packet(client, 3, [1].pack('C'))
      col_def = lenenc_str('') * 4 + lenenc_str('1') * 2 + [0x0C].pack('C') +
                [0x21, 0x00].pack('S<') + [10].pack('L<') + [0x08].pack('C') +
                [0x0000].pack('S<') + [0].pack('C') + [0x00, 0x00].pack('C2')
      send_packet(client, 4, col_def)
    end

    def send_row_data(client)
      send_packet(client, 6, lenenc_str('1'))
    end

    def send_eof(client, sequence)
      send_packet(client, sequence, [0xFE, 0x00, 0x00, 0x02, 0x00].pack('C*'))
    end
  end
end
