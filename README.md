# WezTerm 設定

macOS 向けの WezTerm ターミナル設定。

## 概要

- **フォント**: Hack Nerd Font (14pt)
- **カラースキーム**: Ef-Night
- **半透明背景**: opacity 0.92 + blur 20
- **タブバー**: シンプルなスタイル（カラースキームと統一）
- **IME**: 有効
- **Leader キー**: `Ctrl+A`

### キーバインド

| キー | 動作 |
|---|---|
| `Cmd+Shift+R` | 設定リロード |
| `Cmd+W` | ペイン閉じる |
| `Cmd+,` | 縦分割 |
| `Cmd+.` | 横分割 |
| `Shift+矢印` | ペイン移動 |
| `Cmd+左/右` | ワークスペース切替 |
| `Alt+9` | ワークスペース一覧 (Fuzzy) |
| `Ctrl+N` | ペインズーム切替 |

## セットアップ

### 1. WezTerm のインストール

```bash
brew install --cask wezterm
```

### 2. フォントのインストール

```bash
brew install --cask font-hack-nerd-font
```

### 3. 設定ファイルの配置

```bash
git clone <このリポジトリのURL> ~/.config/wezterm
```

既に `~/.config/wezterm` がある場合は、バックアップしてから置き換えてください。

```bash
mv ~/.config/wezterm ~/.config/wezterm.bak
git clone <このリポジトリのURL> ~/.config/wezterm
```

WezTerm を起動すれば設定が自動で読み込まれます。
