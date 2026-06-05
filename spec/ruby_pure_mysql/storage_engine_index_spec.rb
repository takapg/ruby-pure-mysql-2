# frozen_string_literal: true

require 'spec_helper'
require 'json'
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

    it '明示的に指定された PRIMARY インデックスが自動検出された主キー定義よりも優先されること' do
      # カラム定義では id(0) が PK だが、create_table の引数で code(1) を PK として指定
      cols = [
        { name: 'id', primary_key: true },
        { name: 'code', primary_key: false }
      ]
      explicit_indexes = { 'PRIMARY' => [1] }
      engine.create_table('override_pk_table', cols, explicit_indexes)

      index_defs = engine.instance_variable_get(:@index_definitions)['override_pk_table']
      expect(index_defs['PRIMARY']).to eq([1])
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

    it 'UNIQUE 制約が指定されたカラムに重複値を挿入した際に :duplicate_pk が返されること' do
      unique_table = 'unique_test_table'
      # email (index 1) を UNIQUE に設定
      cols = [
        { name: 'id' },
        { name: 'email', unique: true },
        { name: 'age' }
      ]
      engine.create_table(unique_table, cols)
      engine.insert(unique_table, [1, 'test@example.com', 20])
      # 同じメールアドレスで挿入
      expect(engine.insert(unique_table, [2, 'test@example.com', 30])).to eq(:duplicate_pk)
      # 異なるメールアドレスなら成功
      expect(engine.insert(unique_table, [3, 'other@example.com', 40])).to be true
    end

    it 'UNIQUE 制約が自動的にインデックス定義に追加されること' do
      unique_table = 'auto_unique_table'
      cols = [
        { name: 'id' },
        { name: 'email', unique: true }
      ]
      engine.create_table(unique_table, cols)
      index_defs = engine.instance_variable_get(:@index_definitions)[unique_table]
      expect(index_defs).to have_key('unique_email')
      expect(index_defs['unique_email']).to eq([1])
    end

    it '自動検出された複合主キーが重複している場合に insert が :duplicate_pk を返すこと（属性定義）' do
      comp_table = 'auto_comp_pk_table'
      cols = [
        { name: 'id', primary_key: true },
        { name: 'code', primary_key: true },
        { name: 'name', primary_key: false }
      ]
      engine.create_table(comp_table, cols)
      engine.insert(comp_table, [1, 'A1', 'Alice'])
      expect(engine.insert(comp_table, [1, 'A1', 'Bob'])).to eq(:duplicate_pk)
      expect(engine.insert(comp_table, [1, 'A2', 'Bob'])).to be true
    end

    it '自動検出された複合主キーが重複している場合に insert が :duplicate_pk を返すこと（テーブル制約定義）' do
      comp_table = 'auto_comp_constraint_table'
      cols = [
        { name: 'id' },
        { name: 'code' },
        { primary_key: true, columns: [0, 1] }
      ]
      engine.create_table(comp_table, cols)
      engine.insert(comp_table, [1, 'A1', 'Alice'])
      expect(engine.insert(comp_table, [1, 'A1', 'Bob'])).to eq(:duplicate_pk)
      expect(engine.insert(comp_table, [1, 'A2', 'Bob'])).to be true
    end
  end

  describe 'インデックス接頭辞ルックアップにおける範囲検索の検証' do
    let(:range_table) { 'range_table' }
    let(:range_cols) { %w[id name age] }
    let(:range_indexes) { { 'id_idx' => [0], 'comp_idx' => [0, 2] } }

    before do
      engine.create_table(range_table, range_cols, range_indexes)
      [
        [10, 'A', 20],
        [20, 'B', 30],
        [30, 'C', 40],
        [40, 'D', 50]
      ].each { |row| engine.insert(range_table, row) }
    end

    it '単一カラムインデックスで > 検索が正しく動作すること' do
      where = [{ column: 'id', operator: '>', value: 20 }]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(2, 3)
    end

    it '単一カラムインデックスで < 検索が正しく動作すること' do
      where = [{ column: 'id', operator: '<', value: 30 }]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(0, 1)
    end

    it '単一カラムインデックスで >= 検索が正しく動作すること' do
      where = [{ column: 'id', operator: '>=', value: 20 }]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(1, 2, 3)
    end

    it '単一カラムインデックスで <= 検索が正しく動作すること' do
      where = [{ column: 'id', operator: '<=', value: 30 }]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(0, 1, 2)
    end

    it '複合インデックスの先頭カラムで範囲検索が動作すること' do
      where = [{ column: 'id', operator: '>', value: 15 }]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(1, 2, 3)
    end

    it '複合インデックスの先頭が範囲検索の場合、後続のカラム条件はインデックスルックアップに寄与しないが結果は正しいこと' do
      where = [
        { column: 'id', operator: '>', value: 15 },
        { column: 'age', operator: '=', value: 30 }
      ]
      indices = engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      expect(indices).to contain_exactly(1)
    end

    it 'インデックスの先頭カラムに NULL 値が含まれている場合に範囲検索を行ってもクラッシュしないこと' do
      engine.insert(range_table, [nil, 'NullUser', 20])
      where = [{ column: 'id', operator: '>', value: 10 }]
      expect do
        engine.find_matching_indices(nil, engine.select(range_table), engine.get_columns(range_table), where)
      end.not_to raise_error
    end
  end

  describe '複合インデックスの最適化ルックアップの検証' do
    let(:comp_table) { 'comp_table' }
    let(:comp_cols) { %w[col1 col2 col3] }
    let(:comp_indexes) { { 'comp_idx' => [0, 1, 2] } }

    before do
      engine.create_table(comp_table, comp_cols, comp_indexes)
      [
        ['A', 10, 'X'],
        ['A', 20, 'Y'],
        ['A', 20, 'Z'],
        ['B', 10, 'X'],
        ['B', 20, 'Y']
      ].each { |row| engine.insert(comp_table, row) }
    end

    it '複合インデックスの全カラムが = 条件の場合に正しく絞り込まれること' do
      where = [
        { column: 'col1', operator: '=', value: 'A' },
        { column: 'col2', operator: '=', value: 20 },
        { column: 'col3', operator: '=', value: 'Z' }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(2)
    end

    it '複合インデックスの一部（先頭から）が = 条件で、その後に範囲検索がある場合に正しく絞り込まれること' do
      where = [
        { column: 'col1', operator: '=', value: 'A' },
        { column: 'col2', operator: '>', value: 15 }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(1, 2)
    end

    it '範囲検索の後のカラム条件はインデックスルックアップに寄与しないが、結果は正しいこと' do
      where = [
        { column: 'col1', operator: '>', value: 'A' },
        { column: 'col2', operator: '=', value: 10 }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(3)
    end

    it 'インデックスカラムの途中に条件がない場合、そこまでの条件のみで絞り込まれること' do
      where = [
        { column: 'col1', operator: '=', value: 'A' },
        { column: 'col3', operator: '=', value: 'Y' }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(1)
    end

    it '複合インデックスの途中に範囲検索があり、その後に完全一致条件がある場合に正しく絞り込まれること' do
      where = [
        { column: 'col1', operator: '=', value: 'A' },
        { column: 'col2', operator: '>', value: 15 },
        { column: 'col3', operator: '=', value: 'Z' }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(2)
    end

    it '自動検出された複合主キーを用いた WHERE 句ルックアップが正しく動作すること' do
      comp_table = 'auto_lookup_table'
      cols = [
        { name: 'id', primary_key: true },
        { name: 'code', primary_key: true },
        { name: 'name' }
      ]
      engine.create_table(comp_table, cols)
      engine.insert(comp_table, [1, 'A1', 'Alice'])
      engine.insert(comp_table, [2, 'B1', 'Bob'])

      where = [{ column: 'id', operator: '=', value: 1 }, { column: 'code', operator: '=', value: 'A1' }]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(0)
    end

    it '境界値（等号を含む範囲検索）が正しく評価されること' do
      where = [
        { column: 'col1', operator: '>=', value: 'B' },
        { column: 'col2', operator: '<=', value: 20 }
      ]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where)
      expect(indices).to contain_exactly(3, 4)
    end

    it '複合インデックスのカラムに NULL が含まれる場合に、範囲検索や完全一致が正しく動作し、クラッシュしないこと' do
      engine.insert(comp_table, [nil, 10, 'X'])
      engine.insert(comp_table, ['A', nil, 'Y'])
      engine.insert(comp_table, ['A', 20, nil])

      where_null = [{ column: 'col1', operator: '=', value: nil }]
      indices = engine.find_matching_indices(nil, engine.select(comp_table), engine.get_columns(comp_table), where_null)
      expect(indices).to be_empty
    end
  end

  describe 'インデックスキャッシュの細粒度クリアの検証' do
    let(:cache_table) { 'cache_test_table' }
    let(:cache_cols) { %w[id name age] }
    let(:cache_indexes) { { 'name_idx' => [1], 'age_idx' => [2] } }

    before do
      engine.create_table(cache_table, cache_cols, cache_indexes)
      1000.times do |i|
        engine.insert(cache_table, [i, "Name#{i}", 20 + i])
      end
    end

    it 'インデックス対象外のカラムを更新した際に、全てのインデックスキャッシュが維持されること' do
      # キャッシュを生成
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'name', operator: '>', value: 'Name500' }], table_name: cache_table
      )
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'age', operator: '>', value: 520 }], table_name: cache_table
      )

      cache_before = engine.instance_variable_get(:@index_sorted_keys)[cache_table].dup
      expect(cache_before).to have_key('name_idx')
      expect(cache_before).to have_key('age_idx')

      # id (index 0) を更新。インデックス対象外
      engine.update_rows_with_where(cache_table, {}, { 0 => 9999 })

      cache_after = engine.instance_variable_get(:@index_sorted_keys)[cache_table]
      expect(cache_after).to eq(cache_before)
    end

    it '特定のインデックス対象カラムを更新した際に、該当するインデックスのみキャッシュがクリアされること' do
      # キャッシュを生成
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'name', operator: '>', value: 'Name500' }], table_name: cache_table
      )
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'age', operator: '>', value: 520 }], table_name: cache_table
      )

      # name (index 1) を更新
      engine.update_rows_with_where(cache_table, {}, { 1 => 'UpdatedName' })

      cache_after = engine.instance_variable_get(:@index_sorted_keys)[cache_table]
      expect(cache_after).not_to have_key('name_idx')
      expect(cache_after).to have_key('age_idx')
    end

    it '行を削除した際に、テーブルの全インデックスキャッシュがクリアされること' do
      # キャッシュを生成
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'name', operator: '>', value: 'Name500' }], table_name: cache_table
      )
      engine.find_matching_indices(
        nil, engine.select(cache_table), engine.get_columns(cache_table),
        [{ column: 'age', operator: '>', value: 520 }], table_name: cache_table
      )

      # 行を削除
      engine.delete_rows_with_where(cache_table, {})

      cache_after = engine.instance_variable_get(:@index_sorted_keys)[cache_table]
      expect(cache_after).to be_nil
    end
  end

  describe 'インデックスの自動クリーンアップ検証' do
    it 'カラム更新後、古い値のインデックスエントリが@index_dataから完全に削除されること' do
      engine.insert(table_name, [1, 'Alice', 30])
      engine.update_rows_with_where(table_name, {}, { 1 => 'Bob' })

      index_data = engine.instance_variable_get(:@index_data)[table_name]['name_idx']
      expect(index_data).not_to have_key(['Alice'])
      expect(index_data).to have_key(['Bob'])
    end

    it '行削除後、その行が唯一の参照であったインデックスキーが@index_dataから消滅すること' do
      engine.insert(table_name, [1, 'Alice', 30])
      engine.delete_rows_with_where(table_name, {})

      index_data = engine.instance_variable_get(:@index_data)[table_name]['name_idx']
      expect(index_data).not_to have_key(['Alice'])
    end

    it '永続化後のJSONファイルに空のインデックスキーが含まれていないこと' do
      engine.insert(table_name, [1, 'Alice', 30])
      engine.update_rows_with_where(table_name, {}, { 1 => 'Bob' })
      engine.send(:save_data, table_name)

      file_path = engine.send(:data_file_path, table_name)
      json_content = JSON.parse(File.read(file_path))
      indexes = json_content['indexes']['name_idx']

      expect(indexes).not_to have_key('["Alice"]')
      expect(indexes).to have_key('["Bob"]')
    end

    it 'clear_index_cache 呼び出し後に @index_sorted_keys が適切にクリアされること' do
      # インデックスが確実に使用されるよう、データ量をさらに増やし、
      # オプティマイザがフルスキャンを選択しないようにする
      5000.times do |i|
        engine.insert(table_name, [i, "Name#{i.to_s.rjust(4, '0')}", 20 + i])
      end

      # 範囲を絞り込み、インデックス利用のメリットを明確にする
      where = [{ column: 'name', operator: '>', value: 'Name4000' }]
      engine.find_matching_indices(
        nil, engine.select(table_name), engine.get_columns(table_name), where, table_name: table_name
      )

      # キャッシュが生成されたことを確認
      cache = engine.instance_variable_get(:@index_sorted_keys)
      expect(cache).not_to be_nil
      expect(cache[table_name]).not_to be_nil

      engine.clear_index_cache(table_name)
      expect(engine.instance_variable_get(:@index_sorted_keys)[table_name]).to be_nil
    end
  end

  describe 'NULL値の厳格な検証 (MySQL 8.0 互換)' do
    let(:null_table) { 'null_test_table' }
    let(:null_cols) { %w[id val] }
    let(:null_indexes) { { 'val_idx' => [1] } }

    before do
      engine.create_table(null_table, null_cols, null_indexes)
      [
        [1, nil],
        [2, 10],
        [3, 20]
      ].each { |row| engine.insert(null_table, row) }
    end

    it '単一カラムインデックスで NULL が含まれる場合、比較演算子で NULL が除外されること' do
      rows = engine.select(null_table)
      cols = engine.get_columns(null_table)

      # val > 5 -> [2, 3]
      where_gt = [{ column: 'val', operator: '>', value: 5 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_gt)).to contain_exactly(1, 2)

      # val < 15 -> [2]
      where_lt = [{ column: 'val', operator: '<', value: 15 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_lt)).to contain_exactly(1)

      # val = 10 -> [2]
      where_eq = [{ column: 'val', operator: '=', value: 10 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_eq)).to contain_exactly(1)

      # val >= 10 -> [2, 3]
      where_ge = [{ column: 'val', operator: '>=', value: 10 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_ge)).to contain_exactly(1, 2)

      # val <= 20 -> [2, 3]
      where_le = [{ column: 'val', operator: '<=', value: 20 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_le)).to contain_exactly(1, 2)
    end

    it '検索値に NULL が指定された場合、比較演算子では何も抽出されないこと' do
      rows = engine.select(null_table)
      cols = engine.get_columns(null_table)

      # val = NULL -> []
      where_nil_eq = [{ column: 'val', operator: '=', value: nil }]
      expect(engine.find_matching_indices(nil, rows, cols, where_nil_eq)).to be_empty

      # val > NULL -> []
      where_nil_gt = [{ column: 'val', operator: '>', value: nil }]
      expect(engine.find_matching_indices(nil, rows, cols, where_nil_gt)).to be_empty

      # val < NULL -> []
      where_nil_lt = [{ column: 'val', operator: '<', value: nil }]
      expect(engine.find_matching_indices(nil, rows, cols, where_nil_lt)).to be_empty
    end

    it '複合インデックスの途中に NULL がある場合に正しくフィルタリングされること' do
      comp_null_table = 'comp_null_table'
      comp_null_cols = %w[id c1 c2 c3]
      comp_null_indexes = { 'comp_idx' => [1, 2, 3] }
      engine.create_table(comp_null_table, comp_null_cols, comp_null_indexes)
      [
        [1, 'A', nil, 'X'],
        [2, 'A', 10, 'X'],
        [3, 'B', 10, 'Y']
      ].each { |row| engine.insert(comp_null_table, row) }

      # c1 = 'A' AND c3 = 'X' -> [1, 2] (c2がNULLでもc1, c3が一致すれば抽出される)
      where_partial = [
        { column: 'c1', operator: '=', value: 'A' },
        { column: 'c3', operator: '=', value: 'X' }
      ]
      indices_partial = engine.find_matching_indices(
        nil, engine.select(comp_null_table), engine.get_columns(comp_null_table), where_partial
      )
      expect(indices_partial).to contain_exactly(0, 1)

      # c1 = 'A' AND c2 = 10 AND c3 = 'X' -> [2] (c2がNULLの行は除外される)
      where_full = [
        { column: 'c1', operator: '=', value: 'A' },
        { column: 'c2', operator: '=', value: 10 },
        { column: 'c3', operator: '=', value: 'X' }
      ]
      indices_full = engine.find_matching_indices(
        nil, engine.select(comp_null_table), engine.get_columns(comp_null_table), where_full
      )
      expect(indices_full).to contain_exactly(1)

      # 範囲検索 + NULL値の検証: c1 > 'A' AND c2 = 10
      # 行3 ('B', 20, 'Y') はマッチするが、もし ('B', nil, 'Y') があれば除外されるべき
      engine.insert(comp_null_table, [4, 'B', nil, 'Z'])
      where_range_null = [
        { column: 'c1', operator: '>', value: 'A' },
        { column: 'c2', operator: '=', value: 10 }
      ]
      indices_range_null = engine.find_matching_indices(
        nil, engine.select(comp_null_table), engine.get_columns(comp_null_table), where_range_null
      )
      expect(indices_range_null).to contain_exactly(2) # 行3のみ
    end

    it 'IS NULL 演算子を使用した場合に、正しく NULL 行が抽出されること' do
      rows = engine.select(null_table)
      cols = engine.get_columns(null_table)
      where_is_null = [{ column: 'val', operator: 'IS NULL', value: nil }]
      indices = engine.find_matching_indices(nil, rows, cols, where_is_null)
      expect(indices).to contain_exactly(0) # row 0 is [1, nil]

      # NULL安全等価演算子 (<=>) の検証
      # NULL <=> NULL -> マッチ
      where_null_safe_null = [{ column: 'val', operator: '<=>', value: nil }]
      expect(engine.find_matching_indices(nil, rows, cols, where_null_safe_null)).to contain_exactly(0)

      # 非NULL <=> NULL -> マッチしない
      where_val_safe_null = [{ column: 'val', operator: '<=>', value: 10 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_val_safe_null)).to contain_exactly(1)

      # 非NULL <=> 非NULL -> 正しくマッチ
      where_val_safe_val = [{ column: 'val', operator: '<=>', value: 20 }]
      expect(engine.find_matching_indices(nil, rows, cols, where_val_safe_val)).to contain_exactly(2)
    end
  end
end
