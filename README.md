# Shiller

A marketing campaign app for crypto projects, in the spirit of Gleam, built for PulseChain. Projects create a campaign of X (Twitter) tasks, participants complete them and submit proof, and the creator approves proofs and pays out rewards.

## How it works

- **Creators** connect a wallet, pay a small USDC fee and create a campaign with at least three tasks: follow, repost, like, comment, quote, tag friends or visit a link. Extra tasks cost a little more.
- **Participants** complete the tasks through the X links and submit a proof URL.
- **Creators** review and approve proofs from their dashboard, using the campaign ID.
- A leaderboard ranks the most active campaigns.

Campaign data lives in a smart contract on PulseChain (`0x7Ccf50b57Ea24AA77e4A25e4CAC30E04Ecdef169`); campaign images are pinned to IPFS. A campaign costs 2 USDC plus 1 USDC for each task after the third, and runs for 3 days. Rewards are paid by the creator directly; the contract does not hold or send them.

## Notes for maintainers

- Everything a creator or participant types is stored on-chain and shown to other users, so `script.js` escapes it (`esc`, `safeUrl`) before putting it in the page. Keep doing that for any new template.
- The contract only adds an address to a campaign's participant list when one of its proofs is approved. The dashboard therefore also reads `ProofSubmitted` events to find proofs that are still pending.
- Image upload posts to an endpoint on the original domain. To run your own, use the server in `backend/` and point the `fetch` call in `uploadToIPFS` at it.

## What is in this repo

| Path | Purpose |
|---|---|
| `index.html`, `style.css` | The single-page front end |
| `script.js` | Front-end logic: wallet connection, contract calls, campaigns, dashboard and leaderboard |
| `contracts/Shiller.sol` | Verified source of the campaign contract (Solidity 0.8.0, optimizer on, 200 runs) |
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
