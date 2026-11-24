package com.mobiwha.mobiwha

import android.content.Context
import android.provider.ContactsContract

/**
 * Reads the phone's saved contacts and marks the ones that are on WhatsApp.
 *
 * WhatsApp / WhatsApp Business add their own raw contact (account type
 * "com.whatsapp" / "com.whatsapp.w4b") to every saved contact that uses
 * WhatsApp; its SYNC1 column holds the WhatsApp id "<digits>@s.whatsapp.net",
 * which is the number in international form. Requires READ_CONTACTS.
 */
object PhoneContacts {

    /** One entry per (contact, number): name, phone, whatsapp, business. */
    fun read(context: Context): List<Map<String, Any>> {
        val resolver = context.contentResolver

        // contact id → WhatsApp numbers (international digits) per app
        val waNumbers = HashMap<Long, MutableSet<String>>()
        val waBusiness = HashSet<Long>()
        resolver.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(
                ContactsContract.RawContacts.CONTACT_ID,
                ContactsContract.RawContacts.ACCOUNT_TYPE,
                ContactsContract.RawContacts.SYNC1,
            ),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} IN (?, ?) AND ${ContactsContract.RawContacts.DELETED} = 0",
            arrayOf("com.whatsapp", "com.whatsapp.w4b"),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val contactId = c.getLong(0)
                val jid = c.getString(2) ?: continue
                if (jid.contains("@g.us")) continue // group
                val digits = jid.substringBefore('@').filter { it.isDigit() }
                if (digits.length !in 7..15) continue
                waNumbers.getOrPut(contactId) { mutableSetOf() }.add(digits)
                if (c.getString(1) == "com.whatsapp.w4b") waBusiness.add(contactId)
            }
        }

        val out = ArrayList<Map<String, Any>>()
        val seen = HashSet<String>()
        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER,
            ),
            null,
            null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} COLLATE NOCASE ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val contactId = c.getLong(0)
                val name = c.getString(1)?.trim().orEmpty()
                val raw = c.getString(2)?.trim().orEmpty()
                val e164 = c.getString(3)?.trim().orEmpty() // "+96170123456" when Android knows the country
                if (raw.isEmpty() && e164.isEmpty()) continue

                val digits = (e164.ifEmpty { raw }).filter { it.isDigit() }
                val wa = waNumbers[contactId].orEmpty()
                // Match this number to the contact's WhatsApp id (handles local formats).
                val waMatch = wa.firstOrNull { w ->
                    w == digits || (digits.length >= 7 && w.endsWith(digits.trimStart('0')))
                }
                // Prefer the WhatsApp id (always international), then E.164, then as typed.
                val phone = when {
                    waMatch != null -> "+$waMatch"
                    e164.startsWith("+") -> e164
                    else -> raw
                }
                val key = phone.filter { it.isDigit() }
                if (key.length < 7 || !seen.add(key)) continue
                out.add(
                    mapOf(
                        "name" to name,
                        "phone" to phone,
                        "whatsapp" to (waMatch != null),
                        "business" to (waMatch != null && waBusiness.contains(contactId)),
                    ),
                )
            }
        }

        // WhatsApp numbers whose phone entry didn't match (e.g. odd formats).
        resolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME),
            null, null, null,
        )?.use { c ->
            val names = HashMap<Long, String>()
            while (c.moveToNext()) names[c.getLong(0)] = c.getString(1)?.trim().orEmpty()
            for ((contactId, numbers) in waNumbers) {
                for (d in numbers) {
                    if (!seen.add(d)) continue
                    out.add(
                        mapOf(
                            "name" to (names[contactId] ?: ""),
                            "phone" to "+$d",
                            "whatsapp" to true,
                            "business" to waBusiness.contains(contactId),
                        ),
                    )
                }
            }
        }
        return out
    }
}
