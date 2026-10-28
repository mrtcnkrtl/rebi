"""Tıraş sonrası tahriş / batık tüy: erkek kullanıcıya tek bir Yaşam notu (bakım satırı eklemez)."""

import pytest

import flow_engine


def _flow(**kw):
    base = dict(
        concern="acne", severity_score=5, age=28, gender="male", skin_type_key="normal", stress_score=6,
        sleep_hours=7, water_intake=2, smoking=False, alcohol=False, uv_index=3, humidity=50, temperature=20,
    )
    base.update(kw)
    return flow_engine.run_flow(**base)


def _notes(result):
    return [i for i in result["routine_items"] if i.get("step_order") == 94]


@pytest.mark.parametrize(
    "after,expected",
    [("irritated", "Tıraş sonrası tahriş"), ("ingrown", "Batık tüy")],
)
def test_tiras_sorunu_olan_erkege_tek_yasam_notu(after, expected):
    notes = _notes(_flow(shaving_frequency=3, shaving_after=after))
    assert len(notes) == 1
    assert notes[0]["category"] == "Yaşam"
    assert expected in notes[0]["action"]
    assert "dermatolo" in notes[0]["usage"], "kalıcı/iltihaplı durumda uzmana yönlendirir"


def test_not_bakim_satiri_eklemez_ve_rutin_geri_kalani_degismez():
    plain = _flow()
    with_note = _flow(shaving_frequency=3, shaving_after="irritated")
    care = lambda r: [(i["time"], i["action"]) for i in r["routine_items"] if i["category"] != "Yaşam"]
    assert care(plain) == care(with_note)


@pytest.mark.parametrize(
    "kw",
    [
        dict(shaving_frequency=3, shaving_after="ok"),  # sorunsuz
        dict(shaving_frequency=0, shaving_after="irritated"),  # tıraş olmuyor
        dict(gender="female", shaving_frequency=3, shaving_after="irritated"),  # yalnız erkek
        dict(shaving_frequency=3, shaving_after=""),  # cevap yok
    ],
)
def test_diger_durumlarda_not_yok(kw):
    assert _notes(_flow(**kw)) == []


def test_baglam_ozeti_tirasi_anlatir():
    ctx = _flow(shaving_frequency=7, shaving_after="irritated")["context_summary"]
    assert "Tıraş: her gün" in ctx
    assert "kızarma/yanma" in ctx
