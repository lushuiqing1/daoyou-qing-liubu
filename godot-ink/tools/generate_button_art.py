"""Author original text-free SVG brush/paper skins; runtime text stays native."""
from pathlib import Path
import random

target = Path(__file__).resolve().parents[1] / 'assets/ui/buttons'
target.mkdir(parents=True, exist_ok=True)
contour = 'M8 5 L29 4 61 5 95 3.8 129 5 165 4.1 203 5 229 4.2 234 9 233 24 235 40 233 55 228 59 204 58 167 59.2 134 58 99 59 65 58.4 29 59 8 58 5 52 6 38 4.8 25 6 11 Z'
top = 'M8 10 Q31 8 55 9 L88 8.6 127 9.5 160 8.6 199 9.4 230 8.5'
bottom = 'M10 54 L42 55 79 54.3 119 55 157 54.2 191 55 229 54'
colors = {
    'paper': ['#f7efdd', '#f4ecd6', '#e6ddc4'],
    'jade': ['#e7edde', '#dfe8d5', '#cfddc4'],
    'cinnabar': ['#a64734', '#b3513b', '#813727'],
    'selected': ['#f3e6cc', '#f0dfbd', '#e0ccb0'],
}

def write(name, contents, width=240, height=64):
    (target / (name+'.svg')).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{contents}</svg>\n', encoding='utf-8')

for family, fills in colors.items():
    for index, state in enumerate(['normal','hover','pressed']):
        fill = fills[index]
        dark = family == 'cinnabar'
        accent = '#f4dfb4' if dark else '#a64230' if family == 'selected' else '#385447'
        edge = '#743522' if dark else '#a64230' if family == 'selected' else '#75806a' if state == 'normal' else '#3b5749'
        body = f'<path d="{contour}" fill="{fill}" stroke="{edge}" stroke-width="1.1"/>'
        # Feathered dry-brush edges and translucent overprints, with a calm text area.
        if dark:
            body += '<path d="M6 13 L11 6 62 8 108 6 154 8 203 6 233 10 231 14 179 12 134 13 78 11 28 13 Z" fill="#d59975" opacity=".19"/>'
            body += '<path d="M6 48 L25 51 72 50 121 52 166 50 213 52 233 47 231 58 180 56 137 58 79 56 31 58 7 55 Z" fill="#5b2e23" opacity=".16"/>'
        else:
            body += '<path d="M7 11 Q24 7 58 10 L111 8 172 10 228 8 232 16 204 15 134 13 68 16 10 15 Z" fill="#d3c8ac" opacity=".19"/>'
            body += '<path d="M8 48 L41 51 101 49 155 52 217 49 232 52 229 58 186 56 128 58 65 55 9 57 Z" fill="#c2b99d" opacity=".17"/>'
        body += f'<path d="{top}" fill="none" stroke="{accent}" stroke-width=".85" opacity=".32"/>'
        body += f'<path d="{bottom}" fill="none" stroke="{accent}" stroke-width=".8" opacity=".31"/>'
        body += f'<path d="M8 15 L7 22 8 30 M232 32 L231 41 232 48" fill="none" stroke="{accent}" stroke-width="1.2" opacity=".55"/>'
        rng = random.Random(family)
        for i in range(28):
            x = rng.uniform(18,221); y = rng.choice([rng.uniform(7,13),rng.uniform(51,57)])
            body += f'<path d="M{x:.2f} {y:.2f} l{rng.uniform(1,4):.2f} -.3" stroke="{accent}" stroke-width=".65" opacity=".14"/>'
        # Tiny non-letter seal at the rim; no words are baked into the skin.
        if family in ['cinnabar','selected']:
            body += f'<path d="M223 17 L230 16.6 230.4 24 222.7 24.2 Z M226 18 L226 22 M224 20 L228.3 20" fill="none" stroke="{accent}" stroke-width=".85" opacity=".72"/>'
        if state == 'pressed':
            body += f'<path d="M12 7 L48 6 99 7 149 6 193 7 228 6" fill="none" stroke="{edge}" stroke-width="1.9" opacity=".4"/>'
        write(family+'-'+state, body)

write('disabled',f'<path d="{contour}" fill="#e9e3d6" stroke="#aaa794" stroke-width=".9"/><path d="{top}" fill="none" stroke="#a4a490" stroke-width=".8" opacity=".2"/><path d="{bottom}" fill="none" stroke="#a4a490" stroke-width=".8" opacity=".2"/>')
write('focus','<path d="M5 18 L5 7 18 5 M222 5 L235 7 234 20 M235 44 L234 58 221 60 M18 59 L5 57 5 44" fill="none" stroke="#a64230" stroke-width="2.3" stroke-linecap="round"/><path d="M25 60 L62 59 91 60 M150 60 L185 59 216 60" fill="none" stroke="#a64230" stroke-width="1.3" opacity=".7"/>')
for state, fill, opacity in [('active','#b9cba4','.45'),('hover','#cbd5b5','.32'),('pressed','#a8bb95','.48')]:
    write('nav-'+state,f'<path d="M10 7 L28 5 70 8 115 6 161 8 207 6 231 9 232 22 230 43 232 56 208 58 164 56 118 59 73 56 27 59 8 55 6 40 8 25 Z" fill="{fill}" opacity="{opacity}"/><path d="M14 56 L48 54 97 56 147 54 193 56 226 54" fill="none" stroke="#47694e" stroke-width="1.1" opacity=".28"/>')
write('nav-mark','<path d="M1 5 L6 2.6 16 3.8 25 2 36 3.4 44 2.5 50 4 44 5.5 33 5 22 6 11 5.2 4 6 Z" fill="#a64230"/><path d="M4 7 L19 6.5 37 7" stroke="#a64230" opacity=".25" stroke-width=".7"/>',52,9)
for enabled in [False,True]:
    fill = '#5b735b' if enabled else '#c0bba6'; knob = 32 if enabled else 12
    write('toggle-on' if enabled else 'toggle-off',f'<path d="M8 6 L17 5 28 6 37 5 42 9 41 18 36 22 26 21 15 22 7 21 3 17 4 10 Z" fill="{fill}" opacity=".78"/><path d="M7 7 L21 6 37 7" stroke="{fill}" stroke-width="1.3"/><circle cx="{knob}" cy="13.5" r="8.6" fill="#f7f0de" stroke="#6a7c61" stroke-width="1.1"/><path d="M{knob-3} 14 l2 2 4 -5" fill="none" stroke="#a64230" stroke-width="1.3" opacity="{1 if enabled else 0}"/>',46,28)
print('Generated',len(list(target.glob('*.svg'))),'original text-free SVG skins.')
