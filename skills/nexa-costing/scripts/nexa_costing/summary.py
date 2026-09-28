"""Markdown summary of an estimate — what Claude shows in chat after a run."""
from __future__ import annotations


def _m(v: float) -> str:
    return f"{v:,.0f}"


def markdown(est: dict, files: dict | None = None, max_purchase: int = 12) -> str:
    meta, tot, it = est["meta"], est["totals"], est["internal"]
    cur = meta.get("currency", "AED")
    out = []
    who = " · ".join(x for x in (meta.get("client"), meta.get("project"), meta.get("location")) if x)
    out.append(f"## {meta['ref']} — {meta['title']}")
    if who:
        out.append(f"_{who}_")
    out.append("")
    vat = f" + VAT {tot['vat_pct']:g}% {_m(tot['vat'])}" if tot.get("vat_registered") else ""
    disc = f" (after {tot['discount_label']} −{_m(tot['discount'])})" if tot.get("discount") else ""
    out.append(f"**Client total: {cur} {_m(tot['grand_total'])}** — net {_m(tot['net'])}{disc}{vat}")
    out.append(f"**Direct cost:** {cur} {_m(it['direct_cost'])} · **Gross profit:** {cur} {_m(it['gross_profit'])} "
               f"(**{it['gross_margin_pct']:.1f}%** margin, {it['markup_on_cost_pct']:.0f}% markup) · "
               f"**Net after {it['overhead_pct']:g}% overhead:** {cur} {_m(it['net_profit'])} ({it['net_margin_pct']:.1f}%)")
    s = it.get("schedule", {})
    if s.get("total_days"):
        out.append(f"**Timeline:** ~{s['total_days']} working days (≈{s['weeks']:g} weeks) — "
                   f"procurement {s['procurement_days']:g} d, workshop {s['workshop_days']:g} d, site {s['site_days']:g} d")
    out.append("")
    out.append("| # | Scope item | Qty | Client amount | Cost | Margin |")
    out.append("|---|---|---|---:|---:|---:|")
    for sc in est["scope"]:
        i = sc["internal"]
        out.append(f"| {sc['no']} | {sc['title']} | {sc['qty_display']} | {_m(sc['amount'])} | "
                   f"{_m(i['cost_total'])} | {i['margin_pct']:.0f}% |")
    out.append(f"| | **Subtotal** | | **{_m(tot['subtotal'])}** | **{_m(it['direct_cost'])}** | "
               f"**{it['gross_margin_pct']:.0f}%** |")
    out.append("")
    if it.get("boards"):
        out.append("**Joinery boards (wood used):** " + "; ".join(
            f"{b['description']}: {b['m2']:g} m² of parts → {b['sheets_to_buy']:g} sheets" for b in it["boards"]))
        out.append("")
    if it.get("labour"):
        out.append("**Labour:** " + "; ".join(f"{l['label']} {l['hours']:g} h" for l in it["labour"])
                   + f" — total {sum(l['hours'] for l in it['labour']):,.0f} man-hours")
        out.append("")
    pl = it.get("purchase_list", [])
    if pl:
        out.append(f"**Shopping list** (top {min(max_purchase, len(pl))} of {len(pl)} by cost):")
        out.append("")
        out.append("| Material | Buy | Cost |")
        out.append("|---|---|---:|")
        for p in sorted(pl, key=lambda x: -x["cost"])[:max_purchase]:
            buy = f"{p['qty_to_buy']:g} {p['unit']}" + (f" ({p['pack_note']})" if p.get("pack_note") else "")
            flag = " ⚠︎" if p.get("placeholder") else ""
            out.append(f"| {p['description']}{flag} | {buy} | {_m(p['cost'])} |")
        out.append("")
    if it.get("warnings"):
        out.append("**Check before sending:**")
        for w in it["warnings"]:
            out.append(f"- {w}")
        out.append("")
    if it.get("assumptions"):
        out.append("**Assumptions:**")
        for a in it["assumptions"]:
            out.append(f"- {a}")
        out.append("")
    ph = it.get("placeholders_used", [])
    if ph:
        out.append(f"**Placeholder rates used ({len(ph)})** — market defaults, not your prices yet: "
                   + ", ".join(f"`{p}`" for p in ph[:25]) + (" …" if len(ph) > 25 else ""))
        out.append("")
    if files:
        out.append("**Files:** " + " · ".join(f"{k}: `{v}`" for k, v in files.items()))
    return "\n".join(out).rstrip() + "\n"
