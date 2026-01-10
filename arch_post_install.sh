#!/bin/bash

# =============================================================================
# Arch Linux Post-Install Script (Perfect Edition)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEEDED_FILE="$SCRIPT_DIR/needed_app"
SUCCESS_LOG="$SCRIPT_DIR/installed_app.log"
ERROR_LOG="$SCRIPT_DIR/error_install.log"
SERVICE_LOG="$SCRIPT_DIR/service_needed.log"

DRY_RUN=false

# --- Справка ---
show_help() {
    echo "Использование: $0 [флаги]"
    echo ""
    echo "Доступные флаги:"
    echo "  -start        Запустить процесс проверки и установки"
    echo "  --dry-run     Режим имитации: отчет без внесения изменений"
    echo "  -h, --help    Показать эту справку"
}

# Обработка аргументов
if [[ $# -eq 0 ]]; then show_help; exit 0; fi

for arg in "$@"; do
    case $arg in
        -start)    START_EXEC=true ;;
        --dry-run) DRY_RUN=true; START_EXEC=true ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Ошибка: Неизвестный параметр '$arg'"; show_help; exit 1 ;;
    esac
done

if [[ ! -f "$NEEDED_FILE" ]]; then
    echo "Ошибка: Файл со списком пакетов не найден: $NEEDED_FILE"
    exit 1
fi

# --- Функции ---

# Очищенное получение версии: берем только цифры и символы версии до первого пробела
get_version() {
    pacman -Qi "$1" 2>/dev/null | grep -m 1 "^Version" | sed 's/.*: //; s/ .*//' || echo "N/A"
}

is_installed() {
    pacman -Qi "$1" &> /dev/null || paru -Qi "$1" &> /dev/null
}

# --- Начало работы ---

[[ "$DRY_RUN" = true ]] && echo "--- РЕЖИМ ИМИТАЦИИ ---"

echo "Продолжить выполнение? (y/n)"
read -r confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

# Инициализация логов с заголовками
echo "ОТЧЕТ ОБ УСТАНОВКЕ ОТ $(date)" > "$SUCCESS_LOG"
echo "----------------------------------------" >> "$SUCCESS_LOG"
> "$ERROR_LOG"
echo "РЕКОМЕНДАЦИИ ПО СЕРВИСАМ" > "$SERVICE_LOG"
echo "----------------------------------------" >> "$SERVICE_LOG"

# Основной цикл
while IFS= read -r line; do
    # Игнорируем комментарии и пустые строки
    [[ -z "$line" || "$line" =~ ^\[.*\]$ || "$line" =~ ^\s*# ]] && continue
    package=$(echo "$line" | sed 's/#.*//' | awk '{print $1}')
    [[ -z "$package" ]] && continue

    if is_installed "$package"; then
        ver=$(get_version "$package")
        echo "[OK] $package — Версия: $ver" >> "$SUCCESS_LOG"
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Пакет будет установлен: $package"
    else
        echo "Установка: $package..."
        if pacman -Ss "^${package}$" &> /dev/null; then
            sudo pacman -S --noconfirm --needed "$package" >> "$SUCCESS_LOG" 2>> "$ERROR_LOG"
        else
            paru -S --noconfirm --needed "$package" >> "$SUCCESS_LOG" 2>> "$ERROR_LOG"
        fi
    fi
done < "$NEEDED_FILE"

# Анализ сервисов
FOUND_SVC=false
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^\[.*\]$ || "$line" =~ ^\s*# ]] && continue
    pkg=$(echo "$line" | sed 's/#.*//' | awk '{print $1}')

    if is_installed "$pkg"; then
        # Ищем юниты только в системной директории, исключая пользовательские
        units=$(pacman -Ql "$pkg" 2>/dev/null | grep "/usr/lib/systemd/system/" | grep -E "\.(service|path|timer)$" | awk '{print $2}' | xargs -I{} basename {})
        for unit in $units; do
            # Проверяем, не включен ли уже этот юнит
            if ! systemctl is-enabled "$unit" &> /dev/null; then
                echo "Пакет: $pkg -> Команда: sudo systemctl enable --now $unit" >> "$SERVICE_LOG"
                FOUND_SVC=true
            fi
        done
    fi
done < "$NEEDED_FILE"

[[ "$FOUND_SVC" = false ]] && echo "Все необходимые сервисы уже активны." >> "$SERVICE_LOG"

echo "----------------------------------------"
echo "Завершено. Результаты записаны в директорию скрипта."
