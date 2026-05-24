# ... 既存コード ...

describe 'Aggregate Functions (COUNT)' do
  before do
    client.query('DROP TABLE IF EXISTS users;')
    client.query('CREATE TABLE users (id INT, name VARCHAR(255));')
    client.query("INSERT INTO users VALUES (1, 'alice');")
    client.query("INSERT INTO users VALUES (2, 'bob');")
    client.query("INSERT INTO users VALUES (3, 'charlie');")
  end

  it 'returns the count of all rows with COUNT(*)' do
    results = client.query('SELECT COUNT(*) FROM users;')
    expect(results.fields).to eq(['COUNT(*)'])
    expect(results.first.values.first).to eq(3)
  end

  it 'returns 0 for COUNT(*) on empty table' do
    client.query('DROP TABLE IF EXISTS empty_table;')
    client.query('CREATE TABLE empty_table (id INT);')
    results = client.query('SELECT COUNT(*) FROM empty_table;')
    expect(results.first.values.first).to eq(0)
  end

  it 'returns the count of filtered rows with COUNT(*) and WHERE' do
    results = client.query('SELECT COUNT(*) FROM users WHERE id > 1;')
    expect(results.first.values.first).to eq(2)
  end

  it 'returns 0 for COUNT(*) with WHERE that matches no rows' do
    results = client.query('SELECT COUNT(*) FROM users WHERE id > 100;')
    expect(results.first.values.first).to eq(0)
  end
end
