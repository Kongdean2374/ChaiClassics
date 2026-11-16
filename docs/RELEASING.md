# GitHub → match → TestFlight → App Store

公開原始碼：Kongdean2374/ChaiClassics，預設 main。私密簽署：**Kongdean2374/ChaiClassics-Signing / main**。簽署流程僅 `workflow_dispatch` 且 `refs/heads/main`；一般 push／PR 的 CI 完全不讀 Apple／match Secrets。

## 一般 TestFlight／App Store 的 Developer Key 與共用設定

| 設定 | 格式／用途 |
| --- | --- |
| ASC_KEY_ID | 10 碼 Apple API Key ID |
| ASC_ISSUER_ID | ASC issuer UUID，並非 Apple Team ID |
| ASC_API_KEY_P8 | **完整原始多行 p8**，含 BEGIN PRIVATE KEY／END PRIVATE KEY；不是 Base64，不是字面上的 `\n` |
| APPLE_TEAM_ID | 10 碼 Apple Developer Team ID，可用 Repository Secret、Variable 或手動 workflow input；input > Variable > Secret |
| SIGNING_REPO_PAT | 可存取私人 ChaiClassics-Signing 的 PAT；初始化需 Contents read/write，readonly 取回需 Contents read |
| MATCH_PASSWORD | match 私人倉庫的加密密碼，必須持續保留同一值 |

使用者已回報上述 Secrets 已配置（含 APPLE_TEAM_ID）；程式不讀取／公開其值，執行時才驗證真實有效性。共用 Repository Secrets 保留 APPLE_TEAM_ID、SIGNING_REPO_PAT、MATCH_PASSWORD。一般 TestFlight／App Store 仍讀取原本的 Developer ASC_KEY_ID／ASC_ISSUER_ID／ASC_API_KEY_P8；不使用 Admin Key。

### 首次初始化專用 Admin Key

使用者已建立 Environment **signing-bootstrap**，僅 Initialize Signing Job 選用，映射如下：

| signing-bootstrap 的 Admin Secret | 初始化程序讀取的環境變數 |
| --- | --- |
| SIGNING_ASC_KEY_ID | ASC_KEY_ID |
| SIGNING_ASC_ISSUER_ID | ASC_ISSUER_ID |
| SIGNING_ASC_API_KEY_P8 | ASC_API_KEY_P8（完整原始多行 p8，非 Base64） |

這些名稱只在初始化 YAML 的 env 映射使用；Fastfile 與預檢程式維持統一 ASC_* 變數，不需要更換 Repository 的 Developer Key。Admin Secrets 不傳給 reusable CI，也不傳給一般 TestFlight／App Store。APPLE_TEAM_ID、MATCH_PASSWORD、SIGNING_REPO_PAT 沿用原共用設定。注意 Environment 內若另有同名共用 Secret，GitHub 會優先使用 Environment 的值。

**不需要手動提供 p12、Distribution 證書或 provisioning profile。** 舊版手動匯入的 base64 Secrets 已停用，可以移除；不要把任何 p8、PAT、密碼、明文簽署檔貼到 issue、聊天或公開 repo。

PAT 建議 fine-grained、只授權 ChaiClassics-Signing、Contents read/write；組織倉庫另需 SSO／政策核准。Public 倉庫的 `GITHUB_TOKEN` 無法取代私人簽署 PAT。預檢會核對精確倉庫名稱、private、main、讀取／初始化推送權限；GitHub API 的角色權限不一定代表 PAT 具備所有細部 scope，真正 clone／push 仍由 match 驗證。

## Apple 前置條件與權限

- 有效 Apple Developer Program 與協議；正確 Team 的 Bundle ID **cc.chaihome.chaiclassics** 已在 Developer Portal 註冊。ID 不存在會明確停止，不偷偷換 ID。
- 使用 team App Store Connect API Key，確保能管理此 App，並有 Certificates, Identifiers & Profiles 所需的讀取／建立權限（角色與帳戶設定均需正確；不足時向 Account Holder／Admin 調整）。初始化會先對 certificate、profile、Bundle ID API 做讀取探測，實際建立權限仍由 Apple 建立請求驗證。
- Key 是 EC P-256，Issuer／Key ID 與 p8 相符。API Key 不同於 App 專用密碼，ASC Issuer ID 不同於 Developer Team ID。
- TestFlight 上傳另需 App Store Connect App Record，ID 必須相同。

## 首次簽署初始化：只手動執行一次

GitHub Actions → **Initialize Signing (match)** → Run workflow → main。Team ID 已在 Secret 時不用填 input。

