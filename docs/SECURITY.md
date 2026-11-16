# 公開倉庫與簽署安全

此倉庫可公開閱讀，未加入 LICENSE；公開不代表自動授予重製授權。

禁止提交 p8、p12、mobileprovision、私鑰、API Key、密碼、含機密的設定、簽署輸出或公開 artifact。`.gitignore` 是防誤操作，不是秘密掃描；提交前仍需檢查 git diff。若曾外洩，立即撤銷 Apple 資產／API Key，再處理 Git 歷史，刪檔本身不足。

CI／PR 僅 contents: read，不接觸 Apple Secrets。發布只允許手動 main，先跑 CI，再由 environment 才注入 Secrets。不執行不受信任 PR 的發布程式，不使用 pull_request_target。production 的 required reviewers 需管理員在 Settings 真正啟用，不能只靠 YAML 名稱。

Fastlane 以記憶體 API key、0600 臨時檔、臨時 keychain 工作；signing 子命令不回顯參數或輸出，確保清理 profile／keychain。只上傳 provenance，不公開 IPA／簽署資料。Actions checkout 與 artifact action pin commit；Ruby setup 也 pin 已驗證 commit。Fastlane 固定 2.228.0，Gemfile.lock 為實際 CI 安裝解析結果，發布與 CI 使用 frozen install。正式發布前應按依賴安全更新政策審查新版本與 lockfile。

App 執行期不使用網路、帳號、analytics、廣告或推播。隱私問卷需根據實際二進位與第三方依賴填寫；不能以此文件代替 Apple 申報。App 只本機存檔，裝置／系統備份與卸載行為由 iOS 管理，不保證卸載後可恢復。
