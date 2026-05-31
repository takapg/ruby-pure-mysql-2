# frozen_string_literal: true

module RubyPureMysql
  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    def tokenize_math(col)
      col.scan(%r{[-+]?\d*\.?\d+|\w+\(.*\)|[+*/-]}).map do |t|
        if t.match?(%r{[+*/-]}) && t.length == 1
          t
        elsif t.match?(/\A\w+\(.*\)\z/)
          val = evaluate_expression(t)
          val.is_a?(Numeric) ? val.to_f : val.to_s.to_f
        else
          t.to_f
        end
      end
    end

    def split_args(args_str)
      args = []
      buf = +''
      depth = 0

      args_str.each_char do |c|
        depth = adjust_depth(c, depth)
        if comma_at_root?(c, depth)
          args << buf.strip
          buf = +''
        else
          buf << c
        end
      end
      args << buf.strip unless buf.strip.empty?
      args
    end

    private

    def adjust_depth(c, depth)
      return depth + 1 if c == '('
      return depth - 1 if c == ')' && depth.positive?
      depth
    end

    def comma_at_root?(c, depth)
      c == ',' && depth.zero?
    end
  end
end
