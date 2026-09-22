#!/bin/bash
# install_claude_proxy.sh - Полная автоматическая установка мультитенантного прокси-моста, аудита трафика и автопатчера Claude Code
# Использование:
#   ./install_claude_proxy.sh "socks5://USER:PASSWORD@HOST:PORT"
# Либо запустите без параметров для интерактивного ввода:
#   ./install_claude_proxy.sh

set -e

# Установка локали UTF-8 для вывода
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"

# 1. Определение SOCKS5 прокси (из аргументов либо через диалог/stdin)
SOCKS5_URL="${1:-}"

if [ -z "$SOCKS5_URL" ]; then
    echo "========================================================="
    echo " Настройка Claude Code Proxy (Мультитенантная архитектура)"
    echo "========================================================="
    echo ""
    echo "Укажите адрес вашего SOCKS5-прокси."
    echo "Формат: socks5://USER:PASSWORD@HOST:PORT"
    echo "   или: socks5://HOST:PORT (если без авторизации)"
    echo ""

    read -r -p "Введите адрес SOCKS5: " SOCKS5_URL || true
fi

# Проверка, что адрес прокси не пустой
if [ -z "$SOCKS5_URL" ]; then
    echo ""
    echo "Ошибка: Адрес SOCKS5-прокси не указан!"
    echo "Использование:"
    echo "  $0 \"socks5://USER:PASSWORD@HOST:PORT\""
    echo ""
    exit 1
fi

