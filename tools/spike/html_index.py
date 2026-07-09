"""Generates the A/B listening page: a clip x variant grid of audio
players with instant keyboard switching (number keys keep the playback
position, so variants toggle like an A/B switch)."""

from pathlib import Path

SCRIPT = """
const audios = [...document.querySelectorAll('audio')];
let active = null;

function setActive(a) {
  active = a;
  document.querySelectorAll('td.on').forEach(td => td.classList.remove('on'));
  a.closest('td').classList.add('on');
}

audios.forEach(a => a.addEventListener('play', () => {
  audios.forEach(o => { if (o !== a) o.pause(); });
  setActive(a);
}));

document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT') return;
  const col = parseInt(e.key, 10) - 1;
  if (!active || isNaN(col)) return;
  const target = document.querySelector(
    `audio[data-row="${active.dataset.row}"][data-col="${col}"]`);
  if (!target || target === active) return;
  e.preventDefault();
  const t = active.currentTime;
  const wasPlaying = !active.paused;
  active.pause();
  const jump = () => {
    target.currentTime = t;
    if (wasPlaying) target.play();
  };
  if (target.readyState >= 1) {
    jump();
  } else {
    target.addEventListener('loadedmetadata', jump, { once: true });
    target.load();
  }
  setActive(target);
});
"""

STYLE = """
  body { font-family: -apple-system, sans-serif; margin: 2rem; }
  table { border-collapse: collapse; }
  th, td { padding: 0.5rem 0.75rem; border-bottom: 1px solid #ccc; text-align: left; }
  thead th { position: sticky; top: 0; background: canvas; }
  th.clip { white-space: nowrap; }
  td.on { background: color-mix(in srgb, canvas 85%, deepskyblue); border-radius: 6px; }
  audio { width: 200px; }
  p.hint { max-width: 60rem; }
  kbd { border: 1px solid #999; border-radius: 3px; padding: 0 0.3em; font-size: 0.9em; }
"""


def write_index(output_dir: Path, columns: list[tuple[str, str]]) -> Path:
    models = [(d, label) for d, label in columns
              if (output_dir / d).is_dir() and any((output_dir / d).glob("*.wav"))]
    stems = sorted({p.stem for d, _ in models for p in (output_dir / d).glob("*.wav")})

    header = "".join(f"<th>{i + 1} · {label}</th>" for i, (_, label) in enumerate(models))
    rows = []
    for row, stem in enumerate(stems):
        cells = []
        for col, (d, _) in enumerate(models):
            if (output_dir / d / f"{stem}.wav").exists():
                cells.append(
                    f'<td><audio controls preload="metadata" data-row="{row}" '
                    f'data-col="{col}" src="{d}/{stem}.wav"></audio></td>')
            else:
                cells.append("<td>—</td>")
        rows.append(f'<tr><th class="clip">{stem}</th>{"".join(cells)}</tr>')

    keys = "</kbd> <kbd>".join(str(i + 1) for i in range(len(models)))
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>StudioVocals — enhancement A/B</title>
<style>{STYLE}</style>
</head>
<body>
<h1>StudioVocals — enhancement A/B</h1>
<p class="hint">All files 48kHz mono, loudness-matched to -14 LUFS
(true peak ≤ -1 dBTP). Use headphones. <strong>Play any clip, then press
<kbd>{keys}</kbd> to switch variant in place</strong> — playback position
is preserved, so it works like an A/B toggle.</p>
<table>
<thead><tr><th>Clip</th>{header}</tr></thead>
<tbody>
{chr(10).join(rows)}
</tbody>
</table>
<script>{SCRIPT}</script>
</body>
</html>
"""
    index = output_dir / "index.html"
    index.write_text(html)
    return index
