#!/usr/bin/env python3
"""Package and verify the probe's deliberately unsigned iOS IPA."""

from __future__ import annotations

import argparse
import hashlib
import os
import posixpath
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


APP_NAME = "VPhoneIndicatorProbe.app"
BUNDLE_ID = "org.vphone.indicatorprobe"
IPA_NAME = "VPhoneIndicatorProbe-unsigned.ipa"
APP_ARCHIVE_ROOT = "Payload/" + APP_NAME
ARM64_CPUTYPE = 0x0100000C
LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
IOS_PLATFORM = 2
IOS_SIMULATOR_PLATFORM = 7
PRIVATE_KEY_HEADER = re.compile(rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")
FORBIDDEN_SUFFIXES = {
    ".mobileprovision",
    ".provisionprofile",
    ".p12",
    ".p8",
    ".key",
}


class VerificationError(Exception):
    pass


def fail(message: str) -> None:
    raise VerificationError(message)


def ensure_path_is_under_build(path_value: str, app_root: str, build_root: str) -> str:
    candidate = path_value if os.path.isabs(path_value) else os.path.join(app_root, path_value)
    resolved_build = os.path.realpath(build_root)
    resolved_candidate = os.path.realpath(candidate)
    try:
        common = os.path.commonpath([resolved_build, resolved_candidate])
    except ValueError:
        fail("Output and derived-data paths must be beneath the app's build/ directory.")
    if common != resolved_build:
        fail("Output and derived-data paths must be beneath the app's build/ directory.")
    return resolved_candidate


def validate_paths(args: argparse.Namespace) -> None:
    app_root = os.path.realpath(args.app_root)
    lexical_build_root = os.path.abspath(args.build_root)
    build_root = os.path.realpath(args.build_root)
    if build_root != lexical_build_root:
        fail("The ignored build/ directory must not be a symlink.")
    output_dir = ensure_path_is_under_build(args.output_dir, app_root, build_root)
    derived_data_dir = ensure_path_is_under_build(args.derived_data_dir, app_root, build_root)
    if output_dir == build_root or derived_data_dir == build_root:
        # Keeping artifacts in build/ itself is safe, but separating these
        # roots avoids an accidental collision with Xcode's generated files.
        pass
    if output_dir == derived_data_dir:
        fail("The output directory and derived-data directory must be different.")
    if output_dir.startswith(derived_data_dir + os.sep) or derived_data_dir.startswith(output_dir + os.sep):
        fail("The output directory and derived-data directory must not contain one another.")


def forbidden_bundle_path(rel_path: str) -> str | None:
    parts = PurePosixPath(rel_path).parts
    for part in parts:
        if part == "_CodeSignature":
            return "_CodeSignature"
        if part == ".DS_Store" or part.startswith("._") or part == "__MACOSX":
            return "macOS metadata"
        if Path(part).suffix.lower() in FORBIDDEN_SUFFIXES:
            return "signing credential or provisioning artifact"
    return None


def validate_symlink_target(rel_path: str, target: str) -> None:
    if not target or target.startswith("/") or "\\" in target:
        fail("App contains a symlink with an absolute or invalid target: " + rel_path)
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(rel_path), target))
    if resolved == ".." or resolved.startswith("../"):
        fail("App contains a symlink that escapes its bundle: " + rel_path)


