#!/usr/bin/bash
set -euo pipefail

SMTP_AUTH_USER="${SMTP_AUTH_USER:-}"
SMTP_AUTH_PASS="${SMTP_AUTH_PASS:-}"
MAILNAME_VALUE="${MAILNAME:-}"

if [[ -z "$SMTP_AUTH_USER" || -z "$SMTP_AUTH_PASS" ]]; then
  echo "[postfix-auth-init] SMTP_AUTH_USER/SMTP_AUTH_PASS not set; refusing to start because ZITADEL requires AUTH." >&2
  exit 1
fi

# Ensure SASL group exists and postfix can read /etc/sasldb2
if ! getent group sasl >/dev/null 2>&1; then
  groupadd -r sasl
fi

if id postfix >/dev/null 2>&1; then
  usermod -a -G sasl postfix || true
fi

# Create /etc/sasldb2 with our user
# Realm matters depending on client; we set it to MAILNAME when provided.
REALM_ARGS=()
if [[ -n "$MAILNAME_VALUE" ]]; then
  REALM_ARGS=(-u "$MAILNAME_VALUE")
fi

echo "$SMTP_AUTH_PASS" | saslpasswd2 -p -c "${REALM_ARGS[@]}" "$SMTP_AUTH_USER"
chown root:sasl /etc/sasldb2
chmod 640 /etc/sasldb2

# Enable SMTP AUTH in postfix and require it for relaying
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_type = cyrus'
postconf -e 'smtpd_sasl_path = smtpd'
postconf -e 'smtpd_sasl_security_options = noanonymous'
postconf -e 'broken_sasl_auth_clients = yes'

# Allow AUTH even without TLS (only inside docker network). If you want to enforce TLS, set this to yes and use port 587.
postconf -e 'smtpd_tls_auth_only = no'

# Do not allow bypass via mynetworks; only loopback is trusted.
postconf -e 'mynetworks = 127.0.0.0/8 [::1]/128'

# Only SASL-authenticated clients may relay to non-local domains
postconf -e 'smtpd_relay_restrictions = permit_sasl_authenticated, defer_unauth_destination'

exec /dinit
