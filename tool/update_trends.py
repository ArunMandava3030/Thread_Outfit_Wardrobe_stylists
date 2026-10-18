"""Fetch public RSS headline metadata for Thread's static Pages feed.

No article body, images, affiliate link, API key, or user data is collected.
Run: python tool/update_trends.py --output web/data/trends.json
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import html
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


FEEDS = (
    ("GQ", "https://www.gq.com/feed/rss", "gq.com"),
    ("Esquire", "https://www.esquire.com/rss/style.xml/", "esquire.com"),
    ("FashionBeans", "https://www.fashionbeans.com/feed/", "fashionbeans.com"),
)
MAX_AGE = timedelta(days=90)
MAX_BYTES = 2_000_000
CLOTHING = re.compile(
    r"\b(menswear|fashion|outfits?|shirts?|pants|trousers|denim|jeans|suits?|"
    r"tailoring|blazers?|jackets?|coats?|parkas?|outerwear|knitwear|sweaters?|"
    r"cardigans?|sneakers?|shoes|boots|loafers?|footwear|streetwear|athleisure|"
    r"wardrobe|layering|runway|preppy|corduroy|shorts)\b", re.I
)
EXCLUDED = re.compile(
    r"\b(watches?|cologne|fragrance|perfume|grooming|hairstyles?|haircuts?|"
    r"skincare|skin care|beard|shaving|shavers?|mattresses?|furniture)\b", re.I
)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_date(value: str) -> datetime:
    try:
        result = parsedate_to_datetime(value)
    except (ValueError, TypeError):
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("A timezone is required")
    return result.astimezone(timezone.utc)


def clean_url(value: str, domain: str) -> str | None:
    try:
        uri = urlsplit(value.strip())
        if (
            uri.scheme != "https"
            or uri.hostname not in (domain, "www." + domain)
            or uri.username
            or uri.password
            or uri.port not in (None, 443)
            or len(value) > 2000
        ):
            return None
        return urlunsplit((uri.scheme, uri.netloc, uri.path, "", ""))
    except ValueError:
        return None


def parse_feed(raw: bytes, publisher: str, domain: str, now: datetime) -> list[dict]:
    if len(raw) > MAX_BYTES or b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("Feed is too large or contains unsupported XML declarations")
    root = ET.fromstring(raw)
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError("Expected an RSS channel")
    items = []
    for entry in root.findall("./channel/item"):
        title = " ".join(html.unescape(entry.findtext("title", "")).split())
        title = re.sub(r"<[^>]+>", "", title).strip()
        link = clean_url(entry.findtext("link", ""), domain)
        categories = " ".join(x.text or "" for x in entry.findall("category"))
        if not title or not link or EXCLUDED.search(title + " " + categories):
            continue
        if not CLOTHING.search(title) and not (
            "/mens-fashion/" in link
            or re.search(r"\b(men.s fashion|men.s style|style)\b", categories, re.I)
        ):
            continue
        try:
            published = parse_date(entry.findtext("pubDate", ""))
        except (ValueError, TypeError, OverflowError):
            continue
        if published > now or now - published > MAX_AGE:
            continue
        # Only short headline metadata is republished, with a direct source link.
        if len(title) > 160:
            title = title[:157].rsplit(" ", 1)[0] + "..."
        items.append({"headline": title, "url": link, "publisher": publisher,
                      "publishedAt": iso(published)})
    return items


def fetch_source(source: tuple, now: datetime) -> tuple[dict, list[dict]]:
    name, url, domain = source
    request = Request(url, headers={
        "User-Agent": "ThreadStyle/1.0 (+https://github.com/ArunMandava3030/Thread_Outfit_Wardrobe_stylists)",
        "Accept": "application/rss+xml, application/xml, text/xml",
    })
    with urlopen(request, timeout=25) as response:
        raw = response.read(MAX_BYTES + 1)
    return ({"name": name, "url": url, "fetchedAt": iso(now), "status": "ok"},
            parse_feed(raw, name, domain, now))


def collect(now: datetime, previous: dict | None = None, fetcher=fetch_source) -> dict:
    previous = previous or {}
    sources, items, successes = [], [], 0
    with ThreadPoolExecutor(max_workers=len(FEEDS)) as pool:
        pending = [(source, pool.submit(fetcher, source, now)) for source in FEEDS]
        for source, future in pending:
            name, url, domain = source
            try:
                metadata, entries = future.result()
                sources.append(metadata)
                items.extend(entries)
                successes += 1
            except Exception as error:
                print(f"Warning: {name} could not refresh ({type(error).__name__}).", file=sys.stderr)
                old_sources = previous.get("sources", [])
                old = next((s for s in old_sources if isinstance(s, dict) and s.get("name") == name), {})
                sources.append({"name": name, "url": url, "fetchedAt": old.get("fetchedAt"), "status": "error"})
                for item in previous.get("items", []):
                    try:
                        date = parse_date(item["publishedAt"])
                        if (item["publisher"] == name and isinstance(item["headline"], str)
                                and 0 < len(item["headline"]) <= 160
                                and clean_url(item["url"], domain)
                                and timedelta(0) <= now - date <= MAX_AGE):
                            items.append(item)
                    except (ValueError, TypeError, KeyError, OverflowError):
                        continue
    if not successes:
        raise RuntimeError("All RSS sources failed; the last successful feed is unchanged.")
    unique = {entry["url"]: entry for entry in items}
    ordered = sorted(unique.values(), key=lambda entry: entry["publishedAt"], reverse=True)
    if not ordered:
        raise RuntimeError("No eligible recent headlines; the last successful feed is unchanged.")
    # Cap each publisher so the feed includes independent sources when available.
    selected, counts = [], {}
    for entry in ordered:
        publisher = entry["publisher"]
        if counts.get(publisher, 0) < 6:
            selected.append(entry)
            counts[publisher] = counts.get(publisher, 0) + 1
    return {"schemaVersion": 1, "fetchedAt": iso(now), "sources": sources, "items": selected[:18]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("web/data/trends.json"))
    options = parser.parse_args()
    previous = {}
    if options.output.exists():
        try:
            previous = json.loads(options.output.read_text(encoding="utf-8"))
            if not isinstance(previous, dict):
                previous = {}
        except (OSError, ValueError):
            pass
    try:
        result = collect(datetime.now(timezone.utc), previous)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    options.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = options.output.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(options.output)
    print(f"Saved {len(result['items'])} sourced headlines to {options.output}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
