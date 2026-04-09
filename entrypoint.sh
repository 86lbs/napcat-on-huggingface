
save_to_hf
#!/bin/bash
trap "" SIGPIPE

NAP_CONFIG="/app/napcat/config"
NAP_PLUGINS="/app/napcat/plugins"
QQ_CONFIG1="/app/.config/QQ"
QQ_CONFIG2="/home/user/.config/QQ"
mkdir -p $NAP_CONFIG $QQ_CONFIG1 $QQ_CONFIG2 $NAP_PLUGINS

# --- 通用上传函数 ---
_upload_to_hf() {
    local file=$1
    local repo_path=$2
    local label=$3
    for i in 1 2 3; do
        python3 -c "
import os
from huggingface_hub import HfApi
try:
    HfApi().upload_file(
        path_or_fileobj='$file',
        path_in_repo='$repo_path',
        repo_id=os.environ['DATASET_REPO'],
        repo_type='dataset',
        token=os.environ['HF_TOKEN']
    )
    print('[$label] 备份成功!')
except Exception as e:
    print(f'[$label] 备份失败: {e}')
    exit(1)
" && break
        echo "[$label] 重试 $i/3..."
        sleep 5
    done
}

# --- 备份 NapCat 配置 ---
save_napcat_to_hf() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 备份 NapCat 配置 ---"
    rm -f /tmp/napcat.zip
    zip -r /tmp/napcat.zip $NAP_CONFIG \
        --exclude "*/logs/*" \
        --exclude "*/webui/*"
    _upload_to_hf /tmp/napcat.zip napcat.zip NapCat配置
}

# --- 备份 QQ 配置（不含聊天记录）---
save_qq_to_hf() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 备份 QQ 配置 ---"
    rm -f /tmp/qq.zip
    zip -r /tmp/qq.zip $QQ_CONFIG1 $QQ_CONFIG2 \
        --exclude "*/logs/*" \
        --exclude "*/Cache/*" \
        --exclude "*/GPUCache/*" \
        --exclude "*/nt_db/*" \
        --exclude "*/nt_data/*" \
        --exclude "*/richMediaProxyFiles/*" \
        --exclude "*/cacheFile/*" \
        --exclude "*/crash/*" \
        --exclude "*/__MACOSX/*"
    _upload_to_hf /tmp/qq.zip qq.zip QQ配置
}

# --- 备份插件 ---
save_plugins_to_hf() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 备份插件数据 ---"
    rm -f /tmp/plugins.zip
    zip -r /tmp/plugins.zip $NAP_PLUGINS \
        --exclude "*/logs/*" \
        --exclude "*/Cache/*"
    _upload_to_hf /tmp/plugins.zip plugins.zip 插件
}

save_to_hf() {
    save_napcat_to_hf
    save_qq_to_hf
    save_plugins_to_hf
}

trap 'echo "Received SIGTERM"; save_to_hf; exit 0' SIGTERM SIGINT

# --- 恢复单个zip ---
restore_zip() {
    local zip_file="$1"
    local label="$2"
    python3 -c "
import zipfile, sys
zip_path = sys.argv[1]
label = sys.argv[2]
try:
    skipped = 0
    extracted = 0
    with zipfile.ZipFile(zip_path, 'r') as z:
        members = z.namelist()
        print(f'[恢复/{label}] 共 {len(members)} 个文件')
        for member in members:
            try:
                z.extract(member, '/')
                extracted += 1
            except Exception:
                skipped += 1
    print(f'[恢复/{label}] 成功 {extracted} 个，跳过 {skipped} 个')
except Exception as e:
    print(f'[恢复/{label}] 失败: {e}')
" "$zip_file" "$label"
}

