# ... 既存コード ...

def handle_select(client, result)
  columns = validate_table(client, result[:table_name])
  return unless columns

  # 集計クエリの処理を追加
  if result[:aggregate] == :count
    rows = fetch_and_filter_rows(client, columns, result)
    return if rows.nil?
    
    count = rows.size
    send_selected_columns(client, [count], columns, ['COUNT(*)'])
    return
  end

  rows = fetch_and_filter_rows(client, columns, result)
  send_selected_columns(client, rows, columns)
end
