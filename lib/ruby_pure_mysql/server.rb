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
          begin
            handle_client(client)
          ensure
            client.close
          end
        end
      end
    end

    private

    def send_packet(client, seq, payload)
      # ペイロードの長さを3バイト（リトルエンディアン）で取得
      len = payload.bytesize
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF].pack("C3")
      client.write(header + [seq].pack("C") + payload)
    end

    def read_packet(client)
      header = client.read(4)
      return nil unless header

      len = header[0..2].unpack1("C3").then { |b| b[0] + (b[1] << 8) + (b[2] << 16) }
      seq = header[3].unpack1("C")
      payload = client.read(len)
      [seq, payload]
    end

    def handle_client(client)
      # A. ハンドシェイク (Seq: 0)
      payload = [10].pack("C") + "8.0.0\0" + [0].pack("L<") + [0].pack("C") + [0xFFF7, 0x8007].pack("L<L<") + [0].pack("C") + "8.0.0\0" + ("\0" * 10)
      send_packet(client, 0, payload)

      # B. 認証レスポンスの読み飛ばし (Seq: 1)
      read_packet(client)

      # C. OKパケットの送信 (Seq: 2)
      send_packet(client, 2, [0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00].pack("C*"))

      # D. コマンド待機ループ
      loop do
        packet = read_packet(client)
        break unless packet

        seq, payload = packet
        command = payload[0].unpack1("C")

        if command == 0x03 # COM_QUERY
          # 1. カラム数
          send_packet(client, 3, [1].pack("C"))
          # 2. カラム定義
          send_packet(client, 4, [0].pack("C") + "1".ljust(10, "\0") + [0].pack("C") + "\0" * 20)
          # 3. EOF
          send_packet(client, 5, [0xFF].pack("C"))
          # 4. 行データ
          send_packet(client, 6, [1].pack("C") + "1")
          # 5. 最終EOF
          send_packet(client, 7, [0xFF].pack("C"))
        end
      end
    end
  end
end
