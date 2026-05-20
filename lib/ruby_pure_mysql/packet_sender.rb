# frozen_string_literal: true

module RubyPureMysql
  # MySQLプロトコルのパケット送信を支援するモジュール
  module PacketSender
    include Constants
    include PacketBuilder

    def send_packet(client, seq, payload)
      len = payload.bytesize
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF].pack('C3')
      packet = header + [seq].pack('C') + payload

      RubyPureMysql.logger.debug "Sending packet [seq: #{seq}, len: #{len}]"
      client.write(packet)
    end

    def read_packet(client)
      header = client.read(4)
      return nil unless header&.bytesize == 4

      len, seq = parse_packet_header(header)
      payload = client.read(len)
      return nil unless payload&.bytesize == len

      RubyPureMysql.logger.debug "Received packet [seq: #{seq}, len: #{len}]"
      [seq, payload]
    end

    def parse_packet_header(header)
      len = header[0..2].unpack('C3').then { |b| b[0] + (b[1] << 8) + (b[2] << 16) }
      seq = header[3].unpack1('C')
      [len, seq]
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

    def send_result_set(client, rows, columns = nil)
      # 行が空の場合、列定義が明示的に渡されていないとメタデータを送信できないためエラーとする
      cols = columns || (rows.first if rows && !rows.empty?)
      raise 'Columns must be provided for empty result sets' if cols.nil?

      # 1. Column Count (seq 1)
      send_packet(client, 1, lenenc_int(cols.size))

      # 2. Column Definition (seq 2...)
      seq = send_column_definitions(client, 2, cols)

      # 3. EOF (seq N)
      send_eof(client, seq & 0xFF)

      # 4. Row Data / 終端
      if rows.empty?
        send_eof(client, (seq + 1) & 0xFF)
      else
        send_rows(client, (seq + 1) & 0xFF, rows)
      end
    end

    def send_rows(client, start_seq, rows)
      current_seq = start_seq
      rows.each do |row|
        send_row_data(client, current_seq & 0xFF, row)
        current_seq += 1
      end
      send_eof(client, current_seq & 0xFF)
    end

    def send_column_definitions(client, start_seq, values)
      seq = start_seq
      values.each_with_index do |val, index|
        send_packet(client, seq & 0xFF, build_column_definition_payload(val, index + 1))
        seq += 1
      end
      seq
    end

    def build_column_definition_payload(val, index)
      type = val.is_a?(String) ? MYSQL_TYPE_VAR_STRING : MYSQL_TYPE_LONGLONG
      name = index.to_s
      pack_column_definition(type, name)
    end

    def pack_column_definition(type, name)
      # Column Definition Packet
      data = [lenenc_str('def'), lenenc_str(''), lenenc_str(''), lenenc_str(''),
              lenenc_str(name), lenenc_str(name), 0x0c, 0x21, 0x00,
              0x00, 0x00, 0x00, 0x00, type, 0x00, 0x00, 0x00, 0x00, 0x00]
      data.pack('a*a*a*a*a*a*C C C C C C C C C C C C C')
    end

    def send_row_data(client, seq, values)
      row_payload = values.map do |v|
        if v.nil?
          [NULL_COLUMN_VALUE].pack('C')
        else
          lenenc_str(v.to_s)
        end
      end.join
      send_packet(client, seq, row_payload)
    end

    def send_eof(client, sequence)
      # EOFパケット: 0xFE, warning_count(0), status_flags(0x0002)
      payload = [EOF_PACKET_HEADER, 0, SERVER_STATUS_AUTOCOMMIT].pack('C v v')
      send_packet(client, sequence, payload)
    end
  end
end
