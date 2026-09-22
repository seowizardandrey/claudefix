#!/bin/bash
# setup_claude_user.sh - Подключение и настройка персонального Claude Code Proxy для пользователя
# Использование:
#   sudo setup_claude_user.sh ИМЯ_ПОЛЬЗОВАТЕЛЯ [SOCKS5_URL]
# Или от своего имени (если у пользователя есть sudo):
#   setup_claude_user.sh [SOCKS5_URL]
# Или просмотр статистики:
#   setup_claude_user.sh --stats [ИМЯ_ПОЛЬЗОВАТЕЛЯ]

set -e

# Установка локали UTF-8 для вывода
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"

# Обработка вызова статистики
if [ "${1:-}" = "--stats" ] || [ "${1:-}" = "-s" ]; then
    shift
    if [ -x /usr/local/bin/claude-stats ]; then
        exec /usr/local/bin/claude-stats "$@"
    else
        echo "Утилита claude-stats не найдена. Выполните установку через install_claude_proxy.sh"
        exit 1
    fi
fi

# 1. Разбор аргументов
ARG1="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"

# Проверяем, передан ли в первом аргументе SOCKS5 прокси (значит запуск для себя)
if [[ "$ARG1" == socks5://* || "$ARG1" == socks5h://* ]]; then
    TARGET_USER="${SUDO_USER:-$USER}"
    SOCKS5_URL="$ARG1"
    PROXY_MODE="${ARG2:-anthropic_only}"
else
    # Первый аргумент - имя пользователя (или текущий, если пуст)
    TARGET_USER="${ARG1:-${SUDO_USER:-$USER}}"
    SOCKS5_URL="$ARG2"
    PROXY_MODE="${ARG3:-anthropic_only}"
fi

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Ошибка: Укажите имя обычного (не root) пользователя для настройки."
    echo "Пример: sudo setup_claude_user.sh developer 'socks5://login:pass@host:port'"
    exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Ошибка: Пользователь '$TARGET_USER' не найден в системе."
    exit 1
fi

USER_UID=$(id -u "$TARGET_USER")
USER_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "Ошибка: Домашняя директория '$USER_HOME' для пользователя '$TARGET_USER' не найдена."
    exit 1
fi

# Вычисление уникального локального порта для пользователя (19000 + смещение по UID)
# UID 1000 -> 19000, UID 1001 -> 19001, etc.
if [ "$USER_UID" -ge 1000 ]; then
    PROXY_PORT=$(( 19000 + (USER_UID - 1000) ))
else
    PROXY_PORT=$(( 19000 + USER_UID ))
fi

CONFIG_DIR="$USER_HOME/.config/claude-proxy"
CONFIG_FILE="$CONFIG_DIR/proxy.env"
BYPASS_FILE="$CONFIG_DIR/bypass.conf"
DIRECT_PROC_FILE="$CONFIG_DIR/direct_processes.conf"
SHIMS_DIR="$CONFIG_DIR/shims"

# Если прокси не передан, проверяем существующую конфигурацию или дефолт
if [ -z "$SOCKS5_URL" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        # Читаем уже имеющийся прокси
        SOCKS5_URL=$(grep "^SOCKS5_URL=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    fi

    # Проверяем общесистемный дефолт (если задан администратором)
    if [ -z "$SOCKS5_URL" ] && [ -f /etc/claude-proxy/default.env ]; then
        SOCKS5_URL=$(grep "^SOCKS5_URL=" /etc/claude-proxy/default.env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    fi

    # Если всё еще нет прокси — запрашиваем у пользователя
    if [ -z "$SOCKS5_URL" ]; then
        echo "========================================================="
        echo " Настройка персонального прокси для пользователя: $TARGET_USER"
        echo "========================================================="
        echo "Укажите адрес вашего SOCKS5-прокси."
        echo "Формат: socks5://USER:PASSWORD@HOST:PORT"
        echo ""
        read -r -p "Введите адрес SOCKS5: " SOCKS5_URL || true
    fi
fi

if [ -z "$SOCKS5_URL" ]; then
    echo "Ошибка: Адрес SOCKS5-прокси не указан."
    echo "Использование: sudo setup_claude_user.sh $TARGET_USER 'socks5://USER:PASS@HOST:PORT'"
    exit 1
fi

if [[ "$SOCKS5_URL" != socks5://* && "$SOCKS5_URL" != socks5h://* ]]; then
    echo "Предупреждение: Добавлена схема socks5:// к указанному адресу."
    SOCKS5_URL="socks5://${SOCKS5_URL}"
fi

echo "========================================================="
echo " Настройка Claude Code Proxy для: $TARGET_USER"
echo " Домашняя папка : $USER_HOME"
echo " Локальный порт : 127.0.0.1:$PROXY_PORT"
echo " Персональный прокси: $SOCKS5_URL"
echo "========================================================="

# 1. Проверка наличия системных компонентов
if [ ! -f /usr/local/bin/claude_proxy_bridge.py ] || [ ! -f /usr/local/bin/autopatch_claude.sh ]; then
    echo "Ошибка: Системные компоненты не найдены. Сначала запустите install_claude_proxy.sh"
    exit 1
fi

# 2. Создание изолированного каталога конфигурации с правами только для пользователя (700 / 600)
echo "=> [1/6] Сохранение изолированной конфигурации прокси..."
mkdir -p "$USER_HOME/.config"
chown "$TARGET_USER:$USER_GROUP" "$USER_HOME/.config" 2>/dev/null || true
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

cat << INNER_CONF_EOF > "$CONFIG_FILE"
PROXY_PORT=$PROXY_PORT
SOCKS5_URL="$SOCKS5_URL"
PROXY_MODE="$PROXY_MODE"
INNER_CONF_EOF
chmod 600 "$CONFIG_FILE"

# 3. Настройка белого списка тяжелых хабов (bypass.conf)
echo "=> [2/6] Настройка белого списка доменов для прямого трафика (bypass.conf)..."
if [ ! -f "$BYPASS_FILE" ]; then
    if [ -f /etc/claude-proxy/bypass.conf ]; then
        cp /etc/claude-proxy/bypass.conf "$BYPASS_FILE"
    else
        cat << 'INNER_BYPASS_EOF' > "$BYPASS_FILE"
# Claude Code Proxy - Destination Bypass List
# Все домены не из этого списка по умолчанию идут через SOCKS5 прокси!
# В этот список включены только проверенные тяжелые хабы разработки и локальная сеть.

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
INNER_BYPASS_EOF
    fi
fi
chmod 644 "$BYPASS_FILE"

# 4. Настройка белого списка прямых процессов (direct_processes.conf) и шимов
echo "=> [3/6] Настройка белого списка дочерних процессов (direct_processes.conf)..."
if [ ! -f "$DIRECT_PROC_FILE" ]; then
    if [ -f /etc/claude-proxy/direct_processes.conf ]; then
        cp /etc/claude-proxy/direct_processes.conf "$DIRECT_PROC_FILE"
    else
        cat << 'INNER_PROC_EOF' > "$DIRECT_PROC_FILE"
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
INNER_PROC_EOF
    fi
fi
chmod 644 "$DIRECT_PROC_FILE"

# Создание каталога шимов и скрипта окружения дочерних процессов
mkdir -p "$SHIMS_DIR"
rm -f "$SHIMS_DIR"/*

# Создание шимов для каждого прямого процесса
while IFS= read -r proc || [ -n "$proc" ]; do
    proc=$(echo "$proc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$proc" || "$proc" == \#* ]] && continue

    shim_path="$SHIMS_DIR/$proc"
    cat << 'INNER_SHIM_EOF' > "$shim_path"
#!/bin/bash
# Direct execution shim - strips proxy variables
BIN_NAME="$(basename "$0")"
REAL_BIN=$(PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin" type -P "$BIN_NAME" 2>/dev/null || true)
if [ -z "$REAL_BIN" ]; then
    REAL_BIN="/usr/bin/$BIN_NAME"
fi
exec env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
         -u npm_config_proxy -u npm_config_https_proxy \
         "$REAL_BIN" "$@"
INNER_SHIM_EOF
    chmod +x "$shim_path"
done < "$DIRECT_PROC_FILE"

# Генерация child_env.sh (загружается через BASH_ENV в дочерних bash-сессиях Claude)
CHILD_ENV="$CONFIG_DIR/child_env.sh"
cat << 'INNER_CHILD_EOF' > "$CHILD_ENV"
# Claude Child Shell Environment Initializer
# Injects shims for direct processes and keeps proxy for curl/unknown commands
SHIMS_DIR="$HOME/.config/claude-proxy/shims"
if [ -d "$SHIMS_DIR" ]; then
    case ":$PATH:" in
        *":$SHIMS_DIR:"*) ;;
        *) export PATH="$SHIMS_DIR:$PATH" ;;
    esac
fi

# Function wrappers for direct tools (for non-interactive subshells)
DIRECT_CONF="$HOME/.config/claude-proxy/direct_processes.conf"
if [ -f "$DIRECT_CONF" ]; then
    while IFS= read -r tool || [ -n "$tool" ]; do
        tool=$(echo "$tool" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -z "$tool" || "$tool" == \#* ]] && continue
        eval "
        $tool() {
            (
                unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy \
                      npm_config_proxy npm_config_https_proxy
                command $tool \"\$@\"
            )
        }
        "
    done < "$DIRECT_CONF"
fi
INNER_CHILD_EOF
chmod 755 "$CHILD_ENV"

# Установка корректного владельца на весь конфиг
chown -R "$TARGET_USER:$USER_GROUP" "$CONFIG_DIR"
chown "$TARGET_USER:$USER_GROUP" "$USER_HOME/.config" 2>/dev/null || true

# 5. Запуск индивидуальной службы прокси-моста gost-claude@<TARGET_USER>
echo "=> [4/6] Запуск персонального моста gost-claude@$TARGET_USER на порту $PROXY_PORT..."
if [ "$(id -u)" -eq 0 ]; then
    systemctl daemon-reload
    systemctl enable "gost-claude@$TARGET_USER"
    systemctl restart "gost-claude@$TARGET_USER"
    systemctl enable "claude-autopatch@$TARGET_USER"
    systemctl restart "claude-autopatch@$TARGET_USER"
else
    sudo systemctl daemon-reload
    sudo systemctl enable "gost-claude@$TARGET_USER"
    sudo systemctl restart "gost-claude@$TARGET_USER"
    sudo systemctl enable "claude-autopatch@$TARGET_USER"
    sudo systemctl restart "claude-autopatch@$TARGET_USER"
fi

# 6. Создание ссылок и проверка ~/.bashrc
echo "=> [5/6] Настройка ссылок в домашней директории..."
sudo -u "$TARGET_USER" ln -sf /usr/local/bin/setup_claude_user.sh "$USER_HOME/setup_claude_user.sh" 2>/dev/null || \
    ln -sf /usr/local/bin/setup_claude_user.sh "$USER_HOME/setup_claude_user.sh" 2>/dev/null || true

sudo -u "$TARGET_USER" ln -sf /usr/local/bin/claude-stats "$USER_HOME/claude-stats" 2>/dev/null || \
    ln -sf /usr/local/bin/claude-stats "$USER_HOME/claude-stats" 2>/dev/null || true

sudo -u "$TARGET_USER" ln -sf /usr/local/bin/codex-stats "$USER_HOME/codex-stats" 2>/dev/null || \
    ln -sf /usr/local/bin/codex-stats "$USER_HOME/codex-stats" 2>/dev/null || true

sudo -u "$TARGET_USER" ln -sf /usr/local/bin/antigravity-stats "$USER_HOME/antigravity-stats" 2>/dev/null || \
    ln -sf /usr/local/bin/antigravity-stats "$USER_HOME/antigravity-stats" 2>/dev/null || true

sudo -u "$TARGET_USER" ln -sf /usr/local/bin/install_claude_cli.sh "$USER_HOME/install_claude_cli.sh" 2>/dev/null || \
    ln -sf /usr/local/bin/install_claude_cli.sh "$USER_HOME/install_claude_cli.sh" 2>/dev/null || true

if [ -f /usr/local/bin/setup_codex.sh ]; then
    sudo -u "$TARGET_USER" ln -sf /usr/local/bin/setup_codex.sh "$USER_HOME/setup_codex.sh" 2>/dev/null || \
        ln -sf /usr/local/bin/setup_codex.sh "$USER_HOME/setup_codex.sh" 2>/dev/null || true
fi

if [ -f /usr/local/bin/setup_antigravity.sh ]; then
    sudo -u "$TARGET_USER" ln -sf /usr/local/bin/setup_antigravity.sh "$USER_HOME/setup_antigravity.sh" 2>/dev/null || \
        ln -sf /usr/local/bin/setup_antigravity.sh "$USER_HOME/setup_antigravity.sh" 2>/dev/null || true
fi

BASHRC="$USER_HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    if ! grep -q "autopatch_claude.sh" "$BASHRC"; then
        echo -e "\n# Claude Code Proxy auto-patch fallback\n/usr/local/bin/autopatch_claude.sh >/dev/null 2>&1 || true" >> "$BASHRC"
        chown "$TARGET_USER:$USER_GROUP" "$BASHRC" 2>/dev/null || true
    fi
fi

# 7. Начальный патчинг установленных расширений и CLI
echo "=> [6/6] Применение автопатчинга для $TARGET_USER..."
sudo -u "$TARGET_USER" HOME="$USER_HOME" /usr/local/bin/autopatch_claude.sh --verbose || true

# 8. Проверка доступности персонального моста
echo "=> Проверка работоспособности персонального моста на 127.0.0.1:$PROXY_PORT..."
sleep 1
if curl -s -o /dev/null -x "http://127.0.0.1:$PROXY_PORT" https://api.anthropic.com 2>/dev/null; then
    echo "✔ Персональный мост успешно отвечает!"
else
    echo "⚠ Предупреждение: Внешний SOCKS5 прокси пока не ответил. Проверьте адрес и журнал: journalctl -u gost-claude@$TARGET_USER"
fi

echo "========================================================="
echo " Настройка для пользователя $TARGET_USER успешно завершена!"
echo "   - Персональный мост   : 127.0.0.1:$PROXY_PORT (gost-claude@$TARGET_USER)"
echo "   - Служба автопатча    : claude-autopatch@$TARGET_USER"
echo "   - Изолированный конфиг: $CONFIG_FILE (права 600)"
echo "   - Белый список доменов: $BYPASS_FILE (напрямую в обход SOCKS5)"
echo "   - Прямые процессы     : $DIRECT_PROC_FILE (git, npm, docker...)"
echo "   - Просмотр статистики : claude-stats | codex-stats | antigravity-stats (-app all)"
echo "   - Доп. AI-инструменты : setup_codex.sh | setup_antigravity.sh"
echo "========================================================="
