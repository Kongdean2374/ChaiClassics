# Apple 簽署診斷與 Run 43810107847

## 已確認與無法還原的部分

失敗來源：[Initialize Signing Run 43810107847](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43810107847)，commit 6ce8511。

- ci/release-tooling、ci/test、Secrets／私人簽署 repo 預檢均成功。
- Initialize encrypted Distribution certificate and App Store profile 失敗，公開結果只有 APPLE_ACCESS。
- 舊 `verify_apple_access!` 把全部 Spaceship::UnexpectedResponse 改寫為權限不足；舊 Python 包裝也按 forbidden／unauthorized 字串推測權限。這些字串不能證明實際是 403。
- 已查固定 fastlane 2.228.0：Certificate.all(limit:1)、Profile.all(limit:1)、BundleId.all(filter:...) 的參數簽名有效，未找到參數呼叫簽名不相容的證據。但這三個方法會調用 all_pages；limit:1 是每頁數量，並非最多一個請求。
- SDK 的 UnexpectedResponse 可能來自非 JSON 回應、errors 欄位、暫時服務錯誤等；它不等於 AccessForbiddenError，且未必保留 HTTP 狀態。
- 舊敏感 log 已按設計刪除，無法從公開紀錄還原原 HTTP、資源與原始 Apple 回應。**無法據此斷言是 401、403、API 相容性、Apple 服務或真正權限不足。** 不會為補資料而重新執行初始化。

## 初始化預檢的讀取方式

預檢使用標準 Ruby HTTPS 對 Apple 官方三個固定路由各讀一頁，保留 fastlane 產生的同一個 team JWT；不依賴 SDK 將 HTTP 錯誤格式化成字串，也不升級／改寫全域 Spaceship 行為：

| 資源 | 固定 GET | 查詢 |
| --- | --- | --- |
| certificates | /v1/certificates | limit=1 |
| profiles | /v1/profiles | limit=1 |
| bundleIds | /v1/bundleIds | limit=1、filter[identifier]=cc.chaihome.chaiclassics |

共用 Client 另允許下方手動診斷的 /v1/apps 唯讀路由。只允許 api.appstoreconnect.apple.com、HTTPS／TLS 憑證驗證；不跟隨重新導向或 links.next，不自動重試、不登入 Apple ID、不建立／刪除／重發／撤銷任何資產。SDK 相容性測試會用固定版本的 Spaceship::ConnectAPI::Token.text 與臨時測試 key，沒有真實 Apple 請求。

成功 HTTP 仍須符合 JSON:API data array 與資源 type／attributes 結構；非 JSON、200 但 errors、錯誤 schema 均列為 PROTOCOL，不當作權限問題。保留 exact Bundle ID 及既有 certificate OU／Team ID 驗證；沒有舊證書時，初始化後仍核對實際 profile 與私鑰。

## 安全輸出

Ruby 只產生 schema 固定的小型 IPC report：檢查通過的資源、失敗資源、HTTP 數字／unknown、固定分類，及少數明確 allowlist 的 Apple code（例如協議過期）。Python 再次驗證所有欄位與 enum，才輸出固定文字。

不輸出 API Key ID／Issuer 值、JWT、p8、PAT、密碼、請求標頭、回應標頭、request ID、原始回應、title／detail、證書內容、Team ID 值或任意 exception.message。原始 fastlane 輸出仍只在匿名私密暫存檔，離開時刪除；IPC report 也位於 0700 臨時目錄，檔案 0600，無 artifact。缺少有效 report 不宣稱診斷成功。

範例（只顯示固定安全 metadata）：

```text
Apple read-only check: resource=certificates method=GET HTTP=200
Apple API failure [APPLE_403]: resource=profiles method=GET HTTP=403 category=FORBIDDEN
```

## 依分類決定下一步

| 結果 | 含義／是否需要 Apple 後台設定 |
| --- | --- |
| 401 / AUTHENTICATION | 檢查選中的 Key／Issuer／p8 是否配對、Key 是否有效、runner 時鐘；不是 403 角色結論，不先重建證書。 |
| 403 / FORBIDDEN | Apple 確實拒絕該資源。確認實際 Environment 對應的 team key／角色與 Certificates, Identifiers & Profiles 存取範圍。Admin 名稱不自動證明權限。 |
| 403 / AGREEMENTS | 僅在收到 allowlisted agreements code 時，請 Account Holder 檢查／接受必要協議。 |
| 404 / NOT_FOUND | 查端點／資源可見性，不把列表端點 404 等同 Bundle ID 未註冊。 |
| 200 / BUNDLE_ID_MISSING | 已成功查詢但缺精確 Bundle ID；才需在正確 Team 註冊本 App ID。 |
| 429 / RATE_LIMIT | 等候後再手動唯讀診斷，不換 Key／憑證，不自動重跑初始化。 |
| 5xx / SERVER | Apple 服務異常；沒有權限不足證據，不修改證書。 |
| 400、409 / INVALID_REQUEST | 參數／資源狀態或 API 相容性；檢查呼叫，不先改角色。 |
| PROTOCOL / CLIENT_COMPATIBILITY | 格式或 SDK/token 介面問題，非權限結論。 |
| NETWORK / TLS | runner 網路／DNS／TLS／逾時，非權限結論。 |
| 未知或舊 UnexpectedResponse | 標為 unknown／unclassified；不從原文字串猜測 403。 |

