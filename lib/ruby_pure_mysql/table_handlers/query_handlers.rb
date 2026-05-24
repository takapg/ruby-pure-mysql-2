# frozen_string_literal: true

module RubyPureMysql
  # SELECTクエリの処理を担当するモジュール
  module QueryHandlers
    def handle_select(client, result)
      # resultがハッシュであることを確認
      return unless result.is_a?(Hash)

      columns = validate_table(client, result[:table_name])
      return unless columns

      if result[:aggregate] == :count
        rows = fetch_and_filter_rows(client, columns, result)
        return if rows.nil?

        count = rows.size
        send_selected_columns(client, [count], columns, ['COUNT(*)'])
        return
      end

      # 通常のSELECT処理
      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      send_selected_columns(client, rows, columns, result[:columns])
    end

    private

    def fetch_and_filter_rows(client, columns, result)
      table_name = result[:table_name]
      where_clauses = prepare_where_clauses(client, columns, result[:where])
      order_by = result[:order_by]
      limit = result[:limit]
      offset = result[:offset]

      rows = @storage_engine.select(table_name)

      # WHERE句の適用
      unless where_clauses.empty?
        rows = rows.select do |row|
          match_row?(row, columns, where_clauses)
        end
      end

      # ORDER BY句の適用
      unless order_by.nil?
        rows = apply_order_by(client, order_by, columns, rows)
      end

      # LIMITとOFFSETの適用
      unless limit.nil?
        offset ||= 0
        rows = rows[offset, limit] || []
      end

      rows
    end
  end
end
