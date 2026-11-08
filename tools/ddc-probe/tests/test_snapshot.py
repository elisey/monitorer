from ddc_probe.ddc import DDCClient
from ddc_probe.snapshot import diff_snapshots, load_snapshot, save_snapshot, take_snapshot

from test_ddc import FakeDisplay


def snapshot_of(values: dict[int, int]) -> dict:
    return take_snapshot(DDCClient(FakeDisplay(values), sleep=lambda _: None))


def test_snapshot_keeps_only_supported_codes():
    snapshot = snapshot_of({0x10: 85, 0x12: 50})
    assert snapshot["values"] == {
        "0x10": {"type": 0, "max": 100, "current": 85},
        "0x12": {"type": 0, "max": 100, "current": 50},
    }
    assert snapshot["errors"] == {}


def test_snapshot_records_read_errors():
    display = FakeDisplay({0x10: 85}, corrupt_reads=1000)
    snapshot = take_snapshot(DDCClient(display, sleep=lambda _: None), codes=[0x10])
    assert snapshot["values"] == {}
    assert "0x10" in snapshot["errors"]


def test_diff_finds_changed_code():
    before = snapshot_of({0x10: 85, 0x86: 2})
    after = snapshot_of({0x10: 85, 0x86: 8})
    changes = diff_snapshots(before, after)
    assert [change.code for change in changes] == [0x86]
    assert changes[0].before["current"] == 2
    assert changes[0].after["current"] == 8


def test_diff_reports_appeared_and_disappeared_codes():
    changes = diff_snapshots(snapshot_of({0x10: 85}), snapshot_of({0xE0: 1}))
    assert [(c.code, c.before is None, c.after is None) for c in changes] == [
        (0x10, False, True),
        (0xE0, True, False),
    ]


def test_identical_snapshots_have_no_diff():
    assert diff_snapshots(snapshot_of({0x10: 85}), snapshot_of({0x10: 85})) == []


def test_snapshot_round_trips_through_file(tmp_path):
    snapshot = snapshot_of({0x10: 85})
    path = tmp_path / "snapshot.json"
    save_snapshot(snapshot, path)
    assert load_snapshot(path) == snapshot
