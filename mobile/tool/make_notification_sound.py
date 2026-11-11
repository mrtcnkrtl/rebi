#!/usr/bin/env python3
"""Rebi bildirim sesini üretir (yalnızca standart kütüphane; harici ses dosyası, lisans ya da indirme yok).

    python tool/make_notification_sound.py                 # varsayılan: "cinlama" -> Android + iOS klasörlerine yazar
    python tool/make_notification_sound.py --preview       # üç adayı tool/sounds/ altına yazar (dinleyip seçmek için)
    python tool/make_notification_sound.py --pick damla    # seçilen adayı uygulamaya yazar

Ses tamamen sentezlenir: yumuşak başlangıç, cam gibi iki notalı yükselen çınlama, sönümlenen kısmi sesler ve hafif bir oda yankısı.
Kısa (~1,5 sn), kulak tırmalamayan orta-tiz bölgede (≈650–1000 Hz) ve zirvesi -1 dBFS'in altında. Çıktı: 44,1 kHz, 16 bit, mono WAV; Android
(`res/raw`) ve iOS (bildirim sesi için .wav, <30 sn) aynı dosyayı kullanır. `test/notification_sound_test.dart` biçimi ve yerleşimi korur.
"""

import argparse
import math
import os
import struct
import sys
import wave

SR = 44100

# Ad: (notalar [(frekans Hz, başlangıç sn, güç)], tını [(kısmi oranı, genlik, sönüm çarpanı)], temel sönüm sn, toplam sn, yankı)
CANDIDATES = {
    # Varsayılan: E5 -> B5 (tam beşli yükselen), cam çan tınısı.
    'cinlama': dict(
        notes=[(659.25, 0.00, 1.00), (987.77, 0.16, 0.92)],
        partials=[(1.0, 1.00, 1.00), (2.0, 0.30, 0.55), (3.0, 0.11, 0.35), (4.2, 0.04, 0.22)],
        tau=0.34, total=1.7, wet=0.20,
    ),
    # Marimba/damla: sıcak, kısa, tek yönlü iniş-çıkış (G5 -> C6).
    'damla': dict(
        notes=[(783.99, 0.00, 1.00), (1046.50, 0.13, 0.85)],
        partials=[(1.0, 1.00, 1.00), (3.9, 0.16, 0.18), (9.2, 0.03, 0.08)],
        tau=0.16, total=1.1, wet=0.14,
    ),
    # Müzik kutusu: üç notalı sakin arpej (C6 E6 G6 yerine bir oktav aşağı: C5 E5 G5 + tiz kıvılcım).
    'kutu': dict(
        notes=[(523.25, 0.00, 0.95), (659.25, 0.13, 0.90), (783.99, 0.26, 0.85)],
        partials=[(1.0, 1.00, 1.00), (2.0, 0.22, 0.60), (4.0, 0.10, 0.30), (5.4, 0.04, 0.18)],
        tau=0.26, total=1.8, wet=0.22,
    ),
}


def _voice(freq: float, length: int, partials, tau: float) -> list[float]:
    """Tek nota: kısmi seslerin toplamı; her kısmi biraz ayarsız ikinci bir sesle çiftlenir (sıcak, canlı bir tını)."""
    out = [0.0] * length
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f > 9500:
            continue
        for detune, weight in ((1.0, 0.62), (1.0016, 0.38)):
            w = 2 * math.pi * f * detune / SR
            k = 1.0 / (SR * tau * decay)
            for i in range(length):
                out[i] += amp * weight * math.exp(-k * i) * math.sin(w * i)
    # Yumuşak başlangıç (4 ms yükselen kosinüs): tık sesi yok.
    attack = int(SR * 0.004)
    for i in range(min(attack, length)):
        out[i] *= 0.5 - 0.5 * math.cos(math.pi * i / attack)
    return out


def _comb(x: list[float], delay: int, feedback: float, damp: float) -> list[float]:
    y = [0.0] * len(x)
    lp = 0.0
    for i in range(len(x)):
        fb = y[i - delay] if i >= delay else 0.0
        lp = fb * (1 - damp) + lp * damp  # yüksekler yankıda daha çabuk sönsün
        y[i] = x[i] + feedback * lp
    return y


def _allpass(x: list[float], delay: int, gain: float) -> list[float]:
    y = [0.0] * len(x)
    for i in range(len(x)):
        xd = x[i - delay] if i >= delay else 0.0
        yd = y[i - delay] if i >= delay else 0.0
        y[i] = -gain * x[i] + xd + gain * yd
    return y


def _reverb(dry: list[float], wet: float) -> list[float]:
    """Küçük, sıcak bir oda: dört paralel tarak + iki tüm-geçiren (Schroeder)."""
    delays = [int(SR * ms / 1000) for ms in (29.7, 37.1, 41.1, 43.7)]
    combs = [_comb(dry, d, 0.62, 0.35) for d in delays]
    mix = [sum(c[i] for c in combs) / 4 for i in range(len(dry))]
    for d, g in ((int(SR * 5.0 / 1000), 0.7), (int(SR * 1.7 / 1000), 0.7)):
        mix = _allpass(mix, d, g)
    return [dry[i] * (1 - wet) + mix[i] * wet * 1.6 for i in range(len(dry))]


def synthesize(spec: dict) -> list[int]:
    total = int(SR * spec['total'])
    mixbus = [0.0] * total
    for freq, start, power in spec['notes']:
        s = int(SR * start)
        voice = _voice(freq, total - s, spec['partials'], spec['tau'])
        for i, v in enumerate(voice):
            mixbus[s + i] += v * power
    wet = _reverb(mixbus, spec['wet'])
    # Sona doğru 180 ms'lik yumuşak kapanış: ses aniden kesilmez.
    fade = int(SR * 0.18)
    for i in range(fade):
        wet[total - fade + i] *= 0.5 + 0.5 * math.cos(math.pi * i / fade)
    # Zirve -1 dBFS (≈ 0,89): kırpılma yok, telefonlarda yeterince duyulur.
    peak = max(abs(v) for v in wet) or 1.0
    scale = 0.89 / peak
    return [max(-32767, min(32767, int(round(v * scale * 32767)))) for v in wet]


def write_wav(path: str, samples: list[int]) -> None:
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack('<%dh' % len(samples), *samples))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--preview', action='store_true', help='üç adayı tool/sounds/ altına yaz')
    ap.add_argument('--pick', choices=sorted(CANDIDATES), default='cinlama', help='uygulamaya yazılacak aday')
    args = ap.parse_args()

    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    if args.preview:
        for name, spec in CANDIDATES.items():
            write_wav(os.path.join(root, 'tool', 'sounds', f'rebi_{name}.wav'), synthesize(spec))
            print('önizleme:', f'tool/sounds/rebi_{name}.wav')
        return 0
    samples = synthesize(CANDIDATES[args.pick])
    targets = [
        os.path.join(root, 'android', 'app', 'src', 'main', 'res', 'raw', 'rebi_chime.wav'),
        os.path.join(root, 'ios', 'Runner', 'rebi_chime.wav'),
    ]
    for t in targets:
        write_wav(t, samples)
        print('yazıldı:', os.path.relpath(t, root), f'({os.path.getsize(t) // 1024} KB, {len(samples) / SR:.2f} sn)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
