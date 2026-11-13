"""Analiz isteği (`POST /generate_routine`) girdi normalleştirme: mobilin yaş/cinsiyete göre eklediği alanlar."""

import main


def _req(**kw):
    base = dict(user_id="u", full_name="Ali", age=30, gender="male", concern="acne")
    base.update(kw)
    return main.AssessmentRequest(**base)


def test_eski_istemci_tiras_alani_olmadan_gonderir():
    r = _req()
    assert r.shaving_frequency == 0
    assert r.shaving_after == ""


def test_tiras_cevabi_korunur():
    r = _req(shaving_frequency=3, shaving_after="irritated")
    assert (r.shaving_frequency, r.shaving_after) == (3, "irritated")


def test_gecersiz_tiras_degerleri_normallesir():
    r = _req(shaving_frequency=99, shaving_after="bilinmeyen")
    assert r.shaving_frequency == 7
    assert r.shaving_after == ""
    assert _req(shaving_frequency=-4).shaving_frequency == 0


def test_yas_13_100_araligina_kirpilir():
    assert _req(age=9).age == 13
    assert _req(age=130).age == 100
