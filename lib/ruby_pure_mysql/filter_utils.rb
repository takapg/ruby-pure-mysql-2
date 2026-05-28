# frozen_string_literal: true

module RubyPureMysql
  # フィルタリングおよびWHERE句のコンパイルを支援するモジュール
  module FilterUtils
    def build_like_regex(target_value)
      escaped = Regexp.escape(target_value.to_s)
      pattern = escaped.gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE)
    end

    def compile_where_clauses(client, table_columns, ast, table_map = {})
      return nil if ast.nil?

      if ast.is_a?(Hash) && ast[:op]
        left = compile_where_clauses(client, table_columns, ast[:left], table_map)
        right = compile_where_clauses(client, table_columns, ast[:right], table_map)
        return nil if left.nil? || right.nil?

        { op: ast[:op], left: left, right: right }
      else
        col_idx = get_column_index(client, table_columns, ast[:column], table_map)
        return nil unless col_idx

        regex = ast[:operator] == 'LIKE' ? build_like_regex(ast[:value]) : nil
        { col_idx: col_idx, operator: ast[:operator], value: ast[:value], regex: regex }
      end
    end
  end
end
