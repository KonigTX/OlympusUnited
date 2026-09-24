from __future__ import annotations

import os
import hashlib
import argparse
import re
from pathlib import Path
from zipfile import ZipFile

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addon" / "OlympusUnited"
TOC = ADDON / "OlympusUnited.toc"


def toc_files() -> list[Path]:
    entries: list[Path] = []
    for raw_line in TOC.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("##"):
            entries.append(ADDON / line.replace("\\", "/"))
    return entries


def verify_manifest() -> None:
    required = toc_files()
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    assert not missing, f"TOC references missing files: {missing}"

    toc_text = TOC.read_text(encoding="utf-8-sig")
    assert "## Interface: 16001, 16000" in toc_text
    assert "## SavedVariables: OlympusUnitedDB" in toc_text
    assert "## Version: 0.6.0" in toc_text
    assert "## Author: KonigTX" in toc_text and "Konigtx" not in toc_text
    assert "## X-Curse-Project-ID: 1709990" in toc_text
    assert (ADDON / "Media" / "OlympusLogo.tga").is_file()


def verify_lua_syntax() -> None:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    for path in toc_files():
        source = path.read_text(encoding="utf-8")
        runtime.compile(source, name=str(path.relative_to(ROOT)))


def run_lua_specs() -> None:
    os.environ["OLYMPUS_UNITED_ROOT"] = ROOT.as_posix()
    for spec in (
        ROOT / "tests" / "protocol_state_spec.lua",
        ROOT / "tests" / "guild_trust_spec.lua",
        ROOT / "tests" / "chat_guard_spec.lua",
        ROOT / "tests" / "census_spec.lua",
        ROOT / "tests" / "guild_roster_spec.lua",
        ROOT / "tests" / "network_spec.lua",
        ROOT / "tests" / "ui_smoke_spec.lua",
    ):
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute(spec.read_text(encoding="utf-8"))


def verify_api_provenance() -> None:
    source_root = os.environ.get("WOW_FOREVER_UI_SOURCE")
    if source_root:
        source = Path(source_root)
    else:
        source = Path.home() / "ref" / "wow-ui-source-forever" / "Interface" / "AddOns"
    club = source / "Blizzard_APIDocumentationGenerated" / "ClubDocumentation.lua"
    guild = source / "Blizzard_APIDocumentationGenerated" / "GuildInfoDocumentation.lua"
    communities = source / "Blizzard_FrameXMLUtil" / "CommunitiesUtil.lua"
    chat_filters = source / "Blizzard_ChatFrameBase" / "Shared" / "ChatFrameFilters.lua"
    chat_docs = source / "Blizzard_APIDocumentationGenerated" / "ChatInfoDocumentation.lua"
    friend_docs = source / "Blizzard_APIDocumentationGenerated" / "FriendListDocumentation.lua"
    player_docs = source / "Blizzard_APIDocumentationGenerated" / "PlayerScriptDocumentation.lua"
    community_frame = source / "Blizzard_Communities" / "CommunitiesFrame.lua"
    for path in (club, guild, communities, chat_filters, chat_docs, friend_docs, player_docs, community_frame):
        assert path.is_file(), f"Forever API source missing: {path}"
    club_text = club.read_text(encoding="utf-8-sig")
    for token in ("GetGuildClubId", "GetClubInfo", "GetClubMembers", "GetMemberInfo", "ClubMemberInfo", "memberCount", "presence"):
        assert token in club_text, f"Club API provenance missing {token}"
    guild_text = guild.read_text(encoding="utf-8-sig")
    assert 'Name = "GuildRoster"' in guild_text and 'LiteralName = "GUILD_ROSTER_UPDATE"' in guild_text
    assert 'Name = "IsGuildOfficer"' in guild_text, "exact-build guild-officer predicate is missing"
    player_text = player_docs.read_text(encoding="utf-8-sig")
    assert 'Name = "IsGuildLeader"' in player_text, "exact-build guild-leader predicate is missing"
    authority_text = community_frame.read_text(encoding="utf-8-sig")
    assert re.search(r"IsGuildLeader\(\)\s+or\s+C_GuildInfo\.IsGuildOfficer\(\)", authority_text), \
        "Blizzard's combined guild authority predicate is missing"
    live_text = communities.read_text(encoding="utf-8-sig")
    assert "C_Club.GetClubMembers" in live_text and "C_Club.GetMemberInfo" in live_text
    filter_text = chat_filters.read_text(encoding="utf-8-sig")
    assert "function ChatFrameUtil.AddMessageEventFilter" in filter_text
    chat_text = chat_docs.read_text(encoding="utf-8-sig")
    assert 'LiteralName = "CHAT_MSG_CHANNEL"' in chat_text and '{ Name = "guid", Type = "WOWGUID"' in chat_text
    friend_text = friend_docs.read_text(encoding="utf-8-sig")
    for token in ('Name = "GetNumFriends"', 'Name = "GetFriendInfoByIndex"', 'Name = "GetNumWhoResults"',
                  'Name = "GetWhoInfo"', 'LiteralName = "WHO_LIST_UPDATE"'):
        assert token in friend_text, f"friend API provenance missing {token}"


