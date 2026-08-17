package app.attestation.auditor;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Base64;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Arrays;

/**
 * Explicit entry point and contact-scoped result cache for the local QR attestation alpha.
 *
 * <p>The caller owns the opaque scope token. This class stores only SHA-256(scopeToken), a
 * verdict and a timestamp; it never stores the token, a contact identifier or certificate data.
 */
public final class SovereignAuditorAlpha {
    private static final String EXTRA_SCOPE_TOKEN =
            "app.attestation.auditor.extra.SCOPE_TOKEN_V1";
    private static final String STATUS_PREFERENCES =
            "sovereign_attestation_scope_status_v1";
    private static final String STATUS_SEPARATOR = ":";
    private static final int MINIMUM_SCOPE_TOKEN_BYTES = 16;
    public static final int RECOMMENDED_SCOPE_TOKEN_BYTES = 32;

    public enum Verdict {
        NONE,
        VERIFIED_BASIC,
        VERIFIED_STRONG,
        REJECTED
    }

    public record Status(Verdict verdict, long updatedAtEpochMillis) {
        public boolean isFresh(final long maximumAgeMillis) {
            if (maximumAgeMillis < 0 || verdict == Verdict.NONE || updatedAtEpochMillis <= 0) {
                return false;
            }
            final long age = System.currentTimeMillis() - updatedAtEpochMillis;
            return age >= 0 && age <= maximumAgeMillis;
        }
    }

    private SovereignAuditorAlpha() {}

    /** Returns whether the pinned Auditor code is supported by this alpha. */
    public static boolean isSupported() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU;
    }

    /** Generates an opaque token suitable for one contact scope. Persist it in the core database. */
    public static byte[] generateScopeToken() {
        final byte[] token = new byte[RECOMMENDED_SCOPE_TOKEN_BYTES];
        new SecureRandom().nextBytes(token);
        return token;
    }

    /**
     * Opens the non-exported QR activity for one opaque contact scope.
     *
     * <p>The token must be random and stable for that contact. Do not pass a contact identifier or
     * an unsalted hash of one.
     */
    public static Intent createIntent(final Context context, final byte[] scopeToken) {
        if (!isSupported()) {
            throw new UnsupportedOperationException("local attestation requires Android 13+");
        }
        final Intent intent = new Intent(context, AttestationActivity.class)
                .putExtra(EXTRA_SCOPE_TOKEN, checkedCopy(scopeToken));
        if (!(context instanceof Activity)) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        return intent;
    }

    /** Reads the cached local QR result for a scope. NONE also covers absent/corrupt entries. */
    public static Status readStatus(final Context context, final byte[] scopeToken) {
        final String encoded = preferences(context).getString(statusKey(scopeToken), null);
        if (encoded == null) {
            return new Status(Verdict.NONE, 0);
        }
        final int separator = encoded.indexOf(STATUS_SEPARATOR);
        if (separator <= 0 || separator == encoded.length() - 1) {
            return new Status(Verdict.NONE, 0);
        }
        try {
            final Verdict verdict = Verdict.valueOf(encoded.substring(0, separator));
            final long timestamp = Long.parseLong(encoded.substring(separator + 1));
            if (verdict == Verdict.NONE || timestamp <= 0) {
                return new Status(Verdict.NONE, 0);
            }
            return new Status(verdict, timestamp);
        } catch (final IllegalArgumentException e) {
            return new Status(Verdict.NONE, 0);
        }
    }

    /** Removes only the cached verdict for the supplied opaque scope. */
    public static void clearStatus(final Context context, final byte[] scopeToken) {
        preferences(context).edit().remove(statusKey(scopeToken)).apply();
    }

    static byte[] requireScopeToken(final Intent intent) {
        if (intent == null) {
            throw new IllegalArgumentException("missing launch intent");
        }
        return checkedCopy(intent.getByteArrayExtra(EXTRA_SCOPE_TOKEN));
    }

    static void writeStatus(
            final Context context, final byte[] scopeToken, final Verdict verdict) {
        if (verdict == null || verdict == Verdict.NONE) {
            throw new IllegalArgumentException("a terminal verdict is required");
        }
        final String value = verdict.name() + STATUS_SEPARATOR + System.currentTimeMillis();
        preferences(context).edit().putString(statusKey(scopeToken), value).apply();
    }

    private static SharedPreferences preferences(final Context context) {
        return context.getApplicationContext().getSharedPreferences(
                STATUS_PREFERENCES, Context.MODE_PRIVATE);
    }

    private static String statusKey(final byte[] scopeToken) {
        final byte[] digest;
        try {
            digest = MessageDigest.getInstance("SHA-256").digest(checkedCopy(scopeToken));
        } catch (final NoSuchAlgorithmException e) {
            throw new AssertionError("Android must provide SHA-256", e);
        }
        return Base64.encodeToString(
                digest, Base64.NO_WRAP | Base64.NO_PADDING | Base64.URL_SAFE);
    }

    private static byte[] checkedCopy(final byte[] scopeToken) {
        if (scopeToken == null || scopeToken.length < MINIMUM_SCOPE_TOKEN_BYTES) {
            throw new IllegalArgumentException(
                    "scopeToken must contain at least " + MINIMUM_SCOPE_TOKEN_BYTES + " bytes");
        }
        return Arrays.copyOf(scopeToken, scopeToken.length);
    }
}
