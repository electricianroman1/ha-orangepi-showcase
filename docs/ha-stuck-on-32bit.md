# HA Supervised «застрял» на 2025.11 на 64-битной плате

## Симптом
Home Assistant на Orange Pi Zero 3 (aarch64, Ubuntu 22.04, установка Supervised) не обновляется выше **2025.11.3**, новых версий не предлагает.

## Причина
При установке Supervised указывают тип машины (`MACHINE`). Для платы выбрали `raspberrypi4`, а это **32-битный** вариант (образ `armv7`), хотя плата и дополнения 64-битные. С версии 2025.12 Home Assistant перестал выпускать 32-битные сборки.

| Тип машины | Последняя доступная версия HA |
|---|---|
| `raspberrypi4` | 2025.11.3 |
| `raspberrypi4-64` | 2026.9.4 (на момент записи) |

Проверить актуальные версии по типам:

```bash
curl -s https://version.home-assistant.io/stable.json | python3 -c "
import json,sys
ha=json.load(sys.stdin)['homeassistant']
for k in ('raspberrypi4','raspberrypi4-64','generic-aarch64'): print(k, ha.get(k))"
```

## Лечение
Переустанавливать систему не нужно, данные и настройки остаются.

1. Полный бэкап и копия на другой компьютер.
2. Сменить тип машины и перезапустить Supervisor:

   ```bash
   sudo cp /etc/hassio.json /etc/hassio.json.bak
   sudo sed -i 's/"machine": "raspberrypi4"/"machine": "raspberrypi4-64"/' /etc/hassio.json
   sudo systemctl restart hassio-supervisor
   ```

3. **Грабля.** Работающий контейнер Supervisor держит старое значение в окружении. В моём случае он удалил HA и заново скачал тот же 32-битный образ. Помогло пересоздание контейнера (служба поднимает его сама):

   ```bash
   docker rm -f hassio_supervisor
   docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' hassio_supervisor | grep MACHINE   # должно быть raspberrypi4-64
   ```

4. Supervisor скачивает 64-битный образ той же версии (около 1,8 ГБ) и запускает его. Проверка архитектуры образа:

   ```bash
   docker image inspect -f '{{.Architecture}}' $(docker inspect -f '{{.Image}}' homeassistant)   # arm64
   ```

5. Если используется HACS, заново пройти в нём авторизацию до обновления HA, иначе custom-интеграции нельзя обновить, а старые версии ломаются на новом HA.
6. Обновлять поэтапно, после каждого шага проверка и бэкап: HA до 2025.12, затем интеграции HACS, затем HA до последней версии. Скрипты: [`scripts/update/`](../scripts/update).

## Результат
HA 2025.11.3 (32-бит) → 2026.9.4 (64-бит), дополнения обновлены, ни один прибор не включился сам. Установка Supervised на Ubuntu у HA остаётся «неподдерживаемой» (флаги `os`, `apparmor`), это нормально и на работу не влияет.

## Откат
Восстановление из полного бэкапа, сделанного перед шагом 2, плюс возврат `/etc/hassio.json.bak`.
