#!/usr/bin/env python3
"""Render explanatory panels around screenshots from the synthetic test run."""

import base64
import subprocess
import tempfile
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "Tools"))
from apply_foundry.browser_tools import resolve_browser

OUTPUT = ROOT / ".github/assets"


def image(name):
    return "data:image/png;base64," + base64.b64encode((HERE / name).read_bytes()).decode("ascii")


PANELS = {
    "readme-abgleich": """
      <div class="kicker">SYNTHETISCHER TESTLAUF · AUSZUG AUS DER MATRIX</div>
      <h1>Was verlangt die Stelle?<br><span>Was ist im Profil belegt?</span></h1>
      <p class="intro">Im Beispiel werden Anforderungen mit konkreten Profilstellen verbunden.</p>
      <div class="columns">
        <section><div class="label">STELLENANZEIGE</div><h2>Fullstack Developer</h2>
        <p>Fullstack-Entwicklung und Python für wartbare APIs und Qualitätssicherung.</p>
        <div class="tag">Fiktive Stelle · Acme GmbH</div></section>
        <section class="profile"><div class="label">BELEG IM PROFIL</div><h2>01/2020 – 12/2024</h2>
        <p>Fullstack-Entwicklung mit Python, PHP und Webtechnologien.</p>
        <div class="tag">Synthetische Berufserfahrung</div></section>
      </div>
      <div class="bar"><b>Matrix</b> Fullstack-Entwicklung und Python sind mit demselben Profileintrag verknüpft.</div>
    """,
    "readme-pruefung": """
      <div class="kicker">SYNTHETISCHER TESTLAUF · ECHTE CHROMIUM-VORSCHAU</div>
      <div class="review">
        <div><h1>Jetzt bist<br><span>du gefragt.</span></h1>
        <p class="intro">Der Testlauf hält bei der persönlichen Sichtprüfung an. Die Vorschauen rechts stammen aus dem tatsächlichen Layoutcheck.</p>
        <div class="steps"><p><b>1</b> Namen, Daten und Aussagen prüfen</p>
        <p><b>2</b> Lesbarkeit und Seitenaufteilung ansehen</p>
        <p><b>3</b> Jede genannte Seite persönlich bestätigen</p></div>
        <p class="note">Fiktive Minimaldokumente für den technischen Test</p></div>
        <div class="paper"><img src="CV_IMAGE" alt="Synthetische Lebenslaufvorschau">
        <img src="LETTER_IMAGE" alt="Synthetische Anschreibenvorschau"></div>
      </div>
    """,
    "readme-ergebnis": """
      <div class="kicker">SCHEMATISCHE DARSTELLUNG · SYNTHETISCHES BEISPIEL</div>
      <h1>Nach deiner Prüfung:<br><span>die richtigen Dateien finden.</span></h1>
      <p class="intro">Die lokale Freigabe legt die ausgewählten Dateien in einem eigenen Ordner ab.</p>
      <div class="columns">
        <section class="profile"><div class="label">VERSAND/</div><h2>Deine Unterlagen</h2>
        <p>Lebenslauf.pdf<br>Anschreiben.pdf<br>E-Mail-Nachricht.md</p>
        <div class="tag">Für die Bewerbung vorgesehen</div></section>
        <section><div class="label">INTERN/</div><h2>Deine Nachweise</h2>
        <p>HTML-Quellen<br>Analyse und Qualitätscheck<br>Weitere Arbeitsunterlagen</p>
        <div class="tag">Für deine Dokumentation</div></section>
      </div>
      <div class="bar"><b>Du entscheidest</b> über die persönliche Freigabe und den späteren Versand.</div>
    """,
}

STYLE = """
*{box-sizing:border-box}body{margin:0;color:#17263d;font-family:Arial,'Liberation Sans',sans-serif}
main{width:1200px;height:700px;padding:48px 60px;background:#f1f5fa}
.kicker{font-size:15px;font-weight:bold;letter-spacing:1.1px;color:#375e83}
h1{font-size:44px;line-height:1.08;letter-spacing:-1.2px;margin:24px 0 14px}
h1 span{color:#117a72}.intro{font-size:20px;line-height:1.4;color:#4b6078;margin:0 0 26px}
.columns{display:grid;grid-template-columns:1fr 1fr;gap:20px}
section{height:255px;background:#fff;border:1px solid #d9e2ed;border-radius:16px;padding:26px}
section.profile{background:#e5f5f1;border-color:#a8d8cd}.label{font-size:14px;letter-spacing:1px;font-weight:bold;color:#406788}
h2{font-size:26px;margin:19px 0 12px}section p{font-size:19px;line-height:1.45;margin:0}
.tag{font-size:15px;font-weight:bold;color:#316a65;margin-top:18px}.bar{background:#183b5c;color:#fff;border-radius:12px;margin-top:22px;padding:20px;font-size:18px}
.bar b{color:#7ce3d0;margin-right:14px}.review{display:grid;grid-template-columns:1fr 500px;gap:30px}
.steps p{font-size:20px}.steps b{display:inline-block;background:#dcebe9;color:#12695f;border-radius:50%;padding:8px 13px;margin-right:12px}
.note{font-size:15px;color:#536a7f}.paper{display:flex;align-items:center;gap:14px}
.paper img{width:235px;box-shadow:0 12px 25px #263b5630;background:white}
"""


def main():
    browser = resolve_browser(requested="auto", require_chromium=True)
    OUTPUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="apply-readme-") as temp:
        directory = Path(temp)
        for name, body in PANELS.items():
            body = body.replace("CV_IMAGE", image("lebenslauf.png")).replace("LETTER_IMAGE", image("anschreiben.png"))
            page = directory / (name + ".html")
            page.write_text("<!doctype html><html lang='de'><meta charset='utf-8'><style>" + STYLE + "</style><main>" + body + "</main></html>", encoding="utf-8")
            result = subprocess.run(
                [str(browser.path), "--headless=new", "--disable-gpu", "--disable-dev-shm-usage",
                 "--no-first-run", "--disable-background-networking", "--hide-scrollbars",
                 "--user-data-dir=" + str(directory / "profile"), "--window-size=1200,700",
                 "--screenshot=" + str(OUTPUT / (name + ".png")), page.as_uri()],
                capture_output=True, text=True, timeout=60,
            )
            if result.returncode:
                raise RuntimeError(result.stderr)
            print(OUTPUT / (name + ".png"))


if __name__ == "__main__":
    main()
