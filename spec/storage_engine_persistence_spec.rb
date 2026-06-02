# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/ruby_pure_mysql/storage_engine'

RSpec.describe RubyPureMysql::StorageEngine do
  let(:db_dir) { 'db' }

  before do
    FileUtils.rm_rf(db_dir)
  end

  after do
    FileUtils.rm_rf(db_dir)
  end

  it 'persists table and data across instances' do
    # 1. 最初のインスタンスでテーブル作成とデータ挿入
    engine1 = described_class.new
    engine1.create_table('users', %w[id name])
    engine1.insert('users', [1, 'alice'])
    engine1.insert('users', [2, 'bob'])

    # 2. インスタンスを破棄し、新しいインスタンスを作成（再起動のシミュレーション）
    engine2 = described_class.new

    # 3. データが保持されているか確認
    expect(engine2.list_tables).to include('users')
    expect(engine2.get_columns('users')).to eq(%w[id name])
    expect(engine2.select('users')).to eq([[1, 'alice'], [2, 'bob']])
  end

  it 'persists updates across instances' do
    engine1 = described_class.new
    engine1.create_table('users', %w[id name])
    engine1.insert('users', [1, 'alice'])

    engine2 = described_class.new
    # UPDATEのシミュレーション
    engine2.update_rows_with_where('users', { client: nil, where: [], table_map: {} }, { 1 => 'bob' })

    engine3 = described_class.new
    expect(engine3.select('users')).to eq([[1, 'bob']])
  end

  it 'persists deletions across instances' do
    engine1 = described_class.new
    engine1.create_table('users', %w[id name])
    engine1.insert('users', [1, 'alice'])
    engine1.insert('users', [2, 'bob'])

    engine2 = described_class.new
    # DELETEのシミュレーション
    engine2.delete_rows_with_where('users', { client: nil, where: [], table_map: {} })

    engine3 = described_class.new
    expect(engine3.select('users')).to be_empty
  end

  it 'removes data file when table is dropped' do
    engine = described_class.new
    engine.create_table('users', %w[id name])
    engine.insert('users', [1, 'alice'])

    data_file = File.join(db_dir, 'data', 'users.json')
    expect(File.exist?(data_file)).to be true

    engine.drop_table('users')
    expect(File.exist?(data_file)).to be false
  end

  it 'prevents path traversal in table names' do
    engine = described_class.new
    traversal_name = '../../traversal_test'
    engine.create_table(traversal_name, %w[id])
    engine.insert(traversal_name, [1])

    expected_path = File.join(db_dir, 'data', 'traversal_test.json')
    expect(File.exist?(expected_path)).to be true
  end

  it 'persists index definitions and data across instances' do
    engine1 = described_class.new
    engine1.create_table('users', %w[id name], { 'id_idx' => [0] })
    engine1.insert('users', [1, 'alice'])

    engine2 = described_class.new
    expect(engine2.instance_variable_get(:@index_definitions)['users']).to eq({ 'id_idx' => [0] })
    index_data = engine2.instance_variable_get(:@index_data)['users']['id_idx']
    expect(index_data[[1].to_json]).to eq([0])
  end

  it 'updates index map on insert' do
    engine = described_class.new
    engine.create_table('users', %w[id name], { 'id_idx' => [0] })
    engine.insert('users', [1, 'alice'])
    engine.insert('users', [2, 'bob'])

    index_data = engine.instance_variable_get(:@index_data)['users']['id_idx']
    expect(index_data[[1].to_json]).to eq([0])
    expect(index_data[[2].to_json]).to eq([1])
  end
end
