import os
import sys
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

# 1. APIキーの確認
api_key = os.environ.get("GEMINI_API_KEY")
if not api_key:
    print("Error: GEMINI_API_KEY is not set.")
    sys.exit(1)

# 2. AIに返してほしいJSONの構造を定義（これで絶対パースエラーが起きなくなる）
class GitHubIssue(BaseModel):
    title: str = Field(description="Issue のタイトル")
    body: str = Field(description="Markdown形式の本文。必ず「#### 概要、#### 実装のポイント、#### 期待される動作、#### テスト計画」のセクションを含めること")

# 3. クライアントの初期化
client = genai.Client(api_key=api_key)

# 4. コンテキスト（ソースコード）の読み込み
try:
    with open("repomix-output.xml", "r", encoding="utf-8") as f:
        repo_code = f.read()
except FileNotFoundError:
    print("Error: repomix-output.xml not found.")
    sys.exit(1)

# 5. 指示の組み立て
user_input = os.environ.get("USER_INPUT", "")
if not user_input:
    instruction = "現在の lib/ および spec/ の実装状況を分析し、MySQL 8.0 互換性を高めるために次に実装すべき最適なタスクを1つ特定して、GitHub Issue を作成してください。"
else:
    instruction = f"指示: {user_input} に基づき、GitHub Issue の内容を作成してください。"

full_prompt = f"""あなたは優秀なテックリードです。以下のソースコードのコンテキストを元に、条件に沿った GitHub Issue を作成してください。

【指示】
{instruction}

【ソースコード】
{repo_code}

【条件】
* 出力する文章は、必ず「日本語」で作成してください。
* Aider が一度の開発で迷子にならない小規模な内容にすること。
* まだ実装されていない機能や、リファクタリングのどちらかにすること。
* 回答を導き出す前に、リポジトリ全体のコードの依存関係と、MySQL の挙動を、頭の中でステップ・バイ・ステップで極限まで深く推論・シミュレーションし、最適なものを選ぶこと。
"""

print("Gemini API にリクエストを送信中...")

# 6. API呼び出し
try:
    response = client.models.generate_content(
        model="gemma-4-31b-it",
        contents=full_prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=GitHubIssue,
            temperature=0.2, # 意図しないブレを減らす
        ),
    )
    
    # 成果物を issue.json として保存（Geminiが保証した綺麗なJSONがそのまま入る）
    with open("issue.json", "w", encoding="utf-8") as f:
        f.write(response.text)
        
    print("Success: issue.json が正常に生成されました。")

except Exception as e:
    print(f"API Error: {e}")
    sys.exit(1)
