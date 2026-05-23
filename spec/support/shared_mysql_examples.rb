# frozen_string_literal: true

RSpec.shared_examples 'a MySQL-compatible server' do |port|
  let(:client) do
    Mysql2::Client.new(
      host: '127.0.0.1',
      username: 'root',
      port: port,
      connect_timeout: 2,
      database: 'mysql'
    )
  end

  after do
    client&.close
  rescue StandardError
    # 接続が既に切れている場合のクローズエラーを無視
  end

  it 'filters rows by AND condition' do
    results = client.query("SELECT * FROM users WHERE id > 1 AND name LIKE 'b%';")
    expect(results.count).to eq(1)
    expect(results.first.values).to eq([2, 'bob'])
  end
end