# --- 1. 从 HF 恢复数据 ---
if [ -n "${HF_TOKEN}" ] && [ -n "${DATASET_REPO}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 正在同步：从 HF Dataset 获取备份 ---"
    python3 -c "
import os
from huggingface_hub import hf_hub_download

# napcat.zip 兼容旧格式（旧版同时含 NapCat + QQ 配置）
# qq.zip 新格式单独的 QQ 配置（若存在则覆盖旧版内容）
for filename, label in [('napcat.zip', 'NapCat/QQ配置'), ('qq.zip', 'QQ配置'), ('plugins.zip', '插件')]:
    try:
        path = hf_hub_download(
            repo_id=os.environ['DATASET_REPO'],
            filename=filename,
            repo_type='dataset',
            token=os.environ['HF_TOKEN']
        )
        print(f'[下载] {filename} -> {path}')
        with open(f'/tmp/restore_{filename}.path', 'w') as f:
            f.write(path)
    except Exception as e:
        print(f'[下载] {filename} 不存在或失败: {e}')
"
    for zip_label in "napcat.zip:NapCat/QQ配置" "qq.zip:QQ配置" "plugins.zip:插件"; do
        zip_file="${zip_label%%:*}"
        label="${zip_label##*:}"
        path_file="/tmp/restore_${zip_file}.path"
        if [ -f "$path_file" ]; then
            restore_zip "$(cat $path_file)" "$label"
        fi
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 恢复完成，目录状态 ---"
    python3 -c "
import glob
for path in ['/app/.config/QQ', '/home/user/.config/QQ', '/app/napcat/plugins']:
    files = glob.glob(path + '/**', recursive=True)
    print(f'  {path}: {len(files)} 个文件/目录')
"
fi

# --- 2. 检查 WebUI 配置 ---
CONFIG_PATH="$NAP_CONFIG/webui.json"
if [ ! -f "${CONFIG_PATH}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 生成默认 WebUI 配置..."
    cat > "${CONFIG_PATH}" << EOF
{
    "host": "0.0.0.0",
    "port": 6099,
    "token": "${NAPCAT_WEBUI_SECRET_KEY:-admin}",
    "loginRate": 3
}
EOF
fi

rm -rf /tmp/.X*

# --- 3. 定时备份（每30分钟）---
periodic_backup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [备份] 将在 3 分钟后执行首次备份..."
    sleep 180
    save_to_hf
    while true; do
        sleep 1800
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- 定时备份（每30分钟）---"
        save_to_hf
    done
}
periodic_backup &

# --- 4. 调试WS保活 ---
debug_keepalive() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [保活] 等待 NapCat WebUI 启动..."
    while ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6099/api/auth/check | grep -q "200"; do
        sleep 3
    done
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [保活] WebUI 已就绪，启动保活进程..."

    python3 -u << 'PYEOF'
import os, time, json, asyncio, hashlib
import urllib.request

BASE = "http://127.0.0.1:6099"
TOKEN = os.environ.get("NAPCAT_WEBUI_SECRET_KEY") or os.environ.get("WEBUI_TOKEN", "admin")

def make_hash(token):
    return hashlib.sha256((token + ".napcat").encode()).hexdigest()

def login():
    for i in range(5):
        try:
            data = json.dumps({"hash": make_hash(TOKEN)}).encode()
            req = urllib.request.Request(
                f"{BASE}/api/auth/login",
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                resp = json.loads(r.read())
                credential = resp.get("data", {}).get("Credential")
                if credential:
                    print(f"[保活] 登录成功", flush=True)
                    return credential
                print(f"[保活] 登录响应: {resp}", flush=True)
        except Exception as e:
            print(f"[保活] 登录失败({i+1}/5): {e}", flush=True)
            time.sleep(5)
    return None

def create_debug_adapter(credential):
    try:
        req = urllib.request.Request(
            f"{BASE}/api/Debug/create",
            data=b"{}",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {credential}"
            },
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            resp = json.loads(r.read())
            ws_token = resp.get("data", {}).get("token")
            if ws_token:
                print(f"[保活] 调试适配器创建成功", flush=True)
                return ws_token
            print(f"[保活] 创建适配器响应: {resp}", flush=True)
    except Exception as e:
        print(f"[保活] 创建适配器失败: {e}", flush=True)
    return None

async def keep_ws_alive(ws_token):
    import websockets
    url = f"ws://127.0.0.1:6099/api/Debug/ws?token={ws_token}"
    try:
        async with websockets.connect(
            url,
            ping_interval=30,
            ping_timeout=10,
        ) as ws:
            print(f"[保活] WS 连接已建立，保持中...", flush=True)
            async for msg in ws:
                pass
    except Exception as e:
        print(f"[保活] WS 连接断开: {e}", flush=True)

def run():
    while True:
        credential = login()
        if not credential:
            print("[保活] 无法登录，60秒后重试...", flush=True)
            time.sleep(60)
            continue

        ws_token = create_debug_adapter(credential)
        if not ws_token:
            print("[保活] 无法获取 WS token，30秒后重试...", flush=True)
            time.sleep(30)
            continue

        asyncio.run(keep_ws_alive(ws_token))
        print("[保活] 连接断开，30秒后重新建立...", flush=True)
        time.sleep(30)

run()
PYEOF
}
debug_keepalive &

export FFMPEG_PATH=/usr/bin/ffmpeg
export QT_X11_NO_MITSHM=1

nginx &

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Run NapCat QQ..."
if [ -n "${ACCOUNT}" ]; then
    xvfb-run -a /opt/QQ/qq --no-sandbox -q "${ACCOUNT}" &
else
    xvfb-run -a /opt/QQ/qq --no-sandbox &
fi

QQ_PID=$!
wait $QQ_PID
save_to_hf
