# Claude Code Proxy & Auto-Patcher (Linux & Windows)

Комплексное решение для стабильной и безопасной работы **Claude Code** (расширения для VS Code и автономной консольной утилиты Claude CLI) на серверах Linux и рабочих станциях Windows в условиях региональных блокировок (РФ и др.).

> 🪟 **Для пользователей Windows 10 / 11**: Готовый комплект инструментов (C# микро-враппер, автопатчер, прокси-мост и статистика) находится в каталоге [`windows/`](windows/README.md).

---

## 🎯 Ключевые возможности

1. **Индивидуальный изолированный прокси для каждого пользователя (Multi-Tenant)**:
   - Каждый пользователь системы получает **собственный изолированный локальный порт моста** (`19000 + UID - 1000`) и службу `gost-claude@<username>`.
   - Конфигурация прокси каждого пользователя хранится в `~/.config/claude-proxy/proxy.env` с правами доступа `600` (каталог `700`). Другие пользователи сервера **не имеют прав** просматривать чужие пароли или изменять настройки.
   - Сбой или смена прокси у одного пользователя никак не влияет на остальных.

2. **Защита от утечки реального IP (Default-to-Proxy)**:
   - Все запросы Claude, авторизация, проверки гео, телеметрия (Datadog, Growthbook, Statsig) и любые неизвестные или новые сервисы Anthropic **по умолчанию на 100% идут через SOCKS5-прокси**.
   - Реальный IP сервера никогда не будет обнаружен чекерами геопозиции.

3. **Белый список тяжелых хабов (Destination Bypass — `bypass.conf`)**:
   - Только проверенные тяжелые хабы разработки направляются напрямую в обход SOCKS5:
     - `github.com`, `*.github.com`, `gitlab.com`, `*.gitlab.com`
     - `registry.npmjs.org`, `*.npmjs.org`, `pypi.org`, `*.pythonhosted.org`, `crates.io`
     - `docker.io`, `*.docker.io`, `archive.ubuntu.com`, `deb.debian.org`
     - Локальные сети (`127.0.0.1`, `10.0.0.0/8`, `192.168.0.0/16`) и российские домены (`*.ru`, `*.рф`).
   - Настраивается глобально в `/etc/claude-proxy/bypass.conf` и персонально в `~/.config/claude-proxy/bypass.conf`.

4. **Белый список дочерних процессов (`direct_processes.conf`)**:
   - Пакетные менеджеры и сборщики (`git`, `npm`, `npx`, `yarn`, `pnpm`, `docker`, `pip`, `pip3`, `cargo`, `go`) запускаются **напрямую** без переменных прокси, не нагружая канал SOCKS5 гигабайтами зависимостей.
   - Утилиты общего назначения (`curl`, `wget`, пользовательские скрипты) **сохраняют прокси**, гарантируя успешное прохождение сетевых вызовов.

5. **Полный аудит трафика и статистика (`claude-stats`)**:
   - Система точно определяет имя и PID процесса (`claude`, `git`, `curl` и др.), целевой домен, статус-код, маршрут (`SOCKS5` vs `DIRECT`) и объем переданных данных (вплоть до байта).
   - Удобная консольная утилита `claude-stats` отображает сводные таблицы, лог соединений и рекомендации по оптимизации списков.

6. **Безопасность при падении прокси (Fail-Closed) и удаленный DNS**:
   - Отсутствует тихий откат к прямому соединению. При недоступности прокси возвращается ошибка `502 Bad Gateway` без утечки IP.
   - DNS-запросы передаются на внешний прокси по именам хостов (`socks5h`, `ATYP=0x03`).

7. **Автоматический патчинг при обновлениях (Self-Healing)**:
   - Демон `claude-autopatch@<username>` в фоновом режиме отслеживает появление новых версий расширения VS Code и CLI, автоматически накладывая прокси-обертку.

---

## 🏗 Мультитенантная архитектура

```mermaid
flowchart TD
    subgraph External ["Внешняя сеть"]
        AnthropicAPI["Anthropic API / Claude.ai / Geo-Checkers"]
        HeavyHubs["GitHub / NPM / PyPI / Docker / OS"]
        SOCKS5_User1["SOCKS5 Прокси Пользователя 1"]
        SOCKS5_User2["SOCKS5 Прокси Пользователя 2"]
    end

    subgraph Server ["Linux Сервер"]
        subgraph User1 ["Пользователь: wizard (UID 1000)"]
            Conf1["~/.config/claude-proxy/proxy.env (600)<br>bypass.conf / direct_processes.conf"]
            Claude1["Claude (VS Code / CLI)"]
            Proxy1["gost-claude@wizard.service<br>127.0.0.1:19000"]
            Shims1["Direct Shims: git, npm, docker"]
        end

        subgraph User2 ["Пользователь: developer (UID 1001)"]
            Conf2["~/.config/claude-proxy/proxy.env (600)<br>bypass.conf / direct_processes.conf"]
            Claude2["Claude (VS Code / CLI)"]
            Proxy2["gost-claude@developer.service<br>127.0.0.1:19001"]
            Shims2["Direct Shims: git, npm, docker"]
        end
    end

    Claude1 -->|"Все запросы по умолчанию"| Proxy1
    Proxy1 -->|"Anthropic, Geo, Telemetry"| SOCKS5_User1
    SOCKS5_User1 --> AnthropicAPI
    Proxy1 -.->|"bypass.conf: тяжелые хабы"| HeavyHubs
    Claude1 -->|"Shims: npm, git, docker"| HeavyHubs

    Claude2 -->|"Все запросы по умолчанию"| Proxy2
    Proxy2 -->|"Anthropic, Geo, Telemetry"| SOCKS5_User2
    SOCKS5_User2 --> AnthropicAPI
    Proxy2 -.->|"bypass.conf: тяжелые хабы"| HeavyHubs
    Claude2 -->|"Shims: npm, git, docker"| HeavyHubs
```

---

## 📁 Структура репозитория

В репозитории находятся только 3 целевых скрипта (всю внутреннюю инфраструктуру установщик создает в системе сам):

| Файл | Назначение |
| :--- | :--- |
| **`install_claude_proxy.sh`** | **1. Главный инсталлер (Linux)**. Разворачивает прокси-ядро с аудитом, шаблоны `systemd`, глобальный лаунчер, утилиты статистики и автопатчер «под ключ». |
| **`setup_claude_user.sh`** | **2. Подключение пользователей (Linux)**. Настраивает персональный порт, изолированные конфиги (`600/700`), шимы прямых процессов и службы для пользователя. |
| **`install_claude_cli.sh`** | **3. Установка Claude CLI (Linux)**. Скачивает и устанавливает официальный автономный CLI через персональный прокси. |
| **`setup_codex.sh`** | **4. Настройка OpenAI Codex / ChatGPT**. Настраивает VS Code Remote-SSH с плагином `openai.chatgpt` и/или Codex CLI (`@openai/codex`). |
| **`setup_antigravity.sh`** | **5. Настройка Google Antigravity**. Настраивает Antigravity IDE Remote-SSH и/или Antigravity CLI (`agy`). |
| **[`windows/`](windows/README.md)** | **6. Комплект для Windows 10/11**. Полный набор инструментов (C# микро-враппер, PowerShell инсталлер, автопатчер, мост на Node.js/Python, статистика). |

---

## 🚀 Быстрый старт (Установка на новом сервере)

### 1. Клонирование репозитория

```bash
git clone https://github.com/seowizardandrey/claudefix.git
cd claudefix
chmod +x *.sh
```

### 2. Запуск основного инсталлера

Вы можете передать адрес прокси в качестве аргумента:

```bash
./install_claude_proxy.sh "socks5://USER:PASSWORD@HOST:PORT"
```

Либо запустить скрипт без параметров — он запустит интерактивный диалог и запросит адрес прокси:

```bash
./install_claude_proxy.sh
```

#### Что произойдет автоматически:
- Установятся системные пакеты (`inotify-tools`, `wget`, `curl`, `python3`);
- Установится ядро прокси с аудитом в `/usr/local/bin/claude_proxy_bridge.py`;
- Установятся утилиты статистики: `claude-stats`, `codex-stats`, `antigravity-stats`;
- Установятся скрипты настройки: `setup_codex.sh`, `setup_antigravity.sh`, `setup_claude_user.sh`, `install_claude_cli.sh`;
- Создадутся шаблоны служб `gost-claude@.service` и `claude-autopatch@.service`;
- Текущему пользователю выделится изолированный порт (`19000`), создадутся списки `bypass.conf` и `direct_processes.conf`, запустится персональный мост и автопатчер;
- Пропатчатся текущие расширения Claude Code в VS Code.

---

## 👥 Добавление других пользователей и персональные прокси

Каждый пользователь может иметь свой собственный SOCKS5-прокси.

### Добавление пользователя администратором:

```bash
sudo setup_claude_user.sh ИМЯ_ПОЛЬЗОВАТЕЛЯ "socks5://USER:PASS@HOST:PORT"
```

### Настройка/смена прокси пользователем для себя:

Если у пользователя есть права sudo, он может просто запустить в своем терминале:

```bash
setup_claude_user.sh "socks5://НОВЫЙ_ЛОГИН:НОВЫЙ_ПАРОЛЬ@ХОСТ:ПОРТ"
```

#### Безопасность и изоляция:
- Файл конфигурации создается в `~/.config/claude-proxy/proxy.env` с правами `600`.
- Никакой другой пользователь сервера не сможет подсмотреть чужие пароли прокси или перезаписать их.
- Порты пользователей рассчитываются как `19000 + (UID - 1000)` и никогда не пересекаются.

---

## 🧠 Настройка OpenAI Codex / ChatGPT (`setup_codex.sh`)

Скрипт настраивает доступ к сервисам OpenAI (`chatgpt.com`, `api.openai.com`) через персональный мост в двух вариантах:

```bash
setup_codex.sh
```

Вы можете передать режим напрямую:
* `setup_codex.sh vscode` — **Вариант 1 (VS Code Remote-SSH + плагин)**:
  * Прописывает в `~/.vscode-server/data/Machine/settings.json` параметры переопределения прокси (`http.proxy`, `http.proxySupport: override`).
  * Устанавливает официальный плагин [openai.chatgpt](https://marketplace.visualstudio.com/items?itemName=openai.chatgpt) на серверной стороне.
  * Фиксирует прокси-переменные в окружении сервера `~/.vscode-server/server-env.sh`.
* `setup_codex.sh cli` — **Вариант 2 (Codex CLI)**:
  * Устанавливает пакет `@openai/codex` через персональный прокси: `npm i -g @openai/codex`.
  * Создает жесткий системный wrapper `codex`, принудительно направляющий весь трафик в локальный шлюз.
* `setup_codex.sh all` — выполняет настройку обоих вариантов.

---

## 🛸 Настройка Google Antigravity (`setup_antigravity.sh`)

Скрипт настраивает доступ к экосистеме Google Antigravity (`antigravity.google`, Gemini API, `generativelanguage.googleapis.com`):

```bash
setup_antigravity.sh
```

Вы можете передать режим напрямую:
* `setup_antigravity.sh ide` — **Вариант 1 (Antigravity IDE Remote-SSH)**:
  * Настраивает серверные конфигурации `~/.antigravity-server/data/Machine/settings.json` и профиль IDE.
  * Задает принудительное переопределение сетевого стека через персональный мост.
* `setup_antigravity.sh cli` — **Вариант 2 (Antigravity CLI — `agy`)**:
  * Скачивает и устанавливает официальный CLI строго через прокси: `curl -fsSL https://antigravity.google/cli/install.sh | bash`.
  * Создает wrapper `agy` с обязательной поддержкой `GRPC_PROXY` (критично для Gemini / Google Cloud AI endpoints).
* `setup_antigravity.sh all` — выполняет настройку обоих вариантов.

---

## 📊 Изолированная статистика и аудит трафика

Каждый инструмент имеет собственную специализированную команду статистики, отображающую **только свои** запросы и объемы данных. С флагом `-app all` (или `--app all`) любая утилита выводит **полную сводную статистику** по всем инструментам сервера:

| Команда | Режим по умолчанию | Режим с флагом `-app all` |
| :--- | :--- | :--- |
| **`claude-stats`** | Трафик **Claude Code** (`anthropic.com`, `claude.ai`, Datadog) | Полная статистика по всем AI и процессам |
| **`codex-stats`** | Трафик **OpenAI Codex / ChatGPT** (`chatgpt.com`, `openai.com`) | Полная статистика по всем AI и процессам |
| **`antigravity-stats`** | Трафик **Google Antigravity** (`antigravity.google`, Google AI) | Полная статистика по всем AI и процессам |

### Примеры использования:

```bash
# Статистика только по Claude Code:
claude-stats

# Статистика только по Codex / ChatGPT:
codex-stats

# Статистика только по Google Antigravity:
antigravity-stats

# Полная сводная статистика по всем инструментам и процессам:
claude-stats -app all
# (или codex-stats -app all / antigravity-stats -app all)

# Просмотр статистики другого пользователя (для root):
sudo claude-stats developer -app all
```

### Что вы увидите в отчете:
1. **Сводка по AI-инструментам**: агрегированный трафик по Claude Code, OpenAI Codex/ChatGPT, Google Antigravity и сборщикам.
2. **Детализация по процессам (Apps)**: какие процессы подключались (`claude`, `codex`, `agy`, `git`), сколько запросов сделали через SOCKS5 и напрямую, объем данных (в МБ/ГБ).
3. **Топ целевых доменов**: список всех внешних ресурсов, маршрут (`SOCKS5` / `DIRECT`), коды ответов (`200`, `502`) и суммарный трафик.
4. **Лог последних соединений**: точное время, кто и куда обращался, код ответа, размер данных и время отклика.
5. **Умные рекомендации**: подсветка доменов, потребляющих много трафика через SOCKS5, с предложением добавить их в `bypass.conf`.

---

## ⚙️ Тонкая настройка белых списков

Конфигурационные файлы каждого пользователя находятся в `~/.config/claude-proxy/`:

### 1. Добавление доменов в прямой доступ (`bypass.conf`):
Если вам нужно пустить трафик к внутренней подсети или CDN напрямую:
```bash
nano ~/.config/claude-proxy/bypass.conf
```
Добавьте домен или подсеть (например, `192.168.1.0/24` или `*.mycompany.internal`). Изменения подхватываются автоматически без перезапуска службы.

### 2. Изменение списка прямых процессов (`direct_processes.conf`):
Если вы хотите, чтобы определенная утилита запускалась Claude напрямую без прокси:
```bash
nano ~/.config/claude-proxy/direct_processes.conf
```
После изменения обновите шимы: `setup_claude_user.sh`.

---

## 💻 Установка и использование автономного Claude CLI

Если вам нужен консольный `claude` в терминале (независимо от VS Code):

```bash
install_claude_cli.sh
```

Скрипт автоматически скачает официальный инсталлер Anthropic через локальный мост, установит бинарник в `~/.local/share/claude/versions/` и применит к нему патчер.

Запуск Claude из любого каталога:

```bash
# Проверка версии
claude --version

# Проверка связи с API
claude -p "ping"

# Интерактивная сессия
claude
```

> **Автообновление**: Встроенная команда `claude update` полностью поддерживается. Фоновый демон `claude-autopatch` автоматически перехватывает новые версии CLI и накладывает прокси-патч.

---

## 🛠 Управление службами и диагностика

```bash
# Статус персонального прокси-моста пользователя
systemctl status gost-claude@$USER

# Статус автопатчера пользователя
systemctl status claude-autopatch@$USER

# Логи в реальном времени
journalctl -u gost-claude@$USER -f
journalctl -u claude-autopatch@$USER -f
```

---

## 📄 Лицензия

MIT License.
