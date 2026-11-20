# Trust store: ca/devsecops

Put the PEM certificate of the CA that issued the Key Vault signing
certificate here (for a self-signed Key Vault certificate, the certificate
itself), for example:

```bash
az keyvault certificate download --vault-name <vault> --name devsecops-signing \
  --encoding PEM --file devsecops-signing.pem
```

`trustpolicy.json` trusts only signatures from that store whose certificate
subject matches `trustedIdentities`. Notation ignores this README.
