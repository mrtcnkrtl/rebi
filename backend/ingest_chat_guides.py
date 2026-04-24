"""
Chat-only SSS rehberlerini knowledge store'a (knowledge_documents / knowledge_chunks) ingest eder.

- Routine/Analysis knowledge_base tablosuna DOKUNMAZ.
- Hedef folder: slug=chat-guides
"""

from pathlib import Path

from config import KNOWLEDGE_CATALOG_USER_ID, get_logger
from knowledge.ingest import ingest_directory

log = get_logger("ingest_chat_guides")


def main() -> None:
    root = Path(__file__).resolve().parent / "chat-documents"
    if not root.is_dir():
        raise SystemExit(f"Missing dir: {root}")

    uid = (KNOWLEDGE_CATALOG_USER_ID or "").strip() or "00000000-0000-4000-8000-000000000001"
    log.info("Ingest chat guides from %s (user=%s)", root, uid)

    result = ingest_directory(
        user_id=uid,
        folder_slug="chat-guides",
        folder_title="Chat Guides (FAQ)",
        root_dir=root,
        store_raw_text=False,
        skip_existing=False,
        replace_existing=True,
    )
    log.info("Done: %s", result)
    print(result)


if __name__ == "__main__":
    main()

