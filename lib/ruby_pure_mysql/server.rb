# frozen_string_literal: true

require 'socket'
require_relative 'packet_builder'
require_relative 'constants'
require_relative 'sql_parser'

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
      # OKパケット: 0x00, affected_rows(0), last_insert_id(0), status_flags(2 bytes), warnings(2 bytes)
      payload = [
        OK_PACKET_HEADER,
        0, # affected_rows
        0, # last_insert_id
        SERVER_STATUS_AUTOCOMMIT, # status_flags (2 bytes, little-endian)
        0                         # warnings (2 bytes, little-endian)
      ].pack('C C C v v')
      send_packet(client, sequence, payload)
    end

    def send_err_packet(client, sequence, message)
      # ERR Packet: 0xFF, ErrorCode(2), SQLStateMarker('#'), SQLState(5), Message
      payload = "#{[0xFF].pack('C')}#{[1].pack('v')}#HY000#{message}"
      send_packet(client, sequence, payload)
    end

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      RubyPureMysql.logger.info "Received Query: #{sql}"

      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        send_result_set(client, result[:result])
      end
    end

    def send_result_set(client, rows)
      # 1. Column Count (seq 1)
      # rows.first.size でカラム数を取得
      send_packet(client, 1, [rows.first.size].pack('C'))

      # 2. Column Definition (seq 2...)
      # カラム定義は最初の行の構造に基づいて作成
      seq = send_column_definitions(client, rows.first)

      # 3. EOF (seq N)
      send_eof(client, seq)

      # 4. Row Data (seq N+1...) & 5. EOF (seq N+last)
      current_seq = (seq + 1) & 0xFF
      rows.each do |row|
        send_row_data(client, current_seq, row)
        current_seq = (current_seq + 1) & 0xFF
      end
      send_eof(client, current_seq)
    end

    def send_column_definitions(client, values)
      seq = 2
      values.each_with_index do |_, index|
        send_packet(client, seq, build_column_definition_payload((index + 1).to_s))
        seq += 1
      end
      seq
    end

    def send_row_data(client, seq, values)
      row_payload = values.map { |v| lenenc_str(v.to_s) }.join
      send_packet(client, seq, row_payload)
    end

    def send_eof(client, sequence)
      # EOFパケット: 0xFE, warning_count(0), status_flags(0x0002)
      send_packet(client, sequence, [EOF_PACKET_HEADER, 0x00, 0x00, SERVER_STATUS_AUTOCOMMIT, 0x00].pack('C*'))
    end
  end
end
