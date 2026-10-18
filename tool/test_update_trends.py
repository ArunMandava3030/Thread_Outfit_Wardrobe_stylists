"""Offline behavioral checks for the RSS metadata publishing pipeline."""
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from update_trends import collect, parse_feed


NOW = datetime(2026, 10, 18, 12, tzinfo=timezone.utc)


def rss(*items):
    return ("<rss><channel>" + "".join(items) + "</channel></rss>").encode()


def item(title="New denim shirts", date="Fri, 16 Oct 2026 18:00:00 +0000",
         url="https://www.gq.com/story/new-denim", category="Style"):
    return f"<item><title>{title}</title><pubDate>{date}</pubDate><link>{url}</link><category>{category}</category><description>Must not be copied</description></item>"


class TrendsTest(unittest.TestCase):
    def test_extracts_only_metadata_and_rejects_unrelated_grooming(self):
        entries = parse_feed(rss(item(), item("New haircuts", category="Grooming")), "GQ", "gq.com", NOW)
        self.assertEqual(len(entries), 1)
        self.assertEqual(set(entries[0]), {"headline", "url", "publisher", "publishedAt"})
        self.assertEqual(entries[0]["publishedAt"], "2026-10-16T18:00:00Z")

    def test_rejects_future_old_missing_and_impossible_dates(self):
        dates = ["Wed, 20 Oct 2027 12:00:00 +0000", "Sun, 01 Feb 2026 12:00:00 +0000",
                 "2026-02-31T10:00:00Z", "", "not a date", "2026-10-16T10:00:00"]
        self.assertEqual(parse_feed(rss(*(item(date=date) for date in dates)), "GQ", "gq.com", NOW), [])

    def test_rejects_untrusted_urls_xml_and_overlong_titles(self):
        for url in ("https://gq.com.evil.example/story/a", "http://www.gq.com/story/a", "https://me@www.gq.com/story/a"):
            self.assertEqual(parse_feed(rss(item(url=url)), "GQ", "gq.com", NOW), [])
        for raw in (b"<html/>", b"<!DOCTYPE rss><rss><channel/></rss>", b"bad xml"):
            with self.assertRaises(Exception):
                parse_feed(raw, "GQ", "gq.com", NOW)
        entry = parse_feed(rss(item(title="Denim " * 40)), "GQ", "gq.com", NOW)[0]
        self.assertLessEqual(len(entry["headline"]), 160)

    def test_partial_failure_preserves_eligible_previous_source(self):
        previous_item = {"headline": "New denim shirts", "url": "https://www.gq.com/story/old",
                         "publisher": "GQ", "publishedAt": "2026-10-15T12:00:00Z"}
        def fetcher(source, now):
            name, url, _ = source
            if name == "GQ":
                raise OSError("offline")
            entries = [{"headline": "New suit shapes", "url": "https://www.esquire.com/style/mens-fashion/suits",
                        "publisher": "Esquire", "publishedAt": "2026-10-16T12:00:00Z"}] if name == "Esquire" else []
            return {"name": name, "url": url, "fetchedAt": "2026-10-18T12:00:00Z", "status": "ok"}, entries
        result = collect(NOW, {"items": [previous_item]}, fetcher=fetcher)
        self.assertEqual([entry["publisher"] for entry in result["items"]], ["Esquire", "GQ"])
        self.assertEqual(result["sources"][0]["status"], "error")

    def test_total_failure_and_no_eligible_content_fail_before_write(self):
        def failure(*_):
            raise OSError("offline")
        def empty(source, _):
            return {"name": source[0], "url": source[1], "status": "ok"}, []
        for fetcher in (failure, empty):
            with self.assertRaises(RuntimeError):
                collect(NOW, fetcher=fetcher)


if __name__ == "__main__":
    unittest.main()
