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
從本目錄建置映像。

```sh
docker build --load --platform linux/amd64 --network host -t pz-server:local .
```

建置會以匿名存取、依建置架構選擇的官方 DepotDownloader，從 Steam 的公開穩定分支
下載目前的 Build 42 專用伺服器，並驗證下載器的 SHA-256；完成後才將檔案複製至
`linux/amd64` 最終映像。此步驟需要網路連線，且可能花費數分鐘。

下載層請使用 `--network host`，讓 Steam 連線直接使用部署主機的網路。

本映像刻意不使用在 Apple Silicon 上無法可靠執行的 32 位元 SteamCMD。若
DepotDownloader 建置失敗，Docker 會立刻以非零狀態結束；請保留最後成功的映像，
稍後再重新建置。

所有要連線的玩家都必須使用 Steam 的正常公開版本；請勿選擇 `Unstable`、`42.19` 或其他
Beta 分支，否則會與此 Build 42 Stable 伺服器發生版本不符。

## 持久化伺服器資料與首次啟動

Project Zomboid 會在容器內的 `/home/steam/Zomboid` 儲存產生的設定與多人存檔。映像的
entrypoint 會在這個目錄不存在時自動建立它。請掛載此路徑；**不要**掛載覆蓋
`/home/steam/pzserver`，該處存放的是映像內安裝的遊戲檔案。

第一次啟動時請保持終端機連接。以下範例會自動設定管理員密碼，並使用具名 Docker
volume `pz-data` 儲存設定與世界；volume 不存在時 Docker 會自動建立它。初始設定完成後，
從另一個終端機停止伺服器：

```sh
docker run --platform linux/amd64 --name pz-server -itd --stop-timeout 60 \
  -v pz-data:/home/steam/Zomboid \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  -e PZ_ADMIN_PASSWORD='請換成強密碼' \
  pz-server:local
```

`PZ_ADMIN_PASSWORD` 會在首次建立時自動設定 `admin` 帳號，因此不會要求互動輸入。
映像只會在偵測到 PZ 的兩個首次密碼提示時，經由僅存在於記憶體的私有 stdin FIFO 提供
這個值，避免 PZ 啟動器把密碼當成 command-line argument 寫進日誌，也不會把它當成伺服器
console 指令；未設定時維持 Project Zomboid 的正常啟動路徑。這個值仍會出現在 shell 歷史
與 `docker inspect` 的容器設定中，請勿使用容易猜測的密碼，並於首次初始化後從後續容器
設定中移除它。

### 本機測試時降低 Java heap

Project Zomboid 預設使用 `-Xmx8g`。若 Docker Desktop 的本機可用記憶體不足，可在 `docker run`
加入例如 `-e PZ_JAVA_XMX=2g`，讓這次啟動的 Java heap 上限改為 2 GiB：

```sh
docker run --platform linux/amd64 --name pz-server -itd \
  -v pz-data:/home/steam/Zomboid \
  -e PZ_JAVA_XMX=2g \
  pz-server:local
```

`PZ_JAVA_XMX` 只接受正整數加 `m` 或 `g`，例如 `512m`、`2g`；未設定時維持遊戲提供的
預設值。它限制的是 **Java heap**，不是 Docker 容器的總記憶體，仍可能因 Java 以外的記憶體
使用而 OOM；設定太小也可能讓伺服器無法正常載入世界或模組。

```sh
docker stop --timeout 60 pz-server
```

後續執行時，可在背景啟動既有且已設定的容器，或連接至其主控台：

```sh
docker start pz-server
docker logs --follow pz-server
```

重新建置映像後若要替換容器，請保留同一個 `pz-data` volume，並以新映像重複執行
`docker run` 命令。它包含 `Server/` 設定與 `Saves/Multiplayer/` 世界資料。可使用
`docker volume inspect pz-data` 查看其 Docker 管理的位置。

若刻意需要主機可見的檔案，也能改用 bind mount，例如
`-v "$PWD/data:/home/steam/Zomboid"`；此時 `data` 是主機目錄，必須由主機端建立並確保
容器內 `steam` 使用者可寫入。Dockerfile 無法建立部署主機上的這個目錄，因此本文的主要
指令採用 `pz-data` volume。

`STOPSIGNAL` 與 `--stop-timeout 60` 會讓伺服器有機會完成正常關閉。強制停止仍可能
遺失尚未儲存的進度；請定期備份持久化資料目錄。

## 僅限容器本機的管理指令

這些功能讓你登入 Linux 主機後，直接查詢目前人數，或下 PZ 的管理指令。設定完成後，平常只需記得：

```sh
docker exec pz-server pz-query         # 目前有幾個人在線上？
docker exec pz-server pz-rcon save     # 立刻存檔
docker exec pz-server pz-rcon quit     # 正常關閉伺服器
```

`pz-query` 不需要 RCON 或 RCON 密碼；它只會在容器內查詢 PZ 的 loopback A2S 狀態。`pz-rcon`
則用於存檔、公告與關服等管理動作。兩者都不會開放管理埠到網際網路或區網，也不需要額外在
Linux 安裝工具。

### 查詢線上人數（不需要 RCON）

伺服器正在運行時，直接執行：

