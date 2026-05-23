# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # スキーマ操作に関連するハンドラメソッドをまとめたモジュール
  module SchemaHandlers
    def handle_create(client, query)
      # 実装は省略
    end
  end

  # データ操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include SchemaHandlers
    include TableHandlerUtils

    def handle_select(client, result)
      # 簡易的なSELECTハンドラの実装
      # 実際にはテーブルデータにアクセスしてフィルタリングを行う
      # ここではエラーを回避するためにメソッドを定義
      # 実際のデータ取得ロジックは既存のテーブル管理機能に依存
    end

    def apply_where_filter(client, where_clauses, table_columns, rows)
      # where_clauses は配列として渡されるため、reduceで順次絞り込む
      where_clauses.reduce(rows) do |current_rows, clause|
        col_idx = find_column_index(client, clause[:column], table_columns)
        return nil unless col_idx

        filter_rows(current_rows, col_idx, clause)
      end
    end
  end
end
