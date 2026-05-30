# frozen_string_literal: true

module RubyPureMysql
  # フィルタリングおよびWHERE句のコンパイルを支援するモジュール
  module FilterUtils
    def build_like_regex(target_value)
      escaped = Regexp.escape(target_value.to_s)
      pattern = escaped.gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE)
    end

    def compile_where_clauses(client, table_columns, where_clauses, table_map = {})
      where_clauses.map do |clause|
        col_idx = get_column_index(client, table_columns, clause[:column], table_map)
        return nil unless col_idx

        regex = compile_regex(clause[:operator], clause[:value])
        { col_idx: col_idx, operator: clause[:operator], value: clause[:value], regex: regex }
      end
    end

    def compile_regex(operator, value)
      case operator
      when 'LIKE' then build_like_regex(value)
      when 'REGEXP', 'RLIKE' then Regexp.new(value.to_s, Regexp::IGNORECASE)
      end
    end
  end
end
