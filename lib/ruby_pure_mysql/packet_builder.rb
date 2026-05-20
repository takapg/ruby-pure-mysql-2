# frozen_string_literal: true

require_relative 'constants'

module RubyPureMysql
  # MySQLプロトコルのパケット構築を支援するモジュール
  module PacketBuilder
    include Constants

    def lenenc_str(str)
      lenenc_prefix(str.bytesize) + str
    end

    def lenenc_prefix(len)
      if len < LENENC_INT_LIMIT_1
        [len].pack('C')
      elsif len <= LENENC_INT_LIMIT_2
        [LENENC_INT_2_BYTES, len].pack('Cv')
      elsif len <= LENENC_INT_LIMIT_3
        [LENENC_INT_3_BYTES, len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF].pack('CCCC')
      else
        [LENENC_INT_8_BYTES, len].pack('CQ<')
      end
    end

    def lenenc_int(number)
      if number < 251
        [number].pack('C')
      elsif number < 65_536
        [0xFC, number].pack('Cv')
      elsif number < 16_777_216
        [0xFD, number & 0xFF, (number >> 8) & 0xFF, (number >> 16) & 0xFF].pack('C3')
      else
        [0xFE, number].pack('CQ<')
      end
    end

    def build_handshake_payload
      [build_handshake_header, build_handshake_auth_data].join
    end

    def build_handshake_header
      [[PROTOCOL_VERSION_10].pack('C'), SERVER_VERSION, [1].pack('L<'), '12345678', [0x00].pack('C')].join
    end

    def build_handshake_auth_data
      [
        [0xF7FF, DEFAULT_CHARSET, SERVER_STATUS_AUTOCOMMIT, 0x8007, 0x15].pack('S< C S< S< C'),
        "\0" * 10,
        '1234567890123',
        AUTH_PLUGIN_NAME
      ].join
    end

    def build_column_definition_payload(name)
      [
        lenenc_str('def'), lenenc_str(''), lenenc_str(''),
        lenenc_str(name), lenenc_str(name), lenenc_str(name)
      ].join + build_column_definition_details
    end

    def build_column_definition_details
      [
        [0x0C].pack('C'), [DEFAULT_CHARSET].pack('S<'), [10].pack('L<'),
        [0x08].pack('C'), [0x0000].pack('S<'), [0].pack('C'), [0, 0].pack('C2')
      ].join
    end
  end
end
