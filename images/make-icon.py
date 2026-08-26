from PIL import Image, ImageDraw, ImageFilter
import math, sys

BG_DEEP  = (10, 5, 18)
VOID_MID = (64, 26, 108)
VOID_LIT = (150, 86, 228)
VOID_DK  = (52, 20, 92)
GLOW     = (222, 192, 255)
GOLD     = (240, 186, 68)
GOLD_HI  = (255, 238, 172)
GOLD_LO  = (116, 76, 20)
IRON     = (74, 74, 88)

def lerp(a, b, t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))

def render(N, S=8, pad=0.47):
    P = N*S
    def canvas(): return Image.new("RGBA", (P, P), (0, 0, 0, 0))
    c = P/2

    def radial(img, inner, outer, radius):
        d = ImageDraw.Draw(img)
        for i in range(200, 0, -1):
            t = i/200; r = radius*t
            d.ellipse([c-r, c-r, c+r, c+r], fill=lerp(inner, outer, t**0.8)+(255,))

    def hexagon(r, rot=math.pi/2, cx=None, cy=None):
        cx = c if cx is None else cx; cy = c if cy is None else cy
        return [(cx+r*math.cos(rot+i*math.pi/3), cy+r*math.sin(rot+i*math.pi/3)) for i in range(6)]

    def glow(fn, blur, alpha):
        g = canvas(); fn(g)
        g = g.filter(ImageFilter.GaussianBlur(blur))
        g.putalpha(g.split()[3].point(lambda v: int(v*alpha)))
        return g

    img = canvas()
    radial(img, VOID_MID, BG_DEEP, P*pad)

    R = P*0.315
    # outer glow off the gem
    img.alpha_composite(glow(lambda g: ImageDraw.Draw(g).polygon(hexagon(R), fill=VOID_LIT+(255,)), P*0.06, 1.0))

    d = ImageDraw.Draw(img)
    d.polygon(hexagon(R), fill=VOID_LIT+(255,))

    # facets: upper half lit, lower half shadowed
    for i in range(6):
        a0 = math.pi/2 + i*math.pi/3
        a1 = a0 + math.pi/3
        p0 = (c+R*math.cos(a0), c+R*math.sin(a0))
        p1 = (c+R*math.cos(a1), c+R*math.sin(a1))
        mid_y = (p0[1]+p1[1])/2
        shade = lerp(VOID_LIT, GLOW, 0.42) if mid_y < c else lerp(VOID_LIT, VOID_DK, 0.45)
        d.polygon([(c, c), p0, p1], fill=shade+(255,))

    # bright core
    d.polygon(hexagon(R*0.52), fill=GLOW+(255,))
    d.polygon(hexagon(R*0.52), outline=lerp(GLOW, VOID_LIT, 0.5)+(255,), width=int(P*0.006))

    # gem rim
    d.polygon(hexagon(R), outline=lerp(VOID_LIT, GLOW, 0.55)+(220,), width=int(P*0.011))

    # gold bar, with a shadow so it reads as in front of the gem
    bh = P*0.125
    sh = canvas()
    ImageDraw.Draw(sh).rounded_rectangle(
        [P*0.075, c-bh/2+P*0.022, P*0.925, c+bh/2+P*0.022], radius=bh*0.34, fill=(0, 0, 0, 190))
    sh = sh.filter(ImageFilter.GaussianBlur(P*0.016))
    _cr = P*pad*0.955
    _cm = Image.new("L", (P, P), 0)
    ImageDraw.Draw(_cm).ellipse([c-_cr, c-_cr, c+_cr, c+_cr], fill=255)
    sh.putalpha(Image.composite(sh.split()[3], Image.new("L", (P, P), 0), _cm))
    img.alpha_composite(sh)

    bar = canvas()
    d = ImageDraw.Draw(bar)
    x0, x1 = P*0.075, P*0.925
    y0, y1 = c-bh/2, c+bh/2
    d.rounded_rectangle([x0, y0, x1, y1], radius=bh*0.34, fill=GOLD+(255,))
    d.rounded_rectangle([x0, y0, x1, y0+bh*0.30], radius=bh*0.28, fill=GOLD_HI+(255,))
    d.rounded_rectangle([x0, y1-bh*0.24, x1, y1], radius=bh*0.28, fill=GOLD_LO+(255,))
    rr = bh*0.155
    for rx in (c-P*0.315, c+P*0.315):
        d.ellipse([rx-rr, c-rr, rx+rr, c+rr], fill=GOLD_LO+(255,))
        d.ellipse([rx-rr*0.55, c-rr*0.75, rx+rr*0.35, c+rr*0.15], fill=GOLD_HI+(255,))

    inner_r = P*pad*0.955
    clip = Image.new("L", (P, P), 0)
    ImageDraw.Draw(clip).ellipse([c-inner_r, c-inner_r, c+inner_r, c+inner_r], fill=255)
    bar.putalpha(Image.composite(bar.split()[3], Image.new("L", (P, P), 0), clip))
    img.alpha_composite(bar)

    d = ImageDraw.Draw(img)

    # bezel
    d.ellipse([c-P*pad, c-P*pad, c+P*pad, c+P*pad], outline=IRON+(255,), width=int(P*0.034))
    d.ellipse([c-P*pad*0.962, c-P*pad*0.962, c+P*pad*0.962, c+P*pad*0.962],
              outline=lerp(IRON, (0, 0, 0), 0.55)+(210,), width=int(P*0.013))

    return img.resize((N, N), Image.LANCZOS)

icon = render(128)
icon.save("final.png")
render(512, S=4).save("final_512.png")

# TGA for WoW: uncompressed 32-bit, flattened over nothing (keeps alpha)
icon.save("icon.tga", compression=None)

sheet = Image.new("RGBA", (620, 200), (52, 52, 56, 255))
sheet.alpha_composite(icon, (20, 20))
x = 175
for sz in (64, 48, 32, 24, 20):
    sheet.alpha_composite(icon.resize((sz, sz), Image.LANCZOS), (x, 40))
    sheet.alpha_composite(icon.resize((sz, sz), Image.LANCZOS), (x, 120))
    x += sz + 18
sheet.save("final_sheet.png")
print("ok")
