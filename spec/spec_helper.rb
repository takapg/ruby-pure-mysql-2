# frozen_string_literal: true

require 'bundler/setup'
require 'mysql2'
require 'ruby_pure_mysql'

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation

  # テスト開始前に 3307 ポートで自作サーバーを起動
  config.before(:suite) do
    Thread.new do
      RubyPureMysql.start(host: '127.0.0.1', port: 3307)
    rescue Errno::EADDRINUSE
      # 既に起動している場合は無視
    end

    # サーバーが起動するまで接続をリトライ
    timeout = 10 # seconds
    start_time = Time.now
    connected = false

    until connected || (Time.now - start_time) > timeout
      begin
        socket = TCPSocket.new('localhost', 3307)
        # サーバーからハンドシェイクパケットの最初の1バイトが届くか確認
        connected = true if socket.read(1)
        socket.close
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        sleep 0.1
      end
    end

    raise 'Server failed to start within timeout' unless connected
  end
end
