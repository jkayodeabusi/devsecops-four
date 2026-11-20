#!/usr/bin/env python3
"""
pin-digests.py  (DSO-01)

Finds every container image written as name:tag in the repo's pipeline,
Dockerfile and pod files, asks the registry for that tag's current digest,
and rewrites it as name:tag@sha256:<digest>. The tag stays for humans; the
digest is what actually gets pulled, so nobody can swap the image under you.

    python3 scripts/pin-digests.py            # rewrite files in place
    python3 scripts/pin-digests.py --check    # exit 1 if anything is unpinned (CI use)

Needs one of: `docker buildx imagetools` or `crane` on the PATH.
"""
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

FILES = [
    "app-classic/Dockerfile",
    "tools/cloud-cli/Dockerfile",
    ".gitlab-ci.yml",
    ".github/workflows/devsecops-classic.yml",
    "jenkins/pod-templates/devsecops.yaml",
    "platform-repos/ado-pipeline-templates/templates/secure-pipeline.yml",
    "platform-repos/gitlab-security-policies/pipeline/enforced-security.yml",
]

# Where an image reference can appear in these files.
KEYED = re.compile(
    r"(?P<lead>(?:^\s*FROM\s+|^\s*-?\s*image:\s+|^\s*name:\s+|^\s*value:\s+|_IMAGE:\s+))"
    r"(?P<ref>[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+)(?![@\w.-])",
    re.MULTILINE,
)
# Images named inline in shell commands, e.g. `docker run ghcr.io/zaproxy/zaproxy:stable`.
INLINE = re.compile(
    r"(?P<lead>(?<![\w/.-]))(?P<ref>(?:ghcr\.io|gcr\.io|quay\.io|docker\.io)/[a-z0-9._/-]+:[A-Za-z0-9._-]+)(?![@\w.-])"
)
# Images these pipelines build themselves are deployed by digest already.
SKIP_PREFIXES = ("contosodevsecops.azurecr.io/",)


def digest_of(ref: str) -> str:
    if shutil.which("crane"):
        out = subprocess.run(["crane", "digest", ref], check=True, capture_output=True, text=True)
        return out.stdout.strip()
    if shutil.which("docker"):
        has_buildx = subprocess.run(["docker", "buildx", "version"], capture_output=True).returncode == 0
        if has_buildx:
            out = subprocess.run(
                ["docker", "buildx", "imagetools", "inspect", ref, "--format", "{{json .Manifest.Digest}}"],
                check=True, capture_output=True, text=True)
            return out.stdout.strip().strip('"')
        # No buildx: pull the image, then read the registry digest Docker recorded.
        subprocess.run(["docker", "pull", "-q", ref], check=True, capture_output=True, text=True)
        out = subprocess.run(
            ["docker", "image", "inspect", ref, "--format", "{{index .RepoDigests 0}}"],
            check=True, capture_output=True, text=True)
        return out.stdout.strip().split("@", 1)[1]
    sys.exit("pin-digests: install crane or docker first")


def main() -> int:
    check_only = "--check" in sys.argv
    cache: dict[str, str] = {}
    unpinned = []
    for rel in FILES:
        path = ROOT / rel
        if not path.exists():
            continue
        text = path.read_text()

        def repl(m: re.Match) -> str:
            ref = m.group("ref")
            if ref.startswith(SKIP_PREFIXES):
                return m.group(0)
            if f"{rel}: {ref}" not in unpinned:
                unpinned.append(f"{rel}: {ref}")
            if check_only:
                return m.group(0)
            if ref not in cache:
                try:
                    cache[ref] = digest_of(ref)
                    print(f"  {ref} -> {cache[ref]}")
                except subprocess.CalledProcessError as err:
                    cache[ref] = ""
                    print(f"  WARNING: cannot resolve {ref} ({err.stderr.strip()[:120]}); left unpinned")
            if not cache[ref]:
                return m.group(0)
            return f"{m.group('lead')}{ref}@{cache[ref]}"

        new = INLINE.sub(repl, KEYED.sub(repl, text))
        if new != text and not check_only:
            path.write_text(new)
            print(f"pinned: {rel}")

    if check_only:
        for u in unpinned:
            print(f"unpinned: {u}")
        return 1 if unpinned else 0
    print(f"done: {sum(1 for d in cache.values() if d)} of {len(cache)} images pinned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
