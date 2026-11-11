#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""iStoreOS 上游包清单基准对比 / 冲突守护。

每次构建前，以 iStoreOS 上游「默认已选中的包」+「全部可构建包元数据」为基准，
检查本仓库的 builtin-list（待映射的 566 包）与 configs/g68-hybrid.config：

  DUPLICATE         上游默认已选中同名包        -> 注释（上游优先）
  PROVIDES_CONFLICT 本包 PROVIDES 命中上游占用  -> 注释（例如 dnsmasq-full 提供 dnsmasq）
  CONFLICTS         本包 CONFLICTS 命中上游选中 -> 注释
  UNKNOWN           上游包索引里查不到该包      -> 只告警，不注释（Phase 2 需人工映射）
  OK                上游存在但未默认选中        -> 保留

关键点：只做「同名去重」挡不住 package/install Error 255。上次失败是
dnsmasq-full 与 iStoreOS 自带的 dnsmasq 抢同一批文件，两者名字不同，
但 dnsmasq-full 的 Makefile 写了 PROVIDES:=dnsmasq，所以必须连虚拟包名一起比。

默认不改动仓库文件：把注释后的副本和报告写到 --out-dir。
加 --apply 才原地写回；--strict 让「存在需注释项」时返回非零（适合 PR 门禁）。

用法见 workflows/package-guard.yml 或 --help。
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import sys
from pathlib import Path

TAG = "[package-guard]"
REASON = {
    "duplicate": "上游默认已内置同名包，上游优先",
    "provides_conflict": "本包 PROVIDES 与上游已占用名冲突",
    "conflicts": "本包 CONFLICTS 命中上游已选包",
    "unknown": "上游包索引中未找到，需 Phase 2 映射",
}
CONFIG_LINE = re.compile(r"^(\s*)CONFIG_PACKAGE_([\w.+-]+)=([ym])(\s*)$")
LIST_LINE = re.compile(r"^(\s*)([A-Za-z0-9][A-Za-z0-9.+-]*)(?:\s+-\s+\S+)?(\s*)$")
FIELD_LINE = re.compile(r"^([A-Za-z][A-Za-z-]*):\s*(.*)$")


def parse_defconfig(path):
    """返回上游默认选中包集合 {name}（=y；=m 只是 ipk，不进固件故不计）。"""
    selected = set()
    if not path or not os.path.isfile(path):
        return selected
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^CONFIG_PACKAGE_([\w.+-]+)=y$", line)
            if m:
                selected.add(m.group(1))
    return selected


def _split_blocks(text):
    """.packageinfo 用 @@ 分包；也兼容空行分包。"""
    parts = re.split(r"^@@\s*$", text, flags=re.M)
    if len(parts) > 1:
        return parts
    return re.split(r"\n\s*\n", text)


def parse_index(patterns, meta):
    """解析 feeds/*.index（OpenWrt .packageinfo 格式）里的 Package/Provides/Conflicts。"""
    files = []
    for pattern in patterns:
        files.extend(sorted(glob.glob(pattern)))
    for path in files:
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for block in _split_blocks(text):
            name = None
            provides, conflicts = set(), set()
            for raw in block.splitlines():
                m = FIELD_LINE.match(raw.strip())
                if not m:
                    continue
                key, val = m.group(1).lower(), m.group(2).strip()
                if key == "package" and not name:
                    name = val.split()[0] if val else None
                elif key in ("provides", "conflicts"):
                    dest = provides if key == "provides" else conflicts
                    dest.update(v.strip() for v in val.replace(",", " ").split() if v.strip())
            if name:
                rec = meta.setdefault(name, {"provides": set(), "conflicts": set()})
                rec["provides"].update(provides)
                rec["conflicts"].update(conflicts)
    return files


