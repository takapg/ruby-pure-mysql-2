# frozen_string_literal: true

require_relative 'column_utils'

module RubyPureMysql
  # 結果セットの投影（カラム選択）と制限（LIMIT/OFFSET）を支援するモジュール
  module ProjectionUtils
    include ColumnUtils

    def apply_offset_and_limit(rows, result)
      rows.drop(result[:offset] || 0).then { |r| result[:limit] ? r.first(result[:limit]) : r }
    end

    def project_rows(client, rows, columns, selected_columns, table_map = {})
      return [rows, columns] if selected_columns.nil? || selected_columns.any? { |c| c[:original] == '*' }

      indices = selected_columns.map { |c| get_column_index(client, columns, c[:original], table_map) }
      return nil if indices.any?(&:nil?)

      [project_data(rows, indices), selected_columns]
    end

    def project_data(rows, indices)
      rows.map { |row| indices.map { |idx| row[idx] } }
    end

    def project_column_names(selected_columns)
      selected_columns.map { |c| c[:alias] || c[:original].split('.').last }
    end
  end
end
