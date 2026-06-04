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
      when :string  then val.to_s
      else val
      end
    end

    def cast_to_numeric(val, method)
      return nil if val.nil?

      val.is_a?(Numeric) ? val.send(method) : val.to_s.send(method)
    end

    def determine_base_types(rows)
      return [] if rows.nil? || rows.empty?

      num_cols = rows.first.size
      (0...num_cols).map { |col_idx| resolve_column_type(rows, col_idx) }
    end

    private

    def resolve_column_type(rows, col_idx)
      # 全ての非NULL値をチェックして、最も汎用的な型を決定する
      # 優先順位: String > Float > Integer
      types = rows.filter_map { |row| map_value_to_type(row[col_idx]) }
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
