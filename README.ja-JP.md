<div align="center">

# Default Browser Switcher

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

**複数のブラウザを行き来しながら作業する人のための、軽量な macOS メニューバーアプリです。既定のブラウザも、その時々の作業の流れに合わせて素早く切り替えられます。**

**Safari、Arc、Chrome、Firefox などの間で作業の軸が移るたびに、System Settings を開き直さなくても、リンクの既定の開き先を今使いたいブラウザへすばやく寄せられます。**

</div>

## このプロジェクトについて

いまの Mac では、ひとつのブラウザだけで一日を過ごすほうがむしろ珍しくなりました。あるブラウザには仕事用アカウントがログイン済みで、別のブラウザにはプロジェクト用のタブが並び、また別のブラウザはテスト向きだったり、次の数時間にちょうど合っていたりする。そうした使い分けが日常になると、既定ブラウザの変更は一度きりの初期設定ではなく、地味に流れを止める細かな作業になっていきます。

`Default Browser Switcher` は、その日常的な切り替えをもっと自然にするためのツールです。作業の重心が変わったときに、より素早くネイティブ感のある形で既定ブラウザを切り替えられるので、アプリやツールやシステムから開いたリンクを、その瞬間に使いたいブラウザへ気持ちよく着地させやすくなります。

## できること

- メニューバーから現在の既定ブラウザを確認できます。
- 別のインストール済みブラウザへワンクリックで切り替えられます。
- ブラウザ検出結果を更新して、現在の既定ブラウザの状態と選択可能なブラウザ一覧を読み直せます。
- `LaunchServices Direct` と `System Prompt` の 2 つの切り替えモードを選べます。
- ログイン時に自動起動するかどうかを切り替えられます。

## Settings

メニューバーの `Settings…` から設定画面を開けます。

- `Default web browser`: リンクを既定で開くブラウザを選びます。
- `Refresh current browser`: 現在のシステム検出結果を読み直し、表示中の既定ブラウザと選択可能なブラウザ一覧を最新化します。切り替え後、ブラウザを追加または削除した後、あるいは状態が正しく見えないときに最新状態を確認できます。
- `Switch mode`: 2 つの切り替え実装を選びます。
  - `LaunchServices Direct` が既定です。ユーザーの LaunchServices ブラウザハンドラを直接更新するため、通常はより速く、macOS の確認ダイアログも出にくくなります。
  - `System Prompt` は macOS の公式 API を使う保守的な経路で、macOS がブラウザ変更の確認を求めることがあります。
- `Launch at login`: サインイン時にアプリを自動起動するかを切り替えます。

実装方式を後から変えたい場合も、メニューバーの `Settings…` を開いて `Switch mode` を変更するだけです。

## 開発

ビルド:

```bash
xcodebuild -scheme DefaultBrowserSwitcher -project DefaultBrowserSwitcher.xcodeproj -destination 'platform=macOS' build
```

テスト:

```bash
xcodebuild test -scheme DefaultBrowserSwitcher -project DefaultBrowserSwitcher.xcodeproj -destination 'platform=macOS'
```

任意の検証:

```bash
bash Scripts/verify-s01.sh
bash Scripts/verify-s02.sh
```

## License

[MIT](LICENSE)