def verify_skill_inputs() -> None:
    codex_root = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    root = codex_root / "skills" / "forever-addon-ui"
    expected = {
        "SKILL.md": "59c4fe114372f11a3d540d4e5a814683671780ae6229e56c77f08b365f249c24",
        "reference/lessons.md": "457e4b882fa2fc6ad926975808388885d09bf1e51ed09d9395096562478395d3",
        "reference/patterns.lua": "b9bbf95166a97421915324341ae477178dc066298b05067561f98195564a5342",
        "reference/look/window-and-more.png": "b7e191e88365fe4fbc3f5dc73512e10d4f8ba7e8bc0998f448ba40d9255d755d",
        "reference/look/card-match.png": "42af600f87d1b24d02e9dbb8d87268b5cd23d05206e3a8c2e36361aa6b11d135",
        "reference/look/card-nomatch.png": "f8fff7e2e167771fc85646f888b1da73ffcda7aeae180e1c051400676ef4110c",
        "reference/example/Blueprint/Blueprint.lua": "08a8eb514faeabf3b50629cb3fbeb34de5f1645dd1697d30e47661e7f1fcc56d",
        "reference/example/Blueprint/Blueprint.toc": "ed8bed0d38616ce8cd2fdb4e823a22716dd320343e6a7325d1f1961a088132ab",
        "tools/forever_load_check.py": "9ff1a66eddd85c798da9dfd5f203909559fdb567a6facb94fee056808680e33f",
    }
    for relative, digest in expected.items():
        path = root / relative
        assert path.is_file(), f"routed UI skill asset missing: {relative}"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"routed UI skill asset changed: {relative}"
    skill = (root / "SKILL.md").read_text(encoding="utf-8-sig")
    assert re.match(r"^---\nname: forever-addon-ui\ndescription: >-\n", skill), "repaired multiline skill frontmatter regressed"
    assert not (ROOT / "skills" / "forever-addon-ui").exists(), "duplicate local UI skill must not be created"


def version() -> str:
    match = re.search(r"^## Version:\s*(\S+)\s*$", TOC.read_text(encoding="utf-8-sig"), re.MULTILINE)
    assert match, "TOC version missing"
    return match.group(1)


def expected_archive_files() -> set[str]:
    files = {
        "OlympusUnited/" + path.relative_to(ADDON).as_posix()
        for path in ADDON.rglob("*")
        if path.is_file()
    }
    files.update({"OlympusUnited/README.md", "OlympusUnited/CHANGELOG.md", "OlympusUnited/LICENSE.txt"})
    return files


