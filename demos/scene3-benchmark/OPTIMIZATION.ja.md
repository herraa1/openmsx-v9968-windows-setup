[English](OPTIMIZATION.md)

# Scene 3 の画素を維持した最適化

2026-09-14測定。0.7.1に同梱した最適化の測定結果です。公開済みの基準ROM・rom.json・results.jsonは変更していません。最適化版は `SCENE3-BENCHMARK-OPTIMIZED.rom`、ハッシュは [rom-optimized.json](rom-optimized.json)、全測定のフレーム数・経過tickは [results-optimized.json](results-optimized.json) に記録しています。

## 測定方法

Windows 10 x64、PowerShell 5.1、手元のz88dk/sdcc -SO3、固定したopenMSX d884c4bで測定しました。C-BIOSはZ80、FS-A1GTは所有BIOSを使ったR800 ROMモードです。各段階で同じスクリプトを使い、FULL/FAST/COMPAT、通常アニメーション/固定ポーズの各条件を、エミュレーター時間15秒×連続3区間で測定しました。FPSは完了フレーム合計×60÷経過VBlank tick合計です。HUD・PSG/BGM・垂直同期待ちを含みます。区間の差は測定窓による変動であり、統計的な信頼区間ではありません。実機と音質は未検証です。

再ビルドした基準ベンチマークは公開済みROMとハッシュが異なるため、以下は今回測った値です。基準デモは公開済みデモと同じハッシュを再現しました。ソースのコミットとコンパイラーのハッシュもJSONに記録しています。アニメーションはtick基準で、FPSが上がっても進行速度は変えません。Pはポーズ・水面位相を0に固定して描画を続ける操作です。最適化後は同一形状を再利用するため、通常再生より大きな効果があります。

## 通常アニメーション / FULL

| Stage | C-BIOS / Z80 fps | FS-A1GT / R800 fps |
|---|---:|---:|
| baseline | 6.433 | 8.244 |
| A | 6.548 | 8.539 |
| AB | 6.716 | 8.867 |
| ABC | 7.957 | 10.504 |
| ABCD | 8.305 | 10.798 |
| ABCDE | 10.070 | 12.312 |

## 固定ポーズ / FULL

| Stage | C-BIOS / Z80 fps | FS-A1GT / R800 fps |
|---|---:|---:|
| baseline | 6.000 | 7.500 |
| A | 6.000 | 7.500 |
| AB | 9.627 | 12.000 |
| ABC | 12.000 | 15.000 |
| ABCD | 12.000 | 15.000 |
| ABCDE | 13.005 | 20.000 |

## 各段階と画素の一致

- A：水面描画前の49,152画素の全面クリアだけを除去。主転送と左右端の繰り返しで全画素を上書きします。
- AB：画面の退避コピーを廃止し、ページ2に背景と立体を直接描画。前の立体の外接矩形だけをページ3から復元します。正確な外接矩形の平均は15,175.680画素、HMMMのバイト境界に広げた実復元範囲は15,298.141画素です。同じポーズなら復元も立体の再描画も省きます。
- ABC：横方向の対応が同じで、転送元と転送先の行が連続する帯だけを統合。主転送は平均96→53.102回、左右端の1画素転送2回も含めると平均224.000→123.273回です（削除したクリアは別）。全256位相で元の行と左右端を維持します。
- ABCD：ラスタライズ後の同色・同X・同幅の走査線を縦に結合。LMMVは平均257.141→223.836回、最適化後の範囲は107〜328回です。全128画像を元のPillowラスタと照合します。Scene6は可変の矩形高を保ったまま色を15に置き換えます。
- ABCDE：アセンブリでCEを待ち、パケットを連続出力。R17選択の2回の書き込みだけを割り込みから保護し、CEが下がるまで次のコマンドレジスターは変更しません。65,535回の待機上限とCF06=1の異常表示・映像/音の停止を残しました。ISRは継続し、S2を復元し、ROMバンクとR17は変更しません。診断用に `-CStream` でCのメッシュ・残光・水面処理を選べます。

