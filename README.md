barile
=====

An OTP application

Build
-----

    $ rebar3 compile

-----

仕様の設計
cronのようなスケジュールタスク実行ミドルウェアさん

* 便利なjobqueueにしたい
* 実行するのは外部コマンド？
* 自身がkey-valueを持つようにする
* jobqueueのやり取りはどうする? HTTP?独自のプロトコル?
* taskの詳細な実行処理は何で書く？
 - lua
 - golang?
 - c
 - ruby/python/perlなどのLL言語?
 - 外部コマンド
* erlangでの外部コマンドはどうやって渡せば良さそうか

* taskの状態はETSでもつ
* barile全体の状態はどうする？
* 
