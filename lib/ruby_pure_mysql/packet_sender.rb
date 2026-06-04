# frozen_string_literal: true

require_relative 'packet_io'

module RubyPureMysql
  # カラム定義パケットの構築を支援するユーティリティ
  module PacketDefinitionUtils
    def determine_column_type(val)
      if val.is_a?(Integer)
        Constants::MYSQL_TYPE_LONGLONG
      elsif val.is_a?(Float)
        Constants::MYSQL_TYPE_DOUBLE
      else
        Constants::MYSQL_TYPE_VAR_STRING
      end
    end

    def pack_column_definition(type, name, org_name)
      # Column Name, Alias, Type, Length, Charset, Collation
      data = [
        lenenc_str(org_name),
        lenenc_str(name),
        lenenc_str(''),
        lenenc_str(''),
        lenenc_str(''),
        lenenc_str(''),
        0x0c, # Privilege
        0x0021, # Flags
        0, # Numeric Flags
        0, # Space
        type, # Type
        0, # Unsigned
        0 # Zero Fill
      ]
      data.pack('a*a*a*a*a*a*C v V C C C C')
    end

    def resolve_column_names(name_info, index, original_names)
      name = name_info.is_a?(Hash) ? (name_info[:alias] || name_info[:original]) : name_info
      org_name = if original_names
                   raw_org = original_names[index]
                   raw_org.is_a?(Hash) ? (raw_org[:original] || raw_org) : raw_org
                 else
                   name
                 end
      [name.to_s.split('.').last, org_name.to_s.split('.').last]
    end
  end

  # MySQLプロトコルのパケット送信を支援するモジュール
  module PacketSender
    include Constants
    include PacketBuilder
    include PacketIO
    include PacketDefinitionUtils

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

    # 0x042A = 1066 (Default)
    def send_err_packet(client, sequence, message, error_code = 0x042A)
      # ERR Packet: 0xFF, ErrorCode(2), SQLStateMarker('#'), SQLState(5), Message
      payload = [0xFF, error_code].pack('Cv') + "#HY000#{message}"
      send_packet(client, sequence, payload)
    end

    def send_result_set(client, rows, columns = nil, original_columns = nil)
      cols = resolve_columns(rows, columns)
      return unless valid_row_width?(client, rows, cols)

      # 1. Column Count (seq 1)
      seq = 1
      send_packet(client, seq, lenenc_int(cols.size))

      # 2. Column Definition (seq 2...)
      seq = send_column_definitions(client, seq + 1, cols, rows, original_columns)

      # 3. EOF (結果セットの定義終了を示す)
      send_eof(client, seq & 0xFF)
      seq += 1

      # 4. Row Data (seq N+1...)
      if rows.any?
        send_rows(client, seq & 0xFF, rows)
      else
        send_eof(client, seq & 0xFF)
      end
    end

    def valid_row_width?(client, rows, cols)
      if rows.any? { |row| !row.respond_to?(:size) || row.size != cols.size }
        send_err_packet(client, 1, 'Internal error: Invalid row type or width mismatch')
        return false
      end
      true
    end


    def resolve_columns(rows, columns)
      return resolve_explicit_columns(columns) if columns && !columns.empty?

      cols = rows&.first
      raise 'Columns must be provided for empty result sets' if cols.nil?

      resolve_implicit_columns(cols)
    end

    private

    def resolve_explicit_columns(columns)
      columns
    end

    def resolve_implicit_columns(cols)
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

    def send_column_definitions(client, start_seq, column_names, rows, original_names = nil)
      seq = start_seq
      rows ||= []
      column_names.each_with_index do |name_info, index|
        name, org_name = resolve_column_names(name_info, index, original_names)

        # 型の決定: 1. name_info (Hash) からの指定, 2. 実際のデータから判定
        type = if name_info.is_a?(Hash) && name_info[:type]
                 name_info[:type]
               else
                 sample_val = rows.lazy.map { |row| row[index] }.find { |v| !v.nil? }
                 determine_column_type(sample_val)
               end

        send_packet(client, seq & 0xFF, pack_column_definition(type, name, org_name))
        seq += 1
      end
      seq
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
