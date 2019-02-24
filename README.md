# slot machine - ethereum

This repository contains smart contract code for an Ethereum slot machine. The frontend code which goes with this contract is located at my other repo: [slotmachine-frontend](https://github.com/mettinger/slotmachine-frontend).  

Both repositories are intended to be easily customizable, making it easy to design and deploy new, creative slot machines on Ethereum.

Tips and instructions for creating your custom slot machine contract:

1.  Modify THE section at the beginning of the contract marked off as "START MACHINE DEFINITION" AND "END MACHINE DEFINITION".  The essential elements to define are:
  * The number of reels on your machine: numReel
  * The maximum payout multiplier: maxMultiplier
2.  The jupyter notebook python/slotMachine.ipynb contains tools and utilities to assist in the process of creating a custom slot machine.
