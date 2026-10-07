# Shiller

A marketing campaign app for crypto projects, in the spirit of Gleam, built for PulseChain. Projects create a campaign of X (Twitter) tasks, participants complete them and submit proof, and the creator approves proofs and pays out rewards.

## How it works

- **Creators** connect a wallet, pay a small USDC fee and create a campaign with at least three tasks: follow, repost, like, comment, quote, tag friends or visit a link. Extra tasks cost a little more.
- **Participants** complete the tasks through the X links and submit a proof URL.
- **Creators** review and approve proofs from their dashboard, using the campaign ID.
- A leaderboard ranks the most active campaigns.

Campaign data lives in a smart contract; campaign images are pinned to IPFS.

## What is in this repo

| Path | Purpose |
|---|---|
| `index.html`, `style.css` | The single-page front end |
| `script.min.js` | Front-end logic: wallet connection, contract calls, campaigns, dashboard and leaderboard |
| `shiller-abi.js` | Placeholder for the contract ABI |
| `images/` | Icons |
| `backend/` | Small Express server that uploads campaign images to IPFS through Pinata |

## Run locally

Front end:

```bash
npx serve -s . -p 3000
```

Backend (image uploads):

```bash
cd backend
npm install
cp .env.example .env
npm start
```

Fill in `backend/.env` with your own [Pinata](https://www.pinata.cloud/) key, secret and gateway. The server listens on port 3001 and exposes `POST /api/upload-to-ipfs` (images only, 5 MB limit).

## Status

Built in 2025 as a working prototype. Not actively maintained.