標準経路は完全一致を目標とし、近似FAST_EDGE、解像度の削減、サンプリングの変更、立体の簡略化は行っていません。転送中のページ2は不変です。ページ0/1は表裏、2は作業/履歴、3は背景とヘッダーに使用します。背景・テクスチャ読み込み時にキャッシュを無効化し、Scene6との往復も含めて再初期化します。

## データ形式とコンパイラー

ROMは1 MiB、64バンクのASCII16のままです。MESHは1フレーム4,096バイト。先頭u16の個数、11バイト×個数のLMMV矩形、余白、オフセット4092のx/y/幅/高さです。WATERは1位相512バイト。先頭u8の個数と、sx/dx/幅/sy/高さの5バイト×個数、余白です。幅0は256を表し、転送先Yは高さの累積です。IDENTITYは全192行を転送する6バイトの単一レコードです。各バンクの開始位置は変わりません。

-SO3ではwater_prepareの引数を直接マスクする処理が削除されました。引数とは別の変数へマスク結果を代入し、128〜255の入力でFLOORバンクへはみ出す問題を防ぎます。これは全シーンの回帰で発見し、専用試験でも上位ビット付きの全入力を使います。途中段階のベンチマークは呼び出し元ですでに0〜127に制限されていました。

## 検証

- 生成時：全メッシュを再構成して画素一致、矩形の非重複、容量、水面展開の完全一致を確認。
- verify-water-model.py：全256位相、元の2行帯24,576個を独立した数式と照合。横揺れと縦方向のクランプも検査。
- test-water.ps1：両CPUで無変形は元画像と一致。水面は識別しやすい端の画素を使って独立参照と比較し、不一致バイト0。
- test-water-work.ps1：各CPUでページ2全体を130画像比較。全128ポーズ、上位ビット入力、同一ポーズ再利用、Scene6からの再進入を確認。期待値は元のラスタと背景から作り、実行時の出力は参照しません。試験のCPU待避中だけIRQを止め、再開前にIFFを復元します。この試験は速度測定には使いません。
- 全デモ：両CPUで6シーン、ヘッダー、Wなどの操作、マッパー、R20、エラーフラグがPASS。
- ベンチマーク：両CPUでV9968のF/P/Escと全3モードがPASS。通常版V9958のCOMPATも両CPUでPASS。従来VDPへV9968専用モード設定は行いません。

## 再現方法

リポジトリ直下で実際のz88dkディレクトリとセットアップ済みruntimeを指定します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/build.ps1 -Z88dk "<z88dk>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/launch.ps1 -Mode cbios -Optimized
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/measure-optimization.ps1 -Runtime runtime/cbios
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/v9968-tech-demo/test-water-work.ps1 -Runtime runtime/cbios
```

FS-A1GTではfsa1gtを指定します。デモの試験には先にデモ側build.ps1でビルドしてください。測定の `-Reference` は公開済み基準ROMを選びます。今回再ビルドした最適化前ROMとは区別します。結果はGit対象外のtest-outputへ保存し、所有BIOSを公開してはいけません。共通アセットの生成処理も実行され、アセットファイルを再生成します。同じ入力では同じデータになります。`-CStream` のROMは `build-c/` に分離し、配布ROMと既存測定を変更しません。今後の比較でもVBlank単位の段階的なFPSと固定ポーズのキャッシュ効果を明示してください。V9990への移植は今回行っていません。

## 配布用スライドとC実装の検証

[日本語PDF](scene3-optimization.ja.pdf) / [English PDF](scene3-optimization.pdf)。

ベンチマークも `build.ps1 -CStream` でC版を生成し、`launch.ps1 -Mode cbios -CStream` または `test.ps1 -Runtime <runtime> -CStream` で確認できます。`-Standard` との併用で通常VDPも試験できます。[C/ASMの対応と全シーンの検証手順](../v9968-tech-demo/DEVELOPMENT.ja.md)。