def parse_makefiles(dirs, meta):
    """补充解析上游 package/**/Makefile 的 define Package/<name> 段内 PROVIDES/CONFLICTS。"""
    scanned = 0
    for d in dirs:
        root = Path(d)
        if not root.is_dir():
            continue
        for mk in root.rglob("Makefile"):
            try:
                lines = mk.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            scanned += 1
            current = None
            for raw in lines:
                line = raw.strip()
                m = re.match(r"^define\s+Package/([A-Za-z0-9][A-Za-z0-9.+-]*)", line)
                if m:
                    current = m.group(1)
                    meta.setdefault(current, {"provides": set(), "conflicts": set()})
                    continue
                if line == "endef":
                    current = None
                    continue
                if not current:
                    continue
                m = re.match(r"^(PROVIDES|CONFLICTS)\s*[:+?]?=\s*(.+)$", line)
                if m:
                    key = "provides" if m.group(1) == "PROVIDES" else "conflicts"
                    meta[current][key].update(
                        v.strip() for v in m.group(2).replace(",", " ").split() if v.strip()
                    )
    return scanned


def build_occupied(selected, meta):
    occupied = set(selected)
    for name in selected:
        rec = meta.get(name)
        if rec:
            occupied.update(rec["provides"])
    return occupied


def classify(name, selected, occupied, meta):
    if name in selected:
        return "duplicate"
    rec = meta.get(name)
    if rec is None:
        return "unknown"
    if rec["provides"] & occupied:
        return "provides_conflict"
    if rec["conflicts"] & selected:
        return "conflicts"
    return "ok"


def read_names_from_list(path):
    names = []
    if not path or not os.path.isfile(path):
        return names
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            names.append(s.split()[0].split(" - ")[0])
    return names


def read_names_from_config(path):
    names = []
    if not path or not os.path.isfile(path):
        return names
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.lstrip().startswith("#"):
                continue
            m = CONFIG_LINE.match(line.rstrip("\n"))
            if m:
                names.append(m.group(2))
    return names


def annotate(path, kind, decisions, apply_in_place, out_dir):
    """返回 (输出路径, 注释条数)。kind = config | list"""
    if not path or not os.path.isfile(path):
        return None, 0
    src = Path(path)
    out_lines, changed = [], 0
    with src.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            stripped = line.rstrip("\n")
            if stripped.lstrip().startswith("#"):
                out_lines.append(stripped)
                continue
            m = CONFIG_LINE.match(stripped) if kind == "config" else LIST_LINE.match(stripped)
            name = m.group(2) if m else None
            verdict = decisions.get(name) if name else None
            if name and verdict in ("duplicate", "provides_conflict", "conflicts"):
                body = "%sCONFIG_PACKAGE_%s=%s" % (m.group(1), name, m.group(3)) if kind == "config" \
                    else "%s%s" % (m.group(1), name)
                out_lines.append("# %s  # %s %s" % (body.strip(), TAG, REASON[verdict]))
                changed += 1
            else:
                out_lines.append(stripped)
    text = "\n".join(out_lines) + "\n"
    if apply_in_place:
        src.write_text(text, encoding="utf-8")
        return str(src), changed
    dest = Path(out_dir) / src.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding="utf-8")
    return str(dest), changed


