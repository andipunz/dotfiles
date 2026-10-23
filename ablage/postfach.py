"""Holt Mails aus dem Archiv-Ordner von iCloud Mail: Anhänge nach ~/Documents/_Eingang, die ganze Mail als .eml.

Mail archivieren (auf jedem Gerät, Ordner "Archive") -> PDF-/Bild-/Office-Anhänge landen im Eingang und
werden dort wie jede andere Datei einsortiert; Absender, Betreff und Datum gehen an Claude (mail-meta.json).
Die Mail wandert danach nach "Archive/Erledigt" (oder "Archive/Ohne-Anhang", wenn nichts Brauchbares
dranhing) und wird vollständig als .eml in ~/Documents/10_Mail-Archiv/YYYY/ gesichert
(Ende-zu-Ende-verschlüsselt per Advanced Data Protection und im restic-Backup, iCloud Mail nicht).
Einmal am Tag löscht cleanup() Mails aus den beiden Unterordnern, die seit mehr als 30 Tagen abgelegt
sind, aber nur, wenn ihre .eml mit der gespeicherten Größe vorhanden ist (mail-archive.json).

Der alte Ordner "folder" (z. B. "Ablage") wird weiter geleert: Mails darin werden genauso verarbeitet,
die aus "Ablage/Erledigt" und "Ablage/Ohne-Anhang" nur gesichert und in die Archiv-Unterordner verschoben.

Konfiguration in ~/Documents/.ablage.json:
  "imap": {"user": "name@icloud.com", "host": "imap.mail.me.com", "archive": "Archive", "folder": "Ablage"}
  ("archive" und "folder" sind optional)
Passwort (app-spezifisch, appleid.apple.com) nur im Schlüsselbund:
  security add-generic-password -a name@icloud.com -s ablage-imap -w
"""
import datetime, email, email.policy, email.utils, hashlib, imaplib, json, os, re, subprocess, time, unicodedata
from pathlib import Path

ALLOWED = {".pdf", ".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff", ".doc", ".docx", ".xlsx", ".odt", ".rtf"}
MIME_EXT = {"application/pdf": ".pdf", "image/jpeg": ".jpg", "image/png": ".png", "image/heic": ".heic",
            "image/tiff": ".tif"}
MIN_IMAGE_BYTES = 30_000  # smaller images are usually logos or signature graphics
KEEP_DAYS = 30  # filed mails stay in the mailbox this long; afterwards only the archived .eml remains


