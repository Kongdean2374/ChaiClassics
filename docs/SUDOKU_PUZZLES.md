# 固定數獨題庫

v1 的 `Core/Resources/sudoku-v1.json` 共有 150 題，各難度 001～050。Stable ID 為 `sudoku.easy.0001` 等。App 只打包題面，不打包解答畫面，也不提供求解器操作。

生成器 `scripts/generate_sudoku.py`（seed 20261116）先建立完整合法解，再逐格挖空，用 MRV 回溯計數確認仍為唯一解。每個完整解最多取一題，避免同一底盤挖空的多個近似版本；不重複題面。

獨立驗證器 `scripts/verify_sudoku.py` 用 324 約束的 Algorithm X Exact Cover 計數（不是生成器的 MRV 程式）。每題解數必須恰好 1。另驗證 9×9 給定數字合法、ID／題面唯一、序號連續、分類、舊 manifest SHA256 不變。

分級不是依給定數字數量：

- 簡單：只用 naked singles 可以完成。
- 中等：naked singles 停滯，必須使用 hidden singles，但不必分支。
- 困難：以上兩種策略後仍有未定格，需要進一步策略或分支推理。這是可重現的策略分級，不聲稱等同某報紙的主觀評等，也不聲稱一定需要猜測（進階人類策略可能可解）。

每題策略指標保存在 `docs/sudoku-verification-v1.json`。首次本機執行：150 唯一解，三類各 50，0 失敗。CI 重新計數，不只相信報告。

## 新增 051 之後

1. 不要重新產生或覆寫 v1。生成到新的暫存輸出，與舊 pack 合併，只把新題編為各難度 0051、0052…。
2. 保持舊題面、ID、難度、題號與順序不變，新題追加；保留 `docs/sudoku-manifest-v1.json` 作為永久基準。
3. 更新測試預期的題數，在新 manifest 記錄追加題目的 hash，但不可取代舊基準。
4. 跑 `python3 scripts/verify_sudoku.py`。CI 也會以 push 前提交／PR base 逐題比較，防止連 manifest 一起改來繞過保護。
5. 驗證舊存檔、050→051 解鎖、各難度獨立及既有鉛筆筆記，透過新版 App 發布。不能直接靠修改 GitHub 檔案讓已安裝 App 得到題目。

重新產生初版的研究指令（只能輸出新檔，不得覆寫已發布資料）：

```sh
python3 scripts/generate_sudoku.py --seed 20261116 --count 50 --output /tmp/sudoku-reproduction.json
python3 scripts/verify_sudoku.py --pack /tmp/sudoku-reproduction.json
```
