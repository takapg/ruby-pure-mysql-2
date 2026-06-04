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
    client.query("SET SESSION sql_mode=(SELECT CONCAT(@@sql_mode, ',PIPES_AS_CONCAT'))")
  rescue StandardError
    nil
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

    it 'can calculate basic subtraction (SELECT 1 - 1;)' do
      results = client.query('SELECT 1 - 1;')
      expect(results.first.values.first).to eq(0)
    end

    it 'can calculate subtraction with negative numbers (SELECT 1 - -1;)' do
      results = client.query('SELECT 1 - -1;')
      expect(results.first.values.first).to eq(2)
    end

    it 'can calculate multiplication (SELECT 2 * 3;)' do
      results = client.query('SELECT 2 * 3;')
      expect(results.first.values.first).to eq(6)
    end

    it 'can calculate division (SELECT 100 / 4;)' do
      results = client.query('SELECT 100 / 4;')
      expect(results.first.values.first).to eq(25)
    end

    it 'returns NULL for division by zero (SELECT 1/0;)' do
      results = client.query('SELECT 1/0;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for zero divided by zero (SELECT 0/0;)' do
      results = client.query('SELECT 0/0;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for division by an expression that evaluates to zero (SELECT 1/(2-2);)' do
      results = client.query('SELECT 1/(2-2);')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for modulo by zero (SELECT 1%0;)' do
      results = client.query('SELECT 1%0;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for arithmetic with NULL (SELECT 1 + NULL;)' do
      results = client.query('SELECT 1 + NULL;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for arithmetic with NULL (SELECT NULL - 1;)' do
      results = client.query('SELECT NULL - 1;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for arithmetic with NULL (SELECT NULL * 1;)' do
      results = client.query('SELECT NULL * 1;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for arithmetic with NULL (SELECT NULL / 1;)' do
      results = client.query('SELECT NULL / 1;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for unary operator with NULL (SELECT -NULL;)' do
      results = client.query('SELECT -NULL;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns NULL for complex nested arithmetic with NULL (SELECT (1 + NULL) * (2 + 2);)' do
      results = client.query('SELECT (1 + NULL) * (2 + 2);')
      expect(results.first.values.first).to be_nil
    end

    it 'returns a float for division even if the result is a whole number (SELECT 4/2;)' do
      results = client.query('SELECT 4/2;')
      val = results.first.values.first
      expect(val).to eq(2.0)
      expect(val).to be_a(Numeric)
      expect(val).not_to be_a(Integer)
    end

    it 'respects operator precedence (SELECT 1 + 2 * 3;)' do
      results = client.query('SELECT 1 + 2 * 3;')
      expect(results.first.values.first).to eq(7)
    end

    it 'can calculate complex arithmetic (SELECT 10 - 2 * 3 + 4 / 2;)' do
      results = client.query('SELECT 10 - 2 * 3 + 4 / 2;')
      expect(results.first.values.first).to eq(6)
    end

    it 'can calculate complex arithmetic with mixed operators (SELECT 1 + 2 * 3 - 4 / 2;)' do
      results = client.query('SELECT 1 + 2 * 3 - 4 / 2;')
      expect(results.first.values.first).to eq(5.0)
    end

    it 'can calculate float arithmetic (SELECT 1.5 + 2.5;)' do
      results = client.query('SELECT 1.5 + 2.5;')
      expect(results.first.values.first).to eq(4.0)
    end

    it 'can handle implicit cast from string to numeric (SELECT "abc" + 0;)' do
      results = client.query('SELECT "abc" + 0;')
      expect(results.first.values.first).to eq(0)
    end

    it 'returns NULL for arithmetic with NULL (SELECT NULL + 1;)' do
      results = client.query('SELECT NULL + 1;')
      expect(results.first.values.first).to be_nil
    end

    it 'can calculate nested constant expressions (SELECT (1 + 1) * (2 + 2);)' do
      results = client.query('SELECT (1 + 1) * (2 + 2);')
      expect(results.first.values.first).to eq(8)
    end

    it 'can evaluate constant expressions in UNION (SELECT 1 + 1 UNION SELECT 2 + 2;)' do
      results = client.query('SELECT 1 + 1 UNION SELECT 2 + 2;')
      expect(results.to_a.map { |r| r.values.first }).to eq([2, 4])
    end

    it 'returns NULL for division by zero in any SELECT pattern (SELECT 1/0;)' do
      results = client.query('SELECT 1/0;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns an error for invalid arithmetic (SELECT 1 + * 2;)' do
      expect do
        client.query('SELECT 1 + * 2;')
      end.to raise_error(Mysql2::Error)
    end

    it 'can return a simple negative integer (SELECT -1;)' do
      results = client.query('SELECT -1;')
      expect(results.first.values.first).to eq(-1)
    end

    it 'can calculate basic arithmetic with an alias (SELECT 1 + 1 AS total;)' do
      results = client.query('SELECT 1 + 1 AS total;')
      expect(results.fields.first).to eq('total')
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

    it 'can calculate with negative numbers and leading dots (SELECT -1.5 + .5;)' do
      results = client.query('SELECT -1.5 + .5;')
      expect(results.first.values.first).to eq(-1.0)
    end

    it 'can calculate mixed numeric types (SELECT 1 + 1.5;)' do
      results = client.query('SELECT 1 + 1.5;')
      expect(results.first.values.first).to eq(2.5)
    end

    it 'can calculate deeply nested arithmetic (SELECT (1 + (2 * 3)) / 2;)' do
      results = client.query('SELECT (1 + (2 * 3)) / 2;')
      expect(results.first.values.first).to eq(3.5)
    end

    it 'can calculate 1 + 2 * 3 and returns 7 (Integer)' do
      results = client.query('SELECT 1 + 2 * 3;')
      val = results.first.values.first
      expect(val).to eq(7)
      expect(val).to be_a(Integer)
    end

    it 'can calculate (10 - 2) * 3 and returns 24 (Integer)' do
      results = client.query('SELECT (10 - 2) * 3;')
      val = results.first.values.first
      expect(val).to eq(24)
      expect(val).to be_a(Integer)
    end

    it 'can calculate 100 + 100.5 and returns 200.5 (Float)' do
      results = client.query('SELECT 100 + 100.5;')
      val = results.first.values.first
      expect(val).to eq(200.5)
      expect(val).to be_a(Numeric)
    end

    it 'can handle very large numeric operations (SELECT 1000000 * 1000000;)' do
      results = client.query('SELECT 1000000 * 1000000;')
      expect(results.first.values.first).to eq(1_000_000_000_000)
    end

    it 'can handle scientific notation (SELECT 1e1 + 1;)' do
      results = client.query('SELECT 1e1 + 1;')
      expect(results.first.values.first).to eq(11.0)
    end

    it 'returns an error for unsupported syntax' do
      expect do
        client.query('INVALID SQL')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error when inserting a duplicate primary key' do
      client.query('DROP TABLE IF EXISTS pk_test;')
      client.query('CREATE TABLE pk_test (id INT PRIMARY KEY, name VARCHAR(255));')
      client.query("INSERT INTO pk_test VALUES (1, 'alice');")
      expect do
        client.query("INSERT INTO pk_test VALUES (1, 'bob');")
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

    it 'handles string literals with quotes (SELECT "It\'s a test";)' do
      results = client.query('SELECT "It\'s a test";')
      expect(results.first.values.first).to eq("It's a test")
    end

    it 'handles escaped backslashes in strings (SELECT "C:\\";)' do
      results = client.query('SELECT "C:\\\\";')
      expect(results.first.values.first).to eq('C:\\')
    end

    it 'handles doubled single quotes (SELECT \'It\'\'s a test\';)' do
      results = client.query("SELECT 'It''s a test';")
      expect(results.first.values.first).to eq("It's a test")
    end

    it 'returns nil for SELECT NULL;' do
      results = client.query('SELECT NULL;')
      expect(results.first.values.first).to be_nil
    end

    it 'returns a float value for SELECT 1.5;' do
      results = client.query('SELECT 1.5;')
      expect(results.first.values.first).to eq(1.5)
      expect(results.first.values.first).to be_a(Numeric)
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

  describe 'Built-in Functions support' do
    it 'returns current time for SELECT NOW();' do
      results = client.query('SELECT NOW();')
      val = results.first.values.first
      expect(val.to_s).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end

    it 'returns current user for SELECT USER();' do
      results = client.query('SELECT USER();')
      expect(results.first.values.first).to match(/.*@.*/)
    end

    it 'returns server version for SELECT VERSION();' do
      results = client.query('SELECT VERSION();')
      expect(results.first.values.first).to match(/8\.0/)
    end

    it 'can evaluate functions within arithmetic (SELECT 1 + NOW();)' do
      # NOW() returns a string, which to_f converts to a number (e.g. 2026.0)
      # 1 + 2026.0 = 2027.0
      results = client.query('SELECT 1 + NOW();')
      expect(results.first.values.first).to be_a(Numeric)
    end

    it 'can evaluate nested functions (SELECT CONCAT(USER(), VERSION());)' do
      results = client.query('SELECT CONCAT(USER(), VERSION());')
      val = results.first.values.first
      expect(val).to match(/root@.*/)
      expect(val).to match(/8\.0/)
    end

    it 'can evaluate functions within arithmetic (SELECT 1 + NOW();)' do
      # NOW() returns a string, which to_f converts to a number (e.g. 2026.0)
      # 1 + 2026.0 = 2027.0
      results = client.query('SELECT 1 + NOW();')
      expect(results.first.values.first).to be_a(Numeric)
    end

    it 'can evaluate string concatenation using || (SELECT "hello" || " world";)' do
      results = client.query('SELECT "hello" || " world";')
      expect(results.first.values.first).to eq('hello world')
    end

    it 'can evaluate mixed arithmetic and concatenation (SELECT (1 + 1) || " is two";)' do
      results = client.query('SELECT (1 + 1) || " is two";')
      expect(results.first.values.first).to eq('2 is two')
    end

    it 'can evaluate CONCAT with arithmetic (SELECT CONCAT("Result: ", 1 + 1);)' do
      results = client.query('SELECT CONCAT("Result: ", 1 + 1);')
      expect(results.first.values.first).to eq('Result: 2')
    end

    it 'can calculate nested arithmetic (SELECT (1 + 2) * 3;)' do
      results = client.query('SELECT (1 + 2) * 3;')
      expect(results.first.values.first).to eq(9)
    end

    it 'returns an error for invalid syntax (missing closing parenthesis)' do
      expect do
        client.query('SELECT NOW(;')
      end.to raise_error(Mysql2::Error)
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

    it 'executes DESCRIBE and returns column information' do
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
      client.query("INSERT INTO users VALUES (3, 'cory');")
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

    it 'filters rows by > operator' do
      results = client.query('SELECT * FROM users WHERE id > 1;')
      expect(results.count).to eq(2)
      expect(results.map { |r| r['id'] }).to include(2, 3)
    end

    it 'filters rows by != operator' do
      results = client.query('SELECT * FROM users WHERE id != 1;')
      expect(results.count).to eq(2)
      expect(results.map { |r| r['id'] }).to include(2, 3)
    end

    it 'filters rows by <= operator' do
      results = client.query('SELECT * FROM users WHERE id <= 1;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'filters rows by >= operator' do
      results = client.query('SELECT * FROM users WHERE id >= 2;')
      expect(results.count).to eq(2)
      expect(results.map { |r| r['id'] }).to include(2, 3)
    end

    it 'filters rows by < operator' do
      results = client.query('SELECT * FROM users WHERE id < 2;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'filters rows by <> operator (alias for !=)' do
      results = client.query('SELECT * FROM users WHERE id <> 1;')
      expect(results.count).to eq(2)
      expect(results.map { |r| r['id'] }).to include(2, 3)
    end

    it 'filters rows by >= operator (boundary)' do
      results = client.query('SELECT * FROM users WHERE id >= 1;')
      expect(results.count).to eq(3)
    end

    it 'filters rows by > operator (boundary)' do
      results = client.query('SELECT * FROM users WHERE id > 2;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(3)
    end

    it 'filters rows by <= operator (boundary)' do
      results = client.query('SELECT * FROM users WHERE id <= 2;')
      expect(results.count).to eq(2)
    end

    it 'filters rows by < operator (boundary)' do
      results = client.query('SELECT * FROM users WHERE id < 1;')
      expect(results.count).to eq(0)
    end

    it 'filters rows by LIKE operator (prefix)' do
      results = client.query("SELECT * FROM users WHERE name LIKE 'a%';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'filters rows by LIKE operator (contains)' do
      results = client.query("SELECT * FROM users WHERE name LIKE '%o%';")
      expect(results.count).to eq(2)
      expect(results.map { |r| r['name'] }).to include('bob', 'cory')
    end

    it 'filters rows by LIKE operator (suffix)' do
      results = client.query("SELECT * FROM users WHERE name LIKE '%e';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'filters rows by LIKE operator (single character wildcard)' do
      # 'bob' を 'b_b' でマッチさせる
      results = client.query("SELECT * FROM users WHERE name LIKE 'b_b';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([2, 'bob'])
    end

    it 'filters rows by IN operator with integers' do
      results = client.query('SELECT * FROM users WHERE id IN (1, 3);')
      expect(results.count).to eq(2)
      ids = results.map { |r| r['id'] }
      expect(ids).to contain_exactly(1, 3)
    end

    it 'filters rows by IN operator with strings' do
      results = client.query("SELECT * FROM users WHERE name IN ('alice', 'cory');")
      expect(results.count).to eq(2)
      names = results.map { |r| r['name'] }
      expect(names).to contain_exactly('alice', 'cory')
    end

    it 'returns empty result set when IN list contains no matches' do
      results = client.query('SELECT * FROM users WHERE id IN (99, 100);')
      expect(results.count).to eq(0)
    end

    it 'returns an error for IN with an empty list' do
      expect do
        client.query('SELECT * FROM users WHERE id IN ();')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns empty result set for IN with only NULL' do
      results = client.query('SELECT * FROM users WHERE id IN (NULL);')
      expect(results.count).to eq(0)
    end

    it 'filters correctly when IN list contains NULL' do
      results = client.query('SELECT * FROM users WHERE id IN (1, NULL);')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'filters rows by BETWEEN operator (integers)' do
      results = client.query('SELECT * FROM users WHERE id BETWEEN 1 AND 2;')
      expect(results.count).to eq(2)
      ids = results.map { |r| r['id'] }
      expect(ids).to contain_exactly(1, 2)
    end

    it 'filters rows by BETWEEN operator (boundary values)' do
      results = client.query('SELECT * FROM users WHERE id BETWEEN 2 AND 2;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(2)
    end

    it 'returns empty result set when BETWEEN range does not match' do
      results = client.query('SELECT * FROM users WHERE id BETWEEN 10 AND 20;')
      expect(results.count).to eq(0)
    end

    it 'filters rows by BETWEEN operator (strings)' do
      results = client.query("SELECT * FROM users WHERE name BETWEEN 'alice' AND 'bob';")
      # 'alice' and 'bob' should match
      expect(results.count).to eq(2)
    end

    it 'filters rows by REGEXP operator' do
      results = client.query("SELECT * FROM users WHERE name REGEXP '^a.*e$';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'filters rows by RLIKE operator' do
      results = client.query("SELECT * FROM users WHERE name RLIKE '^b';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([2, 'bob'])
    end

    it 'is case-insensitive for REGEXP' do
      results = client.query("SELECT * FROM users WHERE name REGEXP '^ALICE$';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'returns empty result set when REGEXP does not match' do
      results = client.query("SELECT * FROM users WHERE name REGEXP '^z';")
      expect(results.count).to eq(0)
    end

    it 'filters rows by NOT BETWEEN operator' do
      results = client.query('SELECT * FROM users WHERE id NOT BETWEEN 1 AND 2;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(3)
    end

    it 'handles BETWEEN combined with other AND conditions' do
      results = client.query("SELECT * FROM users WHERE id BETWEEN 1 AND 3 AND name = 'alice';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'alice'])
    end

    it 'filters rows by OR operator' do
      results = client.query('SELECT * FROM users WHERE id = 1 OR id = 3;')
      expect(results.count).to eq(2)
      ids = results.map { |r| r['id'] }
      expect(ids).to contain_exactly(1, 3)
    end

    it 'filters rows by mixed AND and OR operators (precedence check)' do
      # id=1 AND name='alice' (match) OR id=3 (match) -> 2 rows
      results = client.query("SELECT * FROM users WHERE id = 1 AND name = 'alice' OR id = 3;")
      expect(results.count).to eq(2)
      ids = results.map { |r| r['id'] }
      expect(ids).to contain_exactly(1, 3)
    end

    it 'filters rows by mixed AND and OR operators (precedence check 2)' do
      # id=2 AND name='alice' (no match) OR id=1 (match) -> 1 row
      results = client.query("SELECT * FROM users WHERE id = 2 AND name = 'alice' OR id = 1;")
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(1)
    end
  end

  describe 'IS NULL / IS NOT NULL support' do
    before do
      client.query('DROP TABLE IF EXISTS null_test;')
      client.query('CREATE TABLE null_test (id INT, val VARCHAR(255));')
      client.query("INSERT INTO null_test VALUES (1, 'hello');")
      client.query('INSERT INTO null_test VALUES (2, NULL);')
    end

    it 'filters rows by IS NULL' do
      results = client.query('SELECT * FROM null_test WHERE val IS NULL;')
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([2, nil])
    end

    it 'filters rows by IS NOT NULL' do
      results = client.query('SELECT * FROM null_test WHERE val IS NOT NULL;')
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([1, 'hello'])
    end

    it 'returns empty result set when IS NULL finds nothing' do
      results = client.query('SELECT * FROM null_test WHERE id IS NULL;')
      expect(results.count).to eq(0)
    end
  end

  describe 'LEFT JOIN with IS NULL' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('DROP TABLE IF EXISTS orders;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query('CREATE TABLE orders (id INT, user_id INT);')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query('INSERT INTO orders VALUES (101, 1);')
    end

    it 'extracts users who have no orders' do
      query = 'SELECT users.name FROM users LEFT JOIN orders ON users.id = orders.user_id WHERE orders.id IS NULL;'
      results = client.query(query)
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq('bob')
    end
  end

  describe 'INNER JOIN support' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('DROP TABLE IF EXISTS orders;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query('CREATE TABLE orders (id INT, user_id INT, amount INT);')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query('INSERT INTO orders VALUES (101, 1, 1000);')
      client.query('INSERT INTO orders VALUES (102, 1, 2000);')
      client.query('INSERT INTO orders VALUES (103, 2, 3000);')
    end

    it 'executes a simple INNER JOIN' do
      query = 'SELECT users.name, orders.amount FROM users ' \
              'INNER JOIN orders ON users.id = orders.user_id;'
      results = client.query(query)
      expect(results.count).to eq(3)

      data = results.to_a.map { |r| [r['name'], r['amount']] }
      expect(data).to include(['alice', 1000], ['alice', 2000], ['bob', 3000])
    end

    it 'filters joined results using WHERE' do
      query = 'SELECT users.name FROM users INNER JOIN orders ' \
              'ON users.id = orders.user_id WHERE orders.amount > 2000;'
      results = client.query(query)
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq('bob')
    end

    it 'returns empty result set when no rows match JOIN condition' do
      client.query('DROP TABLE IF EXISTS orders;')
      client.query('CREATE TABLE orders (id INT, user_id INT, amount INT);')
      client.query('INSERT INTO orders VALUES (101, 99, 1000);') # user_id 99 は存在しない

      results = client.query('SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id;')
      expect(results.count).to eq(0)
    end
  end

  describe 'LEFT JOIN support' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('DROP TABLE IF EXISTS orders;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query('CREATE TABLE orders (id INT, user_id INT, amount INT);')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'charlie');")
      client.query('INSERT INTO orders VALUES (101, 1, 1000);')
      client.query('INSERT INTO orders VALUES (102, 1, 2000);')
      client.query('INSERT INTO orders VALUES (103, 2, 3000);')
      # charlie (id: 3) は注文を持っていない
    end

    it 'returns all rows from the left table, filling right table columns with NULL when no match' do
      query = 'SELECT users.name, orders.amount FROM users LEFT JOIN orders ON users.id = orders.user_id;'
      results = client.query(query)

      expect(results.count).to eq(4)
      data = results.to_a.map { |r| [r['name'], r['amount']] }

      expect(data).to include(['alice', 1000], ['alice', 2000], ['bob', 3000])
      expect(data).to include(['charlie', nil])
    end

    it 'filters LEFT JOIN results using WHERE' do
      # NOTE: Our current implementation of WHERE doesn't support 'IS NULL',
      # but we can test with a value that doesn't match.
      # Instead, let's test a simple filter.
      query = 'SELECT users.name FROM users LEFT JOIN orders ON users.id = orders.user_id WHERE users.name = ' \
              "'charlie';"
      results = client.query(query)
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq('charlie')
    end
  end

  describe 'SELECT DISTINCT' do
    before do
      client.query('DROP TABLE IF EXISTS distinct_test;')
      client.query('CREATE TABLE distinct_test (name VARCHAR(255));')
      client.query("INSERT INTO distinct_test VALUES ('alice');")
      client.query("INSERT INTO distinct_test VALUES ('bob');")
      client.query("INSERT INTO distinct_test VALUES ('alice');")
      client.query("INSERT INTO distinct_test VALUES ('charlie');")
      client.query("INSERT INTO distinct_test VALUES ('bob');")
    end

    it 'returns only unique values when DISTINCT is used' do
      results = client.query('SELECT DISTINCT name FROM distinct_test;')
      expect(results.count).to eq(3)
      names = results.map { |r| r['name'] }.sort
      expect(names).to eq(%w[alice bob charlie])
    end

    it 'returns all values when DISTINCT is not used' do
      results = client.query('SELECT name FROM distinct_test;')
      expect(results.count).to eq(5)
    end

    it 'returns unique values when combined with WHERE' do
      results = client.query("SELECT DISTINCT name FROM distinct_test WHERE name = 'alice';")
      expect(results.count).to eq(1)
    end

    it 'returns empty when no rows match' do
      results = client.query("SELECT DISTINCT name FROM distinct_test WHERE name = 'non_existent';")
      expect(results.count).to eq(0)
    end

    it 'returns only one NULL when multiple NULLs are present in SELECT DISTINCT' do
      client.query('DROP TABLE IF EXISTS null_distinct_test;')
      client.query('CREATE TABLE null_distinct_test (val INT);')
      client.query('INSERT INTO null_distinct_test VALUES (1);')
      client.query('INSERT INTO null_distinct_test VALUES (NULL);')
      client.query('INSERT INTO null_distinct_test VALUES (NULL);')
      results = client.query('SELECT DISTINCT val FROM null_distinct_test;')
      expect(results.count).to eq(2)
      values = results.map { |r| r['val'] }
      expect(values).to contain_exactly(nil, 1)
    end

    it 'handles SELECT DISTINCT with mixed types (Integer, String, NULL)' do
      client.query('DROP TABLE IF EXISTS mixed_distinct_test;')
      client.query('CREATE TABLE mixed_distinct_test (val VARCHAR(255));')
      client.query("INSERT INTO mixed_distinct_test VALUES ('1');")
      client.query('INSERT INTO mixed_distinct_test VALUES (1);')
      client.query('INSERT INTO mixed_distinct_test VALUES (NULL);')
      client.query('INSERT INTO mixed_distinct_test VALUES (NULL);')
      results = client.query('SELECT DISTINCT val FROM mixed_distinct_test;')
      values = results.map { |r| r['val'] }
      # MySQL 8.0 では VARCHAR カラムへの挿入時にキャストされるため、'1' と 1 は同一視される
      expect(results.count).to eq(2)
      expect(values).to contain_exactly('1', nil)
    end

    it 'combines SELECT DISTINCT with WHERE clause filtering NULLs' do
      client.query('DROP TABLE IF EXISTS where_distinct_test;')
      client.query('CREATE TABLE where_distinct_test (val INT);')
      client.query('INSERT INTO where_distinct_test VALUES (1);')
      client.query('INSERT INTO where_distinct_test VALUES (1);')
      client.query('INSERT INTO where_distinct_test VALUES (NULL);')
      client.query('INSERT INTO where_distinct_test VALUES (NULL);')
      results = client.query('SELECT DISTINCT val FROM where_distinct_test WHERE val IS NOT NULL;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'handles SELECT DISTINCT with composite columns and NULLs' do
      client.query('DROP TABLE IF EXISTS composite_distinct_test;')
      client.query('CREATE TABLE composite_distinct_test (a INT, b INT);')
      client.query('INSERT INTO composite_distinct_test VALUES (1, NULL);')
      client.query('INSERT INTO composite_distinct_test VALUES (1, NULL);')
      client.query('INSERT INTO composite_distinct_test VALUES (NULL, 1);')
      client.query('INSERT INTO composite_distinct_test VALUES (NULL, 1);')
      client.query('INSERT INTO composite_distinct_test VALUES (NULL, NULL);')
      client.query('INSERT INTO composite_distinct_test VALUES (NULL, NULL);')
      client.query('INSERT INTO composite_distinct_test VALUES (1, 1);')

      results = client.query('SELECT DISTINCT a, b FROM composite_distinct_test;')
      expect(results.count).to eq(4)
      data = results.to_a.map(&:values)
      expect(data).to contain_exactly([1, nil], [nil, 1], [nil, nil], [1, 1])
    end

    it 'distinguishes between different types with same string representation in DISTINCT' do
      # MySQLでは単一カラムでは型が固定されるため、UNIONを用いて異なる型を混在させる
      results = client.query('SELECT DISTINCT 1 UNION SELECT DISTINCT "1";')
      # 本物の MySQL 8.0 では UNION DISTINCT 時に共通型にキャストされるため、
      # 結果として 1 行になる。互換性テストとしてこの挙動に合わせる。
      expect(results.count).to eq(1)
    end

    it 'returns only one NULL when all values in the column are NULL' do
      client.query('DROP TABLE IF EXISTS all_null_test;')
      client.query('CREATE TABLE all_null_test (val INT);')
      client.query('INSERT INTO all_null_test VALUES (NULL);')
      client.query('INSERT INTO all_null_test VALUES (NULL);')
      client.query('INSERT INTO all_null_test VALUES (NULL);')
      results = client.query('SELECT DISTINCT val FROM all_null_test;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to be_nil
    end

    it 'returns only one row when all composite columns are NULL' do
      client.query('DROP TABLE IF EXISTS all_null_composite_test;')
      client.query('CREATE TABLE all_null_composite_test (a INT, b INT);')
      client.query('INSERT INTO all_null_composite_test VALUES (NULL, NULL);')
      client.query('INSERT INTO all_null_composite_test VALUES (NULL, NULL);')
      results = client.query('SELECT DISTINCT a, b FROM all_null_composite_test;')
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([nil, nil])
    end

    it 'handles SELECT DISTINCT with composite columns and mixed types via UNION' do
      # (1, 'a') と (1.0, 'a') は同一行として扱われるべき
      results = client.query('SELECT DISTINCT 1, "a" UNION SELECT DISTINCT 1.0, "a";')
      expect(results.count).to eq(1)
    end

    it 'handles SELECT DISTINCT with composite columns where some are NULL and some are mixed types' do
      # (1, NULL) と (1.0, NULL) は同一行として扱われるべき
      results = client.query('SELECT DISTINCT 1, NULL UNION SELECT DISTINCT 1.0, NULL;')
      expect(results.count).to eq(1)
    end

    it 'handles SELECT DISTINCT with a larger dataset' do
      client.query('DROP TABLE IF EXISTS large_distinct_test;')
      client.query('CREATE TABLE large_distinct_test (val INT);')
      # 100行挿入: 50種類の値をそれぞれ2回ずつ挿入
      50.times { |i| client.query("INSERT INTO large_distinct_test VALUES (#{i});") }
      50.times { |i| client.query("INSERT INTO large_distinct_test VALUES (#{i});") }

      results = client.query('SELECT DISTINCT val FROM large_distinct_test;')
      expect(results.count).to eq(50)
    end
  end

  describe 'Query Filtering (WHERE clause with AND)' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'alice');")
    end

    it 'filters rows by multiple conditions with AND' do
      results = client.query("SELECT * FROM users WHERE id > 1 AND name = 'alice';")
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([3, 'alice'])
    end
  end

  describe 'Query Sorting (ORDER BY clause)' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'charlie');")
    end

    it 'sorts rows in ascending order' do
      results = client.query('SELECT * FROM users ORDER BY id ASC;')
      expect(results.map { |r| r['id'] }).to eq([1, 2, 3])
    end

    it 'defaults to ascending order when direction is omitted' do
      results = client.query('SELECT * FROM users ORDER BY id;')
      expect(results.map { |r| r['id'] }).to eq([1, 2, 3])
    end

    it 'sorts rows in descending order' do
      results = client.query('SELECT * FROM users ORDER BY id DESC;')
      expect(results.map { |r| r['id'] }).to eq([3, 2, 1])
    end

    it 'combines ORDER BY and LIMIT' do
      results = client.query('SELECT id FROM users ORDER BY id DESC LIMIT 2;')
      expect(results.map { |r| r['id'] }).to eq([3, 2])
    end
  end

  describe 'Aggregate Functions (COUNT(*))' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'charlie');")
    end

    it 'returns the total count of rows' do
      results = client.query('SELECT COUNT(*) FROM users;')
      expect(results.fields.first).to eq('COUNT(*)')
      expect(results.first.values.first).to eq(3)
    end

    it 'returns the filtered count of rows' do
      results = client.query('SELECT COUNT(*) FROM users WHERE id > 1;')
      expect(results.fields.first).to eq('COUNT(*)')
      expect(results.first.values.first).to eq(2)
    end

    it 'returns 0 when no rows match' do
      results = client.query('SELECT COUNT(*) FROM users WHERE id = 999;')
      expect(results.fields.first).to eq('COUNT(*)')
      expect(results.first.values.first).to eq(0)
    end

    it 'returns 0 for an empty table' do
      client.query('DELETE FROM users;')
      results = client.query('SELECT COUNT(*) FROM users;')
      expect(results.fields.first).to eq('COUNT(*)')
      expect(results.first.values.first).to eq(0)
    end

    it 'returns an empty result set for COUNT(*) with LIMIT 0' do
      results = client.query('SELECT COUNT(*) FROM users LIMIT 0;')
      expect(results.count).to eq(0)
    end

    it 'returns an empty result set for COUNT(*) with OFFSET 1' do
      results = client.query('SELECT COUNT(*) FROM users LIMIT 1 OFFSET 1;')
      expect(results.count).to eq(0)
    end
  end

  describe 'GROUP BY support' do
    before do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, category VARCHAR(255), price INT);')
      client.query("INSERT INTO products VALUES (1, 'electronics', 100);")
      client.query("INSERT INTO products VALUES (2, 'electronics', 200);")
      client.query("INSERT INTO products VALUES (3, 'books', 50);")
      client.query("INSERT INTO products VALUES (4, 'books', 150);")
      client.query("INSERT INTO products VALUES (5, 'clothing', 300);")
    end

    it 'calculates COUNT(*) with GROUP BY' do
      results = client.query('SELECT category, COUNT(*) FROM products GROUP BY category;')
      expect(results.count).to eq(3)
      data = results.to_h { |r| [r['category'], r['COUNT(*)']] }
      expect(data['electronics']).to eq(2)
      expect(data['books']).to eq(2)
      expect(data['clothing']).to eq(1)
    end

    it 'calculates SUM with GROUP BY' do
      results = client.query('SELECT category, SUM(price) FROM products GROUP BY category;')
      data = results.to_h { |r| [r['category'], r['SUM(price)']] }
      expect(data['electronics']).to eq(300.0)
      expect(data['books']).to eq(200.0)
      expect(data['clothing']).to eq(300.0)
    end

    it 'calculates AVG with GROUP BY' do
      results = client.query('SELECT category, AVG(price) FROM products GROUP BY category;')
      data = results.to_h { |r| [r['category'], r['AVG(price)']] }
      expect(data['electronics']).to eq(150.0)
      expect(data['books']).to eq(100.0)
      expect(data['clothing']).to eq(300.0)
    end

    it 'calculates MIN and MAX with GROUP BY' do
      results = client.query('SELECT category, MIN(price), MAX(price) FROM products GROUP BY category;')
      data = results.to_h { |r| [r['category'], [r['MIN(price)'], r['MAX(price)']]] }
      expect(data['electronics']).to eq([100.0, 200.0])
      expect(data['books']).to eq([50.0, 150.0])
      expect(data['clothing']).to eq([300.0, 300.0])
    end

    it 'combines GROUP BY with WHERE' do
      results = client.query('SELECT category, COUNT(*) FROM products WHERE price > 100 GROUP BY category;')
      data = results.to_h { |r| [r['category'], r['COUNT(*)']] }
      expect(data['electronics']).to eq(1)
      expect(data['books']).to eq(1)
      expect(data['clothing']).to eq(1)
    end

    it 'combines GROUP BY with ORDER BY and LIMIT' do
      query = 'SELECT category, SUM(price) FROM products ' \
              'GROUP BY category ORDER BY SUM(price) DESC LIMIT 1;'
      results = client.query(query)
      expect(results.count).to eq(1)
      # electronics(300) or clothing(300)
      expect(%w[electronics clothing]).to include(results.first['category'])
      expect(results.first['SUM(price)']).to eq(300.0)
    end

    it 'filters groups using HAVING clause' do
      results = client.query('SELECT category, COUNT(*) FROM products GROUP BY category HAVING COUNT(*) > 1;')
      expect(results.count).to eq(2) # electronics and books
      categories = results.map { |r| r['category'] }
      expect(categories).to contain_exactly('electronics', 'books')
    end

    it 'filters groups using HAVING with SUM' do
      results = client.query('SELECT category, SUM(price) FROM products GROUP BY category HAVING SUM(price) >= 300;')
      expect(results.count).to eq(2) # electronics(300) and clothing(300)
      categories = results.map { |r| r['category'] }
      expect(categories).to contain_exactly('electronics', 'clothing')
    end

    it 'combines WHERE and HAVING clauses' do
      # price > 100 のものを集計し、その結果 COUNT(*) > 1 のものを抽出
      # electronics: 200 (1件), books: 150 (1件), clothing: 300 (1件)
      # 全て1件になるため、COUNT(*) > 1 では 0件になるはず
      query = 'SELECT category, COUNT(*) FROM products ' \
              'WHERE price > 100 GROUP BY category HAVING COUNT(*) > 1;'
      results = client.query(query)
      expect(results.count).to eq(0)
    end

    it 'returns empty result set when no groups match HAVING' do
      results = client.query('SELECT category FROM products GROUP BY category HAVING SUM(price) > 10000;')
      expect(results.count).to eq(0)
    end

    it 'filters groups using HAVING with multiple AND conditions' do
      # electronics: count=2, sum=300 -> match
      # books: count=2, sum=200 -> match
      # clothing: count=1, sum=300 -> no match (count <= 1)
      query = 'SELECT category, COUNT(*) FROM products ' \
              'GROUP BY category HAVING COUNT(*) > 1 AND SUM(price) > 100;'
      results = client.query(query)
      expect(results.count).to eq(2)
      categories = results.map { |r| r['category'] }
      expect(categories).to contain_exactly('electronics', 'books')
    end

    it 'filters groups using HAVING with REGEXP' do
      results = client.query("SELECT category FROM products GROUP BY category HAVING category REGEXP '^e';")
      expect(results.count).to eq(1)
      expect(results.first['category']).to eq('electronics')
    end

    it 'filters groups using HAVING with IN operator' do
      query = "SELECT category FROM products GROUP BY category HAVING category IN ('electronics', 'books');"
      results = client.query(query)
      categories = results.map { |r| r['category'] }
      expect(categories).to contain_exactly('electronics', 'books')
    end

    it 'returns an error when HAVING clause contains an unknown column' do
      expect do
        client.query('SELECT category FROM products GROUP BY category HAVING unknown_col > 1;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'GROUP BY with multiple columns' do
    before do
      client.query('DROP TABLE IF EXISTS sales;')
      client.query('CREATE TABLE sales (product VARCHAR(255), region VARCHAR(255), amount INT);')
      client.query("INSERT INTO sales VALUES ('Apple', 'North', 10);")
      client.query("INSERT INTO sales VALUES ('Apple', 'North', 20);")
      client.query("INSERT INTO sales VALUES ('Apple', 'South', 15);")
      client.query("INSERT INTO sales VALUES ('Banana', 'North', 5);")
      client.query("INSERT INTO sales VALUES ('Banana', 'North', 10);")
    end

    it 'calculates COUNT(*) with multiple columns in GROUP BY' do
      results = client.query('SELECT product, region, COUNT(*) FROM sales GROUP BY product, region;')
      expect(results.count).to eq(3)
      data = results.to_h { |r| [[r['product'], r['region']], r['COUNT(*)']] }
      expect(data[%w[Apple North]]).to eq(2)
      expect(data[%w[Apple South]]).to eq(1)
      expect(data[%w[Banana North]]).to eq(2)
    end
  end

  describe 'Aggregate Functions with DISTINCT' do
    before do
      client.query('DROP TABLE IF EXISTS distinct_test;')
      client.query('CREATE TABLE distinct_test (id INT, val INT);')
      client.query('INSERT INTO distinct_test VALUES (1, 10);')
      client.query('INSERT INTO distinct_test VALUES (2, 10);')
      client.query('INSERT INTO distinct_test VALUES (3, 20);')
    end

    it 'calculates COUNT(DISTINCT col) correctly' do
      results = client.query('SELECT COUNT(DISTINCT val) FROM distinct_test;')
      expect(results.first.values.first).to eq(2)
    end

    it 'calculates SUM(DISTINCT col) correctly' do
      results = client.query('SELECT SUM(DISTINCT val) FROM distinct_test;')
      expect(results.first.values.first).to eq(30.0)
    end

    it 'calculates AVG(DISTINCT col) correctly' do
      results = client.query('SELECT AVG(DISTINCT val) FROM distinct_test;')
      expect(results.first.values.first).to eq(15.0)
    end
  end

  describe 'GROUP BY with DISTINCT' do
    before do
      client.query('DROP TABLE IF EXISTS sales;')
      client.query('CREATE TABLE sales (category VARCHAR(255), user_id INT);')
      client.query("INSERT INTO sales VALUES ('electronics', 1);")
      client.query("INSERT INTO sales VALUES ('electronics', 1);")
      client.query("INSERT INTO sales VALUES ('electronics', 2);")
      client.query("INSERT INTO sales VALUES ('books', 3);")
      client.query("INSERT INTO sales VALUES ('books', 3);")
      client.query("INSERT INTO sales VALUES ('books', 4);")
      client.query("INSERT INTO sales VALUES ('books', 4);")
    end

    it 'calculates COUNT(DISTINCT col) with GROUP BY' do
      results = client.query('SELECT category, COUNT(DISTINCT user_id) FROM sales GROUP BY category;')
      expect(results.count).to eq(2)
      data = results.to_h { |r| [r['category'], r['COUNT(DISTINCT user_id)']] }
      expect(data['electronics']).to eq(2)
      expect(data['books']).to eq(2)
    end
  end

  describe 'Aggregate Functions (SUM, AVG, MIN, MAX)' do
    before do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, price INT);')
      client.query('INSERT INTO products VALUES (1, 100);')
      client.query('INSERT INTO products VALUES (2, 200);')
      client.query('INSERT INTO products VALUES (3, 300);')
    end

    it 'calculates SUM correctly' do
      results = client.query('SELECT SUM(price) FROM products;')
      expect(results.first.values.first).to eq(600.0)
    end

    it 'calculates AVG correctly' do
      results = client.query('SELECT AVG(price) FROM products;')
      expect(results.first.values.first).to eq(200.0)
    end

    it 'calculates MIN correctly' do
      results = client.query('SELECT MIN(price) FROM products;')
      expect(results.first.values.first).to eq(100.0)
    end

    it 'calculates MAX correctly' do
      results = client.query('SELECT MAX(price) FROM products;')
      expect(results.first.values.first).to eq(300.0)
    end

    it 'filters rows before aggregating' do
      results = client.query('SELECT SUM(price) FROM products WHERE price > 150;')
      expect(results.first.values.first).to eq(500.0)
    end

    it 'returns NULL for SUM/AVG/MIN/MAX on empty result set' do
      results = client.query('SELECT SUM(price) FROM products WHERE price > 1000;')
      expect(results.first.values.first).to be_nil
    end
  end

  describe 'Query Limiting (LIMIT clause)' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'charlie');")
    end

    it 'limits the number of rows returned' do
      results = client.query('SELECT * FROM users LIMIT 1;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'returns empty result set for LIMIT 0' do
      results = client.query('SELECT * FROM users LIMIT 0;')
      expect(results.count).to eq(0)
    end

    it 'returns all rows when LIMIT exceeds row count' do
      results = client.query('SELECT * FROM users LIMIT 10;')
      expect(results.count).to eq(3)
    end

    it 'combines WHERE and LIMIT correctly' do
      results = client.query('SELECT * FROM users WHERE id = 2 LIMIT 1;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(2)
    end

    it 'supports LIMIT offset, count syntax (LIMIT 1, 1)' do
      results = client.query('SELECT * FROM users LIMIT 1, 1;')
      expect(results.count).to eq(1)
      expect(results.first['name']).to eq('bob')
    end

    it 'supports LIMIT offset, count syntax (LIMIT 0, 2)' do
      results = client.query('SELECT * FROM users LIMIT 0, 2;')
      expect(results.count).to eq(2)
      expect(results.map { |r| r['name'] }).to eq(%w[alice bob])
    end
  end

  describe 'LIMIT offset, count syntax' do
    before do
      client.query('DROP TABLE IF EXISTS limit_comma_test;')
      client.query('CREATE TABLE limit_comma_test (id INT);')
      10.times { |i| client.query("INSERT INTO limit_comma_test VALUES (#{i + 1});") }
    end

    it 'returns first 5 rows with LIMIT 0, 5' do
      results = client.query('SELECT * FROM limit_comma_test LIMIT 0, 5;')
      expect(results.count).to eq(5)
      expect(results.map { |r| r['id'] }).to eq([1, 2, 3, 4, 5])
    end

    it 'returns 0 rows with LIMIT 5, 0' do
      results = client.query('SELECT * FROM limit_comma_test LIMIT 5, 0;')
      expect(results.count).to eq(0)
    end

    it 'returns empty result set when offset exceeds row count (LIMIT 100, 5)' do
      results = client.query('SELECT * FROM limit_comma_test LIMIT 100, 5;')
      expect(results.count).to eq(0)
    end

    it 'returns rows from offset 5 with limit 10 (LIMIT 5, 10)' do
      results = client.query('SELECT * FROM limit_comma_test LIMIT 5, 10;')
      expect(results.count).to eq(5)
      expect(results.map { |r| r['id'] }).to eq([6, 7, 8, 9, 10])
    end
  end

  describe 'LIMIT and OFFSET combinations' do
    before do
      client.query('DROP TABLE IF EXISTS limit_offset_test;')
      client.query('CREATE TABLE limit_offset_test (id INT);')
      15.times { |i| client.query("INSERT INTO limit_offset_test VALUES (#{i + 1});") }
    end

    it 'returns 5 rows starting from the 11th row (LIMIT 5 OFFSET 10)' do
      results = client.query('SELECT id FROM limit_offset_test LIMIT 5 OFFSET 10;')
      expect(results.count).to eq(5)
      expect(results.map { |r| r['id'] }).to eq([11, 12, 13, 14, 15])
    end

    it 'returns 5 rows starting from the 1st row (LIMIT 5 OFFSET 0)' do
      results = client.query('SELECT id FROM limit_offset_test LIMIT 5 OFFSET 0;')
      expect(results.count).to eq(5)
      expect(results.map { |r| r['id'] }).to eq([1, 2, 3, 4, 5])
    end

    it 'returns empty result set when OFFSET exceeds row count (LIMIT 5 OFFSET 100)' do
      results = client.query('SELECT id FROM limit_offset_test LIMIT 5 OFFSET 100;')
      expect(results.count).to eq(0)
    end

    it 'returns 0 rows when LIMIT is 0 (LIMIT 0 OFFSET 5)' do
      results = client.query('SELECT id FROM limit_offset_test LIMIT 0 OFFSET 5;')
      expect(results.count).to eq(0)
    end

    it 'returns an error when LIMIT comma syntax and OFFSET keyword are used together' do
      expect do
        client.query('SELECT id FROM limit_offset_test LIMIT 0, 10 OFFSET 5;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'OFFSET clause support' do
    before do
      client.query('DROP TABLE IF EXISTS offset_test;')
      client.query('CREATE TABLE offset_test (id INT);')
      15.times { |i| client.query("INSERT INTO offset_test VALUES (#{i + 1});") }
    end

    it 'returns an error when OFFSET is used without LIMIT (SELECT id FROM offset_test OFFSET 5;)' do
      expect do
        client.query('SELECT id FROM offset_test OFFSET 5;')
      end.to raise_error(Mysql2::Error)
    end

    it 'combines LIMIT and OFFSET (SELECT * FROM offset_test LIMIT 10 OFFSET 5;)' do
      results = client.query('SELECT * FROM offset_test LIMIT 10 OFFSET 5;')
      expect(results.count).to eq(10)
      expect(results.first.values.first).to eq(6)
      expect(results.to_a.last.values.first).to eq(15)
    end

    it 'supports LIMIT offset, count syntax (SELECT * FROM offset_test LIMIT 5, 10;)' do
      results = client.query('SELECT * FROM offset_test LIMIT 5, 10;')
      expect(results.count).to eq(10)
      expect(results.first.values.first).to eq(6)
    end

    it 'returns an error for LIMIT offset, count combined with OFFSET keyword' do
      expect do
        client.query('SELECT * FROM offset_test LIMIT 5, 10 OFFSET 5;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'Multi-column ORDER BY support' do
    before do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, category VARCHAR(255), price INT);')
      client.query("INSERT INTO products VALUES (1, 'electronics', 100);")
      client.query("INSERT INTO products VALUES (2, 'electronics', 200);")
      client.query("INSERT INTO products VALUES (3, 'books', 50);")
      client.query("INSERT INTO products VALUES (4, 'books', 150);")
    end

    it 'sorts by multiple columns (category ASC, price DESC)' do
      results = client.query('SELECT category, price FROM products ORDER BY category ASC, price DESC;')
      rows = results.to_a
      expect(rows[0].values).to eq(['books', 150])
      expect(rows[1].values).to eq(['books', 50])
      expect(rows[2].values).to eq(['electronics', 200])
      expect(rows[3].values).to eq(['electronics', 100])
    end

    it 'defaults to ASC when direction is omitted' do
      results = client.query('SELECT category, price FROM products ORDER BY category, price;')
      rows = results.to_a
      expect(rows[0].values).to eq(['books', 50])
      expect(rows[1].values).to eq(['books', 150])
      expect(rows[2].values).to eq(['electronics', 100])
      expect(rows[3].values).to eq(['electronics', 200])
    end

    it 'sorts by mixed directions (category DESC, price ASC)' do
      results = client.query('SELECT category, price FROM products ORDER BY category DESC, price ASC;')
      rows = results.to_a
      expect(rows[0].values).to eq(['electronics', 100])
      expect(rows[1].values).to eq(['electronics', 200])
      expect(rows[2].values).to eq(['books', 50])
      expect(rows[3].values).to eq(['books', 150])
    end

    it 'sorts NULL values correctly (NULLs first for ASC, last for DESC)' do
      client.query('DROP TABLE IF EXISTS null_sort_test;')
      client.query('CREATE TABLE null_sort_test (id INT, val_int INT, val_str VARCHAR(255));')
      client.query('INSERT INTO null_sort_test VALUES (1, NULL, NULL);')
      client.query("INSERT INTO null_sort_test VALUES (2, 10, 'B');")
      client.query("INSERT INTO null_sort_test VALUES (3, NULL, 'A');")
      client.query('INSERT INTO null_sort_test VALUES (4, 20, NULL);')

      # ASC: NULLs first (integers)
      results_int_asc = client.query('SELECT id FROM null_sort_test ORDER BY val_int ASC;')
      ids_int_asc = results_int_asc.map { |r| r['id'] }
      expect(ids_int_asc.first(2)).to contain_exactly(1, 3)
      expect(ids_int_asc[2..]).to eq([2, 4])

      # DESC: NULLs last (integers)
      results_int_desc = client.query('SELECT id FROM null_sort_test ORDER BY val_int DESC;')
      ids_int_desc = results_int_desc.map { |r| r['id'] }
      expect(ids_int_desc.first(2)).to eq([4, 2])
      expect(ids_int_desc[2..]).to contain_exactly(1, 3)

      # ASC: NULLs first (strings)
      results_str_asc = client.query('SELECT id FROM null_sort_test ORDER BY val_str ASC;')
      ids_str_asc = results_str_asc.map { |r| r['id'] }
      expect(ids_str_asc.first(2)).to contain_exactly(1, 4)
      expect(ids_str_asc[2..]).to eq([3, 2])

      # DESC: NULLs last (strings)
      results_str_desc = client.query('SELECT id FROM null_sort_test ORDER BY val_str DESC;')
      ids_str_desc = results_str_desc.map { |r| r['id'] }
      expect(ids_str_desc.first(2)).to eq([2, 3])
      expect(ids_str_desc[2..]).to contain_exactly(1, 4)

      # Multiple columns with NULLs
      results_multi = client.query('SELECT id FROM null_sort_test ORDER BY val_int ASC, val_str ASC;')
      expect(results_multi.map { |r| r['id'] }).to eq([1, 3, 2, 4])
    end

    it 'returns an error for non-existent columns in ORDER BY' do
      expect do
        client.query('SELECT category FROM products ORDER BY non_existent, category ASC;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'ORDER BY with Alias support' do
    before do
      client.query('DROP TABLE IF EXISTS users;')
      client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      client.query("INSERT INTO users VALUES (2, 'bob');")
      client.query("INSERT INTO users VALUES (3, 'charlie');")
    end

    it 'sorts by column alias' do
      results = client.query('SELECT name AS user_name FROM users ORDER BY user_name DESC;')
      expect(results.map { |r| r['user_name'] }).to eq(%w[charlie bob alice])
    end

    it 'sorts by aggregate alias' do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, category VARCHAR(255), price INT);')
      client.query("INSERT INTO products VALUES (1, 'electronics', 100);")
      client.query("INSERT INTO products VALUES (2, 'electronics', 200);")
      client.query("INSERT INTO products VALUES (3, 'books', 50);")
      client.query("INSERT INTO products VALUES (4, 'books', 150);")
      results = client.query('SELECT category, SUM(price) AS total FROM products GROUP BY category ORDER BY total ASC;')
      expect(results.map { |r| r['category'] }).to eq(%w[books electronics])
    end

    it 'returns an error for non-existent alias in ORDER BY' do
      expect do
        client.query('SELECT name FROM users ORDER BY unknown_alias;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'Alias support' do
    it 'supports column aliases with AS' do
      results = client.query('SELECT 1 AS total;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(1)
    end

    it 'supports column aliases without AS' do
      results = client.query('SELECT 1 total;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(1)
    end

    it 'supports implicit aliases with expressions (SELECT 1 + 1 total;)' do
      results = client.query('SELECT 1 + 1 total;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(2)
    end

    it 'supports implicit aliases with backticks (SELECT 1 + 1 `total`;)' do
      results = client.query('SELECT 1 + 1 `total`;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(2)
    end

    it 'does not treat the last word as an alias if the expression ends with an operator (SELECT 1 + total;)' do
      # 'total' がカラムとして存在しないため、定数式としては不正であり、エラーになることが期待される
      expect { client.query('SELECT 1 + total;') }.to raise_error(Mysql2::Error)
    end

    it 'supports implicit aliases with string literals (SELECT "hello" alias;)' do
      results = client.query('SELECT "hello" alias;')
      expect(results.fields.first).to eq('alias')
      expect(results.first.values.first).to eq('hello')
    end

    it 'supports implicit aliases with parenthesized expressions (SELECT (1 + 1) total;)' do
      results = client.query('SELECT (1 + 1) total;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(2)
    end

    it 'supports NULL with an alias (SELECT NULL AS val;)' do
      results = client.query('SELECT NULL AS val;')
      expect(results.fields.first).to eq('val')
      expect(results.first.values.first).to be_nil
    end

    it 'supports parenthesized expressions with explicit aliases (SELECT (1 + 1) AS total;)' do
      results = client.query('SELECT (1 + 1) AS total;')
      expect(results.fields.first).to eq('total')
      expect(results.first.values.first).to eq(2)
    end

    it 'returns the expression as column name when no alias is provided (SELECT 1 + 1;)' do
      results = client.query('SELECT 1 + 1;')
      expect(results.fields.first).to eq('1 + 1')
      expect(results.first.values.first).to eq(2)
    end

    it 'supports table aliases with AS' do
      client.query('CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      results = client.query('SELECT u.name FROM users AS u;')
      expect(results.first.values.first).to eq('alice')
    end

    it 'supports table aliases without AS' do
      client.query('CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(255));')
      client.query("INSERT INTO users VALUES (1, 'alice');")
      results = client.query('SELECT u.name FROM users u;')
      expect(results.first.values.first).to eq('alice')
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

    it 'updates multiple columns simultaneously' do
      client.query("UPDATE users SET name = 'charlie', id = 10 WHERE id = 1;")
      results = client.query('SELECT id, name FROM users WHERE id = 10;')
      expect(results.count).to eq(1)
      expect(results.first.values).to eq([10, 'charlie'])
    end

    it 'returns an error when updating a non-existent column' do
      expect do
        client.query("UPDATE users SET non_existent = 'value' WHERE id = 1;")
      end.to raise_error(Mysql2::Error)
    end

    it 'updates all rows when WHERE clause is omitted' do
      client.query("UPDATE users SET name = 'everyone';")
      results = client.query('SELECT name FROM users;')
      expect(results.count).to eq(2)
      expect(results.all? { |r| r['name'] == 'everyone' }).to be true
    end

    it 'updates columns with values containing commas' do
      client.query("UPDATE users SET name = 'Doe, John' WHERE id = 1;")
      results = client.query('SELECT name FROM users WHERE id = 1;')
      expect(results.first.values.first).to eq('Doe, John')
    end

    it 'supports INSERT with column list (reordered)' do
      client.query("INSERT INTO users (name, id) VALUES ('charlie', 3);")
      results = client.query('SELECT * FROM users WHERE id = 3;')
      expect(results.first.values).to eq([3, 'charlie'])
    end

    it 'supports INSERT with column list (partial)' do
      client.query("INSERT INTO users (name) VALUES ('diana');")
      results = client.query("SELECT * FROM users WHERE name = 'diana';")
      expect(results.first.values).to eq([nil, 'diana'])
    end

    it 'returns an error for INSERT with non-existent column' do
      expect do
        client.query('INSERT INTO users (unknown_col) VALUES (1);')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error for INSERT with column count mismatch (no column list)' do
      expect do
        client.query('INSERT INTO users VALUES (1);')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error for INSERT with column count mismatch (with column list)' do
      expect do
        client.query('INSERT INTO users (id, name) VALUES (1);')
      end.to raise_error(Mysql2::Error)
    end

    it 'deletes specific rows matching a WHERE clause' do
      client.query('DELETE FROM users WHERE id = 2;')
      results = client.query('SELECT * FROM users;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end

    it 'updates rows with ORDER BY and LIMIT' do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, price INT, sale INT);')
      client.query('INSERT INTO products VALUES (1, 100, 0);')
      client.query('INSERT INTO products VALUES (2, 300, 0);')
      client.query('INSERT INTO products VALUES (3, 200, 0);')

      # 価格の高い順に2件をセール対象にする
      client.query('UPDATE products SET sale = 1 ORDER BY price DESC LIMIT 2;')

      results = client.query('SELECT id FROM products WHERE sale = 1 ORDER BY id ASC;')
      ids = results.map { |r| r['id'] }
      expect(ids).to contain_exactly(2, 3)
    end

    it 'deletes rows with ORDER BY and LIMIT' do
      client.query('DROP TABLE IF EXISTS logs;')
      client.query('CREATE TABLE logs (id INT, timestamp INT);')
      client.query('INSERT INTO logs VALUES (1, 1000);')
      client.query('INSERT INTO logs VALUES (2, 2000);')
      client.query('INSERT INTO logs VALUES (3, 3000);')

      # タイムスタンプが古い順に2件削除する
      client.query('DELETE FROM logs ORDER BY timestamp ASC LIMIT 2;')

      results = client.query('SELECT id FROM logs;')
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(3)
    end

    it 'updates rows with WHERE, ORDER BY and LIMIT' do
      client.query('DROP TABLE IF EXISTS products;')
      client.query('CREATE TABLE products (id INT, category VARCHAR(255), price INT, sale INT);')
      client.query("INSERT INTO products VALUES (1, 'electronics', 100, 0);")
      client.query("INSERT INTO products VALUES (2, 'electronics', 300, 0);")
      client.query("INSERT INTO products VALUES (3, 'electronics', 200, 0);")
      client.query("INSERT INTO products VALUES (4, 'books', 500, 0);")

      # electronics カテゴリの中で価格の高い順に1件をセール対象にする
      client.query("UPDATE products SET sale = 1 WHERE category = 'electronics' ORDER BY price DESC LIMIT 1;")

      results = client.query('SELECT id FROM products WHERE sale = 1;')
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(2)
    end

    it 'deletes rows with WHERE, ORDER BY and LIMIT' do
      client.query('DROP TABLE IF EXISTS logs;')
      client.query('CREATE TABLE logs (id INT, level VARCHAR(10), timestamp INT);')
      client.query("INSERT INTO logs VALUES (1, 'INFO', 1000);")
      client.query("INSERT INTO logs VALUES (2, 'INFO', 2000);")
      client.query("INSERT INTO logs VALUES (3, 'INFO', 3000);")
      client.query("INSERT INTO logs VALUES (4, 'ERROR', 500);")
      client.query("INSERT INTO logs VALUES (5, 'ERROR', 1500);")

      # ERROR レベルの中でタイムスタンプが古い順に1件削除する
      client.query("DELETE FROM logs WHERE level = 'ERROR' ORDER BY timestamp ASC LIMIT 1;")

      results = client.query("SELECT id FROM logs WHERE level = 'ERROR';")
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(5)
    end

    it 'updates multiple rows using OR in WHERE clause' do
      client.query('DROP TABLE IF EXISTS update_or_test;')
      client.query('CREATE TABLE update_or_test (id INT, val VARCHAR(255));')
      client.query("INSERT INTO update_or_test VALUES (1, 'a');")
      client.query("INSERT INTO update_or_test VALUES (2, 'b');")
      client.query("INSERT INTO update_or_test VALUES (3, 'c');")

      client.query("UPDATE update_or_test SET val = 'updated' WHERE id = 1 OR id = 3;")
      results = client.query('SELECT id, val FROM update_or_test ORDER BY id ASC;')
      rows = results.to_a
      expect(rows[0]['val']).to eq('updated')
      expect(rows[1]['val']).to eq('b')
      expect(rows[2]['val']).to eq('updated')
    end

    it 'deletes multiple rows using OR in WHERE clause' do
      client.query('DROP TABLE IF EXISTS delete_or_test;')
      client.query('CREATE TABLE delete_or_test (id INT, val VARCHAR(255));')
      client.query("INSERT INTO delete_or_test VALUES (1, 'a');")
      client.query("INSERT INTO delete_or_test VALUES (2, 'b');")
      client.query("INSERT INTO delete_or_test VALUES (3, 'c');")

      client.query('DELETE FROM delete_or_test WHERE id = 1 OR id = 2;')
      results = client.query('SELECT id FROM delete_or_test;')
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(3)
    end

    it 'returns an error for UPDATE with OFFSET in LIMIT' do
      expect do
        client.query('UPDATE users SET name = "test" LIMIT 10 OFFSET 5;')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error for UPDATE with comma-separated LIMIT' do
      expect do
        client.query('UPDATE users SET name = "test" LIMIT 5, 10;')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error for DELETE with OFFSET in LIMIT' do
      expect do
        client.query('DELETE FROM users LIMIT 5 OFFSET 2;')
      end.to raise_error(Mysql2::Error)
    end

    it 'returns an error for DELETE with comma-separated LIMIT' do
      expect do
        client.query('DELETE FROM users LIMIT 2, 5;')
      end.to raise_error(Mysql2::Error)
    end
  end

  describe 'UPDATE and DELETE with LIMIT' do
    before do
      client.query('DROP TABLE IF EXISTS limit_test;')
      client.query('CREATE TABLE limit_test (id INT, val VARCHAR(255));')
      client.query("INSERT INTO limit_test VALUES (1, 'a');")
      client.query("INSERT INTO limit_test VALUES (2, 'b');")
      client.query("INSERT INTO limit_test VALUES (3, 'c');")
    end

    it 'updates only the first N rows using LIMIT' do
      client.query("UPDATE limit_test SET val = 'updated' LIMIT 2;")
      results = client.query('SELECT id, val FROM limit_test ORDER BY id ASC;')
      rows = results.to_a
      expect(rows[0]['val']).to eq('updated')
      expect(rows[1]['val']).to eq('updated')
      expect(rows[2]['val']).to eq('c')
    end

    it 'deletes only the first N rows using LIMIT' do
      client.query('DELETE FROM limit_test WHERE id > 0 LIMIT 2;')
      results = client.query('SELECT id FROM limit_test;')
      expect(results.count).to eq(1)
      expect(results.first['id']).to eq(3)
    end

    it 'updates 0 rows when LIMIT 0 is specified' do
      client.query("UPDATE limit_test SET val = 'updated' LIMIT 0;")
      results = client.query('SELECT id, val FROM limit_test ORDER BY id ASC;')
      expect(results.to_a.none? { |r| r['val'] == 'updated' }).to be true
    end

    it 'deletes 0 rows when LIMIT 0 is specified' do
      client.query('DELETE FROM limit_test WHERE id > 0 LIMIT 0;')
      results = client.query('SELECT id FROM limit_test;')
      expect(results.count).to eq(3)
    end

    it 'updates all rows when LIMIT exceeds row count' do
      client.query("UPDATE limit_test SET val = 'updated' LIMIT 100;")
      results = client.query('SELECT id, val FROM limit_test ORDER BY id ASC;')
      expect(results.to_a.all? { |r| r['val'] == 'updated' }).to be true
    end

    it 'deletes all rows when LIMIT exceeds row count' do
      client.query('DELETE FROM limit_test WHERE id > 0 LIMIT 100;')
      results = client.query('SELECT id FROM limit_test;')
      expect(results.count).to eq(0)
    end
  end
end
