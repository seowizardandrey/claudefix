#!/bin/bash
# setup_codex.sh - Настройка OpenAI Codex / ChatGPT для пользователя через персональный прокси-мост
# Варианты:
#   1) VS Code Remote-SSH + плагин Codex (openai.chatgpt)
#   2) Codex CLI (npm i -g @openai/codex)
#   3) Оба варианта (all)
set -e

export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"

# 1. Определение пользователя и домашней директории
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
    USER_HOME="$HOME"
fi

CONFIG_FILE="$USER_HOME/.config/claude-proxy/proxy.env"
PROXY_PORT=""

if [ -f "$CONFIG_FILE" ]; then
    PROXY_PORT=$(grep "^PROXY_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [ -z "$PROXY_PORT" ]; then
    USER_UID=$(id -u "$TARGET_USER" 2>/dev/null || id -u)
    if [ "$USER_UID" -ge 1000 ]; then
        PROXY_PORT=$(( 19000 + (USER_UID - 1000) ))
    else
        PROXY_PORT=$(( 19000 + USER_UID ))
    fi
fi

PROXY_URL="http://127.0.0.1:$PROXY_PORT"

echo "========================================================="
echo " Настройка OpenAI Codex / ChatGPT через персональный прокси"
echo " Пользователь: $TARGET_USER"
echo " Прокси-мост : $PROXY_URL"
echo "========================================================="

# Проверка активности службы прокси
if ! curl -s -o /dev/null -x "$PROXY_URL" https://chatgpt.com/ 2>/dev/null; then
    echo "Предупреждение: Персональный мост $PROXY_URL не отвечает на запросы к chatgpt.com."
    echo "Убедитесь, что служба запущена: sudo systemctl status gost-claude@$TARGET_USER"
fi

# Выбор режима работы
MODE="$1"
if [ -z "$MODE" ]; then
    echo ""
    echo "Выберите вариант настройки:"
    echo "  1) VS Code Remote-SSH + плагин openai.chatgpt"
    echo "  2) Codex CLI (npm i -g @openai/codex)"
    echo "  3) Установить и настроить оба варианта (all)"
    read -rp "Ваш выбор [1-3] (по умолчанию: 3): " CHOICE
    case "$CHOICE" in
        1) MODE="vscode" ;;
        2) MODE="cli" ;;
        *) MODE="all" ;;
    esac
fi

# Вспомогательная функция для обновления JSON-конфигов VS Code
update_vscode_json() {
    local json_file="$1"
    local dir_path
    dir_path=$(dirname "$json_file")
    mkdir -p "$dir_path"
    chown -R "$TARGET_USER":"$TARGET_USER" "$dir_path" 2>/dev/null || true

    python3 - << PYEOF
import json
import os

path = "$json_file"
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}

data["http.proxy"] = "$PROXY_URL"
data["http.proxySupport"] = "override"
data["http.proxyStrictSSL"] = True
data["chatgpt.proxy"] = "$PROXY_URL"

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
    chown "$TARGET_USER":"$TARGET_USER" "$json_file" 2>/dev/null || true
    chmod 644 "$json_file" 2>/dev/null || true
}

# --- ВАРИАНТ 1: VS Code Remote-SSH + плагин openai.chatgpt ---
setup_vscode() {
    echo ""
    echo "=> [1/2] Настройка окружения VS Code Remote-SSH на сервере..."
    
    # 1. Серверные конфигурации Remote-SSH
    local machine_settings="$USER_HOME/.vscode-server/data/Machine/settings.json"
    local machine_insiders="$USER_HOME/.vscode-server-insiders/data/Machine/settings.json"
    local user_code_settings="$USER_HOME/.config/Code/User/settings.json"

    update_vscode_json "$machine_settings"
    update_vscode_json "$machine_insiders"
    update_vscode_json "$user_code_settings"
    echo "   Конфигурация Machine settings.json успешно обновлена (proxy: $PROXY_URL)"

    # 2. Окружение Remote-SSH сервера (server-env.sh)
    mkdir -p "$USER_HOME/.vscode-server"
    cat << ENVEOF > "$USER_HOME/.vscode-server/server-env.sh"
# VS Code Remote-SSH server environment for $TARGET_USER
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"
ENVEOF
    chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.vscode-server/server-env.sh" 2>/dev/null || true
    chmod 644 "$USER_HOME/.vscode-server/server-env.sh" 2>/dev/null || true

    # 3. Установка плагина openai.chatgpt при наличии code CLI на сервере
    echo "   Проверка установщика расширений VS Code..."
    local code_bin=""
    if command -v code >/dev/null 2>&1; then
        code_bin="code"
    elif [ -f "$USER_HOME/.vscode-server/bin" ]; then
        code_bin=$(find "$USER_HOME/.vscode-server/bin" -name "code-server" 2>/dev/null | head -n 1 || true)
    fi

    if [ -n "$code_bin" ]; then
        echo "   Установка плагина openai.chatgpt через $code_bin..."
        su - "$TARGET_USER" -c "$code_bin --install-extension openai.chatgpt" 2>/dev/null || \
            $code_bin --install-extension openai.chatgpt 2>/dev/null || true
    else
        echo "   [Инфо] VS Code CLI на сервере пока не найден (первое подключение Remote-SSH еще не производилось)."
        echo "   Конфигурация прокси уже подготовлена в ~/.vscode-server/data/Machine/settings.json."
        echo "   При первом подключении с вашего ПК через Remote-SSH плагин 'openai.chatgpt' автоматически"
        echo "   будет работать через прокси $PROXY_URL."
    fi
}

