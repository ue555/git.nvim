# git.nvim

Neovim上でコミット履歴とブランチを操作するLua 5.1製プラグインです。
履歴の確認、詳細・diff表示、ブランチ移動、選択コミットへの移動を
Neovimから実行できます。

## 機能

- `vim.system()`による非同期Git操作
- コミット選択時に詳細と色付きdiffを自動表示する2ペインUI
- 追加・削除・変更ファイル・diff hunkの色分け表示
- ローカル・リモートブランチ一覧と切り替え
- 選択コミットへの安全なdetached HEAD移動
- 選択コミットからのブランチ作成
- 移動前に使用していたブランチへの復帰
- 未コミット変更がある場合の移動防止
- `--follow`を使用したファイル単位の履歴
- Git以外の外部依存なし

## 必要要件

- Neovim 0.10以降
- Git 2.23以降

## 設定

```lua
require("git_history").setup({
  default_view = "commits",
  window = {
    width = 0.9,
    height = 0.85,
    list_width = 0.42,
    border = "rounded",
  },
  log = {
    max_count = 100,
  },
  checkout = {
    confirm = true,
    allow_dirty = false,
  },
  branch = {
    show_remote = true,
    allow_dirty = false,
    allow_delete = true,
  },
})
```

## コマンド

| コマンド | 内容 |
|---|---|
| `:GitHistory [directory]` | コミット履歴を表示 |
| `:GitHistoryFile` | 現在のファイルの履歴を表示 |
| `:GitBranches [directory]` | ブランチ一覧を表示 |
| `:GitCheckout {hash}` | 選択したコミットへ移動 |
| `:GitSwitch {branch}` | ブランチへ移動 |
| `:GitNewBranch {name}` | 新しいブランチを作成して移動 |
| `:GitHistoryBack` | 移動前のブランチへ戻る |
| `:GitHistoryRefresh` | 再読み込み |
| `:GitHistoryClose` | UIを閉じる |

## キー操作

| キー | 操作 |
|---|---|
| `1` / `2` | コミット／ブランチ画面 |
| `Tab` | 画面切り替え |
| `Enter` | 詳細表示、またはブランチ移動 |
| `l` / `h` | Detailsへ移動／一覧へ戻る |
| `d` | diff表示 |
| `f` | 変更ファイル表示 |
| `c` | 選択コミットへ移動 |
| `n` | 選択位置から新しいブランチを作成 |
| `D` | ローカルブランチを削除 |
| `P` | リモート情報を取得 |
| `B` | 元のブランチへ戻る |
| `r` | 再読み込み |
| `q` / `Esc` | 閉じる |

プラグインが`git reset --hard`、自動stash、未追跡ファイルの削除を
実行することはありません。

ディレクトリを省略した`:GitHistory`と`:GitBranches`は、現在編集中の
ファイルがあるディレクトリを使用します。無名バッファの場合のみ
Neovimのカレントディレクトリを使用します。

## ライセンス

MIT
