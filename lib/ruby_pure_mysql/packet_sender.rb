# frozen_string_literal: true

module RubyPureMysql
  # MySQLプロトコルのパケット送信を支援するモジュール
  module PacketSender
    include Constants
    include PacketBuilder
    include PacketIO

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
      cols = resolve_columns(rows, columns)
      return unless valid_row_width?(client, rows, cols)

      # 1. Column Count (seq 1)
      send_packet(client, 1, lenenc_int(cols.size))

      # 2. Column Definition (seq 2...)
      seq = send_column_definitions(client, 2, cols, rows.first)

      # 3. EOF (seq N)
      send_eof(client, seq & 0xFF)

      # 4. Row Data / 終端
      send_result_set_data(client, seq + 1, rows)
    end

    def valid_row_width?(client, rows, cols)
      if rows.any? { |row| row.size != cols.size }
        send_err_packet(client, 1, 'Internal error: Row width mismatch')
        return false
      end
      true
    end

    def send_result_set_data(client, start_seq, rows)
      if rows.empty?
        send_eof(client, start_seq & 0xFF)
      else
        send_rows(client, start_seq & 0xFF, rows)
      end
    end

    def resolve_columns(rows, columns)
      # columnsが明示的に渡されている場合はそれを優先
      return columns if columns && !columns.empty?

      # 渡されていない場合はrowsから推論
      cols = (rows.first if rows && !rows.empty?)

      # どちらも存在しない場合はエラー
      raise 'Columns must be provided for empty result sets' if cols.nil?

      # カラム名がない場合はインデックスを名前にする
      cols.each_with_index.map { |_, i| (i + 1).to_s }
    end

    def send_rows(client, start_seq, rows)
      current_seq = start_seq
      rows.each do |row|
        send_row_data(client, current_seq & 0xFF, row)
        current_seq += 1
      end
      send_eof(client, current_seq & 0xFF)
    end

    def send_column_definitions(client, start_seq, column_names, sample_row)
      seq = start_seq
      column_names.each_with_index do |name, index|
        val = sample_row ? sample_row[index] : nil
        type = val.is_a?(Integer) ? MYSQL_TYPE_LONGLONG : MYSQL_TYPE_VAR_STRING
        send_packet(client, seq & 0xFF, pack_column_definition(type, name))
        seq += 1
      end
      seq
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
