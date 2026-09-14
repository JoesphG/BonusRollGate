"""Renders icon.tga and the CurseForge avatar. Needs Pillow and numpy.

A void d6 under a riveted gold bar, corner to corner: the roll, gated. Square
like a Blizzard icon so it fills the AddOns list slot; the earlier round bezel
lost a fifth of the pixels at 20px.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import numpy as np, math, random

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

class Icon:
    def __init__(self, N=128, S=4):
        self.N, self.S, self.P = N, S, N * S
        self.img = Image.new("RGBA", (self.P, self.P), (0, 0, 0, 255))
    def canvas(self): return Image.new("RGBA", (self.P, self.P), (0, 0, 0, 0))
    def out(self): return self.img.resize((self.N, self.N), Image.LANCZOS)

    def background(self, top, bottom, glow=None, glow_at=(0.5, 0.5), glow_r=0.6, stars=140, seed=3):
        P = self.P
        y = np.linspace(0, 1, P)[:, None]
        t = np.repeat(y, P, axis=1)
        arr = np.zeros((P, P, 3))
        for i in range(3): arr[..., i] = top[i] * (1 - t) + bottom[i] * t
        if glow:
            xx, yy = np.meshgrid(np.linspace(0, 1, P), np.linspace(0, 1, P))
            d = np.sqrt((xx - glow_at[0]) ** 2 + (yy - glow_at[1]) ** 2) / glow_r
            g = np.clip(1 - d, 0, 1) ** 2.2
            for i in range(3): arr[..., i] += glow[i] * g
        self.img = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGB").convert("RGBA")
        if stars:
            rnd = random.Random(seed); st = self.canvas(); d = ImageDraw.Draw(st)
            for _ in range(stars):
                x, yv = rnd.random() * P, rnd.random() * P
                r = rnd.choice([0.5, 0.7, 1.0, 1.3, 2.0]) * P / 256
                a = rnd.randint(90, 255)
                d.ellipse([x - r, yv - r, x + r, yv + r], fill=(235, 225, 255, a))
            self.img.alpha_composite(st.filter(ImageFilter.GaussianBlur(P / 600)))
            big = self.canvas(); d = ImageDraw.Draw(big)
            for _ in range(6):
                x, yv = rnd.random() * P, rnd.random() * P; r = P * 0.012
                d.ellipse([x - r, yv - r, x + r, yv + r], fill=(255, 255, 255, 120))
            self.img.alpha_composite(big.filter(ImageFilter.GaussianBlur(P * 0.012)))

    def vignette(self, strength=0.75):
        P = self.P
        xx, yy = np.meshgrid(np.linspace(-1, 1, P), np.linspace(-1, 1, P))
        d = np.clip(np.sqrt(xx ** 2 + yy ** 2) - 0.55, 0, 1.5) / 0.9
        a = (np.clip(d, 0, 1) ** 1.6 * 255 * strength).astype("uint8")
        v = Image.new("RGBA", (P, P), (0, 0, 0, 0)); v.putalpha(Image.fromarray(a, "L"))
        self.img.alpha_composite(v)

    def glow(self, fn, blur, alpha=1.0):
        g = self.canvas(); fn(ImageDraw.Draw(g))
        g = g.filter(ImageFilter.GaussianBlur(blur))
        g.putalpha(g.split()[3].point(lambda v: int(v * alpha)))
        self.img.alpha_composite(g)

    def gradient_poly(self, pts, c0, c1, p0, p1, alpha=255):
        """Fill polygon pts with a linear gradient from colour c0 at point p0 to c1 at p1."""
        P = self.P
        xx, yy = np.meshgrid(np.arange(P), np.arange(P))
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = dx * dx + dy * dy
        t = np.clip(((xx - p0[0]) * dx + (yy - p0[1]) * dy) / L, 0, 1)
        arr = np.zeros((P, P, 4), dtype="uint8")
        for i in range(3): arr[..., i] = (c0[i] * (1 - t) + c1[i] * t).astype("uint8")
        arr[..., 3] = alpha
        layer = Image.fromarray(arr, "RGBA")
        m = Image.new("L", (P, P), 0); ImageDraw.Draw(m).polygon(pts, fill=255)
        layer.putalpha(ImageChops.multiply(layer.split()[3], m))
        self.img.alpha_composite(layer)

    def frame(self, gold=(214, 166, 60), hi=(255, 236, 170), lo=(96, 64, 14), w=None):
        P = self.P; w = w or P * 0.035
        d = ImageDraw.Draw(self.img)
        d.rectangle([0, 0, P, P], outline=lo + (255,), width=int(w))
        d.rectangle([w * 0.35, w * 0.35, P - w * 0.35, P - w * 0.35], outline=gold + (255,), width=int(w * 0.45))
        d.line([(w * 0.35, w * 0.35), (P - w * 0.35, w * 0.35)], fill=hi + (255,), width=int(w * 0.18))
        d.line([(w * 0.35, w * 0.35), (w * 0.35, P - w * 0.35)], fill=hi + (255,), width=int(w * 0.18))
        d.line([(P - w * 0.35, w * 0.35), (P - w * 0.35, P - w * 0.35)], fill=lo + (255,), width=int(w * 0.18))
        d.line([(w * 0.35, P - w * 0.35), (P - w * 0.35, P - w * 0.35)], fill=lo + (255,), width=int(w * 0.18))
        d.rectangle([w * 0.8, w * 0.8, P - w * 0.8, P - w * 0.8], outline=(10, 8, 14, 255), width=int(w * 0.15))

# --- 3D cube -------------------------------------------------------------

def rot(v, yaw, pitch):
    x, y, z = v
    cy, sy = math.cos(yaw), math.sin(yaw)
    x, z = x * cy + z * sy, -x * sy + z * cy
    cp, sp = math.cos(pitch), math.sin(pitch)
    y, z = y * cp - z * sp, y * sp + z * cp
    return (x, y, z)

class Cube:
    """Unit cube at origin, orthographic, camera looking down -z. y up."""
    FACES = {  # name: (normal, corners in face-local (u,v) -> 3d)
        "top":   ((0, 1, 0),  lambda u, v: (u, 1, -v)),
        "front": ((0, 0, 1),  lambda u, v: (u, v, 1)),
        "right": ((1, 0, 0),  lambda u, v: (1, v, -u)),
        "left":  ((-1, 0, 0), lambda u, v: (-1, v, u)),
    }
    def __init__(self, icon, cx, cy, size, yaw=math.radians(32), pitch=math.radians(22), light=(-0.5, 0.9, 0.7)):
        self.i, self.cx, self.cy, self.s = icon, cx, cy, size
        self.yaw, self.pitch = yaw, pitch
        L = np.array(light, float); self.light = L / np.linalg.norm(L)
    def proj(self, p):
        x, y, z = rot(p, self.yaw, self.pitch)
        return (self.cx + x * self.s, self.cy - y * self.s), z
    def face_pts(self, name, inset=1.0):
        _, f = self.FACES[name]
        return [self.proj(f(u * inset, v * inset))[0] for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    def visible(self, name):
        n = rot(self.FACES[name][0], self.yaw, self.pitch)
        return n[2] > 0.02, n
    def shade(self, name, base, ambient=0.45):
        vis, n = self.visible(name)
        lam = max(0.0, float(np.dot(np.array(n), self.light)))
        k = ambient + (1 - ambient) * lam
        return tuple(int(min(255, c * k)) for c in base)
    def draw(self, base, edge=None, edge_w=None, pips=None, pip_col=(200, 150, 255), pip_r=0.13, pip_draw=None):
        i = self.i
        order = sorted(self.FACES, key=lambda f: -self.visible(f)[1][2])
        for name in order:
            vis, n = self.visible(name)
            if not vis: continue
            col = self.shade(name, base)
            pts = self.face_pts(name)
            # gradient across the face: brighter toward the light-facing corner
            bright = lerp(col, (255, 255, 255), 0.22); dark = lerp(col, (0, 0, 0), 0.5)
            xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
            p_hi = (min(xs), min(ys)); p_lo = (max(xs), max(ys))
            i.gradient_poly(pts, bright, dark, p_hi, p_lo)
            if edge:
                ImageDraw.Draw(i.img).polygon(pts, outline=edge + (255,), width=int(edge_w or self.s * 0.03))
            if pips and name in pips:
                self.pips(name, pips[name], pip_col, pip_r, pip_draw)
    def pip_positions(self, name, n):
        lay = {1: [(0, 0)], 2: [(-.55, -.55), (.55, .55)], 3: [(-.55, -.55), (0, 0), (.55, .55)],
               4: [(-.55, -.55), (.55, -.55), (-.55, .55), (.55, .55)],
               5: [(-.55, -.55), (.55, -.55), (0, 0), (-.55, .55), (.55, .55)],
               6: [(-.55, -.6), (.55, -.6), (-.55, 0), (.55, 0), (-.55, .6), (.55, .6)]}[n]
        _, f = self.FACES[name]
        out = []
        for u, v in lay:
            c = self.proj(f(u, v))[0]
            # ellipse axes from projected face basis
            du = self.proj(f(u + 0.01, v))[0]; dv = self.proj(f(u, v + 0.01))[0]
            out.append((c, (du[0] - c[0]) * 100, (du[1] - c[1]) * 100, (dv[0] - c[0]) * 100, (dv[1] - c[1]) * 100))
        return out
    def pip_poly(self, c, ux, uy, vx, vy, r, k=24):
        return [(c[0] + r * (math.cos(a) * ux + math.sin(a) * vx), c[1] + r * (math.cos(a) * uy + math.sin(a) * vy))
                for a in [j * 2 * math.pi / k for j in range(k)]]
    def pips(self, name, n, col, r, custom=None):
        i = self.i
        polys = [self.pip_poly(c, ux, uy, vx, vy, r) for c, ux, uy, vx, vy in self.pip_positions(name, n)]
        if custom:
            for poly, pos in zip(polys, self.pip_positions(name, n)): custom(i, poly, pos, r)
            return
        i.glow(lambda g: [g.polygon(p, fill=col + (255,)) for p in polys], self.s * 0.12, 0.9)
        d = ImageDraw.Draw(i.img)
        for p in polys:
            d.polygon(p, fill=lerp(col, (0, 0, 0), 0.25) + (255,))
        inner = [self.pip_poly(c, ux, uy, vx, vy, r * 0.55) for c, ux, uy, vx, vy in self.pip_positions(name, n)]
        for p in inner: d.polygon(p, fill=lerp(col, (255, 255, 255), 0.55) + (255,))


GOLD, GOLD_HI, GOLD_LO = (222, 172, 62), (255, 240, 180), (104, 68, 14)
OBS = (96, 70, 150)
OBS_EDGE = (215, 185, 255)
PIP = (235, 200, 255)
BG_TOP, BG_BOT, VGLOW = (14, 8, 30), (3, 2, 8), (70, 30, 120)


def render(N, S=4):
    i = Icon(N, S)
    i.background(BG_TOP, BG_BOT, glow=VGLOW, glow_at=(0.55, 0.45), glow_r=0.55, seed=3)
    P = i.P
    c = P / 2
    cube = Cube(i, c, c, P * 0.27, yaw=math.radians(30), pitch=math.radians(20))

    def die_glow(g):
        for f in ("top", "front", "right"):
            if cube.visible(f)[0]:
                g.polygon(cube.face_pts(f, 1.06), fill=(120, 60, 200, 255))

    i.glow(die_glow, P * 0.05, 1.0)
    cube.draw(OBS, edge=OBS_EDGE, pips={"top": 5, "front": 2, "right": 6}, pip_col=PIP, pip_r=0.17)
    # thick diagonal gold bar with rivets, bottom-left to top-right
    w = P * 0.13; L = P * 0.62
    p0 = (c - L, c + L); p1 = (c + L, c - L)
    sh = i.canvas(); ImageDraw.Draw(sh).line([(p0[0], p0[1] + w * 0.3), (p1[0], p1[1] + w * 0.3)], fill=(0, 0, 0, 210), width=int(w * 1.2))
    i.img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(w * 0.2)))
    d = ImageDraw.Draw(i.img)
    d.line([p0, p1], fill=GOLD_LO + (255,), width=int(w))
    off = w * 0.16
    d.line([(p0[0], p0[1] - off), (p1[0], p1[1] - off)], fill=GOLD + (255,), width=int(w * 0.66))
    d.line([(p0[0], p0[1] - off * 1.9), (p1[0], p1[1] - off * 1.9)], fill=GOLD_HI + (255,), width=int(w * 0.14))
    for t in (0.3, 0.7):
        rx, ry = p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t - off
        rr = w * 0.14
        d.ellipse([rx - rr, ry - rr, rx + rr, ry + rr], fill=GOLD_LO + (255,))
        d.ellipse([rx - rr * 0.6, ry - rr * 0.8, rx + rr * 0.2, ry], fill=GOLD_HI + (255,))
    i.vignette(0.7)
    i.frame()
    return i.out()



icon = render(128)
icon.save("images/icon-128.png")
icon.save("icon.tga", compression=None)
render(512, S=2).save("images/curseforge-avatar.png")
print("ok")
