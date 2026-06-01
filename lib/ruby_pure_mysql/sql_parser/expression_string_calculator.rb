# frozen_string_literal: true

module RubyPureMysql
  # 文字列結合の計算ロジックを提供するモジュール
  module ExpressionStringCalculator
    include ExpressionCommon

    def apply_string_concatenation(tokens)
      return nil if tokens.empty?

      index = 1
      while index < tokens.size
        if tokens[index] == '||'
          process_concat_op!(tokens, index)
          next
        end
        index += 1
      end
      tokens[0]
    end

    def process_concat_op!(tokens, index)
      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]
      return if left_raw.nil? || right_raw.nil?

      tokens[index - 1] = "#{format_for_concat(left_raw)}#{format_for_concat(right_raw)}"
      tokens.slice!(index, 2)
    end
  end
end
