# ruby-pure-mysql-2

Ruby による MySQL プロトコルおよびストレージエンジンの純粋な再実装プロジェクト。

## プロジェクトの目的

- MySQL の理解と実装。
- 外部の C 拡張に頼らない、Ruby のみによる MySQL 互換サーバーの構築。
- RSpec を用いた本物の MySQL との互換性テストの実施。

## 技術スタック

- **Language:** Ruby
- **Test:** RSpec (Comparison with real MySQL 8.0)
- **CI:** GitHub Actions
- **Environment:** Docker Compose (for real MySQL)
