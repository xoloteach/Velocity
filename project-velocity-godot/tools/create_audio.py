#!/usr/bin/env python3
"""Generate upgraded, multi-layered 32 kHz audio & dynamic music for Project Velocity.

Pure Python 3 stdlib only. Produces crisp SFX, heroic city score, boss combat
stem, urban atmosphere, Rift dimension ambience, and aerodynamic wind loops.
"""
from __future__ import annotations

import math
from pathlib import Path
from random import Random
from struct import pack
from wave import open as open_wave

RATE = 32000
DESTINATION = Path(__file__).resolve().parents[1] / "assets/audio"
DESTINATION.mkdir(parents=True, exist_ok=True)


def write_wav(name: str, samples: list[float], peak: float = 0.92) -> None:
    max_abs = max((abs(s) for s in samples), default=1.0)
    scale = (peak / max_abs) if max_abs > 1e-6 else 1.0
    # Soft saturation to prevent harsh digital clipping
    raw = bytearray(len(samples) * 2)
    for i, s in enumerate(samples):
        v = math.tanh(s * scale * 1.15) / math.tanh(1.15)
        iv = max(-32767, min(32767, round(v * 32766)))
        raw[i * 2 : i * 2 + 2] = pack("<h", iv)
    with open_wave(str(DESTINATION / f"{name}.wav"), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(bytes(raw))


def lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    rc = 1.0 / (math.tau * max(20.0, cutoff_hz))
    dt = 1.0 / RATE
    alpha = dt / (rc + dt)
    out = [0.0] * len(samples)
    y = 0.0
    for i, x in enumerate(samples):
        y += alpha * (x - y)
        out[i] = y
    return out


def highpass(samples: list[float], cutoff_hz: float) -> list[float]:
    lp = lowpass(samples, cutoff_hz)
    return [samples[i] - lp[i] for i in range(len(samples))]


def bandpass(samples: list[float], lo_hz: float, hi_hz: float) -> list[float]:
    return highpass(lowpass(samples, hi_hz), lo_hz)


def apply_fade(samples: list[float], fade_in_s: float = 0.004, fade_out_s: float = 0.012) -> list[float]:
    n = len(samples)
    fi = max(1, round(fade_in_s * RATE))
    fo = max(1, round(fade_out_s * RATE))
    out = list(samples)
    for i in range(min(fi, n)):
        out[i] *= i / fi
    for i in range(min(fo, n)):
        out[n - 1 - i] *= i / fo
    return out


def noise_buf(n: int, seed: int) -> list[float]:
    rng = Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def build_sfx() -> None:
    # 1. Step: tight sneaker/boot contact thud + asphalt grit
    n = round(RATE * 0.13)
    nz = bandpass(noise_buf(n, 101), 400.0, 3200.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 125.0 * math.exp(-t * 28.0) + 48.0
        ph += math.tau * freq / RATE
        thud = math.sin(ph) * math.exp(-t * 36.0) * 0.72
        grit = nz[i] * math.exp(-t * 48.0) * 0.42
        s.append(thud + grit)
    write_wav("step", apply_fade(s, 0.002, 0.015), 0.78)

    # 2. Land: deep superhero impact + stone grit + rush of air
    n = round(RATE * 0.30)
    nz = bandpass(noise_buf(n, 102), 180.0, 2600.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 105.0 * math.exp(-t * 16.0) + 34.0
        ph += math.tau * freq / RATE
        sub = math.sin(ph) * math.exp(-t * 13.0) * 0.90
        crunch = nz[i] * math.exp(-t * 19.0) * 0.55
        s.append(sub + crunch)
    write_wav("land", apply_fade(s, 0.002, 0.025), 0.90)

    # 3. Jump: kinetic upward air-whoosh + crisp takeoff pop
    n = round(RATE * 0.28)
    nz = bandpass(noise_buf(n, 103), 500.0, 4200.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 140.0 + 360.0 * (t / 0.28)
        ph += math.tau * freq / RATE
        env = math.sin(min(1.0, t / 0.28) * math.pi)
        pop = math.sin(ph) * math.exp(-t * 11.0) * 0.55
        whoosh = nz[i] * env * 0.55
        s.append(pop + whoosh)
    write_wav("jump", apply_fade(s, 0.003, 0.02), 0.84)

    # 4. Hit: meaty martial impact + electric snap
    n = round(RATE * 0.28)
    nz = bandpass(noise_buf(n, 104), 350.0, 5200.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 185.0 * math.exp(-t * 22.0) + 46.0
        ph += math.tau * freq / RATE
        punch = (math.sin(ph) + 0.35 * math.sin(ph * 2.1)) * math.exp(-t * 16.0)
        crack = nz[i] * math.exp(-t * 32.0) * 0.85
        s.append(punch * 0.85 + crack)
    write_wav("hit", apply_fade(s, 0.001, 0.02), 0.94)

    # 5. Damage: resonant low jolt + warning grit
    n = round(RATE * 0.32)
    nz = bandpass(noise_buf(n, 105), 140.0, 1800.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 115.0 * math.exp(-t * 9.0) + 38.0
        ph += math.tau * freq / RATE
        tone = (math.sin(ph) + 0.45 * math.sin(ph * 1.414)) * math.exp(-t * 10.5)
        s.append(tone * 0.78 + nz[i] * math.exp(-t * 14.0) * 0.50)
    write_wav("damage", apply_fade(s, 0.002, 0.025), 0.90)

    # 6. Boost: iconic Flash sonic boom + rising electric turbine + crackle
    n = round(RATE * 0.62)
    nz_low = lowpass(noise_buf(n, 106), 1400.0)
    nz_hi = bandpass(noise_buf(n, 107), 2200.0, 7500.0)
    s = []
    ph1, ph2 = 0.0, 0.0
    for i in range(n):
        t = i / RATE
        f1 = 92.0 * math.exp(-t * 8.0) + 42.0
        f2 = 220.0 + 680.0 * (t / 0.62) ** 1.3
        ph1 += math.tau * f1 / RATE
        ph2 += math.tau * f2 / RATE
        boom = math.sin(ph1) * math.exp(-t * 7.5) * 0.95
        turbine = (math.sin(ph2) + 0.35 * math.sin(ph2 * 1.5)) * math.sin(min(1.0, t / 0.62) * math.pi) * 0.38
        crackle = nz_hi[i] * (0.35 + 0.65 * max(0.0, math.sin(t * 95.0))) * math.exp(-t * 4.5) * 0.55
        whoosh = nz_low[i] * math.exp(-t * 3.8) * 0.50
        s.append(boom + turbine + crackle + whoosh)
    write_wav("boost", apply_fade(s, 0.002, 0.04), 0.95)

    # 7. Lightning: sharp crackling arc discharge + thunder body
    n = round(RATE * 0.52)
    nz_hi = bandpass(noise_buf(n, 108), 1600.0, 9000.0)
    nz_lo = lowpass(noise_buf(n, 109), 520.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 320.0 * math.exp(-t * 14.0) + 65.0
        ph += math.tau * freq / RATE
        gate = 1.0 if (math.sin(t * 140.0) + math.cos(t * 217.0)) > -0.35 else 0.18
        zap = nz_hi[i] * gate * math.exp(-t * 7.5) * 0.92
        arc = math.sin(ph + 2.4 * math.sin(ph * 3.1)) * math.exp(-t * 11.0) * 0.55
        thunder = nz_lo[i] * math.exp(-t * 4.2) * 0.62
        s.append(zap + arc + thunder)
    write_wav("lightning", apply_fade(s, 0.001, 0.03), 0.94)

    # 8. Slide: rapid tire/boot friction skid + air rush
    n = round(RATE * 0.42)
    nz = bandpass(noise_buf(n, 110), 650.0, 4800.0)
    s = []
    for i in range(n):
        t = i / RATE
        env = math.sin(min(1.0, t / 0.42) * math.pi) ** 0.7
        s.append(nz[i] * env * 0.78 + math.sin(math.tau * (95.0 - 30.0 * t) * t) * env * 0.20)
    write_wav("slide", apply_fade(s, 0.008, 0.03), 0.80)

    # 9. Rewind: unmistakable reverse-time temporal pull & shimmer
    n = round(RATE * 0.95)
    nz = bandpass(noise_buf(n, 111), 900.0, 5600.0)
    s = []
    ph1, ph2 = 0.0, 0.0
    for i in range(n):
        t = i / RATE
        # Reverse envelope: swells upward then snaps clean at end!
        u = t / 0.95
        rev_env = (u ** 1.35) * math.exp(-max(0.0, u - 0.88) * 28.0)
        f1 = 160.0 + 480.0 * (u ** 1.6)
        f2 = 520.0 + 840.0 * u
        ph1 += math.tau * f1 / RATE
        ph2 += math.tau * f2 / RATE
        ticks = max(0.0, math.sin(math.tau * (10.0 + 18.0 * u) * t)) ** 6.0
        body = (math.sin(ph1) * 0.55 + math.sin(ph2) * 0.30 * (0.4 + 0.6 * ticks)) * rev_env
        shimmer = nz[i] * rev_env * 0.32
        s.append(body + shimmer)
    write_wav("rewind", apply_fade(s, 0.015, 0.025), 0.90)

    # 10. Phase: quantum vibration FM hum
    n = round(RATE * 0.44)
    nz = bandpass(noise_buf(n, 112), 1400.0, 6200.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 390.0 - 150.0 * (t / 0.44)
        ph += math.tau * freq / RATE
        vib = math.sin(ph + 1.8 * math.sin(math.tau * 34.0 * t))
        env = math.exp(-t * 4.5)
        s.append((vib * 0.65 + nz[i] * 0.25) * env)
    write_wav("phase", apply_fade(s, 0.005, 0.03), 0.85)

    # 11. Shockwave: seismic sub-drop + resonant expanding pressure wave
    n = round(RATE * 0.72)
    nz = lowpass(noise_buf(n, 113), 1600.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        freq = 130.0 * math.exp(-t * 7.5) + 32.0
        ph += math.tau * freq / RATE
        sub = math.sin(ph) * math.exp(-t * 4.8) * 1.0
        blast = nz[i] * math.exp(-t * 6.5) * 0.72
        ring = math.sin(math.tau * 210.0 * t) * math.exp(-t * 10.0) * 0.22
        s.append(sub + blast + ring)
    write_wav("shockwave", apply_fade(s, 0.002, 0.04), 0.96)

    # 12. Portal: swirling Speed Force dimensional tear
    n = round(RATE * 0.88)
    nz = bandpass(noise_buf(n, 114), 400.0, 4500.0)
    s = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        u = t / 0.88
        env = math.sin(u * math.pi) ** 0.85
        freq = 146.83 + 110.0 * u
        ph += math.tau * freq / RATE
        chord = (
            math.sin(ph) * 0.45
            + math.sin(ph * 1.5) * 0.30
            + math.sin(ph * 2.25) * 0.22 * math.sin(math.tau * 5.0 * t)
        )
        s.append((chord + nz[i] * 0.35) * env)
    write_wav("portal", apply_fade(s, 0.01, 0.04), 0.88)

    # 13. Goal / Reward fanfare: crisp uplifting heroic chord arpeggio
    n = round(RATE * 1.05)
    notes = (261.626, 329.628, 391.995, 523.251, 659.255, 783.991)
    s = [0.0] * n
    for idx, f in enumerate(notes):
        start = round(idx * 0.068 * RATE)
        for i in range(start, n):
            lt = (i - start) / RATE
            env = min(1.0, lt * 120.0) * math.exp(-lt * 4.2)
            s[i] += (math.sin(math.tau * f * lt) + 0.32 * math.sin(math.tau * f * 2.0 * lt)) * env * 0.25
    write_wav("goal", apply_fade(s, 0.003, 0.05), 0.86)

    # 14. Counter: sharp heroic electric parry chime
    n = round(RATE * 0.38)
    s = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t * 260.0) * math.exp(-t * 9.5)
        chime = (
            math.sin(math.tau * 660.0 * t) * 0.48
            + math.sin(math.tau * 990.0 * t) * 0.35
            + math.sin(math.tau * 1320.0 * t) * 0.22
        )
        punch = math.sin(math.tau * (160.0 * math.exp(-t * 18.0)) * t) * math.exp(-t * 18.0) * 0.55
        s.append(chime * env + punch)
    write_wav("counter", apply_fade(s, 0.001, 0.025), 0.90)


def build_music_and_loops() -> None:
    # 15. Heroic Calder City Score (16.0s seamless 120 BPM loop = 32 beats)
    dur = 16.0
    n = round(RATE * dur)
    # Chord roots per 2-second bar (8 bars): Am -> F -> C -> G -> Am -> F -> Dm -> E
    roots = (110.0, 87.307, 130.813, 98.0, 110.0, 87.307, 146.832, 82.407)
    # Heroic motif melody (quarter-note steps across 8 bars)
    melody = (
        440.0, 0.0, 523.25, 659.25,   587.33, 523.25, 440.0, 0.0,
        392.0, 0.0, 523.25, 587.33,   659.25, 587.33, 523.25, 493.88,
        440.0, 0.0, 523.25, 659.25,   783.99, 659.25, 587.33, 523.25,
        587.33, 0.0, 659.25, 587.33,  493.88, 0.0, 392.0, 440.0,
    )
    hat_nz = highpass(noise_buf(n, 201), 6500.0)
    s = [0.0] * n
    for i in range(n):
        t = i / RATE
        bar = int(t / 2.0) % 8
        root = roots[bar]
        beat_f = t * 2.0  # 120 BPM = 2 beats/sec
        step_16 = (t * 8.0) % 1.0  # 16th-note pulse
        beat_frac = beat_f % 1.0

        # Driving 16th-note synth bass
        bass_env = math.exp(-step_16 * 5.8) * min(1.0, step_16 * 40.0)
        bass = (math.sin(math.tau * root * t) + 0.45 * math.sin(math.tau * root * 2.0 * t)) * bass_env * 0.34

        # Warm heroic pad (root + fifth + octave)
        pad = (
            math.sin(math.tau * root * 2.0 * t) * 0.16
            + math.sin(math.tau * root * 3.0 * t) * 0.11
            + math.sin(math.tau * root * 4.0 * t) * 0.07
        ) * (0.75 + 0.25 * math.sin(math.tau * 0.25 * t))

        # Shimmering speedster arpeggio
        arp_mult = (2.0, 3.0, 4.0, 3.0)[int(t * 8.0) % 4]
        arp_env = math.exp(-step_16 * 9.0) * min(1.0, step_16 * 60.0)
        arp = math.sin(math.tau * root * arp_mult * t) * arp_env * 0.12

        # Heroic brass-synth lead motif
        m_idx = int(beat_f) % len(melody)
        mf = melody[m_idx]
        lead = 0.0
        if mf > 0.0:
            l_env = min(1.0, beat_frac * 24.0) * math.exp(-beat_frac * 3.2)
            lead = (math.sin(math.tau * mf * t) + 0.35 * math.sin(math.tau * mf * 2.0 * t) + 0.15 * math.sin(math.tau * mf * 3.0 * t)) * l_env * 0.22

        # Subtle kinetic kick on beat + offbeat hi-hat
        kick = math.sin(math.tau * (58.0 + 75.0 * math.exp(-beat_frac * 30.0)) * beat_frac * 0.5) * math.exp(-beat_frac * 18.0) * 0.30
        hat_pos = (beat_f + 0.5) % 1.0
        hat = hat_nz[i] * math.exp(-hat_pos * 42.0) * 0.08
        s[i] = bass + pad + arp + lead + kick + hat
    write_wav("score", lowpass(apply_fade(s, 0.03, 0.03), 9000.0), 0.78)

    # 16. Boss Combat Score (16.0s seamless 135 BPM intense loop)
    dur_b = 16.0
    nb = round(RATE * dur_b)
    b_roots = (92.499, 92.499, 103.826, 82.407, 92.499, 110.0, 123.471, 87.307)
    snare_nz = bandpass(noise_buf(nb, 202), 900.0, 6200.0)
    sb = [0.0] * nb
    for i in range(nb):
        t = i / RATE
        bar = int(t / 2.0) % 8
        root = b_roots[bar]
        pulse8 = (t * 9.0) % 1.0
        beat = (t * 2.25) % 1.0
        # Aggressive saw-like ostinato bass
        b_env = math.exp(-pulse8 * 6.5) * min(1.0, pulse8 * 50.0)
        osc = math.sin(math.tau * root * t) + 0.5 * math.sin(math.tau * root * 2.0 * t) + 0.28 * math.sin(math.tau * root * 3.0 * t)
        ost = osc * b_env * 0.36
        # Dramatic brass stab on downbeat & beat 3
        stab_env = math.exp(-beat * 5.0) * min(1.0, beat * 35.0)
        stab = (math.sin(math.tau * root * 4.0 * t) + 0.5 * math.sin(math.tau * root * 6.0 * t)) * stab_env * 0.22
        # Punchy kick & snare
        kick = math.sin(math.tau * (62.0 + 90.0 * math.exp(-beat * 34.0)) * beat * 0.44) * math.exp(-beat * 20.0) * 0.38
        sn_pos = (t * 2.25 + 0.5) % 1.0
        snare = snare_nz[i] * math.exp(-sn_pos * 26.0) * 0.20
        sb[i] = ost + stab + kick + snare
    write_wav("boss_score", lowpass(apply_fade(sb, 0.02, 0.02), 9500.0), 0.82)

    # 17. Urban Atmosphere (8.0s smooth seamless loop)
    dur_a = 8.0
    na = round(RATE * dur_a)
    amb_nz = lowpass(noise_buf(na, 301), 360.0)
    sa = []
    for i in range(na):
        t = i / RATE
        swell = 0.78 + 0.22 * math.sin(math.tau * t / dur_a)
        hum = (math.sin(math.tau * 55.0 * t) * 0.14 + math.sin(math.tau * 82.5 * t) * 0.09) * swell
        sa.append(amb_nz[i] * 0.65 * swell + hum)
    # Crossfade edges cleanly for zero click
    fade = round(0.15 * RATE)
    for i in range(fade):
        w = i / fade
        sa[i] = sa[i] * w + sa[na - fade + i] * (1.0 - w)
    write_wav("atmosphere", sa, 0.68)

    # 18. Rift Ambience (8.0s ethereal harmonic Speed Force loop)
    sr = []
    for i in range(na):
        t = i / RATE
        mod = 0.72 + 0.28 * math.sin(math.tau * 2.0 * t / dur_a)
        pad = (
            math.sin(math.tau * 110.0 * t) * 0.32
            + math.sin(math.tau * 165.0 * t) * 0.24
            + math.sin(math.tau * 247.5 * t) * 0.16 * mod
            + math.sin(math.tau * 330.0 * t + 0.5 * math.sin(math.tau * 3.0 * t / dur_a)) * 0.12
        )
        sr.append(pad)
    write_wav("rift_ambience", sr, 0.68)

    # 19. High-Speed Slipstream Wind (8.0s clean filtered loop)
    nw = round(RATE * 8.0)
    w_nz = bandpass(noise_buf(nw, 302), 180.0, 2600.0)
    sw = [w_nz[i] * (0.85 + 0.15 * math.sin(math.tau * 2.0 * (i / RATE) / 8.0)) for i in range(nw)]
    for i in range(fade):
        w = i / fade
        sw[i] = sw[i] * w + sw[nw - fade + i] * (1.0 - w)
    write_wav("wind", sw, 0.78)


def main() -> None:
    build_sfx()
    build_music_and_loops()
    files = sorted(DESTINATION.glob("*.wav"))
    print(f"Generated {len(files)} upgraded 32 kHz audio assets in {DESTINATION}")


if __name__ == "__main__":
    main()
