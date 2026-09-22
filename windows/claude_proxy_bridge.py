#!/usr/bin/env python3
# claude_proxy_bridge.py - Multi-tenant Proxy Bridge with SOCKS5 upstream, Bypass & Stats Logging
# Cross-platform (Windows & Linux) version for Claude Code Proxy Toolkit

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

HOME = os.environ.get("USERPROFILE", "") or os.environ.get("HOME", "")
if not HOME:
    HOME = os.path.expanduser("~")

CONFIG_DIR = os.path.join(HOME, ".config", "claude-proxy")
PROGRAMDATA_DIR = os.environ.get("ProgramData", "C:\\ProgramData")
GLOBAL_CONFIG_DIR = os.path.join(PROGRAMDATA_DIR, "claude-proxy")
CONFIG_CANDIDATES = [
    os.path.join(CONFIG_DIR, "proxy.env"),
    os.path.join(GLOBAL_CONFIG_DIR, "proxy.env"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "proxy.env")
]
BYPASS_FILE = os.path.join(CONFIG_DIR, "bypass.conf")
LOCAL_BYPASS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bypass.conf")
GLOBAL_BYPASS_FILE = os.path.join(GLOBAL_CONFIG_DIR, "bypass.conf")
LOG_FILE = os.path.join(CONFIG_DIR, "traffic.jsonl")

PROXY_PORT = 19000
SOCKS5_URL = ""
PROXY_MODE = "anthropic_only"

def load_env():
    global PROXY_PORT, SOCKS5_URL, PROXY_MODE
    for conf_path in CONFIG_CANDIDATES:
        if os.path.isfile(conf_path):
            try:
                with open(conf_path, "r", encoding="utf-8") as f:
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
                if SOCKS5_URL:
                    break
            except Exception as e:
                sys.stderr.write(f"[bridge] Warning reading {conf_path}: {e}\n")

load_env()

if not SOCKS5_URL and len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
    SOCKS5_URL = sys.argv[1]

if len(sys.argv) > 2:
    try:
        PROXY_PORT = int(sys.argv[2])
    except ValueError:
        pass

if not SOCKS5_URL:
    sys.stderr.write("[bridge] Error: SOCKS5_URL is not set.\n")
    sys.stderr.write("Usage: python claude_proxy_bridge.py \"socks5://user:pass@host:port\" [port]\n")
    sys.exit(1)

parsed_socks = urllib.parse.urlparse(SOCKS5_URL)
SOCKS5_HOST = parsed_socks.hostname or "127.0.0.1"
SOCKS5_PORT = parsed_socks.port or 1080
SOCKS5_USER = urllib.parse.unquote(parsed_socks.username or "")
SOCKS5_PASS = urllib.parse.unquote(parsed_socks.password or "")

def load_bypass_rules():
    rules = set()
    for p in [LOCAL_BYPASS_FILE, BYPASS_FILE, GLOBAL_BYPASS_FILE]:
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
            "*.ru", "*.рф", "*.su"
        }
    return rules

BYPASS_RULES = load_bypass_rules()

def is_bypassed(target_host):
    target = target_host.lower().split(":")[0]
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
    """Detects PID and process name associated with local client_port."""
    if os.name == "nt":
        # Windows: default to claude or use netstat / Get-NetTCPConnection
        return 0, "claude"
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
                        return pid, app_name
            except Exception:
                continue
    except Exception:
        pass
    return 0, "unknown"

def log_traffic(client_ip, client_port, app_name, method, host, port, route, status, bytes_up, bytes_down, latency_ms):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "client_ip": client_ip,
        "client_port": client_port,
        "app": app_name,
        "method": method,
        "host": host,
        "port": port,
        "route": route,
        "status": status,
        "bytes_up": bytes_up,
        "bytes_down": bytes_down,
        "latency_ms": round(latency_ms, 2)
    }
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass

async def socks5_handshake(reader, writer, target_host, target_port):
    if SOCKS5_USER and SOCKS5_PASS:
        writer.write(b"\x05\x02\x00\x02")
    else:
        writer.write(b"\x05\x01\x00")
    await writer.drain()

    resp = await reader.readexactly(2)
    if resp[0] != 5:
        raise Exception(f"Invalid SOCKS5 version: {resp[0]}")
        
    auth_method = resp[1]
    if auth_method == 0x02:
        u_bytes = SOCKS5_USER.encode()
        p_bytes = SOCKS5_PASS.encode()
        auth_pkt = bytes([1, len(u_bytes)]) + u_bytes + bytes([len(p_bytes)]) + p_bytes
        writer.write(auth_pkt)
        await writer.drain()
        auth_resp = await reader.readexactly(2)
        if auth_resp[1] != 0:
            raise Exception("SOCKS5 authentication failed")
    elif auth_method != 0x00:
        raise Exception(f"SOCKS5 auth method {auth_method} not supported")

    host_bytes = target_host.encode("utf-8")
    req = bytes([5, 1, 0, 3, len(host_bytes)]) + host_bytes + struct.pack("!H", target_port)
    writer.write(req)
    await writer.drain()

    conn_resp = await reader.readexactly(4)
    if conn_resp[1] != 0:
        raise Exception(f"SOCKS5 connect error: {conn_resp[1]}")

    atyp = conn_resp[3]
    if atyp == 1:
        await reader.readexactly(4 + 2)
    elif atyp == 3:
        dlen = (await reader.readexactly(1))[0]
        await reader.readexactly(dlen + 2)
    elif atyp == 4:
        await reader.readexactly(16 + 2)