def archive_source(name: str) -> Path:
    relative = Path(name).relative_to("OlympusUnited")
    if relative.name == "README.md" and len(relative.parts) == 1:
        return ROOT / "README.md"
    if relative.name == "CHANGELOG.md" and len(relative.parts) == 1:
        return ROOT / "CHANGELOG.md"
    if relative.name == "LICENSE.txt" and len(relative.parts) == 1:
        return ROOT / "LICENSE.txt"
    return ADDON / relative


def verify_archive() -> Path | None:
    archive_path = ROOT / "dist" / f"OlympusUnited-{version()}.zip"
    sidecar = ROOT / "dist" / f"OlympusUnited-{version()}.sha256"
    if not archive_path.is_file():
        return None
    assert sidecar.is_file(), "archive checksum sidecar missing"
    with ZipFile(archive_path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        assert names == sorted(names), "archive entries are not unique ordinal order"
        assert set(names) == expected_archive_files(), "archive file set differs from the release boundary"
        assert all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in infos), "archive timestamps are not fixed"
        for info in infos:
            source = archive_source(info.filename)
            assert source.is_file(), f"archive source missing: {info.filename}"
            assert hashlib.sha256(archive.read(info)).digest() == hashlib.sha256(source.read_bytes()).digest(), \
                f"archive content is stale: {info.filename}"
    actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    recorded = sidecar.read_text(encoding="ascii").strip().split()[0]
    assert actual == recorded, "archive checksum sidecar mismatch"
    return archive_path


def verify_installed(installed_path: Path) -> None:
    expected = installed_path.resolve()
    authorized = Path(r"D:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\OlympusUnited").resolve()
    assert expected == authorized, f"installed verification path is not the exact authorized destination: {expected}"
    archive_path = verify_archive()
    assert archive_path is not None, "archive is required before installed verification"
    with ZipFile(archive_path) as archive:
        for info in archive.infolist():
            relative = Path(info.filename).relative_to("OlympusUnited")
            destination = installed_path / relative
            assert destination.is_file(), f"installed file missing: {relative.as_posix()}"
            assert hashlib.sha256(destination.read_bytes()).digest() == hashlib.sha256(archive.read(info)).digest(), \
                f"installed file hash mismatch: {relative.as_posix()}"


def verify_privacy_and_copy() -> None:
    roster = (ADDON / "GuildRoster.lua").read_text(encoding="utf-8")
    for forbidden in ("memberNote", "officerNote", "guildRank", "achievementPoints", "profession1"):
        assert forbidden not in roster, f"roster adapter must not access {forbidden}"
    strings = (ADDON / "Strings.lua").read_text(encoding="utf-8").lower()
    for jargon in ("lease", "epoch", "snapshot revision", "payload", "chunk", "relay"):
        assert not re.search(rf"\b{re.escape(jargon)}\b", strings), f"player-facing protocol jargon leaked: {jargon}"
    ui = (ADDON / "UI.lua").read_text(encoding="utf-8")
    assert "BackdropTemplate" not in ui and "SetBackdrop(" not in ui, "flat generic backdrop chrome returned"
    assert "UIPanelScrollFrameTemplate" in (ADDON / "UIPrimitives.lua").read_text(encoding="utf-8")
    guard = (ADDON / "ChatGuard.lua").read_text(encoding="utf-8")
    assert "SendWho =" not in guard and "C_FriendList.SendWho" not in guard, "chat guard must not replace or launch Who"
    assert 'return "unknown"' in guard and "RemoveMessagesByPredicate" not in guard, \
        "unknown senders must remain visible and rendered history must remain untouched"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--installed-path", type=Path)
    parser.add_argument("--archive", action="store_true",
                        help="also verify the repository dist candidate; omitted for source-only repair gates")
    args = parser.parse_args()
    verify_manifest()
    verify_lua_syntax()
    run_lua_specs()
    verify_api_provenance()
    verify_skill_inputs()
    verify_privacy_and_copy()
    if args.archive or args.installed_path:
        verify_archive()
    if args.installed_path:
        verify_installed(args.installed_path)
    print("Olympus United verification passed")
