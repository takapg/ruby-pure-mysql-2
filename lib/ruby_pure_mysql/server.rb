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
      protocol_version = 10
      server_version = "8.0.0\0"
      connection_id = 1
      auth_part1 = '12345678'
      filler = 0x00
      capability_flags_lower = 0xF7FF
      character_set = 0x21
      status_flags = 0x0002
      capability_flags_upper = 0x8007
      auth_plugin_data_len = 0x15
      reserved = "\0" * 10
      auth_part2 = '1234567890123'
      auth_plugin_name = "mysql_native_password\0"

      payload = [protocol_version].pack('C') +
                server_version +
                [connection_id].pack('L<') +
                auth_part1 +
                [filler].pack('C') +
                [capability_flags_lower].pack('S<') +
                [character_set].pack('C') +
                [status_flags].pack('S<') +
                [capability_flags_upper].pack('S<') +
                [auth_plugin_data_len].pack('C') +
                reserved +
                auth_part2 +
                auth_plugin_name

      send_packet(client, 0, payload)
    end

    def send_ok_packet(client, sequence)
      send_packet(client, sequence, [0x00, 0x00, 0x00, 0x02, 0x00, 0x00].pack('C*'))
    end

    def handle_query(client, packet_body)
      # 1. カラム数
      send_packet(client, 3, [1].pack('C'))

      # 2. カラム定義
      col_def = lenenc_str('') + # catalog
                lenenc_str('') + # schema
                lenenc_str('') + # table
                lenenc_str('') + # org_table
                lenenc_str('1') + # name
                lenenc_str('1') + # org_name
                [0x0C].pack('C') + # length of fixed fields
                [0x21, 0x00].pack('S<') + # charset
                [10].pack('L<') + # column length
                [0x08].pack('C') + # type (LONGLONG)
                [0x0000].pack('S<') + # flags
                [0].pack('C') + # decimals
                [0x00, 0x00].pack('C2') # filler

      send_packet(client, 4, col_def)

      # 3. EOF
      send_packet(client, 5, [0xFE, 0x00, 0x00, 0x02, 0x00].pack('C*'))

      # 4. 行データ
      row_data = lenenc_str('1')
      send_packet(client, 6, row_data)

      # 5. 最終EOF
      send_packet(client, 7, [0xFE, 0x00, 0x00, 0x02, 0x00].pack('C*'))
    end
  end
end
