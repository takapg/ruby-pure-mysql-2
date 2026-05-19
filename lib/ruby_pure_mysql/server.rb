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
          handle_client(client)
        rescue Errno::E