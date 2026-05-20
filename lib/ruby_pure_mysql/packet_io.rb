# frozen_string_literal: true

module RubyPureMysql
  # MySQLプロトコルのパケット読み書きを支援するモジュール
  module PacketIO
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
  end
end
