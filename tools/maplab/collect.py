#!/usr/bin/env python3
"""One-time, Python-standard-library-only map input collection on the gaming PC.

py -3 tools/maplab/collect.py --wow "C:\\Games\\World of Warcraft" --output map-art.zip

Reads local Forever CASC only; never opens WTF/account files, modifies the client,
contacts a CDN, decrypts files, or installs dependencies. No Pillow/Lua needed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

from clientdata import ClientInputError, REPO, candidate_ids, minimap, model, read_tables, scenarios
import casc
import db2

PART_BYTES = 24 * 1024 * 1024
MAX_BYTES = 128 * 1024 * 1024


def installation(selected, requested_product=None):
    """Accept a client subfolder; select only a product actually listed locally."""
    selected = selected.resolve()
    root = next((path for path in (selected, *list(selected.parents)[:2])
                 if (path / ".build.info").is_file() and (path / "Data/data").is_dir()), None)
    if root is None:
        raise ClientInputError("No .build.info and Data/data found in the selected folder or its two nearest parents")
    rows = [row for row in casc.builds(root) if row.get("Product")]
    products = sorted({row["Product"] for row in rows})
    if requested_product:
        if requested_product not in products:
            raise ClientInputError("Requested product is not installed. Available products: " + ", ".join(products))
        return root, requested_product
    # Folder spelling is a hint only: a matching product must exist in metadata.
    hint = selected.name.strip("_").lower()
    hinted = {p for p in products if p.lower().removeprefix("wow_") == hint}
    named = {p for p in products if "forever" in p.lower()}
    versioned = {row["Product"] for row in rows if row.get("Version", "").startswith("1.60.")}
    active = {row["Product"] for row in rows if row.get("Active") == "1"}
    choices = set(products)
    for candidates in (hinted, named, versioned, active):
        narrower = choices & candidates
        if narrower:
            choices = narrower
        if len(choices) == 1:
            return root, next(iter(choices))
    raise ClientInputError(("Multiple products found: " + ", ".join(sorted(choices)) if choices else "No products found in .build.info") +
                           ". Run again with --product followed by the desired listed product")


def make_kit(output):
    """Small source-only handoff, no game install or extracted artwork included."""
    names = ["tools/maplab/collect.py", "tools/maplab/clientdata.py", "tools/maplab/Collect-Map-Art.cmd",
             "tools/navbake/casc.py", "tools/navbake/db2.py", "tools/navbake/wowfiles.py",
             "!!!TwichUI/map/Data.lua", "!!!TwichUI/map/LocalData.lua", "!!!TwichUI/LICENSES/OpenMap.txt", "LICENSE"]
    output = output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(REPO / name, name)
        archive.write(REPO / "tools/maplab/Collect-Map-Art.cmd", "Collect-Map-Art.cmd")
        archive.writestr("READ-ME.txt", """TwichUI private map-art collector

1. Extract this source kit on the gaming PC. Python 3.10+ is required; no
   Pillow, Lua, third-party packages, client modifications or login is needed.
2. Double-click Collect-Map-Art.cmd and choose _forever_ or the installation ROOT.
   The collector checks nearby parents for .build.info and Data. Or run:
   py -3 tools/maplab/collect.py --wow "D:\\Games\\World of Warcraft"
3. Return only TwichUI-map-art.zip (or every numbered TwichUI-map-art-XX.zip)
   from this extracted kit folder to the existing private Codex conversation.

The collector reads local Forever CASC only. It never opens account/WTF files,
writes to the installation, contacts a CDN, decrypts files, or uploads anything.
ZIP parts stay below 24 MiB. Output includes only map metadata and referenced
texture candidates around Booty Bay, Undercity and an Elwynn/Westfall border.
If Python is absent, install it from python.org; no automatic download occurs.
The installed product is selected from .build.info, not a hardcoded beta name.
If several products remain ambiguous, the error lists valid --product choices.
Unknown schemas or conflicting map assignments stop instead of guessing.
These private game-art ZIPs must not be committed or published. The source kit
itself contains no extracted game artwork. Client extraction remains unverified
until run on an actual installation. Keep any error message if collection fails.
""")
    return output


def pack(folder, destination):
    """Independent ZIP parts, each below the chat's 32 MiB input limit."""
    members = [folder / "client.json", folder / "assets/manifest.json", *sorted((folder / "assets").glob("*.blp"))]
    files, archive, current = [], None, None
    try:
        for source in members:
            size = source.stat().st_size
            if archive is None or archive.fp.tell() + size + (len(archive.filelist) + 1) * 128 + 8192 >= PART_BYTES:
                if archive:
                    archive.close()
                current = folder / f"part-{len(files) + 1:02}.zip"
                archive = zipfile.ZipFile(current, "w", compression=zipfile.ZIP_DEFLATED)
                files.append(current)
            archive.write(source, source.relative_to(folder).as_posix())
        archive.close(); archive = None
        targets = [destination if len(files) == 1 else destination.with_name(f"{destination.stem}-{i:02}.zip")
                   for i in range(1, len(files) + 1)]
        if any(p.exists() for p in targets):
            raise ClientInputError("Output already exists; choose a different output name")
        destination.parent.mkdir(parents=True, exist_ok=True)
        for source, target in zip(files, targets):
            if source.stat().st_size >= PART_BYTES:
                raise ClientInputError("An output ZIP exceeded the transfer budget")
            with source.open("rb") as src, target.open("xb") as dst:
                shutil.copyfileobj(src, dst)
        return targets
    finally:
        if archive:
            archive.close()


