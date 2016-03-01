# barile

An OTP application
TODO: 英語で概要を書く

## 問題設定
問題設定: cronを動かすバッチサーバが冗長化されておらず、SPOFとなっている.これを解消したい.
## ゴール
 cronライクなタスクスケジュールで、容易に高可用性のあるバッチシステムを構築できることを目標とする.

## 仕様の設計

### barileの要件
  - システム要件
    1. 外部コマンドのosプロセスレベルでの再起動は必要なし
    1. erlangのタスクが失敗したかどうかは確認したいので、osプロセスの実行結果をキャッチしたい
    1. 失敗した場合はerlangのログに流す
    1. 失敗したタスクを簡単に取得、一覧化して、再実行させる等のインターフェースが欲しい
    1. 分散して冗長化を容易に設計したい。例えば、Aのサーバが死んだらBのサーバで起動しているbarileに瞬時に切り替わる.
    1. 各タスクに対しての解説(description)も保存しておきたい
  - 機能要件
    - ここは各エンジニアに入れてもらいたい

### memo書き 
* スケジュールの追加方法のプロトコルはコマンドベースにする（escript?）なのでhttpとかは必要ない
  - http等で他言語から実行したい要望があれば考慮する?
* barile独自のスケジュールフォーマットを使う
  - cronでいう * * * * * でスケジュールを指定する部分のこと
  - まだ考えていないので考えないといけない
* 1プロセス1スケジュール（1 cron => 1 erlang process)
* 実行するインターフェースはerlangから外部コマンドを実行する形式にする.
  - 確認事項
    1. erlangからosのプロセスの状態を見ることができるかどうか
    1. osプロセスの実行結果を流して受け取ることができるかどうか
    1. erlangからosプロセスを停止、終了の確認がとれるかどうか
