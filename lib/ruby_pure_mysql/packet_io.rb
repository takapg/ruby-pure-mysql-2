# frozen_string_literal: true

module RubyPureMysql
  # MySQLプロトコルのパケット読み書きを支援するモジュール
  module PacketIO
    def send_packet(client, seq, payload)
      len = payload.bytesize
      # MySQL packet header (4 bytes):
      #   - 3 bytes: payload length (little-endian)
      #   - 1 byte: sequence number
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF].pack('C3')
      packet = header + [seq].pack('C') + payload

      RubyPureMysql.logger.debug "Sending packet [seq: #{seq}, len: #{len}]"
      client.write(packet)
    end

    def read_packet(client)
      header = read_exactly(client, 4)
      return nil unless header

      len, seq = parse_packet_header(header)
      payload = read_exactly(client, len)
      return nil unless payload

      RubyPureMysql.logger.debug "Received packet [seq: #{seq}, len: #{len}]"
      [seq, payload]
    end

    def read_exactly(client, len)
      buf = String.new(encoding: 'ASCII-8BIT', capacity: len)
      while buf.bytesize < len
        chunk = client.read(len - buf.bytesize)
        return nil if chunk.nil? || chunk.empty?

        buf << chunk
      end
      buf
    end

    def parse_packet_header(header)
      # MySQL packet header: 3-byte length (little-endian) + 1-byte sequence
      combined = header.unpack1('V')
      len = combined & 0xFFFFFF
      seq = (combined >> 24) & 0xFF
      [len, seq]
    end
  end
end
