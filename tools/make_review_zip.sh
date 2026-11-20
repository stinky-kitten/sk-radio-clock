#!/usr/bin/env bash
exec python3 -I - "$@" <<'PY'
import argparse
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile


ZIP_COMMENT = b"make_review_zip.sh working-tree snapshot v1"
REVIEW_ZIP = re.compile(r".+[-_]review[-_]\d{8}[-_]\d{6}\.zip", re.IGNORECASE | re.DOTALL)
TEMP_ZIP = re.compile(r"\.review-zip-.+\.tmp", re.DOTALL)
BACKUP_TAG = r"(?:bak|backup|bkp|old|orig|save|tmp|temp|sw[opx]|copy)"
BACKUP_SUFFIX = re.compile(rf"~+$|[. ]{BACKUP_TAG}(?:\.\d+)?$")
BACKUP_BEFORE_EXTENSION = re.compile(rf"(?:[. ]{BACKUP_TAG}| \(copy\))(?=\.[^.]+$)")
TEMPLATE_SUFFIXES = (".example", ".sample", ".template")
KEY_SUFFIXES = (".key", ".pem", ".p12", ".pfx", ".ppk", ".jks", ".keystore", ".keytab")
SSH_KEY = re.compile(r"id_(?:rsa|dsa|ecdsa(?:_sk)?|ed25519(?:_sk)?)|ssh_host_.+_key")
PRIVATE_KEY_NAME = re.compile(r"private[-_]?key(?:\.(?:asc|gpg|json|txt))?")
PRIVATE_CONFIG = re.compile(
    r"\.?(?:(?:[a-z0-9]+[-_.])*|wifi|api|db|database|cloud)"
    r"(?:credentials?|secrets?|service[-_]?account)"
    r"(?:[-_.](?:local|dev|development|prod|production|staging|test|backup|bak|tmp))?"
    r"(?:\.(?:json|ya?ml|toml|ini|cfg|conf|properties|plist|swift|xml|txt|env|py|js|ts))?"
)
KNOWN_CONFIG_NAMES = {
    ".git-credentials", ".netrc", "_netrc", ".npmrc", ".pypirc",
    ".htpasswd", "kubeconfig", "application_default_credentials.json", "terraform.tfvars",
}
KNOWN_CONFIG_PATHS = {
    (".aws", "credentials"), (".aws", "config"), (".kube", "config"),
    (".docker", "config.json"), (".config", "gh", "hosts.yml"),
}


class ReviewError(Exception):
    pass


def parse_args():
    parser = argparse.ArgumentParser(
        prog="make_review_zip.sh",
        description="Archive tracked and nonignored untracked files from the current Git worktree.",
        epilog=(
            "Relative output paths are relative to the Git root. The default output is in "
            "its parent directory. Repository-relative exclusions are literal. Symlinks "
            "and special files are rejected. Configuration templates may end in "
            ".example, .sample or .template. Key and backup filename checks still apply. "
            "Filenames alone cannot detect embedded secrets. Inspect before sharing."
        ),
    )
    parser.add_argument("output", nargs="?", help="optional output .zip path")
    parser.add_argument("--dry-run", action="store_true", help="print the member list as JSON")
    parser.add_argument("--exclude", action="append", default=[], metavar="PATH",
                        help="exclude a repository-relative file or directory (repeatable)")
    return parser.parse_args()


