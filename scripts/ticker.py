#!/usr/bin/env python3.9

import os
import argparse
from web3 import Web3, HTTPProvider
from eth_account import Account
from web3.middleware import (
    BufferedGasEstimateMiddleware,
    SignAndSendRawMiddlewareBuilder,
)

node_uri_pat = "https://{chain}.infura.io/v3/{infura_key}"
batcher_abi = [
    {
        "inputs": [],
        "name": "tick",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function",
    }
]

default_batcher_address = "0x613d088F2e5a2ED91635016483dAFa3cd47a8964"


def new_wallet_account(w3: Web3, eth_private_key):
    return new_wallet_account_list(w3, [eth_private_key])[0]


def new_wallet_account_list(w3: Web3, eth_private_keys, name=None):
    """
    Creates new eth accounts and registers them (including the private keys).
    The new accounts may have no funds.
    This function is more efficient than calling new_wallet_account() many times
    as it creates only one middleware layer.
    """
    accounts = [Account.from_key(eth_private_key) for eth_private_key in eth_private_keys]
    # accepts a single key/account or a list/tuple/set of them
    signing_middleware = SignAndSendRawMiddlewareBuilder.build(accounts)
    w3.middleware_onion.add(signing_middleware, name=name)

    # default middleware name "gas_estimate" is still valid
    w3.middleware_onion.remove("gas_estimate")
    w3.middleware_onion.add(BufferedGasEstimateMiddleware, name="gas_estimate")
    return [account.address for account in accounts]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Collect pending withdrawals waiting for l1_recipient"
    )
    parser.add_argument(
        "--chain",
        type=str,
        choices=["mainnet", "sepolia"],
        default="mainnet",
        help="Select Ethereum chain (default: mainnet)",
    )
    parser.add_argument(
        "--batcher_contract",
        type=str,
        default=default_batcher_address,
        help="L1 withdrawal batching contract",
    )
    args = parser.parse_args()
    args.batcher_contract = Web3.to_checksum_address(args.batcher_contract)
    return args


def main():
    args = parse_args()
    account = Account.from_key(os.environ["PK"])
    node_uri = node_uri_pat.format(chain=args.chain, infura_key=os.environ["INFURA_KEY"])
    w3 = Web3(HTTPProvider(node_uri))

    assert w3.is_connected()
    w3.eth.default_account = new_wallet_account(w3, account.key)
    batcher = w3.eth.contract(address=args.batcher_contract, abi=batcher_abi)
    print(w3.eth.default_account, batcher.address)

    pending_funds = batcher.functions.tick().call()
    if pending_funds:
        print(f"Awaiting {pending_funds//10**6} withdrawal waiting.")
        th = batcher.functions.tick().transact()
        print(f"Pending withdrawal collected, tx hash: {th.hex()}")
    else:
        print("nothing to tick")


if __name__ == "__main__":
    main()
