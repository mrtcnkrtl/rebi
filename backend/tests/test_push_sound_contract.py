"""Bildirim sesi sözleşmesi: sunucunun (FCM) kanal ve ses adları mobildekiyle birebir aynı olmalı.

Android kanalının sesi oluştuktan sonra değiştirilemez ve iOS sesi paketteki dosya adıyla çalınır; bir tarafta yazım farkı sessizce
varsayılan sese düşer. Mobilin tek kaynağı `mobile/lib/core/notification_sound.dart`'tır; burada okunup karşılaştırılır.
"""

from __future__ import annotations

import re
from pathlib import Path

import push_service

DART = Path(__file__).resolve().parents[2] / "mobile" / "lib" / "core" / "notification_sound.dart"


def _const(name: str) -> str:
    text = DART.read_text(encoding="utf-8")
    m = re.search(rf"const\s+{name}\s*=\s*'([^']+)'", text)
    assert m, f"{name} notification_sound.dart içinde bulunamadı"
    return m.group(1)


def test_channel_and_sound_names_match_the_mobile_app():
    assert push_service.ANDROID_CHANNEL_ID == _const("reminderChannelId")
    assert push_service.ANDROID_SOUND == _const("reminderSoundResource")
    assert push_service.IOS_SOUND == _const("reminderSoundFile")


def test_the_sound_files_the_names_point_to_exist_in_both_apps():
    mobile = DART.parents[2]
    assert (mobile / "android/app/src/main/res/raw" / f"{push_service.ANDROID_SOUND}.wav").is_file()
    assert (mobile / "ios/Runner" / push_service.IOS_SOUND).is_file()


def test_the_android_manifest_default_channel_is_the_new_channel():
    manifest = (DART.parents[2] / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    m = re.search(r'default_notification_channel_id"\s*android:value="([^"]+)"', manifest)
    assert m and m.group(1) == push_service.ANDROID_CHANNEL_ID
