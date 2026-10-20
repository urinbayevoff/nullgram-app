#!/usr/bin/env python3
"""Fetch Tepegram's pure-Python libraries from PyPI into vendor/.

They are installed on the phone next to the app (tools/deploy.sh) and
compiled there once, rather than bundled into the app's binary: the
binary's zip cannot hold bytecode, and Telethon's generated TL classes are
several megabytes of Python to compile at every start.

Pinned versions, checked against PyPI's sha256. pyaes ships only as an
sdist, so its package directory is taken out of the tarball.
"""
import hashlib
import io
import json
import os
import shutil
import sys
import tarfile
import urllib.request
import zipfile

PINS = {
	"telethon": "1.45.0",	# MIT
	"rsa": "4.9.1",		# Apache-2.0
	"pyasn1": "0.6.4",	# BSD-2-Clause
	"qrcode": "8.2",	# BSD
	"pyaes": "1.6.1",	# MIT
}
PACKAGES = {"telethon": ["telethon"], "rsa": ["rsa"], "pyasn1": ["pyasn1"], "qrcode": ["qrcode"], "pyaes": ["pyaes"]}

HERE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
OUT = os.path.join(HERE, "vendor")


def fetch(name, version):
	meta = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/{name}/{version}/json"))
	files = meta["urls"]
	pick = next((f for f in files if f["filename"].endswith("-py3-none-any.whl")), None) or \
		next(f for f in files if f["packagetype"] == "sdist")
	data = urllib.request.urlopen(pick["url"]).read()
	if hashlib.sha256(data).hexdigest() != pick["digests"]["sha256"]:
		sys.exit(f"{pick['filename']}: sha256 does not match PyPI")
	return pick["filename"], data


def extract(name, filename, data):
	wanted = PACKAGES[name]
	licenses = os.path.join(OUT, "LICENSES")
	if filename.endswith(".whl"):
		with zipfile.ZipFile(io.BytesIO(data)) as z:
			for member in z.namelist():
				top = member.split("/")[0]
				if top in wanted:
					z.extract(member, OUT)
				elif top.endswith(".dist-info") and "/licenses/" in member.lower() or member.lower().endswith(("license", "license.txt", "license.md", "license.rst")):
					with open(os.path.join(licenses, f"{name}-{os.path.basename(member)}"), "wb") as f:
						f.write(z.read(member))
	else:
		with tarfile.open(fileobj=io.BytesIO(data)) as t:
			for member in t.getmembers():
				parts = member.name.split("/")
				if len(parts) > 1 and parts[1] in wanted and member.isfile():
					member.name = "/".join(parts[1:])
					t.extract(member, OUT, filter="data")
				elif len(parts) == 2 and parts[1].lower().startswith("license") and member.isfile():
					with open(os.path.join(licenses, f"{name}-{parts[1]}"), "wb") as f:
						f.write(t.extractfile(member).read())


if __name__ == "__main__":
	shutil.rmtree(OUT, ignore_errors=True)
	os.makedirs(os.path.join(OUT, "LICENSES"))
	for name, version in PINS.items():
		filename, data = fetch(name, version)
		extract(name, filename, data)
		print(filename)
	with open(os.path.join(OUT, "VERSIONS"), "w") as f:
		f.write("".join(f"{n}=={v}\n" for n, v in PINS.items()))
