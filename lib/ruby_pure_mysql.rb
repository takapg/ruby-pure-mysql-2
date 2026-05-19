# frozen_string_literal: true

require_relative 'ruby_pure_mysql/server'

# Ruby による純粋な MySQL の再実装を提供します。
module RubyPureMysql
  def self.start(host: '127.0.0.1', port: 3307)
    puts "Starting MySQL-compatible server on #{host}:#{port}..."
    Server.new(host:, port:).run
  end
end
