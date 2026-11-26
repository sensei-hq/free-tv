"""Catalog JSON: per-channel facets plus run stats for apps and debugging."""
from datetime import datetime, timezone


def build_catalog(entries, probes, tracker, epg_urls):
    channels = []
    online = 0
    quarantined = 0
    for entry in entries:
        probe = probes.get(entry.url)
        status = probe.status if probe else "unchecked"
        reason = probe.reason if probe else ""
        if probe is not None:
            state = tracker.update(entry.url, status, reason, entry.name)
        else:
            state = tracker.entries.get(entry.url)
        is_quarantined = bool(state and state.quarantined)
        quarantined += 1 if is_quarantined else 0
        online += 1 if status == "online" else 0
        channels.append({
            "name": entry.name,
            "url": entry.url,
            "logo": entry.logo,
            "tvg_id": entry.tvg_id,
            "category": entry.group or entry.category or "Unsorted",
            "country": entry.country,
            "sources": entry.sources,
            "status": status,
            "quarantined": is_quarantined,
        })
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(
            timespec="seconds"),
        "epg_urls": epg_urls,
        "stats": {
            "total": len(entries),
            "online": online,
            "quarantined": quarantined,
        },
        "channels": channels,
    }
