# frozen_string_literal: true

module RubyPureMysql
  # フィルタリングおよびWHERE句のコンパイルを支援するモジュール
  module FilterUtils
    def build_like_regex(target_value)
      str = target_value.to_s
      result = +''
      escaped = false
      str.each_char do |char|
        if escaped
          # エスケープされた文字はすべてリテラルとして扱う
          result << Regexp.escape(char)
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '%'
          result << '.*'
        elsif char == '_'
          result << '.'
        else
          result << Regexp.escape(char)
        end
      end
      # 末尾にバックスラッシュが残った場合はリテラルとして扱う
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
  end
end
