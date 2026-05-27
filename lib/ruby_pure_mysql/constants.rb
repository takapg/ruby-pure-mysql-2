# frozen_string_literal: true

module RubyPureMysql
  module Constants
    # Packet Headers
    OK_PACKET_HEADER = 0x00
    EOF_PACKET_HEADER = 0xFE

    # Command Types
    COM_QUERY = 0x03

    # Status Flags
    SERVER_STATUS_AUTOCOMMIT = 0x0002

    # Length Encoded Integer Constants
    LENENC_INT_LIMIT_1 = 251
    LENENC_INT_2_BYTES = 0xFC
    LENENC_INT_LIMIT_2 = 0xFFFF
    LENENC_INT_3_BYTES = 0xFD
    LENENC_INT_LIMIT_3 = 0xFFFFFF
    LENENC_INT_8_BYTES = 0xFE
    NULL_COLUMN_VALUE = 0xFB

    # MySQL Type Codes
    MYSQL_TYPE_LONGLONG = 0x08
    MYSQL_TYPE_DOUBLE = 0x0B
    MYSQL_TYPE_VAR_STRING = 0xFD

    # Handshake
    PROTOCOL_VERSION_10 = 10
    SERVER_VERSION = "Hi-MySQL-8.0\0"
    DEFAULT_CHARSET = 33
    AUTH_PLUGIN_NAME = "mysql_native_password\0"
  end
end
