# frozen_string_literal: true

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    def initialize
      @tables = {}
    end

    # rubocop:disable Naming/PredicateMethod
    def create_table(name, columns)
      return false if @tables.key?(name)

      @tables[name] = columns
      true
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
