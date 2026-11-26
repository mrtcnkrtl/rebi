import rag_service as rs
from free_chat_quota import free_chat_limit


def test_strip_botty_openers_removes_leading_and_inline_hitap():
    s = "Canım benim, bunu anlıyorum. Kırmızı izler aynı şey değil canım."
    out = rs._strip_botty_openers(s)
    assert "Canım" not in out
    assert "canım" not in out.lower()


def test_strip_broad_routine_questions_removed_when_not_placement_intent():
    user_msg = "Göz altımda milia oldu, ne yapayım?"
    reply = "Şu anki cilt bakım rutinin nasıl? Rutininde neler var? Milia bazen ağır kremlerle artabilir."
    out = rs._strip_broad_routine_questions(reply, user_message=user_msg)
    assert "rutinin" not in out.lower()
    assert "milia" in out.lower()


def test_strip_broad_routine_questions_kept_when_placement_question():
    user_msg = "Niacinamide'ı rutinde nereye koyayım, sabah mı akşam mı?"
    reply = "Rutininde neler var? Niacinamide genelde sabah da akşam da olur."
    out = rs._strip_broad_routine_questions(reply, user_message=user_msg)
    # placement intent => routine question should be preserved
    assert "rutininde" in out.lower()


def test_chat_reply_keeps_two_sentences():
    text = "Birinci cümle. İkinci cümle. Üçüncü cümle. Dördüncü cümle."
    out = rs._chat_general_shape(text)
    assert out == "Birinci cümle. İkinci cümle."


def test_chat_blocks_etken_ozet_kb_dump():
    dump = (
        "Etken özet:\n"
        "- Niasinamid: tipik %2-10 (etkili ~%4); pH ~5-7; hamilelik: genelde uygun kabul (yine de doktor) [A (Güçlü RCT)]\n"
        "- C Vitamini (L-Askorbik Asit): tipik %5-20 (etkili ~%10); pH ~2.5-3.5; hamilelik: genelde uygun kabul (yine de doktor) [A (Güçlü RCT)]\n"
        "- Salisilik Asit: tipik %0.5-2; pH ~3-4; hamilelik: dikkat / genelde kaçınılır"
    )
    out = rs._chat_general_shape(dump)
    assert "Etken özet" not in out
    assert "tipik %" not in out
    assert "anlatayım" in out.lower() or "etkeni" in out.lower()


def test_looks_like_internal_kb_dump():
    assert rs._looks_like_internal_kb_dump("Etken özet:\n- X: tipik %1; pH ~3; hamilelik: genelde")
    assert not rs._looks_like_internal_kb_dump("Niasinamid genelde gözenek görünümünü yumuşatmaya yardımcı olabilir.")


def test_free_chat_daily_limit_defaults_to_six(monkeypatch):
    monkeypatch.delenv("FREE_CHAT_DAILY_LIMIT", raising=False)
    assert free_chat_limit() == 6

