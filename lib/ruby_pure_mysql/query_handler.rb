# frozen_string_literal: true

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless columns

      if result[:values].size != columns.size
        return send_err_packet(client, 1, 'Column count doesn\'t match value count at row 1', 1136)
      end

      @storage_engine.insert(result[:table_name], result[:values])
      send_ok_packet(client, 1)
    end

    def handle_update(client, result)
      columns = validate_table_and_where(client, result)
      return unless columns

      col_idx = get_column_index(client, columns, result[:column])
      return unless col_idx

      where_col_idx = get_column_index(client, columns, result[:where][:column])
      return unless where_col_idx

      @storage_engine.update(result[:table_name], col_idx, result[:value], where_col_idx, result[:where][:value])
      send_ok_packet(client, 1)
    end

    def handle_delete(client, result)
      columns = validate_table_and_where(client, result)
      return unless columns

      where_col_idx = get_column_index(client, columns, result[:where][:column])
      return unless where_col_idx

      @storage_engine.delete(result[:table_name], where_col_idx, result[:where][:value])
      send_ok_packet(client, 1)
    end

    def handle_select(client, result)
      table_columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless table_columns

      rows = @storage_engine.select(result[:table_name])
      rows = apply_where_filter(client, result[:where], table_columns, rows) if result[:where]
      return unless rows

      send_select_result(client, result, rows, table_columns)
    end

    def send_select_result(client, result, rows, table_columns)
      if result[:columns] == ['*']
        send_result_set(client, rows, table_columns)
      else
        handle_projection(client, result, rows, table_columns)
      end
    end

    def apply_where_filter(client, where_clause, table_columns, rows)
      col_idx = table_columns.index(where_clause[:column])
      unless col_idx
        send_err_packet(client, 1, "Unknown column '#{where_clause[:column]}' in WHERE clause", 1054)
        return nil
      end

      rows.select { |row| row[col_idx] == where_clause[:value] }
    end

    def handle_projection(client, result, rows, table_columns)
      indices = result[:columns].map { |col| table_columns.index(col) }

      if indices.include?(nil)
        send_err_packet(client, 1, 'Unknown column in field list', 1054)
        return
      end

      projected_rows = rows.map { |row| indices.map { |i| row[i] } }
      send_result_set(client, projected_rows, result[:columns])
    end

    def handle_create_table(client, result)
      if @storage_engine.create_table(result[:table_name], result[:columns]) || result[:if_not_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' already exists", 1050)
      end
    end

    def handle_drop_table(client, result)
      if @storage_engine.drop_table(result[:table_name]) || result[:if_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Unknown table '#{result[:table_name]}'", 1051)
      end
    end

    private

    def validate_table_and_where(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      unless columns
        send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146)
        return nil
      end

      unless result[:where]
        send_err_packet(client, 1, 'WHERE clause is required', 1064)
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
  end

  # クエリのハンドリングを行うモジュール
  module QueryHandler
    include TableHandlers

    def handle_query(client, packet_body)
      sql = packet_body[1..].strip
      query_type = sql.split(/\s+/, 2).first&.upcase
      RubyPureMysql.logger.info "Received Query type: #{query_type}"

      result = SqlParser.parse(sql)

      if result[:error]
        send_err_packet(client, 1, result[:error])
      else
        dispatch_query(client, result)
      end
    end

    def dispatch_query(client, result)
      case result[:type]
      when :create_table then handle_create_table(client, result)
      when :drop_table   then handle_drop_table(client, result)
      when :insert       then handle_insert(client, result)
      when :update       then handle_update(client, result)
      when :delete       then handle_delete(client, result)
      when :select_from  then handle_select(client, result)
      else send_result_set(client, result[:result], result[:columns])
      end
    end
  end
end
