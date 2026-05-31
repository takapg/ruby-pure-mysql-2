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
class ResultJson(BaseModel):
    title: str = Field(description="エラーの対応方針をまとめたタイトル。")
    body: str = Field(description="Markdown形式の本文。必ず「#### 失敗の原因、#### 修正のヒント、#### 次のアクション」のセクションを含めること")

# 3. クライアントの初期化
client = genai.Client(api_key=api_key)

# 4. コンテキストの読み込み
try:
    with open("repomix-output.xml", "r", encoding="utf-8") as f:
        repo_code = f.read()
except FileNotFoundError:
    print("Error: repomix-output.xml not found.")
    sys.exit(1)

try:
    with open("ci-error.log", "r", encoding="utf-8") as f:
        error_log = f.read()
except FileNotFoundError:
    print("Error: ci-error.log not found.")
    sys.exit(1)

# 5. 指示の組み立て
full_prompt = f"""あなたは Ruby と MySQL のスペシャリストです。
現在開発中の 'ruby-pure-mysql-2' プロジェクトで CI が失敗しました。
提供された「プロジェクトの全コード」と「エラーログ」を元に、原因の特定と修正案を提示してください。

【プロジェクトの全コード】
{repo_code}

【エラーログ】
{error_log}

【条件】
* 出力する文章は、必ず「日本語」で作成してください。
* 回答を導き出す前に、リポジトリ全体のコードの依存関係と、MySQL の挙動を、頭の中でステップ・バイ・ステップで極限まで深く推論・シミュレーションし、絶対に手戻りのない確実な原因を特定すること。

【回答形式】
1. 失敗の原因: 何が起きているのかを技術的に簡潔に説明してください。
2. 修正のヒント: どのファイルのどのあたりを修正すべきか、具体的なコード例を含めて提示してください。
3. 次のアクション: 修正のために Aider に与えるべき指示内容を提案してください。
"""

print("Gemini API にリクエストを送信中...")

# 6. API呼び出し
try:
    response = client.models.generate_content(
        model="gemma-4-31b-it",
        contents=full_prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=ResultJson,
            temperature=0.2, # 意図しないブレを減らす
        ),
    )
    
    # 成果物を issue.json として保存（Geminiが保証した綺麗なJSONがそのまま入る）
    with open("result.json", "w", encoding="utf-8") as f:
        f.write(response.text)
        
    print("Success: result.json が正常に生成されました。")

except Exception as e:
    print(f"API Error: {e}")
    sys.exit(1)
