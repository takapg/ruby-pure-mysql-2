# frozen_string_literal: true

require 'logger'
require_relative 'ruby_pure_mysql/server'

# Ruby による純粋な MySQL の再実装を提供します。
module RubyPureMysql
  # ロガーの設定
  @logger_mutex = Mutex.new

  def self.logger
    return @logger if @logger

    @logger_mutex.synchronize do
      @logger ||= Logger.new($stdout).tap do |log|
        level_name = ENV.fetch('LOG_LEVEL', 'DEBUG').upcase
        log.level = Logger.const_defined?(level_name) ? Logger.const_get(level_name) : Logger::DEBUG
        log.formatter = proc do |severity, datetime, _progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
        end
      end
    end
  end

  def self.start(host: '127.0.0.1', port: 3307)
    logger.info "Starting MySQL-compatible server on #{host}:#{port}..."
    Server.new(host:, port:).run
  end
end
