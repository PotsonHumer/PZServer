# Project Zomboid 專用伺服器

本儲存庫會建立可在 Apple Silicon、Linux x86_64 與 Windows Docker Desktop 建置的
Project Zomboid **Build 42 Unstable** 專用伺服器映像。建置的第一階段會依建置主機架構
自動選擇官方 [DepotDownloader](https://github.com/SteamRE/DepotDownloader)：ARM64 使用
`arm64`，x86_64 使用 `x64`，並從 Steam App ID `380870` 的 `unstable` 分支下載伺服器。
最終映像是 `linux/amd64`；在 Apple Silicon 上由 OrbStack 或 Docker Desktop 的 Apple
x86_64 轉譯執行完整遊戲與 Java 程序。**不會執行 SteamCMD**。若要更新伺服器檔案，請
重新建置映像。

## 先決條件

- Apple Silicon 主機上的 OrbStack，或已啟用 x86_64/Rosetta 容器轉譯的 Docker Desktop；
  一般 Linux／Windows x86_64 Docker 主機則可原生執行最終映像。請保留至少 8 GB 記憶體。
- Project Zomboid 伺服器沒有原生 ARM64 Linux 執行檔。下載器會在建置主機架構原生執行，
  遊戲則一律作為完整 `linux/amd64` 程序樹執行，避免 32 位元 SteamCMD 與 Box64 JVM 的問題。
- 用於持久化伺服器資料的主機目錄或 Docker volume。

## 建置

請在 Apple Silicon、Linux x86_64 或 Windows Docker Desktop 的 Linux containers 模式中，
從本目錄建置映像。

```sh
docker build --platform linux/amd64 --network host -t pz-server:local .
```

建置會以匿名存取、依建置架構選擇的官方 DepotDownloader，從 Steam 的 `unstable`
分支下載最新的 Build 42 專用伺服器，並驗證下載器的 SHA-256；完成後才將檔案複製至
`linux/amd64` 最終映像。此步驟需要網路連線，且可能花費數分鐘。

下載層請使用 `--network host`，讓 Steam 連線直接使用部署主機的網路。

本映像刻意不使用在 Apple Silicon 上無法可靠執行的 32 位元 SteamCMD。若
DepotDownloader 建置失敗，Docker 會立刻以非零狀態結束；請保留最後成功的映像，
稍後再重新建置。

所有要連線的玩家也必須在 Steam 的「內容／Betas」中選擇 `Unstable` 分支，否則會與
此 Build 42 伺服器發生版本不符。

## 持久化伺服器資料與首次啟動

Project Zomboid 會在容器內的 `/home/steam/Zomboid` 儲存產生的設定與多人存檔。
請掛載此路徑；**不要**掛載覆蓋 `/home/steam/pzserver`，該處存放的是映像內安裝的
遊戲檔案。

第一次啟動時請保持終端機連接。以下範例會自動設定管理員密碼，並在掛載目錄下建立
設定；初始設定完成後，從另一個終端機停止伺服器：

```sh
mkdir -p data
docker run --platform linux/amd64 --name pz-server -itd --stop-timeout 60 \
  -v "$PWD/data:/home/steam/Zomboid" \
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

```sh
docker stop --time 60 pz-server
```

後續執行時，可在背景啟動既有且已設定的容器，或連接至其主控台：

```sh
docker start pz-server
docker logs --follow pz-server
```

重新建置映像後若要替換容器，請保留同一個 `data` 目錄，並以新映像重複執行
`docker run` 命令。掛載目錄包含 `Server/` 設定與 `Saves/Multiplayer/` 世界資料。

`STOPSIGNAL` 與 `--stop-timeout 60` 會讓伺服器有機會完成正常關閉。強制停止仍可能
遺失尚未儲存的進度；請定期備份持久化資料目錄。

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
  -v "$PWD/data:/home/steam/Zomboid" \
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
  -v "$PWD/data-legacy:/home/steam/Zomboid" \
  -p 16261:16261/udp \
  -p 8766:8766/udp \
  -p 8767:8767/udp \
  pz-server:local
```

變更遊戲內 UDP 連接埠時，也要一併變更對應的 `-p` 選項、Zeabur UDP forwarding 或主機
網路規則。每個伺服器實例都需要一組未被占用的 UDP 連接埠。

## 更新

映像在執行時刻意維持不可變。請透過重新建置更新至 Steam `unstable` 分支當時最新的
Build 42 版本：

```sh
docker build --pull --platform linux/amd64 --network host -t pz-server:local .
```

請先確認已備份舊容器的持久化資料目錄，再停止與移除舊容器。接著以相同的資料掛載
建立替代容器。
