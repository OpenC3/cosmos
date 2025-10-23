---
title: Security Vulnerabilities
description: Known security vulnerabilities and issues
sidebar_custom_props:
  myEmoji: 🛡️
---

Below is a list of CVEs reported in COSMOS. This does not include CVEs in our dependencies - you can find those in our [Trivy scans](https://github.com/OpenC3/cosmos/actions/workflows/post_release_trivy.yml).

## Patched

| CVE                                                               | Patched Version                                                 | Affected Editions | Description                                                                                                            |
| ----------------------------------------------------------------- | --------------------------------------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [CVE-2024-43795](https://nvd.nist.gov/vuln/detail/cve-2024-43795) | [5.19.0](https://github.com/OpenC3/cosmos/releases/tag/v5.19.0) | Core only         | XSS exploit in login screen                                                                                            |
| [CVE-2024-46977](https://nvd.nist.gov/vuln/detail/cve-2024-46977) | [5.19.0](https://github.com/OpenC3/cosmos/releases/tag/v5.19.0) | Core & Enterprise | Path traversal for .txt files via LocalMode's `open_local_file` function                                               |
| [CVE-2024-47529](https://nvd.nist.gov/vuln/detail/cve-2024-47529) | [5.19.0](https://github.com/OpenC3/cosmos/releases/tag/v5.19.0) | Core only         | Plaintext storage of password in browser LocalStorage                                                                  |
| [CVE-2025-28380](https://nvd.nist.gov/vuln/detail/cve-2025-28380) | [6.0.2](https://github.com/OpenC3/cosmos/releases/tag/v6.0.2)   | Core & Enterprise | XSS exploit via crafted URLs to the Documentation Tool or via stored screens in Telemetry Viewer                       |
| [CVE-2025-28381](https://nvd.nist.gov/vuln/detail/cve-2025-28381) | [6.0.2](https://github.com/OpenC3/cosmos/releases/tag/v6.0.2)   | Core & Enterprise | Certain Docker credentials were leaked through environment variables, readable by authenticated users in Script Runner |
| [CVE-2025-28382](https://nvd.nist.gov/vuln/detail/cve-2025-28382) | [6.1.0](https://github.com/OpenC3/cosmos/releases/tag/v6.1.0)   | Core & Enterprise | Arbitrary file read/copy/delete via the Table Manager API                                                              |
| [CVE-2025-28384](https://nvd.nist.gov/vuln/detail/cve-2025-28384) | [6.1.0](https://github.com/OpenC3/cosmos/releases/tag/v6.1.0)   | Core & Enterprise | Arbitrary file read via the Script Runner API                                                                          |
| [CVE-2025-28388](https://nvd.nist.gov/vuln/detail/cve-2025-28388) | [6.0.2](https://github.com/OpenC3/cosmos/releases/tag/v6.0.2)   | Core only         | Hardcoded credentials for the service account (used by running scripts to access the API - no admin permissions)       |

## Open

| CVE                                                               | Affected Editions | Description                                        | Why is it still open?                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------------------------------- | ----------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [CVE-2025-28386](https://nvd.nist.gov/vuln/detail/cve-2025-28386) | Core & Enterprise | RCE via installing a plugin                        | **Won't fix:** this is inherent to the functionality of plugins - if plugins couldn't execute code, you couldn't customize COSMOS. Only authenticated users can load code for execution, and in Enterprise that user must have admin permissions.                                                                                                                                    |
| [CVE-2025-28389](https://nvd.nist.gov/vuln/detail/cve-2025-28389) | Core only         | API accepts plaintext passwords for authentication | **Breaking change:** some users depend on this functionality in our API. Anticipate a patch in COSMOS v7.0 ([GitHub issue](https://github.com/OpenC3/cosmos/issues/2461)). Note that exploiting this vulnerability still requires brute-forcing the password; it is just generally easier to brute force a plaintext password than a token or hash with the use of dictionary tools. |

