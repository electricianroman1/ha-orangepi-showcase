// EKF is-th-zb — датчик температуры и влажности с экраном (Tuya TS0601 _TZE200_3pi0jxej).
// В Zigbee2MQTT 2.14 его нет; конвертер из https://github.com/Koenkk/zigbee2mqtt/issues/33315
const exposes = require('zigbee-herdsman-converters/lib/exposes');
const tuya = require('zigbee-herdsman-converters/lib/tuya');
const e = exposes.presets;

module.exports = {
    fingerprint: [{modelID: 'TS0601', manufacturerName: '_TZE200_3pi0jxej'}],
    model: 'is-th-zb',
    vendor: 'EKF',
    description: 'Temperature & humidity sensor with LCD screen',
    fromZigbee: [tuya.fz.datapoints],
    toZigbee: [tuya.tz.datapoints],
    onEvent: tuya.onEventSetTime,
    configure: tuya.configureMagicPacket,
    exposes: [e.temperature(), e.humidity(), e.battery()],
    meta: {
        tuyaDatapoints: [
            [1, 'temperature', tuya.valueConverter.divideBy10],
            [2, 'humidity', tuya.valueConverter.raw],
            [4, 'battery', tuya.valueConverter.raw],
        ],
    },
};
