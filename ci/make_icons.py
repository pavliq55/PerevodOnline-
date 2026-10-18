from PIL import Image, ImageDraw, ImageFilter, ImageFont
S = 4; W = 1024 * S
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BLACK, GRAPH, YEL, YEL2 = (14, 14, 16), (40, 40, 44), (255, 204, 0), (255, 222, 89)
def P(*v): return [x * S for x in v]
def bubble(d, box, tail, fill=None, outline=None, w=0, r=110):
    d.rounded_rectangle(P(*box), radius=r * S, fill=fill, outline=outline, width=w * S)
    if fill: d.polygon([tuple(P(*p)) for p in tail], fill=fill)
def grad(c1, c2):
    g = Image.new("RGB", (1, 256))
    for y in range(256): g.putpixel((0, y), tuple(int(a + (b - a) * y / 255) for a, b in zip(c1, c2)))
    return g.resize((W, W))
def save(im, n): im.resize((1024, 1024), Image.LANCZOS).save(n)
font = ImageFont.truetype(F, 230 * S)

# A — чёрный фон, жёлтый пузырь «Аб» (я), графитовый «Ab» (собеседник)
im = grad((28, 28, 32), (6, 6, 8)); d = ImageDraw.Draw(im)
bubble(d, (380, 470, 900, 820), [(760, 800), (850, 930), (660, 810)], fill=GRAPH)
d.text(P(640, 640), "Ab", font=font, fill=YEL, anchor="mm")
sh = Image.new("L", (W, W), 0); ds = ImageDraw.Draw(sh); ds.rounded_rectangle(P(120, 208, 640, 558), radius=110 * S, fill=150)
im.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(22 * S)))
bubble(d, (120, 190, 640, 540), [(230, 520), (170, 660), (350, 530)], fill=YEL)
d.text(P(380, 360), "Аб", font=font, fill=BLACK, anchor="mm")
save(im, "A.png")

# B — жёлтый фон, чёрный пузырь «Аб» (я), тёмно-жёлтый «Ab» (собеседник)
im = grad(YEL2, YEL); d = ImageDraw.Draw(im)
bubble(d, (380, 470, 900, 820), [(760, 800), (850, 930), (660, 810)], fill=(214, 160, 0))
d.text(P(640, 640), "Ab", font=font, fill=BLACK, anchor="mm")
sh = Image.new("L", (W, W), 0); ds = ImageDraw.Draw(sh); ds.rounded_rectangle(P(120, 208, 640, 558), radius=110 * S, fill=90)
im.paste((120, 80, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(22 * S)))
bubble(d, (120, 190, 640, 540), [(230, 520), (170, 660), (350, 530)], fill=BLACK)
d.text(P(380, 360), "Аб", font=font, fill=YEL, anchor="mm")
save(im, "B.png")

# C — чёрный фон, один жёлтый пузырь с волной голоса (без букв — читается с любого расстояния)
im = grad((26, 26, 30), (4, 4, 6)); d = ImageDraw.Draw(im)
bubble(d, (150, 250, 874, 740), [(300, 720), (250, 890), (470, 732)], fill=YEL, r=170)
bars = [110, 210, 320, 190, 270, 150, 80]
x0 = 512 - (len(bars) - 1) * 46
for i, h in enumerate(bars):
    x = x0 + i * 92
    d.rounded_rectangle(P(x - 26, 495 - h // 2, x + 26, 495 + h // 2), radius=26 * S, fill=BLACK)
save(im, "C.png")

# Сводка: три варианта рядом, со скруглением как на айфоне
sheet = Image.new("RGB", (3 * 360 + 4 * 40, 460), (242, 242, 247)); ds = ImageDraw.Draw(sheet)
lab = ImageFont.truetype(F, 34)
for i, n in enumerate("ABC"):
    ic = Image.open(n + ".png").resize((360, 360), Image.LANCZOS)
    m = Image.new("L", (360, 360), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 359, 359), radius=81, fill=255)
    x = 40 + i * 400; sheet.paste(ic, (x, 30), m)
    ds.text((x + 180, 425), n, font=lab, fill=(30, 30, 30), anchor="mm")
sheet.save("variants.png")
print("ok")
