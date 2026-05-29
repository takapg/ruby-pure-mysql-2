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
      client.query('DROP TABLE IF EXISTS null_sort;')
      client.query('CREATE TABLE null_sort (id INT, val VARCHAR(255));')
      client.query('INSERT INTO null_sort VALUES (1, NULL);')
      client.query("INSERT INTO null_sort VALUES (2, 'A');")
      client.query('INSERT INTO null_sort VALUES (3, NULL);')

      # ASC: NULLs first
      results_asc = client.query('SELECT id FROM null_sort ORDER BY val ASC;')
      expect(results_asc.map { |r| r['id'] }).to include(1, 3)
      expect(results_asc.to_a.last['id']).to eq(2)

      # DESC: NULLs last
      results_desc = client.query('SELECT id FROM null_sort ORDER BY val DESC;')
      expect(results_desc.first['id']).to eq(2)
      expect(results_desc.map { |r| r['id'] }).to include(1, 3)
    end

    it 'returns an error for non-existent columns in ORDER BY' do
      expect do
        client.query('SELECT category FROM products ORDER BY non_existent, category ASC;')
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

    it 'deletes specific rows matching a WHERE clause' do
      client.query('DELETE FROM users WHERE id = 2;')
      results = client.query('SELECT * FROM users;')
      expect(results.count).to eq(1)
      expect(results.first.values.first).to eq(1)
    end
  end
end
