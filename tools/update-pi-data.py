#!/usr/bin/env python3
"""Regenerates src/split/PIData.lua: the expected Power Infusion DPS gain per damage spec.

Run from the repo root: mise run pi-data (or python3 tools/update-pi-data.py, then stylua src/split/PIData.lua).
Dev only: tools/ is not packaged.

Sources, combined per spec:
  1. Ulria's tier + PI sims sheet (feat Mazz), tab "PI Sims - 5 mins patchwerk (on CDs)": the 4-piece "% gain"
     column, averaged over the spec's hero trees (other players' hero trees can't be seen in game).
  2. bloodmallet.com Power Infusion chart (castingpatchwerk): DPS with PI / DPS without PI - 1.
  3. whoshouldgetpi.com: top-100 logs with vs without PI per raid boss. These come out negative for most specs
     (parses that got PI come from different raids and comps), so they are NOT a gain. Only where a spec ranks
     against the others is used: a nudge of LOG_WEIGHT x (spec median - median of all specs), clipped to
     +-LOG_CLIP percentage points.
The base is the mean of 1 and 2 (whichever exist for the spec); 3 is added on top.
"""

import csv
import datetime
import io
import json
import re
import statistics
import sys
import urllib.request

SHEET_ID = "1exJeu5eVe4bTmyg3WFx5PTxIWvDLi0j-WW-XWpGoG88"
SHEET_GID = "853763455"  # PI Sims - 5 mins patchwerk (on CDs)
BLOODMALLET = "https://bloodmallet.com/chart/get/power_infusion/castingpatchwerk/priest/shadow"
WHOSHOULDGETPI = "https://www.whoshouldgetpi.com/"
LOG_WEIGHT, LOG_CLIP, LOG_MIN_SAMPLES = 0.15, 0.5, 30
MIN_SPECS, MAX_GAIN = 20, 15.0  # sanity checks: a source that changed shape must not ship wrong numbers
OUT = "src/split/PIData.lua"

# spec ID -> (display name, sheet row prefix, bloodmallet name, whoshouldgetpi "Spec Class")
SPECS = {
    62: ("Arcane Mage", "Arcane Mage", "Arcane Mage", "Arcane Mage"),
    63: ("Fire Mage", "Fire Mage", "Fire Mage", "Fire Mage"),
    64: ("Frost Mage", "Frost Mage", "Frost Mage", "Frost Mage"),
    70: ("Retribution Paladin", "Ret Paladin", "Retribution Paladin", "Retribution Paladin"),
    71: ("Arms Warrior", "Arms Warrior", "Arms Warrior", "Arms Warrior"),
    72: ("Fury Warrior", "Fury Warrior", "Fury Warrior", "Fury Warrior"),
    102: ("Balance Druid", "Balance Druid", "Balance Druid", "Balance Druid"),
    103: ("Feral Druid", "Feral Druid", "Feral Druid", "Feral Druid"),
    251: ("Frost Death Knight", "Frost DK", "Frost Death Knight", "Frost Death Knight"),
    252: ("Unholy Death Knight", "UH DK", "Unholy Death Knight", "Unholy Death Knight"),
    253: ("Beast Mastery Hunter", "BM Hunter", "Beast_Mastery Hunter", "Beast Mastery Hunter"),
    254: ("Marksmanship Hunter", "MM Hunter", "Marksmanship Hunter", "Marksmanship Hunter"),
    255: ("Survival Hunter", "Survival Hunter", "Survival Hunter", "Survival Hunter"),
    258: ("Shadow Priest", "Shadow Priest", "Shadow Priest", "Shadow Priest"),
    259: ("Assassination Rogue", "Assa Rogue", "Assassination Rogue", "Assassination Rogue"),
    260: ("Outlaw Rogue", "Outlaw Rogue", "Outlaw Rogue", "Outlaw Rogue"),
    261: ("Subtlety Rogue", "Sub Rogue", "Subtlety Rogue", "Subtlety Rogue"),
    262: ("Elemental Shaman", "Ele Shaman", "Elemental Shaman", "Elemental Shaman"),
    263: ("Enhancement Shaman", "Enh Shaman", "Enhancement Shaman", "Enhancement Shaman"),
    265: ("Affliction Warlock", "Aff Wlock", "Affliction Warlock", "Affliction Warlock"),
    266: ("Demonology Warlock", "Demo Wlock", "Demonology Warlock", "Demonology Warlock"),
    267: ("Destruction Warlock", "Destro Wlock", "Destruction Warlock", "Destruction Warlock"),
    269: ("Windwalker Monk", "WW Monk", "Windwalker Monk", "Windwalker Monk"),
    577: ("Havoc Demon Hunter", "Havoc DH", "Havoc Demon Hunter", "Havoc Demon Hunter"),
    1467: ("Devastation Evoker", "Deva Evoker", "Devastation Evoker", "Devastation Evoker"),
    1480: ("Devourer Demon Hunter", "Devourer DH", "Devourer Demon Hunter", "Devourer Demon Hunter"),
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (NSRT Raid Utility PI data)"})
    return urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")


def fail(message):
    print("error: " + message + f"; {OUT} was not changed", file=sys.stderr)
    sys.exit(1)


def check(name, gains):
    if len(gains) < MIN_SPECS:
        fail(f"{name}: only {len(gains)} specs matched (expected {MIN_SPECS}+); the source may have changed")
    for spec, gain in gains.items():
        if not 0 < gain < MAX_GAIN:
            fail(f"{name}: implausible gain {gain:.2f}% for {SPECS[spec][0]}")


def percent(text):
    text = text.strip().rstrip("%").replace(",", ".")
    return float(text) if text else None


def sheet_gains():
    url = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid={SHEET_GID}"
    rows = list(csv.reader(io.StringIO(get(url))))
    h = next(i for i, row in enumerate(rows) if any(c.strip() == "Class and Build" for c in row))
    head = [c.strip() for c in rows[h]]
    name_col = head.index("Class and Build")
    gain_cols = [i for i, c in enumerate(head) if c == "% gain"]
    if len(gain_cols) < 3:
        fail(f"sheet: expected three '% gain' columns (0p, 2p, 4p), found {len(gain_cols)}")
    four_piece = gain_cols[2]  # 0p, 2p, 4p
    if head[four_piece - 3] != "4p no PI":
        fail(f"sheet: the third '% gain' column is not under '4p no PI' (found {head[four_piece - 3]!r})")
    by_prefix = {}
    for row in rows[h + 1 :]:
        if len(row) <= four_piece or not row[name_col].strip():
            continue
        value = percent(row[four_piece])
        if value is not None:
            by_prefix.setdefault(row[name_col].strip(), value)
    gains = {}
    for spec, (_, prefix, _, _) in SPECS.items():
        values = [v for name, v in by_prefix.items() if name.startswith(prefix + " ")]
        if values:
            gains[spec] = statistics.mean(values)
    return gains


def bloodmallet_gains():
    data = json.loads(get(BLOODMALLET))
    values, gains = data["data"], {}
    for spec, (_, _, name, _) in SPECS.items():
        with_pi, without = values.get(name), values.get("{" + name + "}")
        if isinstance(with_pi, (int, float)) and isinstance(without, (int, float)) and without > 0:
            gains[spec] = (with_pi / without - 1) * 100
    return gains, data.get("timestamp", "?"), data.get("profile_without_pi_support", [])


def log_nudges():
    html = get(WHOSHOULDGETPI)
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.S)
    payload = "".join(json.loads('"' + c + '"') for c in chunks)
    start = payload.find('"allStats":') + len('"allStats":')
    stats, _ = json.JSONDecoder().raw_decode(payload[start:])
    deltas = {}
    for key, block in stats.items():
        if "M+" in key or not key.endswith("-DPS"):
            continue  # raid bosses only
        for s in block["stats"]:
            w, wo = s["withBuffs"], s["withoutBuffs"]
            if min(w["rankings"]["length"], wo["rankings"]["length"]) >= LOG_MIN_SAMPLES and wo["avgDPS"] > 0:
                deltas.setdefault(s["specName"] + " " + s["className"], []).append(
                    (w["avgDPS"] / wo["avgDPS"] - 1) * 100
                )
    medians = {name: statistics.median(v) for name, v in deltas.items()}
    center = statistics.median(medians.values())
    nudges = {}
    for spec, (_, _, _, name) in SPECS.items():
        if name in medians:
            nudges[spec] = max(-LOG_CLIP, min(LOG_CLIP, LOG_WEIGHT * (medians[name] - center)))
    return nudges


