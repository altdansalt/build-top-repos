#!/bin/sh
# Black-box smoke: verify version + key noarch module imports.
# XX-Net is a proxy daemon with no CLI --version flag; we read version.txt
# and exercise the bundled noarch library (utils, xlog, dnslib) that every
# component of the proxy depends on.  $PROJECT = restored build tree.
set -e

# Show version
VERSION=$(cat "$PROJECT/code/default/version.txt")
echo "XX-Net version: $VERSION"

# Verify Python deps installed and key noarch modules importable + functional
"$PROJECT/.venv/bin/python3" - <<'EOF'
import sys, os
noarch = os.path.join(os.environ['PROJECT'], 'code', 'default', 'lib', 'noarch')
sys.path.insert(0, noarch)

import utils
from dnslib.dns import DNSRecord, DNSHeader, QTYPE
import xlog

# IP validation exercises a core utility used throughout the proxy
assert utils.check_ip_valid4('1.2.3.4') == 1,  "valid IPv4 should return 1"
assert utils.check_ip_valid4('999.0.0.1') == 0, "invalid IPv4 should return 0"
assert utils.check_ip_valid4('bat-bing-com.a-0001.a-msedge.net.') == 0, "hostname should return 0"

# Verify is_private_ip is accessible
assert utils.is_private_ip('192.168.1.1'), "192.168.1.1 should be private"
assert not utils.is_private_ip('8.8.8.8'),  "8.8.8.8 should not be private"

# Build a DNS question record to exercise dnslib
q = DNSRecord(header=DNSHeader(id=1234))
print("dnslib DNSRecord id:", q.header.id)

print("XX-NET noarch imports OK")
EOF

echo XXNET_SMOKE_OK
