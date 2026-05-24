# frozen_string_literal: true

module RubyPureMysql
  # テーブル操作に関連するユーティリティメソッド
  module TableHandlerUtils
    def send_column_definitions(client, count, columns, values)
      # 実装はクライアントへのパケット送信
      raise NotImplementedError, 'send_column_definitions is not implemented'
    end

    def send_row_data(client, sequence_id, row)
      raise NotImplementedError, 'send_row_data is not implemented'
    end

    def send_eof(client, sequence_id)
      raise NotImplementedError, 'send_eof is not implemented'
    end

    def send_err_packet(client, sequence_id, message, error_code)
      raise NotImplementedError, 'send_err_packet is not implemented'
    end

    def send_result_set(client, rows, columns)
      raise NotImplementedError, 'send_result_set is not implemented'
    end

    def compile_where_clauses(client, columns, where)
      raise NotImplementedError, 'compile_where_clauses is not implemented'
    end
  end
end
