# frozen_string_literal: true

module RubyPureMysql
  # フィルタリングおよびWHERE句のコンパイルを支援するモジュール
  module FilterUtils
    def build_like_regex(target_value)
      escaped = Regexp.escape(target_value.to_s)
      pattern = escaped.gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE)
    end

    def compile_where_clauses(client, table_columns, where_clauses)
      where_clauses.map do |clause|
        col_idx = table_columns.index(clause[:column])
        unless col_idx
          send_err_packet(client, 1, "Unknown column '#{clause[:column]}'", 1054)
          return nil
        end
        regex = clause[:operator] == 'LIKE' ? build_like_regex(clause[:value]) : nil
        { col_idx: col_idx, operator: clause[:operator], value: clause[:value], regex: regex }
      end
    end
  end
end
