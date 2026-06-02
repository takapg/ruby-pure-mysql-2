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
    expect(index_data[1][[1]]).to eq([0])
  end

  it 'updates index map on insert' do
    engine = described_class.new
    engine.create_table('users', %w[id name], { 'id_idx' => [0] })
    engine.insert('users', [1, 'alice'])
    engine.insert('users', [2, 'bob'])

    index_data = engine.instance_variable_get(:@index_data)['users']['id_idx']
    expect(index_data[1][[1]]).to eq([0])
    expect(index_data[2][[2]]).to eq([1])
  end

  it 'handles composite indexes' do
    engine = described_class.new
    # [id, name] の複合インデックスを作成
    engine.create_table('users', %w[id name], { 'composite_idx' => [0, 1] })
    engine.insert('users', [1, 'alice'])
    engine.insert('users', [2, 'bob'])

    index_data = engine.instance_variable_get(:@index_data)['users']['composite_idx']
    expect(index_data[1][[1, 'alice']]).to eq([0])
    expect(index_data[2][[2, 'bob']]).to eq([1])
  end

  it 'handles non-unique index values' do
    engine = described_class.new
    # name カラムに非ユニークなインデックスを作成
    engine.create_table('users', %w[id name], { 'name_idx' => [1] })
    engine.insert('users', [1, 'alice'])
    engine.insert('users', [2, 'alice']) # 重複値

    index_data = engine.instance_variable_get(:@index_data)['users']['name_idx']
    expect(index_data['alice'][['alice']]).to eq([0, 1])
  end

  it 'optimizes search using indexes' do
    engine = described_class.new
    # 複合インデックス [id, name] を作成
    engine.create_table('users', %w[id name], { 'composite_idx' => [0, 1] })
    engine.insert('users', [1, 'alice'])
    engine.insert('users', [2, 'bob'])
    engine.insert('users', [3, 'charlie'])

    # 1. 完全一致ルックアップの検証 (id=2, name='bob')
    criteria_exact = {
      client: nil,
      where: [[{ column: 'id', operator: '=', value: 2 }, { column: 'name', operator: '=', value: 'bob' }]],
      table_map: {}
    }
    # update_rows_with_where を利用して間接的に get_target_indices を呼び出す
    engine.update_rows_with_where('users', criteria_exact, { 1 => 'bob_updated' })
    expect(engine.select('users')[1]).to eq([2, 'bob_updated'])

    # 2. 接頭辞マッチングの検証 (id=1 のみ指定)
    criteria_prefix = { client: nil, where: [[{ column: 'id', operator: '=', value: 1 }]], table_map: {} }
    engine.update_rows_with_where('users', criteria_prefix, { 1 => 'alice_updated' })
    expect(engine.select('users')[0]).to eq([1, 'alice_updated'])

    # 3. インデックスが使えない条件 (name='charlie' のみ指定、idはインデックスの先頭)
    criteria_no_idx = { client: nil, where: [[{ column: 'name', operator: '=', value: 'charlie' }]], table_map: {} }
    engine.update_rows_with_where('users', criteria_no_idx, { 1 => 'charlie_updated' })
    expect(engine.select('users')[2]).to eq([3, 'charlie_updated'])
  end
end
