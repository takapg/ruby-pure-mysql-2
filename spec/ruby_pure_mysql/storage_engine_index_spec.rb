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

      # 内部メソッドをモックして、特定の行を更新させる
      # collect_indices_to_delete が 0番目の行を返すと仮定
      allow(engine).to receive(:collect_indices_to_delete).and_return([0])

      # perform_update_rows? が実際にデータを更新するようにラップ
      allow(engine).to receive(:perform_update_rows?).and_wrap_original do |_m, *args|
        data, _cols, map, _crit = args
        row = data[0]
        map.each { |col_idx, val| row[col_idx] = val }
        true
      end

      # 'Alice' (index 1) を 'Bob' に更新
      engine.update_rows_with_where(table_name, {}, { 1 => 'Bob' })

      index_data = engine.instance_variable_get(:@index_data)[table_name]['name_idx']
      expect(index_data).not_to have_key('Alice')
      expect(index_data['Bob'][['Bob']]).to have_key(0)
    end

    it 'DELETEによって行が削除された際にインデックスエントリが完全に削除されること' do
      engine.insert(table_name, [1, 'Alice', 30])

      # 0番目の行を削除対象とする
      allow(engine).to receive(:collect_indices_to_delete).and_return([0])
      engine.delete_rows_with_where(table_name, {})

      index_data = engine.instance_variable_get(:@index_data)[table_name]['name_idx']
      expect(index_data).to be_empty
    end
  end
end
