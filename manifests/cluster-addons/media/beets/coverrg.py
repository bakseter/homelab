"""coverrg: fetch canonical album art from the MusicBrainz RELEASE GROUP.

Cover Art Archive attaches art to a specific release, so art for a 50th
anniversary remaster is the anniversary sleeve. The release group has a
designated representative image, which is the original album cover. This
plugin fetches that instead and writes it into the album's directories.

Multi-disc aware: writes into every directory the album's tracks live in,
plus their common parent, so Jellyfin finds a primary image regardless of
which level it looks at.

Enable with:

    pluginpath: /config/plugins
    plugins: musicbrainz mbsync coverrg

    coverrg:
      filenames: [folder.jpg, cover.jpg]
      variants: [front-1200, front]
      parent_dir: yes
      delay: 1.0
      timeout: 30

Usage:

    beet coverrg                      # albums missing art
    beet coverrg -f "album:Yeezus"    # overwrite, one album
    beet coverrg -p                   # dry run
"""

import os
import time

import requests

from beets import ui
from beets.plugins import BeetsPlugin

BASE = "https://coverartarchive.org/release-group"


class CoverRGPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.config.add(
            {
                # Jellyfin checks folder.* before cover.*, so folder.jpg
                # wins. Writing both keeps other players happy too.
                "filenames": ["folder.jpg", "cover.jpg"],
                "variants": ["front-1200", "front"],
                # Also write into the album's parent when tracks are split
                # across disc subfolders.
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
            help="fetch release-group cover art into album directories",
        )
        cmd.parser.add_option(
            "-f",
            "--force",
            action="store_true",
            default=False,
            help="overwrite art that already exists",
        )
        cmd.parser.add_option(
            "-p",
            "--pretend",
            action="store_true",
            default=False,
            help="report what would happen, write nothing",
        )
        cmd.func = self._run
        return [cmd]

    def _run(self, lib, opts, args):
        stats = {"written": 0, "skipped": 0, "no_art": 0, "failed": 0}
        delay = self.config["delay"].as_number()

        for album in lib.albums(ui.decargs(args)):
            result = self._handle(album, opts.force, opts.pretend)
            stats[result] += 1
            # Only sleep when we actually hit the network.
            if result in ("written", "no_art", "failed"):
                time.sleep(delay)

        self._log.info(
            "written={} skipped={} no_art={} failed={}",
            stats["written"],
            stats["skipped"],
            stats["no_art"],
            stats["failed"],
        )

    def _import_stage(self, session, task):
        if task.is_album and task.album:
            self._handle(task.album, force=False, pretend=False)

    # ---- directories -----------------------------------------------------

    @staticmethod
    def _decode(path):
        if isinstance(path, bytes):
            return path.decode("utf-8", "surrogateescape")
        return path

    def _target_dirs(self, album):
        """Every directory this album's art should land in.

        For a single-disc album that is one directory. For a multi-disc
        album it is each disc subfolder, plus their common parent when
        `parent_dir` is set and the parent is shared by all of them.
        """
        dirs = []
        for item in album.items():
            d = os.path.dirname(self._decode(item.path))
            if d and d not in dirs:
                dirs.append(d)

        if not dirs:
            return []

        if len(dirs) > 1 and self.config["parent_dir"].get(bool):
            parent = os.path.commonpath(dirs)
            # Guard against a degenerate common path (e.g. the library
            # root) by requiring it to be a direct parent of every dir.
            if parent and all(
                os.path.dirname(d) == parent for d in dirs
            ):
                dirs.append(parent)

        return dirs

    # ---- worker ----------------------------------------------------------

    def _handle(self, album, force, pretend):
        label = f"{album.albumartist} - {album.album}"

        rgid = album.mb_releasegroupid
        if not rgid:
            self._log.info("no release-group id: {}", label)
            return "no_art"

        try:
            dirs = self._target_dirs(album)
        except (AttributeError, TypeError, ValueError) as exc:
            self._log.warning("cannot resolve directories: {}: {}", label, exc)
            return "failed"

        if not dirs:
            self._log.info("no directory: {}", label)
            return "failed"

        filenames = self.config["filenames"].as_str_seq()

        # Every destination that does not already exist.
        targets = [
            os.path.join(d, name) for d in dirs for name in filenames
        ]
        pending = [t for t in targets if force or not os.path.exists(t)]

        if not pending:
            self._log.debug("art present in all {} location(s): {}",
                            len(dirs), label)
            return "skipped"

        data = self._fetch(rgid, label)
        if data is None:
            return "no_art"

        if pretend:
            for t in pending:
                self._log.info("would write {} bytes: {}", len(data), t)
            return "written"

        wrote = 0
        for dest in pending:
            if self._write(dest, data, label):
                wrote += 1

        if not wrote:
            return "failed"

        self._log.info(
            "ok ({} bytes, {} file(s) across {} dir(s)): {}",
            len(data),
            wrote,
            len(dirs),
            label,
        )
        return "written"

    @staticmethod
    def _write_atomic(dest, data):
        tmp = dest + ".tmp"
        try:
            with open(tmp, "wb") as fh:
                fh.write(data)
            os.replace(tmp, dest)
        except OSError:
            if os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            raise

    def _write(self, dest, data, label):
        try:
            self._write_atomic(dest, data)
        except OSError as exc:
            self._log.warning("write failed: {}: {}: {}", label, dest, exc)
            return False
        return True

    def _fetch(self, rgid, label):
        timeout = self.config["timeout"].as_number()
        headers = {"User-Agent": "beets-coverrg/1.1 (self-hosted jellyfin)"}

        for variant in self.config["variants"].as_str_seq():
            url = f"{BASE}/{rgid}/{variant}"
            try:
                resp = requests.get(url, headers=headers, timeout=timeout)
            except requests.RequestException as exc:
                self._log.warning("request failed: {}: {}", label, exc)
                return None

            if resp.status_code == 200 and resp.content:
                return resp.content
            if resp.status_code == 404:
                self._log.debug("{} not available for {}", variant, label)
                continue
            self._log.warning("http {}: {}", resp.status_code, label)
            return None

        self._log.info("no art: {}", label)
        return None