def git(*args, cwd=None, allow_failure=False):
    result = subprocess.run(
        ["git", "--no-optional-locks", "-c", "core.fsmonitor=false", *args],
        cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        if allow_failure:
            return None
        raise ReviewError(f"git {args[0]} failed (exit status {result.returncode})")
    return result.stdout


def git_paths(root, *args):
    return set(filter(None, git("ls-files", "--full-name", "-z", *args, cwd=root).split(b"\0")))


def member_parts(name):
    parts = tuple(name.split("/"))
    if (
        any(part in ("", ".", "..") for part in parts)
        or "\\" in name
        or re.match(r"[a-zA-Z]:", name)
    ):
        raise ReviewError(f"unsafe archive member path {name!r}")
    try:
        name.encode("utf-8")
    except UnicodeEncodeError:
        raise ReviewError(f"archive member path is not valid UTF-8: {name!r}") from None
    return parts


def sensitive_rule(parts):
    original = parts[-1].casefold()
    parent = tuple(part.casefold() for part in parts[:-1])
    name = original
    # Also recognise Emacs and Vim backup names.
    if name.startswith(".#"):
        name = name[2:]
    elif name.startswith("#") and name.endswith("#"):
        name = name[1:-1]
    while (unwrapped := BACKUP_BEFORE_EXTENSION.sub("", BACKUP_SUFFIX.sub("", name))) != name:
        name = unwrapped

    variants = [name]
    if name != original and name.startswith("."):
        variants.append(name[1:])

    for candidate in variants:
        suffix = next((suffix for suffix in TEMPLATE_SUFFIXES if candidate.endswith(suffix)), "")
        base = candidate[:-len(suffix)] if suffix else candidate
        if (
            base.endswith(KEY_SUFFIXES) or SSH_KEY.fullmatch(base) or PRIVATE_KEY_NAME.fullmatch(base)
            or "private-keys-v1.d" in parent
        ):
            return "private key, key bundle, or key store"
        if suffix and candidate == original:
            continue
        if base in (".env", ".envrc") or base.startswith(".env.") or base.endswith(".env"):
            return "environment configuration"
        if (
            base in KNOWN_CONFIG_NAMES or PRIVATE_CONFIG.fullmatch(base)
            or base.endswith((".tfstate", ".auto.tfvars"))
            or (*parent[-1:], base) in KNOWN_CONFIG_PATHS
            or (*parent[-2:], base) in KNOWN_CONFIG_PATHS
        ):
            return "credential or secret configuration"
    return None


@contextmanager
def member_parent(root_fd, parts, name):
    """Open each directory without following symlinks, including after validation."""
    fd = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            mode = os.stat(part, dir_fd=fd, follow_symlinks=False).st_mode
            if stat.S_ISLNK(mode):
                raise ReviewError(f"{name!r}: symbolic link in member path")
            if not stat.S_ISDIR(mode):
                raise FileNotFoundError(name)
            child_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child_fd
        yield fd, parts[-1]
    finally:
        os.close(fd)


def file_version(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@contextmanager
def open_member(root_fd, parts, name, expected):
    with member_parent(root_fd, parts, name) as (parent_fd, leaf):
        # A FIFO substituted after validation must not block this process.
        fd = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd)
    with os.fdopen(fd, "rb") as source:
        actual = os.fstat(source.fileno())
        if not stat.S_ISREG(actual.st_mode) or file_version(actual) != file_version(expected):
            raise ReviewError(f"{name!r}: file changed during snapshot")
        yield source
        if file_version(os.fstat(source.fileno())) != file_version(expected):
            raise ReviewError(f"{name!r}: file changed during snapshot")


def marked_review_zip(root_fd, parts, name, info):
    trailer_size = 22 + len(ZIP_COMMENT)
    if not name.lower().endswith(".zip") or info.st_size < trailer_size:
        return False
    # Inspect only the fixed-size ZIP trailer, never extract a candidate archive.
    with open_member(root_fd, parts, name, info) as source:
        source.seek(-trailer_size, os.SEEK_END)
        trailer = source.read(trailer_size)
    return (
        trailer.startswith(b"PK\x05\x06")
        and trailer[20:] == len(ZIP_COMMENT).to_bytes(2, "little") + ZIP_COMMENT
    )


def select_members(root, root_fd, excludes, output):
    tracked = git_paths(root, "--cached")
    untracked = git_paths(root, "--others", "--exclude-standard")
    ignored = git_paths(root, "--others", "--ignored", "--exclude-standard", "--directory")
    excluded = [(os.fsdecode(path), "ignored by Git") for path in sorted(ignored)]
    candidates = []

    for path in sorted(tracked | untracked):
        name = os.fsdecode(path).removesuffix("/")
        parts = member_parts(name)
        if any(part.casefold() == ".git" for part in parts):
            excluded.append((name, "Git metadata"))
            continue
        if any(parts[:len(prefix)] == prefix for prefix in excludes):
            excluded.append((name, "explicit exclusion"))
            continue
        if REVIEW_ZIP.fullmatch(parts[-1]) or TEMP_ZIP.fullmatch(parts[-1]) or root / name == output:
            excluded.append((name, "review ZIP or archive temporary file"))
            continue

        try:
            with member_parent(root_fd, parts, name) as (parent_fd, leaf):
                info = os.stat(leaf, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            excluded.append((name, "absent from the working tree"))
            continue
        if stat.S_ISDIR(info.st_mode):
            excluded.append((name, "directory entry (Git submodule, nested repository, or replacement)"))
            continue
        rule = sensitive_rule(parts)
        if rule:
            raise ReviewError(f"{name!r}: sensitive filename rule matched ({rule})")
        if stat.S_ISLNK(info.st_mode):
            raise ReviewError(f"{name!r}: symbolic links are not archived")
        if not stat.S_ISREG(info.st_mode):
            raise ReviewError(f"{name!r}: unsupported file type")
        candidates.append((name, parts, info, path in tracked))

    members = []
    for name, parts, info, is_tracked in candidates:
        if marked_review_zip(root_fd, parts, name, info):
            excluded.append((name, "previous review ZIP (archive marker)"))
        else:
            members.append((name, parts, info, is_tracked))
    return members, excluded


def write_zip(output, root_fd, members):
    fd, temp = tempfile.mkstemp(prefix=".review-zip-", suffix=".tmp", dir=output.parent)
    try:
        with os.fdopen(fd, "w+b") as archive:
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
                zipped.comment = ZIP_COMMENT
                for name, parts, info, _ in members:
                    modified = datetime.fromtimestamp(info.st_mtime)
                    if modified.year < 1980 or modified.year > 2107:
                        modified = datetime(min(max(modified.year, 1980), 2107), 1, 1)
                    entry = zipfile.ZipInfo(name, modified.timetuple()[:6])
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    entry.file_size = info.st_size
                    entry.external_attr = info.st_mode << 16
                    with open_member(root_fd, parts, name, info) as source, zipped.open(entry, "w") as dest:
                        shutil.copyfileobj(source, dest)
            archive.seek(0)
            with zipfile.ZipFile(archive) as zipped:
                if zipped.namelist() != [name for name, _, _, _ in members]:
                    raise ReviewError("ZIP verification failed: archive members differ from the manifest")
                bad_member = zipped.testzip()
                if bad_member is not None:
                    raise ReviewError(f"ZIP verification failed for member {bad_member!r}")

        # The hard link publishes the complete file atomically and fails if the
        # destination appeared after the initial collision check.
        try:
            os.link(temp, output)
        except FileExistsError:
            raise ReviewError(f"output already exists: {str(output)!r}") from None
    finally:
        os.unlink(temp)


def main():
    args = parse_args()
    result = git("rev-parse", "--show-toplevel", allow_failure=True)
    if result is None:
        raise ReviewError("run this utility inside a Git working tree")
    root = Path(os.fsdecode(result.removesuffix(b"\n"))).resolve()
    if args.output is None:
        output = root.parent / f"{root.name}-review-{datetime.now():%Y%m%d-%H%M%S}.zip"
    else:
        output = root / args.output
        output = output.parent.resolve() / output.name
    if output.suffix.lower() != ".zip":
        raise ReviewError("the output path must end in .zip")
    if os.path.lexists(output):
        raise ReviewError(f"output already exists: {str(output)!r}")

    excludes = [member_parts(name.removesuffix("/")) for name in args.exclude]
    root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        members, excluded = select_members(root, root_fd, excludes, output)
        revision = git("rev-parse", "--verify", "HEAD", cwd=root, allow_failure=True)
        status_paths = [":(top,literal,exclude)" + "/".join(parts) for parts in excludes]
        dirty = git(
            "status", "--porcelain=v1", "-z", "--no-renames", "--ignore-submodules=dirty",
            "--untracked-files=normal", "--", *status_paths, cwd=root,
        )
        scope = " (outside explicit exclusions)" if excludes else ""
        revision_text = revision.decode("ascii").strip() if revision else "unborn HEAD"
        print(f"Repository: {root.name!r} ({revision_text})", file=sys.stderr)
        print(f"Working tree changes: {'yes' if dirty else 'no'}{scope}", file=sys.stderr)
        tracked_count = sum(is_tracked for _, _, _, is_tracked in members)
        print(f"Selected {tracked_count} tracked and {len(members) - tracked_count} untracked files",
              file=sys.stderr)
        for name, reason in excluded:
            print(f"Excluded {name!r}: {reason}", file=sys.stderr)
        if args.dry_run:
            print(json.dumps([name for name, _, _, _ in members], indent=2))
        else:
            write_zip(output, root_fd, members)
            print(f"ZIP verified: {len(members)} members match the manifest and pass CRC checks")
            print(f"Archive: {str(output)!r}")
    finally:
        os.close(root_fd)


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


signal.signal(signal.SIGTERM, interrupted)
try:
    main()
except KeyboardInterrupt:
    sys.exit("Error: review ZIP interrupted")
except (ReviewError, OSError, zipfile.BadZipFile, ValueError) as error:
    sys.exit(f"Error: {error}")
PY
