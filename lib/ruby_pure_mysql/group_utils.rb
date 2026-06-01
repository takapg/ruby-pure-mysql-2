# frozen_string_literal: true

module RubyPureMysql
  # グループ化処理の補助ロジックを提供するモジュール
  module GroupUtils
    def group_rows_by_indices(rows, indices)
      return { [] => rows } if indices.empty?

      rows.group_by { |row| indices.map { |idx| row[idx] } }
    end

    def group_computation_failed?(res_rows)
      res_rows.nil? || res_rows.any? { |row| row.include?(:error) }
    end

    def handle_group_by_error(client)
      send_err_packet(client, 1, 'Error executing GROUP BY query', 1105)
    end

    def get_group_column_indices(client, columns, group_by_cols, table_map)
      group_by_cols.split(',').map do |col_name|
        idx = get_column_index(client, columns, col_name.strip, table_map)
        return nil if idx.nil?

        idx
      end
    end
  end
end
