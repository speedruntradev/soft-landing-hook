# Capability checklist

Catalog digest: `a7875ce817fafd7ca4e0655e2937fa5a49b602283aa846e804732d18e6c1478e`
Selection digest: `3a0ef2146e48f619ec1d76cf056266e16dfe2252478643ea815e2a3034a0aac2`

## Known accelerators

### Custom Uniswap v4 hook

Start a canonical v4 pool whose custom hook owns the required pool behavior and fee integration.

Review route: `custom-review`

- [ ] Capability: canonical-v4-pool
- [ ] Capability: custom-hook-behavior

### Custom hook behavior

Document and test custom PoolManager callbacks without assuming any specific product category.

Review route: `custom-review`

- [ ] Capability: custom-hook-behavior

### Dynamic LP fee

Vary the pool LP fee from bounded, attributable inputs without confusing it with hook-owned fees.

Review route: `custom-review`

- [ ] Capability: dynamic-lp-fee

### Metadata, tags and disclosures

Bind public names, media, economics, affiliations and provider-specific evidence without hidden tags.

Review route: `standard-review`

- [ ] Capability: provider-disclosures
- [ ] Capability: public-metadata

### Mandatory Programmable volume fee

Specify the non-additive 0.1 percent Programmable share on executed canonical-pool volume.

Review route: `custom-review`

- [ ] Capability: claimable-platform-fee
- [ ] Capability: quote-side-volume-accounting

### Tests, evidence and threat model

Create project-specific security properties, test obligations and attributable evidence from the start.

Review route: `standard-review`

- [ ] Capability: evidence-plan
- [ ] Capability: security-properties

## Owner-defined capabilities

### Directional block congestion controller (`directional-block-congestion-controller`)

Catalog status: `unlisted`. Automatic decision: `none`. Route: `architecture-review-required`.

- [ ] Actors and assets
- [ ] Authority and trust boundary
- [ ] Value flow and conservation
- [ ] Failure, recovery and user exit
- [ ] Source, tests and attributable evidence

### Irreversible launch expiry (`irreversible-launch-expiry`)

Catalog status: `unlisted`. Automatic decision: `none`. Route: `architecture-review-required`.

- [ ] Actors and assets
- [ ] Authority and trust boundary
- [ ] Value flow and conservation
- [ ] Failure, recovery and user exit
- [ ] Source, tests and attributable evidence


An unlisted capability remains part of the project. It is never unsafe or rejected solely because this catalog lacks a label.

