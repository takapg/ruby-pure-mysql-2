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
      return nil if where_clauses.nil? || where_clauses.empty?
      compile_ast_node(client, table_columns, where_clauses, table_map)
    end

    private

    def compile_ast_node(client, table_columns, node, table_map)
      if node.is_a?(Hash) && node[:op] == :and
        left = compile_ast_node(client, table_columns, node[:left], table_map)
        right = compile_ast_node(client, table_columns, node[:right], table_map)
        return nil unless left && right

        { op: :and, left: left, right: right }
      elsif node.is_a?(Hash) && node[:op] == :or
        left = compile_ast_node(client, table_columns, node[:left], table_map)
        right = compile_ast_node(client, table_columns, node[:right], table_map)
        return nil unless left && right

        { op: :or, left: left, right: right }
      else
        col_idx = get_column_index(client, table_columns, node[:column], table_map)
        return nil unless col_idx

        regex = node[:operator] == 'LIKE' ? build_like_regex(node[:value]) : nil
        { col_idx: col_idx, operator: node[:operator], value: node[:value], regex: regex }
      end
    end
  end
end
