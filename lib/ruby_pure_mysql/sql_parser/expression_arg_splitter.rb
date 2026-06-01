# frozen_string_literal: true

module RubyPureMysql
  # 式の引数分割ロジックを提供するモジュール
  module ExpressionArgSplitter
    include ExpressionCommon

    def split_args(args_str)
      return [] if args_str.nil? || args_str.strip.empty?

      state = { args: [], current_arg: +'', depth: 0, quote: nil }
      args_str.each_char.with_index do |char, i|
        update_split_state(char, i, args_str, state)
      end
      state[:args] << state[:current_arg].strip
      state[:args]
    end

    def update_split_state(char, index, args_str, state)
      return handle_split_quote_state(char, index, args_str, state) if state[:quote]
      return handle_split_quote_start(char, state) if ["'", '"'].include?(char)
      return handle_split_bracket_state(char, state) if ['(', ')'].include?(char)
      return handle_split_comma(state) if char == ',' && state[:depth].zero?

      state[:current_arg] << char
    end

    def handle_split_quote_state(char, index, args_str, state)
      state[:quote] = nil if char == state[:quote] && (index.zero? || args_str[index - 1] != '\\')
      state[:current_arg] << char
    end

    def handle_split_quote_start(char, state)
      state[:quote] = char
      state[:current_arg] << char
    end

    def handle_split_bracket_state(char, state)
      char == '(' ? state[:depth] += 1 : state[:depth] -= 1
      state[:current_arg] << char
    end

    def handle_split_comma(state)
      state[:args] << state[:current_arg].strip
      state[:current_arg] = +''
    end
  end
end
