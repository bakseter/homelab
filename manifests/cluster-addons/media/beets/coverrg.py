"""coverrg: canonical, high-quality album art for a Jellyfin library.

Cover Art Archive attaches art to a specific release, so art for a 50th
anniversary remaster is the anniversary sleeve. The MusicBrainz release
group has a designated representative image, which is the original album
cover -- but MusicBrainz ranks "representative" above "high quality", so
that image is sometimes a faded scan of a physical sleeve.

This plugin therefore treats the release group as the authority on *which*
artwork is correct, and iTunes as a source of a clean copy of it. iTunes
serves the label-supplied digital master rather than a user scan, so it is
used when the CAA image is missing or too small.

Quality is judged on pixel dimensions via Pillow, not file size: file size
tracks visual complexity as much as resolution, so a flat 1200x1200 digital
cover can weigh less than a busy 600x600 scan.

Requests to the Cover Art Archive are retried on 5xx and timeouts, since
they are served by the Internet Archive and fail transiently.

Multi-disc aware: writes into every directory the album's tracks live in,
plus their common parent.

Enable with:

    pluginpath: /config/plugins
    plugins: musicbrainz mbsync coverrg

    coverrg:
      sources: [release-group, itunes]
      filenames: [folder.jpg, cover.jpg]
      variants: [front-1200, front]
      min_pixels: 1000         # min width AND height to accept a source
      itunes_size: 1200
      itunes_min_ratio: 0.6
      retries: 3
      parent_dir: yes
      delay: 1.0
      timeout: 30

Usage:

    beet coverrg                      # albums missing art
    beet coverrg -f "album:Yeezus"    # overwrite, one album
    beet coverrg -p                   # dry run
    beet coverrg -f -s itunes         # force one source
"""

import difflib
import io
import os
import re
import time

import requests

from beets import ui
from beets.plugins import BeetsPlugin

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

CAA_RG = "https://coverartarchive.org/release-group"
ITUNES_SEARCH = "https://itunes.apple.com/search"

# artworkUrl100 looks like .../source/100x100bb.jpg -- the size segment is
# rewritable to larger values.
ITUNES_SIZE_RE = re.compile(r"/\d+x\d+bb\.(jpg|png)$")

RETRY_STATUS = (500, 502, 503, 504, 429)


class CoverRGPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.config.add(
            {
                # Tried in order. A source wins when its image is at least
                # min_pixels on both axes; otherwise the next is tried and
                # the largest image seen is used as a fallback.
                "sources": ["release-group", "itunes"],
                # Jellyfin checks folder.* before cover.*.
                "filenames": ["folder.jpg", "cover.jpg"],
                "variants": ["front-1200", "front"],
                "min_pixels": 1000,
                "itunes_size": 1200,
                "itunes_country": "us",
                # Reject an iTunes hit whose album title is less similar
                # than this to the tagged one (0..1).
                "itunes_min_ratio": 0.6,
                # Retries for transient Internet Archive failures.
                "retries": 3,
                "retry_backoff": 2.0,
                "parent_dir": True,
                "delay": 1.0,
                "timeout": 30,
                "auto": False,
            }
        )
        if self.config["auto"].get(bool):
            self.import_stages = [self._import_stage]
        if Image is None:
            self._log.warning(
                "Pillow not installed; falling back to file size for quality"
            )

    # ---- command ---------------------------------------------------------

    def commands(self):
        cmd = ui.Subcommand(
            "coverrg",
            help="fetch canonical album art into album directories",
        )
        cmd.parser.add_option(
            "-f", "--force", action="store_true", default=False,
            help="overwrite art that already exists",
        )
        cmd.parser.add_option(
            "-p", "--pretend", action="store_true", default=False,
            help="report what would happen, write nothing",
        )
        cmd.parser.add_option(
            "-s", "--source", action="append", dest="sources", default=None,
            help="use only this source (repeatable): release-group, itunes",
        )
        cmd.func = self._run
        return [cmd]

    def _run(self, lib, opts, args):
        stats = {"written": 0, "skipped": 0, "no_art": 0, "failed": 0}
        delay = self.config["delay"].as_number()
        sources = opts.sources or self.config["sources"].as_str_seq()

        for album in lib.albums(ui.decargs(args)):
            result = self._handle(album, opts.force, opts.pretend, sources)
            stats[result] += 1
            if result in ("written", "no_art", "failed"):
                time.sleep(delay)

        self._log.info(
            "written={} skipped={} no_art={} failed={}",
            stats["written"], stats["skipped"],
            stats["no_art"], stats["failed"],
        )

    def _import_stage(self, session, task):
        if task.is_album and task.album:
            self._handle(
                task.album, False, False, self.config["sources"].as_str_seq()
            )

    # ---- http ------------------------------------------------------------

    def _headers(self):
        return {"User-Agent": "beets-coverrg/2.1 (self-hosted jellyfin)"}

    def _get(self, url, label, what, params=None, retry=True):
        """GET with retries on transient failures.

        Returns the response, or None when it failed for good. A 404 is
        returned as-is; it is a legitimate "not here" answer.
        """
        timeout = self.config["timeout"].as_number()
        attempts = self.config["retries"].get(int) if retry else 1
        backoff = self.config["retry_backoff"].as_number()

        for attempt in range(1, attempts + 1):
            try:
                resp = requests.get(url, params=params,
                                    headers=self._headers(), timeout=timeout)
            except (requests.Timeout, requests.ConnectionError) as exc:
                if attempt < attempts:
                    wait = backoff * attempt
                    self._log.debug(
                        "{}: {} attempt {}/{} failed ({}); retrying in {}s",
                        label, what, attempt, attempts, exc, wait,
                    )
                    time.sleep(wait)
                    continue
                self._log.warning("{} request failed: {}: {}",
                                  what, label, exc)
                return None
            except requests.RequestException as exc:
                self._log.warning("{} request failed: {}: {}",
                                  what, label, exc)
                return None

            if resp.status_code in RETRY_STATUS and attempt < attempts:
                wait = backoff * attempt
                self._log.debug(
                    "{}: {} http {} (attempt {}/{}); retrying in {}s",
                    label, what, resp.status_code, attempt, attempts, wait,
                )
                time.sleep(wait)
                continue

            return resp

        return None

    # ---- quality ---------------------------------------------------------

    def _dimensions(self, data):
        if Image is None or not data:
            return None
        try:
            with Image.open(io.BytesIO(data)) as im:
                return im.size
        except Exception as exc:  # noqa: BLE001 - any decode failure
            self._log.debug("cannot read image dimensions: {}", exc)
            return None

    def _score(self, data):
        """Comparable quality score, and a human-readable description."""
        dims = self._dimensions(data)
        if dims:
            w, h = dims
            return min(w, h), f"{w}x{h}"
        # No Pillow, or an undecodable image: fall back to bytes. Scale it
        # down so it never outranks a real pixel measurement.
        return len(data) / 10000.0, f"{len(data) // 1024} KB"

    def _acceptable(self, data):
        floor = self.config["min_pixels"].get(int)
        dims = self._dimensions(data)
        if dims is None:
            # Cannot measure; accept only if it is at least plausibly big.
            return len(data) >= 200000
        return dims[0] >= floor and dims[1] >= floor

    # ---- directories -----------------------------------------------------

    @staticmethod
    def _decode(path):
        if isinstance(path, bytes):
            return path.decode("utf-8", "surrogateescape")
        return path

    def _target_dirs(self, album):
        dirs = []
        for item in album.items():
            d = os.path.dirname(self._decode(item.path))
            if d and d not in dirs:
                dirs.append(d)

        if not dirs:
            return []

        if len(dirs) > 1 and self.config["parent_dir"].get(bool):
            parent = os.path.commonpath(dirs)
            # Only when it is a direct parent of every disc dir, so a stray
            # item cannot resolve the common path up to the library root.
            if parent and all(os.path.dirname(d) == parent for d in dirs):
                dirs.append(parent)

        return dirs

    # ---- worker ----------------------------------------------------------

    def _handle(self, album, force, pretend, sources):
        label = f"{album.albumartist} - {album.album}"

        try:
            dirs = self._target_dirs(album)
        except (AttributeError, TypeError, ValueError) as exc:
            self._log.warning("cannot resolve directories: {}: {}", label, exc)
            return "failed"

        if not dirs:
            self._log.info("no directory: {}", label)
            return "failed"

        filenames = self.config["filenames"].as_str_seq()
        targets = [os.path.join(d, n) for d in dirs for n in filenames]
        pending = [t for t in targets if force or not os.path.exists(t)]

        if not pending:
            self._log.debug("art present in all {} location(s): {}",
                            len(dirs), label)
            return "skipped"

        data, origin, desc = self._best(album, label, sources)
        if data is None:
            return "no_art"

        if pretend:
            for t in pending:
                self._log.info("would write {} from {}: {}", desc, origin, t)
            return "written"

        wrote = sum(1 for dest in pending if self._write(dest, data, label))
        if not wrote:
            return "failed"

        self._log.info(
            "ok ({} from {}, {} file(s) across {} dir(s)): {}",
            desc, origin, wrote, len(dirs), label,
        )
        return "written"

    def _best(self, album, label, sources):
        """Try each source in order; return the first acceptable image,
        else the highest-scoring image any source returned."""
        best = (None, None, None, -1.0)

        for name in sources:
            if name == "release-group":
                data = self._from_caa(album, label)
            elif name == "itunes":
                data = self._from_itunes(album, label)
            else:
                self._log.warning("unknown source: {}", name)
                continue

            if not data:
                continue

            score, desc = self._score(data)
            if self._acceptable(data):
                return data, name, desc

            self._log.debug("{}: {} gave {}, below floor", label, name, desc)
            if score > best[3]:
                best = (data, name, desc, score)

        if best[0] is not None:
            self._log.debug("{}: no source cleared the floor, using {} ({})",
                            label, best[1], best[2])
            return best[0], best[1], best[2]

        self._log.info("no art: {}", label)
        return None, None, None

    # ---- sources ---------------------------------------------------------

    def _from_caa(self, album, label):
        rgid = album.mb_releasegroupid
        if not rgid:
            self._log.debug("no release-group id: {}", label)
            return None

        for variant in self.config["variants"].as_str_seq():
            resp = self._get(f"{CAA_RG}/{rgid}/{variant}", label, "caa")
            if resp is None:
                return None
            if resp.status_code == 200 and resp.content:
                return resp.content
            if resp.status_code == 404:
                continue
            self._log.warning("caa http {}: {}", resp.status_code, label)
            return None
        return None

    def _from_itunes(self, album, label):
        artist = album.albumartist or ""
        title = album.album or ""
        if not title:
            return None

        params = {
            "term": f"{artist} {title}".strip(),
            "entity": "album",
            "media": "music",
            "limit": 5,
            "country": self.config["itunes_country"].as_str(),
        }
        resp = self._get(ITUNES_SEARCH, label, "itunes", params=params)
        if resp is None or resp.status_code != 200:
            if resp is not None:
                self._log.warning("itunes http {}: {}",
                                  resp.status_code, label)
            return None

        try:
            results = resp.json().get("results", [])
        except ValueError as exc:
            self._log.warning("itunes bad json: {}: {}", label, exc)
            return None

        hit = self._match(results, artist, title, label)
        if hit is None:
            return None

        art = hit.get("artworkUrl100") or hit.get("artworkUrl60")
        if not art:
            return None

        size = self.config["itunes_size"].get(int)
        big = ITUNES_SIZE_RE.sub(rf"/{size}x{size}bb.jpg", art)

        img = self._get(big, label, "itunes image")
        if img is not None and img.status_code == 200 and img.content:
            return img.content

        # Requested size may not exist; fall back to what was given.
        img = self._get(art, label, "itunes image", retry=False)
        if img is not None and img.status_code == 200 and img.content:
            return img.content
        return None

    def _match(self, results, artist, title, label):
        """iTunes matches on text, not MBID, so guard against grabbing a
        tribute album or a greatest-hits variant."""
        floor = self.config["itunes_min_ratio"].as_number()
        want = self._norm(title)
        best, best_ratio = None, 0.0

        for r in results:
            got = self._norm(r.get("collectionName", ""))
            ratio = difflib.SequenceMatcher(None, want, got).ratio()
            if artist:
                a_ratio = difflib.SequenceMatcher(
                    None, self._norm(artist),
                    self._norm(r.get("artistName", "")),
                ).ratio()
                ratio = (ratio * 2 + a_ratio) / 3
            if ratio > best_ratio:
                best, best_ratio = r, ratio

        if best is None or best_ratio < floor:
            self._log.debug("itunes: no confident match for {} (best {:.2f})",
                            label, best_ratio)
            return None
        return best

    @staticmethod
    def _norm(s):
        s = (s or "").lower()
        s = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", s)
        s = re.sub(r"[^a-z0-9]+", " ", s)
        return " ".join(s.split())

    # ---- writing ---------------------------------------------------------

    def _write(self, dest, data, label):
        tmp = dest + ".tmp"
        try:
            with open(tmp, "wb") as fh:
                fh.write(data)
            os.replace(tmp, dest)
        except OSError as exc:
            self._log.warning("write failed: {}: {}: {}", label, dest, exc)
            if os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            return False
        return True
