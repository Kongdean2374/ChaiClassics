# GitHub → TestFlight → App Store

原始碼倉庫為 Public，預設分支 main。CI 不需要 Apple Secrets，push／PR 自動執行，最低 `contents: read`，不使用 pull_request_target。

## Apple 與 GitHub 一次性設定

1. 加入 Apple Developer Program，註冊 Bundle ID `cc.chaihome.chaiclassics`。如已占用，先報告後才決定改 ID，不自動改用其他 App ID。
2. 建立 App Store Connect App Record，取得可管理此 App 的 ASC API Key（Key ID、Issuer ID、p8）。建立 Apple Distribution 憑證，匯出含私鑰的 p12，下載符合本 App／Team 的 App Store provisioning profile。
3. 在 GitHub Settings → Environments 建立 `testflight` 與 `production`，限制只允許 main 部署。為 production 設定 required reviewers 與 prevent self-review（方案支援時）。**workflow 檔會引用 environment，但不會自動建立審核保護；必須在 GitHub Settings 完成。**
4. 在 testflight Environment Secrets（或 Repository Secrets）設定下表；production 只需前三個 ASC secrets。不要把值放進 issue／聊天／README。大檔轉 base64 應採單行，於安全本機操作後直接貼 Secrets；不要提交中間檔。

| Secret | 用途 |
| --- | --- |
| ASC_KEY_ID | ASC API Key ID |
| ASC_ISSUER_ID | ASC issuer UUID |
| ASC_API_KEY_P8_BASE64 | p8 原檔的單行 base64 |
| APPLE_TEAM_ID | Apple Developer Team ID |
| DISTRIBUTION_CERT_P12_BASE64 | 含私鑰 Distribution p12 的單行 base64 |
| DISTRIBUTION_CERT_PASSWORD | p12 匯出密碼 |
| APPSTORE_PROFILE_BASE64 | App Store profile 的單行 base64 |

Secrets 缺少時 workflow 會列出缺少的「名稱」並失敗，不顯示值、不捏造證書。App ID、profile 的到期時間與 distribution 用途也會驗證。API Key 與 profile 必須在 Apple 後台有效；單有同名 Secrets 不保證可用。

## TestFlight

先看 CI 全綠。在 Actions → TestFlight → Run workflow，選 main 與版本（例如 0.1.0）。流程先重跑完全相同 CI，成功後才讀發布 Secrets，在臨時 keychain 匯入證書，Release archive／export IPA 並上傳。結束必定移除臨時 keychain、profile 與簽署檔。簽署資產不放 artifact；只保留不含機密的 provenance.txt。

版本三段數字由手動輸入。Build number 固定為 `GITHUB_RUN_NUMBER.0.GITHUB_RUN_ATTEMPT`（4.2.2 格式上限 9999.0.99）；相同 run／attempt 必定得到相同值。只有 TestFlight workflow 產生新二進位，App Store workflow 選用既有 build。兩個發布 workflow 共用 concurrency；上傳前查詢 ASC 同版本既有 build，若號碼已用或倒退則明確拒絕。重新上傳請建立新的 TestFlight dispatch，不要重跑早於現有版本的舊 run。API 處理的短暫一致性延遲若導致 Apple 拒絕重複上傳，也必須讓流程失敗，再建立新 run。GitHub run ID／完整 commit 另記於 changelog 與 provenance，不能只用畫面版本猜測來源。

上傳成功後 Apple 仍要處理。內部測試先在 ASC 分派測試群組；外部測試可能需要 Beta App Review。使用者須在 iPhone 安裝 TestFlight 並完成 docs/TESTING.md。沒有 Mac 也可使用 Actions 建置與 iPhone 驗收；建立／取得 Apple 簽署資產仍須由帳戶持有人透過受信任流程完成。

## 準備 App Store（不自動送審）

先完成三款 TestFlight 真機測試，再按產品規格加入五子棋、Klondike、記憶翻牌，或明確決定保留三款 beta。不要以未驗收的六款空殼上架。

需要先在 App Store Connect 填妥真實 App 名稱、簡介、描述、關鍵字、支援／隱私政策網址、著作權、分類、審查聯絡方式與符合當前尺寸要求的 iPhone 截圖；審查聯絡個資與截圖不需要進公開 repo。App Store 隱私與年齡問卷也由帳戶持有人確認。

`prepare_store` lane 只選入既有 TestFlight build 並更新這次的 release notes，保留 ASC 上已審閱的商店資料／截圖。沒有自動生成虛構網址、聯絡人或截圖。metadata_reviewed 核取欄位是使用者確認，不代表程式已自動審查 Apple 的每個必填欄位；真正送審前仍需由 ASC 完成檢查。
Actions → Prepare App Store：選 main、已測版本、確切 build number、provenance 完整 commit、release notes，確認兩個驗收欄位。CI 通過並經 production environment 審核後，fastlane 選入既有 TestFlight build、更新 release notes，`submit_for_review: false`、`automatic_release: false`。目前要求所選 TestFlight commit 等於執行的 main commit，以避免選錯版本。

送審、隱私問卷、截圖、年齡分級、出口合規與發布時間最後都由使用者在 ASC 確認。Apple 審查通過與發布設定決定上架時機，GitHub push 不會直接更新用戶 App。新增題庫與新遊戲也需要新版建置、測試與相應 Apple 發布流程。

## 工具鏈要求查核（2026-11-16）

已查 Apple 官方 [SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)：2026-04-28 起需 Xcode 26+ 與 iOS 26 SDK。此次真正 Actions 使用 Xcode 26.3、iOS SDK 26.2，符合此最低要求；未來發布前需重新查官方條件，特別是 Apple 已公告的 2027-04 SDK 27 要求。選擇器只挑 runner 已安裝的穩定版，不下載來路不明工具鏈。
