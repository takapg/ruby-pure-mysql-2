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

  it 'executes SELECT 1; and returns 1' do
    results = client.query('SELECT 1;')
    expect(results.first.values.first).to eq(1)
  end

  it 'executes SELECT 2; and returns 2' do
    results = client.query('SELECT 2;')
    expect(results.first.values.first).to eq(2)
  end

  describe 'SQL Parsing & Calculation' do
    it 'can calculate basic arithmetic (SELECT 1 + 1;)' do
      results = client.query('SELECT 1 + 1;')
      expect(results.first.values.first).to eq(2)
    end

    it 'handles queries with extra spaces and semicolons' do
      results = client.query('  SELECT   42  ;  ')
      expect(results.first.values.first).to eq(42)
    end

    it 'handles case-insensitive SELECT' do
      results = client.query('select 100;')
      expect(results.first.values.first).to eq(100)
    end

    it 'returns an error for unsupported syntax' do
      expect do
        client.query('INVALID SQL')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'Multi-column support' do
    it 'executes SELECT 1, 2; and returns two columns with correct values' do
      results = client.query('SELECT 1, 2;')
      expect(results.fields.size).to eq(2)
      expect(results.first.values).to eq([1, 2])
    end
  end

  describe 'Multi-row support' do
    it 'executes a query that returns multiple rows (e.g., UNION)' do
      results = client.query('SELECT 1 UNION SELECT 2;')
      expect(results.count).to eq(2)
      rows = results.to_a
      expect(rows[0].values).to eq([1])
      expect(rows[1].values).to eq([2])
    end
  end

  describe 'Data Type support' do
    it 'returns a string value for SELECT "hello";' do
      results = client.query('SELECT "hello";')
      expect(results.first.values.first).to eq('hello')
    end

    it 'returns nil for SELECT NULL;' do
      results = client.query('SELECT NULL;')
      expect(results.first.values.first).to be_nil
    end
  end

  # describe 'Empty result set' do
  #   it 'executes a query that returns no rows (e.g., SELECT 1 WHERE 1=0)' do
  #     results = client.query('SELECT 1 WHERE 1=0;')
  #     expect(results.count).to eq(0)
  #   end
  # end

  describe 'System Variables support' do
    it 'returns a value for SELECT @@version_comment;' do
      results = client.query('SELECT @@version_comment;')
      expect(results.first.values.first).to be_a(String)
      expect(results.fields.first).to eq('@@version_comment')
    end
  end

  describe 'Schema Management (Storage Engine)' do
    it 'executes CREATE TABLE and returns an OK packet' do
      expect do
        client.query('CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));')
      end.not_to raise_error
    end

    it 'returns an error when creating a table that already exists' do
      client.query('CREATE TABLE IF NOT EXISTS test_table (id INT);')
      expect do
        client.query('CREATE TABLE test_table (id INT);')
      end.to raise_error(Mysql2::Error)
    end

    it 'executes SHOW TABLES and returns table names' do
      client.query('CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));')
      results = client.query('SHOW TABLES;')
      expect(results.map(&:values).flatten).to include('users')
    end

    it 'executes DESCRIBE and returns column definitions' do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      results = client.query('DESCRIBE users;')
      
      fields = results.map { |row| row['Field'] }
      expect(fields).to include('id', 'name')
    end
  end

  describe 'Data Manipulation (Storage Engine)' do
    before do
      # テーブルが既に存在する場合に備えてDROP TABLEを実行
      begin
        client.query('DROP TABLE IF EXISTS users;')
      rescue StandardError
        # 無視
      end
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
    end

    it 'inserts and selects data correctly' do
      # 1. データの挿入
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")

      # 2. データの取得
      results = client.query('SELECT * FROM users;')

      expect(results.count).to eq(2)
      rows = results.to_a
      expect(rows[0].values).to eq([1, 'alice'])
      expect(rows[1].values).to eq([2, 'bob'])
    end
  end

  describe 'Query Filtering (WHERE clause)' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
    end

    it 'filters rows by integer column' do
      results = client.query('SELECT * FROM users WHERE id = 1;')
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'filters rows by string column' do
      results = client.query("SELECT name FROM users WHERE name = 'bob';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq(['bob'])
    end

    it 'returns empty result set when no rows match' do
      results = client.query('SELECT * FROM users WHERE id = 999;')
      expect(results.count).to eq(0)
    end
  end

  describe 'Data Modification (UPDATE & DELETE)' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
    end

    it 'updates existing data matching a WHERE clause' do
      client.query("UPDATE users SET name = 'charlie' WHERE id = 1;")
      results = client.query('SELECT name FROM users WHERE id = 1;')
      expect(results.first.values.first).to eq('charlie')
    end

    it 'deletes specific rows matching a WHERE clause' do
      client.query('DELETE FROM users WHERE id = 2;')
      results = client.query('SELECT * FROM users;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end
  end
end
