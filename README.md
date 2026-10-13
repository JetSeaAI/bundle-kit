# bundle-kit

以 Docker Compose 執行加密任務的交付與安裝，支援 Linux amd64 與本機 Docker Engine。
客戶直接 clone 此 repository，使用已發佈的 image；不需編譯 bundle-tools 或取得其原始碼 submodule。

| 主機 | Compose 檔 | Service | Image tag |
|---|---|---|---|
| 客戶 | `docker-compose.client.yaml` | `enrollment`、`install` | `client` |
| 發行者 | `docker-compose.publisher.yaml` | `template`、`create` | `publish` |

## 準備

- 安裝 Docker Engine 與 Compose；發行者另外需要 Buildx。
- 確認目前使用者可執行 Docker，並可下載 `jetseaaiusvfleet/bundle-tools` 的對應 image。
- 發行者另需 MRAN-mmp repository、已簽發的 `.lic`，以及含 `deployment.yaml` 的已展開任務目錄。

將 `<BUNDLE_KIT_URL>` 替換為此公開 repository 的網址：

```bash
git clone <BUNDLE_KIT_URL> bundle-kit
cd bundle-kit
mkdir -p enrollment delivery install "${HOME}/.mmp-cred"
chmod 700 "${HOME}/.mmp-cred"
id -u
id -g
stat -c '%g' /var/run/docker.sock
```

依主機角色修改對應 Compose 檔的 `x-settings`：

| 設定 | 適用主機 | 填入內容 |
|---|---|---|
| `HOST_USER` | 兩者 | `id -u` 與 `id -g` 的結果，以 `UID:GID` 填入 |
| `DOCKER_GID` | 兩者 | Docker socket 的 group ID，取代 `CHANGE_ME` |
| `MRAN_DIR` | 發行者 | MRAN-mmp 的主機絕對路徑，唯讀掛載到 `/MRAN` |
| `LICENSE_FILE` | 發行者 | 已簽發 `.lic` 的主機絕對路徑 |
| `MISSION_FOLDER` | 發行者 | 已展開任務的主機絕對路徑，包含 `.moos`、`.bhv` 與 `deployment.yaml` |
| `TARGET` | 發行者 | MRAN-mmp 中有對應 `manifest-TARGET.yaml` 的客戶識別 |

- `BUNDLE_DIR` 預設為 Compose 檔所在目錄，容器內掛載為 `/bundle`。
- `ENROLLMENT_FILE`、`DELIVERY_FILE` 與 `INSTALL_DIR` 使用容器內路徑；發行者另有 `TEMPLATE_DIR`。
- YAML 的 `&名稱` 定義共用值，`*名稱` 引用該值；只需修改 `x-settings`。
- 每台主機使用自己的 checkout 與金鑰；setup 與 install 使用同一位主機使用者。
- 主機 `~/.mmp-cred/` 固定掛載到 `/.mmp-cred`；私鑰留在主機，不隨 TAR 傳送。
- 若自訂目錄，先建立來源目錄；掛載不會自動建立缺少的路徑。

確認設定並下載 image，只執行符合本機角色的指令：

```bash
# 客戶
docker compose -f docker-compose.client.yaml config --quiet
docker compose -f docker-compose.client.yaml pull
# 發行者
docker compose -f docker-compose.publisher.yaml config --quiet
docker compose -f docker-compose.publisher.yaml pull
```

## 客戶：註冊與安裝

1. 建立 enrollment：

   ```bash
   docker compose -f docker-compose.client.yaml run --rm enrollment
   ```

   將 `enrollment/bundle-enrollment.tar` 傳給發行者，保留本機 `~/.mmp-cred/`。

2. 將收到的交付檔放到 `delivery/bundle-delivery.tar`，執行安裝：

   ```bash
   docker compose -f docker-compose.client.yaml run --rm install
   ```

   安裝到 `install/runtime/` 並載入 image，不覆寫現有檔案或自動啟動應用。
   依安裝後的 README 執行 `compose_up.sh`。

## 發行者：準備與交付

1. 將客戶的 enrollment TAR 放到 `enrollment/bundle-enrollment.tar`，準備 template：

   ```bash
   docker compose -f docker-compose.publisher.yaml run --rm template
   ```

   編輯 `delivery/template/` 的 README、設定、圖資與應用 `.env`，移除 TODO。
   保留發行者公鑰，讓 `packages/` 與 `license/` 維持空白；所有應用共用同一個 `MISSION_PACKAGE`。

2. 確認 `LICENSE_FILE` 與 `MISSION_FOLDER` 後建立 delivery：

   ```bash
   docker compose -f docker-compose.publisher.yaml run --rm create
   ```

   將 `delivery/bundle-delivery.tar` 傳給客戶。任務會加密，原始任務與私鑰不放入交付檔。
   create 不會執行任務啟動腳本或產生 `.moos`／`.bhv`。

## 本機檔案與診斷

- `enrollment/`、`delivery/`、`install/` 的產出與本機憑證已排除於 Git；保留 `.gitkeep`。
- Compose 的本機設定變更仍會顯示於 Git，發佈前請確認路徑與識別值。
- 非空 template 或已存在的輸出預設不覆寫；請選擇新路徑，確認需要時才對 template 使用 `--force`。
- 在對應 command 清單加入 `--verbose` 可查看詳細診斷；各工具也支援 `--help`。
- 舊 `settings.yaml` 與 `--config` 已停用，請將設定移入 Compose 的 `x-settings`。