def validate_bundle_tree(
    app_path: Path, expected_version: str | None = None, expected_build: str | None = None
) -> None:
    if app_path.name != APP_NAME or not app_path.is_dir() or app_path.is_symlink():
        fail("Expected a built " + APP_NAME + " directory.")

    for current, dirnames, filenames in os.walk(str(app_path), topdown=True, followlinks=False):
        dirnames.sort()
        filenames.sort()
        for name in list(dirnames) + filenames:
            full_path = os.path.join(current, name)
            rel_path = os.path.relpath(full_path, str(app_path)).replace(os.sep, "/")
            problem = forbidden_bundle_path(rel_path)
            if problem:
                fail("App contains forbidden " + problem + " at " + rel_path)
            if os.path.islink(full_path):
                validate_symlink_target(rel_path, os.readlink(full_path))
                continue
            if os.path.isfile(full_path):
                try:
                    with open(full_path, "rb") as handle:
                        header = handle.read(4096)
                except OSError as exc:
                    fail("Cannot inspect app file " + rel_path + ": " + str(exc))
                if PRIVATE_KEY_HEADER.search(header):
                    fail("App contains a private-key PEM block at " + rel_path)
                if looks_like_macho(header[:4]):
                    try:
                        with open(full_path, "rb") as handle:
                            verify_macho(handle.read())
                    except OSError as exc:
                        fail("Cannot inspect Mach-O app file " + rel_path + ": " + str(exc))

    info_path = app_path / "Info.plist"
    if not info_path.is_file() or info_path.is_symlink():
        fail("App must contain a regular Info.plist.")
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except Exception as exc:
        fail("Cannot read app Info.plist: " + str(exc))
    if not isinstance(info, dict):
        fail("App Info.plist must contain a dictionary.")
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        fail("Unexpected CFBundleIdentifier: " + repr(info.get("CFBundleIdentifier")))
    if expected_version is not None and info.get("CFBundleShortVersionString") != expected_version:
        fail(
            "Unexpected CFBundleShortVersionString: "
            + repr(info.get("CFBundleShortVersionString"))
            + "; expected "
            + expected_version
        )
    if expected_build is not None and str(info.get("CFBundleVersion")) != expected_build:
        fail(
            "Unexpected CFBundleVersion: "
            + repr(info.get("CFBundleVersion"))
            + "; expected "
            + expected_build
        )
    minimum_os = info.get("MinimumOSVersion")
    try:
        min_parts = tuple(int(piece) for piece in str(minimum_os).split("."))
    except ValueError:
        fail("Info.plist MinimumOSVersion is missing or invalid: " + repr(minimum_os))
    if not min_parts or min_parts[0] != 16:
        fail("Info.plist MinimumOSVersion must target iOS 16; found " + repr(minimum_os))
    if "UILaunchScreen" not in info:
        fail("Info.plist is missing UILaunchScreen.")
    supported = info.get("CFBundleSupportedPlatforms")
    if not isinstance(supported, list) or "iPhoneOS" not in supported:
        fail("Info.plist does not identify iPhoneOS as a supported platform.")

    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name or "/" in executable_name:
        fail("Info.plist CFBundleExecutable is missing or invalid.")
    executable = app_path / executable_name
    if not executable.is_file() or executable.is_symlink():
        fail("App executable is missing or is not a regular file: " + executable_name)
    try:
        with executable.open("rb") as handle:
            executable_bytes = handle.read()
    except OSError as exc:
        fail("Cannot read app executable: " + str(exc))
    verify_macho(executable_bytes)


def is_fat_magic(magic: bytes) -> tuple[str, bool] | None:
    values = {
        b"\xca\xfe\xba\xbe": (">", False),
        b"\xbe\xba\xfe\xca": ("<", False),
        b"\xca\xfe\xba\xbf": (">", True),
        b"\xbf\xba\xfe\xca": ("<", True),
    }
    return values.get(magic)


def looks_like_macho(magic: bytes) -> bool:
    return magic in {
        b"\xce\xfa\xed\xfe",
        b"\xcf\xfa\xed\xfe",
        b"\xfe\xed\xfa\xce",
        b"\xfe\xed\xfa\xcf",
    } or is_fat_magic(magic) is not None


def macho_slices(data: bytes) -> list[bytes]:
    if len(data) < 4:
        fail("App executable is too short to be a Mach-O binary.")
    fat = is_fat_magic(data[:4])
    if fat is None:
        return [data]
    endian, is_64 = fat
    if len(data) < 8:
        fail("Truncated universal Mach-O header.")
    count = struct.unpack(endian + "I", data[4:8])[0]
    arch_size = 32 if is_64 else 20
    table_end = 8 + count * arch_size
    if count < 1 or table_end > len(data):
        fail("Invalid universal Mach-O architecture table.")
    result = []
    for index in range(count):
        start = 8 + index * arch_size
        if is_64:
            _cpu, _subtype, offset, size, _align, _reserved = struct.unpack(
                endian + "iiQQII", data[start : start + arch_size]
            )
        else:
            _cpu, _subtype, offset, size, _align = struct.unpack(
                endian + "iiIII", data[start : start + arch_size]
            )
        if offset < table_end or size < 4 or offset + size > len(data):
            fail("Invalid universal Mach-O slice bounds.")
        result.append(data[offset : offset + size])
    return result


