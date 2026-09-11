# TakeCourt

**Put your take on trial. Community stakes BOT to Crown or Bonk. Winners split the losers' pool.**

Pari-mutuel: at trial end, whichever side staked more wins. Winning voters get their stake back + a proportional slice of the losing pool minus a 3% platform fee. Losers get nothing. Ties or zero-vote trials refund everyone.

Frontend style: **comic-book / pop-art** — halftone dot background, thick black outlines, Bangers + Rubik + Permanent Marker fonts, red/yellow/blue/pink pop palette, speech bubbles and starburst shapes.

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat test
```

## Deploy

```bash
npx hardhat run scripts/deploy.js --network botchain_testnet
npx hardhat run scripts/deploy.js --network botchain
```

Update `frontend/index.html` → `CONTRACT_ADDRESS` (and network config for mainnet).

## Contract Functions

- `fileTake(content, durationSecs)` payable — filing fee 0.005 BOT default; duration 1h–30d
- `voteCrown(id)` payable / `voteBonk(id)` payable — stake BOT for either side; cannot switch sides
- `adjudicate(id)` — anyone can call after voting ends; picks winner
- `claim(id)` — winners claim, losers get 0; ties refund everyone
- `getTake` / `getVote` / `getRecent` / `getTakesByAuthor` / `isVotingOpen` views
- Admin: `setFilingFee`, `setPlatformFeeBps` (max 10%), `setDefaultTrialDuration`, `withdrawFees`, `pause/unpause`

## Frontend

Single-file `frontend/index.html`. Hosts on Vercel/Netlify. Publish directory: `frontend`.
