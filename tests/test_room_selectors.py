"""Room selectors in scope items: an exact room name beats a tag of the same word.

The NexaFix Scan app names rooms the way people do ('Kitchen', 'Bedroom 2'), and the engine also gives a
room tags such as 'kitchen' and 'bedroom'. `rooms: Kitchen` must mean the room called Kitchen, not every
room tagged kitchen. Group words (all, dry, wet, everything, ...) keep their meaning.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "nexa-costing"
sys.path.insert(0, str(SKILL / "scripts"))

from nexa_costing.engine import Context, run_estimate  # noqa: E402
from nexa_costing.ratebook import Ratebook  # noqa: E402
from nexa_costing.util import SpecError  # noqa: E402


@pytest.fixture()
def rates():
    return Ratebook.load(SKILL / "rates.toml")


def ctx(rates, names):
    rooms = [{"name": n, "length": 3.0, "width": 3.0} for n in names]
    return Context(rates, {"project": {"ceiling_height": 2.8}, "rooms": rooms})


def names(rooms):
    return [r.name for r in rooms]


def test_exact_name_beats_tag(rates):
    c = ctx(rates, ["Kitchen", "Kitchen 2", "Living Room"])
    assert names(c.select_rooms("Kitchen")) == ["Kitchen"]
    assert names(c.select_rooms("Kitchen 2")) == ["Kitchen 2"]


def test_bedroom_name_does_not_pull_in_bedroom_2(rates):
    c = ctx(rates, ["Bedroom", "Bedroom 2", "Living Room"])
    assert names(c.select_rooms("Bedroom")) == ["Bedroom"]


def test_tag_still_selects_all_when_no_room_has_that_exact_name(rates):
    c = ctx(rates, ["Master Bedroom", "Bedroom 2", "Living Room"])
    assert names(c.select_rooms("bedrooms")) == ["Master Bedroom", "Bedroom 2"]
    assert names(c.select_rooms("bedroom")) == ["Master Bedroom", "Bedroom 2"]


def test_group_words_keep_their_meaning_even_if_a_room_is_named_like_one(rates):
    c = ctx(rates, ["Dry", "Kitchen", "Bathroom"])
    assert set(names(c.select_rooms("dry"))) == {"Dry", "Kitchen"}
    assert set(names(c.select_rooms("all"))) == {"Dry", "Kitchen", "Bathroom"}
    assert names(c.select_rooms("wet")) == ["Bathroom"]


def test_unknown_selector_still_errors(rates):
    c = ctx(rates, ["Kitchen"])
    with pytest.raises(SpecError):
        c.select_rooms("Pantry")


def test_lists_dedupe_and_mix_names_and_tags(rates):
    c = ctx(rates, ["Kitchen", "Kitchen 2", "Bathroom"])
    assert names(c.select_rooms(["Kitchen", "wet"])) == ["Kitchen", "Bathroom"]


def test_painting_by_name_prices_only_that_room(rates):
    rooms = [{"name": "Kitchen", "length": 3, "width": 3}, {"name": "Kitchen 2", "length": 3, "width": 3}]

    def walls(selector):
        est = run_estimate({"project": {"ceiling_height": 2.8}, "rooms": rooms,
                            "scope": [{"title": "Painting", "type": "painting", "rooms": selector}]}, rates)
        return est["totals"]["subtotal"]

    one, both = walls("Kitchen"), walls(["Kitchen", "Kitchen 2"])
    assert both > one                # naming both rooms must cost more than naming one