```sh
docker exec pz-server pz-query
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

### 第 1 步：準備 RCON 密碼檔

在專案根目錄的 `secrets/` 中建立 `rcon-password` 文字檔，內容只放一行難以猜測的密碼。
這個檔案已被 Git 忽略。建立後讓容器內的 `steam` 使用者可以讀取：

```sh
chmod 0444 ./secrets/rcon-password
```

這個檔案是給 Linux 指令使用的 **RCON 密碼**，不是玩家登入密碼，也不是下面的
`PZ_ADMIN_PASSWORD`。

### 第 2 步：啟動伺服器

在原本的 `docker run` 指令加上三個 `PZ_RCON_*` 設定，以及密碼檔掛載即可。以下可直接
使用；請只替換 `PZ_ADMIN_PASSWORD` 的值。

```sh
docker run --platform linux/amd64 --name pz-server -itd --stop-timeout 60 \
  -v pz-data:/home/steam/Zomboid \
  -v ./secrets/rcon-password:/run/secrets/pz-rcon-password:ro \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  -e PZ_ADMIN_PASSWORD='請換成強密碼' \
  -e PZ_RCON_PASSWORD_FILE=/run/secrets/pz-rcon-password \
  -e PZ_RCON_PORT=27015 \
  -e PZ_SERVER_NAME=servertest \
  pz-server:local
```

這裡沒有 `-p 27015:27015`：這是刻意省略的。RCON 只供容器內的 `pz-rcon` 使用，玩家與
外部網路無法連線到它。

### 第 3 步：在 Linux 主機下管理指令

容器運行後，從同一台 Linux 主機執行：

```sh
docker exec pz-server pz-rcon save             # 立刻存檔
docker exec pz-server pz-rcon 'servermsg "伺服器將於 5 分鐘後維護"'
```

要維護或備份時，依序公告、存檔、關服：

```sh
docker exec pz-server pz-rcon 'servermsg "伺服器現在關閉以進行維護"'
docker exec pz-server pz-rcon save
docker exec pz-server pz-rcon quit
docker wait pz-server
```

注意：能執行 `docker exec` 的 Linux 使用者，就能下任何 PZ 管理指令。RCON 密碼會存進
`pz-data` 的 PZ 設定檔，且隨備份保存；請保護 Docker volume 與備份檔。若不設定
`PZ_RCON_PASSWORD_FILE`，RCON 不會啟用，伺服器仍照原本方式啟動。

## 排程備份後關閉 Linux 主機

[`scripts/pz-backup-and-poweroff.sh`](scripts/pz-backup-and-poweroff.sh) 是供 **root 的
crontab** 使用的主機端腳本。它不是 PZ console 或 RCON 指令；流程會先以
`docker stop --timeout 120 pz-server` 正常停服，再直接封存完整 `pz-data` volume，最後才
關閉整台 Linux 主機。

> 此腳本沒有 dry-run 模式。手動執行成功後會真的呼叫 `systemctl poweroff`，請先在維護時段
> 使用 mock 測試或確認你可接受主機關機。

腳本預設使用下列名稱；若部署時不同，可在 root crontab 中以同名環境變數覆寫：

| 項目 | 預設值 |
| --- | --- |
| 容器 | `pz-server` (`PZ_CONTAINER_NAME`) |
| Docker volume | `pz-data` (`PZ_VOLUME_NAME`) |
| 映像 | `pz-server:local` (`PZ_IMAGE_NAME`) |
| 備份目錄 | `/home/potsonhumer/pa-backup` (`PZ_BACKUP_DIR`) |

主機必須具備 Docker、`tar`、`sha256sum`、`flock`、`runuser`、`sync` 與 `systemctl`；並且
`potsonhumer` 使用者與 `root` 群組必須存在。安裝腳本：

```sh
sudo install -o root -g root -m 0750 \
  scripts/pz-backup-and-poweroff.sh \
  /usr/local/sbin/pz-backup-and-poweroff.sh
```

腳本會在不存在時以 `potsonhumer` 身分建立 `/home/potsonhumer/pa-backup`。封存檔與對應的
`.sha256` 校驗檔會是 `potsonhumer:root`、模式 `0640`。root 會先在自己的暫存目錄產生與驗證
備份，再交由 `potsonhumer` 發布到家目錄，以避免 root cron 在使用者可寫的家目錄中直接改
權限或刪除檔案。

每次成功執行後只保留最新三份：

```text
/home/potsonhumer/pa-backup/
├── pz-data-20260802T040000Z-1234.tar.gz
├── pz-data-20260802T040000Z-1234.tar.gz.sha256
├── pz-data-20260803T040000Z-1234.tar.gz
├── pz-data-20260803T040000Z-1234.tar.gz.sha256
├── pz-data-20260804T040000Z-1234.tar.gz
└── pz-data-20260804T040000Z-1234.tar.gz.sha256
```

請用 `sudo crontab -e` 安裝排程；例如每天 04:00 執行：

```cron
0 4 * * * /usr/local/sbin/pz-backup-and-poweroff.sh >> /var/log/pz-backup-and-poweroff.log 2>&1
```

腳本會在下列情況以非零狀態結束，並且**不會**關閉主機：容器或 volume 不存在、另一個備份
已執行、容器無法正常停止、封存或校驗失敗、或停止後 exit code 為 `137`（Docker 在 120 秒
後強制結束）。在失敗前不會刪除既有完成的備份；exit code `137` 時也不會建立新備份，請先
檢查 `docker logs pz-server` 後再處理。

排程時間與主機下次開機後是否自動啟動 PZ 是獨立的營運決策。後者由 Docker 的 restart policy
決定，這個腳本不會替你設定。

### 驗證與還原封存檔

在主機上可先驗證校驗檔：

```sh
cd /home/potsonhumer/pa-backup
sha256sum --check pz-data-<timestamp>.tar.gz.sha256
```

還原時建議先建立**新的** volume，避免舊世界殘留的檔案混入：

```sh
docker volume create pz-data-restore
docker run --rm --user 0:0 --entrypoint tar \
  -v pz-data-restore:/data \
  -v /home/potsonhumer/pa-backup:/backup:ro \
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
