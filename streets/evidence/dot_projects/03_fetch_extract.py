"""Download the matched bike-related DOT presentations and extract implementation timing.

PDFs go to nyc_transport_data/docs/dot_presentations/ (shared raw data, not in git). For each PDF the script
keeps sentences that combine a timing word (install, implement, construct, complete, began,
began, upgrade, timeline, next steps, post-implementation, before/after) with a date (a year,
a season + year, or a month + year), and lane statements (travel / moving lanes, road diet, lane
removal). Output: dot_projects/presentation_timing.csv (kind = timing / lanes)
Usage (from repo root): python evidence/dot_projects/03_fetch_extract.py [matches.csv out.csv]
  presentations fetched: bike-related, or with the street in their title (relevance >= 2)
"""
import csv, os, re, sys, time, urllib.request
import fitz  # pymupdf

ROOT = (os.environ.get("NYC_TRANSPORT_DATA")
        or os.path.join(os.environ["USERPROFILE"], "Dropbox/1_research/nyc_transport_data"))
PDF_DIR = os.path.join(ROOT, "docs", "dot_presentations")
TIMING = re.compile(r"install|implement|construct|complet|began|begin|upgrad|timeline|next steps|"
                    r"post[- ]implementation|before\b.*\bafter|opened|striped|marking|phase", re.I)
DATE = re.compile(r"\b(spring|summer|fall|autumn|winter|january|february|march|april|may|june|july|august|"
                  r"september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\.?\s+(19|20)\d\d\b"
                  r"|\b(19|20)\d\d\b", re.I)


LANES = re.compile(r"\b(travel|moving|traffic|through|vehicle|vehicular|general) lanes?\b|road diet|lane (reduction|removal)|"
                   r"\b(remove|removal of|reduce|reduction (of|from)|from \w+ to \w+)\b.{0,40}\blanes?\b", re.I)
MATCHES = sys.argv[1] if len(sys.argv) > 1 else "evidence/dot_projects/review_matches.csv"
OUT = sys.argv[2] if len(sys.argv) > 2 else "evidence/dot_projects/presentation_timing.csv"


def fetch(url):
    path = os.path.join(PDF_DIR, os.path.basename(url))
    if not os.path.exists(path):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (research; nyc_streets)"})
        try:
            data = urllib.request.urlopen(req, timeout=120).read()
        except Exception as e:
            return None, f"download failed: {e}"
        if not data.startswith(b"%PDF"):
            return None, "not a pdf"
        open(path + ".part", "wb").write(data)
        os.replace(path + ".part", path)
        time.sleep(0.5)
    return path, ""


def snippets(path):
    out = []
    try:
        doc = fitz.open(path)
    except Exception as e:
        return [("", f"unreadable: {e}")]
    for i, page in enumerate(doc):
        text = re.sub(r"[ \t]+", " ", page.get_text())
        lines = [l.strip() for l in re.split(r"(?<=[.!?])\s+|\n", text) if l.strip()]
        for j, s in enumerate(lines):
            # slides often put the label and the date on separate lines ("Implementation" / "Summer 2021")
            if TIMING.search(s) and not DATE.search(s) and j + 1 < len(lines) and DATE.search(lines[j + 1]) and len(lines[j + 1]) <= 60:
                s = s + " " + lines[j + 1]
            if 12 <= len(s) <= 300 and TIMING.search(s) and DATE.search(s):
                out.append((str(i + 1), s, "timing"))
            elif 12 <= len(s) <= 300 and LANES.search(s):
                out.append((str(i + 1), s, "lanes"))
    # de-duplicate, keep order
    seen, uniq = set(), []
    for p, s, k in out:
        if s.lower() not in seen:
            seen.add(s.lower()); uniq.append((p, s, k))
    return uniq[:60]


def main():
    os.makedirs(PDF_DIR, exist_ok=True)
    matches = [r for r in csv.DictReader(open(MATCHES, encoding="utf-8")) if r["bike_related"] == "1" or int(r["relevance"]) >= 2]
    urls = sorted({r["pdf_url"] for r in matches})
    rows = []
    for k, url in enumerate(urls, 1):
        path, err = fetch(url)
        if path is None:
            rows.append({"pdf_url": url, "file": "", "page": "", "kind": "", "snippet": "", "error": err}); continue
        for p, s, kind in snippets(path):
            rows.append({"pdf_url": url, "file": os.path.basename(path), "page": p, "kind": kind, "snippet": s, "error": ""})
        if k % 10 == 0:
            print(k, "of", len(urls), flush=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["pdf_url", "file", "page", "kind", "snippet", "error"])
        w.writeheader(); w.writerows(rows)
    print(len(urls), "pdfs;", sum(1 for r in rows if r["kind"] == "timing"), "timing and", sum(1 for r in rows if r["kind"] == "lanes"), "lane snippets;", sum(1 for r in rows if r["error"]), "errors")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
