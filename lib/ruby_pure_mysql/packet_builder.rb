# frozen_string_literal: true

module RubyPureMysql
  module PacketBuilder
    def lenenc_str(str)
      [str.bytesize].pack('C') + str
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

    def build_column_definition_payload
      [
        lenenc_str('def'), lenenc_str(''), lenenc_str(''),
        lenenc_str('1'), lenenc_str('1'), lenenc_str('1')
      ].join + build_column_definition_details
    end

    def build_column_definition_details
      [
        [0x0C].pack('C'), [33].pack('S<'), [10].pack('L<'),
        [0x08].pack('C'), [0x0000].pack('S<'), [0].pack('C'), [0, 0].pack('C2')
      ].join
    end
  end
end
