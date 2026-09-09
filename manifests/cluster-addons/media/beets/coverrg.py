"""coverrg: canonical, high-quality album art for a Jellyfin library.

Cover Art Archive attaches art to a specific release, so art for a 50th
anniversary remaster is the anniversary sleeve. The MusicBrainz release
group has a designated representative image, which is the original album
cover -- but MusicBrainz ranks "representative" above "high quality", so
that image is sometimes a faded scan of a physical sleeve.

This plugin therefore treats the release group as the authority on *which*
artwork is correct, and iTunes as a source of a clean copy of it. iTunes
serves the label-supplied digital master rather than a user scan, so it is
used when the CAA image is missing or below a size threshold.

Multi-disc aware: writes into every directory the album's tracks live in,
plus their common parent.

Enable with:

    pluginpath: /config/plugins
    plugins: musicbrainz mbsync coverrg

    coverrg:
      sources: [release-group, itunes]
      filenames: [folder.jpg, cover.jpg]
      variants: [front-1200, front]
      min_bytes: 500000        # below this, try the next source
      itunes_size: 1200
      itunes_min_ratio: 0.6    # title similarity guard
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
import os
import re
import time

import requests

from beets import ui
from beets.plugins import BeetsPlugin

CAA_RG = "https://coverartarchive.org/release-group"
ITUNES_SEARCH = "https://itunes.apple.com/search"

# artworkUrl100 looks like .../source/100x100bb.jpg -- the size segment is
# rewritable to larger values.
ITUNES_SIZE_RE = re.compile(r"/\d+x\d+bb\.(jpg|png)$")


class CoverRGPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.config.add(
            {
                # Tried in order. A source is used when it returns an image
                # of at least min_bytes; otherwise the next one is tried.
                # The best image seen wins if none clears the threshold.
                "sources": ["release-group", "itunes"],
                # Jellyfin checks folder.* before cover.*.
                "filenames": ["folder.jpg", "cover.jpg"],
                "variants": ["front-1200", "front"],
                "min_bytes": 500000,
                "itunes_size": 1200,
                "itunes_country": "us",
                # Reject an iTunes hit whose album title is less similar
                # than this to the tagged one (0..1).
                "itunes_min_ratio": 0.6,
                "parent_dir": True,
                "delay": 1.0,
                "timeout": 30,
                "auto": False,
            }
        )
        if self.config["auto"].get(bool):
            self.import_stages = [self._import_stage]

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

        data, origin = self._best(album, label, sources)
        if data is None:
            return "no_art"

        if pretend:
            for t in pending:
                self._log.info("would write {} bytes from {}: {}",
                               len(data), origin, t)
            return "written"

        wrote = sum(1 for dest in pending if self._write(dest, data, label))
        if not wrote:
            return "failed"

        self._log.info(
            "ok ({} KB from {}, {} file(s) across {} dir(s)): {}",
            len(data) // 1024, origin, wrote, len(dirs), label,
        )
        return "written"

    def _best(self, album, label, sources):
        """Try each source in order; return the first image clearing
        min_bytes, else the largest image any source returned."""
        floor = self.config["min_bytes"].get(int)
        best = (None, None)

        for name in sources:
            if name == "release-group":
                data = self._from_caa(album, label)
            elif name == "itunes":
                data = self._from_itunes(album, label)
            else:
                self._log.warning("unknown source: {}", name)
                continue

            if data is None:
                continue
            if len(data) >= floor:
                return data, name
            self._log.debug("{}: {} only {} KB, below floor",
                            label, name, len(data) // 1024)
            if best[0] is None or len(data) > len(best[0]):
                best = (data, name)

        if best[0] is not None:
            self._log.debug("{}: falling back to best available ({})",
                            label, best[1])
            return best

        self._log.info("no art: {}", label)
        return None, None

    # ---- sources ---------------------------------------------------------

    def _headers(self):
        return {"User-Agent": "beets-coverrg/2.0 (self-hosted jellyfin)"}

    def _from_caa(self, album, label):
        rgid = album.mb_releasegroupid
        if not rgid:
            self._log.debug("no release-group id: {}", label)
            return None

        timeout = self.config["timeout"].as_number()
        for variant in self.config["variants"].as_str_seq():
            url = f"{CAA_RG}/{rgid}/{variant}"
            try:
                resp = requests.get(url, headers=self._headers(),
                                    timeout=timeout)
            except requests.RequestException as exc:
                self._log.warning("caa request failed: {}: {}", label, exc)
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

        timeout = self.config["timeout"].as_number()
        params = {
            "term": f"{artist} {title}".strip(),
            "entity": "album",
            "media": "music",
            "limit": 5,
            "country": self.config["itunes_country"].as_str(),
        }
        try:
            resp = requests.get(ITUNES_SEARCH, params=params,
                                headers=self._headers(), timeout=timeout)
            resp.raise_for_status()
            results = resp.json().get("results", [])
        except (requests.RequestException, ValueError) as exc:
            self._log.warning("itunes request failed: {}: {}", label, exc)
            return None

        hit = self._match(results, artist, title, label)
        if hit is None:
            return None

        art = hit.get("artworkUrl100") or hit.get("artworkUrl60")
        if not art:
            return None

        size = self.config["itunes_size"].get(int)
        big = ITUNES_SIZE_RE.sub(rf"/{size}x{size}bb.jpg", art)

        try:
            img = requests.get(big, headers=self._headers(), timeout=timeout)
            if img.status_code != 200 or not img.content:
                # Requested size may not exist; fall back to what was given.
                img = requests.get(art, headers=self._headers(),
                                   timeout=timeout)
            if img.status_code == 200 and img.content:
                return img.content
        except requests.RequestException as exc:
            self._log.warning("itunes image failed: {}: {}", label, exc)
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
