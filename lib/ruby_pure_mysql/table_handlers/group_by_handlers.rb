# frozen_string_literal: true

module RubyPureMysql
  # GROUP BY 句の集計および結果送信を支援するモジュール
  module GroupByHandlers
    def compute_grouped_rows(columns, result, grouped, group_indices)
      grouped.map do |group_val, group_rows|
        compute_group_row(columns, result, group_val, group_rows, group_indices)
      end
    end

    def filter_grouped_by_having(grouped, having_clauses, group_ctx)
      grouped.select do |group_val, group_rows|
        evaluate_group_having(group_val, group_rows, having_clauses, group_ctx)
      end
    end

    def evaluate_group_having(group_val, group_rows, having_clauses, group_ctx)
      return true if having_clauses.nil?

      # having_clauses が空の配列や空の文字列である場合に true を返さないよう厳格にチェック
      return true if having_clauses.respond_to?(:empty?) && having_clauses.empty?

      evaluate_having_ast(group_val, group_rows, having_clauses, group_ctx)
    end


    def finalize_and_send_group_results(client, result, res_rows)
      res_rows = apply_order_by(client, result[:order], result[:columns], res_rows) if result[:order]
      return if res_rows.nil?

      res_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, res_rows, result[:columns])
    end

    def compute_group_row(columns, result, group_val, group_rows, group_indices)
      result[:columns].each_with_index.map do |col, idx|
        agg = result[:aggregates]&.find { |a| a[:index] == idx }
        if agg
          compute_aggregate_for_group(columns, agg, group_rows)
        else
          resolve_group_column_value(columns, col[:original], group_val, group_rows, group_indices)
        end
      end
    end
  end
end
