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
      expect(index_data['Alice'][['Alice']]).to have_key(0)
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
  end
end
