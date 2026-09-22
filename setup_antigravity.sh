#!/bin/bash
# setup_antigravity.sh - Настройка Google Antigravity для пользователя через персональный прокси-мост
# Варианты:
#   1) Antigravity IDE Remote-SSH
#   2) Antigravity CLI (curl -fsSL https://antigravity.google/cli/install.sh | bash)
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
echo " Настройка Google Antigravity через персональный прокси"
echo " Пользователь: $TARGET_USER"
echo " Прокси-мост : $PROXY_URL"
echo "========================================================="

# Проверка активности службы прокси
if ! curl -s -o /dev/null -x "$PROXY_URL" https://antigravity.google/ 2>/dev/null; then
    echo "Предупреждение: Персональный мост $PROXY_URL не отвечает на запросы к antigravity.google."
    echo "Убедитесь, что служба запущена: sudo systemctl status gost-claude@$TARGET_USER"
fi

# Выбор режима работы
MODE="$1"
if [ -z "$MODE" ]; then
    echo ""
    echo "Выберите вариант настройки:"
    echo "  1) Antigravity IDE Remote-SSH"
    echo "  2) Antigravity CLI (скачивание и установка agy через прокси)"
    echo "  3) Установить и настроить оба варианта (all)"
    read -rp "Ваш выбор [1-3] (по умолчанию: 3): " CHOICE
    case "$CHOICE" in
        1) MODE="ide" ;;
        2) MODE="cli" ;;
        *) MODE="all" ;;
    esac
fi

# Вспомогательная функция для обновления JSON-конфигов
update_json_config() {
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

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
    chown "$TARGET_USER":"$TARGET_USER" "$json_file" 2>/dev/null || true
    chmod 644 "$json_file" 2>/dev/null || true
}

# --- ВАРИАНТ 1: Antigravity IDE Remote-SSH ---
setup_ide() {
    echo ""
    echo "=> [1/2] Настройка окружения Antigravity IDE Remote-SSH на сервере..."

    # Конфигурационные файлы Antigravity IDE Server
    local machine_settings="$USER_HOME/.antigravity-server/data/Machine/settings.json"
    local user_ide_settings="$USER_HOME/.config/Antigravity/User/settings.json"
    local gemini_ide_settings="$USER_HOME/.gemini/antigravity-ide/settings.json"

    update_json_config "$machine_settings"
    update_json_config "$user_ide_settings"
    update_json_config "$gemini_ide_settings"
    echo "   Конфигурационные файлы Antigravity IDE обновлены (proxy: $PROXY_URL)"

    # Окружение Remote-SSH сервера (server-env.sh)
    mkdir -p "$USER_HOME/.antigravity-server"
    cat << ENVEOF > "$USER_HOME/.antigravity-server/server-env.sh"
# Antigravity IDE Remote-SSH environment for $TARGET_USER
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export GRPC_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"
ENVEOF
    chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.antigravity-server/server-env.sh" 2>/dev/null || true
    chmod 644 "$USER_HOME/.antigravity-server/server-env.sh" 2>/dev/null || true
    echo "   Окружение Remote-SSH сервера настроено."
}

# --- ВАРИАНТ 2: Antigravity CLI (agy) ---
setup_cli() {
    echo ""
    echo "=> [2/2] Установка Antigravity CLI (agy) через персональный прокси..."

    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export ALL_PROXY="$PROXY_URL"
    export GRPC_PROXY="$PROXY_URL"
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export all_proxy="$PROXY_URL"

    echo "   Скачивание официального инсталлера Antigravity CLI..."
    # Запуск официального скрипта установки под целевым пользователем через прокси
    su - "$TARGET_USER" -c "export HTTP_PROXY='$PROXY_URL'; export HTTPS_PROXY='$PROXY_URL'; export ALL_PROXY='$PROXY_URL'; export GRPC_PROXY='$PROXY_URL'; export http_proxy='$PROXY_URL'; export https_proxy='$PROXY_URL'; export all_proxy='$PROXY_URL'; curl -fsSL https://antigravity.google/cli/install.sh | bash" 2>/dev/null || \
        (curl -fsSL -x "$PROXY_URL" https://antigravity.google/cli/install.sh 2>/dev/null | bash) || true

    # Создание жесткого wrapper'а для agy
    mkdir -p "$USER_HOME/.local/bin"
    cat << 'WRAPPER_EOF' > "$USER_HOME/.local/bin/agy"
#!/bin/bash
# Hardened wrapper for Antigravity CLI (agy)
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
export GRPC_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"

# Поиск реального бинарника agy
if [ -x "$HOME/.antigravity/bin/agy" ]; then
    exec "$HOME/.antigravity/bin/agy" "$@"
elif [ -x "$HOME/.local/share/antigravity/agy" ]; then
    exec "$HOME/.local/share/antigravity/agy" "$@"
elif [ -x "/opt/antigravity/bin/agy" ]; then
    exec "/opt/antigravity/bin/agy" "$@"
else
    # Фоллбэк
    echo "[agy wrapper] Окружение прокси настроено ($PROXY_URL)."
    if command -v agy >/dev/null 2>&1 && [ "$(command -v agy)" != "$0" ]; then
        exec agy "$@"
    else
        echo "Бинарник agy не найден в ~/.antigravity/bin. Убедитесь в успешности выполнения инсталлера."
        exit 1
    fi
fi
WRAPPER_EOF
    chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.local/bin/agy" 2>/dev/null || true
    chmod +x "$USER_HOME/.local/bin/agy"

    if [ "$(id -u)" -eq 0 ]; then
        cp "$USER_HOME/.local/bin/agy" /usr/local/bin/agy 2>/dev/null || true
        chmod +x /usr/local/bin/agy 2>/dev/null || true
    fi
    echo "   Antigravity CLI wrapper успешно создан: $USER_HOME/.local/bin/agy"
}

case "$MODE" in
    ide)
        setup_ide
        ;;
    cli)
        setup_cli
        ;;
    all|*)
        setup_ide
        setup_cli
        ;;
esac

# Настройка симлинка статистики
if [ -x /usr/local/bin/antigravity-stats ]; then
    ln -sf /usr/local/bin/antigravity-stats "$USER_HOME/antigravity-stats" 2>/dev/null || true
fi

echo ""
echo "========================================================="
echo " Настройка Google Antigravity завершена!"
echo " Проверка статистики:"
echo "   antigravity-stats           - статистика только Google Antigravity"
echo "   antigravity-stats -app all  - общая статистика по всем инструментам"
echo "========================================================="
