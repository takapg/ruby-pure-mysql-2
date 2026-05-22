# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist",