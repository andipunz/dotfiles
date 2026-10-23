"""Prüft, ob regelmäßig erwartete Dokumente fehlen (Gehaltsabrechnungen, Kontoauszüge, Jahresbriefe).

Erwartungen in ~/Documents/.ablage.json, z.B.:
  "expect": [
    {"name": "Gehaltsabrechnung Firma", "folder": "03_Arbeit/Gehalt", "pattern": "_Gehaltsabrechnung_Firma",
     "monthly": true, "since": "2024-06"},
    {"name": "Kontoauszug DKB-1234", "folder": "04_Finanzen/Kontoauszuege/DKB-1234", "pattern": "_Kontoauszug_",
     "max_days": 100}]
monthly: jeder Monat seit "since" braucht eine Datei (der laufende Monat und, bis zum 15., der Vormonat
zählen noch nicht). max_days: die neueste Datei darf höchstens so alt sein (Datum aus dem Dateinamen).
Ergebnis: _Pruefen/YYYY-MM-DD_Bericht_Fehlende-Dokumente.md (ersetzt den vorigen) und eine Mitteilung.
Aufruf von Hand: /usr/bin/python3 ~/.config/ablage/luecken.py
"""
import datetime, json, re, subprocess
from pathlib import Path

DOC = Path.home() / "Documents"


def file_months(folder, pattern):
    out = set()
    for p in (DOC / folder).rglob(f"*{pattern}*"):
        m = re.match(r"(\d{4})-(\d\d)", p.name)
        if m and p.is_file():
            out.add((int(m.group(1)), int(m.group(2))))
    return out


def newest_date(folder, pattern):
    best = None
    for p in (DOC / folder).rglob(f"*{pattern}*"):
        m = re.match(r"(\d{4})-(\d\d)(?:-(\d\d))?", p.name)
        if m and p.is_file():
            d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3) or 1))
            best = max(best, d) if best else d
    return best


def check(expectations, today=None):
    today = today or datetime.date.today()
    findings = []
    for e in expectations:
        if e.get("monthly"):
            have = file_months(e["folder"], e["pattern"])
            y, mo = map(int, e["since"].split("-"))
            last = (today.year, today.month - (1 if today.day > 15 else 2))
            while last[1] < 1:
                last = (last[0] - 1, last[1] + 12)
            missing = []
            while (y, mo) <= last:
                if (y, mo) not in have:
                    missing.append(f"{y}-{mo:02d}")
                y, mo = (y + 1, 1) if mo == 12 else (y, mo + 1)
            if missing:
                findings.append((e["name"], f"{len(missing)} Monate fehlen: " + ", ".join(missing)))
        else:
            d = newest_date(e["folder"], e["pattern"])
            if d is None:
                findings.append((e["name"], "noch kein Dokument abgelegt"))
            elif (today - d).days > e.get("max_days", 400):
                findings.append((e["name"], f"letztes Dokument vom {d:%d.%m.%Y} ({(today - d).days} Tage alt)"))
    return findings


def report(findings, today=None):
    today = today or datetime.date.today()
    review = DOC / "_Pruefen"
    for old in review.glob("*_Bericht_Fehlende-Dokumente.md"):
        old.unlink()
    if not findings:
        return None
    review.mkdir(exist_ok=True)
    out = review / f"{today:%Y-%m-%d}_Bericht_Fehlende-Dokumente.md"
    lines = [f"# Fehlende Dokumente – Stand {today:%d.%m.%Y}", "",
             "Diese regelmäßigen Unterlagen fehlen oder sind überfällig. Herunterladen und in _Eingang legen.", ""]
    lines += [f"- **{name}:** {what}" for name, what in findings]
    out.write_text("\n".join(lines) + "\n")
    return out


def run(expectations):
    findings = check(expectations)
    out = report(findings)
    if out:
        msg = f"{len(findings)} Dokument-Serien unvollständig: {out.name}"
        subprocess.run(["osascript", "-e", f'display notification "{msg}" with title "Fehlende Dokumente"'], check=False)
    return findings


if __name__ == "__main__":
    cfg = json.loads((DOC / ".ablage.json").read_text())
    for name, what in run(cfg.get("expect", [])) or [("alles vollständig", "")]:
        print(f"{name}: {what}")
