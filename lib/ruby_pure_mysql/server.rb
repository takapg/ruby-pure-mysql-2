# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  # TODO: class についての説明を更新してください。
  class Server
    def initialize(host: '127.0.0.1', port: 3307)
      @server = TCPServer.new(host, port)
    end

    def run
      # TODO: 実装してください。
    end
  end
end
