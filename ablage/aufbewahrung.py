#!/usr/bin/python3
"""Jährlicher Aufbewahrungs-Bericht: listet Dateien, deren Aufbewahrungsfrist abgelaufen ist.
Löscht nichts. Schreibt _Pruefen/YYYY-MM-DD_Bericht_Aufbewahrung.md und zeigt eine Mitteilung.

Fristen (Ende des Kalenderjahres des Dokumentdatums + N Jahre):
  09_Rechnungen                          10 Jahre, danach nur löschen, wenn der Gegenstand nicht mehr da ist
  05_Versicherungen/*/Beitraege          10 Jahre
  04_Finanzen/Kontoauszuege              10 Jahre
  04_Finanzen/Steuern/<Steuerjahr>       10 Jahre nach dem Steuerjahr (Lohnsteuerbescheinigungen: bis zur Rente)
  07_Auto                                solange das Auto da ist -> nach 10 Jahren nur als Frage
  10_Mail-Archiv                         10 Jahre (die Anhänge sind ohnehin abgelegt)
  alles andere (Ausweise, Zeugnisse, Verträge, Policen, Haus & Bau, Gehalt, SV, Altersvorsorge): dauerhaft
Aufruf: aufbewahrung.py [--jahr 2040]   (Stichtag simulieren)
"""
import datetime, re, subprocess, sys
from pathlib import Path

DOC = Path.home() / "Documents"
YEARS = 10


def doc_year(p, rel):
    m = re.match(r"(\d{4})", p.name)
    if m:
        return int(m.group(1))
    m = re.search(r"/(\d{4})(/|$)", str(rel.parent) + "/")
    return int(m.group(1)) if m else datetime.date.fromtimestamp(p.stat().st_mtime).year


def rule(rel):
    s = str(rel)
    if s.startswith("09_Rechnungen/"):
        return YEARS, "Rechnung: löschen, wenn der Gegenstand nicht mehr vorhanden ist und keine Garantie mehr läuft"
    if s.startswith("05_Versicherungen/") and "/Beitraege/" in s:
        return YEARS, "Beitragsrechnung"
    if s.startswith("04_Finanzen/Kontoauszuege/"):
        return YEARS, "Kontoauszug"
    if s.startswith("04_Finanzen/Steuern/") and "Lohnsteuerbescheinigung" not in s:
        m = re.match(r"04_Finanzen/Steuern/(\d{4})/", s)
        return (YEARS, "Steuerunterlage", int(m.group(1))) if m else (None, "")
    if s.startswith("10_Mail-Archiv/"):
        return YEARS, "Mail (die Anhänge sind abgelegt)"
    if s.startswith("07_Auto/"):
        return YEARS, "Auto-Unterlage: nur löschen, wenn das Fahrzeug verkauft ist"
    return None, ""


def main():
    today = datetime.date.today()
    year = int(sys.argv[sys.argv.index("--jahr") + 1]) if "--jahr" in sys.argv else today.year
    due = []
    for p in sorted(DOC.rglob("*")):
        rel = p.relative_to(DOC)
        if not p.is_file() or p.name.startswith(".") or rel.parts[0].startswith("_"):
            continue
        r = rule(rel)
        if r[0] is None:
            continue
        base = r[2] if len(r) > 2 else doc_year(p, rel)
        if base + r[0] < year:  # kept through the end of base year + N
            due.append((r[1], str(rel), base + r[0]))
    if not due:
        msg = "Keine Unterlagen mit abgelaufener Frist."
    else:
        out = DOC / "_Pruefen" / f"{today:%Y-%m-%d}_Bericht_Aufbewahrung.md"
        out.parent.mkdir(exist_ok=True)
        lines = [f"# Aufbewahrung – Stand {today:%d.%m.%Y}", "",
                 "Diese Dateien haben ihre Mindest-Aufbewahrungsfrist überschritten. Nichts wurde gelöscht.", ""]
        for kind in sorted({d[0] for d in due}):
            lines += [f"## {kind}", ""] + [f"- `{f}` (aufbewahrt bis Ende {y})" for k, f, y in due if k == kind] + [""]
        out.write_text("\n".join(lines))
        msg = f"{len(due)} Dateien können geprüft/gelöscht werden: {out.name}"
    print(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}", msg)
    subprocess.run(["osascript", "-e", f'display notification "{msg}" with title "Aufbewahrung"'], check=False)


if __name__ == "__main__":
    main()
