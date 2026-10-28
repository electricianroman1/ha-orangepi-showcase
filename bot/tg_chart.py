"""Картинки для Telegram-бота: график температуры за сутки и вода по дням.

Запуск из HA (shell_command.tg_chart): python3 /config/tg/tg_chart.py <temp|water> '<json>'
Данные готовит HA через recorder.get_statistics, сюда приходит уже компактный JSON:
  temp:  {"tz": 10800, "rooms": [[имя, [[unix, °C], ...]], ...], "outside": [...]}
  water: {"tz": 10800, "cold": [[unix начала дня, м³], ...], "hot": [...]}  — прошлый и текущий месяц
Печатает путь к готовой PNG.
"""
import json
import sys
from datetime import datetime, timedelta, timezone

from PIL import Image, ImageDraw, ImageFont

OUT = "/config/tg/media"
FONT = "/config/tg/fonts/DejaVu-Sans.ttf"
FONT_B = "/config/tg/fonts/DejaVu-Sans-Bold.ttf"
S = 2  # рисуем в 2× и уменьшаем — сглаженные линии


def num(v, n):
    return f"{v:.{n}f}".replace(".", ",")

BG, CARD, GRID, TEXT, MUTED = "#f4f6fa", "#ffffff", "#e3e7ee", "#1f2733", "#7a8494"
COLORS = ["#4c7cf3", "#f08a24", "#2bb673", "#d64f8a", "#8a5cf5", "#14a3b8", "#c9a227"]
COLD, HOT = "#3d8bfd", "#f0544f"


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size * S)


def smooth(pts, k=3):
    """Скользящее среднее — 5-минутная статистика у дешёвых датчиков шумит."""
    out = []
    for i in range(len(pts)):
        win = [v for _, v in pts[max(0, i - k):i + k + 1]]
        out.append((pts[i][0], sum(win) / len(win)))
    return out


def canvas(w, h, title, subtitle):
    img = Image.new("RGB", (w * S, h * S), BG)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((16 * S, 16 * S, (w - 16) * S, (h - 16) * S), 24 * S, fill=CARD)
    d.text((40 * S, 34 * S), title, font=font(30, True), fill=TEXT)
    d.text((40 * S, 76 * S), subtitle, font=font(18), fill=MUTED)
    return img, d