def main():
    sheet = sheet_gains()
    check("sheet", sheet)
    blood, blood_date, blood_no_pi = bloodmallet_gains()
    check("bloodmallet", blood)
    try:
        nudges = log_nudges()  # only a nudge: if the page changed, go on without it
    except Exception as error:  # noqa: BLE001 - any parse failure means "no nudges"
        print(f"warning: whoshouldgetpi could not be read ({error}); no log nudges this time", file=sys.stderr)
        nudges = {}
    lines = []
    for spec, (display, _, blood_name, _) in sorted(SPECS.items(), key=lambda kv: kv[1][0]):
        base = [g for g in (sheet.get(spec), blood.get(spec)) if g is not None]
        if not base:
            print(f"warning: no sim data for {display}", file=sys.stderr)
            continue
        gain = statistics.mean(base) + nudges.get(spec, 0)
        parts = []
        if spec in sheet:
            parts.append(f"sheet {sheet[spec]:.2f}")
        if spec in blood:
            note = " (manual PI timing)" if blood_name in blood_no_pi else ""
            parts.append(f"bloodmallet {blood[spec]:.2f}{note}")
        if spec in nudges:
            parts.append(f"logs {nudges[spec]:+.2f}")
        lines.append(f"        [{spec}] = {gain:.2f}, -- {display}: " + ", ".join(parts))
    today = datetime.date.today().isoformat()
    out = f"""-- GENERATED by tools/update-pi-data.py on {today}. Don't edit by hand: rerun it (mise run pi-data).
-- Expected Power Infusion DPS gain per damage spec, in percent. Base: the mean of Ulria's PI sims
-- (4-piece, hero trees averaged) and bloodmallet's PI chart ({blood_date}), plus a small, clipped nudge
-- from where the spec ranks in whoshouldgetpi.com's logs (raw log deltas are biased negative, so they
-- never set the value).
-- Specs not listed (tanks, healers, Augmentation) are never ranked as Power Infusion targets.
local _, RaidUtility = ...

RaidUtility.PI_DATA = {{
    updated = "{today}",
    gain = {{
""" + "\n".join(lines) + """
    },
}
"""
    with open(OUT, "w", encoding="ascii", newline="\n") as f:
        f.write(out)
    print(f"wrote {OUT}: {len(lines)} specs")


if __name__ == "__main__":
    main()
