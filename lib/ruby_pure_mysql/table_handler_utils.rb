# frozen_string_literal: true

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    def validate_table(client, table_name)
      columns = @storage_engine.get_columns(table_name)
      unless columns
        send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146)
        return nil
      end
      columns
    end

    def get_column_index(client, columns, column_name)
      idx = columns.index(column_name)
      unless idx
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054)
        return nil
      end
      idx
    end

    def find_matching_indices(client, rows, table_columns, where_clauses)
      return (0...rows.size).to_a unless where_clauses

      rows.each_with_index.select do |row, _idx|
        where_clauses.all? do |clause|
          col_idx = get_column_index(client, table_columns, clause[:column])
          return nil unless col_idx

          apply_filter(row[col_idx], clause[:operator], clause[:value])
        end
      end.map(&:last)
    end

    def apply_filter(val, operator, target_value, compiled_regex = nil)
      if operator == 'LIKE'
        compiled_regex ||= build_like_regex(target_value)
        compiled_regex.match?(val.to_s)
      else
        # 既存の比較演算子
        method = operator == '=' ? :== : operator.to_sym
        val.public_send(method, target_value)
      end
    end

    def build_like_regex(target_value)
      escaped = Regexp.escape(target_value.to_s)
      pattern = escaped.gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE)
    end

    def apply_order_by(client, order_by, table_columns, rows)
      col_idx = get_column_index(client, table_columns, order_by[:column])
      return nil unless col_idx

      # ソート実行
      # MySQL 8.0 の挙動に合わせる: ASC は NULLS FIRST, DESC は NULLS LAST
      sorted_rows = rows.sort_by { |row| [row[col_idx].nil? ? 0 : 1, row[col_idx]] }
      sorted_rows.reverse! if order_by[:direction] == :DESC
      sorted_rows
    end
  end
end