def collect(wow, output, product=None, storage_factory=casc.Storage):
    wow, product = installation(wow, product)
    output = output.resolve()
    if output == wow or output.is_relative_to(wow):
        raise ClientInputError("Output must be outside the game installation")
    if output.suffix.lower() != ".zip":
        raise ClientInputError("Output must end in .zip")
    print(f"Selected installed product: {product}", flush=True)
    storage = storage_factory(str(wow), product=product)
    try:
        tables, sources = read_tables(storage)
        maps, reveal, world_point = model(tables)
        data = dict(schema=1, kind="twichui-maplab-client-input", synthetic=False,
            clientBuild=storage.version, product=product, maps=sorted(maps.values(), key=lambda m: m["id"]),
            minimap=minimap(storage), reveal=reveal, scenarios=scenarios(maps, world_point), tables=sources,
            numericSources={name: hashlib.sha256((REPO / name).read_bytes()).hexdigest()
                            for name in ("!!!TwichUI/map/Data.lua", "!!!TwichUI/map/LocalData.lua")},
            provenance="Local Forever CASC; table-derived API adapter, not native API capture",
            limitations=["Rectangle lookup cannot reproduce native zone shapes, phases or conditional artwork.",
                "Booty Bay locator is production dock 70, Data.lua build 1.60.1.70450; camera is a deterministic preset.",
                "City/WMO picture geometry remains the production pinned numeric data (1.60.1.70245), pending native alignment acceptance.",
                "Private local artwork bundle; no redistribution rights inferred."])
        ids = candidate_ids(data, world_point)
        if len(ids) > 2048:
            raise ClientInputError("Candidate input exceeds 2048 textures; narrow the collector before extracting")
        print(f"Forever {storage.version}: {len(maps)} map records, {len(ids)} candidate textures", flush=True)
        with tempfile.TemporaryDirectory(prefix="twichui-map-art-") as temporary:
            folder = Path(temporary); assets = folder / "assets"; assets.mkdir()
            records, missing, total = {}, [], 0
            for n, file_id in enumerate(ids, 1):
                try:
                    raw = storage.read(file_id)
                    if raw is None:
                        missing.append(dict(fileId=file_id, reason="not stored locally")); continue
                    if len(raw) > 16 * 1024 * 1024 or raw[:4] not in (b"BLP1", b"BLP2", b"DDS "):
                        missing.append(dict(fileId=file_id, reason="unsupported texture header or size")); continue
                    total += len(raw)
                    if total > MAX_BYTES:
                        raise ClientInputError("Artwork input exceeded 128 MiB; no entire-game copy attempted")
                    (assets / f"{file_id}.blp").write_bytes(raw)
                    digest = hashlib.sha256(raw).hexdigest()
                    records[str(file_id)] = dict(file=f"{file_id}.blp", fileId=file_id, sha256=digest,
                        sourceSha256=digest, kind="local-client-artwork", clientBuild=storage.version,
                        provenance=f"Local Forever CASC; {product}; build {storage.version}; file-data ID {file_id}")
                except casc.CascError as error:
                    missing.append(dict(fileId=file_id, reason=str(error)[:160]))
                if n % 100 == 0:
                    print(f"Read {n}/{len(ids)} candidates", flush=True)
            data["candidateTextureIds"] = ids
            (folder / "client.json").write_text(json.dumps(data, sort_keys=True, separators=(",", ":")), encoding="utf-8")
            manifest = dict(schema=1, assets=records, missing=missing, clientBuild=storage.version, product=product,
                            redistribution="Private local debugging input only; do not commit or publish")
            (assets / "manifest.json").write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
            outputs = pack(folder, output)
            print(f"Prepared {len(records)} textures ({total / 1048576:.1f} MiB), {len(missing)} unavailable", flush=True)
            for target in outputs:
                print(f"PRIVATE INPUT: {target} ({target.stat().st_size / 1048576:.1f} MiB)")
            print("Upload only these ZIP files to this chat. No game installation, WTF, SavedVariables or account files are needed.")
            return outputs
    finally:
        storage.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow", type=Path, help="_forever_ or installation root; omitted opens a folder picker")
    parser.add_argument("--output", type=Path, default=Path("TwichUI-map-art.zip"))
    parser.add_argument("--product", help="override automatic selection with an installed .build.info product")
    parser.add_argument("--make-kit", type=Path, help="make a source-only gaming-PC handoff ZIP; no game access")
    args = parser.parse_args()
    try:
        if args.make_kit:
            if args.wow:
                raise ClientInputError("Source-kit creation does not use a game installation")
            print(make_kit(args.make_kit))
            raise SystemExit(0)
        if args.wow is None:
            try:
                import tkinter
                from tkinter import filedialog
                window = tkinter.Tk(); window.withdraw()
                chosen = filedialog.askdirectory(title="Select _forever_ or the WoW installation root (read-only)")
                window.destroy()
            except Exception as error:
                raise ClientInputError("Folder picker unavailable; run again with --wow followed by the installation path") from error
            if not chosen:
                print("Cancelled; no artwork collected.")
                raise SystemExit(0)
            args.wow = Path(chosen)
        collect(args.wow, args.output, args.product)
    except (OSError, ValueError, casc.CascError, db2.DB2Error) as error:
        print(f"maplab collector: {error}", file=sys.stderr)
        raise SystemExit(2)