def main():
    ap = argparse.ArgumentParser(description="iStoreOS 上游包清单基准对比 / 冲突守护")
    ap.add_argument("--upstream-config", required=True, help="上游 make defconfig 生成的 .config")
    ap.add_argument("--index", action="append", default=[], help="feeds/*.index glob，可重复")
    ap.add_argument("--makefile-dir", action="append", default=[], help="上游 package 源码目录，可重复")
    ap.add_argument("--builtin-list", help="待映射的 builtin-list 清单")
    ap.add_argument("--hybrid-config", help="configs/g68-hybrid.config")
    ap.add_argument("--out-dir", default="package-guard-out")
    ap.add_argument("--json", dest="json_path", help="JSON 报告路径")
    ap.add_argument("--md", dest="md_path", help="Markdown 报告路径")
    ap.add_argument("--apply", action="store_true", help="原地写回注释（默认只写副本）")
    ap.add_argument("--strict", action="store_true", help="存在需注释项时返回非零")
    ap.add_argument("--fail-on-unknown", action="store_true", help="存在未知包时返回非零")
    args = ap.parse_args()

    if not args.index:
        args.index = ["istoreos/feeds/*.index"]
    if not args.makefile_dir:
        args.makefile_dir = ["istoreos/package"]

    selected = parse_defconfig(args.upstream_config)
    meta = {}
    index_files = parse_index(args.index, meta)
    makefiles = parse_makefiles(args.makefile_dir, meta)
    occupied = build_occupied(selected, meta)

    list_names = read_names_from_list(args.builtin_list)
    config_names = read_names_from_config(args.hybrid_config)
    all_names = sorted(set(list_names) | set(config_names))
    decisions = {n: classify(n, selected, occupied, meta) for n in all_names}

    counts = {k: 0 for k in REASON}
    counts["ok"] = 0
    for v in decisions.values():
        counts[v] += 1

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    list_out, list_changed = annotate(args.builtin_list, "list", decisions, args.apply, out_dir)
    config_out, config_changed = annotate(args.hybrid_config, "config", decisions, args.apply, out_dir)

    # 上游基准快照，便于追溯「以哪一版上游为准」
    (out_dir / "upstream-selected.txt").write_text(
        "\n".join(sorted(selected)) + "\n", encoding="utf-8")

    summary = {
        "generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "upstream": {
            "selected_packages": len(selected),
            "known_packages": len(meta),
            "index_files": index_files,
            "makefiles_scanned": makefiles,
            "occupied_names": len(occupied),
        },
        "inputs": {
            "builtin_list": args.builtin_list,
            "builtin_list_packages": len(list_names),
            "hybrid_config": args.hybrid_config,
            "hybrid_config_packages": len(config_names),
        },
        "counts": counts,
        "commented_lines": {"builtin_list": list_changed, "hybrid_config": config_changed},
        "outputs": {"builtin_list": list_out, "hybrid_config": config_out},
        "apply_in_place": args.apply,
        "details": {k: sorted(n for n, v in decisions.items() if v == k) for k in REASON},
    }
    json_path = args.json_path or str(out_dir / "report.json")
    Path(json_path).parent.mkdir(parents=True, exist_ok=True)
    Path(json_path).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# package-guard 报告",
        "",
        "- 上游默认已选中包：%d；上游已知包定义：%d；占用名（含 PROVIDES）：%d"
        % (len(selected), len(meta), len(occupied)),
        "- builtin-list：%d 项；hybrid config：%d 项"
        % (len(list_names), len(config_names)),
        "",
        "| 判定 | 数量 | 处理 |",
        "| --- | --- | --- |",
        "| duplicate | %d | 注释，上游优先 |" % counts["duplicate"],
        "| provides_conflict | %d | 注释，防同文件冲突 |" % counts["provides_conflict"],
        "| conflicts | %d | 注释 |" % counts["conflicts"],
        "| unknown | %d | 仅告警，不自动注释（需映射） |" % counts["unknown"],
        "| ok | %d | 保留 |" % counts["ok"],
        "",
        "注释行数：builtin-list %d，hybrid config %d（%s）"
        % (list_changed, config_changed, "原地写回" if args.apply else "写入 out-dir 副本"),
        "",
    ]
    for key in ("duplicate", "provides_conflict", "conflicts", "unknown"):
        items = summary["details"][key]
        if not items:
            continue
        lines.append("## %s（%d）" % (key, len(items)))
        lines.append("")
        lines.append("```")
        lines.extend(items[:150])
        if len(items) > 150:
            lines.append("... 其余 %d 项见 report.json" % (len(items) - 150))
        lines.append("```")
        lines.append("")
    md_path = args.md_path or str(out_dir / "report.md")
    Path(md_path).write_text("\n".join(lines), encoding="utf-8")

    print("上游默认包 %d / 已知包 %d / 占用名 %d" % (len(selected), len(meta), len(occupied)))
    print("判定：duplicate=%d provides_conflict=%d conflicts=%d unknown=%d ok=%d"
          % (counts["duplicate"], counts["provides_conflict"], counts["conflicts"],
             counts["unknown"], counts["ok"]))
    print("注释行数：builtin-list=%d hybrid-config=%d；报告：%s / %s"
          % (list_changed, config_changed, json_path, md_path))

    needs_action = counts["duplicate"] + counts["provides_conflict"] + counts["conflicts"]
    if args.strict and needs_action:
        print("::error::检测到 %d 项需要注释（strict 模式）" % needs_action, file=sys.stderr)
        return 1
    if args.fail_on_unknown and counts["unknown"]:
        print("::error::检测到 %d 项上游未知包（fail-on-unknown）" % counts["unknown"], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
