import rag_service as rs


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

