"""Build a crisp star layer for the ecliptic-south-pole view from a low-res galactic star map (JPEG/PNG).
Stars are detected as local maxima in the (galactic, equirectangular) map and re-rendered as small
Gaussian points at the output resolution, so they stay sharp even though the source is only ~3 px/deg.

Usage: python3 make_stars_layer.py stars_in.jpg sky_stars.png [--size 2048] [--fov 110] [--thr 0.035]
"""
import argparse
import numpy as np
from PIL import Image
from scipy.ndimage import maximum_filter, median_filter, gaussian_filter
from make_sky_layers import ECL2GAL

def srgb_to_lin(x): return np.where(x <= 0.04045, x/12.92, ((x + 0.055)/1.055)**2.4)
def lin_to_srgb(x): return np.where(x <= 0.0031308, x*12.92, 1.055*np.power(np.clip(x, 0, None), 1/2.4) - 0.055)

def detect(path, thr):
    im = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)/255
    H, W, _ = im.shape
    lum = im @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    res = lum - median_filter(lum, size=9)
    pk = (lum == maximum_filter(lum, size=3)) & (res > thr)
    ys, xs = np.nonzero(pk)
    lin = srgb_to_lin(im)
    bg = np.stack([median_filter(lin[..., c], size=9) for c in range(3)], -1)
    star = np.clip(lin - bg, 0, None)
    flux = np.zeros((len(xs), 3), np.float32); cx = np.zeros(len(xs)); cy = np.zeros(len(xs))
    for i, (x, y) in enumerate(zip(xs, ys)):
        y0, y1, x0, x1 = max(y-1, 0), min(y+2, H), x-1, x+2
        xi = np.arange(x0, x1) % W
        win = star[y0:y1][:, xi]
        w = win.sum(-1) + 1e-9
        gy, gx = np.mgrid[y0:y1, x0:x1]
        cx[i] = (w*gx).sum()/w.sum(); cy[i] = (w*gy).sum()/w.sum()
        flux[i] = win.sum((0, 1))
    return flux, cx % W, cy, W, H

def project(cx, cy, W, H, size, fov):
    l = (0.5 - (cx + 0.5)/W) * 2*np.pi; b = (0.5 - (cy + 0.5)/H) * np.pi
    g = np.stack([np.cos(b)*np.cos(l), np.cos(b)*np.sin(l), np.sin(b)], -1)
    e = g @ ECL2GAL                          # galactic -> ecliptic (inverse rotation)
    c = -e[:, 2]                             # cos of angle from the south pole view axis
    k = 2*np.tan(np.radians(fov/2)/2)
    ok = c > -0.5
    px = 2*e[:, 0]/(1 + c); py = -2*e[:, 1]/(1 + c)
    x = (px/k)*(size/2) + size/2 - 0.5; y = (py/k)*(size/2) + size/2 - 0.5
    return x, y, ok & (x > -20) & (x < size+20) & (y > -20) & (y < size+20)

def splat(layer, x, y, val):
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int); fx = x - x0; fy = y - y0
    S = layer.shape[0]
    for dx, dy, w in ((0, 0, (1-fx)*(1-fy)), (1, 0, fx*(1-fy)), (0, 1, (1-fx)*fy), (1, 1, fx*fy)):
        xi, yi = x0 + dx, y0 + dy; m = (xi >= 0) & (xi < S) & (yi >= 0) & (yi < S)
        np.add.at(layer, (yi[m], xi[m]), val[m]*w[m, None])

def render(src, out_png, size=2048, fov=110.0, thr=0.035, gamma=0.55, gain=1.0):
    flux, cx, cy, W, H = detect(src, thr)
    x, y, ok = project(cx, cy, W, H, size, fov)
    flux, x, y = flux[ok], x[ok], y[ok]
    lum = flux @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    A = np.clip((lum/np.percentile(lum, 99.5))**gamma, 0, 1.6)      # 0..~1 apparent brightness
    col = flux/np.maximum(flux.max(1, keepdims=True), 1e-9)
    col = np.clip(0.35 + 0.65*col, 0, 1) if False else col
    mean = col.mean(1, keepdims=True); col = np.clip(mean + 1.25*(col - mean), 0, 1)   # slight saturation boost
    col = 0.25 + 0.75*col/np.maximum(col.max(1, keepdims=True), 1e-9)                  # keep stars from going pure red/blue
    out = np.zeros((size, size, 3), np.float32)
    sig_edges = [0.0, 0.25, 0.5, 0.8, 9]; sig_vals = [0.8, 1.0, 1.3, 1.7]
    for lo, hi, s in zip(sig_edges[:-1], sig_edges[1:], sig_vals):
        m = (A >= lo) & (A < hi)
        if not m.any(): continue
        L = np.zeros_like(out); splat(L, x[m], y[m], col[m]*(A[m, None]))
        for ch in range(3): L[..., ch] = gaussian_filter(L[..., ch], s) * (2*np.pi*s*s)
        out += L
    m = A > 0.7                              # soft glow around the brightest stars
    G = np.zeros_like(out); splat(G, x[m], y[m], col[m]*(A[m, None]-0.6)*0.9)
    for ch in range(3): G[..., ch] = gaussian_filter(G[..., ch], 4.5) * (2*np.pi*4.5**2) * 0.35
    out += G
    out = np.clip(out*gain, 0, 1)
    Image.fromarray((lin_to_srgb(out)*255 + 0.5).clip(0, 255).astype(np.uint8)).save(out_png, optimize=True)
    return len(x), np.stack([x, y, A], 1)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("src"); ap.add_argument("png")
    ap.add_argument("--size", type=int, default=2048); ap.add_argument("--fov", type=float, default=110.0)
    ap.add_argument("--thr", type=float, default=0.035); ap.add_argument("--gain", type=float, default=1.0)
    a = ap.parse_args()
    n, st = render(a.src, a.png, a.size, a.fov, a.thr, gain=a.gain)
    print("stars in view:", n)
    top = st[np.argsort(-st[:, 2])[:6]]
    print("brightest (x, y, A):\n", np.round(top, 1))