1. 先跑完整免簽署 CI，成功後才在 macOS runner 的 `signing-bootstrap` environment 將三個 SIGNING_ASC_* Admin Secrets 映射為 ASC_*，並注入原共用 Secrets。
2. 預檢原始 PEM、Team ID、私人簽署 repo 的 main 與 PAT 存取；不印值或 HTTP 回應。
3. `initialize_signing` lane 使用 `match(type: appstore, readonly: false, generate_apple_certs: true)`，只指定本 App／Team，在臨時 keychain 建立／安裝 Apple Distribution 與 App Store profile。
4. match 用 MATCH_PASSWORD 加密後 commit/push 到私人 ChaiClassics-Signing/main。公開 repo 與 artifact 不含簽署資產。
5. 核對 profile 的 app ID、Team、到期時間、App Store 用途與有效私鑰，最後清除本 App 的本機 profile、臨時 keychain；match 也清除解密暫存 clone。

已存在有效資產會重用，不強制重發。此初始化 lane 不是自動定期更新工作。若達 Apple Distribution 憑證數量上限、現有證書過期或權限不足，明確失敗；**沒有 nuke、撤銷他 App 憑證或自動釋放配額的路徑**。不要用 nuke 解決失敗；管理既有團隊證書需另行明確決策。

## 後續 TestFlight

Actions → **TestFlight** → Run workflow → main 與版本（如 0.1.0）。CI 成功後在 macOS 用 `match readonly: true` 下載並解密既有資產到臨時 keychain，再 Release archive／export IPA、上傳 ASC。

Readonly 缺資產、過期或無有效私鑰就停止，**不退回建立模式**。先檢查初始化結果及同一 MATCH_PASSWORD，再依明確需要手動執行初始化。TestFlight workflow 不接受手動 p12。

版本三段數字手動輸入。Build number 固定 `GITHUB_RUN_NUMBER.0.GITHUB_RUN_ATTEMPT`（上限 9999.0.99）；ASC 同版本若已用或倒退則拒絕，應新建 TestFlight dispatch，不重跑早於現有 build 的 run。初始化、TestFlight、App Store 共用 concurrency，防止同 repo 同時修改／使用簽署資產。

只上傳不含機密的 provenance.txt；不公開 IPA、簽署資產或敏感 fastlane 日誌。Apple 上傳後仍需處理，外部測試可能要 Beta Review，不代表立即可安裝。使用者完成 docs/TESTING.md 的 iPhone 實測後，才依產品規格繼續加入五子棋、Klondike、記憶翻牌。

## 日誌與失敗處理

三個有憑證的 lane 一律經 `scripts/run_signing_lane.py` 執行。它將 fastlane／Git／OpenSSL 的原始輸出寫入不公開的臨時匿名檔案，最後關閉刪除；即使子工具回顯原始／Base64 PAT、p8、密碼或 backtrace，也不傳到 Actions log／artifact。只輸出固定錯誤碼與文字：APPLE_ACCESS、APPLE_TEAM、APPLE_KEY、BUNDLE_ID、MATCH_GIT、MATCH_DECRYPT、MATCH_ASSETS、CERT_QUOTA、SIGNING_FAILED、UPLOAD_FAILED。

預檢缺少的設定會一次列出「名稱」。403／401 等 HTTP 回應內容、Apple 錯誤原文不回顯。受控錯誤可能無法區分所有 Apple／Git 故障；需要更進一步診斷時應新增特定不含機密的檢查，不能直接改成 cat 原始日誌或開 set -x。

## Environment 審核保護

GitHub Settings → Environments 設定 `signing-bootstrap`、`testflight`、`production`，只允許 main；production 及 signing-bootstrap 建議 required reviewers、prevent self-review（方案支援時）。YAML 引用 Environment 不會自動設定 reviewer 保護，管理員必須確認設定。所有 workflow 都是 contents: read；只有 SIGNING_REPO_PAT 用於私人 repo。

## App Store（不自動送審）

先在 ASC 填妥真實名稱、描述、關鍵字、支援／隱私網址、著作權、分類、審查聯絡方式、實際 iPhone 截圖、隱私／年齡問卷。這些私密聯絡資料不必放公開 repo。

Actions → Prepare App Store：main、已測版本、精確 build number、provenance 完整 commit、release notes，核取真機與 metadata 已審閱。CI／production 核准後只選入既有 build 並更新 notes，`submit_for_review: false`、`automatic_release: false`。只需 ASC 三項 Secrets，亦使用原始 ASC_API_KEY_P8，不下載 match 或要求 p12。

最後由使用者在 ASC 決定送審與發布時機。GitHub push 不會直接更新用戶 App。新增題庫與遊戲同樣要建置、測試及 Apple 發布。

## 工具鏈查核（2026-11-16）

Apple 官方 [SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)：2026-04-28 起需 Xcode 26+／iOS 26 SDK。本次 macOS CI 使用 Xcode 26.3／SDK 26.2。正式上傳前仍要查當前條件，尤其 2027-04 SDK 27 要求。

本次僅修正 bootstrap 環境／金鑰映射，依使用者要求未觸發 Initialize Signing，也未建立／撤銷任何 Apple 憑證。
