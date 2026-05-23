# frozen_string_literal: true

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    def initialize
      @tables = {}
      @data = {}
      @tables_mutex = Mutex.new
    end

    def create_table(name, columns)
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        @data[name] = []
        true
      end
    end

    def drop_table(name)
      @tables_mutex.synchronize do
        return false unless @tables.key?(name)

        @tables.delete(name)
        @data.delete(name)
        true
      end
    end

    def insert(table_name, values)
      @tables_mutex.synchronize do
        columns = @tables[table_name]
        return false unless columns
        return false unless values.size == columns.size

        @data[table_name] << values.dup
        true
      end
    end

    def update_rows_with_where(table_name, where_clauses, col_idx, new_value)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        columns = @tables[table_name]
        rows = @data[table_name]

        indices = rows.each_with_index.select do |row, _idx|
          match_row?(row, columns, where_clauses)
        end.map(&:last)

        indices.each { |idx| rows[idx][col_idx] = new_value }
        true
      end
    end

    def delete_rows_with_where(table_name, where_clauses)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        columns = @tables[table_name]
        rows = @data[table_name]

        indices = rows.each_with_index.select do |row, _idx|
          match_row?(row, columns, where_clauses)
        end.map(&:last)

        indices.sort.reverse_each { |idx| rows.delete_at(idx) }
        true
      end
    end

    def select(table_name)
      @tables_mutex.synchronize do
        @data[table_name] || []
      end
    end

    def get_columns(table_name)
      @tables_mutex.synchronize do
        @tables[table_name]
      end
    end

    def list_tables
      @tables_mutex.synchronize do
        @tables.keys
      end
    end

    private

    def match_row?(row, columns, where_clauses)
      where_clauses.all? { |clause| match_clause?(row, columns, clause) }
    end

    def match_clause?(row, columns, clause)
      c_idx = clause[:col_idx] || columns.index(clause[:column])
      return false unless c_idx

      val = row[c_idx]
      return false if val.nil?

      compare_values(val, clause)
    end

    def compare_values(val, clause)
      if clause[:operator] == 'LIKE'
        clause[:regex] ? clause[:regex].match?(val.to_s) : match_like?(val, clause[:value])
      else
        match_standard?(val, clause[:operator], clause[:value])
      end
    end

    def match_like?(val, pattern_value)
      pattern = Regexp.escape(pattern_value.to_s).gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE).match?(val.to_s)
    end

    def match_standard?(val, operator, target_value)
      method = operator == '=' ? :== : operator.to_sym
      val.public_send(method, target_value)
    end
  end
end