def nice_range(lo, hi, step):
    lo = (int(lo // step)) * step
    hi = (int(hi // step) + 1) * step
    return lo, hi


def line_panel(d, box, series, t0, t1, tz, label, step):
    """Панель с линиями. series: [(имя, [(unix, v)], цвет)]. Справа — легенда с текущим значением."""
    x0, y0, x1, y1 = box
    vals = [v for _, pts, _ in series for _, v in pts]
    if not vals:
        d.text((x0 * S, y0 * S), "нет данных", font=font(18), fill=MUTED)
        return
    lo, hi = nice_range(min(vals), max(vals), step)
    if hi - lo < step * 2:
        hi = lo + step * 2
    px = lambda t: (x0 + (t - t0) / (t1 - t0) * (x1 - x0)) * S
    py = lambda v: (y1 - (v - lo) / (hi - lo) * (y1 - y0)) * S

    d.text((x0 * S, (y0 - 30) * S), label, font=font(17, True), fill=MUTED)
    v = lo
    while v <= hi + 1e-9:
        d.line((x0 * S, py(v), x1 * S, py(v)), fill=GRID, width=S)
        d.text(((x0 - 46) * S, py(v) - 10 * S), f"{v:g}°".replace(".", ","), font=font(15), fill=MUTED)
        v += step
    # метки времени каждые 3 часа по местному времени
    t = (int(t0 + tz) // 10800 + 1) * 10800 - tz
    while t < t1:
        d.line((px(t), y0 * S, px(t), y1 * S), fill=GRID, width=S)
        hh = datetime.fromtimestamp(t + tz, timezone.utc).strftime("%H:%M")
        d.text((px(t) - 22 * S, (y1 + 8) * S), hh, font=font(14), fill=MUTED)
        t += 10800

    ly = y0
    for name, pts, color in series:
        if len(pts) > 1:
            d.line([(px(t), py(v)) for t, v in pts], fill=color, width=3 * S, joint="curve")
        if pts:
            t, v = pts[-1]
            d.ellipse((px(t) - 5 * S, py(v) - 5 * S, px(t) + 5 * S, py(v) + 5 * S), fill=color)
            d.rounded_rectangle(((x1 + 24) * S, (ly + 4) * S, (x1 + 38) * S, (ly + 18) * S), 4 * S, fill=color)
            d.text(((x1 + 46) * S, ly * S), name, font=font(17), fill=TEXT)
            d.text(((x1 + 190) * S, ly * S), f"{num(v, 1)}°", font=font(17, True), fill=TEXT)
        ly += 30


def temp_chart(data):
    tz = data["tz"]
    now = datetime.now(timezone.utc).timestamp()
    t0, t1 = now - 24 * 3600, now
    rooms = [(n, smooth(p), COLORS[i % len(COLORS)]) for i, (n, p) in enumerate(data["rooms"])]
    outside = [(n, smooth(p), COLORS[(i + 4) % len(COLORS)]) for i, (n, p) in enumerate(data["outside"])]
    w, h = 1200, 860
    stamp = datetime.fromtimestamp(now + tz, timezone.utc).strftime("%d.%m %H:%M")
    img, d = canvas(w, h, "Температура за сутки", f"по комнатам · обновлено {stamp}")
    line_panel(d, (100, 160, 880, 470), rooms, t0, t1, tz, "В КВАРТИРЕ", 1)
    line_panel(d, (100, 570, 880, 790), outside, t0, t1, tz, "УЛИЦА И БАЛКОН", 5)
    return save(img, "temp.png")


def water_chart(data):
    tz = data["tz"]
    now = datetime.now(timezone.utc) + timedelta(seconds=tz)
    days = {}
    for idx, key in enumerate(("cold", "hot")):
        for start, v in data[key]:
            day = datetime.fromtimestamp(start + tz, timezone.utc).date()
            pair = list(days.get(day, (0, 0)))
            pair[idx] += v or 0
            days[day] = tuple(pair)
    cur = [(dd, *v) for dd, v in sorted(days.items()) if (dd.year, dd.month) == (now.year, now.month)]
    prev_m = (now.replace(day=1) - timedelta(days=1))
    prev = [v for dd, v in days.items() if (dd.year, dd.month) == (prev_m.year, prev_m.month)]
    # прошлый месяц за те же числа — честное сравнение «на сегодня»
    prev_same = [v for dd, v in days.items()
                 if (dd.year, dd.month) == (prev_m.year, prev_m.month) and dd.day <= now.day]

    months = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август",
              "сентябрь", "октябрь", "ноябрь", "декабрь"]
    tc, th = sum(c for _, c, _ in cur), sum(h for _, _, h in cur)
    w, hgt = 1200, 820
    img, d = canvas(w, hgt, f"Вода — {months[now.month - 1]}", "расход по дням, м³")

    # итоги
    d.rounded_rectangle((40 * S, 120 * S, 300 * S, 200 * S), 16 * S, fill="#eaf2ff")
    d.text((60 * S, 132 * S), "Холодная", font=font(16), fill=MUTED)
    d.text((60 * S, 156 * S), f"{num(tc, 3)} м³", font=font(26, True), fill=COLD)
    d.rounded_rectangle((320 * S, 120 * S, 580 * S, 200 * S), 16 * S, fill="#ffecec")
    d.text((340 * S, 132 * S), "Горячая", font=font(16), fill=MUTED)
    d.text((340 * S, 156 * S), f"{num(th, 3)} м³", font=font(26, True), fill=HOT)
    if prev_same:
        pc, ph = sum(v[0] for v in prev_same), sum(v[1] for v in prev_same)
        def cmp(a, b):
            if b <= 0:
                return "—"
            p = (a - b) / b * 100
            return f"{'▲' if p > 0 else '▼'} {abs(p):.0f} %"
        d.text((610 * S, 132 * S), f"к прошлому месяцу (1–{now.day} число)", font=font(16), fill=MUTED)
        d.text((610 * S, 158 * S), f"холодная {cmp(tc, pc)}   ·   горячая {cmp(th, ph)}", font=font(19, True), fill=TEXT)
    if prev:
        d.text((610 * S, 186 * S) if prev_same else (610 * S, 132 * S),
               f"весь {months[prev_m.month - 1]}: {num(sum(v[0] for v in prev), 2)} / {num(sum(v[1] for v in prev), 2)} м³",
               font=font(15), fill=MUTED)

    # столбики
    x0, y0, x1, y1 = 90, 250, 1150, 730
    import calendar
    ndays = calendar.monthrange(now.year, now.month)[1]
    top = max([max(c, h) for _, c, h in cur] + [0.05])
    step = 0.05 if top <= 0.25 else (0.1 if top <= 0.6 else 0.25)
    hi = (int(top / step) + 1) * step
    py = lambda v: (y1 - v / hi * (y1 - y0)) * S
    v = 0.0
    while v <= hi + 1e-9:
        d.line((x0 * S, py(v), x1 * S, py(v)), fill=GRID, width=S)
        d.text(((x0 - 64) * S, py(v) - 10 * S), num(v, 2), font=font(14), fill=MUTED)
        v += step
    slot = (x1 - x0) / ndays
    bw = slot * 0.36
    byday = {dd.day: (c, h) for dd, c, h in cur}
    for day in range(1, ndays + 1):
        cx = x0 + slot * (day - 0.5)
        c, h_ = byday.get(day, (0, 0))
        if c > 0:
            d.rounded_rectangle(((cx - bw) * S, py(c), cx * S, y1 * S), 3 * S, fill=COLD)
        if h_ > 0:
            d.rounded_rectangle((cx * S, py(h_), (cx + bw) * S, y1 * S), 3 * S, fill=HOT)
        if day == 1 or day % 5 == 0 or day == now.day:
            col = TEXT if day == now.day else MUTED
            d.text(((cx - 9) * S, (y1 + 8) * S), str(day), font=font(14, day == now.day), fill=col)
    return save(img, "water.png")


def save(img, name):
    path = f"{OUT}/{name}"
    img.resize((img.width // S, img.height // S), Image.LANCZOS).save(path, optimize=True)
    return path


if __name__ == "__main__":
    kind, payload = sys.argv[1], json.loads(sys.argv[2])
    print({"temp": temp_chart, "water": water_chart}[kind](payload))