# Добавление схемы socks5://, если пользователь ввел только host:port или user:pass@host:port
if [[ "$SOCKS5_URL" != socks5://* && "$SOCKS5_URL" != socks5h://* ]]; then
    echo "Предупреждение: Добавлена схема socks5:// к указанному адресу."
    SOCKS5_URL="socks5://${SOCKS5_URL}"
fi

# Определение пользователя и домашней директории
TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    FIRST_USER=$(id -nu 1000 2>/dev/null || true)
    if [ -n "$FIRST_USER" ]; then
        TARGET_USER="$FIRST_USER"
    fi
fi
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "========================================================="
echo " Параметры установки:"
echo "   SOCKS5 прокси : $SOCKS5_URL"
echo "   Пользователь  : $TARGET_USER"
echo "   Домашняя папка: $USER_HOME"
echo "========================================================="

# 2. Установка системных пакетов
echo "=> [1/8] Установка системных зависимостей (inotify-tools, wget, curl, python3)..."
sudo apt-get update -qq
sudo apt-get install -y inotify-tools wget curl python3

# 3. Создание общесистемных каталогов и дефолтных настроек
echo "=> [2/8] Создание системных каталогов и списков фильтрации..."
sudo mkdir -p /etc/claude-proxy

cat << 'DEFAULT_ENV_EOF' | sudo tee /etc/claude-proxy/default.env > /dev/null
PROXY_MODE="anthropic_only"
DEFAULT_ENV_EOF

# Общий список доменов прямого выхода (bypass.conf)
cat << 'GLOBAL_BYPASS_EOF' | sudo tee /etc/claude-proxy/bypass.conf > /dev/null
# Claude Code Proxy - Destination Bypass List
# Все домены не из этого списка по умолчанию идут через SOCKS5 прокси!

# Локальная сеть и инфраструктура
localhost
127.0.0.1
::1
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
*.local

# Git репозитории
github.com
*.github.com
# Защита Copilot: *.githubusercontent.com не маскируется целиком,
# чтобы copilot-proxy.githubusercontent.com гарантированно шел через SOCKS5!
raw.githubusercontent.com
objects.githubusercontent.com
avatars.githubusercontent.com
user-images.githubusercontent.com
gitlab.com
*.gitlab.com
bitbucket.org
*.bitbucket.org

# Пакетные менеджеры (npm, pip, cargo, go)
npmjs.org
*.npmjs.org
yarnpkg.com
*.yarnpkg.com
pypi.org
*.pypi.org
pythonhosted.org
*.pythonhosted.org
crates.io
*.crates.io
pkg.go.dev
proxy.golang.org
rubygems.org
*.rubygems.org
packagist.org
*.packagist.org

# Образы и контейнеры
docker.io
*.docker.io
docker.com
*.docker.com
ghcr.io
quay.io

# Системные пакеты ОС
archive.ubuntu.com
security.ubuntu.com
deb.debian.org
*.debian.org

# Российские сервисы
*.ru
*.рф
*.su
GLOBAL_BYPASS_EOF
sudo chmod 644 /etc/claude-proxy/bypass.conf

# Общий список процессов прямого запуска (direct_processes.conf)
cat << 'GLOBAL_DIRECT_EOF' | sudo tee /etc/claude-proxy/direct_processes.conf > /dev/null
# Процессы, которые должны запускаться Claude НАПРЯМУЮ без прокси:
git
npm
npx
yarn
pnpm
docker
pip
pip3
cargo
go
# Примечание: curl и wget здесь НАМЕРЕННО отсутствуют, чтобы любые запросы шли через прокси.
GLOBAL_DIRECT_EOF
sudo chmod 644 /etc/claude-proxy/direct_processes.conf

# 4. Установка высокопроизводительного асинхронного ядра моста (claude_proxy_bridge.py)
echo "=> [3/8] Установка ядра прокси-моста с аудитом (/usr/local/bin/claude_proxy_bridge.py)..."
cat << 'BRIDGE_PY_EOF' | sudo tee /usr/local/bin/claude_proxy_bridge.py > /dev/null
#!/usr/bin/env python3
# claude_proxy_bridge.py - Multi-tenant Proxy Bridge with SOCKS5 upstream, Bypass & Stats Logging
# Part of Claude Code Proxy Toolkit

import asyncio
import socket
import struct
import urllib.parse
import ipaddress
import os
import sys
import time
import json
from datetime import datetime, timezone

USER = os.environ.get("USER", "")
HOME = os.environ.get("HOME", "")
if not HOME:
    HOME = os.path.expanduser("~")

CONFIG_DIR = os.path.join(HOME, ".config", "claude-proxy")
CONFIG_FILE = os.path.join(CONFIG_DIR, "proxy.env")
BYPASS_FILE = os.path.join(CONFIG_DIR, "bypass.conf")
GLOBAL_BYPASS_FILE = "/etc/claude-proxy/bypass.conf"
LOG_FILE = os.path.join(CONFIG_DIR, "traffic.jsonl")

PROXY_PORT = 19000
SOCKS5_URL = ""
PROXY_MODE = "anthropic_only"

def load_env():
    global PROXY_PORT, SOCKS5_URL, PROXY_MODE
    if os.path.isfile(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip("\"'")
                    if k == "PROXY_PORT":
                        PROXY_PORT = int(v)
                    elif k == "SOCKS5_URL":
                        SOCKS5_URL = v
                    elif k == "PROXY_MODE":
                        PROXY_MODE = v
        except Exception as e:
            sys.stderr.write(f"[bridge] Warning reading {CONFIG_FILE}: {e}\n")

load_env()

if not SOCKS5_URL and len(sys.argv) > 1:
    SOCKS5_URL = sys.argv[1]

if len(sys.argv) > 2:
    try:
        PROXY_PORT = int(sys.argv[2])
    except ValueError:
        pass

parsed_socks = urllib.parse.urlparse(SOCKS5_URL)
SOCKS5_HOST = parsed_socks.hostname or "127.0.0.1"
SOCKS5_PORT = parsed_socks.port or 1080
SOCKS5_USER = urllib.parse.unquote(parsed_socks.username or "")
SOCKS5_PASS = urllib.parse.unquote(parsed_socks.password or "")

def load_bypass_rules():
    rules = set()
    for p in [GLOBAL_BYPASS_FILE, BYPASS_FILE]:
        if os.path.isfile(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            rules.add(line.lower())
            except Exception:
                pass
    if not rules:
        rules = {
            "localhost", "127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
            "github.com", "*.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com",
            "avatars.githubusercontent.com", "user-images.githubusercontent.com",
            "gitlab.com", "*.gitlab.com", "bitbucket.org", "*.bitbucket.org",
            "npmjs.org", "*.npmjs.org", "yarnpkg.com", "*.yarnpkg.com",
            "pypi.org", "*.pypi.org", "pythonhosted.org", "*.pythonhosted.org",
            "crates.io", "*.crates.io", "pkg.go.dev", "proxy.golang.org",
            "docker.io", "*.docker.io", "docker.com", "*.docker.com",
            "archive.ubuntu.com", "security.ubuntu.com", "deb.debian.org",
            "*.ru", "*.рф", "*.su"
        }
    return rules

BYPASS_RULES = load_bypass_rules()

def is_bypassed(target_host):
    target = target_host.lower()
    try:
        ip = ipaddress.ip_address(target)
        for rule in BYPASS_RULES:
            if "/" in rule:
                try:
                    if ip in ipaddress.ip_network(rule, strict=False):
                        return True
                except ValueError:
                    pass
            elif rule == target:
                return True
        return False
    except ValueError:
        pass

    for rule in BYPASS_RULES:
        if rule.startswith("*."):
            suffix = rule[1:]
            if target.endswith(suffix) or target == rule[2:]:
                return True
        elif rule.startswith("."):
            if target.endswith(rule) or target == rule[1:]:
                return True
        elif rule == target:
            return True
        elif target.endswith("." + rule):
            return True
            
    return False

def get_process_info(client_port):
    try:
        port_hex = f"{client_port:04X}"
        inode = None
        for proto in ["tcp", "tcp6"]:
            path = f"/proc/net/{proto}"
            if not os.path.exists(path): continue
            with open(path, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 10 and parts[1].endswith(":" + port_hex):
                        inode = parts[9]
                        break
            if inode and inode != "0": break
            
        if not inode or inode == "0":
            return 0, "unknown"
            
        target = f"socket:[{inode}]"
        for pid_dir in os.listdir("/proc"):
            if not pid_dir.isdigit(): continue
            fd_dir = f"/proc/{pid_dir}/fd"
            if not os.path.exists(fd_dir): continue
            try:
                for fd in os.listdir(fd_dir):
                    if os.readlink(f"{fd_dir}/{fd}") == target:
                        pid = int(pid_dir)
                        comm_file = f"/proc/{pid}/comm"
                        cmd_file = f"/proc/{pid}/cmdline"
                        app_name = "unknown"
                        if os.path.exists(comm_file):
                            with open(comm_file, "r") as cf:
                                app_name = cf.read().strip()
                        if os.path.exists(cmd_file):
                            with open(cmd_file, "rb") as cf:
                                cmd_str = cf.read().replace(b"\x00", b" ").decode(errors="ignore").lower()
                            if "claude" in cmd_str:
                                app_name = "claude"
                            elif "copilot" in cmd_str or "codex" in cmd_str:
                                app_name = "copilot"
                            elif "antigravity" in cmd_str or "agy" in cmd_str:
                                app_name = "antigravity"
                            elif "cursor" in cmd_str:
                                app_name = "cursor"
                            elif app_name in ["node", "python", "python3", "bash", "sh"]:
                                for part in cmd_str.split():
                                    if part.endswith(".py") or part.endswith(".js"):
                                        app_name = os.path.basename(part)
                                        break
                        elif "claude" in app_name.lower():
                            app_name = "claude"
                        elif "copilot" in app_name.lower():
                            app_name = "copilot"
                        elif "antigravity" in app_name.lower():
                            app_name = "antigravity"
                        return pid, app_name
            except Exception:
                continue
    except Exception:
        pass
    return 0, "unknown"

async def socks5_connect(host, port):
    reader, writer = await asyncio.open_connection(SOCKS5_HOST, SOCKS5_PORT)
    if SOCKS5_USER and SOCKS5_PASS:
        writer.write(b"\x05\x01\x02")
    else:
        writer.write(b"\x05\x01\x00")
    await writer.drain()
    
    method_resp = await reader.readexactly(2)
    if method_resp[0] != 5:
        writer.close()
        raise ConnectionError(f"Invalid SOCKS5 version: {method_resp[0]}")
        
    selected_method = method_resp[1]
    if selected_method == 2:
        u = SOCKS5_USER.encode("utf-8")
        p = SOCKS5_PASS.encode("utf-8")
        writer.write(b"\x01" + bytes([len(u)]) + u + bytes([len(p)]) + p)
        await writer.drain()
        auth_resp = await reader.readexactly(2)
        if auth_resp[1] != 0:
            writer.close()
            raise PermissionError(f"SOCKS5 authentication failed: {auth_resp[1]}")
    elif selected_method == 255:
        writer.close()
        raise PermissionError("SOCKS5 rejected auth methods")
        
    h_bytes = host.encode("utf-8")
    req = b"\x05\x01\x00\x03" + bytes([len(h_bytes)]) + h_bytes + struct.pack("!H", port)
    writer.write(req)
    await writer.drain()
    
    conn_resp = await reader.readexactly(4)
    status_code = conn_resp[1]
    if status_code != 0:
        writer.close()
        raise ConnectionError(f"SOCKS5 connect failed code: {status_code}")
        
    atyp = conn_resp[3]
    if atyp == 1: await reader.readexactly(4 + 2)
    elif atyp == 3:
        dlen = (await reader.readexactly(1))[0]
        await reader.readexactly(dlen + 2)
    elif atyp == 4: await reader.readexactly(16 + 2)
        
    return reader, writer

async def pipe_stream(src, dst, counter, idx):
    try:
        while True:
            chunk = await src.read(65536)
            if not chunk:
                break
            dst.write(chunk)
            await dst.drain()
            counter[idx] += len(chunk)
    except Exception:
        pass
    finally:
        try:
            dst.close()
        except Exception:
            pass

def log_traffic_entry(entry):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    try:
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 30 * 1024 * 1024:
            old_file = LOG_FILE + ".1"
            if os.path.exists(old_file):
                os.remove(old_file)
            os.rename(LOG_FILE, old_file)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        sys.stderr.write(f"[bridge] Log error: {e}\n")

async def handle_client(client_r, client_w):
    addr = client_w.get_extra_info("peername")
    client_port = addr[1] if addr else 0
    pid, app_name = get_process_info(client_port)
    
    start_time = time.time()
    bytes_counter = [0, 0]
    
    status = 502
    target_host = "unknown"
    target_port = 443
    route = "UNKNOWN"
    
    try:
        req_line = await asyncio.wait_for(client_r.readline(), timeout=10.0)
        if not req_line:
            client_w.close()
            return
            
        parts = req_line.decode(errors="ignore").strip().split()
        if not parts or len(parts) < 2:
            client_w.close()
            return
            
        method = parts[0].upper()
        target = parts[1]
        
        if method == "CONNECT":
            if ":" in target:
                target_host, p_str = target.split(":", 1)
                target_port = int(p_str)
            else:
                target_host = target
                target_port = 443
        else:
            parsed_url = urllib.parse.urlparse(target)
            target_host = parsed_url.hostname or "localhost"
            target_port = parsed_url.port or 80
            
        while True:
            h_line = await client_r.readline()
            if not h_line or h_line == b"\r\n":
                break
                
        route = "DIRECT" if is_bypassed(target_host) else "SOCKS5"
        
        if route == "DIRECT":
            upstream_r, upstream_w = await asyncio.wait_for(
                asyncio.open_connection(target_host, target_port), timeout=15.0
            )
        else:
            upstream_r, upstream_w = await asyncio.wait_for(
                socks5_connect(target_host, target_port), timeout=20.0
            )
            
        if method == "CONNECT":
            client_w.write(b"HTTP/1.1 200 Connection established\r\nProxy-Agent: claude-proxy/2.0\r\n\r\n")
            await client_w.drain()
        else:
            upstream_w.write(req_line)
            await upstream_w.drain()
            
        status = 200
        
        t1 = asyncio.create_task(pipe_stream(client_r, upstream_w, bytes_counter, 0))
        t2 = asyncio.create_task(pipe_stream(upstream_r, client_w, bytes_counter, 1))
        await asyncio.gather(t1, t2)
        
    except Exception:
        status = 502
        try:
            client_w.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n502 Bad Gateway: Proxy upstream error\n")
            await client_w.drain()
        except Exception:
            pass
    finally:
        try:
            client_w.close()
        except Exception:
            pass
            
        dur_ms = round((time.time() - start_time) * 1000, 1)
        entry = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "pid": pid,
            "app": app_name,
            "target": f"{target_host}:{target_port}",
            "route": route,
            "status": status,
            "up": bytes_counter[0],
            "down": bytes_counter[1],
            "ms": dur_ms
        }
        log_traffic_entry(entry)

async def run_server():
    server = await asyncio.start_server(handle_client, "127.0.0.1", PROXY_PORT)
    print(f"[bridge] Claude Proxy Bridge active on 127.0.0.1:{PROXY_PORT}")
    print(f"[bridge] SOCKS5 upstream: {SOCKS5_HOST}:{SOCKS5_PORT}")
    print(f"[bridge] Bypass rules loaded: {len(BYPASS_RULES)} entries")
    print(f"[bridge] Traffic log: {LOG_FILE}")
    sys.stdout.flush()
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        pass
BRIDGE_PY_EOF
sudo chmod +x /usr/local/bin/claude_proxy_bridge.py

# 5. Установка утилиты просмотра статистики (/usr/local/bin/claude-stats)
echo "=> [4/8] Установка утилиты аудита и статистики (/usr/local/bin/claude-stats)..."
cat << 'STATS_PY_EOF' | sudo tee /usr/local/bin/claude-stats > /dev/null
#!/usr/bin/env python3
# claude-stats - Audit log & Traffic Statistics Viewer for Claude Code Proxy
import os
import sys
import json
import time
from datetime import datetime
from collections import defaultdict

def format_bytes(b):
    if b < 1024: return f"{b} B"
    elif b < 1024 * 1024: return f"{b/1024:.1f} KB"
    elif b < 1024 * 1024 * 1024: return f"{b/(1024*1024):.2f} MB"
    else: return f"{b/(1024*1024*1024):.2f} GB"

def find_log_files(user=None):
    files = []
    if user:
        p = f"/home/{user}/.config/claude-proxy/traffic.jsonl"
        if os.path.exists(p): files.append((user, p))
    else:
        home = os.path.expanduser("~")
        cur_log = os.path.join(home, ".config", "claude-proxy", "traffic.jsonl")
        if os.path.exists(cur_log):
            files.append((os.environ.get("USER", "current"), cur_log))
        elif os.path.exists("/home"):
            for u in sorted(os.listdir("/home")):
                p = f"/home/{u}/.config/claude-proxy/traffic.jsonl"
                if os.path.exists(p): files.append((u, p))
    return files

def read_entries(log_file):
    entries = []
    if not os.path.exists(log_file): return entries
    try:
        with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line: continue
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass
    except Exception as e:
        sys.stderr.write(f"Error reading {log_file}: {e}\n")
    return entries

def categorize_entry(app, target=""):
    a = (app or "").lower()
    t = (target or "").lower()
    if any(k in a for k in ["codex", "chatgpt"]) or any(k in t for k in ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com", "githubcopilot.com"]):
        return "OpenAI Codex / ChatGPT"
    elif any(k in a for k in ["antigravity", "agy"]) or any(k in t for k in ["antigravity.google", "generativelanguage.googleapis.com", "alkalimakersuite"]):
        return "Google Antigravity"
    elif any(k in a for k in ["claude", "anthropic"]) or any(k in t for k in ["anthropic.com", "claude.ai", "datadoghq.com"]):
        return "Claude Code"
    elif a in ["git", "npm", "npx", "yarn", "pnpm", "docker", "pip", "pip3", "cargo", "go"]:
        return "Сборщики (Direct)"
    elif a in ["curl", "wget"]:
        return "CLI (curl/wget)"
    return "Прочие процессы"

def print_stats(user, log_file, limit=10, app_filter=None):
    entries = read_entries(log_file)
    if app_filter:
        entries = [e for e in entries if app_filter.lower() in e.get("app", "").lower() or app_filter.lower() in categorize_entry(e.get("app", ""), e.get("target", "")).lower()]

    filter_note = f" (фильтр: \033[1;33m{app_filter}\033[0m)" if app_filter else " (\033[1;32mвсе инструменты: -app all\033[0m)"
    print("=" * 80)
    print(f"  📊 Статистика AI Proxy для пользователя: \033[1;36m{user}\033[0m{filter_note}")
    print(f"  Файл журнала: {log_file} (записей: {len(entries)})")
    print("=" * 80)

    if not entries:
        print("\n  Журнал пуст или по указанному фильтру нет записей.\n")
        return

    tools = defaultdict(lambda: {"count": 0, "socks5": 0, "direct": 0, "up": 0, "down": 0})
    apps = defaultdict(lambda: {"count": 0, "socks5": 0, "direct": 0, "up": 0, "down": 0})
    domains = defaultdict(lambda: {"count": 0, "socks5": 0, "direct": 0, "up": 0, "down": 0, "statuses": defaultdict(int), "last_ts": ""})
    
    total_up = 0
    total_down = 0

    for e in entries:
        app = e.get("app", "unknown")
        target = e.get("target", "unknown")
        tool_cat = categorize_entry(app, target)
        domain = target.split(":")[0]
        route = e.get("route", "UNKNOWN")
        status = e.get("status", 0)
        up = e.get("up", 0)
        down = e.get("down", 0)
        ts = e.get("ts", "")

        total_up += up
        total_down += down

        tools[tool_cat]["count"] += 1
        if route == "SOCKS5": tools[tool_cat]["socks5"] += 1
        else: tools[tool_cat]["direct"] += 1
        tools[tool_cat]["up"] += up
        tools[tool_cat]["down"] += down

        apps[app]["count"] += 1
        if route == "SOCKS5": apps[app]["socks5"] += 1
        else: apps[app]["direct"] += 1
        apps[app]["up"] += up
        apps[app]["down"] += down

        domains[domain]["count"] += 1
        if route == "SOCKS5": domains[domain]["socks5"] += 1
        else: domains[domain]["direct"] += 1
        domains[domain]["up"] += up
        domains[domain]["down"] += down
        domains[domain]["statuses"][status] += 1
        domains[domain]["last_ts"] = ts

    total_traffic = total_up + total_down
    print(f"\n  Общий объем данных: \033[1;32m{format_bytes(total_traffic)}\033[0m "
          f"(Отдано: {format_bytes(total_up)}, Принято: {format_bytes(total_down)})\n")

    # Table 0: AI Tools Summary
    print("  Категории и AI-инструменты:")
    print("┌───────────────────────────┬─────────┬─────────┬─────────┬────────────┬────────────┐")
    print("│ Инструмент / Категория    │ Запросы │ SOCKS5  │ Прямой  │ Трафик     │ % от общего│")
    print("├───────────────────────────┼─────────┼─────────┼─────────┼────────────┼────────────┤")
    for tool, d in sorted(tools.items(), key=lambda x: x[1]["up"]+x[1]["down"], reverse=True):
        t_tool = d["up"] + d["down"]
        pct = (t_tool / total_traffic * 100) if total_traffic > 0 else 0
        print(f"│ {tool:<25} │ {d['count']:<7} │ {d['socks5']:<7} │ {d['direct']:<7} │ {format_bytes(t_tool):<10} │ {pct:>8.1f}% │")
    print("└───────────────────────────┴─────────┴─────────┴─────────┴────────────┴────────────┘")

    # Table 1: Detailed Apps
    print("\n  Детализация по процессам:")
    print("┌───────────────────────────┬─────────┬─────────┬─────────┬────────────┬────────────┐")
    print("│ Приложение (App)          │ Запросы │ SOCKS5  │ Прямой  │ Трафик     │ % от общего│")
    print("├───────────────────────────┼─────────┼─────────┼─────────┼────────────┼────────────┤")
    for app, d in sorted(apps.items(), key=lambda x: x[1]["up"]+x[1]["down"], reverse=True):
        t_app = d["up"] + d["down"]
        pct = (t_app / total_traffic * 100) if total_traffic > 0 else 0
        print(f"│ {app:<25} │ {d['count']:<7} │ {d['socks5']:<7} │ {d['direct']:<7} │ {format_bytes(t_app):<10} │ {pct:>8.1f}% │")
    print("└───────────────────────────┴─────────┴─────────┴─────────┴────────────┴────────────┘")

    # Table 2: Top Domains
    print("\n  Топ целевых ресурсов:")
    print("┌──────────────────────────────────┬─────────┬─────────┬─────────┬────────────┬─────────────┐")
    print("│ Домен (Target Domain)            │ Запросы │ Маршрут │ Статус  │ Объем      │ Посл. визит │")
    print("├──────────────────────────────────┼─────────┼─────────┼─────────┼────────────┼─────────────┤")
    for dom, d in sorted(domains.items(), key=lambda x: x[1]["up"]+x[1]["down"], reverse=True)[:limit]:
        t_dom = d["up"] + d["down"]
        route_str = "SOCKS5" if d["socks5"] >= d["direct"] else "DIRECT"
        status_str = ",".join(f"{k}" for k in sorted(d["statuses"].keys()))
        last_time = d["last_ts"][11:19] if len(d["last_ts"]) >= 19 else d["last_ts"]
        print(f"│ {dom:<32} │ {d['count']:<7} │ {route_str:<7} │ {status_str:<7} │ {format_bytes(t_dom):<10} │ {last_time:<11} │")
    print("└──────────────────────────────────┴─────────┴─────────┴─────────┴────────────┴─────────────┘")

    # Recent Connections
    print(f"\n  Последние {min(6, len(entries))} соединений:")
    for e in entries[-6:]:
        color = "\033[32m" if e.get("status") == 200 else "\033[31m"
        r_color = "\033[35m" if e.get("route") == "SOCKS5" else "\033[36m"
        print(f"   [{e.get('ts','')}] {e.get('app','?')} -> {e.get('target','?')} "
              f"{r_color}{e.get('route','')}\033[0m {color}HTTP {e.get('status')}\033[0m "
              f"({format_bytes(e.get('up',0)+e.get('down',0))}, {e.get('ms',0)}ms)")

    # Recommendations
    recs = []
    for dom, d in domains.items():
        t_dom = d["up"] + d["down"]
        if d["socks5"] > 0 and t_dom > 5 * 1024 * 1024:
            if not any(k in dom for k in ["anthropic", "claude", "datadog", "statsig", "growthbook", "copilot", "openai", "chatgpt", "google", "antigravity"]):
                recs.append(f"Домен '{dom}' скачал {format_bytes(t_dom)} через SOCKS5. Если это не гео-чекер, рекомендуется добавить его в bypass.conf.")

    if recs:
        print("\n  💡 Рекомендации по оптимизации списков:")
        for r in recs:
            print(f"   • \033[33m{r}\033[0m")
    print("")

if __name__ == "__main__":
    script_name = os.path.basename(sys.argv[0]).lower()
    default_tool = None
    if "codex" in script_name:
        default_tool = "OpenAI Codex / ChatGPT"
    elif "antigravity" in script_name or "agy" in script_name:
        default_tool = "Google Antigravity"
    elif "claude" in script_name:
        default_tool = "Claude Code"

    target_user = None
    app_filter = None
    explicit_all = False
    args = sys.argv[1:]
    
    i = 0
    while i < len(args):
        a = args[i]
        if a in ["--app", "-app", "-a", "--tool", "-tool", "-t"] and i + 1 < len(args):
            val = args[i + 1]
            if val.lower() == "all":
                explicit_all = True
                app_filter = None
            else:
                app_filter = val
            i += 2
        elif a in ["--app=all", "-app=all"]:
            explicit_all = True
            app_filter = None
            i += 1
        elif a.startswith("--app=") or a.startswith("-app="):
            val = a.split("=", 1)[1]
            if val.lower() == "all":
                explicit_all = True
                app_filter = None
            else:
                app_filter = val
            i += 1
        elif not a.startswith("-") and not target_user:
            target_user = a
            i += 1
        else:
            i += 1
            
    if not explicit_all and not app_filter and default_tool:
        app_filter = default_tool
        
    logs = find_log_files(target_user)
    if not logs:
        print("Файлы журнала traffic.jsonl не найдены. Соединений пока не было.")
        sys.exit(0)
        
    for u, fpath in logs:
        print_stats(u, fpath, app_filter=app_filter)
STATS_PY_EOF
sudo chmod +x /usr/local/bin/claude-stats
sudo ln -sf /usr/local/bin/claude-stats /usr/local/bin/codex-stats
sudo ln -sf /usr/local/bin/claude-stats /usr/local/bin/antigravity-stats

# 6. Настройка шаблонов systemd
echo "=> [5/8] Настройка шаблонов systemd gost-claude@.service и claude-autopatch@.service..."
cat << 'SYSTEMD_PROXY_EOF' | sudo tee /etc/systemd/system/gost-claude@.service > /dev/null
[Unit]
Description=Claude Code Proxy Bridge for %i
After=network.target

[Service]
Type=simple
User=%i
EnvironmentFile=-/home/%i/.config/claude-proxy/proxy.env
ExecStart=/usr/bin/python3 -u /usr/local/bin/claude_proxy_bridge.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SYSTEMD_PROXY_EOF

cat << 'SYSTEMD_PATCH_EOF' | sudo tee /etc/systemd/system/claude-autopatch@.service > /dev/null
[Unit]
Description=Claude Code Extension Auto-patch Watcher for %i
After=network.target

[Service]
Type=simple
User=%i
ExecStart=/usr/local/bin/claude_watcher.sh
Restart=always
RestartSec=5
Environment=HOME=/home/%i

[Install]
WantedBy=multi-user.target
SYSTEMD_PATCH_EOF

sudo systemctl daemon-reload

# 7. Установка скрипта autopatch_claude.sh в /usr/local/bin
echo "=> [6/8] Установка /usr/local/bin/autopatch_claude.sh..."
cat << 'AUTOPATCH_SH_EOF' | sudo tee /usr/local/bin/autopatch_claude.sh > /dev/null
#!/bin/bash
# autopatch_claude.sh - patches Claude Code binaries (both VS Code extensions & Standalone CLI) to route via proxy
set -u

CONFIG_FILE="$HOME/.config/claude-proxy/proxy.env"
PROXY_PORT=""

if [ -f "$CONFIG_FILE" ]; then
    PORT_VAL=$(grep "^PROXY_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    [ -n "$PORT_VAL" ] && PROXY_PORT="$PORT_VAL"
fi

if [ -z "$PROXY_PORT" ]; then
    USER_UID=$(id -u)
    if [ "$USER_UID" -ge 1000 ]; then
        PROXY_PORT=$(( 19000 + (USER_UID - 1000) ))
    else
        PROXY_PORT=$(( 19000 + USER_UID ))
    fi
fi

PROXY_HTTP="http://127.0.0.1:$PROXY_PORT"
NO_PROXY_LIST="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,github.com,.github.com,gitlab.com,.gitlab.com,bitbucket.org,.bitbucket.org,npmjs.org,.npmjs.org,registry.npmjs.org,yarnpkg.com,.yarnpkg.com,pypi.org,.pypi.org,pythonhosted.org,.pythonhosted.org,files.pythonhosted.org,crates.io,.crates.io,pkg.go.dev,proxy.golang.org,rubygems.org,.rubygems.org,packagist.org,.packagist.org,docker.io,.docker.io,docker.com,.docker.com,ubuntu.com,.ubuntu.com,debian.org,.debian.org,*.ru,*.рф,*.su"
WRAPPER_VERSION_TAG="# CLAUDE_PROXY_WRAPPER_V3"

shopt -s nullglob
patched_any=0

create_wrapper() {
    local target_file="$1"
    local proxy_url="$2"
    local no_proxy="$3"
    cat << 'WRAPPER_TMP_EOF' > "$target_file"
#!/bin/bash
# CLAUDE_PROXY_WRAPPER_V3
TARGET_FILE="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
REAL_BIN="${TARGET_FILE}.real"

export HTTP_PROXY="PROXY_URL_PLACEHOLDER"
export HTTPS_PROXY="PROXY_URL_PLACEHOLDER"
export ALL_PROXY="PROXY_URL_PLACEHOLDER"
export http_proxy="PROXY_URL_PLACEHOLDER"
export https_proxy="PROXY_URL_PLACEHOLDER"
export all_proxy="PROXY_URL_PLACEHOLDER"
export NO_PROXY="NO_PROXY_PLACEHOLDER"
export no_proxy="NO_PROXY_PLACEHOLDER"

# Child process isolation
export BASH_ENV="$HOME/.config/claude-proxy/child_env.sh"

if [ ! -x "$REAL_BIN" ]; then
    echo "Error: $REAL_BIN not found or not executable" >&2
    exit 127
fi

exec "$REAL_BIN" "$@"
WRAPPER_TMP_EOF
    sed -i "s|PROXY_URL_PLACEHOLDER|$proxy_url|g" "$target_file"
    sed -i "s|NO_PROXY_PLACEHOLDER|$no_proxy|g" "$target_file"
    chmod +x "$target_file"
}

is_elf() {
    local file="$1"
    [ -f "$file" ] && [ ! -L "$file" ] && file -b "$file" | grep -q "ELF"
}

# 1. Patch VS Code extension binaries
VSCODE_DIRS=(
    "$HOME/.vscode-server/extensions"/anthropic.claude-code-*/resources/native-binary
    "$HOME/.vscode-server-insiders/extensions"/anthropic.claude-code-*/resources/native-binary
)

for dir in "${VSCODE_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    claude_bin="$dir/claude"
    claude_real="$dir/claude.real"

    if is_elf "$claude_bin"; then
        echo "[autopatch] Found VS Code extension ELF binary at $claude_bin. Moving to claude.real..."
        mv "$claude_bin" "$claude_real"
        chmod +x "$claude_real"
        create_wrapper "$claude_bin" "$PROXY_HTTP" "$NO_PROXY_LIST"
        echo "[autopatch] Created proxy wrapper at $claude_bin (port $PROXY_PORT)"
        patched_any=1
        continue
    fi

    if [ -f "$claude_real" ] && is_elf "$claude_real"; then
        if [ ! -f "$claude_bin" ] || ! grep -q "$WRAPPER_VERSION_TAG" "$claude_bin" 2>/dev/null || ! grep -q "$PROXY_HTTP" "$claude_bin" 2>/dev/null; then
            echo "[autopatch] Updating/fixing proxy wrapper at $claude_bin (port $PROXY_PORT)..."
            create_wrapper "$claude_bin" "$PROXY_HTTP" "$NO_PROXY_LIST"
            patched_any=1
        fi
        continue
    fi
done

# 2. Patch Standalone Claude CLI binaries (~/.local/share/claude/versions/*)
CLI_VERSIONS_DIR="$HOME/.local/share/claude/versions"
if [ -d "$CLI_VERSIONS_DIR" ]; then
    for bin_file in "$CLI_VERSIONS_DIR"/*; do
        [ -f "$bin_file" ] || continue
        [[ "$bin_file" == *.real ]] && continue
        [[ "$bin_file" == *tmp* || "$bin_file" == *.download || "$bin_file" == *.partial ]] && continue

        # Self-healing: if wrapper exists without .real, check for orphaned tmp real binary
        if [ -f "$bin_file" ] && [ ! -f "$bin_file.real" ]; then
            orphan=$(ls "${bin_file}".tmp.*.real 2>/dev/null | head -n 1 || true)
            if [ -n "$orphan" ] && is_elf "$orphan"; then
                mv "$orphan" "$bin_file.real"
            fi
        fi

        if is_elf "$bin_file"; then
            echo "[autopatch] Found standalone CLI ELF binary at $bin_file. Moving to $(basename "$bin_file").real..."
            mv "$bin_file" "$bin_file.real"
            chmod +x "$bin_file.real"
            create_wrapper "$bin_file" "$PROXY_HTTP" "$NO_PROXY_LIST"
            echo "[autopatch] Created proxy wrapper for standalone CLI at $bin_file (port $PROXY_PORT)"
            patched_any=1
            continue
        fi

        if [ -f "$bin_file.real" ] && is_elf "$bin_file.real"; then
            if ! grep -q "$WRAPPER_VERSION_TAG" "$bin_file" 2>/dev/null || ! grep -q "$PROXY_HTTP" "$bin_file" 2>/dev/null; then
                echo "[autopatch] Updating/fixing proxy wrapper for standalone CLI at $bin_file (port $PROXY_PORT)..."
                create_wrapper "$bin_file" "$PROXY_HTTP" "$NO_PROXY_LIST"
                patched_any=1
            fi
            continue
        fi
    done
fi

if [ "$patched_any" -eq 1 ]; then
    echo "[autopatch] Successfully applied patch(es) for user $USER (port $PROXY_PORT)."
    if [ "${1:-}" = "--restart" ] || [ "${RESTART_CLAUDE:-0}" = "1" ]; then
        echo "[autopatch] Restarting running Claude extension processes..."
        pkill -f 'anthropic.claude-code' || true
    fi
else
    if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--verbose" ]; then
        echo "[autopatch] All Claude binaries (VS Code & CLI) are up to date for user $USER (port $PROXY_PORT)."
    fi
fi
AUTOPATCH_SH_EOF
sudo chmod +x /usr/local/bin/autopatch_claude.sh

# 8. Установка скрипта claude_watcher.sh
echo "=> [7/8] Установка /usr/local/bin/claude_watcher.sh и /usr/local/bin/claude..."
cat << 'WATCHER_SH_EOF' | sudo tee /usr/local/bin/claude_watcher.sh > /dev/null
#!/bin/bash
# claude_watcher.sh - inotify daemon watching for new/updated Claude Code binaries
set -e

WATCH_DIRS=()
VSCODE_EXT_DIR="$HOME/.vscode-server/extensions"
VSCODE_INSIDERS_EXT_DIR="$HOME/.vscode-server-insiders/extensions"
CLI_VERSIONS_DIR="$HOME/.local/share/claude/versions"

mkdir -p "$VSCODE_EXT_DIR" 2>/dev/null || true
[ -d "$VSCODE_EXT_DIR" ] && WATCH_DIRS+=("$VSCODE_EXT_DIR")

[ -d "$VSCODE_INSIDERS_EXT_DIR" ] && WATCH_DIRS+=("$VSCODE_INSIDERS_EXT_DIR")

mkdir -p "$CLI_VERSIONS_DIR" 2>/dev/null || true
[ -d "$CLI_VERSIONS_DIR" ] && WATCH_DIRS+=("$CLI_VERSIONS_DIR")

echo "[watcher] Starting Claude Code auto-patch watcher for user $USER..."
/usr/local/bin/autopatch_claude.sh --verbose || true

if [ ${#WATCH_DIRS[@]} -eq 0 ]; then
    echo "[watcher] Error: No watchable directories found." >&2
    exit 1
fi

echo "[watcher] Watching: ${WATCH_DIRS[*]}"

inotifywait -m -r -e create -e moved_to --format '%w%f' "${WATCH_DIRS[@]}" 2>/dev/null | while read -r new_path; do
    if [[ "$new_path" == *"/anthropic.claude-code-"* ]] || [[ "$new_path" == *"/claude/versions/"* ]]; then
        [[ "$new_path" == *tmp* || "$new_path" == *.download || "$new_path" == *.partial ]] && continue
        echo "[watcher] Detected change at $new_path. Applying autopatch..."
        sleep 1
        /usr/local/bin/autopatch_claude.sh --restart || true
    fi
done
WATCHER_SH_EOF
sudo chmod +x /usr/local/bin/claude_watcher.sh

cat << 'CLAUDE_LAUNCHER_EOF' | sudo tee /usr/local/bin/claude > /dev/null
#!/bin/bash
# Global launcher for Claude Code CLI
set -e

USER_CLI="$HOME/.local/bin/claude"
if [ -x "$USER_CLI" ]; then
    exec "$USER_CLI" "$@"
fi

shopt -s nullglob
VERSIONS=("$HOME/.local/share/claude/versions"/*)
if [ ${#VERSIONS[@]} -gt 0 ]; then
    for bin in "${VERSIONS[@]}"; do
        [[ "$bin" == *.real ]] && continue
        if [ -x "$bin" ]; then
            exec "$bin" "$@"
        fi
    done
fi

for ext_dir in "$HOME/.vscode-server/extensions"/anthropic.claude-code-*/resources/native-binary; do
    if [ -x "$ext_dir/claude" ]; then
        exec "$ext_dir/claude" "$@"
    fi
done

echo "Ошибка: Claude Code не установлен." >&2
echo "Запустите install_claude_cli.sh для установки автономного CLI." >&2
exit 1
CLAUDE_LAUNCHER_EOF
sudo chmod +x /usr/local/bin/claude

# 9. Установка скрипта install_claude_cli.sh в /usr/local/bin
cat << 'CLI_INSTALL_EOF' | sudo tee /usr/local/bin/install_claude_cli.sh > /dev/null
#!/bin/bash
# install_claude_cli.sh - Установка официального Claude Code CLI через прокси
set -e

export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"

CONFIG_FILE="$HOME/.config/claude-proxy/proxy.env"
PROXY_PORT=""

if [ -f "$CONFIG_FILE" ]; then
    PROXY_PORT=$(grep "^PROXY_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [ -z "$PROXY_PORT" ]; then
    USER_UID=$(id -u)
    if [ "$USER_UID" -ge 1000 ]; then
        PROXY_PORT=$(( 19000 + (USER_UID - 1000) ))
    else
        PROXY_PORT=$(( 19000 + USER_UID ))
    fi
fi

PROXY_HTTP="http://127.0.0.1:$PROXY_PORT"
echo "=> Установка Claude Code CLI через персональный мост $PROXY_HTTP..."

export HTTP_PROXY="$PROXY_HTTP"
export HTTPS_PROXY="$PROXY_HTTP"
export ALL_PROXY="$PROXY_HTTP"
export http_proxy="$PROXY_HTTP"
export https_proxy="$PROXY_HTTP"
export all_proxy="$PROXY_HTTP"

curl -fsSL https://claude.ai/install.sh | bash

echo "=> Применение патчера к новому CLI..."
/usr/local/bin/autopatch_claude.sh --verbose || true

echo ""
echo "========================================================="
echo " Установка Claude Code CLI успешно завершена!"
echo " Проверить версию: claude --version"
echo " Запустить Claude: claude"
echo "========================================================="
CLI_INSTALL_EOF
sudo chmod +x /usr/local/bin/install_claude_cli.sh

# 10. Установка setup_claude_user.sh и начальная настройка пользователя
echo "=> [8/8] Установка вспомогательных скриптов и настройка пользователя..."
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/setup_claude_user.sh" ]; then
    sudo cp "$DIR/setup_claude_user.sh" /usr/local/bin/setup_claude_user.sh
    sudo chmod +x /usr/local/bin/setup_claude_user.sh
fi
if [ -f "$DIR/setup_codex.sh" ]; then
    sudo cp "$DIR/setup_codex.sh" /usr/local/bin/setup_codex.sh
    sudo chmod +x /usr/local/bin/setup_codex.sh
fi
if [ -f "$DIR/setup_antigravity.sh" ]; then
    sudo cp "$DIR/setup_antigravity.sh" /usr/local/bin/setup_antigravity.sh
    sudo chmod +x /usr/local/bin/setup_antigravity.sh
fi

# Запуск настройки для текущего пользователя
sudo /usr/local/bin/setup_claude_user.sh "$TARGET_USER" "$SOCKS5_URL"

echo ""
echo "========================================================="
echo " Базовая установка сервера успешно завершена!"
echo "   - Персональный мост : gost-claude@$TARGET_USER.service (активен)"
echo "   - Автопатчер        : claude-autopatch@$TARGET_USER.service (активен)"
echo ""
echo " Доступные команды:"
echo "   claude                  - запуск Claude Code CLI"
echo "   claude-stats            - статистика Claude Code (-app all для общей)"
echo "   codex-stats             - статистика Codex / ChatGPT (-app all для общей)"
echo "   antigravity-stats       - статистика Google Antigravity (-app all для общей)"
echo "   setup_codex.sh          - настройка VS Code Remote-SSH и Codex CLI"
echo "   setup_antigravity.sh    - настройка Antigravity Remote-SSH и CLI (agy)"
echo "   install_claude_cli.sh   - установить/переустановить Claude CLI"
echo "   sudo setup_claude_user.sh ИМЯ [SOCKS5_URL] - подключить нового пользователя"
echo "========================================================="