def inspect_thin_macho(data: bytes) -> tuple[int, bool, list[int]]:
    magics = {
        b"\xce\xfa\xed\xfe": ("<", False),
        b"\xcf\xfa\xed\xfe": ("<", True),
        b"\xfe\xed\xfa\xce": (">", False),
        b"\xfe\xed\xfa\xcf": (">", True),
    }
    parsed = magics.get(data[:4])
    if parsed is None:
        fail("App executable is not a recognized Mach-O binary.")
    endian, is_64 = parsed
    header_size = 32 if is_64 else 28
    if len(data) < header_size:
        fail("Truncated Mach-O header.")
    cpu_type = struct.unpack(endian + "I", data[4:8])[0]
    ncmds = struct.unpack(endian + "I", data[16:20])[0]
    sizeofcmds = struct.unpack(endian + "I", data[20:24])[0]
    command_end = header_size + sizeofcmds
    if command_end > len(data):
        fail("Mach-O load commands exceed the executable size.")
    offset = header_size
    has_code_signature = False
    platforms: list[int] = []
    for _ in range(ncmds):
        if offset + 8 > command_end:
            fail("Truncated Mach-O load command.")
        command, command_size = struct.unpack(endian + "II", data[offset : offset + 8])
        if command_size < 8 or offset + command_size > command_end:
            fail("Invalid Mach-O load command size.")
        if command == LC_CODE_SIGNATURE:
            has_code_signature = True
        elif command == LC_BUILD_VERSION:
            if command_size < 24:
                fail("Truncated LC_BUILD_VERSION command.")
            platforms.append(struct.unpack(endian + "I", data[offset + 8 : offset + 12])[0])
        elif command == LC_VERSION_MIN_IPHONEOS:
            platforms.append(IOS_PLATFORM)
        offset += command_size
    if offset != command_end:
        fail("Mach-O load-command size does not match sizeofcmds.")
    return cpu_type, has_code_signature, platforms


def verify_macho(data: bytes) -> None:
    slices = macho_slices(data)
    cpu_types = []
    platform_values: list[int] = []
    for slice_data in slices:
        cpu_type, has_signature, platforms = inspect_thin_macho(slice_data)
        cpu_types.append(cpu_type)
        platform_values.extend(platforms)
        if has_signature:
            fail("App executable contains LC_CODE_SIGNATURE; expected an unsigned binary.")
    if ARM64_CPUTYPE not in cpu_types:
        fail("App executable does not contain an arm64 device slice.")
    if IOS_SIMULATOR_PLATFORM in platform_values:
        fail("App executable contains an iOS Simulator build slice.")
    if not platform_values or any(platform != IOS_PLATFORM for platform in platform_values):
        fail("App executable is missing an iOS device platform load command.")


