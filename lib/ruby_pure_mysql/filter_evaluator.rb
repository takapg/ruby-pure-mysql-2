# frozen_string_literal: true

module RubyPureMysql
  # フィルタリング条件の評価ロジックを提供するモジュール
  module FilterEvaluator
    def apply_filter(val, operator, target_value, regex = nil)
      return val.nil? if operator == 'IS NULL'
      return !val.nil? if operator == 'IS NOT NULL'
      return false if val.nil? && operator != 'IS NULL'

      return regex.match?(val.to_s) if regex.is_a?(Regexp)

      compare_value(val, operator, target_value)
    rescue StandardError
      false
    end

    def compare_value(val, operator, target_value)
      case operator
      when 'LIKE' then match_pattern?(val, target_value, :like)
      when 'REGEXP', 'RLIKE' then match_pattern?(val, target_value, :regexp)
      when 'IN' then handle_in_operator(val, target_value)
      when 'BETWEEN', 'NOT BETWEEN' then handle_between_operator?(val, operator, target_value)
      when '=', '!=', '<>' then compare_equality?(val, operator, target_value)
      else compare_generic_operator(val, operator, target_value)
      end
    end

    def match_pattern?(val, target, type)
      return target.match?(val.to_s) if target.is_a?(Regexp)

      (type == :like ? build_like_regex(target) : Regexp.new(target.to_s, Regexp::IGNORECASE)).match?(val.to_s)
    end

    def match_between?(val, operator, target)
      operator == 'BETWEEN' ? val.between?(*target) : !val.between?(*target)
    end

    def row_matches_compiled_groups?(row, compiled_groups)
      compiled_groups.any? do |group|
        group.all? do |c|
          apply_filter(row[c[:col_idx]], c[:operator], c[:value], c[:regex])
        end
      end
    end

    private

    def compare_equality?(val, operator, target_value)
      v1, v2 = normalize_for_comparison(val, target_value)
      operator == '=' ? v1 == v2 : v1 != v2
    end

    def compare_generic_operator(val, operator, target_value)
      v1, v2 = normalize_for_comparison(val, target_value)
      begin
        v1.public_send(operator.to_sym, v2)
      rescue StandardError
        false
      end
    end

    def handle_in_operator(val, target_value)
      return target_value.include?(val) unless val.is_a?(Numeric)

      target_value.any? { |t| cast_to_numeric(t).is_a?(Numeric) && cast_to_numeric(t) == val }
    end

    def handle_between_operator?(val, operator, target_value)
      if val.is_a?(Numeric)
        normalized_target = target_value.map { |t| cast_to_numeric(t) }
        return false if normalized_target.any? { |t| !t.is_a?(Numeric) }

        begin
          return match_between?(val, operator, normalized_target)
        rescue StandardError
          return false
        end
      end
      match_between?(val, operator, target_value)
    end

    def normalize_for_distinct(value)
      value.nil? ? :null : value.to_s
    end

    def normalize_for_comparison(val1, val2)
      return [val1, val2] if val1.nil? || val2.nil?
      return [val1, val2] unless val1.is_a?(Numeric) || val2.is_a?(Numeric)

      n1 = cast_to_numeric(val1)
      n2 = cast_to_numeric(val2)
      n1.is_a?(Numeric) && n2.is_a?(Numeric) ? [n1, n2] : [val1, val2]
    end

    def cast_to_numeric(val)
      return val if val.is_a?(Numeric)
      return nil if val.nil?

      val.to_s.to_f
    end
  end
end