**對這次舊 Run，目前沒有證據要求先更改 Apple Developer 設定。保持現有 Admin Key、Team、證書與 App 設定，先取得新的唯讀診斷結果，再按上表判斷。** 測試均為模擬回應，不能代替真實 Apple 權限驗證。

## 獨立手動唯讀診斷：同一 JWT 比較 Apps 與 Certificates

**Diagnose Apple Signing (read only)** 僅 main + workflow_dispatch，保留 signing-bootstrap 的三個 Admin Secrets 與 APPLE_TEAM_ID。它不接收 MATCH_PASSWORD／SIGNING_REPO_PAT，不呼叫 match、不建立 keychain、不修改憑證、App ID、Profile 或 Secrets；不自動執行。

使用者已確認 .p8 檔名與 Key ID 相符。新的診斷只從同一個已建立的 Admin Team token 讀取 `.text` 一次，建立不可變的 JWT 字串，分別呼叫：

- `GET /v1/apps?limit=1`
- `GET /v1/certificates?limit=1`

每個請求一次，不刷新 JWT、不重試、不跟隨重新導向／下一頁。第一個 API 即使回 401、403、429、5xx 或網路錯誤，仍收集第二個結果，最後才決定 workflow 成功與否。HTTP 成功且列表為空仍代表該讀取認證成功；不公開 App 清單或證書內容。

### JWT 本機安全檢查

依 Apple [Generating Tokens for API Requests](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests) 檢查下列條件，只輸出 PASS／FAIL：

| 欄位 | 條件（不印實際值） |
| --- | --- |
| structure | 合法三段 compact JWT、可解析的 header／payload |
| alg | ES256 |
| kid | 格式正確，且與此次 Admin Key ID 設定一致 |
| iss | UUID，且與此次 Admin Issuer ID 設定一致（Team Key） |
| aud | appstoreconnect-v1 |
| iat | 整數 Unix 秒、正數、不晚於 runner 現在時間 |
| exp | 整數、尚未過期、晚於 iat；exp−iat 不超過 1200 秒，亦不超過未來 1200 秒 |
| signature | 用同一份 p8 的公開金鑰在本機驗證 ES256 簽章 |

fastlane 2.228.0 會將 iat 往前調 60 秒，預設 duration=500，因此 lifetime 約 560 秒。不能只檢查 duration=1200 就視為安全，因為配合回溯 iat 可能讓 exp−iat 變成 1260 秒。診斷會回報失敗，不自動修改生成參數、金鑰或 Secrets。

kid／iss 的 PASS 只證明 JWT 與目前設定一致，**不證明 Apple 端此 Key／Issuer 配對仍有效、未撤銷或屬於預期 Team**。本機時間檢查也不能代替 Apple 時鐘。p8 檔名相符及本機簽章通過都不代表 Apple 必定接受 JWT。

### 新輸出與判讀

採用 IPC schema 2，只包含八項布林檢查、兩個固定資源的 HTTP／分類／白名單 code，以及固定結論。Python 會重新驗證全部欄位並重算結論。沒有 token、payload／header、實際 kid／iss、時間戳、簽章值或私鑰。未在白名單的 Apple code 只顯示 FILTERED_OR_ABSENT，不回顯原值。

```text
JWT local checks (values withheld): structure=PASS alg=PASS kid=PASS iss=PASS aud=PASS iat=PASS exp=PASS signature=PASS
Apple same-JWT probe: resource=apps method=GET HTTP=200 category=OK apple_code=FILTERED_OR_ABSENT
Apple same-JWT probe: resource=certificates method=GET HTTP=401 category=AUTHENTICATION apple_code=NOT_AUTHORIZED
JWT/API comparison [CERTIFICATES_AUTHENTICATION_REJECTED]: ...
```

| 結果 | 判讀 |
| --- | --- |
| 本機 JWT 欄位／簽章未通過 | JWT_LOCAL_INVALID；先查本機生成／設定一致性，不能直接說 Apple 權限不足。 |
| Apps 401、Certificates 401 | JWT_AUTHENTICATION_REJECTED；兩個 API 都拒絕同一 JWT，查共同的 Key／Issuer 有效性、時效與時鐘。不能僅靠此結果判定哪個 claim 錯誤。 |
| Apps 200、Certificates 401 | CERTIFICATES_AUTHENTICATION_REJECTED；不是該 JWT 全面遭拒，需查憑證端點／Team 存取政策。401 不是 403 權限不足的證明。 |
| Apps 200、Certificates 403 | CERTIFICATES_ACCESS_DENIED；查憑證資源特定權限／政策或明確的協議錯誤。 |
| Certificates 200、Apps 401／403 | Apps 特定認證／存取失敗，不是共同 JWT 全面遭拒。 |
| 一個成功、另一個 429／5xx／網路／格式錯誤 | 對應 API 失敗，依個別 HTTP／分類處理，不直接改角色。 |
| 兩個 200 且本機 JWT 檢查通過 | AUTHENTICATED_BOTH；只證明這兩種唯讀呼叫，不證明有建立簽署資產權限。 |
| 其他混合失敗（如 401／503、兩個 403） | INCONCLUSIVE，不過度歸因為共同 JWT 或單一憑證權限問題。 |

舊的初始化預檢維持 schema 1 的三資源／Team／精確 Bundle ID 驗證；一般 TestFlight 維持 Developer Key。此次只修改與測試，不自動執行任何 Apple workflow。使用者可自行在 Actions 選 main 手動執行唯讀診斷。

官方路由：[certificates](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-certificates)、[profiles](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-profiles)、[bundleIds](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-bundleids)。
