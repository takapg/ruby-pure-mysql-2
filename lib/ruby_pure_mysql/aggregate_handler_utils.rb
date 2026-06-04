# frozen_string_literal: true

module RubyPureMysql
  # 集計クエリのハンドリングを支援するモジュール
  module AggregateHandlerUtils
    def handle_aggregate(client, columns, result)
      # 集計のために全行を取得（LIMIT/OFFSETを無視して集計する）
      rows = fetch_and_filter_rows(client, columns, result.merge(limit: nil, offset: nil, order: nil)) || []

      res_row = build_aggregate_row(rows, columns, result)
      return send_err_packet(client, 1, 'Error executing aggregate query', 1105) if res_row == :error

      # 集計結果は最大1行。この1行に対して LIMIT/OFFSET を適用する
      res_rows = [res_row]
      final_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, final_rows, result[:columns])
    end

    def build_aggregate_row(rows, columns, result)
      result[:columns].each_with_index.map do |col, idx|
        agg = result[:aggregates].find { |a| a[:index] == idx }
        if agg
          val = compute_single_aggregate_value(rows, columns, agg)
          return :error if val == :error

          val
        else
          resolve_aggregate_non_col(rows, columns, col)
        end
      end
    end
  end
end
