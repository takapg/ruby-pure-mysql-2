# ... 既存コード ...

def parse_select_from(query)
  match = query.match(SELECT_REGEX)
  return { error: 'Invalid SELECT syntax' } unless match

  result = { type: :select_from, table_name: match[2], columns: match[1].split(',').map(&:strip) }
  parse_select_clauses(result, match)
end

# ... 他のメソッド ...

# parse_select_clauses メソッドの末尾に COUNT(*) 検出ロジックを追加
def parse_select_clauses(result, match)
  if match[3]
    where_res = parse_where_clause_into(result, match[3])
    return where_res if where_res.is_a?(Hash) && where_res[:error]
  end
  parse_order_by_clause(result, match[4], match[5]) if match[4]
  parse_limit_offset_clause(result, match[6], match[7])
  
  # COUNT(*) の検出を追加
  if result[:columns].size == 1 && result[:columns][0].upcase == 'COUNT(*)'
    result[:aggregate] = :count
  end

  result
end
