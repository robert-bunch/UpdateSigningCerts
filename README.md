# UpdateSigningCerts
This script can be used to ensure that the ADFS Signing Certificates are updated on the Azure AD side of the federated trust, in cases where AutoCertificateRollover is disabled.

# Syntax
.\UpdateSigningCert.pst -stsFQDN *ADFSFQDN*
