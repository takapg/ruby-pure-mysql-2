# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/ruby_pure_mysql/storage_engine'

RSpec.describe RubyPureMysql::StorageEngine do
  let(:engine) { described_class.new }
  let(:table_name) { 'test_table' }
  let(:columns) { %w[id name age] }
  let(:indexes) { { 'name_idx' => [1] } }

  before do
    # 永続化ファイルを汚さないよう、メモリ上のデータを初期化
    engine.instance_variable_set(:@tables, {})
    engine.instance_variable_set(:@data, {})
    engine.instance_variable_set(:@index_definitions, {})
    engine.instance_variable_set(:@index_data, {})
    engine.create_table(table_name, columns, indexes)
  end

  describe 'インデックス更新ロジックの検証' do
    it '行を挿入した際にインデックスが正しく構築されること' do
      engine.insert(table_name, [1, 'Alice', 30])

      index_data = engine.instance_variable_get(:@index_data)[table_name]['name_idx']
      expect(index_data[['Alice']]).to have_key(0)
    end

    it 'UPDATEによってインデックス対象カラムが変更された際にインデックスが更新されること' do
      engine.insert(table_name, [1, 'Alice', 30])

      # 'Alice' (index 1) を 'Bob' に更新 (criteria: {} は全行マッチと想定)
      engine.update_rows_with_where(table_name, {}, { 1 => 'Bob' })

      # インデックスルックアップで 'Bob' が見つかることを検証
      where_bob = [{ column: 'name', operator: '=', value: 'Bob' }]
      indices_bob = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_bob
      )
      expect(indices_bob).to include(0)

      # インデックスルックアップで 'Alice' が見つからないことを検証
      where_alice = [{ column: 'name', operator: '=', value: 'Alice' }]
      indices_alice = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_alice
      )
      expect(indices_alice).to be_empty
    end

    it 'DELETEによって行が削除された際にインデックスエントリが完全に削除されること' do
      engine.insert(table_name, [1, 'Alice', 30])

      # 行を削除 (criteria: {} は全行マッチと想定)
      engine.delete_rows_with_where(table_name, {})

      # インデックスルックアップで何も見つからないことを検証
      where_alice = [{ column: 'name', operator: '=', value: 'Alice' }]
      indices = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_alice
      )
      expect(indices).to be_empty
    end

    it 'インデックスに含まれないカラムのみを更新した場合にインデックスが維持されること' do
      engine.insert(table_name, [1, 'Alice', 30])
      # 'age' (index 2) を更新。'name_idx' ([1]) には影響しないはず
      engine.update_rows_with_where(table_name, {}, { 2 => 31 })

      where_alice = [{ column: 'name', operator: '=', value: 'Alice' }]
      indices = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_alice
      )
      expect(indices).to include(0)
    end

    it '複数行を同時に更新した際に全てのインデックスが正しく更新されること' do
      engine.insert(table_name, [1, 'Alice', 30])
      engine.insert(table_name, [2, 'Bob', 20])
      engine.insert(table_name, [3, 'Charlie', 40])

      # age < 35 (Alice, Bob) の名前を 'Updated' に変更
      engine.update_rows_with_where(table_name, [{ column: 'age', operator: '<', value: 35 }], { 1 => 'Updated' })

      where_updated = [{ column: 'name', operator: '=', value: 'Updated' }]
      indices = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_updated
      )
      expect(indices).to contain_exactly(0, 1)
    end

    it '複数行を同時に削除した際に全てのインデックスエントリが削除されること' do
      engine.insert(table_name, [1, 'Alice', 30])
      engine.insert(table_name, [2, 'Bob', 20])
      engine.insert(table_name, [3, 'Charlie', 40])

      # age > 25 (Alice, Charlie) を削除
      engine.delete_rows_with_where(table_name, [{ column: 'age', operator: '>', value: 25 }])

      where_alice = [{ column: 'name', operator: '=', value: 'Alice' }]
      indices_alice = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_alice
      )
      expect(indices_alice).to be_empty

      where_bob = [{ column: 'name', operator: '=', value: 'Bob' }]
      indices_bob = engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where_bob
      )
      expect(indices_bob).to include(0) # Bobが唯一の行となりインデックス0に移動
    end
  end

  describe '自動インデックス作成の検証' do
    let(:auto_table) { 'auto_table' }
    let(:auto_cols) { %w[id name] }

    it 'インデックスを指定せずに作成した場合にインデックス定義が空であること' do
      engine.create_table(auto_table, auto_cols)
      index_defs = engine.instance_variable_get(:@index_definitions)[auto_table]
      expect(index_defs).to eq({})
    end

    it '文字列配列でカラムを定義し、別途 PRIMARY インデックスを指定した場合に正しく作成されること' do
      engine.create_table('string_cols_table', %w[id name], { 'PRIMARY' => [0] })
      index_defs = engine.instance_variable_get(:@index_definitions)['string_cols_table']
      expect(index_defs).to eq({ 'PRIMARY' => [0] })
    end

    it 'カラム定義に主キーが含まれている場合に自動的に PRIMARY インデックスが作成されること' do
      auto_pk_cols = [
        { name: 'id', primary_key: true },
        { name: 'name', primary_key: false }
      ]
      engine.create_table('auto_pk_table', auto_pk_cols)

      index_defs = engine.instance_variable_get(:@index_definitions)['auto_pk_table']
      expect(index_defs).to eq({ 'PRIMARY' => [0] })

      # 実際にインデックスが機能するか検証
      engine.insert('auto_pk_table', [1, 'AutoAlice'])
      where_id = [{ column: 'id', operator: '=', value: 1 }]
      indices = engine.find_matching_indices(
        nil, engine.select('auto_pk_table'), engine.get_columns('auto_pk_table'), where_id
      )
      expect(indices).to contain_exactly(0)
    end

    it '複数のカラムに主キーが設定されている場合に複合 PRIMARY インデックスが自動的に作成されること' do
      comp_pk_cols = [
        { name: 'id', primary_key: true },
        { name: 'code', primary_key: true },
        { name: 'name', primary_key: false }
      ]
      engine.create_table('comp_pk_table', comp_pk_cols)

      index_defs = engine.instance_variable_get(:@index_definitions)['comp_pk_table']
      expect(index_defs).to eq({ 'PRIMARY' => [0, 1] })

      # 実際にインデックスが機能するか検証
      engine.insert('comp_pk_table', [1, 'A1', 'Alice'])
      where_pk = [{ column: 'id', operator: '=', value: 1 }, { column: 'code', operator: '=', value: 'A1' }]
      indices = engine.find_matching_indices(
        nil, engine.select('comp_pk_table'), engine.get_columns('comp_pk_table'), where_pk
      )
      expect(indices).to contain_exactly(0)
    end

    it 'インデックスがない場合でもルックアップ（フルスキャン）ができること' do
      engine.create_table(auto_table, auto_cols)
      engine.insert(auto_table, [100, 'AutoAlice'])

      where_id = [{ column: 'id', operator: '=', value: 100 }]
      indices = engine.find_matching_indices(
        nil, engine.select(auto_table), engine.get_columns(auto_table), where_id
      )
      expect(indices).to contain_exactly(0)
    end

    it 'indexes が nil の場合でも正常に動作すること' do
      engine.create_table('nil_idx_table', %w[id name], nil)
      index_defs = engine.instance_variable_get(:@index_definitions)['nil_idx_table']
      expect(index_defs).to eq({})
    end

    it 'カラム定義が混在（文字列とハッシュ）している場合に正しく主キーを検出すること' do
      mixed_cols = [
        { name: 'id', primary_key: true },
        'name',
        { name: 'age', primary_key: false }
      ]
      engine.create_table('mixed_cols_table', mixed_cols)
      index_defs = engine.instance_variable_get(:@index_definitions)['mixed_cols_table']
      expect(index_defs).to eq({ 'PRIMARY' => [0] })
    end

    it 'カラム定義の中にテーブル制約としての主キー定義が含まれている場合に正しく検出されること' do
      cols = [
        { name: 'id' },
        { name: 'code' },
        { primary_key: true, columns: [0, 1] }
      ]
      engine.create_table('constraint_pk_table', cols)
      index_defs = engine.instance_variable_get(:@index_definitions)['constraint_pk_table']
      expect(index_defs).to eq({ 'PRIMARY' => [0, 1] })
    end
  end

  describe 'インデックスなしテーブルのDML動作検証' do
    let(:no_idx_table) { 'no_idx_table' }
    let(:no_idx_cols) { %w[id name] }

    before do
      engine.create_table(no_idx_table, no_idx_cols)
    end

    it 'インデックスなしでもINSERTが正常に動作すること' do
      expect(engine.insert(no_idx_table, [1, 'NoIndex'])).to be true
      expect(engine.select(no_idx_table)).to eq([[1, 'NoIndex']])
    end

    it 'インデックスなしでもUPDATEが正常に動作すること' do
      engine.insert(no_idx_table, [1, 'NoIndex'])
      # 全行更新
      expect(engine.update_rows_with_where(no_idx_table, {}, { 1 => 'Updated' })).to be true
      expect(engine.select(no_idx_table)).to eq([[1, 'Updated']])
    end

    it 'インデックスなしでもDELETEが正常に動作すること' do
      engine.insert(no_idx_table, [1, 'NoIndex'])
      # 全行削除
      expect(engine.delete_rows_with_where(no_idx_table, {})).to be true
      expect(engine.select(no_idx_table)).to be_empty
    end
  end

  describe '主キー制約の検証' do
    it '主キーが重複している場合に insert が :duplicate_pk を返すこと' do
      pk_table = 'pk_test_table'
      engine.create_table(pk_table, columns, { 'PRIMARY' => [0] }) # id を主キーに設定
      engine.insert(pk_table, [1, 'Alice', 30])
      expect(engine.insert(pk_table, [1, 'Bob', 25])).to eq(:duplicate_pk)
    end

    it '複合主キーが重複している場合に insert が :duplicate_pk を返すこと' do
      comp_table = 'comp_pk_table'
      # id(0) と name(1) を複合主キーに設定
      engine.create_table(comp_table, columns, { 'PRIMARY' => [0, 1] })
      engine.insert(comp_table, [1, 'Alice', 30])
      # 同じ組み合わせは失敗
      expect(engine.insert(comp_table, [1, 'Alice', 25])).to eq(:duplicate_pk)
      # 片方だけ同じなら成功
      expect(engine.insert(comp_table, [1, 'Bob', 25])).to be true
      expect(engine.insert(comp_table, [2, 'Alice', 25])).to be true
    end

    it '主キーが指定されていない場合は重複挿入が可能であること' do
      no_pk_table = 'no_pk_test_table'
      engine.create_table(no_pk_table, columns)
      engine.insert(no_pk_table, [1, 'Alice', 30])
      expect(engine.insert(no_pk_table, [1, 'Bob', 25])).to be true
    end
  end
end
