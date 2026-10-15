# API sözleşmesi (mobil ↔ backend)

Bu klasördeki JSON dosyaları mobilin dayandığı uçların **gerçek yanıt örnekleridir**; iki taraf da aynı dosyalara karşı test edilir.

| Dosya | Uç |
|-------|----|
| `me_snapshot.json` | `GET /me/snapshot` |
| `today_plan.json` | `GET /today/plan` |
| `reminder_settings.json` | `GET /me/reminder-settings` |
| `me_history.json` | `GET /me/history` |
| `me_profile.json` | `GET /me/profile` |
| `daily_tracking_ingest.json` | `POST /daily_tracking/ingest` |

- **Backend** (`backend/tests/test_contract.py`): gerçek yanıt fixture'daki her anahtarı aynı JSON türüyle taşımalı. Yeni alan eklemek serbest; mobilin okuduğu bir alanı silmek ya da türünü değiştirmek testi kırar.
- **Mobil** (`mobile/test/contract_test.dart`): aynı dosyalar mobilin gerçek ayrıştırıcılarından geçer ve değerler tek tek doğrulanır (ayrıştırıcılar hoşgörülü olduğundan, alan adı değişirse ekran sessizce 0 göstermesin diye).

## Sözleşmeyi bilerek değiştirirken

```bash
cd backend
REBI_UPDATE_CONTRACT=1 python -m pytest tests/test_contract.py   # fixture'ları yeniden üretir
python -m pytest tests/test_contract.py                          # yeni şekle karşı doğrular
cd ../mobile && flutter test test/contract_test.dart             # mobil beklentilerini güncelle
```

Değişikliği `docs/MOBIL-API.md` ile birlikte güncelleyin. Fixture'lardaki tarihler üretildiği günün tarihidir; testler tarihe değil şekle ve sabit sahne değerlerine bakar.
