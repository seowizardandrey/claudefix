#!/bin/bash
# install_claude_cli.sh - Установка официального Claude Code CLI через персональный прокси-мост
set -e

export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"

CONFIG_FILE="$HOME/.config/claude-proxy/proxy.env"
PROXY_PORT=""

# Определение локального порта пользователя
if [ -f "$CONFIG_FILE" ]; then
    PROXY_PORT=$(grep "^PROXY_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

# Если порт не определен из файла, вычисляем по UID
if [ -z "$PROXY_PORT" ]; then
    USER_UID=$(id -u)
    if [ "$USER_UID" -ge 1000 ]; then
        PROXY_PORT=$(( 19000 + (USER_UID - 1000) ))
    else
        PROXY_PORT=$(( 19000 + USER_UID ))
    fi
fi

PROXY_URL="http://127.0.0.1:$PROXY_PORT"

echo "========================================================="
echo " Установка официального Claude Code CLI через прокси"
echo " Пользователь: $USER"
echo " Прокси-мост : $PROXY_URL"
echo "========================================================="

# Проверка доступности прокси
if ! curl -s -o /dev/null -x "$PROXY_URL" https://claude.ai/ 2>/dev/null; then
    echo "Предупреждение: Персональный мост $PROXY_URL не отвечает."
    echo "Убедитесь, что служба gost-claude@$USER запущена: systemctl status gost-claude@$USER"
fi

echo "=> Скачивание и запуск официального инсталлера..."
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"

curl -fsSL https://claude.ai/install.sh | bash

echo "=> Применение патчера к новому CLI..."
/usr/local/bin/autopatch_claude.sh --verbose || true

echo ""
echo "========================================================="
echo " Установка Claude Code CLI успешно завершена!"
echo " Проверить версию:"
echo "   claude --version"
echo " Запустить Claude:"
echo "   claude"
echo "========================================================="