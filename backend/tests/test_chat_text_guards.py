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


def test_free_chat_daily_limit_defaults_to_six(monkeypatch):
    monkeypatch.delenv("FREE_CHAT_DAILY_LIMIT", raising=False)
    assert free_chat_limit() == 6

