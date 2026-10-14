# MOOS 任務發佈指南

## 前置作業

### 1. 準備主機

安裝 Docker Engine、Docker Compose 與 Docker Buildx，並確認目前使用者可使用 Docker。
建立工作目錄與憑證目錄：

下載 Docker 客戶端映像：
```bash
# 正在處理客戶端註冊或安裝時，下載 client image
docker compose -f docker-compose.client.yaml pull
```

下載 Docker 發行者映像（私有映像，需要先 `docker login`）：
```bash
# 正在建立範本或交付檔時，下載 publish image
docker compose -f docker-compose.publisher.yaml pull
```

### 2. 編輯設定

編輯 `docker-compose.client.yaml` 的 `x-settings`，填入客戶主機與註冊資料：

| 設定 | 填入內容 |
|---|---|
| `DOCKER_GID` | 執行 `stat -c '%g' /var/run/docker.sock` 得到的 group ID |


編輯 `docker-compose.publisher.yaml` 的 `x-settings`，填入發行者主機與交付資料：

| 設定 | 填入內容 |
|---|---|
| `DOCKER_GID` | 執行 `stat -c '%g' /var/run/docker.sock` 得到的 group ID |
| `MRAN_DIR` | MOOS-ROS-Autonomous-Navigation (MRAN) 專案的絕對路徑 |
| `LICENSE_FILE` | 此客戶已簽發的 `.lic` 檔案絕對路徑 |
| `MISSION_FOLDER` | 已準備完成的 MOOS 任務資料夾絕對路徑 |
| `TARGET` | MOOS-ROS-Autonomous-Navigation (MRAN) 中具有 `manifest-TARGET.yaml` 的客戶識別值 |

## 操作流程

### 1. 客戶端：製作 enrollment 檔案，並提供給發行者

執行：

```bash
docker compose -f docker-compose.client.yaml run --rm enrollment
```

將 `enrollment/bundle-enrollment.tar` 傳給發行者。客戶保留本機 `~/.mmp-cred/`，
不要傳送其中的私鑰。

### 2. 發行者：放入客戶註冊檔

將收到的 `bundle-enrollment.tar` 放到發行者的 `enrollment/` 目錄。

### 3. 發行者：準備 MOOS 任務

將已準備完成的任務放在 `MISSION_FOLDER` 指定的位置。任務需包含 `deployment.yaml`
及其中列出的 `.moos`、`.bhv` 檔案；若沒有 behavior 檔，將 `bhv` 設為 `none`。
發行工具不會執行任務啟動腳本，也不會產生或修改這些檔案。

`deployment.yaml` 範例：

```yaml
components:
  shoreside:
    moos: shoreside.moos
    bhv: none
  vehicle:
    moos: vehicle.moos
    bhv: vehicle.bhv
```

### 4. 發行者：建立客戶交付範本

執行：

```bash
docker compose -f docker-compose.publisher.yaml run --rm template
```

編輯產生的 `delivery/template/`：填妥 `README.md`、圖資、設定及應用程式 `.env`，
移除所有 TODO。確認各應用程式使用相同的 `MISSION_PACKAGE`，並填入任務中存在的
`MISSION_COMPONENT`。

### 5. 發行者：建立交付檔案

確認範本、`LICENSE_FILE` 與 `MISSION_FOLDER` 設定正確後執行：

```bash
docker compose -f docker-compose.publisher.yaml run --rm create
```

將產生的 `delivery/bundle-delivery.tar` 傳給客戶。不要傳送原始任務資料夾或發行者私鑰。

### 6. 客戶端：安裝交付檔

將收到的檔案存為 `delivery/bundle-delivery.tar`，再執行：

```bash
docker compose -f docker-compose.client.yaml run --rm install
```

安裝完成後，依 `install/runtime/README.md` 的指示啟動 MOOS 任務。
