#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
root = Path('project/app/src/main/java/fr/lagence/control')

def replace(path, old, new):
    p = root / path
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'Bloc introuvable dans {path}: {old[:80]!r}')
    p.write_text(text.replace(old, new))

replace('MainActivity.kt',
'''        authenticate("Déverrouiller L’Agence Control") { loadAdmin() }''',
'''        authenticate(reason = "Déverrouiller L’Agence Control", onSuccess = { loadAdmin() })''')
replace('MainActivity.kt',
'''            authenticate("Session administrateur verrouillée") { loadAdmin() }''',
'''            authenticate(reason = "Session administrateur verrouillée", onSuccess = { loadAdmin() })''')

replace('bot/CampaignEngine.kt',
'''                    repository.saveDelivery(JSONObject()
                        .put("id", deliveryId).put("campaign_id", campaignId).put("user_id", userId)
                        .put("chat_id", chatId).put("status", "failed").put("error", (e.message ?: "Erreur").take(500))
                    failed++''',
'''                    repository.saveDelivery(JSONObject()
                        .put("id", deliveryId).put("campaign_id", campaignId).put("user_id", userId)
                        .put("chat_id", chatId).put("status", "failed").put("error", (e.message ?: "Erreur").take(500)))
                    failed++''')

replace('crypto/KeystoreManager.kt',
'''            val key = store.getKey(alias, null)
            val factory = when (key) {
                is SecretKey -> javax.crypto.SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                else -> KeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            }
            val ki = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo''',
'''            val key = store.getKey(alias, null) ?: throw IllegalStateException("Clé Android Keystore absente: $alias")
            val ki: KeyInfo = when (key) {
                is SecretKey -> javax.crypto.SecretKeyFactory
                    .getInstance(key.algorithm, "AndroidKeyStore")
                    .getKeySpec(key, KeyInfo::class.java) as KeyInfo
                is PrivateKey -> KeyFactory
                    .getInstance(key.algorithm, "AndroidKeyStore")
                    .getKeySpec(key, KeyInfo::class.java) as KeyInfo
                else -> throw IllegalStateException("Type de clé non pris en charge: ${key.javaClass.name}")
            }''')

replace('data/Repository.kt',
'''        val current = user(id) ?: throw IllegalArgumentException("Utilisateur introuvable")
        patch.keys().forEach { key -> current.put(key, patch.get(key)) }
        current.put("updated_at", System.currentTimeMillis())
        db.putEntity(EntityKind.USER, id.toString(), current)
        audit.append(actor, "user.update", id.toString(), JSONObject().put("fields", JSONArray(patch.keySet().toList())))''',
'''        val current = user(id) ?: throw IllegalArgumentException("Utilisateur introuvable")
        val changedFields = JSONArray()
        patch.keys().forEach { key ->
            current.put(key, patch.get(key))
            changedFields.put(key)
        }
        current.put("updated_at", System.currentTimeMillis())
        db.putEntity(EntityKind.USER, id.toString(), current)
        audit.append(actor, "user.update", id.toString(), JSONObject().put("fields", changedFields))''')

replace('data/Repository.kt',
'''            var selected: JSONObject? = null
            for (j in 0 until prices.length()) if (prices.getJSONObject(j).optString("id") == priceId) selected = prices.getJSONObject(j)
            selected = selected ?: prices.getJSONObject(0)
            val unit = selected.getLong("amount_cents")''',
'''            var selected: JSONObject? = null
            for (j in 0 until prices.length()) {
                val candidate = prices.getJSONObject(j)
                if (candidate.optString("id") == priceId) {
                    selected = candidate
                    break
                }
            }
            val selectedPrice = selected ?: prices.getJSONObject(0)
            val unit = selectedPrice.getLong("amount_cents")''')
replace('data/Repository.kt',
'''.put("price_id", selected.getString("id"))
                .put("price_label", selected.optString("label"))''',
'''.put("price_id", selectedPrice.getString("id"))
                .put("price_label", selectedPrice.optString("label"))''')

replace('data/SecureDatabase.kt',
'''                    val payload = values.optJSONObject(i) ?: continue
                    val id = payload.optString("id").ifBlank { continue }
                    putEntity(kind, id, payload)''',
'''                    val payload = values.optJSONObject(i) ?: continue
                    val id = payload.optString("id")
                    if (id.isBlank()) continue
                    putEntity(kind, id, payload)''')
PY