def codesign_status_is_unsigned(app_path: Path) -> str:
    try:
        process = subprocess.run(
            ["codesign", "-d", "--verbose=4", str(app_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except OSError as exc:
        fail("Could not run codesign to inspect the app: " + str(exc))
    diagnostic = (process.stdout + "\n" + process.stderr).strip()
    lowered = diagnostic.lower()
    if process.returncode == 0 or "not signed" not in lowered:
        fail("codesign did not confirm an unsigned app; diagnostic: " + (diagnostic or "<empty>"))
    return diagnostic


def zip_member_mode(info: zipfile.ZipInfo) -> int:
    return (info.external_attr >> 16) & 0xFFFF


def validate_archive_names(infos: list[zipfile.ZipInfo]) -> dict[str, bool]:
    if not infos:
        fail("IPA archive is empty.")
    seen: set[str] = set()
    symlinks: set[str] = set()
    app_prefix = APP_ARCHIVE_ROOT + "/"
    payload_directory_present = False
    app_directory_present = False
    for info in infos:
        name = info.filename
        if not name or name.startswith("/") or "\\" in name or "\x00" in name:
            fail("IPA contains an invalid archive path: " + repr(name))
        raw_parts = name.rstrip("/").split("/")
        if any(part in ("", ".", "..") for part in raw_parts):
            fail("IPA contains an unsafe archive path: " + repr(name))
        if name != "Payload/" and name != APP_ARCHIVE_ROOT + "/" and not name.startswith(app_prefix):
            fail("IPA contains a path outside Payload/" + APP_NAME + ": " + name)
        if name in seen:
            fail("IPA contains a duplicate path: " + name)
        seen.add(name)

        rel_path = name[len("Payload/") :] if name.startswith("Payload/") else name
        problem = forbidden_bundle_path(rel_path)
        if problem:
            fail("IPA contains forbidden " + problem + " at " + name)

        is_directory = name.endswith("/")
        mode = zip_member_mode(info)
        file_type = stat.S_IFMT(mode)
        if is_directory and file_type not in (0, stat.S_IFDIR):
            fail("IPA has a non-directory entry with a directory path: " + name)
        if not is_directory and file_type == stat.S_IFDIR:
            fail("IPA has a directory entry without a trailing slash: " + name)
        if file_type == stat.S_IFLNK:
            if is_directory:
                fail("IPA marks a directory as a symlink: " + name)
            symlinks.add(name)
        elif is_directory or file_type == stat.S_IFDIR:
            pass
        elif file_type not in (0, stat.S_IFREG):
            fail("IPA contains an unsupported filesystem entry: " + name)

        if name == "Payload/":
            payload_directory_present = is_directory
        if name == APP_ARCHIVE_ROOT + "/":
            app_directory_present = is_directory

    for name in seen:
        parts = name.rstrip("/").split("/")
        for length in range(1, len(parts)):
            parent = "/".join(parts[:length])
            if parent in symlinks:
                fail("IPA path traverses a symlink: " + name)
        if name.endswith("/") and name.rstrip("/") in symlinks:
            fail("IPA path is both a directory and symlink: " + name)

    if not payload_directory_present or not app_directory_present:
        fail("IPA must contain Payload/ and Payload/" + APP_NAME + "/ directories.")
    return {"payload": payload_directory_present, "app": app_directory_present}


def safe_extract_archive(archive: zipfile.ZipFile, infos: list[zipfile.ZipInfo], destination: Path) -> Path:
    validate_archive_names(infos)
    symlink_targets: dict[str, str] = {}
    for info in infos:
        if stat.S_IFMT(zip_member_mode(info)) == stat.S_IFLNK:
            try:
                target = archive.read(info).decode("utf-8")
            except Exception as exc:
                fail("Cannot read IPA symlink target for " + info.filename + ": " + str(exc))
            rel_path = info.filename[len("Payload/") :]
            validate_symlink_target(rel_path, target)
            symlink_targets[info.filename] = target

    directory_modes: dict[Path, int] = {}
    for info in sorted(infos, key=lambda item: (item.filename.count("/"), item.filename)):
        name = info.filename
        target_path = destination.joinpath(*name.rstrip("/").split("/"))
        mode = zip_member_mode(info)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        if name.endswith("/") or stat.S_IFMT(mode) == stat.S_IFDIR:
            target_path.mkdir(parents=True, exist_ok=True)
            perms = mode & 0o777
            if perms:
                directory_modes[target_path] = perms
        elif name in symlink_targets:
            os.symlink(symlink_targets[name], target_path)
        else:
            with archive.open(info, "r") as source, target_path.open("xb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            perms = mode & 0o777
            if perms:
                os.chmod(target_path, perms)
    for directory, perms in sorted(directory_modes.items(), key=lambda item: len(item[0].parts), reverse=True):
        os.chmod(directory, perms)
    return destination / APP_ARCHIVE_ROOT


def verify_ipa(
    ipa_path: Path, expected_version: str | None = None, expected_build: str | None = None
) -> None:
    if not ipa_path.is_file():
        fail("IPA file not found: " + str(ipa_path))
    try:
        with zipfile.ZipFile(str(ipa_path), "r") as archive:
            bad_member = archive.testzip()
            if bad_member:
                fail("IPA ZIP CRC check failed for " + bad_member)
            infos = archive.infolist()
            validate_archive_names(infos)
            with tempfile.TemporaryDirectory(
                prefix=".verify-unsigned-ipa.", dir=str(ipa_path.parent.resolve())
            ) as temp_dir:
                extracted_app = safe_extract_archive(archive, infos, Path(temp_dir))
                validate_bundle_tree(extracted_app, expected_version, expected_build)
                status = codesign_status_is_unsigned(extracted_app)
    except zipfile.BadZipFile as exc:
        fail("IPA is not a valid ZIP archive: " + str(exc))
    print("Verified unsigned arm64 iPhoneOS IPA: " + str(ipa_path))
    print("codesign -d: " + status.splitlines()[-1])


def make_zip_info(name: str, mode: int, is_directory: bool = False) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.compress_type = zipfile.ZIP_STORED if is_directory or stat.S_ISLNK(mode) else zipfile.ZIP_DEFLATED
    info.external_attr = (mode & 0xFFFF) << 16
    if is_directory:
        info.external_attr |= 0x10
    return info


def write_directory(archive: zipfile.ZipFile, arc_path: str, source_mode: int = 0o755) -> None:
    name = arc_path.rstrip("/") + "/"
    archive.writestr(make_zip_info(name, stat.S_IFDIR | (source_mode & 0o777), True), b"")


def package_app(
    app_path: Path,
    ipa_path: Path,
    expected_version: str | None = None,
    expected_build: str | None = None,
) -> None:
    validate_bundle_tree(app_path, expected_version, expected_build)
    if os.path.lexists(str(ipa_path)):
        fail("Refusing to overwrite an existing package output: " + str(ipa_path))
    ipa_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(str(ipa_path), "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        write_directory(archive, "Payload")
        write_directory(archive, APP_ARCHIVE_ROOT)
        for current, dirnames, filenames in os.walk(str(app_path), topdown=True, followlinks=False):
            dirnames.sort()
            filenames.sort()
            current_rel = os.path.relpath(current, str(app_path))
            current_rel_posix = "" if current_rel == "." else current_rel.replace(os.sep, "/")
            for dirname in dirnames:
                source_path = Path(current) / dirname
                rel = "/".join(part for part in (current_rel_posix, dirname) if part)
                arc_path = APP_ARCHIVE_ROOT + "/" + rel
                if source_path.is_symlink():
                    target = os.readlink(str(source_path))
                    validate_symlink_target(rel, target)
                    mode = stat.S_IFLNK | 0o777
                    archive.writestr(make_zip_info(arc_path, mode), target.encode("utf-8"))
                else:
                    source_mode = stat.S_IMODE(os.lstat(str(source_path)).st_mode)
                    write_directory(archive, arc_path, source_mode)
            for filename in filenames:
                source_path = Path(current) / filename
                rel = "/".join(part for part in (current_rel_posix, filename) if part)
                arc_path = APP_ARCHIVE_ROOT + "/" + rel
                if source_path.is_symlink():
                    target = os.readlink(str(source_path))
                    validate_symlink_target(rel, target)
                    archive.writestr(
                        make_zip_info(arc_path, stat.S_IFLNK | 0o777), target.encode("utf-8")
                    )
                else:
                    file_stat = os.lstat(str(source_path))
                    if not stat.S_ISREG(file_stat.st_mode):
                        fail("App contains an unsupported filesystem entry: " + rel)
                    mode = stat.S_IFREG | stat.S_IMODE(file_stat.st_mode)
                    with source_path.open("rb") as source:
                        archive.writestr(make_zip_info(arc_path, mode), source.read())
    verify_ipa(ipa_path, expected_version, expected_build)


def write_sha256(ipa_path: Path, output_path: Path) -> None:
    if not ipa_path.is_file():
        fail("IPA file not found: " + str(ipa_path))
    digest = hashlib.sha256()
    with ipa_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(str(output_path)):
        fail("Refusing to overwrite an existing SHA-256 output: " + str(output_path))
    with output_path.open("x", encoding="utf-8") as handle:
        handle.write(digest.hexdigest() + "  " + ipa_path.name + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    paths_parser = subparsers.add_parser("validate-paths", help="ensure generated paths stay under build/")
    paths_parser.add_argument("--app-root", required=True)
    paths_parser.add_argument("--build-root", required=True)
    paths_parser.add_argument("--output-dir", required=True)
    paths_parser.add_argument("--derived-data-dir", required=True)

    package_parser = subparsers.add_parser("package", help="package and verify a built app")
    package_parser.add_argument("--app", required=True, type=Path)
    package_parser.add_argument("--ipa", required=True, type=Path)
    package_parser.add_argument("--expected-version")
    package_parser.add_argument("--expected-build")

    verify_parser = subparsers.add_parser("verify", help="verify an existing unsigned IPA")
    verify_parser.add_argument("--ipa", required=True, type=Path)
    verify_parser.add_argument("--expected-version")
    verify_parser.add_argument("--expected-build")

    sha_parser = subparsers.add_parser("sha256", help="write a portable SHA-256 sidecar")
    sha_parser.add_argument("--ipa", required=True, type=Path)
    sha_parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "validate-paths":
            validate_paths(args)
        elif args.command == "package":
            package_app(args.app, args.ipa, args.expected_version, args.expected_build)
        elif args.command == "verify":
            verify_ipa(args.ipa, args.expected_version, args.expected_build)
        elif args.command == "sha256":
            write_sha256(args.ipa, args.output)
        else:
            fail("Unknown command.")
    except VerificationError as exc:
        print("unsigned IPA verification failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
