# Zigbee «ломается», помогает только перезагрузка

## Причина
ZHA и Zigbee2MQTT одновременно работали с **одним и тем же координатором** (сетевой XZG), а в самом координаторе MQTT был настроен на несуществующий брокер. Два клиента конкурировали за один адаптер.

## Что сделано
1. Интеграция ZHA отключена, остался только Zigbee2MQTT.
2. В координаторе выключен MQTT.
3. Обновлены прошивки координатора ([`scripts/update/xzg_update.sh`](../scripts/update/xzg_update.sh)).
4. Автоматизация-сторож: если Zigbee2MQTT больше 3 минут не на связи, перезапустить его дополнение. Ниже пример-набросок по этой схеме, подгоните под свои сущности.

```yaml
alias: z2m watchdog restart
trigger:
  - platform: state
    entity_id: binary_sensor.zigbee2mqtt_bridge_connection_state
    to: "off"
    for: "00:03:00"
action:
  - service: hassio.addon_restart
    data:
      addon: 45df7312_zigbee2mqtt   # слаг своего дополнения Z2M
```

## Приёмы
- Проверять, что Z2M реально может **отправлять**: сброшенный чип принимает пакеты, но не шлёт, при этом статус «on». Смотрите чтение состояния (`/get`), а не включайте приборы.
- `permit_join` не больше 254 с; при ошибке `INVALID_PARAM` перезапустить Z2M.
- Устройство, флудящее ~3 сообщения в секунду (повтор одного dp, низкий LQI), тормозит всю сеть: найдите его по логу MQTT ([`scripts/zigbee/mqtt_listen.py`](../scripts/zigbee/mqtt_listen.py), [`listen_all.py`](../scripts/zigbee/listen_all.py)).
- Для неподдерживаемых устройств помогает внешний конвертер Z2M, пример: [`ekf_is_th_zb.js`](../scripts/zigbee/ekf_is_th_zb.js) (EKF is-th-zb, `_TZE200_3pi0jxej`).
- [`audit.sh`](../scripts/zigbee/audit.sh) показывает устройства, которые давно молчат.
