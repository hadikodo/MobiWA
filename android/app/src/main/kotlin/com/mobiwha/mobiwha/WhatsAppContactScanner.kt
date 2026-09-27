package com.mobiwha.mobiwha

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract

/**
 * Scans Android's ContactsContract for phone numbers that WhatsApp knows about
 * (i.e. numbers that have chatted with the user) but that are NOT saved in the
 * user's device contacts.
 *
 * How it works:
 * 1. Query RawContacts with account_type = "com.whatsapp" to get all WhatsApp-
 *    known numbers (SYNC1 stores the phone in jid format: "961XXXXXXXX@s.whatsapp.net").
 * 2. Query regular device contacts (non-WhatsApp accounts) to build a set of
 *    saved phone numbers.
 * 3. Subtract saved from WhatsApp-known → unsaved numbers.
 *
 * Requires READ_CONTACTS permission (already declared in AndroidManifest).
 */
object WhatsAppContactScanner {

    data class ScannedContact(
        val phoneNumber: String,        // e.g. "+961XXXXXXXX"
        val whatsappDisplayName: String, // name WhatsApp has, if any
    )

    /**
     * Returns a list of phone numbers that exist in WhatsApp's sync adapter
     * but are NOT saved in the user's device contacts.
     */
    fun getUnsavedWhatsAppContacts(context: Context): List<ScannedContact> {
        val whatsappContacts = getWhatsAppRawContacts(context)
        val savedNumbers = getSavedDeviceNumbers(context)

        return whatsappContacts.filter { contact ->
            val digits = digitsOnly(contact.phoneNumber)
            // Check none of the saved numbers match (compare trailing digits
            // to handle country-code variations)
            savedNumbers.none { saved -> numbersMatch(digits, saved) }
        }
    }

    /**
     * Returns ALL phone numbers WhatsApp has synced, regardless of saved status.
     */
    fun getAllWhatsAppContacts(context: Context): List<ScannedContact> {
        return getWhatsAppRawContacts(context)
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    private fun getWhatsAppRawContacts(context: Context): List<ScannedContact> {
        val results = mutableListOf<ScannedContact>()
        val seenNumbers = mutableSetOf<String>()

        // WhatsApp uses account types "com.whatsapp" and "com.whatsapp.w4b" (Business)
        for (accountType in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            var cursor: Cursor? = null
            try {
                cursor = context.contentResolver.query(
                    ContactsContract.RawContacts.CONTENT_URI,
                    arrayOf(
                        ContactsContract.RawContacts._ID,
                        ContactsContract.RawContacts.SYNC1,       // jid: "961xxx@s.whatsapp.net"
                        ContactsContract.RawContacts.SYNC2,       // display name in WhatsApp
                        ContactsContract.RawContacts.DISPLAY_NAME_PRIMARY,
                    ),
                    "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
                    arrayOf(accountType),
                    null,
                )

                if (cursor != null) {
                    val idxSync1 = cursor.getColumnIndex(ContactsContract.RawContacts.SYNC1)
                    val idxSync2 = cursor.getColumnIndex(ContactsContract.RawContacts.SYNC2)
                    val idxName = cursor.getColumnIndex(ContactsContract.RawContacts.DISPLAY_NAME_PRIMARY)

                    while (cursor.moveToNext()) {
                        val jid = if (idxSync1 >= 0) cursor.getString(idxSync1) else null
                        val phone = jidToPhone(jid) ?: continue
                        val digits = digitsOnly(phone)

                        if (digits.length < 7 || digits.length > 15) continue
                        if (!seenNumbers.add(digits)) continue

                        val displayName = (if (idxSync2 >= 0) cursor.getString(idxSync2) else null)
                            ?: (if (idxName >= 0) cursor.getString(idxName) else null)
                            ?: ""

                        results.add(ScannedContact(phoneNumber = "+$digits", whatsappDisplayName = displayName))
                    }
                }
            } catch (_: Exception) {
                // Permission denied or provider unavailable — skip silently
            } finally {
                cursor?.close()
            }
        }

        return results
    }

    private fun getSavedDeviceNumbers(context: Context): Set<String> {
        val numbers = mutableSetOf<String>()
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                null,
                null,
                null,
            )
            if (cursor != null) {
                val idxNumber = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (cursor.moveToNext()) {
                    val raw = if (idxNumber >= 0) cursor.getString(idxNumber) else null
                    if (raw != null) {
                        val digits = digitsOnly(raw)
                        if (digits.length >= 7) numbers.add(digits)
                    }
                }
            }
        } catch (_: Exception) {
            // Permission denied or provider unavailable
        } finally {
            cursor?.close()
        }
        return numbers
    }

    /**
     * Converts a WhatsApp JID ("961XXXXXXXX@s.whatsapp.net") to a phone number ("+961XXXXXXXX").
     * Returns null for group JIDs or malformed data.
     */
    private fun jidToPhone(jid: String?): String? {
        if (jid.isNullOrBlank()) return null
        // Group chats have "@g.us", skip them
        if (jid.contains("@g.us")) return null
        val numPart = jid.substringBefore("@").trim()
        val digits = digitsOnly(numPart)
        return if (digits.length in 7..15) "+$digits" else null
    }

    private fun digitsOnly(input: String): String = input.replace(Regex("[^\\d]"), "")

    /**
     * Compares two digit-only phone strings. Handles the common case where one
     * has a country code and the other doesn't by comparing the trailing digits
     * if one is shorter (min 7 digits to avoid false matches).
     */
    private fun numbersMatch(a: String, b: String): Boolean {
        if (a == b) return true
        if (a.length < 7 || b.length < 7) return false

        val shorter = if (a.length <= b.length) a else b
        val longer = if (a.length > b.length) a else b

        // Only consider a match if the shorter number is at least 7 digits
        // and the longer number ends with it
        return shorter.length >= 7 && longer.endsWith(shorter)
    }
}
