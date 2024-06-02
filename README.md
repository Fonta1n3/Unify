# Unify

⚠️ Currently in very early stages, likely to change significantly in the future. It is Alpha and not been tested by anyone but myself.

Nearly a [BIP78 over Nostr Payjoin](https://github.com/Kukks/BTCPayServer.BIP78/tree/nostr/BTCPayServer.BIP78.Nostr) wallet.
Unify is fully functional, however won't be compatible with BTCPayServer, it will be soon.

## Config
- Upon first launch RPC and Nostr credentials are automatically created for you (you can edit them, `rpcauth` will automatically update).
- Export the `rpcauth` (from Config) to your `bitcoin.conf`.
- Select the appropriate `rpcport` (8332 for mainnet, 18332 testnet, 38332 signet, 18443 regtest).
- Restart your node.
- Select the `rpcwallet` you'd like to use.
- Add a BIP39 mnemonic (its a hot wallet for now).

## Receive
- Granted your node credentials are correct click "Receive".
- An rpc command is sent to your node to automatically generate a new address from the specified `rpcwallet`.
- You may input a custom address.
- You may either export the QR/text format of the Payjoin invoice or send directly to another `npub` (over nostr) via the "Request" button.
- Once the sender receives your invoice they will add their input and sign the transaction, the signed psbt is then sent to you.
- Once Unify receives the signed psbt from the sender it will display the (mandatory) option to add an input and output in the Receive view.
- After adding an additional input and output Unify will sign the additional inputs, finalize the psbt and send it back to the Sender via Nostr.
- Once the Sender recieves the "Payjoin proposal" a series of checks is made on the Sender side, the psbt is finalized, a complete raw transactions is created with the option to export or broadcast it.

## Send
- Click "Send".
- Scan/paste or automatically receive an invoice via nostr.
- Select an input to pay the invoice with.
- Tap "Payjoin this utxo" to pay the invoice with the selected utxo.
- Unify then builds and signs a psbt, encrypts it and sends it to the recipient via nostr.
- The recipient will do its thing and when complete will send the "Payjoin proposal" to the sender.
- Upon recipt of the "Payjoin proposal" the UI will update and carry out a series of checks on the psbt to ensure we are not being duped into signing a transaction we shouldn't be.
- If all checks pass you will see the raw transaction in hex format with an export or broadcast button enabled.
- Tap broadcast to send the transaction.


## Limitations
- Only works with a local node.
- Native segwit inputs and outputs only.
- Must have a BIP39 signer that can sign for your inputs. 
- Tor is not currently used for nostr traffic, a VPN is recommended.

## Roadmap
- NIP44? (currently utilizes NIP4 for cross compatibility).
- Watch-only capability.
- Manual change address selection (currently Bitcoin Core will automatically add a change output if needed).
- Tor for Bitcoin Core node connection (currently `localhost` only).
- A "PSBT" tab, where the user can create a psbt by adding inputs/outputs as they wish or by uploading a PSBT.
- Output substitution.
- Traditional BIP78 endpoints? The app can create an http server.