async def pipe_data(src_reader, dst_writer, counter):
    try:
        while True:
            data = await src_reader.read(65536)
            if not data:
                break
            counter[0] += len(data)
            dst_writer.write(data)
            await dst_writer.drain()
    except Exception:
        pass
    finally:
        try:
            dst_writer.close()
        except Exception:
            pass

async def handle_client(client_reader, client_writer):
    client_addr = client_writer.get_extra_info("peername")
    client_ip = client_addr[0] if client_addr else "127.0.0.1"
    client_port = client_addr[1] if client_addr else 0

    _, app_name = get_process_info(client_port)

    start_time = time.time()
    bytes_up = [0]
    bytes_down = [0]
    status_code = 200
    route = "UNKNOWN"
    target_host = "unknown"
    target_port = 443
    method = "UNKNOWN"

    try:
        line = await asyncio.wait_for(client_reader.readline(), timeout=10.0)
        if not line:
            return
        parts = line.decode("utf-8", errors="ignore").strip().split()
        if len(parts) < 2:
            return
        method = parts[0].upper()
        raw_target = parts[1]

        headers = []
        while True:
            h_line = await asyncio.wait_for(client_reader.readline(), timeout=10.0)
            if not h_line or h_line == b"\r\n" or h_line == b"\n":
                break
        if raw_target in ["/proxy.pac", "/pac"]:
            pac_body = (
                "function FindProxyForURL(url, host) {\n"
                "    if (shExpMatch(host, '*.anthropic.com') ||\n"
                "        shExpMatch(host, 'anthropic.com') ||\n"
                "        shExpMatch(host, '*.claude.ai') ||\n"
                "        shExpMatch(host, 'claude.ai') ||\n"
                "        shExpMatch(host, '*.usefathom.com') ||\n"
                "        shExpMatch(host, '*.statsig.com') ||\n"
                "        shExpMatch(host, '*.growthbook.io') ||\n"
                "        shExpMatch(host, '*.datadoghq.com')) {\n"
                f"        return 'PROXY 127.0.0.1:{PROXY_PORT}; DIRECT';\n"
                "    }\n"
                "    return 'DIRECT';\n"
                "}\n"
            ).encode("utf-8")
            resp = (
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/x-ns-proxy-autoconfig\r\n"
                b"Cache-Control: no-cache\r\n"
                f"Content-Length: {len(pac_body)}\r\n\r\n".encode()
                + pac_body
            )
            client_writer.write(resp)
            await client_writer.drain()
            return

        if method == "CONNECT":
            if ":" in raw_target:
                target_host, port_str = raw_target.split(":", 1)
                target_port = int(port_str)
            else:
                target_host = raw_target
                target_port = 443

            if is_bypassed(target_host):
                route = "DIRECT"
                try:
                    remote_reader, remote_writer = await asyncio.open_connection(target_host, target_port)
                except Exception as e:
                    status_code = 502
                    client_writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                    await client_writer.drain()
                    return
            else:
                route = "SOCKS5"
                try:
                    remote_reader, remote_writer = await asyncio.open_connection(SOCKS5_HOST, SOCKS5_PORT)
                    await socks5_handshake(remote_reader, remote_writer, target_host, target_port)
                except Exception as e:
                    status_code = 502
                    client_writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                    await client_writer.drain()
                    return

            client_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await client_writer.drain()

            t1 = asyncio.create_task(pipe_data(client_reader, remote_writer, bytes_up))
            t2 = asyncio.create_task(pipe_data(remote_reader, client_writer, bytes_down))
            await asyncio.gather(t1, t2)

        else:
            # Regular HTTP GET/POST
            target_host = "unknown"
            for h in headers:
                if h.lower().startswith(b"host:"):
                    target_host = h.split(b":", 1)[1].decode(errors="ignore").strip().split(":")[0]
                    break
            target_port = 80
            if is_bypassed(target_host):
                route = "DIRECT"
                remote_reader, remote_writer = await asyncio.open_connection(target_host, target_port)
            else:
                route = "SOCKS5"
                remote_reader, remote_writer = await asyncio.open_connection(SOCKS5_HOST, SOCKS5_PORT)
                await socks5_handshake(remote_reader, remote_writer, target_host, target_port)

            remote_writer.write(line)
            for h in headers:
                remote_writer.write(h)
            remote_writer.write(b"\r\n")
            await remote_writer.drain()

            t1 = asyncio.create_task(pipe_data(client_reader, remote_writer, bytes_up))
            t2 = asyncio.create_task(pipe_data(remote_reader, client_writer, bytes_down))
            await asyncio.gather(t1, t2)

    except Exception:
        status_code = 502
    finally:
        try:
            client_writer.close()
        except Exception:
            pass
        latency_ms = (time.time() - start_time) * 1000.0
        log_traffic(client_ip, client_port, app_name, method, target_host, target_port, route, status_code, bytes_up[0], bytes_down[0], latency_ms)

async def main():
    server = await asyncio.start_server(handle_client, "127.0.0.1", PROXY_PORT)
    print(f"[bridge] Python Proxy Bridge running on 127.0.0.1:{PROXY_PORT}")
    print(f"[bridge] Upstream SOCKS5: socks5://{SOCKS5_HOST}:{SOCKS5_PORT}")
    print(f"[bridge] Active bypass rules: {len(BYPASS_RULES)} entries")
    print(f"[bridge] Audit log: {LOG_FILE}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
