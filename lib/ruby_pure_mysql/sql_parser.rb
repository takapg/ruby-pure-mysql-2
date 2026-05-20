# frozen_string_literal: true

module RubyPureMysql
  class SqlParser
    def self.parse(query)
      # SELECT <式>; を解析 (大文字小文字無視)
      match = query.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: "Invalid SQL" } unless match

      expression = match[1]

      # 簡易的な算術演算（数字と+のみ）に対応
      if expression =~ /\A\d+(\s*\+\s*\d+)*\z/
        result = expression.split('+').map(&:strip).map(&:to_i).sum
        { result: result }
      else
        { error: "Unsupported expression" }
      end
    end
  end
end
