# frozen_string_literal: true

module RubyPureMysql
  # カラム名の解決とインデックス取得を支援するモジュール
  module ColumnUtils
    def get_column_index(client, columns, column_name, table_map = {})
      column_name = column_name.to_s.strip
      return resolve_qualified_column(client, column_name, table_map) if column_name.include?('.')
      return resolve_unqualified_column(client, columns, column_name, table_map) if table_map && !table_map.empty?

      resolve_from_all_columns(client, columns, column_name)
    end

    def resolve_qualified_column(client, column_name, table_map)
      table, col = column_name.split('.')
      return nil unless validate_table_exists?(client, table, table_map)

      offset = calculate_table_offset(table, table_map)
      col_idx = find_column_index(client, table, col, table_map)
      return nil unless col_idx

      offset + col_idx
    end

    def validate_table_exists?(client, table, table_map)
      return true if table_map&.key?(table)

      send_err_packet(client, 1, "Unknown table '#{table}'", 1146) if client
      false
    end

    def find_column_index(client, table, col, table_map)
      idx = table_map[table].find_index { |c| (c.is_a?(Hash) ? (c[:name] || c[:original]) : c)&.casecmp?(col) }
      return idx if idx

      send_err_packet(client, 1, "Unknown column '#{col}' in table '#{table}'", 1054) if client
      nil
    end

    def resolve_unqualified_column(client, columns, column_name, table_map)
      table_map.each do |t, cols|
        idx = cols.find_index { |c| (c.is_a?(Hash) ? (c[:name] || c[:original]) : c)&.casecmp?(column_name) }
        next unless idx

        return calculate_table_offset(t, table_map) + idx
      end
      resolve_from_all_columns(client, columns, column_name)
    end

    def resolve_from_all_columns(client, columns, column_name)
      idx = columns.find_index do |c|
        name = c.is_a?(Hash) ? (c[:name] || c[:original]) : c
        name&.casecmp?(column_name)
      end
      unless idx
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054) if client
        return nil
      end
      idx
    end

    def calculate_table_offset(table, table_map)
      offset = 0
      table_map.each do |t, cols|
        break if t == table

        offset += cols.size
      end
      offset
    end

    def validate_selected_columns?(client, columns, selected_columns, table_map = {})
      selected_columns.all? { |col| !get_column_index(client, columns, col, table_map).nil? }
    end
  end
end
