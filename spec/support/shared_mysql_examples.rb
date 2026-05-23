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

  before do
    # テストに必要なテーブルとデータをセットアップ
    client.query("CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));")
    client.query("DELETE FROM users;")
    client.query("INSERT INTO users VALUES (1, 'alice');")
    client.query("INSERT INTO users VALUES (2, 'bob');")
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
