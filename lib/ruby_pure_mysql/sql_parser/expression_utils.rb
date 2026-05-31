# frozen_string_literal: true

module RubyPureMysql
  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    def tokenize_math(col)
      tokens = []
      col.scan(%r{[-+]?\d*\.?\d+|\w+\((?:[^()]*|\([^()]*\))*\)|[+*/-]}).each do |t|
        if t.match?(%r{[+*/-]}) && t.length == 1
          tokens << t
        elsif t.match?(/\A\w+\(.*\)\z/)
          val = evaluate_expression(t)
          return :error if val == :error
          tokens << (val.is_a?(Numeric) ? val.to_f : val.to_s.to_f)
        else
          tokens << t.to_f
        end
      end
      tokens
    end

    def split_args(args_str)
      state = { args: [], buf: +'', depth: 0 }
      args_str.each_char { |char| update_state(state, char) }
      state[:args] << state[:buf].strip unless state[:buf].strip.empty?
      state[:args]
    end

    private

    def update_state(state, char)
      state[:depth] = adjust_depth(char, state[:depth])
      if comma_at_root?(char, state[:depth])
        state[:args] << state[:buf].strip
        state[:buf] = +''
      else
        state[:buf] << char
      end
    end

    def adjust_depth(char, depth)
      return depth + 1 if char == '('
      return depth - 1 if char == ')' && depth.positive?

      depth
    end

    def comma_at_root?(char, depth)
      char == ',' && depth.zero?
    end
  end
end