# --- ВАРИАНТ 2: Codex CLI (npm i -g @openai/codex) ---
setup_cli() {
    echo ""
    echo "=> [2/2] Настройка Codex CLI (@openai/codex)..."

    # Проверка Node.js и npm
    if ! command -v npm >/dev/null 2>&1; then
        echo "   Node.js / npm не найден. Попытка установки..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq nodejs npm
        fi
    fi

    if command -v npm >/dev/null 2>&1; then
        echo "   Установка @openai/codex через прокси-мост $PROXY_URL..."
        export HTTP_PROXY="$PROXY_URL"
        export HTTPS_PROXY="$PROXY_URL"
        export ALL_PROXY="$PROXY_URL"
        export http_proxy="$PROXY_URL"
        export https_proxy="$PROXY_URL"
        export all_proxy="$PROXY_URL"

        # Установка глобально или с sudo если есть права
        if [ "$(id -u)" -eq 0 ]; then
            npm install -g @openai/codex --proxy "$PROXY_URL" --https-proxy "$PROXY_URL" || true
        else
            mkdir -p "$USER_HOME/.npm-global"
            npm config set prefix "$USER_HOME/.npm-global"
            npm install -g @openai/codex --proxy "$PROXY_URL" --https-proxy "$PROXY_URL" || true
        fi

        # Создание жесткого wrapper'а для codex CLI
        mkdir -p "$USER_HOME/.local/bin"
        cat << 'WRAPPER_EOF' > "$USER_HOME/.local/bin/codex"
#!/bin/bash
# Hardened wrapper for Codex CLI
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
PROXY_URL="http://127.0.0.1:$PROXY_PORT"

export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"

# Поиск реального бинарника
if [ -x "$HOME/.npm-global/bin/codex" ]; then
    exec "$HOME/.npm-global/bin/codex" "$@"
elif command -v npx >/dev/null 2>&1; then
    exec npx --yes @openai/codex "$@"
else
    exec codex "$@"
fi
WRAPPER_EOF
        chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.local/bin/codex" 2>/dev/null || true
        chmod +x "$USER_HOME/.local/bin/codex"

        # Если root, копируем также в /usr/local/bin
        if [ "$(id -u)" -eq 0 ]; then
            cp "$USER_HOME/.local/bin/codex" /usr/local/bin/codex 2>/dev/null || true
            chmod +x /usr/local/bin/codex 2>/dev/null || true
        fi
        echo "   Codex CLI wrapper успешно создан: $USER_HOME/.local/bin/codex"
    else
        echo "   [Предупреждение] npm не найден. Установите nodejs и запустите setup_codex.sh повторно."
    fi
}

case "$MODE" in
    vscode)
        setup_vscode
        ;;
    cli)
        setup_cli
        ;;
    all|*)
        setup_vscode
        setup_cli
        ;;
esac

# Настройка симлинка статистики
if [ -x /usr/local/bin/codex-stats ]; then
    ln -sf /usr/local/bin/codex-stats "$USER_HOME/codex-stats" 2>/dev/null || true
fi

echo ""
echo "========================================================="
echo " Настройка OpenAI Codex / ChatGPT завершена!"
echo " Проверка статистики:"
echo "   codex-stats           - статистика только Codex / ChatGPT"
echo "   codex-stats -app all  - общая статистика по всем инструментам"
echo "========================================================="
