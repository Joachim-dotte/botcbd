package org.example.sovereign.attestation.smoke;

import android.app.Activity;
import android.os.Bundle;
import android.util.Base64;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import app.attestation.auditor.SovereignAuditorAlpha;

public final class MainActivity extends Activity {
    private static final String TOKEN_PREFERENCES = "smoke_scope_token_v1";
    private static final String TOKEN_KEY = "opaque_token";

    private byte[] scopeToken;
    private TextView status;

    @Override
    protected void onCreate(final Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        scopeToken = getOrCreateScopeToken();

        final int padding = Math.round(24 * getResources().getDisplayMetrics().density);
        final LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);
        layout.setPadding(padding, padding, padding, padding);

        final TextView warning = new TextView(this);
        warning.setText(
                "Local QR attestation alpha. This smoke test uses one opaque demo scope. " +
                "It is not bound to a SimpleX ratchet or security code.");
        warning.setTextSize(18);
        warning.setGravity(Gravity.CENTER);

        final Button open = new Button(this);
        open.setText("Open local attestation");
        open.setEnabled(SovereignAuditorAlpha.isSupported());
        open.setOnClickListener(view ->
                startActivity(SovereignAuditorAlpha.createIntent(this, scopeToken)));

        status = new TextView(this);
        status.setGravity(Gravity.CENTER);

        final Button clear = new Button(this);
        clear.setText("Clear demo status");
        clear.setOnClickListener(view -> {
            SovereignAuditorAlpha.clearStatus(this, scopeToken);
            refreshStatus();
        });

        layout.addView(warning);
        layout.addView(open);
        layout.addView(status);
        layout.addView(clear);
        setContentView(layout);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatus();
    }

    private void refreshStatus() {
        if (status == null) {
            return;
        }
        final SovereignAuditorAlpha.Status current =
                SovereignAuditorAlpha.readStatus(this, scopeToken);
        status.setText("Cached scope result: " + current.verdict() +
                "\nUpdated: " + current.updatedAtEpochMillis());
    }

    private byte[] getOrCreateScopeToken() {
        final String encoded = getSharedPreferences(TOKEN_PREFERENCES, MODE_PRIVATE)
                .getString(TOKEN_KEY, null);
        if (encoded != null) {
            try {
                final byte[] decoded = Base64.decode(encoded, Base64.NO_WRAP | Base64.NO_PADDING);
                if (decoded.length >= SovereignAuditorAlpha.RECOMMENDED_SCOPE_TOKEN_BYTES) {
                    return decoded;
                }
            } catch (final IllegalArgumentException ignored) {
                // Replace a corrupt demo token below.
            }
        }
        final byte[] generated = SovereignAuditorAlpha.generateScopeToken();
        getSharedPreferences(TOKEN_PREFERENCES, MODE_PRIVATE).edit()
                .putString(TOKEN_KEY,
                        Base64.encodeToString(generated, Base64.NO_WRAP | Base64.NO_PADDING))
                .apply();
        return generated;
    }
}
