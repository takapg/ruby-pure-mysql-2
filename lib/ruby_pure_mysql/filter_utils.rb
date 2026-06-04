# frozen_string_literal: true

module RubyPureMysql
  # フィルタリングおよびWHERE句のコンパイルを支援するモジュール
  module FilterUtils
    def build_like_regex(target_value)
      result, escaped = +'', false
      target_value.to_s.each_char do |char|
        res, escaped = translate_like_char(char, escaped)
        result << res
      end
      result << Regexp.escape('\\') if escaped
      Regexp.new("\\A#{result}\\z", Regexp::IGNORECASE)
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

    private

    def translate_like_char(char, escaped)
      return [Regexp.escape(char), false] if escaped
      return ['', true] if char == '\\'
      return ['.*', false] if char == '%'
      return ['.', false] if char == '_'
      [Regexp.escape(char), false]
    end
  end
end