def keychain_password(user):
    r = subprocess.run(["security", "find-generic-password", "-a", user, "-s", "ablage-imap", "-w"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("kein IMAP-Passwort im Schlüsselbund (Dienst ablage-imap)")
    return r.stdout.strip()


def safe_name(name):
    name = unicodedata.normalize("NFC", name)
    name = re.sub(r"[/\\:\x00-\x1f]", "-", name).strip(". ") or "Anhang"
    return name[:150]


def slug(s, n):
    """ASCII words joined by "-" (naming scheme: no spaces, umlauts or special characters)."""
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"), ("ß", "ss")):
        s = s.replace(a, b)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-")[:n].strip("-")


def mail_key(msg, raw):
    mid = str(msg.get("Message-ID", "")).strip()
    return mid or "sha256:" + hashlib.sha256(raw).hexdigest()


def archive_mail(raw, msg, archive):
    """Saves the whole mail as YYYY-MM-DD_Mail_Absender_Betreff.eml, returns its path relative to `archive`."""
    try:
        day = email.utils.parsedate_to_datetime(str(msg.get("Date", ""))).date()
    except (TypeError, ValueError):
        day = datetime.date.today()
    name, addr = email.utils.parseaddr(str(msg.get("From", "")))
    sender = slug(name, 40) or slug(addr.split("@")[-1].rsplit(".", 1)[0], 40) or "Unbekannt"
    stem = f"{day:%Y-%m-%d}_Mail_{sender}_{slug(str(msg.get('Subject', '')), 60) or 'Ohne-Betreff'}"
    folder = archive / f"{day:%Y}"
    folder.mkdir(parents=True, exist_ok=True)
    target, n = folder / f"{stem}.eml", 2
    while target.exists():
        target, n = folder / f"{stem}-{n}.eml", n + 1
    tmp = folder / f".{target.name}.tmp"
    tmp.write_bytes(raw)
    os.rename(tmp, target)
    return str(target.relative_to(archive))


def load_state(path):
    return json.loads(path.read_text()) if path.exists() else {}


def quote(mailbox):
    return '"' + mailbox.replace("\\", "\\\\").replace('"', '\\"') + '"'


def move(imap, uid, dest):
    if "MOVE" in imap.capabilities:  # RFC 6851; otherwise copy + delete
        if imap.uid("MOVE", uid, quote(dest))[0] == "OK":
            return
    if imap.uid("COPY", uid, quote(dest))[0] != "OK":
        raise RuntimeError(f"Mail konnte nicht nach {dest} kopiert werden")  # never delete without a copy
    imap.uid("STORE", uid, "+FLAGS", "(\\Deleted)")


def attachments(msg):
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        fn = part.get_filename()
        ext = Path(fn).suffix.lower() if fn else MIME_EXT.get(part.get_content_type(), "")
        if ext not in ALLOWED:
            continue
        data = part.get_payload(decode=True) or b""
        if ext in (".jpg", ".jpeg", ".png") and len(data) < MIN_IMAGE_BYTES:
            continue
        yield safe_name(fn or f"Anhang{ext}"), data


def login(cfg):
    imap = imaplib.IMAP4_SSL(cfg.get("host", "imap.mail.me.com"), timeout=60)
    imap.login(cfg["user"], keychain_password(cfg["user"]))
    return imap


def search(imap):
    return (imap.uid("SEARCH", None, "ALL")[1][0] or b"").split()  # iCloud: [None] when empty


def raw_mail(imap, uid):
    raw = imap.uid("FETCH", uid, "(BODY.PEEK[])")[1][0][1]
    return raw, email.message_from_bytes(raw, policy=email.policy.default)


def archive_entry(raw, msg, archive):
    return {"file": archive_mail(raw, msg, archive), "size": len(raw), "filed": time.time()}


def folders(cfg):
    box = cfg.get("archive", "Archive")
    return box, f"{box}/Erledigt", f"{box}/Ohne-Anhang", cfg.get("folder")


def fetch(cfg, inbox, meta_path, archive, state_path):
    """Returns (saved file names, number of processed mails)."""
    box, done, empty, old = folders(cfg)
    meta, state = load_state(meta_path), load_state(state_path)
    saved, mails = [], 0
    imap = login(cfg)
    try:
        for b in (done, empty):
            imap.create(quote(b))  # fails harmlessly if it exists
        for src in (box, old):
            if not src or imap.select(quote(src))[0] != "OK":
                continue
            for uid in search(imap):
                raw, msg = raw_mail(imap, uid)
                key, got = mail_key(msg, raw), 0
                known = key in state  # processed before (archived twice): only move it
                if not known:
                    state[key] = archive_entry(raw, msg, archive)
                    info = {"von": str(msg.get("From", "")), "betreff": str(msg.get("Subject", "")),
                            "datum": str(msg.get("Date", ""))}
                    for name, data in attachments(msg):
                        target, n = inbox / name, 2
                        while target.exists():
                            target = inbox / f"{Path(name).stem}-{n}{Path(name).suffix}"
                            n += 1
                        tmp = inbox / f".mail-{os.getpid()}-{target.name}"  # hidden: the inbox loop skips it
                        tmp.write_bytes(data)
                        os.rename(tmp, target)
                        meta[target.name] = info
                        saved.append(target.name)
                        got += 1
                    mails += 1
                move(imap, uid, done if got or known else empty)
            imap.expunge()
    finally:
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1))
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=1))
        try:
            imap.logout()
        except Exception:
            pass
    return saved, mails


def cleanup(cfg, archive, state_path, days=KEEP_DAYS):
    """Moves mails from the old folder's Erledigt/Ohne-Anhang into the archive subfolders, saves an .eml for
    every mail there that has none yet, and deletes those filed more than `days` ago whose .eml is present
    with the recorded size. Returns (moved, deleted)."""
    box, done, empty, old = folders(cfg)
    state = load_state(state_path)
    moved = deleted = 0
    imap = login(cfg)
    try:
        for src, dest in ((f"{old}/Erledigt", done), (f"{old}/Ohne-Anhang", empty)) if old else ():
            if imap.select(quote(src))[0] != "OK":
                continue
            for uid in search(imap):
                raw, msg = raw_mail(imap, uid)
                key = mail_key(msg, raw)
                if key not in state:
                    state[key] = archive_entry(raw, msg, archive)
                move(imap, uid, dest)
                moved += 1
            imap.expunge()
        for b in (done, empty):
            if imap.select(quote(b))[0] != "OK":
                continue
            for uid in search(imap):
                head = imap.uid("FETCH", uid, "(BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])")[1][0][1]
                key = str(email.message_from_bytes(head, policy=email.policy.default).get("Message-ID", "")).strip()
                if key not in state:  # no Message-ID, or not archived yet
                    raw, msg = raw_mail(imap, uid)
                    key = mail_key(msg, raw)
                    if key not in state:
                        state[key] = archive_entry(raw, msg, archive)
                        continue
                e = state[key]
                f = archive / e["file"]
                if time.time() - e["filed"] > days * 86400 and f.is_file() and f.stat().st_size == e["size"]:
                    imap.uid("STORE", uid, "+FLAGS", "(\\Deleted)")
                    del state[key]
                    deleted += 1
            imap.expunge()
    finally:
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=1))
        try:
            imap.logout()
        except Exception:
            pass
    return moved, deleted
