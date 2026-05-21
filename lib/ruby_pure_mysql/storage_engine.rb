# frozen_string_literal: true

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    def initialize
      @tables = {}
      @tables_mutex = Mutex.new
    end

    # rubocop:disable Naming/PredicateMethod
    def create_table(name, columns)
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        true
      end
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
