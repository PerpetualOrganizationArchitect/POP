# Security Policy

The Perpetual Organization Protocol (POP) is a production smart-contract system used by real organizations with real treasuries. Responsible disclosure is essential. Please follow the process below before any public discussion of a vulnerability.

## Reporting a Vulnerability

**Email [hudson@poa.community](mailto:hudson@poa.community)** with the subject line `[POP SECURITY]` and a clear description of the issue. If you would prefer encrypted communication, request a PGP key in your initial email and we will provide one.

In your report, please include:

- Affected contract(s) and file path(s) under [`src/`](src) (and the commit SHA you tested against).
- A reproduction or proof-of-concept (Foundry test preferred), or, if PoC is impractical, a detailed walkthrough of the attack steps.
- The suspected impact (funds at risk, governance bypass, denial of service, etc.).
- Any relevant on-chain transactions, addresses, or organizations that demonstrate the issue.
- Whether the issue is already publicly known.

**Please do not** open a public GitHub issue, post in Discord, or discuss on social media until we have coordinated disclosure.

## What to Expect

| Stage | Target timeline |
|-------|-----------------|
| Acknowledgement of report | Within 48 hours |
| Initial triage and severity assessment | Within 5 business days |
| Fix and patched release for critical/high issues | As fast as practicable; typically within 14 days |
| Public disclosure | Coordinated with the reporter after the fix has shipped to all affected networks |

We will keep you informed throughout. If you do not receive an acknowledgement within 48 hours, please follow up; email is occasionally unreliable.

## Scope

**In scope:**

- All contracts under [`src/`](src), including [`src/libs/`](src/libs), [`src/factories/`](src/factories), [`src/crosschain/`](src/crosschain), [`src/lens/`](src/lens), [`src/cashout/`](src/cashout).
- The deployment scripts under [`script/`](script) when relevant to a privileged or production deployment path.
- Cross-chain message handling between `PoaManagerHub` and `PoaManagerSatellite`.

**Out of scope:**

- Tests in [`test/`](test), helper scripts in [`scripts/`](scripts), and the auto-generated layout snapshots under [`upgrades/`](upgrades).
- Third-party dependencies. Please report directly to the upstream project:
  - OpenZeppelin contracts → [openzeppelin-contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
  - Hats Protocol → [hats-protocol](https://github.com/hats-protocol/hats-protocol)
  - forge-std → [forge-std](https://github.com/foundry-rs/forge-std)
  - Solady → [solady](https://github.com/Vectorized/solady)
  - Hyperlane → [hyperlane-monorepo](https://github.com/hyperlane-xyz/hyperlane-monorepo)
- Issues in [poa-box/subgraph-pop](https://github.com/poa-box/subgraph-pop), [poa-box/Poa-frontend](https://github.com/poa-box/Poa-frontend), or [poa-box/poa-cli](https://github.com/poa-box/poa-cli). File those directly in the relevant repo (or use the same email if it's a coordinated cross-repo issue).
- Known-as-designed behaviors:
  - `ParticipationToken` reverts on `transfer`/`transferFrom`; non-transferability is intentional.
  - `Executor` ownership is renounced after deployment; the only authorized caller is the configured voting contract.
  - `SwitchableBeacon.renounceOwnership()` reverts; losing ownership would brick the beacon.
  - The optimizer is disabled in the default Foundry profile (see [`foundry.toml`](foundry.toml) for the rationale).

## Bug Bounty

There is currently no formal bounty program. We do recognize and credit researchers who report valid vulnerabilities, and significant findings may be eligible for a discretionary award funded from the protocol's solidarity fund. Reach out before publishing your work and we will discuss in good faith.

## Hall of Fame

Researchers who have responsibly disclosed valid vulnerabilities will be credited here (with their consent).

*No disclosures yet.*

---

For non-security questions, see [CONTRIBUTING.md](CONTRIBUTING.md) and the [community channels listed in the README](README.md#community).
