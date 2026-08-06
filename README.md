# Project Zomboid 專用伺服器

本儲存庫會建立可在 Apple Silicon、Linux x86_64 與 Windows Docker Desktop 建置的
Project Zomboid **Build 42 Stable** 專用伺服器映像。建置的第一階段會依建置主機架構
自動選擇官方 [DepotDownloader](https://github.com/SteamRE/DepotDownloader)：ARM64 使用
`arm64`，x86_64 使用 `x64`，並從 Steam App ID `380870` 的公開穩定分支下載伺服器。
最終映像是 `linux/amd64`；在 Apple Silicon 上由 OrbStack 或 Docker Desktop 的 Apple
x86_64 轉譯執行完整遊戲與 Java 程序。**不會執行 SteamCMD**。若要更新伺服器檔案，請
重新建置映像。

## 先決條件

- Apple Silicon 主機上的 OrbStack，或已啟用 x86_64/Rosetta 容器轉譯的 Docker Desktop；
  一般 Linux／Windows x86_64 Docker 主機則可原生執行最終映像。請保留至少 8 GB 記憶體。
- Project Zomboid 伺服器沒有原生 ARM64 Linux 執行檔。下載器會在建置主機架構原生執行，
  遊戲則一律作為完整 `linux/amd64` 程序樹執行，避免 32 位元 SteamCMD 與 Box64 JVM 的問題。
- 用於持久化伺服器資料的 Docker volume。本文的 `pz-data` 具名 volume 會由 Docker 自動建立。

## 建置

請在 Apple Silicon、Linux x86_64 或 Windows Docker Desktop 的 Linux containers 模式中，
從本目錄以 Docker Compose 建置映像。

```sh
docker compose build
```

建置會以匿名存取、依建置架構選擇的官方 DepotDownloader，從 Steam 的公開穩定分支
下載目前的 Build 42 專用伺服器，並驗證下載器的 SHA-256；完成後才將檔案複製至
`linux/amd64` 最終映像。此步驟需要網路連線，且可能花費數分鐘。

Compose 已為下載層設定 host network，讓 Steam 連線直接使用部署主機的網路。

本映像刻意不使用在 Apple Silicon 上無法可靠執行的 32 位元 SteamCMD。若
DepotDownloader 建置失敗，Docker 會立刻以非零狀態結束；請保留最後成功的映像，
稍後再重新建置。

所有要連線的玩家都必須使用 Steam 的正常公開版本；請勿選擇 `Unstable`、`42.19` 或其他
Beta 分支，否則會與此 Build 42 Stable 伺服器發生版本不符。

## Docker Compose：持久化資料與啟動

Compose 會使用**既有名稱**為 `pz-data` 的 Docker volume，掛載至容器內的
`/home/steam/Zomboid`。其中包含 `420正版` 的設定與多人世界；**不要**掛載覆蓋
`/home/steam/pzserver`，該處存放映像內安裝的遊戲檔案。

### 第一次準備

準備本機 RCON 密碼檔。它只放一行難以猜測的 RCON 密碼，且已被 Git 忽略：

```sh
chmod 0444 ./secrets/rcon-password
```

接著建立本機環境檔：

```sh
cp .env.example .env
```

在 `.env` 設定第一次建立 `admin` 帳號所需的 `PZ_ADMIN_PASSWORD`，以及本機適用的
`PZ_JAVA_XMX`。例如 `PZ_JAVA_XMX=2g` 會將 Java heap 上限限制為 2 GiB。它只接受正整數
加 `m` 或 `g`，例如 `512m`、`2g`；未設定時維持遊戲提供的預設值。這限制的是 **Java heap**，
不是 Docker 容器的總記憶體，仍可能因 Java 以外的記憶體使用而 OOM。

`PZ_ADMIN_PASSWORD` 只在首次建立帳號時需要。帳號建立後可把 `.env` 中該值清空，再執行
`docker compose up -d` 讓 Compose 重建容器；密碼不會留在後續容器設定中。

### 啟動、停止與更新

首次啟動或要重建映像時：

```sh
docker compose up -d --build
```

平常啟動既有服務與查看日誌：

```sh
docker compose up -d
docker compose logs --follow
```

`docker compose down` 會以 60 秒寬限時間停止伺服器，且**不會**刪除 `pz-data`；不要加
`-v`。強制停止仍可能遺失尚未儲存的進度，請定期備份持久化資料。

PZ 遊戲更新時，普通建置可能重用已快取的伺服器下載層。請改用：

```sh
docker compose build --no-cache
docker compose up -d
```

### 從舊的手動容器遷移

若已有用 `docker run` 建立的 `pz-server`，Compose 無法同時使用相同容器名稱。先在維護時段
公告、存檔並正常關服，再刪除**容器本身**：

```sh
docker exec pz-server pz-rcon 'servermsg "伺服器現在關閉以切換 Docker Compose"'
docker exec pz-server pz-rcon save
docker exec pz-server pz-rcon quit
docker wait pz-server
docker rm pz-server
```

然後執行 `docker compose up -d --build`。不要刪除 `pz-data`；Compose 會接回同一份
`420正版` 設定與世界資料。

## 僅限容器本機的管理指令

這些功能讓你登入 Linux 主機後，直接查詢目前人數，或下 PZ 的管理指令。請在
`compose.yaml` 所在目錄執行，並先確認遊戲伺服器已啟動：

```sh
docker compose up -d
```

之後平常只需記得：

```sh
docker compose run pz-query         # 目前有幾個人在線上？
docker compose run pz-rcon save     # 立刻存檔
docker compose run pz-rcon quit     # 正常關閉伺服器
```

`pz-query` 不需要 RCON 或 RCON 密碼；它只會在容器內查詢 PZ 的 loopback A2S 狀態。`pz-rcon`
則用於存檔、公告與關服等管理動作。兩者都不會開放管理埠到網際網路或區網，也不需要額外在
Linux 安裝工具。若 `pz-server` 尚未啟動或已停止，這些指令會以非零狀態失敗，且不會自行
啟動遊戲伺服器。

### 查詢線上人數（不需要 RCON）

伺服器正在運行時，直接執行：

```sh
docker compose run pz-query
```

成功時，輸出固定為兩行：

```text
players=0
max_players=32
```

`players=0` 明確表示伺服器目前沒有人；它不是空白回應。若伺服器尚未啟動完成、已停止、沒有回應，
或設定中的 `DefaultPort` 無效，指令會在 stderr 顯示原因並以非零狀態結束，且**不會**輸出
`players=`。它會讀取所選伺服器的 `DefaultPort`；未設定時使用 `16261`，不需要另外發布埠。

### 使用 RCON 管理伺服器

Compose 會固定啟用容器本機 RCON，並把 `secrets/rcon-password` 掛載到
`/run/secrets/pz-rcon-password`；這裡沒有 RCON 對外埠。該密碼是 Linux 管理指令使用的
RCON 密碼，不是玩家或 `admin` 帳號密碼。

伺服器運行後，從同一台 Linux 主機執行：

```sh
docker compose run pz-rcon save             # 立刻存檔
docker compose run pz-rcon 'servermsg "伺服器將於 5 分鐘後維護"'
```

要維護或備份時，依序公告、存檔、關服：

```sh
docker compose run pz-rcon 'servermsg "伺服器現在關閉以進行維護"'
docker compose run pz-rcon save
docker compose run pz-rcon quit
```

每次 `docker compose run` 都會建立一個一次性 helper 容器。此處刻意**不使用** `--rm`：
指令完成後 helper 會維持 `exited`，可用下列指令查看輸出與清理：

```sh
docker compose ps -a
docker compose logs pz-query
docker compose rm pz-query pz-rcon
```

注意：能執行 Docker Compose 的 Linux 使用者，就能下任何 PZ 管理指令。RCON 密碼會存進
`pz-data` 的 PZ 設定檔，且隨備份保存；請保護 Docker volume 與備份檔。若不設定
`PZ_RCON_PASSWORD_FILE`，RCON 不會啟用，伺服器仍照原本方式啟動。

## 備份與排程關機

### 手動備份

Compose 備份只在 Linux 主機的本專案目錄中使用。先建立**主機上的**備份目錄：

```sh
mkdir -p /home/potsonhumer/pz-backup
chmod 0750 /home/potsonhumer/pz-backup
```

如果要改用其他路徑，在 `.env` 設定 `PZ_BACKUP_DIR=/你的/目錄`，並先自行建立該目錄。
未設定時，Compose 的 `pz-backup` volume 會使用 `/home/potsonhumer/pz-backup`。

伺服器正在運行時，執行：

```sh
docker compose run --rm --no-deps pz-backup
```

它會依序送出 RCON `save`、RCON `quit`，接著**無限期等待** `pz-server` 確實結束，最後才封存
唯讀的 `pz-data`。它不會使用 `docker stop` 或強制 timeout；RCON、等待、封存或校驗任一階段
失敗時都不會建立新的完成備份。成功後遊戲伺服器維持停止；需要恢復服務時再執行
`docker compose up -d`。

備份檔與 `.sha256` 校驗檔會留在目標目錄，檔案擁有者會沿用該目錄的擁有者。每次成功後只保留
最新三組完成的備份；`.partial` 與無關檔案不會列入或刪除。

`pz-backup` 掛載本機 Docker socket，僅用來確認與等待 `pz-server` 狀態。Docker socket 等同
Docker 管理權限，只有受信任的本機 Docker 管理者能執行此指令；它不發布任何 Docker、RCON 或
備份連接埠。`--rm` 會在 runner 結束後自動移除該一次性容器。

### 排程後關機

[`scripts/pz-backup-and-poweroff.sh`](scripts/pz-backup-and-poweroff.sh) 是供 **root 的
crontab** 使用的薄主機 wrapper。它在預設的 `/var/PZServer` 專案目錄執行
`docker compose run --rm --no-deps pz-backup`；`--no-deps` 確保不會協調、重建或啟動
`pz-server`，`--rm` 會清除已完成的 runner。只有該指令成功後才會 `sync` 並執行
`systemctl poweroff`。
它不直接停止 PZ，也不直接建立封存檔。

> 此腳本沒有 dry-run 模式。手動執行成功後會真的關閉主機，請先在維護時段使用 mock 測試。

若專案不在 `/var/PZServer`，可在 root crontab 設定 `PZ_COMPOSE_DIR`。安裝腳本：

```sh
sudo install -o root -g root -m 0750 \
  scripts/pz-backup-and-poweroff.sh \
  /usr/local/sbin/pz-backup-and-poweroff.sh
```

請用 `sudo crontab -e` 安裝排程；例如專案在預設位置時每天 04:00 執行：

```cron
0 4 * * * /usr/local/sbin/pz-backup-and-poweroff.sh >> /var/log/pz-backup-and-poweroff.log 2>&1
```

其他專案位置例如：

```cron
0 4 * * * PZ_COMPOSE_DIR=/srv/PZServer /usr/local/sbin/pz-backup-and-poweroff.sh >> /var/log/pz-backup-and-poweroff.log 2>&1
```

另一個備份已執行、RCON 關服失敗、PZ 未正常結束、封存或校驗失敗時，wrapper 會以非零狀態結束，
並且**不會**關閉主機或刪除既有完成備份。

排程時間與主機下次開機後是否自動啟動 PZ 是獨立的營運決策。後者由 Docker 的 restart policy
決定，這個腳本不會替你設定。

### 驗證與還原封存檔

在主機上可先驗證校驗檔：

```sh
cd /home/potsonhumer/pz-backup
sha256sum --check pz-data-<timestamp>.tar.gz.sha256
```

還原時建議先建立**新的** volume，避免舊世界殘留的檔案混入：

```sh
docker volume create pz-data-restore
docker run --rm --user 0:0 --entrypoint tar \
  -v pz-data-restore:/data \
  -v /home/potsonhumer/pz-backup:/backup:ro \
  pz-server:local \
  -C /data -xzf /backup/pz-data-<timestamp>.tar.gz
```

確認 `pz-data-restore` 中包含 `Server/` 與 `Saves/Multiplayer/` 後，再以它建立隔離的測試
容器，或在另行確認後取代正式容器的掛載 volume。不要在正在執行的 `pz-server` 上直接解壓縮。

## Zeabur 部署

Zeabur 會偵測儲存庫根目錄的 `Dockerfile` 並以它建置服務；本專案不需要 Docker Compose
或額外的啟動腳本。建立服務後，請保留 **Start Command** 空白，因為設定它會覆寫映像的
entrypoint，導致資料目錄準備、訊號處理與管理員密碼初始化被略過。

在服務設定中完成以下項目：

1. 在 Environment Variables 新增秘密 `PZ_ADMIN_PASSWORD`，以非互動方式建立 `admin`
   密碼。不要把這個值提交到 Git，也不要把它寫進 Dockerfile；首次初始化完成後，請從
   後續服務設定中移除它以縮小秘密暴露面。
2. 在 Volumes 新增一個持久化 Volume（例如 ID 為 `pz-data`），Mount Directory 設為
   `/home/steam/Zomboid`。此 Volume 保留 `Server/` 設定與 `Saves/Multiplayer/` 世界資料，
   因此重新部署或替換服務後仍可繼續使用。**不要**掛載 `/home/steam/pzserver`，否則空的
   Volume 會遮蔽映像內安裝的遊戲檔案。
3. 在 Networking 建立兩條公開 UDP forwarding，container port 分別為 `16261` 與 `16262`。
   記下 Zeabur 顯示的公開主機名稱與連接埠：玩家以第一條轉發的公開位址連線，兩條轉發都
   必須保留以支援 Steam query 與直接連線。

`SERVERNAME.ini` 的 `DefaultPort=16261` 與 `UDPPort=16262` 必須繼續對應上述**容器**目標
連接埠；若變更遊戲設定，請同時變更兩條 Zeabur UDP forwarding。首次部署後，請以外部
Project Zomboid 用戶端實際連線，並在重新部署後確認 Volume 中的設定與世界仍存在。

## UDP 連接埠

Dockerfile 中的 `EXPOSE` 僅作為文件用途，不會自行發布連接埠。必須使用 `-p`
發布實際使用的連接埠，並在主機防火牆、路由器或雲端安全性群組開放相同的 UDP
連接埠。`SERVERNAME.ini` 中的連接埠值必須與 Docker 發布設定相符。

### 目前版本的預設連接埠

目前文件記載的預設連接埠為 `16261/udp` 與 `16262/udp`：

```sh
docker run --platform linux/amd64 --name pz-server -d -it --stop-timeout 60 \
  -v pz-data:/home/steam/Zomboid \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  pz-server:local
```

### 41.77 版以前的舊版連接埠

對於設定為 41.77 版以前的 Project Zomboid 伺服器執行檔，請改為發布
`16261/udp`、`8766/udp` 與 `8767/udp`。映像中繼資料會宣告這些連接埠以供辨識，
但僅發布連接埠並不會把目前的伺服器建置變成舊版建置。

```sh
docker run --platform linux/amd64 --name pz-server-legacy -d -it --stop-timeout 60 \
  -v pz-data-legacy:/home/steam/Zomboid \
  -p 16261:16261/udp \
  -p 8766:8766/udp \
  -p 8767:8767/udp \
  pz-server:local
```

變更遊戲內 UDP 連接埠時，也要一併變更對應的 `-p` 選項、Zeabur UDP forwarding 或主機
網路規則。每個伺服器實例都需要一組未被占用的 UDP 連接埠。

## 更新

映像在執行時刻意維持不可變。請透過重新建置更新至 Steam 公開穩定分支當時最新的
Build 42 版本：

```sh
docker build --pull --load --platform linux/amd64 --network host -t pz-server:local .
```

42.19 Unstable 的世界不相容於 42.20 Stable。本專案的 42.20 更新會建立新世界；請使用
新的 `pz-data` volume，而不要掛載舊的 42.19 資料。停止與移除舊容器後，以本文件的
`docker run` 指令建立替代容器。
