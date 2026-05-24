# frozen_string_literal: true

RSpec.shared_examples 'MySQL-Compatible Server' do |port|
  let(:client) do
    # spec_helper で起動したサーバーに接続
    RubyPureMysql::Client.new('127.0.0.1', port)
  end

  it 'responds to the MySQL protocol' do
    expect(client).to be_a(RubyPureMysql::Client)
    # ハンドシェイクが成功することを簡易的に確認
    expect { client.connect }.not_to raise_error
  end
end
