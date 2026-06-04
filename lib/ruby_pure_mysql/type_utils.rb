# frozen_string_literal: true

module RubyPureMysql
  # 型の決定と正規化を支援するモジュール
  module TypeUtils
    def normalize_value_by_type(val, type)
      # NULL (nil) は型に関わらず同一のものとして扱う (NULLマーカー)
      return nil if val.nil?
      return val if type.nil?

      case type
      when :integer then cast_to_numeric(val, :to_i)
      when :float   then cast_to_numeric(val, :to_f)
      when :string
        # 数値の 1.0 と 1 が異なる文字列 ("1.0" vs "1") になり
        # DISTINCT で重複排除されないのを防ぐため、整数値は整数形式にする
        val.is_a?(Numeric) ? (val == val.to_i ? val.to_i.to_s : val.to_s) : val.to_s
      else val
      end
    end

    def cast_to_numeric(val, method)
      return nil if val.nil?
      return val.send(method) if val.is_a?(Numeric)

      # 文字列が数値形式である場合のみキャストし、それ以外は元の値を返す
      # これにより 'abc' が 0 に変換されて 0 と同一視されるのを防ぐ
      str = val.to_s
      if str.match?(/\A[-+]?\d*\.?\d+([eE][-+]?\d+)?\z/)
        str.send(method)
      else
        val
      end
    end

    def ensure_rows_array(rows)
      return [] if rows.nil?
      return rows if rows.empty?

      # 最初の要素が配列またはRowオブジェクトでない場合は、
      # rows全体を「1つの行」として扱うため、配列でラップする
      unless rows.first.respond_to?(:values) || rows.first.is_a?(Array)
        return [rows]
      end

      rows
    end

    def extract_row_values(row)
      row.respond_to?(:values) ? row.values : (row.is_a?(Array) ? row : [row])
    end

    def determine_base_types(rows)
      rows = ensure_rows_array(rows)
      return [] if rows.empty?

      vals = extract_row_values(rows.first)
      (0...vals.size).map { |col_idx| resolve_column_type(rows, col_idx) }
    end

    private

    def resolve_column_type(rows, col_idx)
      # 全ての非NULL値をチェックして、最も汎用的な型を決定する
      # 優先順位: String > Float > Integer
      types = rows.filter_map do |row|
        val = row.respond_to?(:values) ? row.values[col_idx] : row[col_idx]
        map_value_to_type(val)
      end
      return :string if types.include?(:string)
      return :float if types.include?(:float)
      return :integer if types.include?(:integer)

      nil
    end

    def map_value_to_type(val)
      case val
      when Integer then :integer
      when Float   then :float
      when String  then :string
      end
    end
  end
end
